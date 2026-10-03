import 'dart:convert';

import '../source/host_http.dart';

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
  }) : http = http ?? HostHttp();

  final void Function(String message) onLog;
  final HostHttp http;
  final Duration timeout;

  /// 脚本交回的结果（最后写入的生效）。
  Object? result;

  // ---------- 日志 ----------
  void log(Object? message) => onLog('${message ?? ''}');

  // ---------- HTTP（简单 + 高自由度，见 HostHttp）----------
  Future<Map<String, dynamic>> httpGet(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await http.get(url, headers: headers);
    return response.toJson();
  }

  Future<Map<String, dynamic>> httpPost(
    String url, {
    Object? body,
    Map<String, String>? headers,
    String? contentType,
  }) async {
    final response = await http.post(
      url,
      body: body,
      headers: headers,
      contentType: contentType,
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

  // ---------- 结果 ----------
  void setResult(Object? value) => result = value;
}
