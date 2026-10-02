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
    this.highlightStyle,
    this.highlightRange,
    this.extraHighlights = const [],
  });

  final String text;
  final TextStyle style;
  final TextStyle? highlightStyle;

  /// 相对 [text] 的高亮区间 `[start, end)`；为空表示不高亮。
  final List<int>? highlightRange;

  /// 额外高亮（例如正文选中区）；与 [highlightRange] 重叠时后者优先。
  final List<({List<int> range, TextStyle style})> extraHighlights;

  @override
  Widget build(BuildContext context) {
    final ranges = <({List<int> range, TextStyle style})>[
      if (highlightRange != null && highlightRange!.length >= 2 &&
          highlightStyle != null)
        (range: highlightRange!, style: highlightStyle!),
      ...extraHighlights,
    ].where((e) => e.range[1] > e.range[0]).toList();

    if (ranges.isEmpty) return Text(text, style: style);

    // 按所有区间边界切段，重叠段取「后加入」的样式（选中优先于朗读高亮）
    final boundaries = <int>{0, text.length};
    for (final item in ranges) {
      boundaries
        ..add(item.range[0].clamp(0, text.length))
        ..add(item.range[1].clamp(0, text.length));
    }
    final points = boundaries.toList()..sort();

    final spans = <InlineSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final from = points[i];
      final to = points[i + 1];
      if (to <= from) continue;
      TextStyle? segmentStyle;
      for (final item in ranges) {
        if (item.range[0] <= from && item.range[1] >= to) {
          segmentStyle = item.style;
        }
      }
      spans.add(
        TextSpan(
          text: text.substring(from, to),
          style: segmentStyle,
        ),
      );
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
