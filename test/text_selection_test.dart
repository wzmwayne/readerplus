import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/text_selection.dart';

void main() {
  const style = TextStyle(fontSize: 18);

  group('词范围', () {
    test('中文按最多 4 字取词', () {
      const text = '夜色像一层薄薄的墨';
      expect(wordRangeAt(text, 0), [0, 4]);
      expect(wordRangeAt(text, 4), [4, 8]);
    });

    test('英文数字按整词取', () {
      const text = 'hello world_2 test';
      expect(wordRangeAt(text, 1), [0, 5]);
      expect(wordRangeAt(text, 7), [6, 13]);
    });

    test('标点与越界退化为单字符', () {
      expect(wordRangeAt('你，好', 1), [1, 2]);
      expect(wordRangeAt('', 0), [0, 0]);
      expect(wordRangeAt('abc', 99), [0, 3]);
    });
  });

  group('句范围', () {
    test('含句末标点', () {
      const text = '第一句。第二句！第三句';
      expect(sentenceRangeAt(text, 1), [0, 4]);
      expect(sentenceRangeAt(text, 5), [4, 8]);
      expect(sentenceRangeAt(text, 9), [8, 11]);
    });

    test('空文本与越界安全', () {
      expect(sentenceRangeAt('', 3), [0, 0]);
      expect(sentenceRangeAt('没有标点', 99), [0, 4]);
    });
  });

  group('命中测试与选区矩形（与渲染同一套排版参数）', () {
    testWidgets('按点选位置得到字符下标', (tester) async {
      const text = '夜色像一层薄薄的墨';
      late double width;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                width = 200;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      // 行首
      expect(
        charIndexAt(
          text: text,
          style: style,
          maxWidth: width,
          local: const Offset(1, 8),
        ),
        0,
      );
      // 行尾附近应落在靠后的字符上
      final endIndex = charIndexAt(
        text: text,
        style: style,
        maxWidth: width,
        local: const Offset(199, 8),
      );
      expect(endIndex, greaterThan(0));
      expect(endIndex, lessThanOrEqualTo(text.length));
    });


    test('caret 位置用于绘制拖动手柄', () {
      final carets = selectionCarets(
        text: '第一句。第二句。',
        style: style,
        maxWidth: 300,
        start: 4,
        end: 8,
      );
      expect(carets, isNotNull);
      expect(carets!.lineHeight, greaterThan(0));
      expect(carets.end.dx, greaterThan(carets.start.dx));
      expect(
        selectionCarets(
          text: '',
          style: style,
          maxWidth: 300,
          start: 0,
          end: 9,
        ),
        isNull,
      );
    });
    test('选区矩形覆盖选中字符', () {
      const text = '第一句。第二句。';
      final rect = selectionRect(
        text: text,
        style: style,
        maxWidth: 300,
        start: 4,
        end: 8,
      );
      expect(rect, isNotNull);
      expect(rect!.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      expect(
        selectionRect(
          text: text,
          style: style,
          maxWidth: 300,
          start: 4,
          end: 4,
        ),
        isNull,
      );
    });
  });

  group('选择区间', () {
    test('取出选中文本', () {
      const selection = ParagraphSelection(paragraph: 2, start: 1, end: 4);
      expect(selection.textOf('夜色像一层'), '色像一');
      expect(selection.isEmpty, isFalse);
    });

    test('越界不会抛异常', () {
      const selection = ParagraphSelection(paragraph: 0, start: 99, end: 200);
      expect(selection.textOf('短'), '');
    });
  });
}
