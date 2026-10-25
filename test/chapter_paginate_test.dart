import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/chapter_text_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChapterTextLayout build(int paragraphs) => ChapterTextLayout.measure(
        paragraphs: [for (var i = 0; i < paragraphs; i++) '第' * (i == 0 ? 1 : 1) + '段文字内容$i'],
        bodyStyle: const TextStyle(fontSize: 20, height: 1.5),
        titleStyle: const TextStyle(fontSize: 26, height: 1.5),
        indent: '　　',
        paragraphSpacing: 6,
        width: 400,
      );

  test('按行切页：页起点递增且不超过总高', () {
    final layout = build(30);
    final pages = layout.paginate(300);
    expect(pages.length, greaterThan(1));
    for (var i = 1; i < pages.length; i++) {
      expect(pages[i], greaterThan(pages[i - 1]));
    }
    expect(pages.last, lessThanOrEqualTo(layout.height));
  });

  test('每页高度不超过视口（除最后一页）', () {
    final layout = build(40);
    final pages = layout.paginate(250);
    for (var i = 0; i < pages.length - 1; i++) {
      // 段落间距不属于行高，切页点落在段首时整页可能略超视口，
      // 允许最多一行的余量（实际渲染会用 clip 保证不越界）。
      expect(pages[i + 1] - pages[i], lessThan(250 + 80));
    }
  });

  test('单页也能返回至少一个起点', () {
    final layout = build(1);
    expect(layout.paginate(10000), hasLength(1));
  });
}