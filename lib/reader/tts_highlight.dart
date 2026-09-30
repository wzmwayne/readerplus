import 'package:flutter/material.dart';

/// 段落文本：当朗读句与本段有交集时，把交集部分单独着色。
///
/// 独立成组件便于直接做 widget 测试（不依赖阅读器整体状态）。
class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.style,
    required this.highlightStyle,
    this.highlightRange,
  });

  final String text;
  final TextStyle style;
  final TextStyle highlightStyle;

  /// 相对 [text] 的高亮区间 `[start, end)`；为空表示不高亮。
  final List<int>? highlightRange;

  @override
  Widget build(BuildContext context) {
    final range = highlightRange;
    if (range == null || range.length < 2 || range[1] <= range[0]) {
      return Text(text, style: style);
    }
    final from = range[0].clamp(0, text.length);
    final to = range[1].clamp(from, text.length);
    if (to <= from) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (from > 0) TextSpan(text: text.substring(0, from)),
          TextSpan(text: text.substring(from, to), style: highlightStyle),
          if (to < text.length) TextSpan(text: text.substring(to)),
        ],
      ),
    );
  }
}
