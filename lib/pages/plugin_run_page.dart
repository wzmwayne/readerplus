import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/plugin/plugin_sandbox.dart';
import '../state/app_state.dart';

/// 运行一个脚本：前台显示日志（不显示进度），可随时取消，成功后导入产物。
class PluginRunPage extends StatefulWidget {
  const PluginRunPage({
    super.key,
    required this.script,
    this.inputFile,
    this.audit = true,
    this.extraParams = const {},
  });

  final PluginScript script;
  final File? inputFile;
  final bool audit;

  /// 额外参数（例如书源下载的 task / book_id），会覆盖脚本默认参数。
  final Map<String, dynamic> extraParams;

  @override
  State<PluginRunPage> createState() => _PluginRunPageState();
}

class _PluginRunPageState extends State<PluginRunPage> {
  final StringBuffer _log = StringBuffer();
  StreamSubscription<String>? _subscription;
  PluginRunResult? _result;
  bool _running = false;
  bool _imported = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    // 清理本次运行保留的沙盒（产物已导入或用户已离开）
    final directory = _sandboxToCleanup;
    if (directory != null) {
      final dir = Directory(directory);
      if (dir.existsSync()) unawaited(dir.delete(recursive: true));
    }
    super.dispose();
  }

  String? _sandboxToCleanup;

  Future<void> _run() async {
    final state = context.read<AppState>();
    final runner = state.pluginRunner;
    setState(() {
      _running = true;
      _result = null;
      _imported = false;
      _log.clear();
      _log.writeln('开始运行：${widget.script.name}');
    });
    _subscription = runner.logs.listen((chunk) {
      if (!mounted) return;
      setState(() => _log.write(chunk));
    });

    final temp = await getTemporaryDirectory();
    final jobsRoot = Directory('${temp.path}/plugin_jobs');
    if (!jobsRoot.existsSync()) await jobsRoot.create(recursive: true);

    final inputs = <String, List<int>>{};
    final params = <String, dynamic>{
      'task': widget.script.task.id,
      ...widget.script.params,
      ...widget.extraParams,
    };
    if (widget.inputFile != null) {
      final name =
          params['input_file'] as String? ??
          widget.inputFile!.uri.pathSegments.last;
      params['input_file'] = name;
      inputs[name] = await widget.inputFile!.readAsBytes();
    }

    final result = await runner.run(
      scriptSource: widget.script.source,
      jobsRoot: jobsRoot,
      audit: widget.audit,
      params: params,
      inputs: inputs,
      // 成功也保留沙盒：产物在 output/ 下，导入后再清理（否则导入时会找不到文件）
      keepSandbox: true,
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
      _sandboxToCleanup = result.sandboxPath;
      if (result.traceback.isNotEmpty) _log.writeln(result.traceback);
    });
  }

  Future<void> _cancel() async {
    context.read<AppState>().pluginRunner.cancel();
    setState(() => _log.writeln('\n已请求取消…'));
  }

  Future<void> _importOutputs() async {
    final result = _result;
    if (result == null || !result.ok) return;
    final state = context.read<AppState>();
    var imported = 0;
    for (final file in result.outputs) {
      final name = file.uri.pathSegments.last.toLowerCase();
      if (!name.endsWith('.epub') && !name.endsWith('.txt')) continue;
      try {
        await state.importBook(file);
        imported++;
      } catch (error) {
        if (mounted) setState(() => _log.writeln('导入失败：$error'));
      }
    }
    if (!mounted) return;
    setState(() => _imported = imported > 0);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已导入 $imported 本')));
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.script.name),
        actions: [
          if (_running)
            TextButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('取消'),
            ),
          if (!_running && result != null)
            TextButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.refresh),
              label: const Text('重跑'),
            ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(
              _running
                  ? Icons.hourglass_top
                  : (result?.ok ?? false)
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
            ),
            title: Text(
              _running
                  ? '运行中…'
                  : (result?.ok ?? false)
                  ? result!.summary
                  : '失败：${result?.traceback ?? ''}',
            ),
            subtitle: Text(
              [
                widget.script.task.label,
                if (widget.inputFile != null)
                  '输入 ${widget.inputFile!.uri.pathSegments.last}',
                '沙盒审计${widget.audit ? '开启' : '关闭'}',
              ].join(' · '),
            ),
          ),
          if (!_running && result != null && result.ok && result.outputs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      result.outputs
                          .map((f) => f.uri.pathSegments.last)
                          .join('、'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _imported ? null : _importOutputs,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(_imported ? '已导入' : '导入产物'),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFF101418),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  _log.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFFD7E2EA),
                  ),
                ),
              ),
            ),
          ),
          if (!_running && result != null && !result.ok)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.folder_open, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      '沙盒已保留：${result.sandboxPath}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 便于测试与调试：把脚本参数编码成可编辑 JSON。
String prettyParams(Map<String, dynamic> params) =>
    const JsonEncoder.withIndent('  ').convert(params);
