import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../services/backup_service.dart';
import '../services/library_repository.dart';
import '../services/plugin/plugin_repository.dart';
import '../services/plugin/plugin_runner.dart';
import '../services/storage.dart';
import '../services/sync_service.dart';
import '../services/text_cleaner.dart';

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

  /// TXT 导入时的格式清理规则（内置规则 + 用户自定义）。
  List<CleanRule> cleanRules = TextCleaner.defaultRules();

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
    final rulesJson = await storage.readJson('cleaning_rules.json');
    if (rulesJson != null) {
      cleanRules = _mergeCleanRules(rulesJson);
    } else {
      await saveCleanRules();
    }

    ready = true;
    notifyListeners();
  }

  /// 用内置规则为准合并已存配置：保留内置规则及其启停状态，并追加用户自定义规则。
  List<CleanRule> _mergeCleanRules(Map<String, dynamic> json) {
    final stored = ((json['rules'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CleanRule.fromJson)
        .toList();
    final byName = {for (final rule in stored) rule.name: rule};
    final merged = <CleanRule>[];
    for (final rule in TextCleaner.defaultRules()) {
      final saved = byName.remove(rule.name);
      if (saved != null) rule.enabled = saved.enabled;
      merged.add(rule);
    }
    merged.addAll(byName.values.where((r) => !r.builtin));
    return merged;
  }

  Future<void> saveCleanRules() async {
    await storage.writeJson('cleaning_rules.json', {
      'format': 'wzmwayne.reader.cleaning_rules',
      'version': 1,
      'rules': cleanRules.map((r) => r.toJson()).toList(),
    });
    notifyListeners();
  }

  Future<void> resetCleanRules() async {
    cleanRules = TextCleaner.defaultRules();
    await saveCleanRules();
    _notify('清理规则已恢复默认');
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
      final book = await library.importBook(file, cleanRules: cleanRules);
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
