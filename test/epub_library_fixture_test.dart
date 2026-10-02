import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub_importer.dart';

/// 第三方库产出的 EPUB 兼容性回归：夹具由 EbookLib + lxml 生成
/// （桌面端预置这两者；移动端无 lxml wheel，因此只作兼容性验证）。
void main() {
  test('EbookLib 生成的 EPUB 3 可被内置解析器读回', () async {
    final bytes = await File(
      'test/fixtures/ebooklib_sample.epub',
    ).readAsBytes();
    final book = EpubImporter.parse(bytes);

    expect(book.title, '夜航船');
    expect(book.author, '张岱');
    expect(book.chapters.map((c) => c.title).toList(), [
      '第一章 夜叩门',
      '第二章 旧信笺',
    ]);
    expect(book.content, contains('慢慢洇开在窗棂上'));
    expect(book.content, contains('适合想一些很久以前的事'));
  });
}
