import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/tts/tts_token.dart';

void main() {
  group('Sec-MS-GEC v2', () {
    test('与参考实现逐字节一致（多时间点金向量）', () {
      const vectors = <int, String>{
        1792326798:
            'E78ACA2247811C68-ED5BCD44E8D29650A935D696DD5E291911BF97B5C6D31B6584F45A0586597D13',
        1792326000:
            '28146D5A060E671F-BDA73489195BC5C375BBFCDCA5B7043A4911E817410B4C4C88A9F5826CFB39A4',
        1600000000:
            '1F5E89103EC98A08-E69D008C1241797258F0EE06F56044C11FAEC4B60F95C6AB0DB3C5E79BE2F010',
        1000000000:
            '5E9153719FADA922-14D2A75113EC5862E17303287DCDB197E3A671DF9FCC53C100D6B27928384B98',
        1750000000:
            'B029A7426816F097-4579D112DC47FC3BF432B499C0A282F427C659474AF9BF5FA33CE2C003F9E9C2',
      };
      vectors.forEach((ts, expected) {
        expect(secMsGecV2(ts.toDouble()), expected, reason: 'ts=\$ts');
      });
    });

    test('同一 5 分钟窗口内相同', () {
      expect(secMsGecV2(1792326798), secMsGecV2(1792326700));
      expect(secMsGecV2(1792326798), isNot(secMsGecV2(1792327100)));
    });

    test('版本号是 v2 格式', () {
      expect(secMsGecVersion, startsWith('2-'));
    });
  });
}
