import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'edge_tts_client.dart';
import 'tts_audio_sink.dart';
import 'tts_stream_server.dart';

/// 合成一句文本所需的函数签名（便于注入假实现做测试）。
typedef TtsSynthesize =
    Stream<List<int>> Function({
      required String text,
      required String voice,
      String rate,
      String pitch,
    });

Stream<List<int>> _defaultSynthesize({
  required String text,
  required String voice,
  String rate = '+0%',
  String pitch = '+0Hz',
}) => EdgeTtsClient.synthesize(
  text: text,
  voice: voice,
  rate: rate,
  pitch: pitch,
);

/// 一句话在原文中的位置（用于逐句高亮）。
class SentenceSegment {
  const SentenceSegment({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final int start;
  final int end;

  bool overlaps(int from, int to) => start < to && end > from;
}

bool _isSpace(int c) => c == 32 || c == 9 || c == 10 || c == 13 || c == 0x3000;

/// 按句切分并给出每句在原文中的偏移（不改变原文，便于精确定位高亮）。
List<SentenceSegment> splitSentenceSegments(String text, {int maxLength = 120}) {
  if (text.trim().isEmpty) return const [];
  final enders = RegExp(r'[。！？!?…；;\n]');
  final raw = <SentenceSegment>[];

  var start = 0;
  for (var i = 0; i < text.length; i++) {
    if (enders.hasMatch(text[i])) {
      _addTrimmed(raw, text, start, i + 1);
      start = i + 1;
    }
  }
  _addTrimmed(raw, text, start, text.length);

  final result = <SentenceSegment>[];
  for (final segment in raw) {
    if (segment.text.length <= maxLength) {
      result.add(segment);
      continue;
    }
    var offset = segment.start;
    while (offset < segment.end) {
      var end = offset + maxLength;
      if (end >= segment.end) {
        end = segment.end;
      } else {
        var cut = -1;
        for (final mark in ['，', '、', ',', ' ']) {
          final idx = text.lastIndexOf(mark, end);
          if (idx > offset + maxLength ~/ 3) {
            cut = idx + 1;
            break;
          }
        }
        if (cut > offset) end = cut;
      }
      _addTrimmed(result, text, offset, end);
      offset = end;
    }
  }
  return result;
}

void _addTrimmed(
  List<SentenceSegment> out,
  String source,
  int from,
  int to,
) {
  var s = from;
  var e = to;
  while (s < e && _isSpace(source.codeUnitAt(s))) {
    s++;
  }
  while (e > s && _isSpace(source.codeUnitAt(e - 1))) {
    e--;
  }
  if (e <= s) return;
  out.add(SentenceSegment(text: source.substring(s, e), start: s, end: e));
}

/// 计算某段落内需要高亮的范围（相对段落文本起点）；无交集返回 null。
List<int>? highlightRangeInParagraph(
  int paragraphStart,
  int paragraphLength,
  SentenceSegment segment,
) {
  final paragraphEnd = paragraphStart + paragraphLength;
  final from = segment.start > paragraphStart ? segment.start : paragraphStart;
  final to = segment.end < paragraphEnd ? segment.end : paragraphEnd;
  if (to <= from) return null;
  return <int>[from - paragraphStart, to - paragraphStart];
}

/// 只要句子文本（等价于 [splitSentenceSegments] 的文本投影）。
List<String> splitSentences(String text, {int maxLength = 120}) =>
    splitSentenceSegments(text, maxLength: maxLength)
        .map((segment) => segment.text)
        .toList();

/// 一句朗读任务：负责把该句的音频边合成边灌进流式服务。
class _SentenceJob {
  _SentenceJob({required this.text, required this.slotId});

  final String text;
  final String slotId;

  final Completer<void> firstChunk = Completer<void>();
  Future<void>? synthesis;
  bool finished = false;
  int bytesReceived = 0;
}

/// 流式朗读控制器。
///
/// 关键设计（各端完全一致，无平台分支）：
///   1. 每句在进程内 HTTP 流式服务上开一个槽，边合成边可播；
///   2. 播放器只当普通网络流播放，因此首片一到就能起播（毫秒级）；
///   3. 预载 [preloadAhead] 句：当前句播放时，后续句子的音频已在并行合成，
///      切句时无需等待，做到句间无停顿。
class ReadAloudController extends ChangeNotifier {
  ReadAloudController({
    TtsSynthesize? synthesize,
    TtsAudioSink? sink,
    TtsStreamServer? server,
    this.preloadAhead = 3,
  }) : _synthesize = synthesize ?? _defaultSynthesize,
       _sink = sink ?? AudioPlayersSink(),
       _server = server ?? TtsStreamServer();

  final TtsSynthesize _synthesize;
  final TtsAudioSink _sink;
  final TtsStreamServer _server;

  /// 预载句数（含当前句之后的若干句）。
  final int preloadAhead;

  String voice = 'zh-CN-XiaoxiaoNeural';
  String rate = '+0%';
  String pitch = '+0Hz';

  final List<SentenceSegment> _segments = [];
  final List<_SentenceJob> _jobs = [];
  int _index = 0;
  bool _active = false;
  bool _paused = false;

  /// 一页播完时回调（用于自动翻页）。
  VoidCallback? onPageFinished;

  /// 最近一次失败原因（合成/播放），成功后清空。
  String? lastError;

  List<SentenceSegment> get segments => List.unmodifiable(_segments);
  List<String> get sentences =>
      _segments.map((segment) => segment.text).toList();
  int get index => _index;
  String get currentSentence =>
      _index >= 0 && _index < _segments.length ? _segments[_index].text : '';

  /// 当前正在朗读的句子在原文中的范围（未朗读时为 null）。
  SentenceSegment? get currentSegment =>
      isPlaying && _index >= 0 && _index < _segments.length
      ? _segments[_index]
      : null;
  bool get isActive => _active;
  bool get isPaused => _paused;
  bool get isPlaying => _active && !_paused;

  /// 已预载（合成中或已完成）的句子数，便于界面展示与自测。
  int get preloadedCount =>
      _jobs.where((j) => j.synthesis != null).length;

  Future<void> start(String text, {int at = 0}) async {
    await stop();
    _segments
      ..clear()
      ..addAll(splitSentenceSegments(text));
    _active = _segments.isNotEmpty;
    _paused = false;
    lastError = null;
    _index = at.clamp(0, math.max(0, _segments.length - 1));
    if (!_active) {
      notifyListeners();
      return;
    }
    await _server.ensureStarted();
    _jobs
      ..clear()
      ..addAll([
        for (final segment in _segments)
          _SentenceJob(text: segment.text, slotId: _server.createSlot()),
      ]);
    _pumpPreload();
    notifyListeners();
    unawaited(_playFrom(_index));
  }

  Future<void> pause() async {
    if (!_active || _paused) return;
    _paused = true;
    notifyListeners();
    await _sink.pause();
  }

  Future<void> resume() async {
    if (!_active || !_paused) return;
    _paused = false;
    notifyListeners();
    await _sink.resume();
  }

  Future<void> stop() async {
    final wasActive = _active;
    _active = false;
    _paused = false;
    _index = 0;
    _segments.clear();
    for (final job in _jobs) {
      job.finished = true;
      _server.disposeSlot(job.slotId);
    }
    _jobs.clear();
    notifyListeners();
    if (wasActive) await _sink.stop();
  }

  /// 让 [from, from + preloadAhead] 区间内的句子开始并行合成。
  void _pumpPreload() {
    for (var i = _index; i <= _index + preloadAhead && i < _jobs.length; i++) {
      final job = _jobs[i];
      job.synthesis ??= _fill(job);
    }
  }

  /// 把一句的合成分片写入流式服务；首片到达即完成 [firstChunk]。
  Future<void> _fill(_SentenceJob job) async {
    try {
      await for (final chunk in _synthesize(
        // 段落换行对合成无意义，替换为空格
        text: job.text.replaceAll('\n', ' ').trim(),
        voice: voice,
        rate: rate,
        pitch: pitch,
      )) {
        if (!_active || job.finished) return;
        if (chunk.isEmpty) continue;
        job.bytesReceived += chunk.length;
        _server.addChunk(job.slotId, chunk);
        if (!job.firstChunk.isCompleted) job.firstChunk.complete();
      }
    } catch (e) {
      lastError = '合成失败：$e';
      if (kDebugMode) debugPrint('[tts] 合成失败：$e');
      notifyListeners();
    } finally {
      _server.finishSlot(job.slotId);
      if (!job.firstChunk.isCompleted) job.firstChunk.complete();
    }
  }

  Future<void> _playFrom(int index) async {
    if (!_active || index >= _jobs.length) {
      if (_active && index >= _jobs.length) {
        _active = false;
        notifyListeners();
        onPageFinished?.call();
      }
      return;
    }
    _index = index;
    notifyListeners();
    _pumpPreload();

    final job = _jobs[index];
    // 首片一到就交给播放器，起播延迟只取决于首个分片（毫秒级）
    try {
      await job.firstChunk.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      if (!_active) return;
    } catch (_) {
      if (!_active) return;
    }
    if (!_active || job.finished) return;

    try {
      await _sink.playUrl(_server.urlFor(job.slotId).toString());
    } catch (e) {
      // 单句播放失败（空流/网络抖动）不应中断整页朗读
      if (kDebugMode) debugPrint('[tts] 播放失败：$e');
    }
    job.finished = true;
    _server.disposeSlot(job.slotId);
    if (!_active) return;
    await _playFrom(index + 1);
  }

  @override
  void dispose() {
    _active = false;
    unawaited(_sink.dispose());
    unawaited(_server.dispose());
    super.dispose();
  }
}
