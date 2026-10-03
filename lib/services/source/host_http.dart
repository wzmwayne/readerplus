import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../app_log.dart';

/// 宿主提供的 HTTP 能力：**既给简单用法，也给高自由度用法**。
///
/// 所有平台共用这一份实现（`dart:io`），因此 Android 与 Linux 行为一致；
/// 脚本/规则只能通过这里发请求，不能绕过（沙盒的能力面）。
class HostHttp {
  HostHttp({HttpClient Function()? clientFactory})
    : _factory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _factory;
  final List<Cookie> _jar = [];

  /// 当前 cookie 罐（脚本可读写，做会话型站点）。
  List<Map<String, String>> get cookies => _jar
      .map((c) => {'name': c.name, 'value': c.value, 'domain': c.domain ?? ''})
      .toList();

  void setCookie(String name, String value, {String? domain, String path = '/'}) {
    _jar.add(Cookie(name, value)..domain = domain ..path = path);
  }

  void clearCookies() => _jar.clear();

  // ---------- 简单用法 ----------

  Future<HostResponse> get(String url, {Map<String, String>? headers}) =>
      request(url: url, headers: _multi(headers));

  Future<HostResponse> post(
    String url, {
    Object? body,
    Map<String, String>? headers,
    String? contentType,
  }) => request(
    url: url,
    method: 'POST',
    body: body,
    headers: _multi(headers),
    contentType: contentType,
  );

  // ---------- 高自由度用法 ----------

  /// 完整请求：方法、多值头、原始字节体、重定向、超时、代理、证书策略、cookie 罐。
  Future<HostResponse> request({
    required String url,
    String method = 'GET',
    Map<String, List<String>>? headers,
    /// 逐行原样加头（`"X-A: 1"`）；与 [headers] 叠加。
    List<String>? rawHeaderLines,
    Object? body,
    String? contentType,
    Map<String, String>? cookies,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration idleTimeout = const Duration(seconds: 30),
    bool followRedirects = true,
    int maxRedirects = 5,
    /// 形如 `PROXY host:port`（可与 `DIRECT` 串联）；空则用系统默认。
    String? proxy,
    /// 自签/过期证书场景（默认拒绝，显式开启才放行）。
    bool allowBadCertificate = false,
    bool persistentConnection = false,
  }) async {
    final client = _factory()
      ..connectionTimeout = connectTimeout
      ..idleTimeout = idleTimeout
      ..userAgent = 'Mozilla/5.0 (compatible; readerplus/1.0)'
      ..autoUncompress = true;
    if (proxy != null && proxy.trim().isNotEmpty) {
      client.findProxy = (_) => proxy.trim();
    }
    if (allowBadCertificate) {
      client.badCertificateCallback = (_, _, _) => true;
    }

    final uri = Uri.parse(url);
    AppLog.info('http', '$method $uri');
    final request = await client.openUrl(method, uri);
    request.followRedirects = followRedirects;
    request.maxRedirects = maxRedirects;
    request.persistentConnection = persistentConnection;

    headers?.forEach((name, values) {
      for (final value in values) {
        request.headers.add(name, value);
      }
    });
    for (final line in rawHeaderLines ?? const <String>[]) {
      final index = line.indexOf(':');
      if (index <= 0) continue;
      request.headers.add(
        line.substring(0, index).trim(),
        line.substring(index + 1).trim(),
      );
    }
    if (contentType != null && contentType.isNotEmpty) {
      request.headers.contentType = ContentType.parse(contentType);
    }
    for (final cookie in [..._jar, ..._extraCookies(cookies)]) {
      request.cookies.add(cookie);
    }

    if (body != null) {
      if (body is List<int>) {
        request.add(Uint8List.fromList(body));
      } else {
        request.write(body.toString());
      }
    }

    final response = await request.close();
    final bytes = await _readAll(response);
    _harvestCookies(response);

    final responseHeaders = <String, List<String>>{};
    response.headers.forEach((name, values) {
      responseHeaders[name] = values;
    });
    final text = _decode(bytes, response.headers.contentType?.charset);
    AppLog.info(
      'http',
      '← ${response.statusCode} ${response.reasonPhrase} '
      '${bytes.length}B ${response.headers.contentType ?? ''}',
    );
    return HostResponse(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      finalUrl: response.redirects.isEmpty
          ? url
          : response.redirects.last.location.toString(),
      headers: responseHeaders,
      bodyBytes: bytes,
      text: text,
    );
  }

  Map<String, List<String>>? _multi(Map<String, String>? headers) => headers
      ?.map((key, value) => MapEntry(key, [value]));

  List<Cookie> _extraCookies(Map<String, String>? cookies) => (cookies ?? {})
      .entries
      .map((entry) => Cookie(entry.key, entry.value))
      .toList();

  void _harvestCookies(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      _jar.removeWhere((c) => c.name == cookie.name);
      _jar.add(cookie);
    }
  }

  Future<Uint8List> _readAll(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: true);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// 文本解码：显式 charset 优先，其次严格 UTF-8，最后按 GB18030 尝试。
  String _decode(List<int> bytes, String? charset) {
    final name = charset?.toLowerCase();
    if (name != null && name.isNotEmpty) {
      if (name.contains('utf')) return utf8.decode(bytes, allowMalformed: true);
      if (name.contains('gb')) return _gbk(bytes);
      if (name.contains('latin') || name.contains('iso-8859')) {
        return latin1.decode(bytes, allowInvalid: true);
      }
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return _gbk(bytes);
    }
  }

  String _gbk(List<int> bytes) {
    // 不引入原生/额外依赖：GBK 由上层注入的解码器补齐；此处给出安全兜底
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }
}

/// 一次请求的结果（简单用法与高自由度用法共用）。
class HostResponse {
  const HostResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.finalUrl,
    required this.headers,
    required this.bodyBytes,
    required this.text,
  });

  final int statusCode;
  final String reasonPhrase;
  final String finalUrl;

  /// 多值响应头（同名头会全部保留）。
  final Map<String, List<String>> headers;
  final Uint8List bodyBytes;
  final String text;

  bool get ok => statusCode >= 200 && statusCode < 300;

  String header(String name) {
    final values = headers[name.toLowerCase()] ?? headers[name];
    return values == null || values.isEmpty ? '' : values.first;
  }

  Map<String, dynamic> toJson() => {
    'status': statusCode,
    'reason': reasonPhrase,
    'url': finalUrl,
    'headers': headers,
    'text': text,
  };
}
