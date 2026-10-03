import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 书源种类：脚本（Hetu）或声明式规则（JSON）。
enum SourceKind { script, rule }

/// 一个书源条目。
class SourceEntry {
  const SourceEntry({
    required this.id,
    required this.name,
    required this.kind,
    required this.body,
    this.author = '',
    this.description = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final SourceKind kind;

  /// 脚本源码或规则 JSON。
  final String body;
  final String author;
  final String description;
  final bool enabled;

  Set<String> get capabilities {
    if (kind == SourceKind.script) {
      // 脚本自行按 task 分发，三种能力都可尝试
      return const {'search', 'detail', 'download'};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const {'search'};
      return {
        'search',
        if (decoded['detail'] != null) 'detail',
        if (decoded['download'] != null) 'download',
      };
    } catch (_) {
      return const {'search'};
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'body': body,
    'author': author,
    'description': description,
    'enabled': enabled,
  };

  static SourceEntry fromJson(Map<String, dynamic> json) => SourceEntry(
    id: '${json['id']}',
    name: '${json['name'] ?? ''}',
    kind: '${json['kind']}' == 'rule' ? SourceKind.rule : SourceKind.script,
    body: '${json['body'] ?? ''}',
    author: '${json['author'] ?? ''}',
    description: '${json['description'] ?? ''}',
    enabled: json['enabled'] != false,
  );
}

/// 书源仓储：单个 JSON 文件，位置固定、可读可改。
class SourceStore {
  SourceStore({this.root, this.fileName = 'sources.json'});

  /// 存储根目录（默认应用数据目录下的 reader/，测试可注入临时目录）。
  final Future<Directory> Function()? root;
  final String fileName;

  Future<File> _file() async {
    final base = root != null
        ? await root!()
        : Directory('${(await getApplicationSupportDirectory()).path}/reader');
    if (!base.existsSync()) await base.create(recursive: true);
    return File('${base.path}/$fileName');
  }

  Future<List<SourceEntry>> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => SourceEntry.fromJson(item.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<SourceEntry> entries) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        entries.map((e) => e.toJson()).toList(),
      ),
      flush: true,
    );
  }

  Future<List<SourceEntry>> upsert(SourceEntry entry) async {
    final entries = [...await load()];
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      entries[index] = entry;
    } else {
      entries.add(entry);
    }
    await save(entries);
    return entries;
  }

  Future<List<SourceEntry>> remove(String id) async {
    final entries = [...await load()]..removeWhere((e) => e.id == id);
    await save(entries);
    return entries;
  }
}
