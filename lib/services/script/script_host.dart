import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../epub/epub_writer.dart';
import '../source/host_http.dart';
import '../txt/txt_to_epub.dart';
import 'crypto_ops.dart';

/// 宿主暴露给脚本的能力面（白名单）。
///
/// 设计原则：
/// - **只有这里列出的能力脚本才能使用**（没有文件系统、没有裸网络）⇒ 沙盒由能力决定；
/// - 所有函数都返回 Dart 原生值或 Future，脚本可 `await`；
/// - 脚本用 `host.result(...)` 交回结果（JSON 字符串或 Dart 值）。
class ScriptHost {
  ScriptHost({
    required this.onLog,
    HostHttp? http,
    this.timeout = const Duration(seconds: 60),
    Map<String, List<int>> inputs = const {},
    this.outputDir,
    Map<String, String> params = const {},
    this.askRelay,
  }) : http = http ?? HostHttp(),
       inputs = Map.unmodifiable(inputs),
       params = Map.unmodifiable(params);

  final void Function(String message) onLog;
  final HostHttp http;
  final Duration timeout;

  /// 向界面提问的往返通道（由引擎提供：发消息给主 isolate 并等回答）。
  /// 为 null 时 `ask` 直接返回 `{ok:false}`（无界面场景）。
  final Future<Map<String, Object?>> Function(
    String question,
    bool secret,
    String preset,
  )?
  askRelay;

  /// 每次运行的提问次数上限，防脚本狂弹框。
  static const int maxAsks = 10;
  int _askCount = 0;

  /// 本次运行的输入文件（宿主放入，脚本只读）。
  final Map<String, List<int>> inputs;

  /// 本次运行的产物目录（脚本用它写出 EPUB 等）。
  Directory? outputDir;

  /// 本次运行的参数（如 task/query/id）。
  final Map<String, String> params;

  /// 读参数（缺省返回空串）。
  String param(String name, [String fallback = '']) => params[name] ?? fallback;

  /// 脚本交回的结果（最后写入的生效）。
  Object? result;

  /// 结果到达通知：`.then(...)` 这类异步回填也能被引擎等到。
  final Completer<Object?> resultReady = Completer<Object?>();

  /// 等待脚本交回结果（超时由调用方控制）。
  Future<Object?> waitResult() async {
    if (result != null) return result;
    return resultReady.future;
  }

  // ---------- 日志 ----------
  void log(Object? message) => onLog('${message ?? ''}');

  // ---------- 询问用户（脚本用 .then 接回答；秘密询问不入日志）----------

  /// 向用户提问，返回 `{ok, answer}` 的 Future。
  ///
  /// - `secret: false`（默认，明文）：输入框正常显示，问题与回答都可入日志；
  /// - `secret: true`（秘密）：输入框遮挡，**回答内容绝不写日志**（只记录长度）；
  /// - 用户取消 / 无界面 / 超过 [maxAsks] 次 ⇒ `{ok:false, answer:''}`，脚本需自行处理；
  /// - 由 `.then(...)` 接续，无需轮询（isolate 事件循环负责调度）。
  Future<Map<String, Object?>> ask(
    String question, {
    bool secret = false,
    String preset = '',
  }) async {
    final text = question.trim();
    if (text.isEmpty) return {'ok': false, 'answer': ''};
    if (secret) {
      log('询问（秘密，回答不入日志）：$text');
    } else {
      log('询问：$text');
    }
    if (_askCount >= maxAsks) {
      log('提问次数已达上限（$maxAsks 次/每次运行），本次按取消处理');
      return {'ok': false, 'answer': ''};
    }
    _askCount++;
    final relay = askRelay;
    if (relay == null) {
      log('没有可用的界面来提问，已按取消处理');
      return {'ok': false, 'answer': ''};
    }
    final reply = await relay(text, secret, preset);
    final ok = reply['ok'] == true;
    final answer = '${reply['answer'] ?? ''}';
    if (!ok) {
      log('用户取消了本次询问');
      return {'ok': false, 'answer': ''};
    }
    if (secret) {
      log('已回答（秘密，${answer.length} 字符，内容不入日志）');
    } else {
      log('回答：$answer');
    }
    return {'ok': true, 'answer': answer};
  }

  // ---------- HTTP（简单 + 高自由度，见 HostHttp）----------
  Future<Map<String, dynamic>> httpGet(
    String url, {
    Map<String, String>? headers,
    bool includeBytes = false,
  }) async {
    final response = await http.get(
      url,
      headers: headers,
      includeBytes: includeBytes,
    );
    return response.toJson();
  }

  Future<Map<String, dynamic>> httpPost(
    String url, {
    Object? body,
    Map<String, String>? headers,
    String? contentType,
    bool includeBytes = false,
  }) async {
    final response = await http.post(
      url,
      body: body,
      headers: headers,
      contentType: contentType,
      includeBytes: includeBytes,
    );
    return response.toJson();
  }

  /// 高自由度请求：方法、多值头、逐行原头、字节体、cookie、重定向、代理、超时、证书策略。
  Future<Map<String, dynamic>> httpRequest(Map<String, dynamic> options) async {
    final response = await http.request(
      url: '${options['url']}',
      method: '${options['method'] ?? 'GET'}',
      headers: (options['headers'] as Map?)?.map(
        (key, value) => MapEntry(
          '$key',
          value is List ? value.map((v) => '$v').toList() : ['$value'],
        ),
      ),
      rawHeaderLines: (options['rawHeaderLines'] as List?)?.map((l) => '$l').toList(),
      body: options['body'],
      contentType: options['contentType']?.toString(),
      cookies: (options['cookies'] as Map?)?.map((k, v) => MapEntry('$k', '$v')),
      connectTimeout: _duration(options['connectTimeoutMs'], 10),
      idleTimeout: _duration(options['idleTimeoutMs'], 30),
      followRedirects: options['followRedirects'] as bool? ?? true,
      maxRedirects: int.tryParse('${options['maxRedirects'] ?? 5}') ?? 5,
      proxy: options['proxy']?.toString(),
      allowBadCertificate: options['allowBadCertificate'] as bool? ?? false,
      // wantBytes: true ⇒ 响应里额外带 bytes（原始字节列表）
      includeBytes: options['wantBytes'] as bool? ?? false,
    );
    return response.toJson();
  }

  static Duration _duration(Object? ms, int fallbackSeconds) {
    final value = int.tryParse('${ms ?? ''}');
    return value == null
        ? Duration(seconds: fallbackSeconds)
        : Duration(milliseconds: value);
  }

  // ---------- 文本/编码/正则/JSON ----------
  String decodeBytes(List<dynamic> bytes, [String encoding = 'auto']) =>
      decodeText(bytes.cast<int>(), encoding);

  String decodeText(List<int> bytes, [String encoding = 'auto']) {
    if (encoding.toLowerCase() == 'auto' || encoding.isEmpty) {
      try {
        return utf8.decode(bytes);
      } catch (_) {
        return _gbkOrReplace(bytes);
      }
    }
    final name = encoding.toLowerCase().replaceAll('_', '-');
    if (name.contains('utf')) return utf8.decode(bytes, allowMalformed: true);
    if (name.contains('gb')) return _gbkOrReplace(bytes);
    if (name.contains('latin') || name.contains('iso-8859')) {
      return latin1.decode(bytes, allowInvalid: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _gbkOrReplace(List<int> bytes) {
    // 由上层注入的解码器补齐；此处保持纯 Dart 兜底，绝不抛异常
    return latin1.decode(bytes, allowInvalid: true);
  }

  String regExp(String pattern, String input, [String group = '0']) {
    final match = RegExp(pattern, multiLine: true).firstMatch(input);
    if (match == null) return '';
    final index = int.tryParse(group) ?? 0;
    if (index == 0) return match.group(0) ?? '';
    return match.group(index) ?? '';
  }

  List<String> regExpAll(String pattern, String input, [String group = '0']) {
    final index = int.tryParse(group) ?? 0;
    return RegExp(pattern, multiLine: true)
        .allMatches(input)
        .map((m) => m.group(index) ?? '')
        .toList();
  }

  Object? jsonDecodeText(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  String jsonEncodeText(Object? value) => jsonEncode(value);

  String urlJoin(String base, String relative) =>
      Uri.parse(base).resolve(relative).toString();

  String urlEncode(String value) => Uri.encodeComponent(value);

  // ---------- 输入 / 输出 ----------

  /// 读输入文本（自动探测编码）。
  String inputText(String name, [String encoding = 'auto']) {
    final bytes = inputs[name] ?? (inputs.values.isEmpty ? null : inputs.values.first);
    if (bytes == null) throw StateError('没有输入文件：$name');
    return decodeText(bytes, encoding);
  }

  /// 读输入字节。
  List<int> inputBytes(String name) {
    final bytes = inputs[name] ?? (inputs.values.isEmpty ? null : inputs.values.first);
    if (bytes == null) throw StateError('没有输入文件：$name');
    return bytes;
  }

  /// 保存产物，返回完整路径。
  String saveOutput(String name, List<int> bytes) {    final dir = outputDir;
    if (dir == null) throw StateError('没有产物目录');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/$name');
    file.writeAsBytesSync(bytes, flush: true);
    onLog('已写出产物：${file.path}（${bytes.length} 字节）');
    return file.path;
  }

  // ---------- EPUB / 分章 / 清洗 ----------

  /// 生成 EPUB 3 字节（严格规范，见 EpubWriter）。
  List<int> epubBuild(Map<dynamic, dynamic> options) {
    final writer = EpubWriter(
      title: '${options['title'] ?? '未命名'}',
      author: '${options['author'] ?? '佚名'}',
      language: '${options['language'] ?? 'zh-CN'}',
    );
    final chapters = options['chapters'];
    if (chapters is List) {
      for (final chapter in chapters) {
        final map = (chapter as Map).cast<dynamic, dynamic>();
        writer.addChapter('${map['title'] ?? ''}', '${map['body'] ?? ''}');
      }
    }
    final cover = options['cover'];
    if (cover is List && cover.isNotEmpty) {
      writer.setCover(
        Uint8List.fromList(cover.cast<int>()),
        fileName: '${options['coverName'] ?? 'cover.jpg'}',
      );
    }
    return writer.build();
  }

  /// 按标题正则分章，返回 {title, body} 列表。
  List<Map<String, String>> splitChapters(String text, [String pattern = '']) {
    return TxtToEpub.splitChapters(
      text,
      pattern.isEmpty ? TxtToEpub.defaultChapterPattern : pattern,
    ).map((c) => {'title': c.title, 'body': c.body}).toList();
  }

  /// 规则清洗：rules 形如 [[正则, 替换], ...]。
  String cleanText(String text, List<dynamic> rules) {
    final parsed = rules
        .map((rule) => (rule as List).map((e) => '$e').toList())
        .toList();
    return TxtToEpub.applyRules(text, parsed);
  }

  // ---------- 密码学与压缩（自建/私人书源常用）----------

  /// 摘要：md5 / sha1 / sha256 / sha512，输入按 encoding 解释（utf8/base64/hex）。
  String digest(String algorithm, Object? input, [String encoding = 'utf8']) =>
      CryptoOps.digest(algorithm, input, encoding);

  /// HMAC：md5 / sha1 / sha256 / sha512。
  String hmac(
    String algorithm,
    Object? input,
    Object? key, [
    String encoding = 'utf8',
  ]) => CryptoOps.hmac(algorithm, input, key, encoding);

  String base64EncodeBytes(List<int> bytes) => CryptoOps.base64Encode(bytes);

  List<int> base64DecodeText(String text) => CryptoOps.base64Decode(text);

  String hexEncodeBytes(List<int> bytes) => CryptoOps.hexEncode(bytes);

  List<int> hexDecodeText(String text) => CryptoOps.hexDecode(text);

  /// AES：mode=ecb/cbc，padding=pkcs7/none/iso7816，密钥/输入/IV 各自可指定编码。
  List<int> aesDecrypt(Map<dynamic, dynamic> options) => _aes(options, true);

  List<int> aesEncrypt(Map<dynamic, dynamic> options) => _aes(options, false);

  List<int> _aes(Map<dynamic, dynamic> options, bool decrypt) {
    String text(Object? value, String fallback) =>
        value == null ? fallback : '$value';
    return CryptoOps.aes(
      data: options['data'],
      key: options['key'],
      mode: text(options['mode'], 'cbc'),
      iv: options['iv'],
      padding: text(options['padding'], 'pkcs7'),
      decrypt: decrypt,
      keyEncoding: text(options['keyEncoding'], 'utf8'),
      // 未显式指定时由 CryptoOps 按方向取默认（解密 base64 / 加密 utf8）
      inputEncoding: options['inputEncoding'] == null
          ? null
          : text(options['inputEncoding'], 'utf8'),
      ivEncoding: text(options['ivEncoding'], 'utf8'),
    );
  }

  /// 按字节 XOR（key 可反复使用）。
  List<int> xorBytes(List<int> bytes, Object? key, [String keyEncoding = 'utf8']) =>
      CryptoOps.xor(bytes, key, keyEncoding);

  /// gzip 解压（响应头缺失或 .gz 文件时用；带 Content-Encoding 的响应已自动解压）。
  List<int> gunzipBytes(List<int> bytes) => CryptoOps.gunzip(bytes);

  /// gzip 压缩。
  List<int> gzipBytes(List<int> bytes) => CryptoOps.gzipBytes(bytes);

  // ---------- 结果 ----------
  void setResult(Object? value) {
    result = value;
    if (!resultReady.isCompleted) resultReady.complete(value);
  }
}
