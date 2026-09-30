import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/tts/edge_tts_client.dart';
import 'package:reader/services/tts/tts_stream_server.dart';

/// 联网测试：使用**真实文本**向**真实 Edge TTS 接口**发起请求。
///
/// 这些用例验证的是真实链路：令牌被服务端接受、返回真实 mp3 分片、
/// 并且能通过进程内 HTTP 服务边收边播（不是攒齐再发）。
void main() {
  const realText = '夜色像一层薄薄的墨，慢慢洇开在窗棂上。他放下手中的书，听见巷子尽头传来更夫敲梆子的声音。';
  const voice = 'zh-CN-XiaoxiaoNeural';

  group('真实接口', () {
    test('拉取音色列表并筛出中文音色', () async {
      final voices = await EdgeTtsClient.fetchChineseVoices();
      expect(voices, isNotEmpty, reason: '应能取到中文音色');
      expect(voices.every((v) => v.isChinese), isTrue);
      expect(
        voices.any((v) => v.shortName == 'zh-CN-XiaoxiaoNeural'),
        isTrue,
        reason: '应包含默认中文音色',
      );
      // 打印几个可选音色，便于人工核对
      // ignore: avoid_print
      print('中文音色数=${voices.length}，示例：'
          '${voices.take(5).map((v) => v.shortName).join(', ')}');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('真实合成中文文本得到 mp3，且为多分片流式返回', () async {
      final chunks = <List<int>>[];
      await for (final chunk in EdgeTtsClient.synthesize(
        text: realText,
        voice: voice,
      )) {
        if (chunk.isNotEmpty) chunks.add(chunk);
      }
      final bytes = chunks.expand((c) => c).toList();

      expect(bytes.length, greaterThan(2000), reason: '应返回真实音频数据');
      expect(chunks.length, greaterThan(1), reason: '应是流式多分片，而非一次性返回');

      // MP3 文件头：ID3 标签或帧同步 0xFFEx
      final isId3 = bytes.length > 3 &&
          bytes[0] == 0x49 &&
          bytes[1] == 0x44 &&
          bytes[2] == 0x33;
      final isFrame = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
      expect(isId3 || isFrame, isTrue, reason: '应是合法 mp3 数据');
      // ignore: avoid_print
      print('合成完成：${bytes.length} 字节，分片数 ${chunks.length}，'
          '头部 0x${bytes.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('真实音频经进程内 HTTP 服务边到边播（首字节早于合成结束）', () async {
      final server = TtsStreamServer();
      await server.ensureStarted();
      final id = server.createSlot();

      final client = HttpClient();
      final startedAt = DateTime.now();
      final request = await client.getUrl(server.urlFor(id));

      // 真实合成并把分片灌入流式服务（与客户端读取并行）
      Duration? feedFinishedAt;
      final feed = () async {
        await for (final chunk in EdgeTtsClient.synthesize(
          text: realText,
          voice: voice,
        )) {
          server.addChunk(id, chunk);
        }
        feedFinishedAt = DateTime.now().difference(startedAt);
        server.finishSlot(id);
      }();

      final response = await request.close();
      Duration? firstByteAt;
      final received = <int>[];
      final done = response.listen((chunk) {
        firstByteAt ??= DateTime.now().difference(startedAt);
        received.addAll(chunk);
      }).asFuture<void>();
      await done;
      await feed;
      client.close(force: true);
      await server.dispose();

      final first = firstByteAt;
      final feedDone = feedFinishedAt;
      expect(received.length, greaterThan(2000));
      expect(first, isNotNull);
      expect(feedDone, isNotNull);
      expect(
        first!.compareTo(feedDone!) < 0,
        isTrue,
        reason: '首字节应早于合成结束（流式），实际首字节 $first / 合成结束 $feedDone',
      );
      // ignore: avoid_print
      print('流式验证：首字节 ${first.inMilliseconds}ms，'
          '合成结束 ${feedDone.inMilliseconds}ms，共 ${received.length} 字节');
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
