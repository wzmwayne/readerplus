import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serious_python/serious_python.dart';

import '../app_log.dart';
import 'plugin_sandbox.dart';

/// 真实运行时：serious_python 打包的 Python 解释器。
class SeriousPythonRuntime implements PluginRuntime {
  Completer<void>? _cancelled;

  @override
  Future<void> runSandbox(String sandboxPath, {required bool audit}) async {
    _cancelled = Completer<void>();
    // 环境变量在个别平台可能不会传给 Python 进程，因此再写一份"任务指针"文件：
    // 入口脚本先读环境变量，读不到就按约定路径读这个文件（见 main.py）。
    try {
      final support = await getApplicationSupportDirectory();
      final dataDir = Directory('${support.path}/data');
      if (!dataDir.existsSync()) await dataDir.create(recursive: true);
      await File(
        '${dataDir.path}/readerplus_job.txt',
      ).writeAsString(sandboxPath, flush: true);
    } catch (error) {
      debugPrint('[plugin] 写入任务指针失败：$error');
    }
    try {
      final run = SeriousPython.run(
        environmentVariables: {
          'SANDBOX_ROOT': sandboxPath,
          // 由入口脚本读取后立即清除，脚本自身无法得知审计是否开启
          'READERPLUS_SANDBOX_AUDIT': audit ? '1' : '0',
        },
      );
      // 取消时直接结束运行时，不再等待本次调用返回
      final output = await Future.any<Object?>([run, _cancelled!.future]);
      // 把 Python 侧输出留档：脚本没写 manifest 时，宿主据此给出线索
      if (output is String && output.trim().isNotEmpty) {
        try {
          await File(
            '$sandboxPath/runtime_output.txt',
          ).writeAsString(output, flush: true);
        } catch (_) {}
      }
    } on MissingPluginException {
      throw StateError('当前构建未包含 Python 运行时（需要先执行脚本打包）');
    } catch (error) {
      // 运行时未打包时，serious_python 会以缺包/缺 main.py 的形式报错
      throw StateError('Python 运行时不可用：$error');
    }
  }

  @override
  void cancel() {
    if (_cancelled?.isCompleted == false) _cancelled!.complete();
    try {
      SeriousPython.terminate();
    } catch (error) {
      debugPrint('[plugin] 取消失败：$error');
    }
  }
}

/// 执行一次脚本：创建沙盒 → 放输入与参数 → 跑 → 收集产物与日志。
///
/// 日志采用「文件尾随」的方式读取（脚本输出经 main.py 同时写入 log.txt），
/// 因此前台可以边跑边显示，而不用等进程结束。
class PluginRunner {
  PluginRunner({PluginRuntime? runtime})
    : _runtime = runtime ?? SeriousPythonRuntime();

  final PluginRuntime _runtime;
  final StreamController<String> _logs = StreamController<String>.broadcast();
  Timer? _logTimer;
  int _logOffset = 0;

  /// 运行日志（每一次 run 重新开始）。
  Stream<String> get logs => _logs.stream;

  PluginSandbox? _sandbox;

  Future<PluginRunResult> run({
    required String scriptSource,
    required Directory jobsRoot,
    required bool audit,
    Map<String, dynamic> params = const {},
    Map<String, List<int>> inputs = const {},
    Duration timeout = const Duration(minutes: 10),
    bool keepSandboxOnError = true,
    /// 成功时也保留沙盒（调用方读完产物后自行清理）。
    bool keepSandbox = false,
  }) async {
    final sandbox = await PluginSandbox.create(jobsRoot);
    _sandbox = sandbox;
    AppLog.info('plugin', '执行开始：task=${params['task']} 目录=${sandbox.root.path}');
    _logOffset = 0;
    await sandbox.writeParams(params);
    await sandbox.writeScript(scriptSource);
    for (final entry in inputs.entries) {
      await sandbox.addInput(entry.key, entry.value);
    }
    _startTailing(sandbox);

    String? failure;
    try {
      await _runtime
          .runSandbox(sandbox.root.path, audit: audit)
          .timeout(timeout);
    } on TimeoutException {
      _runtime.cancel();
      failure = '执行超时';
    } catch (error) {
      failure = '$error';
    }
    await _stopTailing();

    final manifest = await sandbox.readManifest();
    final log = await sandbox.readLog();
    var traceback = failure ?? manifest.traceback;
    if (!manifest.ok && failure == null) {
      // 脚本没写 manifest：多半是 Python 侧没跑起来，附上它的输出便于排查
      final outputFile = File('${sandbox.root.path}/runtime_output.txt');
      if (outputFile.existsSync()) {
        final output = (await outputFile.readAsString()).trim();
        if (output.isNotEmpty) traceback = '$traceback\n$output';
      }
    }
    final ok = failure == null && manifest.ok;
    AppLog.info(
      'plugin',
      ok ? '执行成功：${manifest.outputs.join('、')}' : '执行失败：$traceback',
    );
    final result = PluginRunResult(
      ok: ok,
      outputs: ok ? sandbox.listOutputs() : const [],
      traceback: traceback,
      sandboxPath: sandbox.root.path,
      log: log,
    );
    await sandbox.dispose(
      keepForDebug: keepSandbox || (!ok && keepSandboxOnError),
    );
    _sandbox = null;
    return result;
  }

  void cancel() => _runtime.cancel();

  /// 读取脚本内的 SCRIPT 声明（不执行脚本主流程）。
  Future<Map<String, dynamic>?> describe({
    required String scriptSource,
    required Directory jobsRoot,
    required bool audit,
  }) async {
    final sandbox = await PluginSandbox.create(jobsRoot);
    try {
      await sandbox.writeParams({'task': 'describe'});
      await sandbox.writeScript(scriptSource);
      await _runtime.runSandbox(sandbox.root.path, audit: audit);
      final manifest = await sandbox.readManifest();
      if (!manifest.ok) {
        debugPrint('[plugin] describe 失败：${manifest.traceback}');
        return null;
      }
      return manifest.script;
    } catch (error) {
      debugPrint('[plugin] describe 异常：$error');
      return null;
    } finally {
      await sandbox.dispose();
    }
  }

  void _startTailing(PluginSandbox sandbox) {
    _logTimer?.cancel();
    _logTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      try {
        final file = sandbox.logFile;
        if (!file.existsSync()) return;
        final content = await file.readAsString();
        if (content.length <= _logOffset) return;
        final chunk = content.substring(_logOffset);
        _logOffset = content.length;
        if (!_logs.isClosed) _logs.add(chunk);
      } catch (_) {
        // 日志读取失败不影响执行
      }
    });
  }

  Future<void> _stopTailing() async {
    _logTimer?.cancel();
    _logTimer = null;
    // 收尾：把剩余日志发出
    final sandbox = _sandbox;
    if (sandbox != null) {
      try {
        final content = await sandbox.readLog();
        if (content.length > _logOffset) {
          final chunk = content.substring(_logOffset);
          _logOffset = content.length;
          if (!_logs.isClosed) _logs.add(chunk);
        }
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _logTimer?.cancel();
    await _logs.close();
  }
}
