import 'package:flutter_test/flutter_test.dart';
import 'package:reader/models/app_settings.dart';

void main() {
  group('书架列数归一化', () {
    test('默认值：竖屏 3、横屏 6', () {
      final settings = AppSettings.fromJson(const {});
      expect(settings.gridColumnsPortrait, 3);
      expect(settings.gridColumnsLandscape, 6);
    });

    test('历史超范围值被裁剪到 1..10（否则 Slider 会断言崩溃）', () {
      final settings = AppSettings.fromJson(const {
        // 旧版迁移曾把 gridColumns 翻倍，产生 12 这种越界值
        'gridColumnsLandscape': 12,
        'gridColumnsPortrait': 0,
      });
      expect(settings.gridColumnsLandscape, 10);
      expect(settings.gridColumnsPortrait, 1);
    });

    test('旧字段 gridColumns 仍可作为回退', () {
      final settings = AppSettings.fromJson(const {'gridColumns': 4});
      expect(settings.gridColumnsPortrait, 4);
      expect(settings.gridColumnsLandscape, 4);
    });

    test('往返保存不丢字段', () {
      final settings = AppSettings.fromJson(const {
        'gridColumnsPortrait': 2,
        'gridColumnsLandscape': 9,
      });
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.gridColumnsPortrait, 2);
      expect(restored.gridColumnsLandscape, 9);
    });
  });
}
