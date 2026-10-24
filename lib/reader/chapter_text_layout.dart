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
}

/// 一章的绘制器：画正文，并按需绘制朗读高亮。
class ChapterPainter extends CustomPainter {
  ChapterPainter({
    required this.layout,
    this.highlightParagraph = -1,
    this.highlightRange,
    this.highlightColor,
  });

  final ChapterTextLayout layout;
  final int highlightParagraph;
  final List<int>? highlightRange;
  final Color? highlightColor;

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
  }

  @override
  bool shouldRepaint(covariant ChapterPainter old) =>
      old.layout != layout ||
      old.highlightParagraph != highlightParagraph ||
      old.highlightColor != highlightColor ||
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