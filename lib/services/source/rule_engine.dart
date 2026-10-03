import 'dart:convert';

import 'package:xml/xml.dart';

import 'host_http.dart';

import '../app_log.dart';
import 'rule_source.dart';

/// 规则引擎：纯 Dart 执行声明式书源（跨端一致、无原生层、可硬超时）。
class RuleEngine {
  RuleEngine({HostHttp? http}) : _http = http ?? HostHttp();

  /// 与脚本插件共用同一套宿主 HTTP（同一条网络栈，含高自由度能力）。
  final HostHttp _http;

  void dispose() {}

  /// 展开模板：{{query}} / {{page}} / {{id}} 等。
  String _template(String template, Map<String, String> values) {
    var result = template;
    values.forEach((key, value) {
      result = result.replaceAll('{{$key}}', Uri.encodeQueryComponent(value));
    });
    return result;
  }

  Future<String> _fetch(RuleRequest request, Map<String, String> values) async {
    final url = _template(request.url, values);
    final headers = {
      'User-Agent': 'Mozilla/5.0 (compatible; readerplus/1.0)',
      ...request.headers,
    };
    AppLog.info('source', '规则请求：${request.method} $url');
    final response = await _http.request(
      url: url,
      method: request.method,
      headers: headers.map((key, value) => MapEntry(key, [value])),
      body: request.body.isEmpty ? null : _template(request.body, values),
    );
    if (!response.ok) {
      throw StateError('HTTP ${response.statusCode}：$url');
    }
    // 编码：优先规则指定，其次响应头 charset，最后按内容探测
    final bytes = response.bodyBytes;
    final declared = request.encoding.toLowerCase();
    if (declared != 'auto' && declared.isNotEmpty) {
      return _decode(bytes, declared);
    }
    final contentType = response.header('content-type');
    final charset = RegExp(r'charset=([\w-]+)')
        .firstMatch(contentType)
        ?.group(1);
    if (charset != null) return _decode(bytes, charset);
    return _decode(bytes, 'auto');
  }

  String _decode(List<int> bytes, String encoding) {
    if (encoding == 'auto') {
      try {
        return utf8.decode(bytes);
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
    if (encoding.replaceAll('_', '-').toLowerCase().startsWith('utf-8') ||
        encoding.toLowerCase() == 'utf8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    // 其它编码（GBK/GB18030 等）交由上层注入的解码器处理；
    // 这里保持纯 Dart 兜底，不引入原生依赖。
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 解析响应体为「可选择的文档」。
  Object? _parse(RuleRequest request, String body) {
    switch (request.format) {
      case RuleFormat.json:
        try {
          return jsonDecode(body);
        } catch (_) {
          return null;
        }
      case RuleFormat.xml:
      case RuleFormat.html:
        try {
          return XmlDocument.parse(body);
        } catch (_) {
          return null;
        }
      case RuleFormat.text:
        return body;
    }
  }

  /// 选择器：支持 `a.b[0].c`、`a.*`、`a[*]`；空选择器表示自身。
  Object? select(Object? document, String path) {
    final selector = path.trim();
    if (selector.isEmpty || selector == '\$' || selector == '.') return document;
    Object? current = document;
    for (final rawPart in _splitPath(selector)) {
      if (current == null) return null;
      final part = rawPart.trim();
      if (part.isEmpty || part == '\$') continue;

      if (current is XmlDocument) {
        final list = current.findAllElements(part).toList();
        if (list.isEmpty) return null;
        current = list.length == 1 ? list.first : list;
        continue;
      }
      if (current is XmlElement) {
        final list = current.findElements(part).toList();
        if (list.isEmpty) return null;
        current = list.length == 1 ? list.first : list;
        continue;
      }
      if (current is List && current.isNotEmpty && current.first is XmlElement) {
        final list = <XmlElement>[];
        for (final node in current) {
          if (node is XmlElement) list.addAll(node.findElements(part));
        }
        if (list.isEmpty) return null;
        current = list.length == 1 ? list.first : list;
        continue;
      }

      final indexMatch = RegExp(r'^(.*?)\[(\d+|\*)\]$').firstMatch(part);
      var key = indexMatch?.group(1) ?? part;
      final index = indexMatch?.group(2);
      if (key.startsWith(r'$.')) key = key.substring(2);

      if (key.isNotEmpty) {
        if (current is Map) {
          final map = current;
          current = map[key] ?? map[key.toString()];
          if (current == null && key.contains('/')) {
            // 允许 `formats.image/jpeg`：含斜杠的键整体匹配
            for (final entry in map.entries) {
              if ('${entry.key}'.contains(key)) {
                current = entry.value;
                break;
              }
            }
          }
        } else if (current is List) {
          // 列表上直接取键：映射到每项
          current = current.map((item) => select(item, key)).toList();
        } else {
          return null;
        }
      }

      if (index != null) {
        if (current is List) {
          if (index == '*') continue;
          final i = int.tryParse(index);
          if (i == null || i < 0 || i >= current.length) return null;
          current = current[i];
        } else {
          return null;
        }
      }
    }
    return current;
  }

  List<String> _splitPath(String path) {
    final parts = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < path.length; i++) {
      final char = path[i];
      if (char == '.' ) {
        // `formats.image/jpeg`：斜杠不是分隔符，保持原样
        parts.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    parts.add(buffer.toString());
    return parts.where((p) => p.isNotEmpty).toList();
  }

  Object? _value(RuleRequest request, Object? document, String selector) {
    if (selector.trim().isEmpty) return null;
    return select(document, selector);
  }

  String _text(Object? value) {
    if (value == null) return '';
    if (value is XmlNode) return value.innerText.trim();
    if (value is String) return value.trim();
    if (value is List) {
      return value.isEmpty ? '' : _text(value.first);
    }
    return value.toString().trim();
  }

  /// 搜索：返回与 Python 书源同构的条目。
  Future<List<Map<String, String>>> search(
    RuleSource source,
    String query, {
    int page = 1,
  }) async {
    final body = await _fetch(source.search, {
      'query': query,
      'page': '$page',
    });
    final document = _parse(source.search, body);
    if (document == null) {
      AppLog.error('source', '规则解析失败（格式 ${source.search.format.name}）');
      return const [];
    }

    final listSelector = source.search.list;
    Object? items;
    if (listSelector.isEmpty) {
      items = document;
    } else {
      // 列表选择器形如 `results[*]`
      final match = RegExp(r'^(.*?)\[(\*)\]$').firstMatch(listSelector.trim());
      final path = match?.group(1) ?? listSelector;
      final value = select(document, path);
      if (value is List) {
        items = value;
      } else if (value is XmlNode) {
        items = value is XmlDocument ? value.rootElement.children : [value];
      } else if (value != null) {
        items = [value];
      }
    }
    if (items is XmlNode && items is XmlDocument) {
      items = items.rootElement.children.whereType<XmlElement>().toList();
    }
    if (items is! List) {
      items = items == null ? const [] : [items];
    }

    final results = <Map<String, String>>[];
    for (final item in items) {
      final entry = <String, String>{};
      source.search.fields.forEach((key, selector) {
        entry[key] = _text(_value(source.search, item, selector));
      });
      if ((entry['id'] ?? '').isEmpty) continue;
      results.add(entry);
    }
    AppLog.info('source', '规则搜索完成：命中 ${results.length} 条');
    return results;
  }

  /// 详情：字段 + 简介 + 封面地址。
  Future<Map<String, String>> detail(
    RuleSource source,
    String id,
  ) async {
    final request = source.detail ?? source.search;
    final body = await _fetch(request, {'id': id});
    final document = _parse(request, body);
    final result = <String, String>{'id': id};
    if (document == null) return result;
    request.fields.forEach((key, selector) {
      result[key] = _text(_value(request, document, selector));
    });
    if (request.description.isNotEmpty) {
      result['description'] = _text(_value(request, document, request.description));
    }
    if (request.cover.isNotEmpty) {
      result['cover'] = _text(_value(request, document, request.cover));
    }
    return result;
  }

  /// 下载：取回正文文本（EPUB 组装由 TxtToEpub 负责）。
  Future<String> downloadText(RuleSource source, String id) async {
    final request = source.download;
    if (request == null) throw StateError('该书源未声明下载规则');
    final body = await _fetch(request, {'id': id});
    return switch (request.format) {
      RuleFormat.json => () {
        final document = _parse(request, body);
        final text = _text(_value(request, document, 'text'));
        return text.isEmpty ? body : text;
      }(),
      _ => body,
    };
  }
}
