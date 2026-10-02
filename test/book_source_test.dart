import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/plugin/book_source.dart';
import 'package:reader/services/plugin/plugin_runner.dart';
import 'package:reader/services/plugin/plugin_sandbox.dart';

/// 假运行时：按 params.json 的 task 产出对应文件，模拟一个书源脚本。
class FakeSourceRuntime implements PluginRuntime {
  final List<String> tasks = [];

  @override
  Future<void> runSandbox(String sandboxPath, {required bool audit}) async {
    final params =
        jsonDecode(File('$sandboxPath/params.json').readAsStringSync())
            as Map<String, dynamic>;
    final task = params['task'] as String? ?? '';
    tasks.add(task);
    final output = Directory('$sandboxPath/output');

    switch (task) {
      case 'search':
        if (params['query'] == 'empty') return;
        File('${output.path}/result.json').writeAsStringSync(
          jsonEncode({
            'items': [
              {'id': '11', 'title': '爱丽丝', 'author': '卡罗尔', 'cover': 'http://x/1.jpg'},
              {'id': '22', 'title': '傲慢与偏见', 'author': '奥斯汀'},
              {'title': '无 id 的条目（应被忽略）'},
            ],
          }),
        );
      case 'detail':
        File('${output.path}/result.json').writeAsStringSync(
          jsonEncode({
            'id': params['book_id'],
            'title': '爱丽丝',
            'author': '卡罗尔',
            'description': '一段简介',
            'cover_file': 'cover.jpg',
          }),
        );
        File('${output.path}/cover.jpg').writeAsBytesSync([1, 2, 3, 4]);
      case 'download':
        File('${output.path}/book.epub').writeAsStringSync('EPUB-BYTES');
    }
    File('$sandboxPath/manifest.json').writeAsStringSync(
      jsonEncode({'status': 'ok', 'outputs': output.listSync().map((f) => f.uri.pathSegments.last).toList()}),
    );
  }

  @override
  void cancel() {}
}

void main() {
  late Directory jobs;
  late FakeSourceRuntime runtime;
  late BookSourceService service;
  late PluginScript script;

  setUp(() async {
    jobs = await Directory.systemTemp.createTemp('source_test');
    runtime = FakeSourceRuntime();
    service = BookSourceService(
      runner: PluginRunner(runtime: runtime),
      jobsRoot: () async => jobs,
      auditEnabled: () => false,
    );
    script = PluginScript(
      id: 's1',
      name: '测试书源',
      source: 'SCRIPT = {}',
      task: PluginTask.source,
    );
  });

  tearDown(() async {
    if (jobs.existsSync()) await jobs.delete(recursive: true);
  });

  test('搜索：解析 result.json 的条目并忽略无 id 项', () async {
    final items = await service.search(script: script, query: '爱丽丝', page: 2);
    expect(runtime.tasks, ['search']);
    expect(items.length, 2);
    expect(items.first.id, '11');
    expect(items.first.title, '爱丽丝');
    expect(items.first.coverUrl, 'http://x/1.jpg');
    expect(items[1].author, '奥斯汀');
  });

  test('详情：带回简介与封面字节，并清理沙盒', () async {
    final detail = await service.detail(script: script, bookId: '11');
    expect(detail.item.id, '11');
    expect(detail.description, '一段简介');
    expect(detail.coverName, 'cover.jpg');
    expect(detail.coverBytes, [1, 2, 3, 4]);
    // 调用方读完即清理
    expect(jobs.listSync(), isEmpty);
  });

  test('下载：产物文件保留在沙盒中供导入', () async {
    final result = await service.download(script: script, bookId: '11');
    expect(result.ok, isTrue);
    expect(result.outputs.single.path, endsWith('book.epub'));
    expect(File(result.outputs.single.path).readAsStringSync(), 'EPUB-BYTES');
    await Directory(result.sandboxPath).delete(recursive: true);
  });

  test('脚本没有输出 result.json 时抛出清晰错误', () async {
    await expectLater(
      service.search(script: script, query: 'empty'),
      throwsA(isA<StateError>()),
    );
  });
}
