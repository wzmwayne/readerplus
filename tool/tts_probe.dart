// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:reader/services/tts/edge_tts_client.dart';
import 'package:reader/services/tts/edge_ws.dart';

String uuid() => List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join();

String ts() {
  final t = DateTime.now().toUtc();
  const wd = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  String two(int v) => v.toString().padLeft(2, '0');
  return '${wd[t.weekday-1]} ${mo[t.month-1]} ${two(t.day)} ${t.year} ${two(t.hour)}:${two(t.minute)}:${two(t.second)} GMT+0000 (Coordinated Universal Time)';
}

Future<void> main() async {
  const token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  final uri = Uri.parse('wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1'
      '?TrustedClientToken=$token'
      '&ConnectionId=${uuid()}'
      '&Sec-MS-GEC=${EdgeTtsClient.secMsGec()}'
      '&Sec-MS-GEC-Version=1-143.0.3650.75');
  final ws = await EdgeWebSocket.connect(uri, headers: {
    'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0',
    'Pragma': 'no-cache', 'Cache-Control': 'no-cache', 'Cookie': 'muid=${uuid().toUpperCase()};',
  });
  print('connected');

  ws.sendText(EdgeTtsClient.buildConfigMessage());
  ws.sendText(EdgeTtsClient.buildSsmlMessage(voice: 'zh-CN-XiaoxiaoNeural', text: '夜色像一层薄薄的墨。'));

  var audio = 0; var textCount = 0; var binaryCount = 0;
  final timer = Timer(const Duration(seconds: 15), () { print('timeout'); ws.close(); });
  await for (final event in ws.events) {
    if (event is String) {
      textCount++;
      print('[text#$textCount] ${event.length} chars :: ${event.replaceAll('\r\n', ' | ').substring(0, event.length < 220 ? event.length : 220)}');
      if (event.contains('Path:turn.end')) break;
    } else if (event is List<int>) {
      binaryCount++;
      if (binaryCount <= 3) {
        final headerLen = event.length >= 2 ? (event[0] << 8 | event[1]) : 0;
        final header = headerLen > 0 && event.length >= 2 + headerLen
            ? utf8.decode(event.sublist(2, 2 + headerLen), allowMalformed: true) : '';
        print('[bin#$binaryCount] len=${event.length} header="${header.replaceAll('\r\n',' | ')}"');
      }
      if (event.length > 2) {
        final h = (event[0] << 8 | event[1]);
        if (event.length > 2 + h) audio += event.length - 2 - h;
      }
    }
  }
  timer.cancel();
  print('RESULT: text=$textCount binary=$binaryCount audioBytes=$audio');
  exit(0);
}
