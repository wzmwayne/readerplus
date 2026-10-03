import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub_importer.dart';
import 'package:reader/services/txt/txt_to_epub.dart';

void main() {
  group('纯 Dart TXT → EPUB', () {
    test('UTF-8 测试书：分章、清洗、可被应用解析器读回', () async {
      final bytes = await TxtToEpub.fromFile(
        File('test/fixtures/sample_book.txt'),
        title: '夜航船（测试）',
        author: '测试作者',
        rules: [
          [r'[\u200b\ufeff]', ''],
          [r'(?m)^\s*(广告|推广)[:：].*$', ''],
        ],
      );
      final book = EpubImporter.parse(bytes);
      expect(book.title, '夜航船（测试）');
      expect(book.author, '测试作者');
      expect(book.chapters.map((c) => c.title).toList(), [
        '第一章 夜叩门',
        '第二章 旧信笺',
        '第三章 山中客',
      ]);
      expect(book.content, contains('更夫敲梆子'));
      expect(book.content, isNot(contains('广告：更多精彩内容')));
    });

    test('GBK 编码自动识别，不乱码', () async {
      final utf8Text = await File('test/fixtures/sample_book.txt').readAsString();
      final gbkBytes = gbk.encode(utf8Text);
      final decoded = TxtToEpub.decode(gbkBytes);
      expect(decoded, contains('更夫敲梆子'));

      final epub = TxtToEpub.buildEpub(
        title: 'GBK 测试',
        chapters: TxtToEpub.splitChapters(decoded, TxtToEpub.defaultChapterPattern),
      );
      final book = EpubImporter.parse(epub);
      expect(book.chapters.length, 3);
      expect(book.content, contains('檐角还在滴着水'));
    });

    test('mimetype 必须是第一个条目且不压缩（EPUB 规范硬要求）', () async {
      final epub = TxtToEpub.buildEpub(
        title: 't',
        chapters: [(title: '一', body: '正文')],
      );
      // 第一段本地文件头：签名 50 4B 03 04，随后 name 长度与内容
      expect(epub.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      final nameLength = epub[26] | (epub[27] << 8);
      final name = utf8.decode(epub.sublist(30, 30 + nameLength));
      final method = epub[8] | (epub[9] << 8);
      expect(name, 'mimetype');
      expect(method, 0, reason: 'mimetype 必须 STORED');

      final archive = ZipDecoder().decodeBytes(epub);
      expect(archive.files.first.name, 'mimetype');
    });

    test('没有章标题时整本当一章', () {
      final chapters = TxtToEpub.splitChapters('就是一段普通文字。', TxtToEpub.defaultChapterPattern);
      expect(chapters.length, 1);
      expect(chapters.first.body, contains('普通文字'));
    });

    test('兼容内联标志 (?m)/(?i)/(?s)（Dart RegExp 原生不支持）', () {
      final text = '广告：下载App\n正文一\n正文二';
      expect(
        TxtToEpub.applyRules(text, [
          [r'(?m)^\s*广告.*$', ''],
        ]),
        isNot(contains('广告')),
      );
      expect(
        TxtToEpub.applyRules('ABC', [
          [r'(?i)abc', 'ok'],
        ]),
        'ok',
      );
      expect(
        TxtToEpub.applyRules('a\nb', [
          [r'(?s)a.b', 'ok'],
        ]),
        'ok',
      );
    });
  });
}
