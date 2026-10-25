import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 一段的排版结果：TextPainter 已 layout，可直接 paint。
class ParagraphBox {
  ParagraphBox({
    required this.painter,
    required this.top,
    required this.height,
    required this.text,
  });

  final TextPainter painter;
  final double top;
  final double height;
  final String text;

  void paint(Canvas canvas) => painter.paint(canvas, Offset(0, top));
}

/// 一章的排版结果：段落盒集合 + 总高度。
///
/// 这是 Legado「预排版 + canvas 绘制」在 Flutter 的对应物：
/// 段落只排版一次（TextPainter.layout），之后滚动只是重放绘制指令，
/// 不再有上千个 Text widget 参与布局与光栅。
class ChapterTextLayout {
  ChapterTextLayout._(this.boxes, this.height);

  final List<ParagraphBox> boxes;
  final double height;

  static ChapterTextLayout measure({
    required List<String> paragraphs,
    required TextStyle bodyStyle,
    required TextStyle titleStyle,
    required String indent,
    required double paragraphSpacing,
    required double width,
  }) {
    final boxes = <ParagraphBox>[];
    var y = 0.0;
    final maxWidth = math.max(1.0, width);
    for (var i = 0; i < paragraphs.length; i++) {
      final isTitle = i == 0;
      final text = isTitle ? paragraphs[i] : '$indent${paragraphs[i]}';
      final painter = TextPainter(
        text: TextSpan(text: text, style: isTitle ? titleStyle : bodyStyle),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      final height = painter.height + paragraphSpacing;
      boxes.add(
        ParagraphBox(painter: painter, top: y, height: height, text: text),
      );
      y += height;
    }
    return ChapterTextLayout._(boxes, y);
  }

  /// 给定本章内的 y 偏移，返回落在该处的段落序号（二分）。
  /// 每行在章内的 y 起点（跨段落展开），按行切页用。
  List<double> lineStarts() {
    final out = <double>[];
    for (final box in boxes) {
      final metrics = box.painter.computeLineMetrics();
      var y = box.top;
      for (final m in metrics) {
        out.add(y);
        y += m.height;
      }
    }
    return out;
  }

  /// 按视口高度切页：返回每页起始 y（页高固定 pageHeight）。
  /// 页 = 本章排版的高度切片，切换分页/滚动模式无需重新排版。
  List<double> paginate(double pageHeight) {
    // 逐行判断「这一行放得下吗」：放不下就在该行前切页。
    // 先收集每行的 (起点, 高度)，才能精确控制每页高度不超过视口。
    final linesY = <double>[];
    final linesH = <double>[];
    for (final box in boxes) {
      final metrics = box.painter.computeLineMetrics();
      var y = box.top;
      for (final m in metrics) {
        linesY.add(y);
        linesH.add(m.height);
        y += m.height;
      }
    }
    if (linesY.isEmpty) return const [0];
    final limit = pageHeight <= 1 ? 1.0 : pageHeight;
    final pages = <double>[linesY.first];
    var pageTop = linesY.first;
    for (var i = 0; i < linesY.length; i++) {
      if (linesY[i] - pageTop + linesH[i] > limit) {
        pageTop = linesY[i];
        pages.add(pageTop);
      }
    }
    return pages;
  }

  int paragraphAt(double y) {
    if (boxes.isEmpty) return 0;
    var lo = 0;
    var hi = boxes.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (boxes[mid].top <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// 某段落的顶部 y 偏移。
  double offsetOf(int paragraph) {
    if (boxes.isEmpty) return 0;
    final i = paragraph.clamp(0, boxes.length - 1);
    return boxes[i].top;
  }

  /// 命中测试：本章内 y 偏移 → 段落序号 + 段内字符位置。
  /// 对应 Legado 的 curPage.longPress(x, y)。
  ({int paragraph, TextPosition position})? hitTest(double x, double y) {
    if (boxes.isEmpty) return null;
    final p = paragraphAt(y);
    final box = boxes[p];
    final position = box.painter.getPositionForOffset(Offset(x, y - box.top));
    return (paragraph: p, position: position);
  }

  /// 词边界选择：对应 Legado 用 BreakIterator 选词。
  ({int start, int end}) wordAt(int paragraph, TextPosition position) {
    final box = boxes[paragraph.clamp(0, boxes.length - 1)];
    final word = box.painter.getWordBoundary(position);
    return (start: word.start, end: word.end);
  }

  /// 选区矩形（段内坐标系，含段落顶部偏移），用于绘制高亮。
  List<Rect> selectionRects(int paragraph, int start, int end) {
    if (boxes.isEmpty) return const [];
    final p = paragraph.clamp(0, boxes.length - 1);
    final box = boxes[p];
    final list = box.painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    return [
      for (final b in list)
        Rect.fromLTWH(b.left, box.top + b.top, b.right - b.left, b.bottom - b.top),
    ];
  }

  /// 跨段选区的两个手柄（章内坐标）：起点在首行基线、终点在末行基线下方。
  List<Offset> spanHandles(int p1, int o1, int p2, int o2) {
    if (boxes.isEmpty) return const [];
    final a = boxes[p1.clamp(0, boxes.length - 1)];
    final b = boxes[p2.clamp(0, boxes.length - 1)];
    final startCaret = a.painter.getOffsetForCaret(
      TextPosition(offset: o1.clamp(0, a.text.length)),
      Rect.zero,
    );
    final endCaret = b.painter.getOffsetForCaret(
      TextPosition(offset: o2.clamp(0, b.text.length)),
      Rect.zero,
    );
    return [
      Offset(startCaret.dx, a.top + startCaret.dy),
      Offset(endCaret.dx, b.top + endCaret.dy + b.painter.preferredLineHeight),
    ];
  }

  /// 选区末端的两个游标位置（段内坐标）。
  List<Offset> selectionHandles(int paragraph, int start, int end) {
    if (boxes.isEmpty) return const [];
    final p = paragraph.clamp(0, boxes.length - 1);
    final box = boxes[p];
    final out = <Offset>[];
    for (final off in [start, end]) {
      final caret = box.painter.getOffsetForCaret(
        TextPosition(offset: off),
        Rect.zero,
      );
      final h = box.painter.preferredLineHeight;
      out.add(Offset(caret.dx, box.top + caret.dy + (off >= end ? h : 0)));
    }
    return out;
  }
}

/// 一章的绘制器：画正文，并按需绘制朗读高亮。
class ChapterPainter extends CustomPainter {
  ChapterPainter({
    required this.layout,
    this.highlightParagraph = -1,
    this.highlightRange,
    this.highlightColor,
    this.selP1 = -1,
    this.selO1 = 0,
    this.selP2 = -1,
    this.selO2 = 0,
    this.selectionColor,
    this.handleColor,
  });

  final ChapterTextLayout layout;
  final int highlightParagraph;
  final List<int>? highlightRange;
  final Color? highlightColor;
  final int selP1;
  final int selO1;
  final int selP2;
  final int selO2;
  final Color? selectionColor;
  final Color? handleColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in layout.boxes) {
      box.paint(canvas);
    }
    final range = highlightRange;
    final color = highlightColor;
    if (range != null &&
        color != null &&
        highlightParagraph >= 0 &&
        highlightParagraph < layout.boxes.length &&
        range.length >= 2 &&
        range[1] > range[0]) {
      final box = layout.boxes[highlightParagraph];
      final boxes = box.painter.getBoxesForSelection(
        TextSelection(baseOffset: range[0], extentOffset: range[1]),
      );
      final paint = Paint()..color = color;
      for (final b in boxes) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              b.left,
              box.top + b.top,
              b.right - b.left,
              b.bottom - b.top,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
    }
    final selColor = selectionColor;
    if (selColor != null && selP1 >= 0 && selP2 >= selP1) {
      final p = Paint()..color = selColor;
      // 跨段：逐段画矩形，首段从 O1 起、末段到 O2 止
      for (var i = selP1; i <= selP2 && i < layout.boxes.length; i++) {
        final len = layout.boxes[i].text.length;
        final from = i == selP1 ? selO1.clamp(0, len) : 0;
        final to = i == selP2 ? selO2.clamp(0, len) : len;
        for (final r in layout.selectionRects(i, from, to)) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(2)),
            p,
          );
        }
      }
      final handleColorValue = handleColor;
      final hs = layout.spanHandles(selP1, selO1, selP2, selO2);
      if (handleColorValue != null && hs.length == 2) {
        final hp = Paint()..color = handleColorValue;
        // 起点手柄竖线向上
        canvas.drawCircle(hs[0], 5, hp);
        canvas.drawRect(
          Rect.fromLTWH(hs[0].dx - 1.2, hs[0].dy - 16, 2.4, 16),
          hp,
        );
        // 终点手柄竖线向下
        canvas.drawCircle(hs[1], 5, hp);
        canvas.drawRect(
          Rect.fromLTWH(hs[1].dx - 1.2, hs[1].dy, 2.4, 16),
          hp,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ChapterPainter old) =>
      old.layout != layout ||
      old.highlightParagraph != highlightParagraph ||
      old.highlightColor != highlightColor ||
      old.selP1 != selP1 ||
      old.selO1 != selO1 ||
      old.selP2 != selP2 ||
      old.selO2 != selO2 ||
      !_sameRange(old.highlightRange, highlightRange);

  static bool _sameRange(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}