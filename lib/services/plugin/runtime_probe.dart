import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:serious_python/serious_python.dart';

/// 运行时探针：判定"嵌入式解释器到底有没有跑起来、跑到哪一步"。
///
/// 为什么需要它：`SeriousPython.run()` 默认 `sync:false`，**只等到线程创建就返回**
/// （成功时返回 null），宿主无法据此判断脚本是否真的执行；而 native abort 会带走
/// 整个进程，Dart 日志来不及落盘。因此这里所有证据都用**同步 append** 写文件。
///
/// 触发方式（两种，效果相同）：
///   1. 开发者页手动点「运行运行时探针」（推荐：不依赖任何编译开关）
///   2. 编译期带 `--dart-define=PLUGIN_PROBE=1` 时，首帧之后自动跑一次
class RuntimeProbe {
  RuntimeProbe._();

  static const bool enabled = bool.fromEnvironment(
    'PLUGIN_PROBE',
    defaultValue: false,
  );

  static File? _log;

  static void _write(String line) {
    final file = _log;
    if (file == null) return;
    try {
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String().substring(11, 23)} $line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  static Future<Directory> _logDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/readerplus-logs');
    await dir.create(recursive: true);
    return dir;
  }

  /// 递归列举目录（相对路径 + 字节数），用于判定资产/解包是否完整。
  static void _dumpTree(String label, Directory dir, {int maxEntries = 400}) {
    if (!dir.existsSync()) {
      _write('$label: 不存在 ${dir.path}');
      return;
    }
    var count = 0;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (count++ >= maxEntries) {
          _write('$label: …（超过 $maxEntries 条，截断）');
          break;
        }
        final rel = entity.path.substring(dir.path.length);
        if (entity is File) {
          var extra = '${entity.lengthSync()}B';
          if (rel.endsWith('.pyc')) {
            try {
              final head = entity.readAsBytesSync().take(4).toList();
              extra +=
                  ' magic=${head.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
            } catch (_) {}
          }
          _write('$label: $rel $extra');
        } else {
          _write('$label: $rel/');
        }
      }
      _write('$label: 共 ${count - 1} 条');
    } catch (error) {
      _write('$label: 列举失败 $error');
    }
  }

  /// 自动执行：首帧之后调用；只跑一次，且限制自动重试次数。
  static Future<void> runIfEnabled() async {
    if (!enabled) return;
    try {
      final dir = await _logDir();
      _log = File('${dir.path}/probe.log');
      if (File('${dir.path}/probe.done').existsSync()) return;
      final attemptsFile = File('${dir.path}/probe.attempts');
      final attempts = attemptsFile.existsSync()
          ? (int.tryParse(attemptsFile.readAsStringSync().trim()) ?? 0)
          : 0;
      // 若探针自身把进程搞崩（来不及写 done），最多再自动试一次，
      // 避免"每次启动都崩、连开发者页都进不去"的死循环。
      if (attempts >= 2) return;
      try {
        attemptsFile.writeAsStringSync('${attempts + 1}', flush: true);
      } catch (_) {}
      await _probe('自动第 ${attempts + 1} 次');
    } catch (error) {
      _write('自动探针异常：$error');
    }
  }

  /// 手动执行（开发者页按钮）：忽略次数限制，供用户主动取证。
  static Future<void> runManually() async {
    try {
      final dir = await _logDir();
      _log = File('${dir.path}/probe.log');
      final done = File('${dir.path}/probe.done');
      if (done.existsSync()) done.deleteSync();
      await _probe('手动');
    } catch (error) {
      _write('手动探针异常：$error');
    }
  }

  static Future<void> _probe(String trigger) async {
    try {
      final support = await getApplicationSupportDirectory();
      _write('A0 探针开始（$trigger）：support=${support.path}');

      // 步骤 1：让插件解包（在此之前 <support>/flet 本来就不存在，属正常）
      final String appPath;
      try {
        appPath = await SeriousPython.prepareApp();
        _write('A1 prepareApp 返回：$appPath');
      } catch (error, stack) {
        _write('A1 prepareApp 抛异常：$error');
        _write('$stack');
        return;
      }

      // 步骤 2：解包结果全量落盘（判定资产是否完整）
      _dumpTree('flet', Directory('${support.path}/flet'));
      _dumpTree('data', Directory('${support.path}/data'), maxEntries: 50);

      // 步骤 3：启动解释器，记录返回值与耗时（成功应为 null）
      final started = DateTime.now();
      try {
        final result = await SeriousPython.run(
          environmentVariables: {'PROBE': '1'},
        );
        _write(
          'A2 run 返回：${result ?? "null（成功 spawn）"}，'
          '耗时 ${DateTime.now().difference(started).inMilliseconds}ms',
        );
      } catch (error, stack) {
        _write('A2 run 抛异常：$error');
        _write('$stack');
      }

      // 步骤 4：90 秒轮询所有可能的产出路径
      final candidates = <String, File>{
        'data/host_boot.txt': File('${support.path}/data/host_boot.txt'),
        'flet/app/host_boot.txt': File('${support.path}/flet/app/host_boot.txt'),
        'flet/app/output/log.txt': File(
          '${support.path}/flet/app/output/log.txt',
        ),
        'flet/app/output/manifest.json': File(
          '${support.path}/flet/app/output/manifest.json',
        ),
      };
      var seen = false;
      for (var i = 0; i < 90; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        for (final entry in candidates.entries) {
          if (entry.value.existsSync()) {
            seen = true;
            _write('T+${i + 1}s 出现 ${entry.key}: ${entry.value.lengthSync()}B');
          }
        }
        if (seen && i > 4) break;
      }
      _write('A3 轮询结束：${seen ? "解释器有产出" : "90 秒内解释器没有任何产出"}');

      // 步骤 5：最小探针——切开"我们的 app.zip/main.py 有问题"与
      //        "这台设备上嵌入式解释器根本起不来"
      final marker = File('${support.path}/data/py_probe_ok.txt');
      try {
        marker.deleteSync();
      } catch (_) {}
      try {
        final minimal = await SeriousPython.runProgram(
          appPath,
          script: "open(r'${marker.path}', 'a').write('PY_OK')\n",
        );
        _write(
          'A4 最小探针返回：${minimal ?? "null"}；'
          '标记文件=${marker.existsSync() ? "已生成" : "未生成"}',
        );
      } catch (error, stack) {
        _write('A4 最小探针抛异常：$error');
        _write('$stack');
      }
      _write('A5 探针结束');
      try {
        File(
          '${support.path}/readerplus-logs/probe.done',
        ).writeAsStringSync(DateTime.now().toIso8601String(), flush: true);
      } catch (_) {}
    } catch (error, stack) {
      _write('探针异常：$error');
      _write('$stack');
    }
  }

  /// 供开发者页展示。
  static Future<String> read() async {
    try {
      final dir = await _logDir();
      final file = File('${dir.path}/probe.log');
      return file.existsSync() ? await file.readAsString() : '（还没有探针日志）';
    } catch (error) {
      return '读取探针日志失败：$error';
    }
  }
}
