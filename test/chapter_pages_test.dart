import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/chapter_text_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChapterTextLayout build(int n) => ChapterTextLayout.measure(
        paragraphs: [for (var i = 0; i < n; i++) '第' + i.toString() + '段文字内容用于分页测试'],
        bodyStyle: const TextStyle(fontSize: 20, height: 1.5),
        titleStyle: const TextStyle(fontSize: 26, height: 1.5),
        indent: '　　',
        paragraphSpacing: 6,
        width: 400,
      );

  test('页切片：页数 > 1，页顶严格递增，页高不超过视口', () {
    final layout = build(40);
    final pages = layout.pages(240);
    expect(pages.length, greaterThan(1));
    for (var i = 1; i < pages.length; i++) {
      expect(pages[i].top, greaterThan(pages[i - 1].top));
    }
    for (var i = 0; i < pages.length - 1; i++) {
      expect(pages[i].height, lessThanOrEqualTo(240));
    }
  });

  test('页覆盖行区间连续且不重叠', () {
    final layout = build(30);
    final pages = layout.pages(200);
    for (var i = 1; i < pages.length; i++) {
      expect(pages[i].startLine, pages[i - 1].endLine + 1);
    }
  });

  test('小内容只有一页', () {
    final layout = build(1);
    expect(layout.pages(10000).length, 1);
  });
}
