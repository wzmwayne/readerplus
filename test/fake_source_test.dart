import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub_importer.dart';

/// 本地假数据书源脚本的端到端测试（完全离线）：
/// describe → search → detail（含封面文件）→ download（EPUB 可被解析器读回）。
Future<String?> _python() async {
  for (final candidate in ['python3', 'python']) {
    try {
      final result = await Process.run(candidate, ['--version']);
      if (result.exitCode == 0) return candidate;
    } catch (_) {}
  }
  return null;
}

/// 在临时沙盒里跑一次任务，返回沙盒目录与日志。
Future<({Directory root, String log, int code})> _run(
  String python,
  Map<String, dynamic> params,
) async {
  final root = await Directory.systemTemp.createTemp('fake_source');
  Directory('${root.path}/input').createSync();
  Directory('${root.path}/output').createSync();
  File('${root.path}/params.json').writeAsStringSync(jsonEncode(params));
  File('${root.path}/user_script.py').writeAsStringSync(
    await File('python/examples/fake_source.py').readAsString(),
  );
  final result = await Process.run(
    python,
    ['${Directory.current.path}/python/app/main.py'],
    environment: {'SANDBOX_ROOT': root.path},
    includeParentEnvironment: true,
  );
  final logFile = File('${root.path}/log.txt');
  return (
    root: root,
    log: logFile.existsSync() ? logFile.readAsStringSync() : '',
    code: result.exitCode,
  );
}

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  late String? python;
  setUpAll(() async => python = await _python());

  test('describe：读到书源声明与能力', () async {
    if (python == null) return markTestSkipped('本机没有 python3');
    final run = await _run(python!, {'task': 'describe'});
    expect(run.code, 0, reason: run.log);
    final manifest = _json('${run.root.path}/manifest.json');
    expect(manifest['status'], 'ok');
    final script = manifest['script'] as Map<String, dynamic>;
    expect(script['kind'], 'source');
    expect(script['id'], 'fake-local');
    expect(script['capabilities'], ['search', 'detail', 'download']);
    await run.root.delete(recursive: true);
  });

  test('search：返回条目且 id 齐全', () async {
    if (python == null) return markTestSkipped('本机没有 python3');
    final run = await _run(python!, {'task': 'search', 'query': '测试', 'page': 1});
    expect(run.code, 0, reason: run.log);
    final payload = _json('${run.root.path}/output/result.json');
    final items = (payload['items'] as List).cast<Map<String, dynamic>>();
    expect(items.length, 3);
    expect(items.every((item) => (item['id'] as String).isNotEmpty), isTrue);
    expect(items.first['title'], contains('测试'));
    await run.root.delete(recursive: true);
  });

  test('search：关键词 fail 时脚本失败并留下 traceback', () async {
    if (python == null) return markTestSkipped('本机没有 python3');
    final run = await _run(python!, {'task': 'search', 'query': 'fail'});
    expect(run.code, isNot(0));
    final manifest = _json('${run.root.path}/manifest.json');
    expect(manifest['status'], 'error');
    expect(manifest['traceback'], contains('测试用的搜索失败'));
    await run.root.delete(recursive: true);
  });

  test('detail：信息与封面文件都在', () async {
    if (python == null) return markTestSkipped('本机没有 python3');
    final run = await _run(python!, {'task': 'detail', 'book_id': '1'});
    expect(run.code, 0, reason: run.log);
    final payload = _json('${run.root.path}/output/result.json');
    expect(payload['title'], contains('夜航船'));
    expect(payload['cover_file'], 'cover.png');
    final cover = File('${run.root.path}/output/cover.png');
    expect(cover.existsSync(), isTrue);
    // PNG magic
    final bytes = cover.readAsBytesSync();
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    await run.root.delete(recursive: true);
  });

  test('download：产出可被应用解析器读回的 EPUB', () async {
    if (python == null) return markTestSkipped('本机没有 python3');
    final run = await _run(python!, {
      'task': 'download',
      'book_id': '1',
      'output_file': 'book.epub',
    });
    expect(run.code, 0, reason: run.log);
    final bytes = File('${run.root.path}/output/book.epub').readAsBytesSync();
    final book = EpubImporter.parse(bytes);
    expect(book.title, contains('夜航船'));
    expect(book.author, contains('张岱'));
    expect(book.chapters.map((c) => c.title).toList(), [
      '第一章 夜叩门',
      '第二章 旧信笺',
      '第三章 山中客',
    ]);
    expect(book.content, contains('慢慢洇开在窗棂上'));
    await run.root.delete(recursive: true);
  });
}
