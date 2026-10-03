import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../services/library_repository.dart';
import '../services/app_log.dart';
import '../services/storage.dart';

/// 全局状态：书架与设置。
class AppState extends ChangeNotifier {
  AppState();

  late Storage storage;
  late LibraryRepository library;

  AppSettings settings = AppSettings();
  ReaderSettings readerSettings = ReaderSettings();

  bool ready = false;
  bool busy = false;
  String? message;

  List<Book> get books => library.sorted(settings.sortMode);

  Future<void> init() async {
    storage = await Storage.instance();
    library = LibraryRepository(storage);

    await library.load();
    final settingsJson = await storage.readJson('settings.json');
    if (settingsJson != null) settings = AppSettings.fromJson(settingsJson);
    final readerJson = await storage.readJson('reader_settings.json');
    if (readerJson != null) {
      readerSettings = ReaderSettings.fromJson(readerJson);
    } else {
      readerSettings.applyStyle(
        kReadingStyles[readerSettings.styleIndex],
        night: readerSettings.nightMode,
      );
    }
    ready = true;
    AppLog.info('app', '初始化完成：书籍 ${books.length} 本');
    notifyListeners();
  }


  void _notify(String? text) {
    message = text;
    notifyListeners();
  }

  Future<void> saveSettings() async {
    await storage.writeJson('settings.json', settings.toJson());
    notifyListeners();
  }

  Future<void> saveReaderSettings() async {
    await storage.writeJson('reader_settings.json', readerSettings.toJson());
    notifyListeners();
  }

  Future<void> setAppTheme(int index) async {
    settings.themeIndex = index;
    await saveSettings();
  }

  /// 导入本地书籍：按扩展名自动分派 TXT / EPUB。
  Future<Book?> importBook(File file) async {
    try {
      busy = true;
      notifyListeners();
      AppLog.info('import', '导入开始：${file.path}');
      final book = await library.importBook(file);
      AppLog.info('import', '导入完成：${book.title}');
      _notify('已导入《${book.title}》，共 ${book.chapterCount} 章');
      return book;
    } catch (e) {
      _notify('导入失败：$e');
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> removeBook(Book book) async {
    await library.deleteBook(book.id);
    _notify('已删除《${book.title}》');
  }

  Future<void> saveProgress(
    Book book,
    int chapter,
    int line,
    int offset,
    double progress,
  ) async {
    await library.touch(
      book,
      chapter: chapter,
      line: line,
      offset: offset,
      progress: progress,
    );
    notifyListeners();
  }
}
