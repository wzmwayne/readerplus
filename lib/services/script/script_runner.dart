import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// 脚本 isolate 入口：静态/顶层函数，可跨 isolate 传递。
///
/// [job] 里包含 source / inputs / outputDir / params（全部可跨 isolate 传递）；
/// 闭包捕获的变量不能跨 isolate，所以这些必须以数据形式随消息走。
typedef ScriptIsolateEntry = void Function(Map<String, Object?> job, SendPort send);

/// 脚本执行结果。
class ScriptRunResult {
  const ScriptRunResult({
    required this.ok,
    this.result,
    this.error = '',
    required this.logs,
    required this.elapsed,
    required this.cancelled,
  });

  final bool ok;
  final Object? result;
  final String error;
  final List<String> logs;
  final Duration elapsed;
  final bool cancelled;
}

/// 脚本运行器：在**独立 isolate** 内执行脚本。
///
/// 因此具备 Python 方案永远给不了的两件事：
///  1. 硬超时到点直接 `Isolate.kill` ⇒ **真取消**（死循环也杀得掉，App 毫发无损）；
///  2. 脚本异常/崩溃只影响该 isolate，宿主进程不受影响。
class ScriptRunner {
  const ScriptRunner({required this.entry, this.onLog});

  /// 引擎入口（例如 `HetuScriptEngine.isolateEntry`）。
  final ScriptIsolateEntry entry;

  /// 日志实时回调（在主 isolate 收到，可直接刷界面/写日志文件）。
  final void Function(String message)? onLog;

  Future<ScriptRunResult> run(
    String source, {
    Duration timeout = const Duration(seconds: 60),
    Map<String, List<int>> inputs = const {},
    Directory? outputDir,
    Map<String, String> params = const {},
  }) async {
    final started = DateTime.now();
    final receive = ReceivePort();
    final logs = <String>[];
    final done = Completer<ScriptRunResult>();
    Isolate? isolate;

    void finish(ScriptRunResult result) {
      if (done.isCompleted) return;
      done.complete(result);
    }

    receive.listen((message) {
      if (message is String) {
        logs.add(message);
        onLog?.call(message);
        return;
      }
      if (message is Map) {
        isolate?.kill(priority: Isolate.immediate);
        isolate = null;
        receive.close();
        finish(
          ScriptRunResult(
            ok: message['ok'] == true,
            result: message['result'],
            error: '${message['error'] ?? ''}',
            logs: logs,
            elapsed: DateTime.now().difference(started),
            cancelled: false,
          ),
        );
      }
    });

    try {
      isolate = await Isolate.spawn<Map<String, Object?>>(_spawnEntry, {
        'entry': entry,
        'send': receive.sendPort,
        'job': <String, Object?>{
          'source': source,
          'inputs': inputs,
          'outputDir': outputDir?.path,
          'params': params,
        },
      });
    } catch (error) {
      receive.close();
      return ScriptRunResult(
        ok: false,
        error: '无法启动脚本 isolate：$error',
        logs: logs,
        elapsed: DateTime.now().difference(started),
        cancelled: false,
      );
    }

    final timer = Timer(timeout, () {
      isolate?.kill(priority: Isolate.immediate);
      isolate = null;
      try {
        receive.close();
      } catch (_) {}
      finish(
        ScriptRunResult(
          ok: false,
          error: '执行超时（${timeout.inSeconds}s），已强制终止',
          logs: logs,
          elapsed: DateTime.now().difference(started),
          cancelled: true,
        ),
      );
    });

    final result = await done.future;
    timer.cancel();
    return result;
  }

  static void _spawnEntry(Map<String, Object?> args) {
    final send = args['send'] as SendPort;
    final job = (args['job'] as Map).cast<String, Object?>();
    final engineEntry = args['entry'] as ScriptIsolateEntry;
    try {
      engineEntry(job, send);
    } catch (error, stack) {
      send.send({'ok': false, 'error': '$error\n$stack'});
    }
  }
}
