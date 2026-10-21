import 'dart:async';

import '../app_log.dart';
import 'sherpa_tts_engine.dart';
import 'tts_model_store.dart';

/// 把「用户导入的本地模型」接到朗读链路上的合成函数。
///
/// 朗读链路只认 `Stream<List<int>>`（以前是 Edge 的分块音频流），
/// 这里把整句合成出的 WAV 作为**单个分块**吐出去，因此播放、逐句高亮、
/// 预取等逻辑完全不用改。
class LocalTtsSynthesizer {
  LocalTtsSynthesizer._();

  /// modelId → 已打开的引擎（模型加载约 1–2 秒，不能每句重开）
  static final Map<String, SherpaTtsEngine> _engines = {};

  /// 闲置回收：int8 模型常驻约 65 MB、fp32 约 104 MB，
  /// 朗读结束后不该一直占着；超时后释放，下次朗读重新加载。
  static final Map<String, Timer> _idle = {};
  static Duration idleTimeout = const Duration(seconds: 60);

  static TtsModelStore store = TtsModelStore();

  /// 桌面端可能需要显式指定原生库路径（Android 由 APK 的 jniLibs 提供，传 null）。
  static String? libPath;

  static Future<SherpaTtsEngine> _engineFor(String modelId) async {
    final cached = _engines[modelId];
    if (cached != null) return cached;

    final models = await store.load();
    TtsModel? model;
    for (final m in models) {
      if (m.id == modelId) {
        model = m;
        break;
      }
    }
    if (model == null) {
      throw StateError(
        models.isEmpty
            ? '尚未导入语音模型：请在「设置 → 朗读」中导入一个模型包（zip 或 tar.bz2）'
            : '选中的语音模型已不存在，请重新导入或改选其它模型',
      );
    }
    final files = TtsModelFiles.fromDir(model.dirPath);
    if (files == null) {
      throw StateError('模型文件不完整（缺少 .onnx 或 tokens.txt）：${model.name}');
    }
    AppLog.info('tts', '打开本地语音模型：${model.name}（${model.dirPath}）');
    // numThreads=1：低端机更稳，内存与线程开销更小（代价是合成慢约 30%）
    final engine = await SherpaTtsEngine.open(files, libPath: libPath, numThreads: 1);
    _engines[modelId] = engine;
    _idle.remove(modelId)?.cancel();
    return engine;
  }

  /// `ttsRatePercent` 形式的速率字符串（如 `+30%`）→ sherpa 的 speed 倍数。
  static double speedOf(String rate) {
    final m = RegExp(r'([+-]?\d+)').firstMatch(rate);
    final percent = m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
    return (1 + percent / 100).clamp(0.5, 2.0);
  }

  static Stream<List<int>> synthesize({
    required String text,
    required String voice,
    String rate = '+0%',
    String pitch = '+0Hz',
  }) async* {
    if (text.trim().isEmpty) return;
    try {
      final engine = await _engineFor(voice);
      final wav = await engine.synthesize(text, speed: speedOf(rate));
      _armIdleRelease(voice);
      yield wav;
    } catch (e) {
      // 合成失败要抛出可读原因：调用方（朗读控制器）会把它写进日志并停止朗读
      if (e is StateError) rethrow;
      throw StateError('语音合成失败：$e');
    }
  }

  static void _armIdleRelease(String modelId) {
    _idle.remove(modelId)?.cancel();
    _idle[modelId] = Timer(idleTimeout, () {
      _idle.remove(modelId);
      AppLog.info('tts', '闲置超时，释放语音模型：$modelId');
      dispose(modelId);
    });
  }

  /// 释放所有已打开的引擎（退出朗读或切换模型时调用）。
  static Future<void> disposeAll() async {
    for (final t in _idle.values) {
      t.cancel();
    }
    _idle.clear();
    final engines = _engines.values.toList();
    _engines.clear();
    for (final e in engines) {
      await e.close();
    }
  }

  static Future<void> dispose(String modelId) async {
    _idle.remove(modelId)?.cancel();
    final e = _engines.remove(modelId);
    await e?.close();
  }
}
