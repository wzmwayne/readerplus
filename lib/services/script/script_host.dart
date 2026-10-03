import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../epub/epub_writer.dart';
import '../source/host_http.dart';
import '../txt/txt_to_epub.dart';

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
  }) : http = http ?? HostHttp(),
       inputs = Map.unmodifiable(inputs),
       params = Map.unmodifiable(params);

  final void Function(String message) onLog;
  final HostHttp http;
  final Duration timeout;

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
  String saveOutput(String name, List<int> bytes) {
    final dir = outputDir;
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

  // ---------- 结果 ----------
  void setResult(Object? value) {
    result = value;
    if (!resultReady.isCompleted) resultReady.complete(value);
  }
}
