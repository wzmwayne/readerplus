import 'dart:convert';
import 'dart:io';

import 'package:fast_gbk/fast_gbk.dart';

import '../models/book.dart';

/// 本地 TXT 导入：识别编码、切分章节、写入自定义存储目录。
class TxtImporter {
  /// 章节标题匹配：第X章 / 第X节 / 第X回 / 第X卷，以及常见英文标记。
  static final RegExp _defaultTocRule = RegExp(
    r'^[ \t　]*('
    r'第[0-9零一二三四五六七八九十百千万两]+[章节節回卷篇]'
    r'|Chapter\s*\d+'
    r'|[0-9]{1,4}[、.．]\s*\S{1,30}'
    r')',
    multiLine: true,
  );

  /// 读取文件并按规则切分。返回正文与章节列表。
  static Future<({String content, List<Chapter> chapters})> parseFile(
    File file, {
    RegExp? tocRule,
  }) async {
    final bytes = await file.readAsBytes();
    return parseBytes(bytes, tocRule: tocRule);
  }

  static ({String content, List<Chapter> chapters}) parseBytes(
    List<int> bytes, {
    RegExp? tocRule,
  }) {
    final content = decodeBytes(bytes);
    return splitChapters(content, tocRule: tocRule);
  }

  /// UTF-8 优先，失败则按 GBK 解码。
  static String decodeBytes(List<int> bytes) {
    var data = bytes;
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      data = data.sublist(3);
    }
    try {
      return utf8.decode(data);
    } on FormatException {
      try {
        return gbk.decode(data);
      } catch (_) {
        return utf8.decode(data, allowMalformed: true);
      }
    }
  }

  /// 依据标题行切分正文，返回 [start, end) 区间。
  ///
  /// 只把「短行、且不含句读」的匹配视为标题，
  /// 避免正文中形如「第二章的正文内容，……」的句子被误判成章节。
  static ({String content, List<Chapter> chapters}) splitChapters(
    String content, {
    RegExp? tocRule,
  }) {
    final rule = tocRule ?? _defaultTocRule;
    final sentencePunctuation = RegExp(r'[。！？；，]');
    final found = <({int start, String line})>[];
    for (final match in rule.allMatches(content)) {
      var lineEnd = content.indexOf('\n', match.start);
      if (lineEnd == -1) lineEnd = content.length;
      final line = content.substring(match.start, lineEnd).trim();
      if (line.isEmpty || line.length > 40) continue;
      if (sentencePunctuation.hasMatch(line)) continue;
      found.add((start: match.start, line: line));
    }

    if (found.isEmpty) {
      return (
        content: content,
        chapters: [
          Chapter(index: 0, title: '全文', start: 0, end: content.length),
        ],
      );
    }

    final chapters = <Chapter>[];
    for (var i = 0; i < found.length; i++) {
      final start = i == 0 ? 0 : found[i].start;
      final end = i == found.length - 1 ? content.length : found[i + 1].start;
      chapters.add(
        Chapter(index: i, title: found[i].line, start: start, end: end),
      );
    }
    return (content: content, chapters: chapters);
  }

  /// 从文件名或首行猜测书名与作者。
  static ({String title, String author}) guessMeta(File file, String content) {
    var title = file.uri.pathSegments.last.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
    var author = '';
    final byPattern = RegExp(r'作者[：:]\s*(\S+)');
    final head = content.length > 800 ? content.substring(0, 800) : content;
    final m = byPattern.firstMatch(head);
    if (m != null) author = m.group(1)!.trim();
    final titlePattern = RegExp(r'《(.+?)》');
    final tm = titlePattern.firstMatch(head);
    if (tm != null) title = tm.group(1)!.trim();
    return (title: title.trim(), author: author);
  }
}
