import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/tts/edge_tts_client.dart';
import 'package:reader/services/tts/edge_ws.dart';

String uuid() {
  final r = Random.secure();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-${h(4)}-${h(4)}-${h(12)}';
}

void main() {
  const token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  const gecVer = '1-143.0.3650.75';
  const origin = 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold';
  const ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0';

  Future<String> probe(String name, Uri uri, Map<String, String> headers) async {
    try {
      final ws = await EdgeWebSocket.connect(uri, headers: headers,
          timeout: const Duration(seconds: 12));
      await ws.close();
      return '[$name] 101 OK';
    } catch (e) {
      return '[$name] $e';
    }
  }

  test('候选端点握手', () async {
    final gec = EdgeTtsClient.secMsGec();
    final base = {
      'Origin': origin,
      'User-Agent': ua,
      'Pragma': 'no-cache',
      'Cache-Control': 'no-cache',
      'Cookie': 'muid=${uuid().toUpperCase()};',
    };
    final results = <String>[];

    results.add(await probe(
        'A 老网关',
        Uri.parse('wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1'
            '?TrustedClientToken=$token&ConnectionId=${uuid()}&Sec-MS-GEC=$gec&Sec-MS-GEC-Version=$gecVer'),
        base));

    final newBase = 'wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1'
        '?TrustedClientToken=$token&ConnectionId=${uuid()}&Sec-MS-GEC=$gec&Sec-MS-GEC-Version=$gecVer';
    results.add(await probe('B 新网关(带Cookie)', Uri.parse(newBase), base));
    results.add(await probe('C 新网关(无Cookie)', Uri.parse(newBase),
        Map.of(base)..remove('Cookie')));

    // ignore: avoid_print
    for (final r in results) { print('RESULT $r'); }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
