import 'package:flutter/material.dart';

/// 朗读高亮底色（橙色）。
const Color kReadAloudHighlight = Color(0xFFFFB74D);

/// 朗读高亮的文字样式：背景橙色 + 加粗。
///
/// 这里的「加粗」通过同色微偏移阴影实现，**不修改 fontWeight**：
/// 真正加粗会改变字形推进宽度，导致换行位置变化，进而使渲染高度超出
/// 分页计算结果（曾实测溢出 2.7px）。阴影描粗在视觉上同样变粗，
/// 但字体度量与正文完全一致，分页结果始终成立。
TextStyle readAloudHighlightStyle(TextStyle base) {
  final color = base.color ?? const Color(0xFF000000);
  return base.copyWith(
    backgroundColor: kReadAloudHighlight,
    shadows: [
      Shadow(color: color, offset: const Offset(0.6, 0)),
      Shadow(color: color, offset: const Offset(-0.6, 0)),
      Shadow(color: color, offset: const Offset(0, 0.5)),
    ],
  );
}

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
