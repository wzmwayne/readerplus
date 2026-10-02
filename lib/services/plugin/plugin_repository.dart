import 'dart:convert';

import '../storage.dart';
import 'plugin_sandbox.dart';

/// 用户脚本仓库：脚本与元数据都存在应用私有目录的 plugins/ 下。
class PluginRepository {
  PluginRepository(this._storage);

  final Storage _storage;
  static const _prefix = 'plugins';
  static const _indexFile = '$_prefix/index.json';

  Future<List<PluginScript>> load() async {
    final raw = await _storage.readText(_indexFile);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final scripts = <PluginScript>[];
      for (final item in decoded.whereType<Map>()) {
        final meta = item.cast<String, dynamic>();
        final source = await _storage.readText(_sourcePath(meta['id'] as String));
        if (source == null) continue;
        scripts.add(PluginScript.fromJson(meta, source));
      }
      return scripts;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(PluginScript script) async {
    final scripts = await load();
    final index = scripts.indexWhere((item) => item.id == script.id);
    if (index >= 0) {
      scripts[index] = script;
    } else {
      scripts.add(script);
    }
    await _storage.writeText(_sourcePath(script.id), script.source);
    await _persist(scripts);
  }

  Future<void> delete(String id) async {
    final scripts = await load()..removeWhere((item) => item.id == id);
    await _storage.delete(_sourcePath(id));
    await _persist(scripts);
  }

  /// 导入一个 .py 脚本；[name] 缺省时从文件名或脚本首行注释推断。
  Future<PluginScript> importSource(
    String source, {
    String? name,
    PluginTask task = PluginTask.clean,
    Map<String, dynamic> params = const {},
    bool builtin = false,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final script = PluginScript(
      id: id,
      name: name ?? _guessName(source) ?? '脚本 $id',
      source: source,
      task: task,
      params: params,
      builtin: builtin,
      description: _guessDescription(source) ?? '',
    );
    await save(script);
    return script;
  }

  Future<void> _persist(List<PluginScript> scripts) async {
    await _storage.writeText(
      _indexFile,
      jsonEncode(scripts.map((script) => script.toJson()).toList()),
    );
  }

  String _sourcePath(String id) => '$_prefix/$id.py';

  String? _guessName(String source) {
    for (final line in source.split('\n').take(12)) {
      if (line.trim().startsWith('#')) {
        final text = line.replaceFirst('#', '').trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  String? _guessDescription(String source) {
    final doc = RegExp(r'"""(.*?)"""', dotAll: true).firstMatch(source);
    if (doc == null) return null;
    final text = doc.group(1)!.trim().split('\n').first.trim();
    return text.isEmpty ? null : text;
  }
}
