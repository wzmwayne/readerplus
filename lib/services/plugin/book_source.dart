import 'dart:convert';
import 'dart:io';

import 'plugin_runner.dart';
import 'plugin_sandbox.dart';

/// 书源搜索结果里的一项。
class SourceItem {
  const SourceItem({
    required this.id,
    required this.title,
    this.author = '',
    this.coverUrl = '',
    this.intro = '',
  });

  final String id;
  final String title;
  final String author;
  final String coverUrl;
  final String intro;

  static SourceItem? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return SourceItem(
      id: id,
      title: (json['title'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      coverUrl: (json['cover'] ?? '').toString(),
      intro: (json['intro'] ?? '').toString(),
    );
  }
}

/// 书籍详情（封面由脚本单独落盘，这里带回字节）。
class SourceDetail {
  const SourceDetail({
    required this.item,
    this.description = '',
    this.coverBytes,
    this.coverName,
  });

  final SourceItem item;
  final String description;
  final List<int>? coverBytes;
  final String? coverName;
}

/// 调用「书源脚本」完成在线搜索、取详情、按 id 下载。
///
/// 约定（详见插件开发指南的「书源脚本」一节）：
///   - search  ：params{task:search, query, page} → output/result.json {"items":[...]}
///   - detail  ：params{task:detail, book_id}     → output/result.json {..., "cover_file":"cover.jpg"}
///   - download：params{task:download, book_id}   → output/*.epub
class BookSourceService {
  BookSourceService({
    required this.runner,
    required this.jobsRoot,
    required this.auditEnabled,
  });

  final PluginRunner runner;
  final Future<Directory> Function() jobsRoot;
  final bool Function() auditEnabled;

  Future<Directory> _root() async {
    final base = await jobsRoot();
    if (!base.existsSync()) await base.create(recursive: true);
    return base;
  }

  /// 在线搜索；[script] 需声明 `search` 能力。
  Future<List<SourceItem>> search({
    required PluginScript script,
    required String query,
    int page = 1,
  }) async {
    final result = await runner.run(
      scriptSource: script.source,
      jobsRoot: await _root(),
      audit: auditEnabled(),
      params: {
        'task': 'search',
        'query': query,
        'page': page,
        ...script.params,
      },
      keepSandbox: true,
    );
    try {
      if (!result.ok) {
        throw StateError(
          result.traceback.isEmpty ? '搜索失败' : result.traceback,
        );
      }
      final payload = await _readResult(result);
      final items = <SourceItem>[];
      for (final raw in (payload['items'] as List?) ?? const []) {
        if (raw is! Map) continue;
        final item = SourceItem.fromJson(raw.cast<String, dynamic>());
        if (item != null) items.add(item);
      }
      return items;
    } finally {
      await _cleanup(result);
    }
  }

  /// 取详情（含封面）。
  Future<SourceDetail> detail({
    required PluginScript script,
    required String bookId,
  }) async {
    final result = await runner.run(
      scriptSource: script.source,
      jobsRoot: await _root(),
      audit: auditEnabled(),
      params: {'task': 'detail', 'book_id': bookId, ...script.params},
      keepSandbox: true,
    );
    try {
      if (!result.ok) {
        throw StateError(
          result.traceback.isEmpty ? '取详情失败' : result.traceback,
        );
      }
      final payload = await _readResult(result);
      final item =
          SourceItem.fromJson(payload) ??
          SourceItem(id: bookId, title: (payload['title'] ?? bookId).toString());

      List<int>? cover;
      final coverName = payload['cover_file'] as String?;
      if (coverName != null && coverName.isNotEmpty) {
        for (final file in result.outputs) {
          if (file.uri.pathSegments.last == coverName && file.existsSync()) {
            cover = await file.readAsBytes();
            break;
          }
        }
      }
      return SourceDetail(
        item: item,
        description: (payload['description'] ?? payload['intro'] ?? '')
            .toString(),
        coverBytes: cover,
        coverName: coverName,
      );
    } finally {
      await _cleanup(result);
    }
  }

  /// 按 id 下载（产物为 EPUB，交给书架导入）。
  ///
  /// 成功时**保留沙盒**，调用方导入产物后需自行删除 [PluginRunResult.sandboxPath]。
  Future<PluginRunResult> download({
    required PluginScript script,
    required String bookId,
    Map<String, dynamic> extra = const {},
  }) => _root().then(
    (root) => runner.run(
      scriptSource: script.source,
      jobsRoot: root,
      audit: auditEnabled(),
      params: {
        'task': 'download',
        'book_id': bookId,
        'output_file': 'book.epub',
        ...script.params,
        ...extra,
      },
      keepSandbox: true,
    ),
  );

  /// 读完产物后清掉保留的沙盒。
  Future<void> _cleanup(PluginRunResult result) async {
    final dir = Directory(result.sandboxPath);
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// 从产出的 result.json 读取结构化结果。
  Future<Map<String, dynamic>> _readResult(PluginRunResult result) async {
    for (final file in result.outputs) {
      if (file.uri.pathSegments.last != 'result.json') continue;
      if (!file.existsSync()) continue;
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }
    // 沙盒保留在 result.sandboxPath 下时可再找一次
    final fallback = File('${result.sandboxPath}/output/result.json');
    if (fallback.existsSync()) {
      return jsonDecode(await fallback.readAsString()) as Map<String, dynamic>;
    }
    throw StateError('脚本没有输出 result.json');
  }
}
