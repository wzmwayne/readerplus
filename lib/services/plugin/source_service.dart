import 'dart:io';
import 'dart:typed_data';

import '../epub/epub_writer.dart';
import '../plugin/plugin_executor.dart';
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
  }) => executor.run(
    _job(entry, params: params, timeout: timeout),
    onLog: onLog,
  );

  /// 搜索：返回统一结构的条目（id/title/author/cover/intro）。
  Future<List<Map<String, String>>> search(
    SourceEntry entry,
    String query, {
    int page = 1,
    void Function(String message)? onLog,
  }) async {
    final result = await _run(entry, {
      'task': 'search',
      'query': query,
      'page': '$page',
    }, onLog: onLog);
    if (!result.ok) throw SourceFailure(result.error.isEmpty ? '搜索失败' : result.error);
    final payload = result.result;
    if (payload is! Map) return const [];
    final items = payload['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry('$key', value == null ? '' : '$value'),
          ),
        )
        .toList();
  }

  /// 详情：字段 + 简介 + 封面地址。
  Future<Map<String, String>> detail(
    SourceEntry entry,
    String id, {
    void Function(String message)? onLog,
  }) async {
    final result = await _run(entry, {'task': 'detail', 'id': id}, onLog: onLog);
    if (!result.ok) throw SourceFailure(result.error.isEmpty ? '取详情失败' : result.error);
    final payload = result.result;
    if (payload is! Map) return {'id': id};
    return payload.map(
      (key, value) => MapEntry('$key', value == null ? '' : '$value'),
    );
  }

  /// 下载：取回章节（脚本/规则都返回同构结构），并可按需生成 EPUB。
  Future<List<({String title, String body})>> downloadChapters(
    SourceEntry entry,
    String id, {
    void Function(String message)? onLog,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final result = await _run(entry, {
      'task': 'download',
      'id': id,
    }, onLog: onLog, timeout: timeout);
    if (!result.ok) throw SourceFailure(result.error.isEmpty ? '下载失败' : result.error);
    final payload = result.result;
    final chapters = <({String title, String body})>[];
    if (payload is Map) {
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
    return chapters;
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
