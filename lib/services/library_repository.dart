import 'dart:io';

import '../models/book.dart';
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

  /// 导入本地 TXT。
  Future<Book> importTxt(File file) async {
    final parsed = await TxtImporter.parseFile(file);
    final meta = TxtImporter.guessMeta(file, parsed.content);
    final book = Book(
      id: Book.newId(),
      title: meta.title.isEmpty ? '未命名' : meta.title,
      author: meta.author,
      originalPath: file.path,
      charCount: parsed.content.length,
      chapterCount: parsed.chapters.length,
    );
    await saveContent(book.id, parsed.content);
    await saveChapters(book.id, parsed.chapters);
    books.add(book);
    await save();
    return book;
  }

  Future<void> deleteBook(String id) async {
    books.removeWhere((b) => b.id == id);
    await storage.delete('books/$id');
    await save();
  }

  Future<void> touch(Book book, {int? chapter, int? offset, double? progress}) async {
    if (chapter != null) book.lastChapter = chapter;
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
