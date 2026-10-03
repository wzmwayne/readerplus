import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../script/hetu_engine.dart';
import '../script/script_runner.dart';
import '../source/rule_engine.dart';
import '../source/rule_source.dart';

/// 一次插件作业（脚本或声明式规则，共用同一套执行模型）。
class PluginJob {
  const PluginJob.script({
    required this.source,
    this.params = const {},
    this.inputs = const {},
    this.outputDir,
    this.timeout = const Duration(seconds: 60),
  }) : rule = null;

  const PluginJob.rule({
    required String ruleJson,
    this.params = const {},
    this.inputs = const {},
    this.outputDir,
    this.timeout = const Duration(seconds: 60),
  }) : rule = ruleJson,
       source = '';

  /// Hetu 脚本源码（脚本作业）。
  final String source;

  /// 声明式规则 JSON（规则作业）。
  final String? rule;

  final Map<String, String> params;
  final Map<String, List<int>> inputs;
  final Directory? outputDir;
  final Duration timeout;
}

/// 统一执行结果。
class PluginJobResult {
  const PluginJobResult({
    required this.ok,
    this.result,
    this.error = '',
    this.logs = const [],
    this.outputs = const [],
    this.outputDir,
  });

  final bool ok;
  final Object? result;
  final String error;
  final List<String> logs;

  /// 本次产物文件（如 EPUB）。
  final List<File> outputs;
  final Directory? outputDir;
}

/// 统一插件执行器。
///
/// 脚本与规则**共用同一个 isolate 运行器**：同样的崩溃隔离、硬超时真取消、
/// 实时日志回调；两者也都通过同一套宿主能力（HTTP/编码/正则/EPUB…）工作。
class PluginExecutor {
  const PluginExecutor();

  /// 传给 [ScriptRunner] 的隔离入口（静态，可跨 isolate 传递）。
  static void isolateEntry(Map<String, Object?> job, SendPort send) {
    final rule = job['rule'];
    if (rule is String && rule.isNotEmpty) {
      _runRule(job, rule, send);
      return;
    }
    HetuScriptEngine.isolateEntry(job, send);
  }

  Future<PluginJobResult> run(PluginJob job) async {
    final runner = ScriptRunner(entry: isolateEntry);
    final run = await runner.run(
      job.rule ?? job.source,
      timeout: job.timeout,
      // 规则作业把 JSON 放进 job['rule']：runner 传的是 source，这里用包装
      inputs: job.inputs,
      outputDir: job.outputDir,
      params: job.params,
      ruleJson: job.rule,
    );
    final outputs = <File>[];
    final dir = job.outputDir;
    if (dir != null && dir.existsSync()) {
      outputs.addAll(dir.listSync().whereType<File>());
    }
    return PluginJobResult(
      ok: run.ok,
      result: run.result,
      error: run.error,
      logs: run.logs,
      outputs: outputs,
      outputDir: dir,
    );
  }

  /// 在 isolate 内执行声明式规则：按 params.task 分发。
  static void _runRule(
    Map<String, Object?> job,
    String ruleJson,
    SendPort send,
  ) {
    final logs = <String>[];
    void log(String message) {
      logs.add(message);
      send.send(message);
    }

    Future<void> execute() async {
      final source = RuleSource.parse(ruleJson);
      if (source == null) {
        send.send({'ok': false, 'error': '规则解析失败'});
        return;
      }
      final params = ((job['params'] as Map?) ?? const {})
          .map((key, value) => MapEntry('$key', '$value'));
      final task = params['task'] ?? 'search';
      final engine = RuleEngine();
      try {
        log('规则执行：task=$task');
        switch (task) {
          case 'detail':
            final detail = await engine.detail(source, params['id'] ?? '');
            send.send({'ok': true, 'result': detail, 'error': ''});
          case 'download':
            final text = await engine.downloadText(source, params['id'] ?? '');
            send.send({
              'ok': true,
              'result': {'id': params['id'] ?? '', 'text': text},
              'error': '',
            });
          default:
            final items = await engine.search(
              source,
              params['query'] ?? '',
              page: int.tryParse(params['page'] ?? '1') ?? 1,
            );
            send.send({
              'ok': true,
              'result': {'items': items},
              'error': '',
            });
        }
      } catch (error) {
        send.send({'ok': false, 'error': '$error'});
      } finally {
        engine.dispose();
      }
    }

    execute();
  }
}

/// JSON 编解码便利（规则文件读写用）。
String encodeRule(Object? value) => const JsonEncoder.withIndent('  ')
    .convert(value);
