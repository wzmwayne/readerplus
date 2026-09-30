import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'edge_ws.dart';

/// Edge TTS 音色。
class TtsVoice {
  const TtsVoice({
    required this.shortName,
    required this.locale,
    required this.gender,
    required this.friendlyName,
  });

  final String shortName;
  final String locale;
  final String gender;
  final String friendlyName;

  /// 中文音色（zh-CN / zh-HK / zh-TW 等）。
  bool get isChinese => locale.toLowerCase().startsWith('zh');

  /// 仅凭 shortName 推导展示名，例如「Xiaoxiao · zh-CN」（无需联网）。
  static String labelOf(String shortName) {
    final parts = shortName.split('-');
    if (parts.length < 3) return shortName;
    final locale = '${parts[0]}-${parts[1]}';
    final name = parts.sublist(2).join('-').replaceAll('Neural', '');
    return '$name · $locale';
  }

  /// 展示名，例如「晓晓（女声）· zh-CN」。
  String get label {
    final short = shortName.split('-').last.replaceAll('Neural', '');
    final genderCn = gender.toLowerCase() == 'female' ? '女声' : '男声';
    return '$short（$genderCn）· $locale';
  }

  static TtsVoice fromJson(Map<String, dynamic> json) => TtsVoice(
    shortName: (json['ShortName'] ?? json['shortName'] ?? '') as String,
    locale: (json['Locale'] ?? json['locale'] ?? '') as String,
    gender: (json['Gender'] ?? json['gender'] ?? '') as String,
    friendlyName:
        (json['FriendlyName'] ?? json['friendlyName'] ?? '') as String,
  );

  /// 解析音色列表并筛出中文音色（按 locale、名称排序）。
  static List<TtsVoice> parseChinese(List<dynamic> raw) {
    final voices = <TtsVoice>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final voice = TtsVoice.fromJson(item.cast<String, dynamic>());
      if (voice.shortName.isEmpty) continue;
      if (!voice.isChinese) continue;
      voices.add(voice);
    }
    voices.sort((a, b) {
      final byLocale = a.locale.compareTo(b.locale);
      return byLocale != 0 ? byLocale : a.shortName.compareTo(b.shortName);
    });
    return voices;
  }
}

/// 微软 Edge 在线朗读（edge-tts）流式合成客户端。
///
/// 协议细节参考 wzmwayne/edge-tts-engine：
///   - 端点：wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1
///   - 鉴权：TrustedClientToken + Sec-MS-GEC（文件时间戳按 300 秒取整后与令牌拼接做 SHA-256）
///   - 会话：先发 speech.config，再发 ssml；二进制帧前 2 字节为大端头长度，
///     头里含 `Path:audio` 时其后为 mp3 数据；文本帧 `Path:turn.end` 表示结束
class EdgeTtsClient {
  const EdgeTtsClient._();

  static const trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const _winEpoch = 11644473600;
  static const _chromiumVersion = '143';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0';
  static const _host = 'speech.platform.bing.com';
  static const _path = '/consumer/speech/synthesize/readaloud/edge/v1';
  static const _voicesUrl =
      'https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/voices/list';

  /// 输出格式：24kHz 48kbps 单声道 mp3，体积小且音质够用。
  static const outputFormat = 'audio-24khz-48kbitrate-mono-mp3';

  /// Sec-MS-GEC 令牌。同一 5 分钟窗口内结果一致，便于缓存与复用连接。
  static String secMsGec([DateTime? now]) {
    final time = (now ?? DateTime.now()).toUtc();
    var ticks = time.millisecondsSinceEpoch ~/ 1000 + _winEpoch;
    ticks -= ticks % 300;
    // Windows FILETIME 以 100 纳秒为单位，必须再乘 10^7（参考实现同此）
    ticks *= 10000000;
    return sha256
        .convert(utf8.encode('$ticks$trustedClientToken'))
        .toString()
        .toUpperCase();
  }

  static String buildSsml({
    required String voice,
    required String text,
    String rate = '+0%',
    String pitch = '+0Hz',
    String volume = '+0%',
  }) =>
      "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis'"
      " xml:lang='en-US'>"
      "<voice name='$voice'>"
      "<prosody pitch='$pitch' rate='$rate' volume='$volume'>"
      '${escapeXml(text)}'
      '</prosody></voice></speak>';

  /// speech.config 消息（含 WebSocket 头部块），与参考实现一致。
  static String buildConfigMessage([DateTime? now]) =>
      'X-Timestamp:${_timestamp(now)}\r\n'
      'Content-Type:application/json; charset=utf-8\r\n'
      'Path:speech.config\r\n\r\n'
      '{"context":{"synthesis":{"audio":{"metadataoptions":'
      '{"sentenceBoundaryEnabled":"true","wordBoundaryEnabled":"false"},'
      '"outputFormat":"$outputFormat"}}}}\r\n';

  /// ssml 消息（含 WebSocket 头部块）。
  /// X-RequestId 用于服务端关联本次合成请求，缺失会导致服务端不回任何数据。
  static String buildSsmlMessage({
    required String voice,
    required String text,
    String rate = '+0%',
    String pitch = '+0Hz',
    DateTime? now,
  }) =>
      'X-RequestId:${_uuid()}\r\n'
      'Content-Type:application/ssml+xml\r\n'
      'X-Timestamp:${_timestamp(now)}Z\r\n'
      'Path:ssml\r\n\r\n'
      '${buildSsml(voice: voice, text: text, rate: rate, pitch: pitch)}';

  static String escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// X-Timestamp 采用服务端接受的格式：
  /// `EEE MMM dd yyyy HH:mm:ss GMT+0000 (Coordinated Universal Time)`
  static String _timestamp([DateTime? now]) {
    final t = (now ?? DateTime.now()).toUtc();
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${weekdays[t.weekday - 1]} ${months[t.month - 1]} ${two(t.day)} ${t.year} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)} '
        'GMT+0000 (Coordinated Universal Time)';
  }

  static String _uuid() {
    final rnd = Random.secure();
    return List.generate(
      32,
      (_) => rnd.nextInt(16).toRadixString(16),
    ).join();
  }

  /// 建立一次合成会话，返回 mp3 字节流（边收边吐）。
  static Stream<List<int>> synthesize({
    required String text,
    required String voice,
    String rate = '+0%',
    String pitch = '+0Hz',
  }) {
    final controller = StreamController<List<int>>();
    EdgeWebSocket? socket;
    var finished = false;

    Future<void> close() async {
      if (finished) return;
      finished = true;
      try {
        await socket?.close();
      } catch (_) {}
      if (!controller.isClosed) await controller.close();
    }

    () async {
      try {
        final uri = Uri.parse(
          'wss://$_host$_path'
          '?TrustedClientToken=$trustedClientToken'
          '&ConnectionId=${_uuid()}'
          '&Sec-MS-GEC=${secMsGec()}'
          '&Sec-MS-GEC-Version=1-$_chromiumVersion.0.3650.75',
        );
        // 握手头部与社区实现一致：Origin 必须是这个扩展 ID，
        // 且必须带 Cookie: muid=<32 位大写十六进制>;
        socket = await EdgeWebSocket.connect(
          uri,
          headers: {
            'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
            'User-Agent': _userAgent,
            'Pragma': 'no-cache',
            'Cache-Control': 'no-cache',
            'Cookie': 'muid=${_uuid().toUpperCase()};',
          },
        );
        socket!.sendText(buildConfigMessage());
        socket!.sendText(
          buildSsmlMessage(voice: voice, text: text, rate: rate, pitch: pitch),
        );

        socket!.events.listen(
          (event) {
            if (event is String) {
              if (event.contains('Path:turn.end')) close();
              return;
            }
            if (event is! List<int> || event.length < 2) return;
            final headerLength = (event[0] << 8) | event[1];
            if (event.length < 2 + headerLength) return;
            final header = utf8.decode(
              event.sublist(2, 2 + headerLength),
              allowMalformed: true,
            );
            if (!header.contains('Path:audio')) return;
            final audio = event.sublist(2 + headerLength);
            if (audio.isNotEmpty && !controller.isClosed) controller.add(audio);
          },
          onError: (Object e, StackTrace s) {
            if (!controller.isClosed) controller.addError(e, s);
            close();
          },
          onDone: close,
          cancelOnError: true,
        );
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
        await close();
      }
    }();

    return controller.stream;
  }

  /// 内置中文音色：联网失败时兜底，保证音色选择与试听始终可用。
  static const List<({String shortName, String gender})> builtinChineseVoices = [
    (shortName: 'zh-CN-XiaoxiaoNeural', gender: 'Female'),
    (shortName: 'zh-CN-XiaoyiNeural', gender: 'Female'),
    (shortName: 'zh-CN-YunxiNeural', gender: 'Male'),
    (shortName: 'zh-CN-YunjianNeural', gender: 'Male'),
    (shortName: 'zh-CN-YunyangNeural', gender: 'Male'),
    (shortName: 'zh-CN-YunxiaNeural', gender: 'Male'),
    (shortName: 'zh-CN-liaoning-XiaobeiNeural', gender: 'Female'),
    (shortName: 'zh-CN-shaanxi-XiaoniNeural', gender: 'Female'),
    (shortName: 'zh-HK-HiuMaanNeural', gender: 'Female'),
    (shortName: 'zh-HK-HiuGaaiNeural', gender: 'Female'),
    (shortName: 'zh-HK-WanLungNeural', gender: 'Male'),
    (shortName: 'zh-TW-HsiaoChenNeural', gender: 'Female'),
    (shortName: 'zh-TW-HsiaoYuNeural', gender: 'Female'),
    (shortName: 'zh-TW-YunJheNeural', gender: 'Male'),
  ];

  /// 内置音色列表（[TtsVoice] 形式）。
  static List<TtsVoice> get builtinVoices => builtinChineseVoices
      .map(
        (v) => TtsVoice(
          shortName: v.shortName,
          locale: v.shortName.split('-').take(2).join('-'),
          gender: v.gender,
          friendlyName: v.shortName,
        ),
      )
      .toList();

  static List<TtsVoice>? _cachedVoices;

  /// 上次成功拉取的音色（可空）。
  static List<TtsVoice>? get cachedVoices => _cachedVoices;

  /// 拉取音色列表并筛出中文音色；失败时回退到内置列表。
  static Future<List<TtsVoice>> loadChineseVoices({
    bool forceRefresh = false,
    HttpClient? httpClient,
  }) async {
    if (!forceRefresh && _cachedVoices != null) return _cachedVoices!;
    try {
      final voices = await fetchChineseVoices(httpClient: httpClient);
      if (voices.isNotEmpty) {
        _cachedVoices = voices;
        return voices;
      }
    } catch (_) {}
    return _cachedVoices ?? builtinVoices;
  }

  /// 拉取音色列表并筛出中文音色。
  static Future<List<TtsVoice>> fetchChineseVoices({
    HttpClient? httpClient,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final client = httpClient ?? HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse('$_voicesUrl?trustedclienttoken=$trustedClientToken'))
          .timeout(timeout);
      request.headers.set('User-Agent', 'Mozilla/5.0');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        throw HttpException('音色列表请求失败：HTTP ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! List) throw const FormatException('音色列表格式异常');
      return TtsVoice.parseChinese(decoded);
    } finally {
      client.close(force: true);
    }
  }
}
