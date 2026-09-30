import 'dart:async';

import 'package:flutter/foundation.dart';

import 'edge_tts_client.dart';
import 'tts_audio_sink.dart';
import 'tts_stream_server.dart';

/// 合成一句文本所需的函数签名（便于注入假实现做测试）。
typedef TtsSynthesize =
    Stream<List<int>> Function({
      required String text,
      required String voice,
      String rate,
      String pitch,
    });

Stream<List<int>> _defaultSynthesize({
  required String text,
  required String voice,
  String rate = '+0%',
  String pitch = '+0Hz',
}) => EdgeTtsClient.synthesize(
  text: text,
  voice: voice,
  rate: rate,
  pitch: pitch,
);

/// 按句切分文本：句末标点后断句，过长片段再按逗号/长度切分。
List<String> splitSentences(String text, {int maxLength = 120}) {
  final normalized = text.replaceAll(RegExp(r'[ \t\u3000]+'), ' ').trim();
  if (normalized.isEmpty) return const [];

  final sentences = <String>[];
  final buffer = StringBuffer();

  void flush() {
    final s = buffer.toString().trim();
    buffer.clear();
    if (s.isNotEmpty) sentences.add(s);
  }

  final enders = RegExp(r'[。！？!?…；;]');
  for (final char in normalized.runes) {
    buffer.writeCharCode(char);
    if (enders.hasMatch(String.fromCharCode(char))) flush();
  }
  flush();

  final result = <String>[];
  for (final sentence in sentences) {
    if (sentence.length <= maxLength) {
      result.add(sentence);
      continue;
    }
    var rest = sentence;
    while (rest.length > maxLength) {
      var cut = -1;
      for (final mark in ['，', '、', ',', ' ']) {
        final idx = rest.lastIndexOf(mark, maxLength);
        if (idx > maxLength ~/ 3) {
          cut = idx + 1;
          break;
        }
      }
      if (cut <= 0) cut = maxLength;
      result.add(rest.substring(0, cut).trim());
      rest = rest.substring(cut);
    }
    if (rest.trim().isNotEmpty) result.add(rest.trim());
  }
  return result;
}

/// 一句朗读任务：负责把该句的音频边合成边灌进流式服务。
class _SentenceJob {
  _SentenceJob({required this.text, required this.slotId});

  final String text;
  final String slotId;

  final Completer<void> firstChunk = Completer<void>();
  Future<void>? synthesis;
  bool finished = false;
  int bytesReceived = 0;
}

/// 流式朗读控制器。
///
/// 关键设计（各端完全一致，无平台分支）：
///   1. 每句在进程内 HTTP 流式服务上开一个槽，边合成边可播；
///   2. 播放器只当普通网络流播放，因此首片一到就能起播（毫秒级）；
///   3. 预载 [preloadAhead] 句：当前句播放时，后续句子的音频已在并行合成，
///      切句时无需等待，做到句间无停顿。
class ReadAloudController extends ChangeNotifier {
  ReadAloudController({
    TtsSynthesize? synthesize,
    TtsAudioSink? sink,
    TtsStreamServer? server,
    this.preloadAhead = 3,
  }) : _synthesize = synthesize ?? _defaultSynthesize,
       _sink = sink ?? AudioPlayersSink(),
       _server = server ?? TtsStreamServer();

  final TtsSynthesize _synthesize;
  final TtsAudioSink _sink;
  final TtsStreamServer _server;

  /// 预载句数（含当前句之后的若干句）。
  final int preloadAhead;

  String voice = 'zh-CN-XiaoxiaoNeural';
  String rate = '+0%';
  String pitch = '+0Hz';

  final List<String> _sentences = [];
  final List<_SentenceJob> _jobs = [];
  int _index = 0;
  bool _active = false;
  bool _paused = false;

  /// 一页播完时回调（用于自动翻页）。
  VoidCallback? onPageFinished;

  List<String> get sentences => List.unmodifiable(_sentences);
  int get index => _index;
  String get currentSentence =>
      _index >= 0 && _index < _sentences.length ? _sentences[_index] : '';
  bool get isActive => _active;
  bool get isPaused => _paused;
  bool get isPlaying => _active && !_paused;

  /// 已预载（合成中或已完成）的句子数，便于界面展示与自测。
  int get preloadedCount =>
      _jobs.where((j) => j.synthesis != null).length;

  Future<void> start(String text) async {
    await stop();
    _sentences
      ..clear()
      ..addAll(splitSentences(text));
    _active = _sentences.isNotEmpty;
    _paused = false;
    _index = 0;
    if (!_active) {
      notifyListeners();
      return;
    }
    await _server.ensureStarted();
    _jobs
      ..clear()
      ..addAll([
        for (final sentence in _sentences)
          _SentenceJob(text: sentence, slotId: _server.createSlot()),
      ]);
    _pumpPreload();
    notifyListeners();
    unawaited(_playFrom(0));
  }

  Future<void> pause() async {
    if (!_active || _paused) return;
    _paused = true;
    notifyListeners();
    await _sink.pause();
  }

  Future<void> resume() async {
    if (!_active || !_paused) return;
    _paused = false;
    notifyListeners();
    await _sink.resume();
  }

  Future<void> stop() async {
    final wasActive = _active;
    _active = false;
    _paused = false;
    _index = 0;
    _sentences.clear();
    for (final job in _jobs) {
      job.finished = true;
      _server.disposeSlot(job.slotId);
    }
    _jobs.clear();
    notifyListeners();
    if (wasActive) await _sink.stop();
  }

  /// 让 [from, from + preloadAhead] 区间内的句子开始并行合成。
  void _pumpPreload() {
    for (var i = _index; i <= _index + preloadAhead && i < _jobs.length; i++) {
      final job = _jobs[i];
      job.synthesis ??= _fill(job);
    }
  }

  /// 把一句的合成分片写入流式服务；首片到达即完成 [firstChunk]。
  Future<void> _fill(_SentenceJob job) async {
    try {
      await for (final chunk in _synthesize(
        text: job.text,
        voice: voice,
        rate: rate,
        pitch: pitch,
      )) {
        if (!_active || job.finished) return;
        if (chunk.isEmpty) continue;
        job.bytesReceived += chunk.length;
        _server.addChunk(job.slotId, chunk);
        if (!job.firstChunk.isCompleted) job.firstChunk.complete();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[tts] 合成失败：$e');
    } finally {
      _server.finishSlot(job.slotId);
      if (!job.firstChunk.isCompleted) job.firstChunk.complete();
    }
  }

  Future<void> _playFrom(int index) async {
    if (!_active || index >= _jobs.length) {
      if (_active && index >= _jobs.length) {
        _active = false;
        notifyListeners();
        onPageFinished?.call();
      }
      return;
    }
    _index = index;
    notifyListeners();
    _pumpPreload();

    final job = _jobs[index];
    // 首片一到就交给播放器，起播延迟只取决于首个分片（毫秒级）
    try {
      await job.firstChunk.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      if (!_active) return;
    } catch (_) {
      if (!_active) return;
    }
    if (!_active || job.finished) return;

    try {
      await _sink.playUrl(_server.urlFor(job.slotId).toString());
    } catch (e) {
      // 单句播放失败（空流/网络抖动）不应中断整页朗读
      if (kDebugMode) debugPrint('[tts] 播放失败：$e');
    }
    job.finished = true;
    _server.disposeSlot(job.slotId);
    if (!_active) return;
    await _playFrom(index + 1);
  }

  @override
  void dispose() {
    _active = false;
    unawaited(_sink.dispose());
    unawaited(_server.dispose());
    super.dispose();
  }
}
