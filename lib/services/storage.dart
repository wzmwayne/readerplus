import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 简单的 JSON 文件读写，作为本项目自定义数据格式的底层。
///
/// 目录结构（应用私有目录下）：
///   library.json            书架索引
///   settings.json           应用设置
///   reader_settings.json    阅读设置
///   webdav.json             WebDAV 配置
///   `books/<id>/chapters.json`  章节目录
///   `books/<id>/content.txt`    正文
class Storage {
  Storage._(this.root);

  final Directory root;

  static Storage? _instance;

  static Future<Storage> instance() async {
    if (_instance != null) return _instance!;
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}/reader');
    await root.create(recursive: true);
    _instance = Storage._(root);
    return _instance!;
  }

  /// 仅供测试注入自定义目录。
  static void overrideRoot(Directory dir) => _instance = Storage._(dir);

  File file(String relative) => File('${root.path}/$relative');

  Directory dir(String relative) => Directory('${root.path}/$relative');

  Future<Map<String, dynamic>?> readJson(String relative) async {
    final f = file(relative);
    if (!await f.exists()) return null;
    try {
      final text = await f.readAsString();
      if (text.trim().isEmpty) return null;
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeJson(String relative, Map<String, dynamic> data) =>
      writeText(relative, const JsonEncoder.withIndent('  ').convert(data));

  Future<void> writeText(String relative, String content) async {
    final f = file(relative);
    await f.parent.create(recursive: true);
    await f.writeAsString(content, flush: true);
  }

  Future<String?> readText(String relative) async {
    final f = file(relative);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  Future<void> delete(String relative) async {
    final f = file(relative);
    if (await f.exists()) await f.delete(recursive: true);
    final d = dir(relative);
    if (await d.exists()) await d.delete(recursive: true);
  }
}
