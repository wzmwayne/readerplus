import 'package:flutter_test/flutter_test.dart';
import 'package:reader/models/reader_settings.dart';
import 'package:reader/services/tts/edge_tts_client.dart';

void main() {
  group('Sec-MS-GEC 令牌（v2）', () {
    test('为「16 位 CS64-64 位 SHA256」大写十六进制', () {
      final token = EdgeTtsClient.secMsGec(DateTime.utc(2026, 9, 30, 12, 0, 0));
      expect(RegExp(r'^[0-9A-F]{16}-[0-9A-F]{64}$').hasMatch(token), isTrue,
          reason: token);
    });

    test('同一 5 分钟窗口内一致，跨窗口变化', () {
      final a = EdgeTtsClient.secMsGec(DateTime.utc(2026, 9, 30, 12, 0, 10));
      final b = EdgeTtsClient.secMsGec(DateTime.utc(2026, 9, 30, 12, 4, 59));
      final c = EdgeTtsClient.secMsGec(DateTime.utc(2026, 9, 30, 12, 5, 1));
      expect(a, b);
      expect(c, isNot(a));
    });

    test('与参考实现（edge-tts drm.py 的 v2）逐字节一致', () {
      // 期望值由 edge-tts 的 generate_sec_ms_gec_v2 独立算出
      expect(
        EdgeTtsClient.secMsGec(DateTime.utc(2026, 9, 30, 12, 0, 0)),
        '1DF20094175DAA65-846235ECFFDDE3C41F40CCCE668A963427B1BBD80B65AF39823B1487B53E8F89',
      );
    });
  });

  group('SSML 构造', () {
    test('包含音色与文本，并转义 XML 特殊字符', () {
      final ssml = EdgeTtsClient.buildSsml(
        voice: 'zh-CN-XiaoxiaoNeural',
        text: '他说 <你好> & "再见"。',
        rate: '+10%',
        pitch: '+0Hz',
      );
      expect(ssml, contains("name='zh-CN-XiaoxiaoNeural'"));
      expect(ssml, contains("rate='+10%'"));
      expect(ssml, contains('&lt;你好&gt;'));
      expect(ssml, contains('&amp;'));
      expect(ssml, contains('&quot;再见&quot;'));
      expect(ssml, isNot(contains('<你好>')));
    });
  });

  group('中文音色筛选', () {
    final raw = [
      {
        'ShortName': 'zh-CN-XiaoxiaoNeural',
        'Locale': 'zh-CN',
        'Gender': 'Female',
        'FriendlyName': 'Microsoft Xiaoxiao Online',
      },
      {
        'ShortName': 'zh-CN-YunxiNeural',
        'Locale': 'zh-CN',
        'Gender': 'Male',
        'FriendlyName': 'Microsoft Yunxi Online',
      },
      {
        'ShortName': 'zh-HK-HiuMaanNeural',
        'Locale': 'zh-HK',
        'Gender': 'Female',
        'FriendlyName': 'Microsoft HiuMaan Online',
      },
      {
        'ShortName': 'en-US-AriaNeural',
        'Locale': 'en-US',
        'Gender': 'Female',
        'FriendlyName': 'Microsoft Aria Online',
      },
      {
        'ShortName': 'ja-JP-NanamiNeural',
        'Locale': 'ja-JP',
        'Gender': 'Female',
        'FriendlyName': 'Microsoft Nanami Online',
      },
      {'ShortName': '', 'Locale': 'zh-CN', 'Gender': 'Female'},
      'not-a-map',
    ];

    test('只保留中文音色并排序', () {
      final voices = TtsVoice.parseChinese(raw);
      expect(voices.length, 3);
      expect(voices.every((v) => v.isChinese), isTrue);
      expect(voices.map((v) => v.locale).toList(), ['zh-CN', 'zh-CN', 'zh-HK']);
      expect(voices.first.shortName, 'zh-CN-XiaoxiaoNeural');
    });

    test('展示名包含性别与语区', () {
      final voice = TtsVoice.parseChinese(raw).first;
      expect(voice.label, contains('女声'));
      expect(voice.label, contains('zh-CN'));
    });

    test('空列表安全', () {
      expect(TtsVoice.parseChinese(const []), isEmpty);
    });
  });

  group('音色展示名与内置兜底', () {
    test('仅凭 shortName 推导展示名（无需联网）', () {
      expect(TtsVoice.labelOf('zh-CN-XiaoxiaoNeural'), 'Xiaoxiao · zh-CN');
      expect(TtsVoice.labelOf('zh-TW-YunJheNeural'), 'YunJhe · zh-TW');
      expect(TtsVoice.labelOf('bad-name'), 'bad-name');
      expect(TtsVoice.labelOf(''), '');
    });

    test('内置中文音色全部为 zh-*，可离线选择', () {
      final voices = EdgeTtsClient.builtinVoices;
      expect(voices.length, EdgeTtsClient.builtinChineseVoices.length);
      expect(voices.every((v) => v.isChinese), isTrue);
      expect(
        voices.any((v) => v.shortName == 'zh-CN-XiaoxiaoNeural'),
        isTrue,
      );
      expect(voices.first.locale, 'zh-CN');
    });
  });

  group('朗读语速', () {
    test('默认正常语速', () {
      expect(ReaderSettings().ttsRateString, '+0%');
    });

    test('正负号与百分号格式正确', () {
      final rs = ReaderSettings();
      rs.ttsRatePercent = 20;
      expect(rs.ttsRateString, '+20%');
      rs.ttsRatePercent = -30;
      expect(rs.ttsRateString, '-30%');
      rs.ttsRatePercent = 0;
      expect(rs.ttsRateString, '+0%');
    });

    test('随阅读设置一起保存与恢复', () {
      final rs = ReaderSettings()
        ..ttsVoice = 'zh-CN-YunxiNeural'
        ..ttsRatePercent = 40;
      final restored = ReaderSettings.fromJson(rs.toJson());
      expect(restored.ttsVoice, 'zh-CN-YunxiNeural');
      expect(restored.ttsRatePercent, 40);
      expect(restored.ttsRateString, '+40%');
    });
  });
}
