import 'dart:typed_data';

/// 把 [-1,1] 的浮点采样编码成 16-bit PCM 单声道 WAV。
///
/// 独立出来是为了可单测：sherpa 只给采样与采样率，容器格式由我们自己拼，
/// 这样播放侧（audioplayers）拿到的就是一个标准的 .wav 字节流，不必落盘再用解码器。
class WavEncoder {
  const WavEncoder._();

  static const int _headerSize = 44;

  static Uint8List encode(Float32List samples, int sampleRate) {
    final dataBytes = samples.length * 2;
    final out = Uint8List(_headerSize + dataBytes);
    final view = ByteData.view(out.buffer);

    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        out[offset + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    view.setUint32(4, 36 + dataBytes, Endian.little); // RIFF 块大小
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    view.setUint32(16, 16, Endian.little); // fmt 块大小
    view.setUint16(20, 1, Endian.little); // PCM
    view.setUint16(22, 1, Endian.little); // 单声道
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * 2, Endian.little); // 字节率
    view.setUint16(32, 2, Endian.little); // 块对齐
    view.setUint16(34, 16, Endian.little); // 位深
    ascii(36, 'data');
    view.setUint32(40, dataBytes, Endian.little);

    var offset = _headerSize;
    for (final s in samples) {
      // 先夹紧再量化，避免溢出成反相噪声
      final clamped = s.isNaN ? 0.0 : (s > 1 ? 1.0 : (s < -1 ? -1.0 : s));
      final v = (clamped * 32767).round();
      view.setInt16(offset, v, Endian.little);
      offset += 2;
    }
    return out;
  }

  /// 解析 16-bit PCM WAV 的采样数与采样率（测试与自检用）。
  static ({int sampleRate, int samples}) inspect(Uint8List wav) {
    final view = ByteData.view(wav.buffer, wav.offsetInBytes, wav.lengthInBytes);
    final sampleRate = view.getUint32(24, Endian.little);
    final dataBytes = view.getUint32(40, Endian.little);
    return (sampleRate: sampleRate, samples: dataBytes ~/ 2);
  }
}
