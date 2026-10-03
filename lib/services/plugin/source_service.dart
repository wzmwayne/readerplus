import 'dart:io';
import 'dart:typed_data';

import '../epub/epub_writer.dart';
import '../plugin/plugin_executor.dart';
import '../script/crypto_ops.dart';
import '../script/script_runner.dart';
import '../source/host_http.dart';
import 'source_store.dart';

/// 书源服务：把「脚本」与「规则」两种书源统一成 search/detail/download 三个动作。
///
/// 两者都经 [PluginExecutor]（同一个 isolate 执行器、同一套宿主能力），
/// 因此崩溃隔离、硬超时真取消、实时日志对两种书源完全一致。
/// 书源执行失败（错误信息保持单层前缀，便于界面直接展示）。
class SourceFailure implements Exception {
  const SourceFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 下载结果：章节 + 脚本可补充的作者/封面。
class DownloadResult {
  const DownloadResult({
    required this.chapters,
    this.author = '',
    this.coverUrl = '',
    this.coverData = '',
  });

  final List<({String title, String body})> chapters;

  /// 作者（脚本补充，优先于搜索结果）。
  final String author;

  /// 封面图地址（App 会抓取字节并嵌入 EPUB）。
  final String coverUrl;

  /// 封面图字节的 base64（脚本已拿到字节时用，优先于 coverUrl）。
  final String coverData;
}

class SourceService {
  const SourceService({this.executor = const PluginExecutor()});

  final PluginExecutor executor;

  PluginJob _job(
    SourceEntry entry, {
    required Map<String, String> params,
    Directory? outputDir,
    Duration timeout = const Duration(seconds: 60),
  }) => entry.format == SourceFormat.rule
      ? PluginJob.rule(
          ruleJson: entry.body,
          params: params,
          outputDir: outputDir,
          timeout: timeout,
        )
      : PluginJob.script(
          source: entry.body,
          params: params,
          outputDir: outputDir,
          timeout: timeout,
        );

  Future<PluginJobResult> _run(
    SourceEntry entry,
    Map<String, String> params, {
    void Function(String message)? onLog,
    Duration timeout = const Duration(seconds: 60),
    ScriptCancelToken? token,
    Future<AskReply> Function(AskRequest request)? onAsk,
  }) => executor.run(
    _job(entry, params: params, timeout: timeout),
    onLog: onLog,
    token: token,
    onAsk: onAsk,
  );

  /// 搜索：返回统一结构的条目（id/title/author/cover/intro/description）。
  ///
  /// 书源契约（不再有独立的"取详情"）：搜索**一次带回全部字段**，
  /// 因此点击结果即可直接展示详情；`cover` 为封面图地址（可为空）。
  Future<List<Map<String, String>>> search(
    SourceEntry entry,
    String query, {
    int page = 1,
    void Function(String message)? onLog,
    ScriptCancelToken? token,
    Future<AskReply> Function(AskRequest request)? onAsk,
  }) async {
    final result = await _run(entry, {
      'task': 'search',
      'query': query,
      'page': '$page',
    }, onLog: onLog, token: token, onAsk: onAsk);
    if (!result.ok) throw SourceFailure(result.error.isEmpty ? '搜索失败' : result.error);
    final payload = result.result;
    if (payload is! Map) return const [];
    final items = payload['items'];
    if (items is! List) return const [];
    return items.whereType<Map>().map((item) {
      final mapped = item.map(
        (key, value) => MapEntry('$key', value == null ? '' : '$value'),
      );
      // 统一保证字段齐全，方便界面直接渲染
      mapped.putIfAbsent('title', () => '');
      mapped.putIfAbsent('author', () => '');
      mapped.putIfAbsent('cover', () => '');
      // 封面三形态（优先级）：coverData(裸 base64) > cover 为 data: URI > cover 为图片地址
      mapped.putIfAbsent('coverData', () => '');
      mapped.putIfAbsent('intro', () => '');
      mapped.putIfAbsent('description', () => '');
      return mapped;
    }).toList();
  }

  /// 下载：取回章节；脚本/规则**还可补充** author / cover(URL) / coverData(base64)。
  ///
  /// 封面若是 URL，则由 App 抓取字节后嵌入 EPUB（严格 EPUB 3 的 cover-image）。
  /// **超时默认无限制**（`Duration.zero`）：下载大书允许慢慢跑，
  /// 需要时由设置项或界面「取消」控制。
  Future<DownloadResult> downloadChapters(
    SourceEntry entry,
    String id, {
    void Function(String message)? onLog,
    Duration timeout = Duration.zero,
    ScriptCancelToken? token,
    Future<AskReply> Function(AskRequest request)? onAsk,
  }) async {
    final result = await _run(entry, {
      'task': 'download',
      'id': id,
    }, onLog: onLog, timeout: timeout, token: token, onAsk: onAsk);
    if (!result.ok) throw SourceFailure(result.error.isEmpty ? '下载失败' : result.error);
    final payload = result.result;
    final chapters = <({String title, String body})>[];
    var author = '';
    var coverUrl = '';
    var coverData = '';
    if (payload is Map) {
      author = '${payload['author'] ?? ''}';
      coverUrl = '${payload['cover'] ?? ''}';
      coverData = '${payload['coverData'] ?? ''}';
      final list = payload['chapters'];
      if (list is List) {
        for (final item in list.whereType<Map>()) {
          chapters.add((
            title: '${item['title'] ?? ''}',
            body: '${item['body'] ?? ''}',
          ));
        }
      } else if (payload['text'] != null) {
        chapters.add((title: '正文', body: '${payload['text']}'));
      }
    }
    return DownloadResult(
      chapters: chapters,
      author: author,
      coverUrl: coverUrl,
      coverData: coverData,
    );
  }

  /// 取封面字节：优先 coverData(base64)，否则抓取 cover URL；失败返回 null。
  Future<List<int>?> fetchCoverBytes(
    DownloadResult result, {
    void Function(String message)? onLog,
  }) async {
    if (result.coverData.trim().isNotEmpty) {
      try {
        return CryptoOps.base64Decode(result.coverData.trim());
      } catch (error) {
        onLog?.call('封面 base64 解析失败：$error');
      }
    }
    final url = result.coverUrl.trim();
    if (url.isEmpty) return null;
    try {
      onLog?.call('下载封面：$url');
      final response = await HostHttp().get(url);
      if (!response.ok || response.bodyBytes.isEmpty) return null;
      return response.bodyBytes;
    } catch (error) {
      onLog?.call('封面下载失败（忽略）：$error');
      return null;
    }
  }

  /// 解析封面内联数据为字节；不是内联数据则返回 null。
  ///
  /// 支持三种写法：
  ///   - `data:image/jpeg;base64,XXXX`
  ///   - 裸 base64（`XXXX`）
  ///   - 空串 / 普通图片地址 ⇒ null（由界面按网络图处理）
  static List<int>? decodeInlineCover(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final comma = text.indexOf(',');
    if (text.startsWith('data:')) {
      if (comma < 0) return null;
      final meta = text.substring(0, comma).toLowerCase();
      final payload = text.substring(comma + 1).trim();
      if (meta.contains('base64')) {
        try {
          return CryptoOps.base64Decode(payload);
        } catch (_) {
          return null;
        }
      }
      // 非 base64 的 data URI（如 utf8 文本）不当作图片
      return null;
    }
    // 裸 base64：只在看起来像 base64 时尝试（避免把 URL 当 base64）
    if (text.contains('/') || text.contains(':')) return null;
    try {
      return CryptoOps.base64Decode(text);
    } catch (_) {
      return null;
    }
  }

  /// 生成 EPUB 字节（严格 EPUB 3）。
  List<int> buildEpub({
    required String title,
    String author = '佚名',
    required List<({String title, String body})> chapters,
    List<int>? cover,
    String coverName = 'cover.jpg',
  }) {
    final writer = EpubWriter(title: title, author: author);
    for (final chapter in chapters) {
      writer.addChapter(chapter.title, chapter.body);
    }
    if (cover != null && cover.isNotEmpty) {
      writer.setCover(
        Uint8List.fromList(cover),
        fileName: coverName,
      );
    }
    return writer.build();
  }
}
