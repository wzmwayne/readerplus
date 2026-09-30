import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/tts/edge_tts_client.dart';

void main() {
  group('Sec-MS-GEC 令牌', () {
    test('为 64 位大写十六进制', () {
      final token = EdgeTtsClient.secMsGec(DateTime.utc(2026, 9, 30, 12, 0, 0));
      expect(token.length, 64);
      expect(RegExp(r'^[0-9A-F]{64}$').hasMatch(token), isTrue);
    });

    test('同一 5 分钟窗口内一致，跨窗口变化', () {
      final a = EdgeTtsClient.secMsGec(DateTime.utc(2026, 9, 30, 12, 0, 10));
      final b = EdgeTtsClient.secMsGec(DateTime.utc(2026, 9, 30, 12, 4, 59));
      final c = EdgeTtsClient.secMsGec(DateTime.utc(2026, 9, 30, 12, 5, 1));
      expect(a, b);
      expect(c, isNot(a));
    });

    test('与独立实现（Python hashlib）结果一致', () {
      // 期望值由 Python 独立算出：ticks 取整到 300 后与令牌拼接做 SHA-256（大写十六进制）
      expect(
        EdgeTtsClient.secMsGec(DateTime.utc(2026, 9, 30, 12, 0, 0)),
        '14C4410C6B810FD3B511152D9A96C51A56FBB5C5530494CC4C8E0EADCF2500D6',
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
}
