import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/chapter_paginator.dart';

/// 用与分页相同的样式与缩放测量「一页」的实际高度，
/// 用于验证分页结果确实不超过可用高度（杜绝显示不全）。
double measurePage(
  ReaderPageContent page, {
  required TextStyle style,
  required double maxWidth,
  required TextScaler scaler,
}) {
  var total = 0.0;
  for (final para in page.paragraphs) {
    final painter = TextPainter(
      text: TextSpan(text: para.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);
    total += painter.height + para.gapAfter;
    painter.dispose();
  }
  return total;
}

void main() {
  const style = TextStyle(fontSize: 18, height: 1.55);
  final text = List.generate(
    80,
    (i) => '第$i段正文内容，用来把页面撑满，长度略微不同以模拟真实排版。',
  ).join('\n');

  group('分页不会超出可用高度', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      test('字体缩放 $scale 倍时每页高度均不超过上限', () {
        final scaler = TextScaler.linear(scale);
        const maxWidth = 320.0;
        const maxHeight = 420.0;
        final pages = ChapterPaginator.paginate(
          text: text,
          style: style,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          indent: '　　',
          paragraphSpacing: 8,
          textScaler: scaler,
        );
        expect(pages.length, greaterThan(1));
        for (final page in pages) {
          expect(page.paragraphs, isNotEmpty);
          final measured = measurePage(
            page,
            style: style,
            maxWidth: maxWidth,
            scaler: scaler,
          );
          // 允许 0.5px 的浮点误差
          expect(
            measured,
            lessThanOrEqualTo(maxHeight + 0.5),
            reason: '第 ${page.firstLine} 行起的页面高度 $measured 超过 $maxHeight',
          );
        }
      });
    }

    test('字体放大后页数增多（说明按实时尺寸重新计算）', () {
      final small = ChapterPaginator.paginate(
        text: text,
        style: style,
        maxWidth: 320,
        maxHeight: 420,
        indent: '　　',
        paragraphSpacing: 8,
        textScaler: TextScaler.noScaling,
      );
      final large = ChapterPaginator.paginate(
        text: text,
        style: style,
        maxWidth: 320,
        maxHeight: 420,
        indent: '　　',
        paragraphSpacing: 8,
        textScaler: const TextScaler.linear(2),
      );
      expect(large.length, greaterThan(small.length));
    });

    test('窗口很小时也不会死循环，且各页都有内容', () {
      final pages = ChapterPaginator.paginate(
        text: text,
        style: style,
        maxWidth: 120,
        maxHeight: 30,
        indent: '　　',
        paragraphSpacing: 8,
      );
      expect(pages, isNotEmpty);
      expect(pages.every((p) => p.paragraphs.isNotEmpty), isTrue);
    });
  });

  group('行号与页的映射（进度按章节 + 行号）', () {
    test('行号可稳定映射到页，且与页面区间一致', () {
      final pages = ChapterPaginator.paginate(
        text: text,
        style: style,
        maxWidth: 320,
        maxHeight: 420,
        indent: '　　',
        paragraphSpacing: 8,
      );
      for (var i = 0; i < pages.length; i++) {
        expect(ChapterPaginator.pageIndexForLine(pages, pages[i].firstLine), i);
        expect(ChapterPaginator.pageIndexForLine(pages, pages[i].lastLine), i);
      }
      // 越界行号回落到最接近的页
      expect(ChapterPaginator.pageIndexForLine(pages, -5), 0);
      expect(ChapterPaginator.pageIndexForLine(pages, 999999), pages.length - 1);
    });

    test('每页行号区间连续且递增', () {
      final pages = ChapterPaginator.paginate(
        text: text,
        style: style,
        maxWidth: 320,
        maxHeight: 420,
        indent: '　　',
        paragraphSpacing: 8,
      );
      expect(pages.first.firstLine, 0);
      for (var i = 1; i < pages.length; i++) {
        expect(pages[i].firstLine, pages[i - 1].lastLine + 1);
      }
    });
  });
}
