import 'dart:convert';

/// 声明式书源（规则型）：纯 Dart 解释执行，跨端行为完全一致。
///
/// 规则文件示例（JSON）：
/// ```json
/// {
///   "id": "gutenberg",
///   "name": "古腾堡（示例）",
///   "version": 1,
///   "search": {
///     "url": "https://gutendex.com/books?search={{query}}&page={{page}}",
///     "format": "json",
///     "list": "results[*]",
///     "fields": {
///       "id": "id",
///       "title": "title",
///       "author": "authors[0].name",
///       "cover": "formats.image/jpeg",
///       "intro": "subjects[0]"
///     }
///   },
///   "detail": {
///     "url": "https://gutendex.com/books/{{id}}",
///     "format": "json",
///     "fields": { "title": "title", "author": "authors[0].name" },
///     "description": "summaries[0]",
///     "cover": "formats.image/jpeg"
///   },
///   "download": {
///     "url": "https://www.gutenberg.org/cache/epub/{{id}}/pg{{id}}.txt",
///     "format": "text",
///     "chapter_pattern": "^第[一二三四五六七八九十百千两0-9]+[章回节卷].*$"
///   }
/// }
/// ```
class RuleSource {
  const RuleSource({
    required this.id,
    required this.name,
    this.version = 1,
    this.author = '',
    this.description = '',
    required this.search,
    this.detail,
    this.download,
  });

  final String id;
  final String name;
  final int version;
  final String author;
  final String description;
  final RuleRequest search;
  final RuleRequest? detail;
  final RuleRequest? download;

  Set<String> get capabilities => {
    'search',
    if (detail != null) 'detail',
    if (download != null) 'download',
  };

  static RuleSource? parse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      final searchRaw = map['search'];
      if (searchRaw is! Map) return null;
      return RuleSource(
        id: (map['id'] ?? '').toString(),
        name: (map['name'] ?? '').toString(),
        version: int.tryParse('${map['version'] ?? 1}') ?? 1,
        author: (map['author'] ?? '').toString(),
        description: (map['description'] ?? '').toString(),
        search: RuleRequest.fromJson(searchRaw.cast<String, dynamic>()),
        detail: map['detail'] is Map
            ? RuleRequest.fromJson((map['detail'] as Map).cast<String, dynamic>())
            : null,
        download: map['download'] is Map
            ? RuleRequest.fromJson(
                (map['download'] as Map).cast<String, dynamic>(),
              )
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

enum RuleFormat { json, xml, text, html }

/// 一次请求 + 一次抽取。
class RuleRequest {
  const RuleRequest({
    required this.url,
    required this.format,
    this.method = 'GET',
    this.headers = const {},
    this.body = '',
    this.list = '',
    this.fields = const {},
    this.description = '',
    this.cover = '',
    this.chapterPattern = '',
    this.encoding = 'auto',
  });

  final String url;
  final RuleFormat format;
  final String method;
  final Map<String, String> headers;
  final String body;

  /// 列表选择器（如 `results[*]`）；搜索结果用。
  final String list;

  /// 字段选择器（相对列表项 / 相对根）。
  final Map<String, String> fields;

  /// 简介选择器（详情用）。
  final String description;

  /// 封面选择器（详情用）。
  final String cover;

  /// 下载：按此正则分章（空则整本当一章）。
  final String chapterPattern;

  final String encoding;

  static RuleRequest fromJson(Map<String, dynamic> json) => RuleRequest(
    url: (json['url'] ?? '').toString(),
    format: switch ((json['format'] ?? 'json').toString().toLowerCase()) {
      'xml' => RuleFormat.xml,
      'text' => RuleFormat.text,
      'html' => RuleFormat.html,
      _ => RuleFormat.json,
    },
    method: (json['method'] ?? 'GET').toString().toUpperCase(),
    headers: ((json['headers'] as Map?) ?? const {})
        .map((key, value) => MapEntry('$key', '$value')),
    body: (json['body'] ?? '').toString(),
    list: (json['list'] ?? '').toString(),
    fields: ((json['fields'] as Map?) ?? const {})
        .map((key, value) => MapEntry('$key', '$value')),
    description: (json['description'] ?? '').toString(),
    cover: (json['cover'] ?? '').toString(),
    chapterPattern: (json['chapter_pattern'] ?? '').toString(),
    encoding: (json['encoding'] ?? 'auto').toString(),
  );
}
