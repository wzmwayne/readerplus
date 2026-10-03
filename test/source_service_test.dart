import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub_importer.dart';
import 'package:reader/services/plugin/script_meta.dart';
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
      format: SourceFormat.script,
      body: 'result("hi")',
      author: '测试',
    );
    await store.upsert(entry);
    final loaded = await store.load();
    expect(loaded.length, 1);
    expect(loaded.first.name, '示例书源');
    expect(loaded.first.format, SourceFormat.script);
    // 未声明类型的脚本按最保守的 tool 处理：不出现在书源页
    expect(loaded.first.kind, ScriptKind.tool);
    expect(loaded.first.isSource, isFalse);

    // 同名 id 覆盖，不追加
    await store.upsert(
      const SourceEntry(id: 'demo', name: '改名', format: SourceFormat.rule, body: '{}'),
    );
    final after = await store.load();
    expect(after.length, 1);
    expect(after.first.name, '改名');
    expect(after.first.format, SourceFormat.rule);
    expect(after.first.kind, ScriptKind.source);
    expect(after.first.isSource, isTrue);

    // 明确声明 kind=source 的脚本才会被当成书源
    await store.upsert(
      const SourceEntry(
        id: 'demo2',
        name: '声明的书源',
        format: SourceFormat.script,
        body: '// @script kind=source\nresult("ok")',
      ),
    );
    final declared = (await store.load()).firstWhere((e) => e.id == 'demo2');
    expect(declared.kind, ScriptKind.source);
    expect(declared.isSource, isTrue);

    await store.remove('demo');
    await store.remove('demo2');
    expect(await store.load(), isEmpty);
    await dir.delete(recursive: true);
  });

  test('服务层：内置假书源（脚本）搜索/详情/下载 + 实时日志', () async {
    final source = await File('assets/plugins/fake_source.ht').readAsString();
    final entry = SourceEntry(
      id: 'fake',
      name: '本地测试书源',
      format: SourceFormat.script,
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
    // 搜索结果自带详情字段（不再有独立的"取详情"）
    expect(items.first['description'], isNotEmpty);
    expect(items.first.containsKey('cover'), isTrue, reason: '每条结果都应带 cover 字段');

    final download = await service.downloadChapters(entry, '1');
    expect(download.chapters.length, 1);
    expect(download.chapters.first.body, contains('假数据正文'));

    // 产物：EPUB 由 Dart 侧组装，应用自己的解析器能读回
    final epub = service.buildEpub(
      title: '假书源产物',
      author: '测试',
      chapters: download.chapters,
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
      format: SourceFormat.script,
      body: source,
    );
    await expectLater(
      service.search(entry, 'fail'),
      throwsA(isA<SourceFailure>()),
    );
  });
}
