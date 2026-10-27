import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../reader/ezbk/ezbk_document.dart';
import 'app_log.dart';

/// 书籍存储：**EZBK 是正本**，纯文本 + 章节偏移是派生缓存。
///
/// 目录布局（应用私有目录下）：
///   books/<id>/book.ezbk     正本（EZBK v1.1）
///   books/<id>/content.txt   派生纯文本（阅读器/TTS/进度沿用）
///   books/<id>/chapters.json 派生章节偏移（基于纯文本）
///
/// 这样阅读、朗读、进度、分页等既有路径完全不需要改动；
/// 导出 TXT/EPUB 时以 book.ezbk 为准重新推导。
class EzbkBookStore {
  EzbkBookStore({Future<Directory> Function()? root})
    : _rootProvider = root ?? _defaultRoot;

  final Future<Directory> Function() _rootProvider;

  static Future<Directory> _defaultRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/reader');
  }

  Future<Directory> _root() async {
    final dir = await _rootProvider();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<Directory> _bookDir(String bookId) async {
    final dir = Directory('${(await _root()).path}/books/$bookId');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<EzbkDocument?> read(String bookId) async {
    final file = File('${(await _bookDir(bookId)).path}/book.ezbk');
    if (!file.existsSync()) return null;
    final raw = file.readAsStringSync();
    final doc = EzbkCodec.parse(raw);
    for (final w in doc.warnings) {
      AppLog.write('ezbk', '[$bookId] $w');
    }
    return doc;
  }

  /// 写入正本并刷新派生缓存；返回派生出的章节。
  Future<List<Chapter>> save(String bookId, EzbkDocument doc) async {
    final dir = await _bookDir(bookId);
    final canonical = EzbkCodec.serialize(doc);
    _writeAtomic(File('${dir.path}/book.ezbk'), utf8.encode(canonical));
    final derived = derivePlainText(doc);
    _writeAtomic(File('${dir.path}/content.txt'), utf8.encode(derived.text));
    _writeAtomic(
      File('${dir.path}/chapters.json'),
      utf8.encode(jsonEncode({
        'bookId': bookId,
        'chapters': [for (final c in derived.chapters) c.toJson()],
      })),
    );
    return derived.chapters;
  }

  /// 从 EZBK 文档推导纯文本与章节偏移（标题行不进入纯文本）。
  static ({String text, List<Chapter> chapters}) derivePlainText(EzbkDocument doc) {
    final buffer = StringBuffer();
    final chapters = <Chapter>[];
    EzbkBlock? pendingHead;
    var pendingStart = 0;

    void flush(int end) {
      final head = pendingHead;
      if (head == null) return;
      chapters.add(Chapter(
        index: chapters.length,
        title: head.text,
        start: pendingStart,
        end: end < pendingStart ? pendingStart : end,
      ));
      pendingHead = null;
    }

    for (final block in doc.blocks) {
      if (block.isHeading) {
        flush(buffer.length);
        pendingHead = block;
        pendingStart = buffer.length;
        continue;
      }
      buffer.writeln(block.text);
    }
    flush(buffer.length);

    if (chapters.isEmpty) {
      // 无标题文档：整篇作为一章
      final text = buffer.toString();
      if (text.trim().isNotEmpty) {
        chapters.add(Chapter(index: 0, title: '正文', start: 0, end: text.length));
      }
    }
    return (text: buffer.toString(), chapters: chapters);
  }

  static void _writeAtomic(File target, List<int> bytes) {
    final tmp = File('${target.path}.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(target.path);
  }
}