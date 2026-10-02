import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub_importer.dart';
import 'package:reader/services/plugin/plugin_repository.dart';
import 'package:reader/services/plugin/plugin_runner.dart';
import 'package:reader/services/plugin/plugin_sandbox.dart';
import 'package:reader/services/storage.dart';

/// 可控的假运行时（不依赖 Python）。
class FakeRuntime implements PluginRuntime {
  FakeRuntime({this.onRun, this.hang = false});

  final Future<void> Function(String sandboxPath)? onRun;
  final bool hang;
  bool cancelled = false;
  String? lastSandbox;

  @override
  Future<void> runSandbox(String sandboxPath, {required bool audit}) async {
    lastSandbox = sandboxPath;
    if (hang) return Completer<void>().future;
    if (onRun != null) await onRun!(sandboxPath);
  }

  @override
  void cancel() => cancelled = true;
}

Future<Directory> _temp(String prefix) => Directory.systemTemp.createTemp(prefix);

/// 找本机 python3（找不到就跳过联网/真实解释器用例）。
Future<String?> _python() async {
  for (final candidate in ['python3', 'python']) {
    try {
      final result = await Process.run(candidate, ['--version']);
      if (result.exitCode == 0) return candidate;
    } catch (_) {}
  }
  return null;
}

void main() {
  group('沙盒契约', () {
    test('创建目录结构并写入参数与脚本', () async {
      final jobs = await _temp('plugin_jobs');
      final sandbox = await PluginSandbox.create(jobs);
      await sandbox.writeParams({'task': 'clean', 'input_file': 'raw.txt'});
      await sandbox.writeScript('print("hi")');
      await sandbox.addInput('raw.txt', utf8.encode('正文'));

      expect(sandbox.input.existsSync(), isTrue);
      expect(sandbox.output.existsSync(), isTrue);
      expect(sandbox.work.existsSync(), isTrue);
      expect(sandbox.scriptFile.existsSync(), isTrue);
      expect(File('${sandbox.input.path}/raw.txt').existsSync(), isTrue);
      final params =
          jsonDecode(await sandbox.paramsFile.readAsString())
              as Map<String, dynamic>;
      expect(params['task'], 'clean');

      await sandbox.dispose();
      expect(sandbox.root.existsSync(), isFalse);
      await jobs.delete(recursive: true);
    });

    test('失败时可保留沙盒用于排查', () async {
      final jobs = await _temp('plugin_jobs');
      final sandbox = await PluginSandbox.create(jobs);
      await sandbox.dispose(keepForDebug: true);
      expect(sandbox.root.existsSync(), isTrue);
      await jobs.delete(recursive: true);
    });

    test('manifest 缺失或损坏都按失败处理', () async {
      final jobs = await _temp('plugin_jobs');
      final sandbox = await PluginSandbox.create(jobs);
      expect((await sandbox.readManifest()).ok, isFalse);

      await sandbox.manifestFile.writeAsString('{ not json');
      final broken = await sandbox.readManifest();
      expect(broken.ok, isFalse);
      expect(broken.traceback, contains('解析失败'));

      await sandbox.manifestFile.writeAsString(
        jsonEncode({'status': 'ok', 'outputs': ['book.epub']}),
      );
      final ok = await sandbox.readManifest();
      expect(ok.ok, isTrue);
      expect(ok.outputs, ['book.epub']);
      await jobs.delete(recursive: true);
    });
  });

  group('执行器', () {
    test('成功后收集 output/ 产物与日志', () async {
      final jobs = await _temp('plugin_jobs');
      final logs = <String>[];
      final runtime = FakeRuntime(
        onRun: (path) async {
          await File('$path/log.txt').writeAsString('[clean] 开始\n');
          Directory('$path/output').createSync(recursive: true);
          await File('$path/output/book.epub').writeAsString('EPUB');
          await File(
            '$path/manifest.json',
          ).writeAsString(jsonEncode({'status': 'ok', 'outputs': ['book.epub']}));
        },
      );
      final runner = PluginRunner(runtime: runtime);
      runner.logs.listen(logs.add);

      final result = await runner.run(
        scriptSource: 'print(1)',
        jobsRoot: jobs,
        audit: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(result.ok, isTrue);
      expect(result.outputs.single.path, endsWith('book.epub'));
      expect(result.log, contains('[clean] 开始'));
      expect(logs.join(), contains('[clean] 开始'));
      await runner.dispose();
      await jobs.delete(recursive: true);
    });

    test('manifest 报错时不算成功，且不返回产物', () async {
      final jobs = await _temp('plugin_jobs');
      final runtime = FakeRuntime(
        onRun: (path) async {
          await File('$path/output/partial.epub').writeAsString('X');
          await File('$path/manifest.json').writeAsString(
            jsonEncode({'status': 'error', 'traceback': '规则语法错误'}),
          );
        },
      );
      final runner = PluginRunner(runtime: runtime);
      final result = await runner.run(
        scriptSource: 'raise SystemExit(1)',
        jobsRoot: jobs,
        audit: true,
      );
      expect(result.ok, isFalse);
      expect(result.traceback, contains('规则语法错误'));
      expect(result.outputs, isEmpty);
      await runner.dispose();
      await jobs.delete(recursive: true);
    });

    test('超时会取消运行时', () async {
      final jobs = await _temp('plugin_jobs');
      final runtime = FakeRuntime(hang: true);
      final runner = PluginRunner(runtime: runtime);
      final result = await runner.run(
        scriptSource: 'while True: pass',
        jobsRoot: jobs,
        audit: true,
        timeout: const Duration(milliseconds: 200),
      );
      expect(result.ok, isFalse);
      expect(result.traceback, contains('超时'));
      expect(runtime.cancelled, isTrue);
      await runner.dispose();
      await jobs.delete(recursive: true);
    });
  });

  group('脚本仓库', () {
    test('导入、更新开关、删除', () async {
      final root = await _temp('plugin_store');
      Storage.overrideRoot(root);
      final storage = await Storage.instance();
      final repository = PluginRepository(storage);

      final script = await repository.importSource(
        '# 我的清洗脚本\n"""把 TXT 清洗成 EPUB"""\nprint("hi")\n',
      );
      expect(script.name, '我的清洗脚本');
      expect(script.description, '把 TXT 清洗成 EPUB');
      expect(script.enabled, isTrue);

      var scripts = await repository.load();
      expect(scripts.length, 1);
      expect(scripts.single.source, contains('print'));

      script.enabled = false;
      await repository.save(script);
      scripts = await repository.load();
      expect(scripts.single.enabled, isFalse);

      await repository.delete(script.id);
      expect(await repository.load(), isEmpty);
      await root.delete(recursive: true);
    });
  });

  group('真实 Python 契约（需要本机 python3）', () {
    test('main.py + 示例脚本：TXT 清洗为可被解析的 EPUB 3', () async {
      final python = await _python();
      if (python == null) {
        markTestSkipped('本机没有 python3');
        return;
      }
      final projectRoot = Directory.current.path;
      final jobs = await _temp('plugin_e2e');
      final sandbox = await PluginSandbox.create(jobs);
      await sandbox.writeParams({
        'task': 'clean',
        'input_file': 'raw.txt',
        'output_file': 'book.epub',
        'title': '夜航船',
        'author': '张岱',
        'chapter_pattern': r'^第[一二三四五六七八九十]+章.*$',
        'clean_rules': [
          [r'[\u200b\ufeff]', ''],
          [r'(?m)^\s*广告.*$', ''],
        ],
      });
      await sandbox.writeScript(
        await File('$projectRoot/python/examples/txt_cleaner.py').readAsString(),
      );
      await sandbox.addInput(
        'raw.txt',
        utf8.encode(
          '第一章 夜叩门\n夜色像一层薄薄的墨，慢慢洇开在窗棂上。\n'
          '广告：请下载本站 App\n'
          '他放下手中的书，听见巷子尽头传来更夫敲梆子的声音。\n'
          '第二章 旧信笺\n这样的夜里，适合想一些很久以前的事。\n',
        ),
      );

      final result = await Process.run(
        python,
        ['$projectRoot/python/app/main.py'],
        environment: {
          'SANDBOX_ROOT': sandbox.root.path,
          'READERPLUS_SANDBOX_AUDIT': '1',
        },
        includeParentEnvironment: true,
      );
      final log = await sandbox.readLog();
      expect(result.exitCode, 0, reason: 'stderr=${result.stderr}\nlog=$log');

      final manifest = await sandbox.readManifest();
      expect(manifest.ok, isTrue, reason: log);
      expect(manifest.outputs, contains('book.epub'));

      // mimetype 必须是第一个条目且不压缩（0 = stored）
      final bytes = await File('${sandbox.output.path}/book.epub').readAsBytes();
      expect(utf8.decode(bytes.sublist(0, 2)), 'PK');
      expect(bytes[8], 0, reason: '本地文件头压缩方式应为 stored');
      expect(bytes[9], 0);
      expect(utf8.decode(bytes.sublist(30, 38)), 'mimetype');
      expect(
        utf8.decode(bytes.sublist(38, 38 + 20)),
        'application/epub+zip',
      );

      // 用应用自己的 EPUB 解析器读回，证明产物真的可用
      final book = EpubImporter.parse(bytes);
      expect(book.title, '夜航船');
      expect(book.author, '张岱');
      expect(book.chapters.map((c) => c.title), ['第一章 夜叩门', '第二章 旧信笺']);
      expect(book.content, contains('慢慢洇开在窗棂上'));
      expect(book.content, isNot(contains('广告：请下载本站 App')));

      await sandbox.dispose();
      await jobs.delete(recursive: true);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('审计钩子阻止越出沙盒的读取', () async {
      final python = await _python();
      if (python == null) {
        markTestSkipped('本机没有 python3');
        return;
      }
      final projectRoot = Directory.current.path;
      final jobs = await _temp('plugin_audit');
      final sandbox = await PluginSandbox.create(jobs);
      await sandbox.writeParams({'task': 'clean'});
      await sandbox.writeScript(
        'with open("/etc/passwd", encoding="utf-8") as handle:\n'
        '    print(handle.read(20))\n',
      );

      final result = await Process.run(
        python,
        ['$projectRoot/python/app/main.py'],
        environment: {
          'SANDBOX_ROOT': sandbox.root.path,
          'READERPLUS_SANDBOX_AUDIT': '1',
        },
        includeParentEnvironment: true,
      );
      expect(result.exitCode, isNot(0));
      final manifest = await sandbox.readManifest();
      expect(manifest.ok, isFalse);
      expect(manifest.traceback, contains('沙盒'));
      await jobs.delete(recursive: true);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
