import 'dart:convert';
import 'dart:io';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/chapter_paginator.dart';
import 'package:reader/services/backup_service.dart';
import 'package:reader/services/storage.dart';
import 'package:reader/services/txt_importer.dart';

const _sample = '''
《测试小说》
作者：某某

第一章 开端
这是第一章的正文内容。它需要足够长以便触发分页逻辑。
第二行内容。

第二章 发展
第二章的正文内容，同样写一些文字用于测试切分是否正确。

第三章 结局
结束。
''';

void main() {
  group('TXT 导入', () {
    test('按章节标题切分', () {
      final result = TxtImporter.splitChapters(_sample);
      expect(result.chapters.length, 3);
      expect(result.chapters[0].title, contains('第一章'));
      expect(result.chapters[2].title, contains('第三章'));
      // 最后一章结尾应等于全文长度
      expect(result.chapters.last.end, result.content.length);
      // 区间连续且不重叠
      for (var i = 0; i < result.chapters.length - 1; i++) {
        expect(result.chapters[i].end, result.chapters[i + 1].start);
      }
    });

    test('无标题时退化为单章', () {
      final result = TxtImporter.splitChapters('没有任何章节标题的纯文本内容。');
      expect(result.chapters.length, 1);
      expect(result.chapters.single.title, '全文');
    });

    test('UTF-8 与 GBK 解码', () {
      expect(TxtImporter.decodeBytes(utf8.encode('中文测试')), '中文测试');
      expect(TxtImporter.decodeBytes(gbk.encode('中文测试')), '中文测试');
      expect(
        TxtImporter.decodeBytes([0xEF, 0xBB, 0xBF, ...utf8.encode('带BOM')]),
        '带BOM',
      );
    });

    test('从内容猜测书名与作者', () {
      final tmp = File('${Directory.systemTemp.path}/我的小说.txt');
      final meta = TxtImporter.guessMeta(tmp, _sample);
      expect(meta.title, '测试小说');
      expect(meta.author, '某某');
    });
  });

  group('分页引擎', () {
    const style = TextStyle(fontSize: 16, height: 1.6);

    test('长文本被切分为多页且不丢字', () {
      final text = List.generate(120, (i) => '第$i段正文内容，用来把页面撑满。').join('\n');
      final pages = ChapterPaginator.paginate(
        text: text,
        style: style,
        maxWidth: 300,
        maxHeight: 200,
        indent: '　　',
        paragraphSpacing: 6,
      );
      expect(pages.length, greaterThan(1));
      for (final page in pages) {
        expect(page.paragraphs, isNotEmpty);
      }
      // 所有分片拼接后应包含全部段落文本
      final joined = pages
          .expand((p) => p.paragraphs)
          .map((p) => p.text.replaceAll('　　', ''))
          .join();
      for (var i = 0; i < 120; i++) {
        expect(joined.contains('第$i段正文内容，用来把页面撑满。'), isTrue);
      }
    });

    test('空文本返回空页', () {
      final pages = ChapterPaginator.paginate(
        text: '',
        style: style,
        maxWidth: 300,
        maxHeight: 200,
        indent: '',
      );
      expect(pages.length, 1);
      expect(pages.single.paragraphs, isEmpty);
    });
  });

  group('备份格式', () {
    late Directory rootA;
    late Directory rootB;

    setUp(() async {
      rootA = await Directory.systemTemp.createTemp('reader_a');
      rootB = await Directory.systemTemp.createTemp('reader_b');
    });

    tearDown(() async {
      for (final d in [rootA, rootB]) {
        if (await d.exists()) await d.delete(recursive: true);
      }
    });

    test('导出后导入可还原全部文件', () async {
      Storage.overrideRoot(rootA);
      final storageA = await Storage.instance();
      await storageA.writeJson('library.json', {
        'format': 'wzmwayne.reader.library',
        'version': 1,
        'books': [
          {'id': 'b1', 'title': '测试书'},
        ],
      });
      await storageA.writeText('books/b1/content.txt', '正文内容');
      await storageA.writeJson('books/b1/chapters.json', {
        'bookId': 'b1',
        'chapters': [
          {'index': 0, 'title': '第一章', 'start': 0, 'end': 4},
        ],
      });

      final bytes = await BackupService(storageA).export();
      expect(bytes.length, greaterThan(0));

      Storage.overrideRoot(rootB);
      final storageB = await Storage.instance();
      final count = await BackupService(storageB).import(bytes);
      expect(count, 3);
      expect(await storageB.readText('books/b1/content.txt'), '正文内容');
      final lib = await storageB.readJson('library.json');
      expect(lib?['books'], isA<List>());
    });
  });
}
