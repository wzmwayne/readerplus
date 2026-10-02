import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/tts_highlight.dart';

void main() {
  const style = TextStyle(fontSize: 16);
  const mark = Color(0x55FF0000);

  /// 递归收集所有 TextSpan，避免依赖 Text.rich 的内部嵌套层次。
  List<TextSpan> collect(InlineSpan span) {
    final result = <TextSpan>[];
    if (span is TextSpan) {
      result.add(span);
      for (final child in span.children ?? const <InlineSpan>[]) {
        result.addAll(collect(child));
      }
    }
    return result;
  }

  testWidgets('当前朗读句被高亮，其余保持普通样式', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HighlightedText(
            text: '甲乙丙丁。戊己庚辛。',
            style: style,
            highlightStyle: style.copyWith(backgroundColor: mark),
            highlightRange: const [5, 10],
          ),
        ),
      ),
    );
    final spans = collect(tester.widget<RichText>(find.byType(RichText)).text);

    final highlighted = spans
        .where((s) => s.style?.backgroundColor == mark)
        .toList();
    expect(highlighted.length, 1);
    expect(highlighted.single.text, '戊己庚辛。');

    final plain = spans.where((s) => s.text == '甲乙丙丁。').toList();
    expect(plain.length, 1);
    expect(plain.single.style?.backgroundColor, isNull);
  });

  testWidgets('高亮区间在段落中部时前后都保留', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HighlightedText(
            text: '0123456789',
            style: style,
            highlightStyle: style.copyWith(backgroundColor: mark),
            highlightRange: const [3, 6],
          ),
        ),
      ),
    );
    final spans = collect(tester.widget<RichText>(find.byType(RichText)).text);
    expect(spans.where((s) => s.style?.backgroundColor == mark).single.text, '345');
    expect(spans.any((s) => s.text == '012'), isTrue);
    expect(spans.any((s) => s.text == '6789'), isTrue);
  });

  testWidgets('高亮样式不改动文字度量（否则会破坏分页）', (tester) async {
    // 橙色背景 + 视觉加粗，但字号/行高/字距/字重/字体必须与正文完全一致
    final highlight = readAloudHighlightStyle(style);
    expect(highlight.backgroundColor, kReadAloudHighlight);
    expect(highlight.shadows, isNotEmpty, reason: '用阴影描粗实现加粗');
    expect(highlight.fontWeight, style.fontWeight, reason: '不得真的改字重');
    expect(highlight.fontSize, style.fontSize);
    expect(highlight.height, style.height);
    expect(highlight.letterSpacing, style.letterSpacing);
    expect(highlight.fontWeight, style.fontWeight);
    expect(highlight.fontFamily, style.fontFamily);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HighlightedText(
            text: '度量一致',
            style: style,
            highlightStyle: highlight,
            highlightRange: const [0, 4],
          ),
        ),
      ),
    );
    final spans = collect(tester.widget<RichText>(find.byType(RichText)).text);
    final marked = spans
        .where((s) => s.style?.backgroundColor == kReadAloudHighlight)
        .single;
    expect(marked.text, '度量一致');
    expect(marked.style?.fontWeight, style.fontWeight);
    expect(marked.style?.fontSize, style.fontSize);
  });

  testWidgets('没有朗读句时是普通文本', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HighlightedText(
            text: '没有高亮',
            style: style,
            highlightStyle: style.copyWith(backgroundColor: mark),
          ),
        ),
      ),
    );
    final spans = collect(tester.widget<RichText>(find.byType(RichText)).text);
    expect(spans.any((s) => s.style?.backgroundColor == mark), isFalse);
    expect(spans.any((s) => s.text == '没有高亮'), isTrue);
  });

  testWidgets('越界或空区间不会抛异常', (tester) async {
    for (final range in <List<int>?>[
      const [50, 80],
      const [2, 2],
      const [5, 1],
      const [],
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HighlightedText(
              text: '短文本',
              style: style,
              highlightStyle: style.copyWith(backgroundColor: mark),
              highlightRange: range,
            ),
          ),
        ),
      );
      expect(find.byType(RichText), findsOneWidget);
    }
  });
}
