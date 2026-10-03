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

  /// 最近一次运行时的启动诊断（心跳是否到达），供宿主写进日志与错误信息。
  String lastBootDiagnosis = '';

  /// 解包目录与心跳文件：用于判断"Python 入口是否真的执行过"。
  Future<({Directory? flet, Directory? app, File? heartbeat})> _paths() async {
    try {
      final support = await getApplicationSupportDirectory();
      return (
        flet: Directory('${support.path}/flet'),
        app: Directory('${support.path}/flet/app'),
        heartbeat: File('${support.path}/readerplus-heartbeat.txt'),
      );
    } catch (_) {
      return (flet: null, app: null, heartbeat: null);
    }
  }

  @override
  Future<void> runSandbox(String sandboxPath, {required bool audit}) async {
    _cancelled = Completer<void>();
    final paths = await _paths();
    lastBootDiagnosis = '';

    // 运行前：解包目录必须有入口脚本，否则清掉让运行时重新解包
    final app = paths.app;
    if (app != null) {
      final hasEntry =
          File('${app.path}/main.py').existsSync() ||
          File('${app.path}/main.pyc').existsSync();
      AppLog.info(
        'plugin',
        '解包目录 ${app.path}：入口${hasEntry ? '存在' : '缺失'}、'
        '目录存在=${app.existsSync()}',
      );
      if (!hasEntry && paths.flet!.existsSync()) {
        AppLog.error('plugin', '解包目录不完整，清理后由运行时重新解包');
        try {
          paths.flet!.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    try {
      paths.heartbeat?.deleteSync();
    } catch (_) {}
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
          if (paths.heartbeat != null)
            'READERPLUS_HEARTBEAT': paths.heartbeat!.path,
        },
      );
      // 取消时直接结束运行时，不再等待本次调用返回
      var output = await Future.any<Object?>([run, _cancelled!.future]);
      if (output is String && output.trim().isNotEmpty) {
        AppLog.info('plugin', 'python 输出：${output.trim()}');
      }

      // 心跳缺失 ⇒ Python 入口没执行过：多半是解包目录坏了，清理后重试一次
      if (!_heartbeatArrived(paths, sandboxPath)) {
        lastBootDiagnosis = 'Python 入口未执行（运行时启动阶段失败）';
        AppLog.error('plugin', '$lastBootDiagnosis：清理解包目录后重试一次');
        try {
          if (paths.flet?.existsSync() == true) {
            paths.flet!.deleteSync(recursive: true);
          }
          paths.heartbeat?.deleteSync();
        } catch (_) {}
        final retry = SeriousPython.run(
          environmentVariables: {
            'SANDBOX_ROOT': sandboxPath,
            'READERPLUS_SANDBOX_AUDIT': audit ? '1' : '0',
            if (paths.heartbeat != null)
              'READERPLUS_HEARTBEAT': paths.heartbeat!.path,
          },
        );
        output = await Future.any<Object?>([retry, _cancelled!.future]);
        if (output is String && output.trim().isNotEmpty) {
          AppLog.info('plugin', 'python 输出（重试）：${output.trim()}');
        }
        if (_heartbeatArrived(paths, sandboxPath)) {
          lastBootDiagnosis = '';
          AppLog.info('plugin', '清理解包目录后重试成功');
        } else {
          AppLog.error('plugin', '重试后仍未见心跳，运行时无法启动');
        }
      }
      // 把 Python 侧输出留档：脚本没写 manifest 时，宿主据此给出线索
      if (output is String && output.trim().isNotEmpty) {
        try {
          await File(
            '$sandboxPath/output/runtime_output.txt',
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
  /// 心跳是否到达：判断 Python 入口有没有真的执行过。
  bool _heartbeatArrived(
    ({Directory? flet, Directory? app, File? heartbeat}) paths,
    String sandboxPath,
  ) {
    final candidates = <File>[
      if (paths.heartbeat != null) paths.heartbeat!,
      if (paths.app != null) File('${paths.app!.path}/host_boot.txt'),
      if (paths.flet != null) File('${paths.flet!.path}/data/host_boot.txt'),
      File('$sandboxPath/host_boot.txt'),
    ];
    for (final file in candidates) {
      try {
        if (file.existsSync()) return true;
      } catch (_) {}
    }
    return false;
  }

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

  /// 单解释器：全局串行，避免两个运行互相 terminate。
  static Future<void> _queue = Future<void>.value();

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
    return _serialize(
      () => _runLocked(
        scriptSource: scriptSource,
        jobsRoot: jobsRoot,
        audit: audit,
        params: params,
        inputs: inputs,
        timeout: timeout,
        keepSandboxOnError: keepSandboxOnError,
        keepSandbox: keepSandbox,
      ),
    );
  }

  /// 单解释器：所有对运行时的使用都在此串行。
  static Future<T> _serialize<T>(Future<T> Function() action) async {
    final previous = _queue;
    final gate = Completer<void>();
    _queue = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  }

  Future<PluginRunResult> _runLocked({
    required String scriptSource,
    required Directory jobsRoot,
    required bool audit,
    required Map<String, dynamic> params,
    required Map<String, List<int>> inputs,
    required Duration timeout,
    required bool keepSandboxOnError,
    required bool keepSandbox,
  }) async {
    // 准备阶段（建沙盒、写参数/脚本/输入）也会抛异常：一律转成失败结果，绝不外抛
    PluginSandbox? sandbox;
    try {
      sandbox = await PluginSandbox.create(jobsRoot);
      _sandbox = sandbox;
      AppLog.info(
        'plugin',
        '执行开始：task=${params['task']} 审计=$audit 脚本 ${scriptSource.length} 字符 '
        '输入=${inputs.keys.join('、')} 目录=${sandbox.root.path}',
      );
      _logOffset = 0;
      await sandbox.writeParams(params);
      await sandbox.writeScript(scriptSource);
      for (final entry in inputs.entries) {
        await sandbox.addInput(entry.key, entry.value);
      }
      _startTailing(sandbox);
    } catch (error, stack) {
      AppLog.error('plugin', '准备运行环境失败：$error', stack);
      _sandbox = null;
      return PluginRunResult(
        ok: false,
        outputs: const [],
        traceback: '准备运行环境失败：$error',
        sandboxPath: sandbox?.root.path ?? '',
        log: '',
      );
    }

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
    if (log.trim().isNotEmpty) {
      final tail = log.length > 2000 ? log.substring(log.length - 2000) : log;
      AppLog.info('plugin', '脚本日志尾部：\n$tail');
    }
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
  ///
  /// 与 [run] 共用同一串行队列：Python 是单解释器，并发使用会直接崩进程。
  Future<Map<String, dynamic>?> describe({
    required String scriptSource,
    required Directory jobsRoot,
    required bool audit,
  }) => _serialize(() async {
    final started = DateTime.now();
    AppLog.info(
      'plugin',
      'describe 开始：脚本 ${scriptSource.length} 字符、审计=$audit、'
      '工作目录=${jobsRoot.path}',
    );
    final sandbox = await PluginSandbox.create(jobsRoot);
    try {
      await sandbox.writeParams({'task': 'describe'});
      await sandbox.writeScript(scriptSource);
      await _runtime.runSandbox(sandbox.root.path, audit: audit);
      final manifest = await sandbox.readManifest();
      if (!manifest.ok) {
        return null;
      }
      final log = await sandbox.readLog();
      if (log.trim().isNotEmpty) AppLog.info('plugin', 'describe 日志：$log');
      AppLog.info(
        'plugin',
        'describe 结束：耗时 ${DateTime.now().difference(started).inMilliseconds}ms、'
        '结果=${manifest.script == null ? '无声明' : '已解析'}',
      );
      if (!manifest.ok) {
        AppLog.error('plugin', 'describe 失败：${manifest.traceback}');
      }
      return manifest.script;
    } catch (error, stack) {
      AppLog.error('plugin', 'describe 异常：$error', stack);
      return null;
    } finally {
      await sandbox.dispose();
    }
  });

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
