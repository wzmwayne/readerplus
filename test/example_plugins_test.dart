import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub_importer.dart';
import 'package:reader/services/script/hetu_engine.dart';
import 'package:reader/services/script/script_runner.dart';

/// 内置示例插件必须跑在**新引擎**上：纯 Dart、isolate 隔离、无原生依赖。
void main() {
  Future<ScriptRunResult> runExample(
    String scriptPath, {
    Map<String, List<int>> inputs = const {},
    Map<String, String> params = const {},
    Directory? outputDir,
  }) async {
    final source = await File(scriptPath).readAsString();
    final runner = ScriptRunner(entry: HetuScriptEngine.isolateEntry);
    return runner.run(
      source,
      inputs: inputs,
      params: params,
      outputDir: outputDir,
      timeout: const Duration(seconds: 30),
    );
  }

  test('示例一：TXT 清洗转 EPUB（产出可被应用解析器读回的 EPUB）', () async {
    final outDir = await Directory.systemTemp.createTemp('example_clean');
    final input = await File('test/fixtures/sample_book.txt').readAsBytes();
    final result = await runExample(
      'assets/plugins/txt_cleaner.ht',
      inputs: {'raw.txt': input},
      params: {'title': '夜航船（示例）', 'author': '测试作者'},
      outputDir: outDir,
    );
    expect(result.ok, isTrue, reason: result.error);
    expect(result.logs.join('\n'), contains('切分得到 3 章'));

    final epub = File('${outDir.path}/book.epub');
    expect(epub.existsSync(), isTrue, reason: '脚本应写出 book.epub');
    final book = EpubImporter.parse(await epub.readAsBytes());
    expect(book.title, '夜航船（示例）');
    expect(book.author, '测试作者');
    expect(book.chapters.map((c) => c.title).toList(), [
      '第一章 夜叩门',
      '第二章 旧信笺',
      '第三章 山中客',
    ]);
    expect(book.content, contains('更夫敲梆子'));
    // 清洗只做规范化（去零宽/BOM），**不删正文内容**：广告行必须保留
    expect(book.content, contains('广告：'), reason: '内置清洗脚本不应删除正文内容');
    await outDir.delete(recursive: true);
  });

  test('示例二：假书源搜索（不联网，返回条目）', () async {
    final result = await runExample(
      'assets/plugins/fake_source.ht',
      params: {'task': 'search', 'query': '测试'},
    );
    expect(result.ok, isTrue, reason: result.error);
    final payload = result.result as Map;
    final items = (payload['items'] as List).cast<Map>();
    expect(items.length, 3);
    expect(items.first['title'], contains('夜航船'));
    expect(result.logs.join('\n'), contains('命中 3 条'));
  });

  test('示例二：关键词 fail 触发失败（错误路径可控）', () async {
    final result = await runExample(
      'assets/plugins/fake_source.ht',
      params: {'task': 'search', 'query': 'fail'},
    );
    expect(result.ok, isFalse);
    expect(result.error, contains('fail'));
  });

  test('示例二：详情任务返回书名与简介', () async {
    final result = await runExample(
      'assets/plugins/fake_source.ht',
      params: {'task': 'detail', 'id': '1'},
    );
    expect(result.ok, isTrue, reason: result.error);
    final payload = result.result as Map;
    expect(payload['id'], '1');
    expect(payload['title'], contains('夜航船'));
    expect('${payload['description']}', isNotEmpty);
  });
}
