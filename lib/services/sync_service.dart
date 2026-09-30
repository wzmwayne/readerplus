import '../models/app_settings.dart';
import 'backup_service.dart';
import 'storage.dart';
import 'webdav_client.dart';

/// WebDAV 同步：以单个备份包为同步单位，避免逐文件往返。
/// 远程布局：`<remoteDir>/reader-backup.zip`
class SyncService {
  SyncService(this.storage);

  final Storage storage;

  static const _remoteFile = 'reader-backup.zip';

  WebDavClient clientOf(WebDavConfig config) => WebDavClient(
    baseUrl: config.url,
    username: config.username,
    password: config.password,
  );

  WebDavClient _prepare(WebDavConfig config) {
    final client = clientOf(config);
    return client;
  }

  String _remotePath(WebDavConfig config) =>
      '/${config.remoteDir}/$_remoteFile';

  Future<bool> test(WebDavConfig config) async {
    final client = _prepare(config);
    try {
      return await client.test();
    } finally {
      client.close();
    }
  }

  /// 上传本地数据到远程（覆盖远程备份）。
  Future<void> upload(WebDavConfig config) async {
    final client = _prepare(config);
    try {
      await client.ensureDir('/${config.remoteDir}');
      final zip = await BackupService(storage).export();
      await client.put(_remotePath(config), zip);
    } finally {
      client.close();
    }
  }

  /// 从远程下载并恢复（调用方需自行先做本地备份）。
  Future<int> download(WebDavConfig config) async {
    final client = _prepare(config);
    try {
      final bytes = await client.get(_remotePath(config));
      if (bytes == null) {
        throw WebDavException('远程没有备份文件：${_remotePath(config)}');
      }
      return await BackupService(storage).import(bytes);
    } finally {
      client.close();
    }
  }

  /// 读取远程备份的时间戳，用于比较新旧。
  Future<DateTime?> remoteUpdatedAt(WebDavConfig config) async {
    final client = _prepare(config);
    try {
      final entries = await client.list('/${config.remoteDir}');
      for (final e in entries) {
        if (e.path.endsWith(_remoteFile)) return e.lastModified;
      }
      return null;
    } finally {
      client.close();
    }
  }
}
