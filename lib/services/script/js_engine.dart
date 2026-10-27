import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'script_storage.dart';
import 'script_vm.dart';

/// 新脚本引擎的 isolate 入口（替代 Hetu）。
///
/// 协议与旧引擎保持一致，宿主侧无需改动：
///   - 日志：直接 send 字符串；
///   - 询问：send {'type':'ask', ...}，等待 replyTo 端口回答；
///   - 结束：send {'ok':true,'result':…} 或 {'ok':false,'error':…}。
///
/// 与旧引擎的差别：脚本用 JS 风味，任务信息从 tmp.read.utf8('task') 读取。
class JsScriptEngine {
  JsScriptEngine._();

  static void isolateEntry(Map<String, Object?> job, SendPort send) async {
    final source = '${job['source'] ?? ''}';
    final scriptId = '${job['id'] ?? job['scriptId'] ?? 'default'}';
    final inputs = ((job['inputs'] as Map?) ?? const {})
        .map((key, value) => MapEntry('$key', (value as List).cast<int>()));
    final params = ((job['params'] as Map?) ?? const {})
        .map((key, value) => MapEntry('$key', '$value'));
    final outputDir = job['outputDir']?.toString() ?? '';

    ScriptStorage? storage;
    try {
      final storageRoot = job['storageRoot']?.toString() ?? '';
      storage = await ScriptStorage.open(
        scriptId,
        rootProvider: storageRoot.isEmpty
            ? null
            : () async => Directory(storageRoot),
      );
      Object? result;
      final vm = ScriptVm(
        storage: storage,
        onLog: send.send,
        onResult: (value) => result = value,
      );

      // 询问：向主 isolate 发请求，等回答送到本 isolate 的临时端口
      vm.onAsk = (question, {secret = false, preset = ''}) async {
        final port = ReceivePort();
        send.send({
          'type': 'ask',
          'question': question,
          'secret': secret,
          'default': preset,
          'replyTo': port.sendPort,
        });
        try {
          final reply = await port.first.timeout(
            const Duration(minutes: 5),
            onTimeout: () => {'ok': false, 'answer': ''},
          );
          if (reply is Map && reply['ok'] == true) return '${reply['answer'] ?? ''}';
          return '';
        } finally {
          port.close();
        }
      };

      vm.injectTask(
        task: {
          'kind': '${job['kind'] ?? 'tool'}',
          'task': '${job['task'] ?? ''}',
          'params': params,
          'inputs': [
            for (final entry in inputs.entries)
              {'name': entry.key, 'size': entry.value.length},
          ],
          'outputDir': outputDir,
        },
        inputs: inputs,
      );

      final value = await vm.runAsync(source);
      send.send({
        'ok': true,
        'result': toSendable(result ?? value),
        'error': '',
      });
    } catch (error, stack) {
      send.send({'ok': false, 'error': '$error\n$stack'});
    } finally {
      // 运行结束：清空临时层（内存层随 isolate 结束自然释放）
      try {
        storage?.temp.clear();
      } catch (_) {}
    }
  }

  /// 只保留 isolate 可传递的类型。
  static Object? toSendable(Object? value) {
    if (value == null || value is num || value is String || value is bool) {
      return value;
    }
    if (value is Uint8List) return value.toList();
    if (value is List) return [for (final item in value) toSendable(item)];
    if (value is Map) {
      return {for (final entry in value.entries) '${entry.key}': toSendable(entry.value)};
    }
    return '$value';
  }
}