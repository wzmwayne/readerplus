import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// 远程文件条目。
class RemoteEntry {
  const RemoteEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    this.lastModified,
  });

  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;
}

/// 最小 WebDAV 客户端：Basic 认证 + PROPFIND/PUT/GET/MKCOL/DELETE/MOVE。
/// 兼容 Nextcloud、坚果云、Alist 等常见实现。
class WebDavClient {
  WebDavClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;
  final http.Client _client;

  Map<String, String> get _headers => {
    'Authorization':
        'Basic ${base64Encode(utf8.encode('$username:$password'))}',
  };

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final clean = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base${Uri.encodeFull(clean)}');
  }

  Future<bool> test() async {
    try {
      final res = await _request('PROPFIND', '', depth: '0');
      return res.statusCode == 207 || res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _request(
    String method,
    String path, {
    String? depth,
    List<int>? body,
    Map<String, String>? extraHeaders,
  }) async {
    final request = http.Request(method, _uri(path));
    request.headers.addAll(_headers);
    if (depth != null) request.headers['Depth'] = depth;
    if (extraHeaders != null) request.headers.addAll(extraHeaders);
    if (body != null) request.bodyBytes = Uint8List.fromList(body);
    final streamed = await _client.send(request).timeout(const Duration(seconds: 60));
    return http.Response.fromStream(streamed);
  }

  Future<bool> exists(String path) async {
    final res = await _request('PROPFIND', path, depth: '0');
    return res.statusCode == 207;
  }

  Future<void> mkcol(String path) async {
    final res = await _request('MKCOL', path);
    // 405 表示已存在。
    if (res.statusCode >= 400 && res.statusCode != 405) {
      throw WebDavException('创建目录失败 ${res.statusCode}: $path');
    }
  }

  /// 递归创建目录。
  Future<void> ensureDir(String path) async {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    var current = '';
    for (final seg in segments) {
      current = '$current/$seg';
      await mkcol(current);
    }
  }

  Future<void> put(String path, List<int> bytes) async {
    final res = await _request(
      'PUT',
      path,
      body: bytes,
      extraHeaders: {'Content-Type': 'application/octet-stream'},
    );
    if (res.statusCode >= 400) {
      throw WebDavException('上传失败 ${res.statusCode}: $path');
    }
  }

  Future<Uint8List?> get(String path) async {
    final res = await _request('GET', path);
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) {
      throw WebDavException('下载失败 ${res.statusCode}: $path');
    }
    return res.bodyBytes;
  }

  Future<void> delete(String path) async {
    final res = await _request('DELETE', path);
    if (res.statusCode >= 400 && res.statusCode != 404) {
      throw WebDavException('删除失败 ${res.statusCode}: $path');
    }
  }

  Future<List<RemoteEntry>> list(String path) async {
    final res = await _request('PROPFIND', path, depth: '1');
    if (res.statusCode == 404) return const [];
    if (res.statusCode != 207) {
      throw WebDavException('列目录失败 ${res.statusCode}: $path');
    }
    return _parseMultiStatus(res.body);
  }

  List<RemoteEntry> _parseMultiStatus(String body) {
    final entries = <RemoteEntry>[];
    final doc = XmlDocument.parse(body);
    for (final response in doc.findAllElements('response')) {
      final href = response.getElement('href')?.innerText.trim() ?? '';
      if (href.isEmpty) continue;
      final isDir = response
          .findAllElements('collection')
          .isNotEmpty;
      final sizeText = _propText(response, 'getcontentlength');
      final modified = _propText(response, 'getlastmodified');
      entries.add(
        RemoteEntry(
          path: Uri.decodeFull(href),
          isDirectory: isDir,
          size: int.tryParse(sizeText ?? '') ?? 0,
          lastModified: modified == null ? null : DateTime.tryParse(modified),
        ),
      );
    }
    return entries;
  }

  String? _propText(XmlElement element, String name) {
    for (final e in element.findAllElements(name)) {
      return e.innerText.trim();
    }
    return null;
  }

  void close() => _client.close();
}

class WebDavException implements Exception {
  WebDavException(this.message);
  final String message;

  @override
  String toString() => message;
}
