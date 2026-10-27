import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../app_log.dart';

/// 脚本三级存储：mem（内存）/ tmp（临时，运行结束清除）/ perm（永久）。
///
/// 规范：docs/script-storage-api.md。三级同构，方法名一致：
///   read.raw(k) / read.utf8(k) / write.raw(k,b) / write.utf8(k,s)
///   remove(k) / keys() / clear()
///
/// 键恒为 UTF-8 文本；值恒按字节存。落盘为 `index.json` + 以 sha1(key) 命名的值文件，
/// 均采用 `写 .tmp → rename` 原子替换。
class ScriptStorageQuota {
  const ScriptStorageQuota({
    this.memoryBytes = 50 * 1024 * 1024,
    this.tempBytes = 100 * 1024 * 1024,
    this.permBytes = 50 * 1024 * 1024,
  });

  final int memoryBytes;
  final int tempBytes;
  final int permBytes;
}

const int kScriptKeyMaxLength = 256;

class ScriptStoreException implements Exception {
  const ScriptStoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 内存层：进程内 Map，脚本结束即丢弃。
class MemoryTier {
  MemoryTier({this.quotaBytes = 50 * 1024 * 1024});

  final int quotaBytes;
  final Map<String, Uint8List> _data = {};
  int _used = 0;

  int get usedBytes => _used;

  Uint8List? readRaw(String key) {
    final value = _data[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  String? readUtf8(String key) {
    final bytes = _data[key];
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  int writeRaw(String key, List<int> bytes) {
    _validateKey(key);
    final next = bytes.length;
    final previous = _data[key]?.length ?? 0;
    if (_used - previous + next > quotaBytes) {
      throw const ScriptStoreException('mem.write: 内存存储超出配额（50 MB）');
    }
    _data[key] = Uint8List.fromList(bytes);
    _used = _used - previous + next;
    return next;
  }

  int writeUtf8(String key, String text) => writeRaw(key, utf8.encode(text));

  bool remove(String key) {
    final old = _data.remove(key);
    if (old == null) return false;
    _used -= old.length;
    return true;
  }

  List<String> keys() => _data.keys.toList()..sort();

  bool clear() {
    _data.clear();
    _used = 0;
    return true;
  }
}

/// 磁盘层：tmp / perm 共用实现，区别只在生命周期与配额。
class DiskTier {
  DiskTier(
    this.root, {
    required this.label,
    this.quotaBytes = 100 * 1024 * 1024,
    this.reservedKeys = const <String>{},
  });

  final Directory root;
  final String label;
  final int quotaBytes;

  /// 脚本不可写的保留键（如 task、input/*）。
  final Set<String> reservedKeys;

  File get _indexFile => File('${root.path}/index.json');

  Map<String, Map<String, Object?>> _readIndex() {
    if (!root.existsSync()) root.createSync(recursive: true);
    if (!_indexFile.existsSync()) return {};
    try {
      final raw = jsonDecode(_indexFile.readAsStringSync());
      if (raw is! Map) return {};
      final out = <String, Map<String, Object?>>{};
      raw.forEach((k, v) {
        if (v is Map) out['$k'] = v.cast<String, Object?>();
      });
      return out;
    } catch (e) {
      AppLog.write('store', '$label 索引损坏，已重置：$e');
      return {};
    }
  }

  void _writeIndex(Map<String, Map<String, Object?>> index) {
    if (!root.existsSync()) root.createSync(recursive: true);
    _writeAtomic(_indexFile, utf8.encode(jsonEncode(index)));
  }

  String _fileNameFor(String key) {
    final digest = sha1.convert(utf8.encode(key)).toString();
    return digest.substring(0, 16);
  }

  int get usedBytes {
    var total = 0;
    for (final entry in _readIndex().values) {
      total += (entry['size'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  Uint8List? readRaw(String key) {
    _validateKey(key);
    final entry = _readIndex()[key];
    if (entry == null) return null;
    final file = File('${root.path}/${entry['file']}');
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
  }

  bool has(String key) {
    _validateKey(key);
    return _readIndex().containsKey(key);
  }

  String? readUtf8(String key) {
    final bytes = readRaw(key);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  int writeRaw(String key, List<int> bytes) {
    _validateKey(key);
    _rejectReserved(key);
    final index = _readIndex();
    final previous = (index[key]?['size'] as num?)?.toInt() ?? 0;
    var used = 0;
    for (final entry in index.values) {
      used += (entry['size'] as num?)?.toInt() ?? 0;
    }
    if (used - previous + bytes.length > quotaBytes) {
      final mb = (quotaBytes ~/ (1024 * 1024));
      throw ScriptStoreException('$label.write: 超出配额（$mb MB）');
    }
    final name = _fileNameFor(key);
    _writeAtomic(File('${root.path}/$name'), bytes);
    index[key] = {
      'file': name,
      'size': bytes.length,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    _writeIndex(index);
    return bytes.length;
  }

  int writeUtf8(String key, String text) => writeRaw(key, utf8.encode(text));

  bool remove(String key) {
    _validateKey(key);
    _rejectReserved(key);
    final index = _readIndex();
    final entry = index.remove(key);
    if (entry == null) return false;
    final file = File('${root.path}/${entry['file']}');
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (e) {
        AppLog.write('store', '$label 删除值文件失败：$e');
      }
    }
    _writeIndex(index);
    return true;
  }

  List<String> keys() => _readIndex().keys.toList()..sort();

  bool clear() {
    final index = _readIndex();
    for (final entry in index.values) {
      final file = File('${root.path}/${entry['file']}');
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
    _writeIndex({});
    return true;
  }

  void _rejectReserved(String key) {
    for (final reserved in reservedKeys) {
      if (key == reserved || key.startsWith('$reserved/')) {
        throw ScriptStoreException('$label.write: 保留键不可写（$key）');
      }
    }
  }

  static void _writeAtomic(File target, List<int> bytes) {
    final tmp = File('${target.path}.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(target.path);
  }
}

/// 一个脚本的三级存储集合。
class ScriptStorage {
  ScriptStorage({
    required this.memory,
    required this.temp,
    required this.perm,
  });

  final MemoryTier memory;
  final DiskTier temp;
  final DiskTier perm;

  /// 按脚本创建三级存储（磁盘目录：scripts/<脚本 id>/{tmp,perm}）。
  static Future<ScriptStorage> open(
    String scriptId, {
    ScriptStorageQuota quota = const ScriptStorageQuota(),
    Future<Directory> Function()? rootProvider,
  }) async {
    final base = rootProvider == null
        ? Directory('${(await getApplicationSupportDirectory()).path}/reader/scripts')
        : Directory('${(await rootProvider()).path}/scripts');
    final dir = Directory('${base.path}/${_safeId(scriptId)}');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return ScriptStorage(
      memory: MemoryTier(quotaBytes: quota.memoryBytes),
      temp: DiskTier(
        Directory('${dir.path}/tmp'),
        label: 'tmp',
        quotaBytes: quota.tempBytes,
        reservedKeys: const {'task', 'input'},
      ),
      perm: DiskTier(
        Directory('${dir.path}/perm'),
        label: 'perm',
        quotaBytes: quota.permBytes,
      ),
    );
  }

  /// 应用启动时清扫所有脚本的 tmp 目录（临时层只对单次运行有效）。
  static Future<void> sweepTemp({Future<Directory> Function()? rootProvider}) async {
    final base = rootProvider == null
        ? Directory('${(await getApplicationSupportDirectory()).path}/reader/scripts')
        : Directory('${(await rootProvider()).path}/scripts');
    if (!base.existsSync()) return;
    for (final entity in base.listSync()) {
      if (entity is! Directory) continue;
      final tmp = Directory('${entity.path}/tmp');
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync(recursive: true);
          AppLog.write('store', '清扫临时存储：${entity.path}');
        } catch (e) {
          AppLog.write('store', '清扫临时存储失败：$e');
        }
      }
    }
  }

  static String _safeId(String id) {
    final cleaned = id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return cleaned.isEmpty ? 'unknown' : cleaned;
  }
}

void _validateKey(String key) {
  if (key.isEmpty) throw const ScriptStoreException('键不能为空');
  if (key.length > kScriptKeyMaxLength) {
    throw const ScriptStoreException('键过长（上限 $kScriptKeyMaxLength 字符）');
  }
}