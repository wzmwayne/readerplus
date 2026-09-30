import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/page_turn_offsets.dart';

void main() {
  const width = 480.0;

  group('覆盖模式位移（必须区别于滑动模式）', () {
    test('向左拖动翻下一页：当前页不动，下一页从右侧盖上来', () {
      expect(coverCurrentOffset(-50), 0, reason: '当前页应保持不动');
      expect(coverNextOffset(-50, width), width - 50);
      expect(coverPrevOffset(-50), 0);
    });

    test('向右拖动回翻：上一页留在原位，当前页向右移出', () {
      expect(coverPrevOffset(60), 0, reason: '上一页应留在原位当底页');
      expect(coverCurrentOffset(60), 60);
    });

    test('松手位置：下一页拖满一屏正好贴合', () {
      expect(coverNextOffset(-width, width), 0);
      expect(coverNextOffset(0, width), width);
    });

    test('与滑动模式的关键差异：任一时刻只有一页在移动', () {
      // 向左拖：当前页位移恒为 0（滑动模式则等于 drag）
      for (final drag in [-20.0, -120.0, -300.0]) {
        expect(coverCurrentOffset(drag), 0);
      }
      // 向右拖：下一页始终在屏外等待，不参与移动
      for (final drag in [20.0, 120.0, 300.0]) {
        expect(coverNextOffset(drag, width), greaterThanOrEqualTo(width));
      }
    });
  });
}
