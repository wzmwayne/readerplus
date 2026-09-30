import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'storage.dart';

/// 自定义备份格式：单个 zip 内包含清单与全部数据文件。
///
///   manifest.json        备份清单
///   library.json         书架
///   settings.json        应用设置
///   reader_settings.json 阅读设置
///   webdav.json          同步配置（不含密码）
///   `books/<id>/...`       目录与正文
class BackupService {
  BackupService(this.storage);

  final Storage storage;

  static const formatId = 'wzmwayne.reader.backup';
  static const formatVersion = 1;

  static const _dataFiles = [
    'library.json',
    'settings.json',
    'reader_settings.json',
  ];

  /// 打包为 zip 字节流。
  Future<Uint8List> export({String? remotePassword}) async {
    final archive = Archive();
    final manifest = <String, dynamic>{
      'format': formatId,
      'version': formatVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'files': <String>[],
    };
    final files = <String>[];

    void addBytes(String name, List<int> bytes) {
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      files.add(name);
    }

    for (final rel in _dataFiles) {
      final f = storage.file(rel);
      if (await f.exists()) addBytes(rel, await f.readAsBytes());
    }

    final webdav = await storage.readJson('webdav.json');
    if (webdav != null) {
      final sanitized = Map<String, dynamic>.from(webdav);
      sanitized['password'] = '';
      addBytes('webdav.json', utf8.encode(jsonEncode(sanitized)));
    }

    final booksDir = storage.dir('books');
    if (await booksDir.exists()) {
      await for (final entity in booksDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final rel = entity.path.substring(storage.root.path.length + 1);
        addBytes(rel, await entity.readAsBytes());
      }
    }

    manifest['files'] = files;
    manifest['bookCount'] = files
        .where((f) => f.startsWith('books/') && f.endsWith('chapters.json'))
        .length;
    addBytes('manifest.json', utf8.encode(jsonEncode(manifest)));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// 从 zip 字节流恢复，返回写入的文件数。
  Future<int> import(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.files.where((f) => f.name == 'manifest.json');
    if (manifestFile.isEmpty) {
      throw const BackupException('备份文件缺少 manifest.json');
    }
    final manifest = jsonDecode(utf8.decode(manifestFile.first.content as List<int>));
    if (manifest is! Map || manifest['format'] != formatId) {
      throw const BackupException('不是本应用生成的备份文件');
    }

    var count = 0;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name == 'manifest.json') continue;
      final target = storage.file(file.name);
      await target.parent.create(recursive: true);
      await target.writeAsBytes(file.content as List<int>, flush: true);
      count++;
    }
    return count;
  }
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}
