import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'wav_encoder.dart';

/// 一个模型目录解析出来的、sherpa 需要的文件集合。
class TtsModelFiles {
  const TtsModelFiles({
    required this.onnx,
    required this.tokens,
    this.dataDir = '',
    this.lexicon = '',
    this.dictDir = '',
    this.ruleFsts = '',
  });

  final String onnx;
  final String tokens;
  final String dataDir;
  final String lexicon;
  final String dictDir;
  final String ruleFsts;

  /// 从模型目录里收集文件。
  ///
  /// 只做"存在就用、不存在就留空"，具体是否可用由导入阶段的校验负责；
  /// 这样引擎不必重复实现一套校验规则。
  static TtsModelFiles? fromDir(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;

    String first(String suffix, {String under = ''}) {
      final files = dir
          .listSync(recursive: under.isNotEmpty)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith(suffix))
          .where((f) => under.isEmpty || f.path.contains(under))
          .toList();
      if (files.isEmpty) return '';
      // 多个 onnx 时优先真实 int8（体积小），与导入阶段的判定保持一致
      if (suffix == '.onnx') {
        final int8 = files.where((f) => f.path.toLowerCase().contains('int8')).toList();
        if (int8.isNotEmpty) return int8.first.path;
      }
      return files.first.path;
    }

    final onnx = first('.onnx');
    final tokens = first('tokens.txt');
    if (onnx.isEmpty || tokens.isEmpty) return null;

    final espeakDir = Directory('${dir.path}/espeak-ng-data');
    final dictDir = Directory('${dir.path}/dict');
    final fsts = <String>[];
    for (final name in const [
      'date.fst',
      'number.fst',
      'phone.fst',
      'new_heteronym.fst',
      'date-zh.fst',
      'number-zh.fst',
      'phone-zh.fst',
    ]) {
      final f = File('${dir.path}/$name');
      if (f.existsSync()) fsts.add(f.path);
    }

    return TtsModelFiles(
      onnx: onnx,
      tokens: tokens,
      dataDir: espeakDir.existsSync() ? espeakDir.path : '',
      lexicon: first('lexicon.txt'),
      dictDir: dictDir.existsSync() ? dictDir.path : '',
      ruleFsts: fsts.join(','),
    );
  }
}

/// 本机离线语音合成引擎（sherpa-onnx / Piper 系模型）。
///
/// 合成放在**常驻 isolate** 里：模型初始化约 1–2 秒、合成占用 CPU，
/// 放主线程会卡 UI；而每次调用都新建 isolate 又会反复加载模型。
class SherpaTtsEngine {
  SherpaTtsEngine._(this._isolate, this._toWorker, this._pending, this.sampleRate);

  final Isolate _isolate;
  final SendPort _toWorker;
  final Map<int, Completer<Uint8List>> _pending;
  final int sampleRate;

  int _nextId = 0;
  bool _closed = false;

  /// 打开引擎并完成模型加载。[libPath] 仅桌面端需要（指向自带/自备的 .so/.dll）；
  /// Android 上库随 APK 打进 nativeLibraryDir，传 null 走系统加载。
  static Future<SherpaTtsEngine> open(
    TtsModelFiles files, {
    String? libPath,
    int numThreads = 2,
  }) async {
    final port = ReceivePort();
    final ready = Completer<({SendPort send, int sampleRate})>();
    final errors = Completer<String>();

    final isolate = await Isolate.spawn(_workerMain, (
      reply: port.sendPort,
      libPath: libPath,
      onnx: files.onnx,
      tokens: files.tokens,
      dataDir: files.dataDir,
      lexicon: files.lexicon,
      dictDir: files.dictDir,
      ruleFsts: files.ruleFsts,
      numThreads: numThreads,
    ));

    final pending = <int, Completer<Uint8List>>{};
    port.listen((message) {
      if (message is Map && message['ready'] == true) {
        if (!ready.isCompleted) {
          ready.complete((send: message['send'] as SendPort, sampleRate: message['sampleRate'] as int));
        }
        return;
      }
      if (message is Map && message['initError'] != null) {
        final msg = '${message['initError']}';
        if (!ready.isCompleted) ready.completeError(StateError(msg));
        if (!errors.isCompleted) errors.complete(msg);
        return;
      }
      if (message is Map && message['id'] != null) {
        final id = message['id'] as int;
        final c = pending.remove(id);
        if (c == null) return;
        final err = message['error'];
        if (err != null) {
          c.completeError(StateError('$err'));
        } else {
          c.complete(message['wav'] as Uint8List);
        }
      }
    });

    try {
      final r = await ready.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw StateError('模型加载超时（60 秒）'),
      );
      return SherpaTtsEngine._(isolate, r.send, pending, r.sampleRate);
    } catch (e) {
      isolate.kill(priority: Isolate.immediate);
      port.close();
      rethrow;
    }
  }

  /// 合成一句话，返回完整 WAV 字节（16-bit PCM 单声道）。
  Future<Uint8List> synthesize(String text, {int sid = 0, double speed = 1.0}) {
    if (_closed) throw StateError('引擎已关闭');
    final id = _nextId++;
    final c = Completer<Uint8List>();
    _pending[id] = c;
    _toWorker.send({'id': id, 'text': text, 'sid': sid, 'speed': speed});
    return c.future;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _toWorker.send({'cmd': 'close'});
    _isolate.kill(priority: Isolate.beforeNextEvent);
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('引擎已关闭'));
    }
    _pending.clear();
  }
}

/// 常驻 worker：加载一次模型，之后按消息顺序合成。
void _workerMain(
  ({
    SendPort reply,
    String? libPath,
    String onnx,
    String tokens,
    String dataDir,
    String lexicon,
    String dictDir,
    String ruleFsts,
    int numThreads,
  })
  cfg,
) {
  final port = ReceivePort();
  try {
    so.initBindings(cfg.libPath);
    final tts = so.OfflineTts(
      so.OfflineTtsConfig(
        model: so.OfflineTtsModelConfig(
          vits: so.OfflineTtsVitsModelConfig(
            model: cfg.onnx,
            tokens: cfg.tokens,
            dataDir: cfg.dataDir,
            lexicon: cfg.lexicon,
            dictDir: cfg.dictDir,
          ),
          numThreads: cfg.numThreads,
          debug: false,
        ),
        ruleFsts: cfg.ruleFsts,
        maxNumSenetences: 1,
      ),
    );
    cfg.reply.send({'ready': true, 'send': port.sendPort, 'sampleRate': tts.sampleRate});
    port.listen((message) {
      if (message is! Map) return;
      if (message['cmd'] == 'close') {
        port.close();
        return;
      }
      final id = message['id'] as int;
      try {
        final audio = tts.generate(
          text: message['text'] as String,
          sid: (message['sid'] as int?) ?? 0,
          speed: (message['speed'] as double?) ?? 1.0,
        );
        cfg.reply.send({
          'id': id,
          'wav': WavEncoder.encode(audio.samples, audio.sampleRate),
        });
      } catch (e) {
        cfg.reply.send({'id': id, 'error': '$e'});
      }
    });
  } catch (e) {
    cfg.reply.send({'initError': '$e'});
    port.close();
  }
}
