import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/reading_progress.dart';

void main() {
  group('滚动模式段落序号的编码/解码', () {
    test('编码结果为负数，可与翻页模式的字符偏移区分', () {
      for (final i in [0, 1, 4, 1234]) {
        expect(encodeScrollPosition(i), isNegative);
      }
    });

    test('编解码往返一致', () {
      for (final i in [0, 1, 4, 999]) {
        expect(decodeScrollPosition(encodeScrollPosition(i)), i);
      }
    });

    test('非负值视为翻页模式的字符偏移，不当成段落号', () {
      expect(decodeScrollPosition(0), isNull);
      expect(decodeScrollPosition(5000), isNull);
    });

    test('返回 0 段落也能被正确还原（旧的估算方案在这里会死锁在段首）', () {
      expect(decodeScrollPosition(encodeScrollPosition(0)), 0);
    });
  });
}
