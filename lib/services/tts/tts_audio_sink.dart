import 'package:audioplayers/audioplayers.dart';

/// 音频播放抽象。
///
/// 控制器只依赖这个接口：
///   - 业务代码里没有任何平台分支（各端走同一条路径）
///   - 单元测试可以注入假实现，不需要音频插件与真实设备
abstract class TtsAudioSink {
  /// 播放一个音频地址（指向进程内的流式 HTTP 服务），
  /// 返回的 Future 在**播放结束**时完成。
  Future<void> playUrl(String url);

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  bool get isPlaying;

  Future<void> dispose();
}

/// 基于 audioplayers 的通用实现。
///
/// audioplayers 覆盖 android / ios / linux / macos / windows / web，API 完全一致，
/// 且各端播放器都支持 HTTP 流式播放，因此这里无需任何平台判断。
class AudioPlayersSink implements TtsAudioSink {
  AudioPlayersSink() {
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> playUrl(String url) async {
    _playing = true;
    await _player.play(UrlSource(url));
    await _player.onPlayerComplete.first;
    _playing = false;
  }

  @override
  Future<void> pause() async {
    _playing = false;
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    _playing = true;
    await _player.resume();
  }

  @override
  Future<void> stop() async {
    _playing = false;
    await _player.stop();
  }

  @override
  Future<void> dispose() => _player.dispose();
}
