import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// 脚本 isolate 入口：静态/顶层函数，可跨 isolate 传递。
///
/// [job] 里包含 source / inputs / outputDir / params（全部可跨 isolate 传递）；
/// 闭包捕获的变量不能跨 isolate，所以这些必须以数据形式随消息走。
typedef ScriptIsolateEntry = void Function(Map<String, Object?> job, SendPort send);

/// 脚本执行结果。
/// 取消令牌：可一次取消**所有**挂在它上面的运行（用于搜索页的「取消」）。
///
/// 取消即 `Isolate.kill(immediate)` —— 与超时走同一条路径，是真取消，
/// 死循环脚本也杀得掉，宿主不受影响。
class ScriptCancelToken {
  final List<void Function(String reason)> _killers = [];
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void attach(void Function(String reason) killer) {
    if (_cancelled) {
      killer('已取消');
      return;
    }
    _killers.add(killer);
  }

  void detach(void Function(String reason) killer) => _killers.remove(killer);

  /// 取消所有在跑的脚本；后续 attach 会立即被取消。
  void cancelAll([String reason = '用户取消：已强制停止脚本']) {
    _cancelled = true;
    final pending = List.of(_killers);
    _killers.clear();
    for (final killer in pending) {
      killer(reason);
    }
    if (pending.isEmpty) _cancelled = false; // 无人在跑：保持可复用
  }
}

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

/// 脚本向用户提问的内容（只有文本问答；`secret` 时输入遮挡且**回答不入日志**）。
class AskRequest {
  const AskRequest({required this.question, this.secret = false, this.default_ = ''});

  final String question;

  /// true ⇒ 秘密询问：输入框遮挡，回答不写日志。
  final bool secret;

  /// 预填文本（可选）。
  final String default_;

  @override
  String toString() => secret ? '询问（秘密）：$question' : '询问：$question';
}

/// 用户对提问的回答；`ok == false` 表示取消/超时/不可用，脚本需自行处理。
class AskReply {
  const AskReply({required this.ok, this.answer = ''});

  const AskReply.cancelled() : ok = false, answer = '';

  final bool ok;
  final String answer;
}

/// 脚本运行器：在**独立 isolate** 内执行脚本。
///
/// 因此具备 Python 方案永远给不了的两件事：
///  1. 硬超时到点直接 `Isolate.kill` ⇒ **真取消**（死循环也杀得掉，App 毫发无损）；
///  2. 脚本异常/崩溃只影响该 isolate，宿主进程不受影响。
class ScriptRunner {
  const ScriptRunner({required this.entry, this.onLog, this.onAsk});

  /// 引擎入口（例如 `HetuScriptEngine.isolateEntry`）。
  final ScriptIsolateEntry entry;

  /// 日志实时回调（在主 isolate 收到，可直接刷界面/写日志文件）。
  final void Function(String message)? onLog;

  /// 脚本提问回调（在主 isolate 收到，可弹对话框）。
  /// 为 null 时脚本的 `ask` 立即得到 `{ok:false}`（无 UI 场景）。
  final Future<AskReply> Function(AskRequest request)? onAsk;

  Future<ScriptRunResult> run(
    String source, {
    /// 运行上限：`Duration.zero`（默认以外的约定值）表示**不设上限**。
    Duration timeout = const Duration(seconds: 60),
    Map<String, List<int>> inputs = const {},
    Directory? outputDir,
    Map<String, String> params = const {},
    String? ruleJson,
    ScriptCancelToken? token,
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

    try {
      isolate = await Isolate.spawn<Map<String, Object?>>(_spawnEntry, {
        'entry': entry,
        'send': receive.sendPort,
        'job': <String, Object?>{
          'source': source,
          'rule': ruleJson,
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

    /// 立即终止：无论是超时还是用户点「取消」，都走同一条真取消路径。
    void killNow(String reason) {
      isolate?.kill(priority: Isolate.immediate);
      isolate = null;
      try {
        receive.close();
      } catch (_) {}
      finish(
        ScriptRunResult(
          ok: false,
          error: reason,
          logs: logs,
          elapsed: DateTime.now().difference(started),
          cancelled: true,
        ),
      );
    }

    token?.attach(killNow);

    // timeout 为 Duration.zero 或负数 ⇒ 不设上限（靠界面「取消」或脚本自身结束）。
    // 默认只对搜索等短任务设上限；下载默认无限制，可在设置里改。
    Timer? timer;
    void armTimeout() {
      timer?.cancel();
      if (timeout <= Duration.zero) return;
      timer = Timer(
        timeout,
        () => killNow('执行超时（${timeout.inSeconds}s），已强制终止'),
      );
    }

    armTimeout();

    /// 提问往返：暂停超时（用户打字不能被硬超时打断），回答后重新计时。
    Future<void> handleAsk(Map<Object?, Object?> message) async {
      timer?.cancel();
      final replyPort = message['replyTo'] as SendPort?;
      final request = AskRequest(
        question: '${message['question'] ?? ''}',
        secret: message['secret'] == true,
        default_: '${message['default'] ?? ''}',
      );
      AskReply reply;
      final handler = onAsk;
      if (handler == null || replyPort == null) {
        const hint = '没有可用的界面来提问，已按取消处理';
        logs.add(hint);
        onLog?.call(hint);
        reply = const AskReply.cancelled();
      } else {
        try {
          reply = await handler(request);
        } catch (error) {
          reply = const AskReply.cancelled();
          logs.add('提问失败：$error');
          onLog?.call('提问失败：$error');
        }
      }
      try {
        replyPort?.send({'ok': reply.ok, 'answer': reply.answer});
      } catch (_) {}
      armTimeout();
    }

    receive.listen((message) {
      if (message is String) {
        logs.add(message);
        onLog?.call(message);
        return;
      }
      if (message is Map && message['type'] == 'ask') {
        // 脚本提问：交给界面，回答后送回脚本（子 isolate 的 replyPort）。
        unawaited(handleAsk(message));
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

    final result = await done.future;
    timer?.cancel();
    token?.detach(killNow);
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
