import 'dart:async';
import 'dart:io';

/// 进程内 HTTP 流式服务：把 edge-tts 陆续到达的 mp3 分片实时转发给播放器。
///
/// 为什么这样做：
///   - 各端播放器（ExoPlayer / GStreamer / AVPlayer …）都支持 HTTP 流式播放，
///     因此「边合成边播」可以用同一条纯 Dart 代码路径实现，不需要任何平台分支；
///   - 配合预载缓冲，已缓冲好的句子可以立刻输出，做到毫秒级起播。
///
/// 每个句子对应一个 [_TtsSlot]：它持有已到达的字节与「有新数据/已结束」通知，
/// HTTP 处理器先把已有字节写出，再等待后续分片继续写，直到结束。
class TtsStreamServer {
  HttpServer? _server;
  final Map<String, _TtsSlot> _slots = {};
  int _seq = 0;

  Future<void> ensureStarted() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    _server = server;
    server.listen(_handle, onError: (Object _) {});
  }

  bool get isRunning => _server != null;

  /// 为一句文本创建播放槽，返回其 id。
  String createSlot() {
    final id = 's${_seq++}';
    _slots[id] = _TtsSlot();
    return id;
  }

  /// 追加一段音频分片。
  void addChunk(String id, List<int> chunk) => _slots[id]?.add(chunk);

  /// 标记该句合成结束。
  void finishSlot(String id) => _slots[id]?.finish();

  /// 重试前清空槽内已收到的分片（此时播放器尚未请求，不会打断播放）。
  void resetSlot(String id) => _slots[id]?.reset();

  /// 释放槽位（播放结束或停止朗读时调用）。
  void disposeSlot(String id) => _slots.remove(id);

  /// 该句已缓冲的字节数（用于判断能否立刻起播）。
  int bufferedBytes(String id) => _slots[id]?.bytes.length ?? 0;

  /// 播放器要访问的地址。
  Uri urlFor(String id) =>
      Uri.parse('http://127.0.0.1:${_server!.port}/tts/$id');

  Future<void> _handle(HttpRequest request) async {
    final slot = _slots[request.uri.pathSegments.last];
    final response = request.response;
    if (slot == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('audio', 'mpeg');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'none');
    // 已整句缓冲（预载命中）时给出长度，播放器可直接把它当普通音频文件播放；
    // 仍在合成中的句子才走 chunked 流式。
    final fullyBuffered = slot.isFinished && slot.bytes.isNotEmpty;
    if (fullyBuffered) {
      response.headers.contentLength = slot.bytes.length;
    } else {
      response.headers.chunkedTransferEncoding = true;
      // 关闭输出缓冲：分片一到就发出，播放器可以边收边播
      response.bufferOutput = false;
    }

    if (fullyBuffered) {
      response.add(slot.bytes);
      await response.close();
      return;
    }

    var sent = 0;
    try {
      while (true) {
        if (slot.bytes.length > sent) {
          response.add(slot.bytes.sublist(sent));
          sent = slot.bytes.length;
          await response.flush();
        }
        if (slot.isFinished && sent >= slot.bytes.length) break;
        await slot.waitForChange();
      }
    } catch (_) {
      // 播放器提前断开（换句/停止）属正常情况
    } finally {
      await response.close();
    }
  }

  Future<void> dispose() async {
    for (final slot in _slots.values) {
      slot.close();
    }
    _slots.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

class _TtsSlot {
  final List<int> bytes = [];
  final List<Completer<void>> _waiters = [];
  bool isFinished = false;

  void _signal() {
    final waiters = List<Completer<void>>.from(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void add(List<int> chunk) {
    if (isFinished) return;
    bytes.addAll(chunk);
    _signal();
  }

  void finish() {
    if (isFinished) return;
    isFinished = true;
    _signal();
  }

  /// 等待「有新分片」或「已结束」。
  Future<void> waitForChange() {
    if (isFinished) return Future<void>.value();
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void close() => finish();

  void reset() {
    bytes.clear();
    isFinished = false;
  }
}
