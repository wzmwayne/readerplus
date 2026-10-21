import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/tts/wav_encoder.dart';

void main() {
  test('WAV 头字段正确（PCM/单声道/位深/长度）', () {
    final samples = Float32List.fromList([0.0, 0.5, -0.5, 1.5, -1.5]);
    final wav = WavEncoder.encode(samples, 22050);
    final view = ByteData.view(wav.buffer);

    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    expect(view.getUint16(20, Endian.little), 1); // PCM
    expect(view.getUint16(22, Endian.little), 1); // 单声道
    expect(view.getUint32(24, Endian.little), 22050);
    expect(view.getUint16(34, Endian.little), 16); // 位深
    expect(view.getUint32(40, Endian.little), samples.length * 2);
    expect(wav.length, 44 + samples.length * 2);
    expect(WavEncoder.inspect(wav), (sampleRate: 22050, samples: 5));
  });

  test('超范围采样被夹紧，不会溢出成反相噪声', () {
    final wav = WavEncoder.encode(Float32List.fromList([1.5, -1.5]), 16000);
    final view = ByteData.view(wav.buffer);
    expect(view.getInt16(44, Endian.little), 32767);
    expect(view.getInt16(46, Endian.little), -32767);
  });

  test('NaN 视为静音', () {
    final wav = WavEncoder.encode(Float32List.fromList([double.nan]), 16000);
    expect(ByteData.view(wav.buffer).getInt16(44, Endian.little), 0);
  });
}
