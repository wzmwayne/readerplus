import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../services/plugin/plugin_sandbox.dart';
import '../state/app_state.dart';
import 'plugin_run_page.dart';

/// 插件（Python 脚本）管理页：导入、启用、运行。
class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  List<PluginScript> _scripts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final scripts = await context.read<AppState>().plugins.load();
    if (!mounted) return;
    setState(() {
      _scripts = scripts;
      _loading = false;
    });
  }

  Future<void> _importFile() async {
    const group = XTypeGroup(label: 'Python 脚本', extensions: ['py']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null || !mounted) return;
    final source = await File(file.path).readAsString();
    final name = file.name.replaceAll(RegExp(r'\.py$'), '');
    if (!mounted) return;
    await context.read<AppState>().plugins.importSource(source, name: name);
    await _reload();
    if (mounted) _toast('已导入：$name');
  }

  Future<void> _importBuiltin() async {
    final source = await rootBundle.loadString(
      'python/examples/txt_cleaner.py',
    );
    if (!mounted) return;
    await context.read<AppState>().plugins.importSource(
      source,
      name: '内置示例：TXT 清洗转 EPUB',
      params: const {
        'input_file': 'raw.txt',
        'output_file': 'book.epub',
        'chapter_pattern': r'^第[一二三四五六七八九十百千0-9]+章.*$',
        'clean_rules': [
          [r'[\u200b\ufeff]', ''],
          [r'(?m)^\s*广告.*$', ''],
        ],
      },
      builtin: true,
    );
    await _reload();
    if (mounted) _toast('已导入内置示例');
  }

  Future<void> _toggle(PluginScript script, bool enabled) async {
    script.enabled = enabled;
    await context.read<AppState>().plugins.save(script);
    await _reload();
  }

  Future<void> _delete(PluginScript script) async {
    await context.read<AppState>().plugins.delete(script.id);
    await _reload();
  }

  Future<void> _run(PluginScript script) async {
    final state = context.read<AppState>();
    // clean 任务需要先选一个输入文件；source 任务由脚本参数决定输入
    File? input;
    if (script.task == PluginTask.clean) {
      const group = XTypeGroup(label: '文本文件', extensions: ['txt']);
      final picked = await openFile(acceptedTypeGroups: const [group]);
      if (picked == null) return;
      input = File(picked.path);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PluginRunPage(
          script: script,
          inputFile: input,
          audit: state.settings.scriptSandboxAudit,
        ),
      ),
    );
    await _reload();
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('脚本插件'),
        actions: [
          IconButton(
            tooltip: '导入 .py',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: _importFile,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'builtin') _importBuiltin();
              if (value == 'doc') _showDoc();
              if (value == 'audit') _toggleAudit();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'builtin', child: Text('导入内置示例')),
              const PopupMenuItem(value: 'doc', child: Text('查看插件开发指南')),
              CheckedPopupMenuItem(
                value: 'audit',
                checked: context.watch<AppState>().settings.scriptSandboxAudit,
                child: const Text('沙盒审计（禁止访问沙盒外文件）'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const ListTile(
                  dense: true,
                  title: Text('脚本在独立沙盒中运行，输入输出全部通过文件交换'),
                  subtitle: Text(
                    '清洗 TXT 的脚本请产出 EPUB 3；书源脚本请自行处理网络与签名',
                  ),
                ),
                const Divider(height: 1),
                if (_scripts.isEmpty)
                  const ListTile(
                    title: Text('还没有脚本'),
                    subtitle: Text('点右上角导入 .py，或从菜单导入内置示例'),
                  ),
                for (final script in _scripts)
                  ListTile(
                    leading: Icon(
                      script.task == PluginTask.clean
                          ? Icons.auto_fix_high_outlined
                          : Icons.cloud_download_outlined,
                    ),
                    title: Text(script.name),
                    subtitle: Text(
                      [
                        script.task.label,
                        if (script.description.isNotEmpty) script.description,
                        if (script.builtin) '内置',
                      ].join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: script.enabled,
                          onChanged: (value) => _toggle(script, value),
                        ),
                        IconButton(
                          tooltip: '运行',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () => _run(script),
                        ),
                        IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(script),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _toggleAudit() async {
    final state = context.read<AppState>();
    setState(
      () => state.settings.scriptSandboxAudit =
          !state.settings.scriptSandboxAudit,
    );
    await state.saveSettings();
    if (mounted) {
      _toast(
        state.settings.scriptSandboxAudit ? '已开启沙盒审计' : '已关闭沙盒审计（信任脚本）',
      );
    }
  }

  Future<void> _showDoc() async {
    final doc = await rootBundle.loadString('docs/插件开发指南.md');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('插件开发指南'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: Text(doc)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

/// 供其它页面复用的参数编码工具（脚本参数以 JSON 文本编辑）。
String encodeParams(Map<String, dynamic> params) =>
    const JsonEncoder.withIndent('  ').convert(params);
