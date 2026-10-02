import 'dart:io';

import '../models/book.dart';
import 'epub_importer.dart';
import 'storage.dart';
import 'txt_importer.dart';

/// 书架数据访问：书籍索引、目录、正文的读写与导入。
class LibraryRepository {
  LibraryRepository(this.storage);

  final Storage storage;

  static const _libraryFile = 'library.json';
  static const _formatId = 'wzmwayne.reader.library';
  static const _formatVersion = 1;

  List<Book> books = [];

  Future<void> load() async {
    final data = await storage.readJson(_libraryFile);
    if (data == null) {
      books = [];
      return;
    }
    final list = (data['books'] as List?) ?? const [];
    books = list
        .whereType<Map<String, dynamic>>()
        .map(Book.fromJson)
        .toList(growable: true);
  }

  Future<void> save() async {
    await storage.writeJson(_libraryFile, {
      'format': _formatId,
      'version': _formatVersion,
      'updatedAt': DateTime.now().toIso8601String(),
      'books': books.map((b) => b.toJson()).toList(),
    });
  }

  Book? byId(String id) {
    for (final b in books) {
      if (b.id == id) return b;
    }
    return null;
  }

  String _chaptersPath(String bookId) => 'books/$bookId/chapters.json';
  String _contentPath(String bookId) => 'books/$bookId/content.txt';

  Future<List<Chapter>> chaptersOf(String bookId) async {
    final data = await storage.readJson(_chaptersPath(bookId));
    if (data == null) return const [];
    final list = (data['chapters'] as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Chapter.fromJson)
        .toList(growable: false);
  }

  Future<void> saveChapters(String bookId, List<Chapter> chapters) =>
      storage.writeJson(_chaptersPath(bookId), {
        'bookId': bookId,
        'chapters': chapters.map((c) => c.toJson()).toList(),
      });

  Future<String> contentOf(String bookId) async =>
      await storage.readText(_contentPath(bookId)) ?? '';

  Future<void> saveContent(String bookId, String content) =>
      storage.writeText(_contentPath(bookId), content);

  /// 按扩展名分派导入：`.epub` 走 EPUB 解析，其余按 TXT 处理。
  Future<Book> importBook(File file) async {
    final path = file.path.toLowerCase();
    if (path.endsWith('.epub')) return importEpub(file);
    return importTxt(file);
  }

  /// 导入本地 TXT（含格式清理）。
  Future<Book> importTxt(File file) async {
    final parsed = await TxtImporter.parseFile(file);
    final meta = TxtImporter.guessMeta(file, parsed.content);
    final book = Book(
      id: Book.newId(),
      title: meta.title.isEmpty ? _titleFromPath(file) : meta.title,
      author: meta.author,
      originalPath: file.path,
      charCount: parsed.content.length,
      chapterCount: parsed.chapters.length,
    );
    await _persist(book, parsed.content, parsed.chapters);
    return book;
  }

  /// 导入本地 EPUB 2 / 3。
  Future<Book> importEpub(File file) async {
    final parsed = EpubImporter.parse(await file.readAsBytes());
    final book = Book(
      id: Book.newId(),
      title: parsed.title.isEmpty ? _titleFromPath(file) : parsed.title,
      author: parsed.author,
      originalPath: file.path,
      charCount: parsed.content.length,
      chapterCount: parsed.chapters.length,
    );
    final cover = parsed.coverBytes;
    if (cover != null && cover.isNotEmpty) {
      final relative = 'books/${book.id}/cover.${parsed.coverExtension ?? 'jpg'}';
      await storage.writeBytes(relative, cover);
      book.coverPath = storage.file(relative).path;
    }
    await _persist(book, parsed.content, parsed.chapters);
    return book;
  }

  Future<void> _persist(Book book, String content, List<Chapter> chapters) async {
    await saveContent(book.id, content);
    await saveChapters(book.id, chapters);
    books.add(book);
    await save();
  }

  /// 文件名去掉扩展名后作为兜底书名。
  String _titleFromPath(File file) {
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final title = (dot > 0 ? name.substring(0, dot) : name).trim();
    return title.isEmpty ? '未命名' : title;
  }

  Future<void> deleteBook(String id) async {
    books.removeWhere((b) => b.id == id);
    await storage.delete('books/$id');
    await save();
  }

  Future<void> touch(
    Book book, {
    int? chapter,
    int? line,
    int? offset,
    double? progress,
  }) async {
    if (chapter != null) book.lastChapter = chapter;
    if (line != null) book.lastLine = line;
    if (offset != null) book.lastOffset = offset;
    if (progress != null) book.progress = progress;
    book.lastReadAt = DateTime.now();
    await save();
  }

  List<Book> sorted(String sortMode) {
    final list = [...books];
    switch (sortMode) {
      case 'title':
        list.sort((a, b) => a.title.compareTo(b.title));
      case 'author':
        list.sort((a, b) => a.author.compareTo(b.author));
      case 'added':
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      default:
        list.sort((a, b) {
          final at = a.lastReadAt ?? a.addedAt;
          final bt = b.lastReadAt ?? b.addedAt;
          return bt.compareTo(at);
        });
    }
    return list;
  }
}
