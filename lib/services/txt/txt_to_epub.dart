import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

import '../epub/epub_writer.dart';

/// 纯 Dart 的 TXT → EPUB 3（不依赖任何原生运行时）。
///
/// 与 Python 版 `python/app/readerplus_epub.py` + `python/examples/txt_cleaner.py`
/// 的行为对齐：编码探测 → 规则清洗 → 正则分章 → EPUB 3 打包。
class TxtToEpub {
  TxtToEpub._();

  static const String defaultChapterPattern =
      r'^第[一二三四五六七八九十百千两0-9]+[章回节卷].*$';

  /// 编码探测：优先 UTF-8，失败退 GB18030，再退 Latin-1（替换非法字节）。
  static String decode(List<int> bytes, {String encoding = 'auto'}) {
    final preferred = encoding.trim().toLowerCase();
    if (preferred.isNotEmpty && preferred != 'auto') {
      return _decodeWith(bytes, preferred);
    }
    try {
      return utf8.decode(bytes); // 严格模式：非法字节会抛异常
    } catch (_) {}
    try {
      return gbk.decode(bytes);
    } catch (_) {}
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _decodeWith(List<int> bytes, String encoding) {
    switch (encoding.replaceAll('_', '-')) {
      case 'utf-8':
      case 'utf8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'gbk':
      case 'gb18030':
      case 'gb2312':
        try {
          return gbk.decode(bytes);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      default:
        return latin1.decode(bytes, allowInvalid: true);
    }
  }

  /// 规则清洗：每条规则是 [正则, 替换]。
  ///
  /// 兼容 Python/JS 风格的内联标志：`(?m)` 多行、`(?i)` 忽略大小写、`(?s)` 点匹配换行、
  /// `(?u)` 忽略（Dart 默认 Unicode）。Dart 的 RegExp 不认这些内联组，会直接抛异常，
  /// 因此这里先把它们摘出来映射为编译选项。
  static String applyRules(String text, List<List<String>> rules) {
    var result = text;
    for (final rule in rules) {
      if (rule.length < 2) continue;
      final pattern = rule[0];
      if (pattern.isEmpty) continue;
      result = result.replaceAll(compileRulePattern(pattern), rule[1]);
    }
    return result;
  }

  /// 把带内联标志的正则编译成 Dart RegExp。
  static RegExp compileRulePattern(String pattern) {
    var source = pattern;
    var multiLine = false;
    var caseSensitive = true;
    var dotAll = false;

    // 全局与行首两种写法都支持：(?m) 或 (?mi)
    final flagGroup = RegExp(r'\(\?([imsux]+)\)');
    while (true) {
      final match = flagGroup.firstMatch(source);
      if (match == null) break;
      final flags = match.group(1)!.toLowerCase();
      if (flags.contains('m')) multiLine = true;
      if (flags.contains('i')) caseSensitive = false;
      if (flags.contains('s')) dotAll = true;
      source = source.replaceRange(match.start, match.end, '');
    }
    try {
      return RegExp(
        source,
        multiLine: multiLine,
        caseSensitive: caseSensitive,
        dotAll: dotAll,
      );
    } catch (_) {
      // 兜底：整体转义，避免一条坏规则打断整本书
      return RegExp(RegExp.escape(source));
    }
  }

  /// 按标题正则分章；匹配不到就整本当一章。
  static List<({String title, String body})> splitChapters(
    String text,
    String pattern,
  ) {
    final lines = text.split('\n');
    final titleReg = pattern.trim().isEmpty
        ? null
        : RegExp(pattern, multiLine: true);

    final chapters = <({String title, String body})>[];
    final buffer = StringBuffer();
    String? currentTitle;

    void flush() {
      final body = buffer.toString().trim();
      if (currentTitle == null && body.isEmpty) return;
      chapters.add((title: currentTitle ?? '正文', body: body));
      buffer.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (titleReg != null &&
          trimmed.isNotEmpty &&
          titleReg.hasMatch(trimmed) &&
          trimmed.length <= 60) {
        flush();
        currentTitle = trimmed;
        continue;
      }
      buffer.writeln(line);
    }
    flush();

    if (chapters.isEmpty) {
      return [(title: '正文', body: text.trim())];
    }
    return chapters;
  }

  /// 组装 EPUB 3（交给 EpubWriter，严格按规范）。
  static Uint8List buildEpub({
    required String title,
    String author = '佚名',
    String language = 'zh-CN',
    required List<({String title, String body})> chapters,
    Uint8List? cover,
    String coverName = 'cover.jpg',
  }) {
    final writer = EpubWriter(
      title: title,
      author: author,
      language: language,
    );
    for (final chapter in chapters) {
      writer.addChapter(chapter.title, chapter.body);
    }
    if (cover != null) writer.setCover(cover, fileName: coverName);
    return writer.build();
  }

  /// 一步到位：读文件 → 探测编码 → 清洗 → 分章 → 产出 EPUB 字节。
  static Future<Uint8List> fromFile(
    File file, {
    String? title,
    String author = '佚名',
    String encoding = 'auto',
    String chapterPattern = defaultChapterPattern,
    List<List<String>> rules = const [],
  }) async {
    final bytes = await file.readAsBytes();
    var text = decode(bytes, encoding: encoding);
    if (rules.isNotEmpty) text = applyRules(text, rules);
    final chapters = splitChapters(text, chapterPattern);
    final name = file.uri.pathSegments.last.replaceAll(
      RegExp(r'\.txt$', caseSensitive: false),
      '',
    );
    return buildEpub(
      title: (title ?? name).trim().isEmpty ? '未命名' : (title ?? name).trim(),
      author: author,
      chapters: chapters,
    );
  }

}
