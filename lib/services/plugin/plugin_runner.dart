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
      if (!hasEntry) {
        // 全新安装时这里本来就还没解包（prepareApp 在 run() 之后才执行），
        // 千万不能删除 <support>/flet —— 它是插件的 PYTHONHOME，
        // 在解释器可能仍在初始化时删除它正是原生 abort 的根源。
        AppLog.info('plugin', '解包目录尚未就绪（首次运行属正常，交由运行时自行解包）');
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
        },
      );
      // 取消时直接结束运行时，不再等待本次调用返回
      final output = await Future.any<Object?>([run, _cancelled!.future]);
      if (output is String && output.trim().isNotEmpty) {
        AppLog.info('plugin', 'python 输出：${output.trim()}');
      }
      AppLog.info('plugin', '解释器调用已返回，等待产出信号…');
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
      // sync:false 下 runSandbox 只等到"线程已创建"就返回，因此不能立刻读结果：
      // 必须轮询 output/manifest.json（脚本结束才会写出），期间保持日志尾随。
      try {
        // 对桥接调用本身也保留硬超时：运行时挂死时不能把整个流程一起拖住
        await _runtime.runSandbox(sandbox.root.path, audit: audit).timeout(timeout);
      } on TimeoutException {
        _runtime.cancel();
        failure = '执行超时（${timeout.inMilliseconds}ms 内未返回，已取消）';
      }

      // 1) 先等"Python 真的起来了"：入口一启动就会写日志文件（main.py 的 tee）。
      //    等待上限取 min(8s, 调用方超时)，避免短超时任务被固定 8 秒拖住。
      final bootWait = timeout < const Duration(seconds: 8)
          ? timeout
          : const Duration(seconds: 8);
      final bootDeadline = DateTime.now().add(bootWait);
      while (DateTime.now().isBefore(bootDeadline)) {
        if (sandbox.logFile.existsSync() || sandbox.manifestFile.existsSync()) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      final started =
          sandbox.logFile.existsSync() || sandbox.manifestFile.existsSync();
      if (failure != null) {
        // 桥接已超时，跳过后续等待
      } else if (!started) {
        _runtime.cancel();
        failure = '执行超时（${bootWait.inMilliseconds}ms 内未开始产出，已取消）';
      } else {
        // 2) 再等脚本写出结果
        final deadline = DateTime.now().add(timeout);
        while (DateTime.now().isBefore(deadline)) {
          if (sandbox.manifestFile.existsSync()) break;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!sandbox.manifestFile.existsSync()) {
          _runtime.cancel();
          failure = '执行超时（脚本 ${timeout.inMinutes} 分钟内未写出结果）';
        }
      }
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
    var manifestOk = false;
    final sandbox = await PluginSandbox.create(jobsRoot);
    try {
      await sandbox.writeParams({'task': 'describe'});
      await sandbox.writeScript(scriptSource);
      await _runtime.runSandbox(sandbox.root.path, audit: audit);
      // 同上：等到脚本真正写出结果（最多 60 秒），否则保留沙盒便于排查
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(deadline) &&
          !sandbox.manifestFile.existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
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
        AppLog.error(
          'plugin',
          'describe 未拿到声明：${manifest.traceback}'
          '（清单路径 ${sandbox.manifestFile.path}，存在=${sandbox.manifestFile.existsSync()}）',
        );
      }
      manifestOk = true;
      return manifest.script;
    } catch (error, stack) {
      AppLog.error('plugin', 'describe 异常：$error', stack);
      return null;
    } finally {
      // 只有确认脚本已结束（拿到清单或明确失败）才清理；否则保留现场
      if (manifestOk) await sandbox.dispose();
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
