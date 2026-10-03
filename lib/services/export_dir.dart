import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 导出目录：放到用户可见的位置，便于用文件管理器取走。
///
/// - Android：应用外部文件目录（`Android/data/<包名>/files/readerplus`），文件管理器可访问，无需额外权限
/// - 桌面：优先 `~/下载` / `~/Downloads`，否则临时目录
Future<Directory> userVisibleDirectory() async {
  try {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      final dir = Directory('${external.path}/readerplus');
      await dir.create(recursive: true);
      return dir;
    }
  } catch (_) {}

  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.isNotEmpty) {
    for (final name in ['下载', 'Downloads']) {
      final candidate = Directory('$home/$name');
      if (candidate.existsSync()) {
        final dir = Directory('${candidate.path}/readerplus');
        await dir.create(recursive: true);
        return dir;
      }
    }
  }

  final temp = await getTemporaryDirectory();
  final dir = Directory('${temp.path}/readerplus');
  await dir.create(recursive: true);
  return dir;
}
