import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/tts/read_aloud_controller.dart';
import 'package:reader/services/tts/tts_audio_sink.dart';
import 'package:reader/services/tts/tts_stream_server.dart';

/// 假播放器：记录播放顺序，并由测试驱动「一句播完」。
class FakeSink implements TtsAudioSink {
  final List<String> played = [];
  final List<String> events = [];
  final List<String> playedBodies = [];
  Completer<void>? _current;

  @override
  bool isPlaying = false;

  /// 是否在播放时把整段音频拉下来（用于验证流式内容）。
  bool fetchBody = false;

  @override
  Future<void> playUrl(String url) async {
    played.add(url);
    events.add('play');
    isPlaying = true;
    if (fetchBody) {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      playedBodies.add(String.fromCharCodes(bytes));
      client.close(force: true);
    }
    _current = Completer<void>();
    await _current!.future;
    isPlaying = false;
  }

  void finishCurrent() {
    if (_current != null && !_current!.isCompleted) _current!.complete();
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    isPlaying = false;
  }

  @override
  Future<void> resume() async {
    events.add('resume');
    isPlaying = true;
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    isPlaying = false;
    finishCurrent();
  }

  @override
  Future<void> dispose() async {}
}

/// 可控分片节奏的假合成器：先给首片，再按 [chunkDelay] 逐片给出。
TtsSynthesize fakeSynth({
  required List<String> log,
  Duration chunkDelay = Duration.zero,
  int chunks = 2,
  Map<String, List<int>>? payload,
}) {
  return ({required text, required voice, rate = '+0%', pitch = '+0Hz'}) {
    log.add(text);
    final bytes = payload?[text] ?? List<int>.generate(chunks, (i) => 65 + i);
    Stream<List<int>> body() async* {
      for (var i = 0; i < bytes.length; i++) {
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
        yield [bytes[i]];
      }
    }

    return body();
  };
}

void main() {
  late FakeSink sink;
  late List<String> log;

  setUp(() {
    sink = FakeSink();
    log = [];
  });

  group('分句', () {
    test('按句末标点切分并保留标点', () {
      expect(splitSentences('他来了。她走了！你还好吗？'), ['他来了。', '她走了！', '你还好吗？']);
    });

    test('过长的句子会再切开', () {
      final sentences = splitSentences('${'很长的一段话' * 30}。', maxLength: 40);
      expect(sentences.length, greaterThan(1));
      expect(sentences.every((s) => s.length <= 45), isTrue);
    });

    test('空白与空文本', () {
      expect(splitSentences('   '), isEmpty);
      expect(splitSentences(''), isEmpty);
    });
  });

  group('多句预载', () {
    test('起始即并行合成 preloadAhead + 1 句', () async {
      final controller = ReadAloudController(
        sink: sink,
        preloadAhead: 3,
        synthesize: fakeSynth(log: log),
      );
      await controller.start('一。二。三。四。五。六。');
      await Future<void>.delayed(Duration.zero);
      expect(log, ['一。', '二。', '三。', '四。']);
      expect(controller.preloadedCount, 4);
      await controller.stop();
    });

    test('预载句数可配置', () async {
      final controller = ReadAloudController(
        sink: sink,
        preloadAhead: 1,
        synthesize: fakeSynth(log: log),
      );
      await controller.start('一。二。三。四。');
      await Future<void>.delayed(Duration.zero);
      expect(log, ['一。', '二。']);
      await controller.stop();
    });
  });

  group('毫秒级起播（首片即播，不等整句）', () {
    test('首片到达后立刻交给播放器，不必等整句合成完', () async {
      // 每片间隔 120ms：若等整句（2 片）需要 ~240ms
      final controller = ReadAloudController(
        sink: sink,
        preloadAhead: 2,
        synthesize: fakeSynth(
          log: log,
          chunkDelay: const Duration(milliseconds: 120),
          chunks: 3,
        ),
      );
      final sw = Stopwatch()..start();
      await controller.start('第一句。');
      // 等播放器拿到地址
      while (sink.played.isEmpty && sw.elapsedMilliseconds < 2000) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      sw.stop();
      expect(sink.played, isNotEmpty);
      expect(
        sw.elapsedMilliseconds,
        lessThan(200),
        reason: '应在首个分片后即起播，而不是等整句（约 360ms）',
      );
      await controller.stop();
    });
  });

  group('流式播放顺序与回调', () {
    test('按句顺序播放，播完触发翻页回调', () async {
      final controller = ReadAloudController(
        sink: sink,
        preloadAhead: 2,
        synthesize: fakeSynth(log: log),
      );
      var finished = 0;
      controller.onPageFinished = () => finished++;

      await controller.start('甲句。乙句。');
      await Future<void>.delayed(Duration.zero);
      expect(sink.played.length, 1);
      expect(controller.currentSentence, '甲句。');

      sink.finishCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sink.played.length, 2);
      expect(controller.currentSentence, '乙句。');

      sink.finishCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.isActive, isFalse);
      expect(finished, 1);
    });


    test('可从指定句开始（改音色/语速后从当前句继续）', () async {
      final controller = ReadAloudController(
        sink: sink,
        preloadAhead: 2,
        synthesize: fakeSynth(log: log),
      );
      await controller.start('一。二。三。', at: 1);
      await Future<void>.delayed(Duration.zero);
      expect(controller.index, 1);
      expect(controller.currentSentence, '二。');
      expect(log, isNot(contains('一。')));
      expect(log, contains('二。'));
      await controller.stop();
    });
    test('停止后不再播放后续句子，也不触发翻页回调', () async {
      final controller = ReadAloudController(
        sink: sink,
        preloadAhead: 2,
        synthesize: fakeSynth(log: log),
      );
      var finished = 0;
      controller.onPageFinished = () => finished++;
      await controller.start('第一句。第二句。');
      await Future<void>.delayed(Duration.zero);
      await controller.stop();
      sink.finishCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.isActive, isFalse);
      expect(sink.played.length, 1);
      expect(finished, 0);
    });

    test('暂停与继续透传到播放器', () async {
      final controller = ReadAloudController(
        sink: sink,
        synthesize: fakeSynth(log: log),
      );
      await controller.start('只有一句。');
      await Future<void>.delayed(Duration.zero);
      await controller.pause();
      expect(controller.isPaused, isTrue);
      await controller.resume();
      expect(controller.isPaused, isFalse);
      expect(sink.events, containsAllInOrder(['pause', 'resume']));
      await controller.stop();
    });
  });

  group('流式 HTTP 服务', () {
    test('边到边发：首字节早于结束，内容完整', () async {
      final server = TtsStreamServer();
      await server.ensureStarted();
      final id = server.createSlot();
      final url = server.urlFor(id).toString();

      final received = <int>[];
      final startedAt = DateTime.now();
      Duration? firstByteAt;

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      // 先开始喂数据（真实播放器也是边请求边收），再等响应头
      Duration? finishedAt;
      final feed = () async {
        server.addChunk(id, [1, 2, 3]);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        server.addChunk(id, [4, 5]);
        finishedAt = DateTime.now().difference(startedAt);
        server.finishSlot(id);
      }();
      final response = await request.close();
      final done = response.listen((chunk) {
        firstByteAt ??= DateTime.now().difference(startedAt);
        received.addAll(chunk);
      }).asFuture<void>();
      await done;
      await feed;
      client.close(force: true);
      await server.dispose();

      expect(received, [1, 2, 3, 4, 5]);
      expect(firstByteAt, isNotNull);
      expect(finishedAt, isNotNull);
      expect(
        firstByteAt!.compareTo(finishedAt!) < 0,
        isTrue,
        reason: '首字节应早于结束（流式），实际首字节 $firstByteAt / 结束 $finishedAt',
      );
    });

    test('未知槽位返回 404', () async {
      final server = TtsStreamServer();
      await server.ensureStarted();
      final client = HttpClient();
      final request = await client.getUrl(server.urlFor('nope'));
      final response = await request.close();
      expect(response.statusCode, 404);
      client.close(force: true);
      await server.dispose();
    });
  });

  group('逐句高亮', () {
    test('句子偏移与段落交集计算正确', () {
      const text = '甲乙丙丁。戊己庚辛。';
      final segments = splitSentenceSegments(text);
      expect(segments.length, 2);
      expect(segments[0].start, 0);
      expect(segments[1].start, 5);
      expect(segments[1].end, 10);

      // 段落就是整段正文
      expect(highlightRangeInParagraph(0, text.length, segments[1]), [5, 10]);
      // 段落只覆盖后半段（段落起点偏移 5、长度 5）
      expect(highlightRangeInParagraph(5, 5, segments[1]), [0, 5]);
      // 完全没有交集
      expect(highlightRangeInParagraph(0, 5, segments[1]), isNull);
    });

    test('同一句跨多段时每段各取交集', () {
      final segment = splitSentenceSegments('前半段没有标点后半段也没有标点。').single;
      expect(highlightRangeInParagraph(0, 5, segment), [0, 5]);
      expect(highlightRangeInParagraph(5, 10, segment), [0, 10]);
      expect(highlightRangeInParagraph(20, 5, segment), isNull);
    });

    test('朗读句首尾空白不影响高亮范围', () {
      final segments = splitSentenceSegments('  第一句。第二句。  ');
      expect(segments.first.start, 2);
      expect(segments.first.text, '第一句。');
    });

  });
}
