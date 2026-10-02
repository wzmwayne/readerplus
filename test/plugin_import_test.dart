import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub_importer.dart';
import 'package:reader/services/plugin/plugin_sandbox.dart';

/// 端到端验证「TXT 导入」链路：TXT → 内置脚本（沙盒）→ EPUB → 应用解析器读回。
///
/// 用本机 python3 直接跑沙盒入口（应用内是打包的同一份 main.py 与同一份脚本），
/// 因此这里验证的就是真实链路，只是不需要打包运行时。
Future<String?> _python() async {
  for (final candidate in ['python3', 'python']) {
    try {
      final result = await Process.run(candidate, ['--version']);
      if (result.exitCode == 0) return candidate;
    } catch (_) {}
  }
  return null;
}

Future<PluginSandbox> _sandboxWith({
  required String python,
  required File txt,
  String title = '夜航船（测试）',
  String author = '测试作者',
}) async {
  final root = await Directory.systemTemp.createTemp('import_test');
  final sandbox = await PluginSandbox.create(root);
  await sandbox.writeParams({
    'task': 'clean',
    'input_file': 'raw.txt',
    'output_file': 'book.epub',
    'title': title,
    'author': author,
    'chapter_pattern': r'^第[一二三四五六七八九十百千0-9]+章.*$',
    'clean_rules': [
      [r'[\u200b\ufeff]', ''],
      [r'(?m)^\s*(广告|推广)[:：].*$', ''],
    ],
  });
  await sandbox.writeScript(
    await File('python/examples/txt_cleaner.py').readAsString(),
  );
  await sandbox.addInput('raw.txt', await txt.readAsBytes());
  return sandbox;
}

Future<({int code, String log})> _runSandbox(
  String python,
  PluginSandbox sandbox,
) async {
  final result = await Process.run(
    python,
    ['${Directory.current.path}/python/app/main.py'],
    environment: {'SANDBOX_ROOT': sandbox.root.path},
    includeParentEnvironment: true,
  );
  return (code: result.exitCode, log: await sandbox.readLog());
}

void main() {
  late String? python;

  setUpAll(() async {
    python = await _python();
  });

  test('导入 UTF-8 测试 TXT：分章正确、广告被清理、可直接阅读', () async {
    if (python == null) {
      markTestSkipped('本机没有 python3');
      return;
    }
    final sandbox = await _sandboxWith(
      python: python!,
      txt: File('test/fixtures/sample_book.txt'),
    );
    final run = await _runSandbox(python!, sandbox);
    expect(run.code, 0, reason: run.log);

    final manifest = await sandbox.readManifest();
    expect(manifest.ok, isTrue, reason: run.log);
    expect(manifest.outputs, contains('book.epub'));

    final book = EpubImporter.parse(
      await File('${sandbox.output.path}/book.epub').readAsBytes(),
    );
    expect(book.title, '夜航船（测试）');
    expect(book.author, '测试作者');
    expect(book.chapters.map((c) => c.title).toList(), [
      '第一章 夜叩门',
      '第二章 旧信笺',
      '第三章 山中客',
    ]);
    // 正文完整
    expect(book.content, contains('更夫敲梆子'));
    expect(book.content, contains('檐角还在滴着水'));
    // 广告行被清理规则删掉
    expect(book.content, isNot(contains('广告：更多精彩内容')));

    await Directory(sandbox.root.parent.path).delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('导入 GBK 编码的 TXT：自动识别编码且不乱码', () async {
    if (python == null) {
      markTestSkipped('本机没有 python3');
      return;
    }
    // 用系统 python 生成一份 GBK 编码的同一本书
    final gbkPath = '${(await Directory.systemTemp.createTemp('gbk')).path}/gbk.txt';
    final encode = await Process.run(python!, [
      '-c',
      'import sys,pathlib;'
      'pathlib.Path(sys.argv[2]).write_bytes(pathlib.Path(sys.argv[1])'
      '.read_text(encoding="utf-8").encode("gbk"))',
      'test/fixtures/sample_book.txt',
      gbkPath,
    ]);
    expect(encode.exitCode, 0, reason: '${encode.stderr}');

    final sandbox = await _sandboxWith(
      python: python!,
      txt: File(gbkPath),
      title: 'GBK 测试',
    );
    final run = await _runSandbox(python!, sandbox);
    expect(run.code, 0, reason: run.log);

    final book = EpubImporter.parse(
      await File('${sandbox.output.path}/book.epub').readAsBytes(),
    );
    expect(book.title, 'GBK 测试');
    expect(book.chapters.length, 3);
    expect(book.content, contains('更夫敲梆子'), reason: 'GBK 应被正确解码');
    expect(book.content, isNot(contains('广告')));

    await Directory(sandbox.root.parent.path).delete(recursive: true);
    await File(gbkPath).parent.delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('测试文本本身可用（夹具完整性）', () async {
    final text = await File('test/fixtures/sample_book.txt').readAsString(
      encoding: utf8,
    );
    expect(text, contains('第一章 夜叩门'));
    expect(text.split('\n').where((line) => line.startsWith('第')).length, 3);
  });

  test('没有 SANDBOX_ROOT 环境变量时，靠任务指针文件也能跑通（Android 场景）', () async {
    if (python == null) {
      markTestSkipped('本机没有 python3');
      return;
    }
    final sandbox = await _sandboxWith(
      python: python!,
      txt: File('test/fixtures/sample_book.txt'),
      title: '指针回退测试',
    );
    // 模拟 Android：不传环境变量，只在当前目录放任务指针文件
    final pointer = File('${Directory.current.path}/readerplus_job.txt');
    await pointer.writeAsString(sandbox.root.path, flush: true);
    try {
      final result = await Process.run(
        python!,
        ['${Directory.current.path}/python/app/main.py'],
        includeParentEnvironment: true,
        workingDirectory: Directory.current.path,
      );
      final log = await sandbox.readLog();
      expect(result.exitCode, 0, reason: 'stderr=${result.stderr}\nlog=$log');
      final manifest = await sandbox.readManifest();
      expect(manifest.ok, isTrue, reason: log);
      expect(manifest.outputs, contains('book.epub'));
      expect(result.stdout.toString(), contains('任务指针'));
    } finally {
      if (pointer.existsSync()) await pointer.delete();
      await Directory(sandbox.root.parent.path).delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('运行器在脚本没写 manifest 时给出可排查信息', () async {
    // 用一个不写 manifest 的"脚本"验证提示内容（不依赖 Python）
    final root = await Directory.systemTemp.createTemp('no_manifest');
    final sandbox = await PluginSandbox.create(root);
    await sandbox.writeScript('print("nothing")');
    final manifest = await sandbox.readManifest();
    expect(manifest.ok, isFalse);
    expect(manifest.traceback, contains('manifest'));
    await root.delete(recursive: true);
  });
}
