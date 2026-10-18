import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/tts/edge_tts_client.dart';

void main() {
  test('直接探一次合成，打印真实异常', () async {
    final chunks = <List<int>>[];
    Object? err;
    StackTrace? st;
    try {
      await for (final c in EdgeTtsClient.synthesize(
        text: '测试一下朗读合成。',
        voice: 'zh-CN-XiaoxiaoNeural',
      ).timeout(const Duration(seconds: 25))) {
        chunks.add(c);
      }
    } catch (e, s) {
      err = e;
      st = s;
    }
    // ignore: avoid_print
    print('CHUNKS=${chunks.length} BYTES=${chunks.fold<int>(0, (a, c) => a + c.length)}');
    // ignore: avoid_print
    print('ERR=$err');
    if (st != null) {
      // ignore: avoid_print
      print('ST=${st.toString().split('\n').take(6).join('\n')}');
    }
    expect(chunks.isNotEmpty, isTrue, reason: '没收到任何音频分片：$err');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
