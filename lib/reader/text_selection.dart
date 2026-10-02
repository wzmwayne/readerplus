import 'package:flutter/rendering.dart';

/// 一段正文里的选择区间（段落序号 + 段内字符范围）。
class ParagraphSelection {
  const ParagraphSelection({
    required this.paragraph,
    required this.start,
    required this.end,
  });

  final int paragraph;
  final int start;
  final int end;

  bool get isEmpty => end <= start;

  String textOf(String paragraphText) =>
      paragraphText.substring(start.clamp(0, paragraphText.length),
          end.clamp(0, paragraphText.length));

  ParagraphSelection copyWith({int? paragraph, int? start, int? end}) =>
      ParagraphSelection(
        paragraph: paragraph ?? this.paragraph,
        start: start ?? this.start,
        end: end ?? this.end,
      );
}

bool _isCjk(int code) =>
    (code >= 0x4E00 && code <= 0x9FFF) ||
    (code >= 0x3400 && code <= 0x4DBF) ||
    (code >= 0xF900 && code <= 0xFAFF);

bool _isWordChar(int code) {
  if (_isCjk(code)) return true;
  // 英文字母、数字、下划线、撇号
  return (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code == 0x5F ||
      code == 0x27;
}

bool _isSentenceEnd(int code) {
  const enders = [0x3002, 0xFF01, 0xFF1F, 0x21, 0x3F, 0x2026, 0xFF1B, 0x3B];
  return enders.contains(code) || code == 0x0A;
}

/// 以 [index] 所在位置的「词」为范围。中文按连续汉字（最多 4 字）取，
/// 英文数字按整词取；标点/空白处退化为单字符。
List<int> wordRangeAt(String text, int index) {
  if (text.isEmpty) return const [0, 0];
  final i = index.clamp(0, text.length - 1);
  if (!_isWordChar(text.codeUnitAt(i))) return [i, i + 1];

  var start = i;
  var end = i + 1;
  final cjk = _isCjk(text.codeUnitAt(i));
  if (cjk) {
    // 中文按最长 4 字的词取，避免一次选中整段
    var count = 1;
    // 先向右扩展到词末，再用剩余额度向左补，保证「点哪里选到哪里的词」
    while (end < text.length && _isCjk(text.codeUnitAt(end)) && count < 4) {
      end++;
      count++;
    }
    while (start > 0 && _isCjk(text.codeUnitAt(start - 1)) && count < 4) {
      start--;
      count++;
    }
  } else {
    while (start > 0 && _isWordChar(text.codeUnitAt(start - 1))) {
      start--;
    }
    while (end < text.length && _isWordChar(text.codeUnitAt(end))) {
      end++;
    }
  }
  return [start, end];
}

/// 以 [index] 所在位置的句子为范围（句末标点/换行为界，含标点）。
List<int> sentenceRangeAt(String text, int index) {
  if (text.isEmpty) return const [0, 0];
  final i = index.clamp(0, text.length - 1);
  var start = i;
  while (start > 0 && !_isSentenceEnd(text.codeUnitAt(start - 1))) {
    start--;
  }
  var end = i;
  while (end < text.length && !_isSentenceEnd(text.codeUnitAt(end))) {
    end++;
  }
  if (end < text.length) end++; // 含句末标点
  return [start, end];
}

TextPainter _layout(String text, TextStyle style, double maxWidth) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth <= 0 ? double.infinity : maxWidth);

/// 选区两端 caret 的位置（相对段落左上角）与行高，用于绘制拖动手柄。
({Offset start, Offset end, double lineHeight})? selectionCarets({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required int start,
  required int end,
}) {
  if (text.isEmpty) return null;
  final painter = _layout(text, style, maxWidth);
  final from = start.clamp(0, text.length);
  final to = end.clamp(0, text.length);
  return (
    start: painter.getOffsetForCaret(TextPosition(offset: from), Rect.zero),
    end: painter.getOffsetForCaret(TextPosition(offset: to), Rect.zero),
    lineHeight: painter.preferredLineHeight,
  );
}

/// 用与渲染一致的排版参数做命中测试，返回字符下标。
int charIndexAt({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required Offset local,
}) {
  if (text.isEmpty) return 0;
  final painter = _layout(text, style, maxWidth);
  final position = painter.getPositionForOffset(local);
  return position.offset.clamp(0, text.length);
}

/// 选择区间在段落内的矩形（用于把操作菜单定位到选区上方）。
Rect? selectionRect({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required int start,
  required int end,
}) {
  if (text.isEmpty || end <= start) return null;
  final painter = _layout(text, style, maxWidth);
  final boxes = painter.getBoxesForSelection(
    TextSelection(
      baseOffset: start.clamp(0, text.length),
      extentOffset: end.clamp(0, text.length),
    ),
  );
  if (boxes.isEmpty) return null;
  var rect = boxes.first.toRect();
  for (final box in boxes.skip(1)) {
    rect = rect.expandToInclude(box.toRect());
  }
  return rect;
}
