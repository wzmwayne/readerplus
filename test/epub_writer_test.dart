import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub/epub_writer.dart';
import 'package:reader/services/epub_importer.dart';

void main() {
  group('EPUB 3 写出模块', () {
    test('结构与规范要点', () {
      final writer = EpubWriter(
        title: '规范测试 & <书名>',
        author: '作者"甲"',
        identifier: 'urn:uuid:11111111-2222-4333-8444-555555555555',
        modified: DateTime.utc(2026, 10, 3, 6, 0, 0),
      )
        ..addChapter('第一章 起', '第一段。\n第二段 & 符号 <x>。')
        ..addChapter('第二章 承', '另一段。');
      final bytes = writer.build();

      // mimetype 必须第一个且 STORED
      expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      final nameLength = bytes[26] | (bytes[27] << 8);
      expect(utf8.decode(bytes.sublist(30, 30 + nameLength)), 'mimetype');
      expect(bytes[8] | (bytes[9] << 8), 0, reason: 'mimetype 必须不压缩');

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.first.name, 'mimetype');
      final opf = utf8.decode(
        archive.findFile('OEBPS/package.opf')!.content as List<int>,
      );
      expect(opf, contains('version="3.0"'));
      expect(opf, contains('<dc:language>zh-CN</dc:language>'));
      expect(opf, contains('property="dcterms:modified"'));
      expect(opf, contains('2026-10-03T06:00:00Z'));
      expect(opf, contains('properties="nav"'));
      expect(opf, contains('urn:uuid:11111111-2222-4333-8444-555555555555'));
      // 转义正确
      expect(opf, contains('规范测试 &amp; &lt;书名&gt;'));
      expect(opf, contains('作者&quot;甲&quot;'));

      final container = utf8.decode(
        archive.findFile('META-INF/container.xml')!.content as List<int>,
      );
      expect(
        container,
        contains('urn:oasis:names:tc:opendocument:xmlns:container'),
      );
      expect(container, contains('OEBPS/package.opf'));

      final nav = utf8.decode(
        archive.findFile('OEBPS/nav.xhtml')!.content as List<int>,
      );
      expect(nav, contains('epub:type="toc"'));
      expect(nav, contains('chapter1.xhtml'));

      // 应用自己的解析器能读回
      final book = EpubImporter.parse(bytes);
      expect(book.title, '规范测试 & <书名>');
      expect(book.chapters.map((c) => c.title).toList(), ['第一章 起', '第二章 承']);
      expect(book.content, contains('第二段 & 符号 <x>'));
    });

    test('封面：cover-image 属性 + 清单项', () {
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic
        ...List.filled(64, 0),
      ]);
      final writer = EpubWriter(title: '带封面')
        ..addChapter('一', '正文')
        ..setCover(png, fileName: 'cover.png');
      final archive = ZipDecoder().decodeBytes(writer.build());
      final opf = utf8.decode(
        archive.findFile('OEBPS/package.opf')!.content as List<int>,
      );
      expect(opf, contains('properties="cover-image"'));
      expect(opf, contains('media-type="image/png"'));
      expect(archive.findFile('OEBPS/cover.png'), isNotNull);
    });

    test('生成样例文件供 EPUBCheck 校验', () async {
      final writer = EpubWriter(
        title: 'EPUBCheck 样例',
        author: '测试',
        identifier: 'urn:uuid:aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        modified: DateTime.utc(2026, 10, 3, 6, 0, 0),
      )
        ..addChapter('第一章 夜叩门', '夜色像一层薄薄的墨。\n他放下手中的书。')
        ..addChapter('第二章 旧信笺', '茶已经凉了，他却舍不得起身。');
      final bytes = writer.build();
      final out = File('/tmp/epub_check_sample.epub');
      await out.writeAsBytes(bytes, flush: true);
      expect(out.existsSync(), isTrue);
    });
  });
}
