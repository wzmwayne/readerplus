import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/app_log.dart';
import '../services/plugin/script_meta.dart';
import '../services/plugin/source_store.dart';
import '../state/app_state.dart';
import 'script_consent_page.dart';

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
  /// 当前语言文案（跟随设置里的语言选项）
  L10n get l => L10n.of(context.read<AppState>().settings);

  late final SourceStore _store = widget.store ?? SourceStore();
  List<SourceEntry> _scripts = const [];
  bool _loading = true;

  /// 关闭态下不读仓储；启用后由 build 里的后置回调补一次加载。
  bool _entriesLoaded = false;

  Future<void> _reload() async {
    if (!mounted) return;
    // 脚本支持关闭时整页只有引导，不碰仓储（也不弹导入/编辑入口）
    if (context.read<AppState>().settings.scriptsEnabled != true) {
      setState(() {
        _scripts = const [];
        _loading = false;
        _entriesLoaded = false;
      });
      return;
    }
    try {
      final entries = await _store.load();
      if (!mounted) return;
      setState(() {
        // 脚本与规则都归这里管理（含书源）
        _scripts = entries.toList();
        _loading = false;
        _entriesLoaded = true;
      });
    } catch (error) {
      // 读失败也标记为"已尝试"：build 里的后置回调按此标志调度，
      // 否则每帧都会重试一次
      AppLog.error('script', '读取脚本仓储失败：$error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _entriesLoaded = true;
      });
    }
  }

  /// 「去开启」：通过闸门后刷新为正常管理页。
  Future<void> _openGate() async {
    final enabled = await ScriptConsentPage.show(context);
    if (enabled) await _reload();
  }

  Future<void> _import() async {
    // 插件页只放行脚本(.ht)与规则(.json)；MIME 里加 octet-stream
    // 是因为 .ht 是自定义后缀，Android 只会报 application/octet-stream
    const group = XTypeGroup(
      label: '脚本或规则',
      extensions: ['ht', 'json'],
      mimeTypes: ['application/json', 'text/plain', 'application/octet-stream'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null || !mounted) return;
    final name = file.name.toLowerCase();
    if (!name.endsWith('.ht') && !name.endsWith('.json')) {
      AppLog.info('script', l.scriptRejectImport);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('插件页只接受 .ht 脚本或 .json 规则')),
        );
      }
      return;
    }
    final body = await File(file.path).readAsString();
    final isRule = name.endsWith('.json');
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
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: l.scriptKindHint,
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
              '${entry.format == SourceFormat.rule ? '（规则）' : '（脚本）'}\n\n'
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

  /// 关闭态整页引导：说明现状 + 「去开启」（点击直接打开闸门）。
  Widget _lockedPage(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('插件管理')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.code_off,
                  size: 44,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(l.scriptOffTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  l.scriptOffBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _openGate, child: Text(l.goEnable)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (context.watch<AppState>().settings.scriptsEnabled != true) {
      return _lockedPage(context);
    }
    if (!_entriesLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
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
                  ListTile(
                    title: Text(l.scriptEmptyTitle),
                    subtitle: Text(l.scriptEmptySubtitle),
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
                                ' · ${script.kind.label}'
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
