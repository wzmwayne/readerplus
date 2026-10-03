import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'script_meta.dart';

/// 条目格式：脚本（Hetu）或声明式规则（JSON）。
enum SourceFormat { script, rule }

/// 一个书源条目。
class SourceEntry {
  const SourceEntry({
    required this.id,
    required this.name,
    required this.format,
    required this.body,
    this.author = '',
    this.description = '',
    this.enabled = true,
    ScriptKind? kind,
  }) : kind = kind ?? ScriptKind.source;

  final String id;
  final String name;
  final SourceFormat format;

  /// 脚本类型（书源 / 清洗 / 其他）；规则固定为书源。
  final ScriptKind kind;

  /// 脚本源码或规则 JSON。
  final String body;
  final String author;
  final String description;
  final bool enabled;

  /// 是否为书源（只有 kind=source 才会出现在书源页，避免脚本被错用）。
  bool get isSource => kind == ScriptKind.source;


  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'format': format.name,
    'kind': kind.name,
    'body': body,
    'author': author,
    'description': description,
    'enabled': enabled,
  };

  static SourceEntry fromJson(Map<String, dynamic> json) {
    final body = '${json['body'] ?? ''}';
    // 不做旧版兼容：只认当前字段；旧数据请清除应用数据后重建
    final format = '${json['format']}' == 'rule'
        ? SourceFormat.rule
        : SourceFormat.script;
    // 类型以脚本内声明为准（编辑/手改后自动同步），规则固定为书源
    final declared = format == SourceFormat.script
        ? ScriptMeta.parse(body)
        : const ScriptMeta(kind: ScriptKind.source);
    return SourceEntry(
      id: '${json['id']}',
      name: '${json['name'] ?? ''}',
      format: format,
      body: body,
      author: '${json['author'] ?? ''}',
      description: '${json['description'] ?? ''}',
      enabled: json['enabled'] != false,
      kind: format == SourceFormat.rule ? ScriptKind.source : declared.kind,
    );
  }
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
