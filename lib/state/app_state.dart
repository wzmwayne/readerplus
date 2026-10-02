import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../services/backup_service.dart';
import '../services/library_repository.dart';
import '../services/plugin/plugin_repository.dart';
import '../services/plugin/plugin_runner.dart';
import '../services/storage.dart';
import '../services/sync_service.dart';

/// 全局状态：书架、设置、同步。
class AppState extends ChangeNotifier {
  AppState();

  late Storage storage;
  late PluginRepository plugins;
  late PluginRunner pluginRunner;
  late LibraryRepository library;
  late BackupService backup;
  late SyncService sync;

  AppSettings settings = AppSettings();
  ReaderSettings readerSettings = ReaderSettings();
  WebDavConfig webdav = WebDavConfig();

  bool ready = false;
  bool busy = false;
  String? message;

  List<Book> get books => library.sorted(settings.sortMode);

  Future<void> init() async {
    storage = await Storage.instance();
    plugins = PluginRepository(storage);
    pluginRunner = PluginRunner();
    library = LibraryRepository(storage);
    backup = BackupService(storage);
    sync = SyncService(storage);

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
    final webdavJson = await storage.readJson('webdav.json');
    if (webdavJson != null) webdav = WebDavConfig.fromJson(webdavJson);
    await _ensureBuiltinPlugin();

    ready = true;
    notifyListeners();
  }

  /// 首次运行导入内置脚本（TXT 清洗转 EPUB）并启用；已有则跳过。
  Future<void> _ensureBuiltinPlugin() async {
    try {
      final scripts = await plugins.load();
      if (scripts.any((script) => script.builtin)) return;
      final source = await rootBundle.loadString(
        'python/examples/txt_cleaner.py',
      );
      await plugins.importSource(
        source,
        name: '内置：TXT 清洗转 EPUB',
        builtin: true,
        params: const {
          'input_file': 'raw.txt',
          'output_file': 'book.epub',
          'chapter_pattern': r'^第[一二三四五六七八九十百千0-9]+章.*$',
          // 内置清理已交由脚本负责：去掉零宽字符与常见广告行
          'clean_rules': [
            [r'[\u200b\ufeff]', ''],
            [r'(?m)^\s*(广告|推广)[:：].*$', ''],
          ],
        },
      );
    } catch (error) {
      debugPrint('[plugin] 导入内置脚本失败：$error');
    }
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

  Future<void> saveWebdav() async {
    await storage.writeJson('webdav.json', webdav.toJson());
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
      final book = await library.importBook(file);
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

  Future<String> exportBackupTo(File target) async {
    final bytes = await backup.export();
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<int> importBackupFrom(File source) async {
    final bytes = await source.readAsBytes();
    final count = await backup.import(bytes);
    await library.load();
    final settingsJson = await storage.readJson('settings.json');
    if (settingsJson != null) settings = AppSettings.fromJson(settingsJson);
    final readerJson = await storage.readJson('reader_settings.json');
    if (readerJson != null) readerSettings = ReaderSettings.fromJson(readerJson);
    notifyListeners();
    return count;
  }

  Future<bool> testWebdav() async {
    busy = true;
    notifyListeners();
    try {
      final ok = await sync.test(webdav);
      _notify(ok ? '连接成功' : '连接失败：请检查地址与账号');
      return ok;
    } catch (e) {
      _notify('连接失败：$e');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> syncUpload() async {
    await saveSettings();
    await saveReaderSettings();
    busy = true;
    notifyListeners();
    try {
      await sync.upload(webdav);
      _notify('已上传到 WebDAV');
    } catch (e) {
      _notify('上传失败：$e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> syncDownload() async {
    busy = true;
    notifyListeners();
    try {
      final count = await sync.download(webdav);
      await library.load();
      final settingsJson = await storage.readJson('settings.json');
      if (settingsJson != null) settings = AppSettings.fromJson(settingsJson);
      final readerJson = await storage.readJson('reader_settings.json');
      if (readerJson != null) readerSettings = ReaderSettings.fromJson(readerJson);
      _notify('已从 WebDAV 恢复 $count 个文件');
    } catch (e) {
      _notify('下载失败：$e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
