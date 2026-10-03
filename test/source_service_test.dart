import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub_importer.dart';
import 'package:reader/services/plugin/source_service.dart';
import 'package:reader/services/plugin/source_store.dart';

void main() {
  const service = SourceService();

  test('书源仓储：写入 / 读取 / 删除（单文件、位置可注入）', () async {
    final dir = await Directory.systemTemp.createTemp('source_store');
    final store = SourceStore(root: () async => dir);
    expect(await store.load(), isEmpty);

    const entry = SourceEntry(
      id: 'demo',
      name: '示例书源',
      kind: SourceKind.script,
      body: 'result("hi")',
      author: '测试',
    );
    await store.upsert(entry);
    final loaded = await store.load();
    expect(loaded.length, 1);
    expect(loaded.first.name, '示例书源');
    expect(loaded.first.kind, SourceKind.script);
    expect(loaded.first.capabilities, containsAll(['search', 'detail', 'download']));

    // 同名 id 覆盖，不追加
    await store.upsert(
      const SourceEntry(id: 'demo', name: '改名', kind: SourceKind.rule, body: '{}'),
    );
    final after = await store.load();
    expect(after.length, 1);
    expect(after.first.name, '改名');
    expect(after.first.kind, SourceKind.rule);
    expect(after.first.capabilities, {'search'});

    await store.remove('demo');
    expect(await store.load(), isEmpty);
    await dir.delete(recursive: true);
  });

  test('服务层：内置假书源（脚本）搜索/详情/下载 + 实时日志', () async {
    final source = await File('assets/plugins/fake_source.ht').readAsString();
    final entry = SourceEntry(
      id: 'fake',
      name: '本地测试书源',
      kind: SourceKind.script,
      body: source,
    );

    final logs = <String>[];
    final items = await service.search(
      entry,
      '测试',
      onLog: logs.add,
    );
    expect(items.length, 3);
    expect(items.first['title'], contains('夜航船'));
    expect(logs.join('\n'), contains('命中 3 条'), reason: '日志应实时回调');

    final detail = await service.detail(entry, '1');
    expect(detail['title'], contains('夜航船'));
    expect(detail['description'], isNotEmpty);

    final chapters = await service.downloadChapters(entry, '1');
    expect(chapters.length, 1);
    expect(chapters.first.body, contains('假数据正文'));

    // 产物：EPUB 由 Dart 侧组装，应用自己的解析器能读回
    final epub = service.buildEpub(
      title: '假书源产物',
      author: '测试',
      chapters: chapters,
    );
    final book = EpubImporter.parse(epub);
    expect(book.title, '假书源产物');
    expect(book.content, contains('假数据正文'));
  });

  test('服务层：搜索失败时抛出带原因的异常（错误路径可控）', () async {
    final source = await File('assets/plugins/fake_source.ht').readAsString();
    final entry = SourceEntry(
      id: 'fake',
      name: '本地测试书源',
      kind: SourceKind.script,
      body: source,
    );
    await expectLater(
      service.search(entry, 'fail'),
      throwsA(isA<StateError>()),
    );
  });
}
