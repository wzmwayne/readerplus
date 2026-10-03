import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/app_log.dart';
import '../services/plugin/script_meta.dart';
import '../services/plugin/source_store.dart';

/// 插件管理页：**所有**脚本与规则（书源在内）的查看、编辑、删除、添加。
///
/// 分组依据：格式（脚本/规则）× 脚本声明的类型（书源/清洗/其他）。
///
/// 类型来自脚本头部的 `// @script kind=...` 声明（纯 Dart 静态解析，不执行代码）：
///   - 书源（kind=source）：出现在「书源」页，可搜索/详情/下载
///   - 清洗（kind=clean）：TXT → EPUB 类脚本
///   - 其他（kind=tool）：默认值，不出现在书源页，避免被错用
class ScriptsPage extends StatefulWidget {
  const ScriptsPage({super.key, this.store, this.assetLoader});

  final SourceStore? store;

  /// 新建脚本时的模板（测试可注入）。
  final Future<String> Function(String asset)? assetLoader;

  @override
  State<ScriptsPage> createState() => _ScriptsPageState();
}

class _ScriptsPageState extends State<ScriptsPage> {
  late final SourceStore _store = widget.store ?? SourceStore();
  List<SourceEntry> _scripts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await _store.load();
    if (!mounted) return;
    setState(() {
      // 脚本与规则都归这里管理（含书源）
      _scripts = entries.toList();
      _loading = false;
    });
  }

  Future<void> _import() async {
    const group = XTypeGroup(label: '脚本或规则', extensions: ['ht', 'json']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null || !mounted) return;
    final body = await File(file.path).readAsString();
    final isRule = file.name.toLowerCase().endsWith('.json');
    final meta = ScriptMeta.parse(body);
    await _store.upsert(
      SourceEntry(
        id: 'plugin:${DateTime.now().millisecondsSinceEpoch}',
        name: meta.name ?? file.name.replaceAll(RegExp(r'\.(ht|json)$'), ''),
        format: isRule ? SourceFormat.rule : SourceFormat.script,
        body: body,
        kind: meta.kind,
        description: meta.description ?? '',
      ),
    );
    AppLog.info('script', '导入脚本：${meta.name ?? file.name}（${meta.kind.label}）');
    await _reload();
  }

  Future<void> _createFromTemplate() async {
    final loader =
        widget.assetLoader ??
        (String asset) async {
          final dir = await Directory.systemTemp.createTemp('script_tpl');
          final target = File('${dir.path}/tpl');
          await target.writeAsString(asset);
          return asset;
        };
    final template = await loader(_template);
    if (!mounted) return;
    final name = await _promptName('新建脚本', '我的脚本');
    if (name == null || !mounted) return;
    final body = template.replaceFirst(
      'kind=tool',
      'kind=tool name="$name"',
    );
    await _store.upsert(
      SourceEntry(
        id: 'script:${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        format: SourceFormat.script,
        body: body,
        kind: ScriptMeta.parse(body).kind,
      ),
    );
    await _reload();
  }

  Future<String?> _promptName(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '脚本名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(SourceEntry entry) async {
    final controller = TextEditingController(text: entry.body);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑：${entry.name}'),
        content: SizedBox(
          width: 640,
          height: 460,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              helperText: '类型由头部 // @script kind=source|clean|tool 决定',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final body = controller.text;
    final meta = ScriptMeta.parse(body);
    await _store.upsert(
      SourceEntry(
        id: entry.id,
        name: meta.name ?? entry.name,
        format: entry.format,
        body: body,
        kind: meta.kind,
        description: meta.description ?? entry.description,
        enabled: entry.enabled,
      ),
    );
    AppLog.info('script', '保存脚本：${entry.name}（类型 ${meta.kind.label}）');
    await _reload();
  }

  Future<void> _view(SourceEntry entry) async {
    final meta = ScriptMeta.parse(entry.body);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.name),
        content: SizedBox(
          width: 640,
          height: 460,
          child: SingleChildScrollView(
            child: SelectableText(
              '类型：${meta.kind.label}'
              '${meta.capabilities.isEmpty ? '' : ' · 能力 ${meta.capabilities.join('/')}'}\n\n'
              '${entry.body}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(SourceEntry entry) async {
    await _store.remove(entry.id);
    await _reload();
  }

  static const String _template = '''
// @script kind=tool
// 说明：把 kind 改成 source（书源）或 clean（清洗），或保持 tool（其他工具）。
//   kind=source 需要处理三种任务：search / detail / download
//   kind=clean  用于 TXT → EPUB
//
// 可用能力见《插件开发指南》：log/result/param/inputText/saveOutput/
// httpGet/httpPost/httpRequest/regexp/splitChapters/cleanText/epubBuild …

log('脚本已启动')
result('ok')
''';

  @override
  Widget build(BuildContext context) {
    final grouped = <ScriptKind, List<SourceEntry>>{};
    for (final script in _scripts) {
      final key = script.format == SourceFormat.rule
          ? ScriptKind.source
          : script.kind;
      grouped.putIfAbsent(key, () => []).add(script);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [
          IconButton(
            tooltip: '新建脚本（模板）',
            icon: const Icon(Icons.note_add_outlined),
            onPressed: _createFromTemplate,
          ),
          IconButton(
            tooltip: '导入 .ht 脚本',
            icon: const Icon(Icons.add),
            onPressed: _import,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (_scripts.isEmpty)
                  const ListTile(
                    title: Text('还没有脚本'),
                    subtitle: Text('用右上角按钮导入 .ht 或从模板新建'),
                  ),
                for (final kind in ScriptKind.values)
                  ...(grouped[kind]?.isNotEmpty == true
                      ? [
                          ListTile(
                            dense: true,
                            title: Text(
                              '${kind.label}（${grouped[kind]!.length}）',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          for (final script in grouped[kind]!)
                            ListTile(
                              title: Text(script.name),
                              subtitle: Text(
                                '${script.format == SourceFormat.rule ? '规则' : '脚本'}'
                                ' · ${script.capabilities.isEmpty ? '未声明能力' : script.capabilities.join('/')}'
                                '${script.description.isEmpty ? '' : ' · ${script.description}'}',
                              ),
                              onTap: () => _view(script),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: '编辑',
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _edit(script),
                                  ),
                                  IconButton(
                                    tooltip: '删除',
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    onPressed: () => _delete(script),
                                  ),
                                ],
                              ),
                            ),
                        ]
                      : const []),
              ],
            ),
    );
  }
}
