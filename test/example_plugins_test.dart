import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/ezbk/ezbk_document.dart';
import 'package:reader/services/script/js_engine.dart';
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
    final runner = ScriptRunner(entry: JsScriptEngine.isolateEntry);
    final storageRoot =
        '${Directory.systemTemp.path}/readerplus_example/${DateTime.now().microsecondsSinceEpoch}';
    return runner.run(
      source,
      inputs: inputs,
      params: params,
      outputDir: outputDir,
      storageRoot: storageRoot,
      timeout: const Duration(seconds: 30),
    );
  }

  test('示例一：TXT 清洗输出 EZBK 文本（可被解析器读回）', () async {
    final outDir = await Directory.systemTemp.createTemp('example_clean');
    final input = await File('test/fixtures/sample_book.txt').readAsBytes();
    final result = await runExample(
      'examples/plugins/txt_cleaner.js',
      inputs: {'raw.txt': input},
      params: {'task': 'import'},
      outputDir: outDir,
    );
    expect(result.ok, isTrue, reason: result.error);
    final text = '${result.result ?? ''}';
    expect(text, isNotEmpty, reason: '清洗脚本应返回 EZBK 文本');

    // 返回内容必须是合规 EZBK：能被解析，且有标题与正文
    final doc = EzbkCodec.parse(text);
    expect(doc.headings, isNotEmpty, reason: '应至少有一个 # 标题');
    expect(doc.toPlainText(), contains('更夫敲梆子'));
    // 清洗只做规范化，**不删正文内容**：广告行必须保留
    expect(doc.toPlainText(), contains('广告：'));
    await outDir.delete(recursive: true);
  });

  test('示例二：假书源搜索（不联网，返回条目）', () async {
    final result = await runExample(
      'examples/plugins/fake_source.js',
      params: {'task': 'search', 'query': '测试'},
    );
    expect(result.ok, isTrue, reason: result.error);
    final payload = result.result as Map;
    final items = (payload['items'] as List).cast<Map>();
    expect(items.length, 3);
    expect(items.first['title'], contains('夜航船'));
    expect(result.logs.join('\n'), contains('命中 3 条'));
    // 新契约：搜索即带回详情与封面字段（不再有独立的 detail 任务）
    expect('${items.first['description']}', isNotEmpty);
    expect(items.first.containsKey('cover'), isTrue);
  });

  test('示例二：关键词 fail 触发失败（错误路径可控）', () async {
    final result = await runExample(
      'examples/plugins/fake_source.js',
      params: {'task': 'search', 'query': 'fail'},
    );
    expect(result.ok, isFalse);
    expect(result.error, contains('fail'));
  });

  test('示例二：下载任务返回章节', () async {
    final result = await runExample(
      'examples/plugins/fake_source.js',
      params: {'task': 'download', 'id': '1'},
    );
    expect(result.ok, isTrue, reason: result.error);
    final payload = result.result as Map;
    final chapters = (payload['chapters'] as List).cast<Map>();
    expect(chapters.first['body'], contains('假数据正文'));
  });
}
