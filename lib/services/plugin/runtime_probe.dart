import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:serious_python/serious_python.dart';

/// 运行时探针：一次安装即可判定"解释器到底有没有跑起来、跑到哪一步"。
///
/// 背景：`SeriousPython.run()` 默认 `sync:false`，**只等到线程创建就返回**
/// （成功时返回 null），因此宿主无法据此判断解释器是否真的执行了脚本；
/// 而 native abort 又会带走整个进程，Dart 日志来不及留下任何东西。
/// 因此这里所有证据都用**同步 append** 落盘，进程死了也留着。
///
/// 由 `--dart-define=PLUGIN_PROBE=1` 开启；只在首次（无 probe.done 标记）运行一次。
class RuntimeProbe {
  RuntimeProbe._();

  static bool get enabled =>
      const bool.fromEnvironment('PLUGIN_PROBE', defaultValue: false);

  static File? _log;

  static void _write(String line) {
    final file = _log;
    if (file == null) return;
    try {
      file.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  /// 递归列出目录（相对路径 + 字节数），用于判定资产/解包是否完整。
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
              extra += ' magic=${head.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
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

  static Future<void> runIfEnabled() async {
    if (!enabled) return;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/readerplus-logs');
      await dir.create(recursive: true);
      _log = File('${dir.path}/probe.log');
      final done = File('${dir.path}/probe.done');
      if (done.existsSync()) return; // 只跑一次，避免每次启动都起解释器

      _write('A0 探针开始：support=${support.path}');
      _write('    app.zip 是否随包：见下一步');

      // 步骤 1：让插件解包（这一步之前 <support>/flet 本来就不存在）
      String appPath;
      try {
        appPath = await SeriousPython.prepareApp();
        _write('A1 prepareApp 返回：$appPath');
      } catch (error, stack) {
        _write('A1 prepareApp 抛异常：$error');
        _write('$stack');
        return;
      }

      // 步骤 2：解包结果全量落盘（判定资产是否完整）
      final flet = Directory('${support.path}/flet');
      _dumpTree('flet', flet);
      for (final name in ['stdlib.zip', 'sitepackages.zip', 'app.zip']) {
        final file = File('${support.path}/$name');
        _write('包 $name：${file.existsSync() ? "${file.lengthSync()}B" : "不存在"}');
      }

      // 步骤 3：启动解释器并记录返回值类型与耗时（成功应为 null）
      final started = DateTime.now();
      try {
        final result = await SeriousPython.run(
          environmentVariables: {'PROBE': '1'},
        );
        _write(
          'A2 run 返回：${result ?? "null（成功 spawn）"}'
          '，耗时 ${DateTime.now().difference(started).inMilliseconds}ms',
        );
      } catch (error, stack) {
        _write('A2 run 抛异常：$error');
        _write('$stack');
      }

      // 步骤 4：90 秒轮询所有可能的产出路径（判定"没起来"还是"没等够"）
      final candidates = <String, File>{
        'data/host_boot.txt': File('${support.path}/data/host_boot.txt'),
        'flet/app/host_boot.txt': File('${support.path}/flet/app/host_boot.txt'),
        'flet/app/output/log.txt': File('${support.path}/flet/app/output/log.txt'),
        'flet/app/output/manifest.json':
            File('${support.path}/flet/app/output/manifest.json'),
      };
      var seenAny = false;
      for (var i = 0; i < 90; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        for (final entry in candidates.entries) {
          if (entry.value.existsSync()) {
            seenAny = true;
            _write(
              'T+${i + 1}s 出现 ${entry.key}: ${entry.value.lengthSync()}B',
            );
          }
        }
        if (seenAny && i > 4) break;
      }
      _write('A3 轮询结束：${seenAny ? "解释器有产出" : "90 秒内解释器没有任何产出"}');

      // 步骤 5：最小探针——把"我们的 app.zip/main.py 有问题"与
      //        "这台设备上嵌入式解释器根本起不来"彻底分开
      final marker = File('${support.path}/data/py_probe_ok.txt');
      try {
        marker.deleteSync();
      } catch (_) {}
      final minimal = await SeriousPython.runProgram(
        appPath,
        script:
            "open(r'${marker.path}', 'a').write('PY_OK')\n",
      );
      _write(
        'A4 最小探针返回：${minimal ?? "null"}；'
        '标记文件=${marker.existsSync() ? "已生成" : "未生成"}',
      );
      _write('A5 探针结束');
      try {
        done.writeAsStringSync(DateTime.now().toIso8601String(), flush: true);
      } catch (_) {}
    } catch (error, stack) {
      _write('探针异常：$error');
      _write('$stack');
    }
  }

  /// 供开发者页展示。
  static Future<String> read() async {
    try {
      final support = await getApplicationSupportDirectory();
      final file = File('${support.path}/readerplus-logs/probe.log');
      return file.existsSync() ? await file.readAsString() : '（还没有探针日志）';
    } catch (error) {
      return '读取探针日志失败：$error';
    }
  }
}
