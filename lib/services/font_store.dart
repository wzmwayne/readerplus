import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';

/// 用户导入的阅读字体（扩展包）。
///
/// 设计：APK **不内置**字体，默认使用系统字体；用户自行导入 TTF/OTF 后，
/// 由 [FontLoader] 在运行时注册，阅读器再按族名选用。
/// 这样既避免了 40MB+ 的安装包体积，也回避了随包分发第三方字体的许可负担。
class ImportedFont {
  const ImportedFont({required this.family, required this.path, required this.label});

  /// 注册到引擎的族名（由文件名清洗得到，稳定且唯一）。
  final String family;
  final String path;
  final String label;

  Map<String, Object?> toJson() => {
    'family': family,
    'path': path,
    'label': label,
  };

  static ImportedFont? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final family = raw['family'] as String?;
    final path = raw['path'] as String?;
    if (family == null || path == null || family.isEmpty) return null;
    return ImportedFont(
      family: family,
      path: path,
      label: (raw['label'] as String?) ?? family,
    );
  }
}

class FontStore {
  FontStore({Future<Directory> Function()? root})
    : _rootProvider = root ?? _defaultRoot;

  final Future<Directory> Function() _rootProvider;

  static Future<Directory> _defaultRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/fonts');
  }

  Future<Directory> _root() async {
    final dir = await _rootProvider();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _manifest() async => File('${(await _root()).path}/fonts.json');

  Future<List<ImportedFont>> load() async {
    final list = <ImportedFont>[];
    final file = await _manifest();
    if (file.existsSync()) {
      try {
        final raw = file.readAsStringSync();
        final decoded = raw.isEmpty ? null : jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final f = ImportedFont.fromJson(item);
            if (f != null && File(f.path).existsSync()) list.add(f);
          }
        }
      } catch (e) {
        AppLog.write('font', '读取字体清单失败：$e');
      }
    }
    return list;
  }

  Future<void> _save(List<ImportedFont> fonts) async {
    final file = await _manifest();
    file.writeAsStringSync(jsonEncode([
      for (final f in fonts) f.toJson(),
    ]));
  }

  /// 导入一个字体文件；返回导入结果。
  Future<ImportedFont> import(File source) async {
    final name = source.uri.pathSegments.last;
    final ext = name.toLowerCase();
    if (!(ext.endsWith('.ttf') || ext.endsWith('.otf'))) {
      throw const FontImportException('只支持 .ttf / .otf 字体文件');
    }
    final stem = name.substring(0, name.lastIndexOf('.'));
    final family = _sanitize(stem);
    if (family.isEmpty) throw const FontImportException('文件名无法作为字体族名');
    final dir = await _root();
    final target = File('${dir.path}/$family${ext.substring(stem.length)}');
    final copy = File('${dir.path}/$family${name.substring(name.lastIndexOf('.'))}');
    await source.copy(copy.path);
    if (target.path != copy.path && target.existsSync()) target.deleteSync();
    final fonts = await load();
    fonts.removeWhere((f) => f.family == family);
    final imported = ImportedFont(family: family, path: copy.path, label: stem);
    fonts.add(imported);
    await _save(fonts);
    await register(imported);
    return imported;
  }

  Future<void> remove(ImportedFont font) async {
    final fonts = await load();
    fonts.removeWhere((f) => f.family == font.family);
    await _save(fonts);
    final file = File(font.path);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }

  /// 把字体注册进引擎（同一族重复注册会被忽略）。
  Future<void> register(ImportedFont font) async {
    try {
      final bytes = await File(font.path).readAsBytes();
      final loader = FontLoader(font.family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      AppLog.info('font', '已注册字体 ${font.family}');
    } catch (e) {
      AppLog.write('font', '注册字体失败 ${font.family}：$e');
    }
  }

  /// 启动时注册所有已导入字体。
  Future<void> registerAll() async {
    for (final f in await load()) {
      await register(f);
    }
  }

  static String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    return cleaned.isEmpty ? '' : 'imported_$cleaned';
  }
}

class FontImportException implements Exception {
  const FontImportException(this.message);
  final String message;
  @override
  String toString() => message;
}