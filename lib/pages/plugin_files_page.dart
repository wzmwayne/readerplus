import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 导出目录：放在用户可见的位置，便于用文件管理器取走。
///
/// - Android：应用外部文件目录（`Android/data/<包名>/files/readerplus`），
///   文件管理器可访问，且不需要额外权限。
/// - 桌面：优先 `~/下载` / `~/Downloads`，否则退回临时目录。
Future<Directory> userVisibleDirectory() async {
  try {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      final dir = Directory('${external.path}/readerplus');
      await dir.create(recursive: true);
      return dir;
    }
  } catch (_) {}

  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
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

/// 查看一次运行的目录：列出文件、看内容、导出到用户可见目录。
class PluginFilesPage extends StatefulWidget {
  const PluginFilesPage({
    super.key,
    required this.sandboxPath,
    this.title = '运行目录',
  });

  final String sandboxPath;
  final String title;

  @override
  State<PluginFilesPage> createState() => _PluginFilesPageState();
}

class _PluginFilesPageState extends State<PluginFilesPage> {
  List<FileSystemEntity> _entries = [];
  final Set<String> _exported = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final root = Directory(widget.sandboxPath);
    final entries = root.existsSync()
        ? root.listSync(recursive: true).whereType<File>().toList()
        : <FileSystemEntity>[];
    entries.sort((a, b) => a.path.compareTo(b.path));
    setState(() => _entries = entries);
  }

  String _relative(String path) =>
      path.replaceFirst(widget.sandboxPath, '').replaceFirst(RegExp(r'^/'), '');

  String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';

  Future<void> _export(FileSystemEntity entry) async {
    final file = File(entry.path);
    final target = await userVisibleDirectory();
    final name = '${DateTime.now().millisecondsSinceEpoch % 100000}-'
        '${entry.uri.pathSegments.last}';
    final saved = await file.copy('${target.path}/$name');
    if (!mounted) return;
    setState(() => _exported.add(entry.path));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已导出到：${saved.path}'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _preview(FileSystemEntity entry) async {
    final file = File(entry.path);
    final size = file.lengthSync();
    String body;
    if (size > 256 * 1024) {
      body = '文件较大（${_size(size)}），仅支持导出。';
    } else {
      final bytes = await file.readAsBytes();
      try {
        body = utf8.decode(bytes);
      } catch (_) {
        body = '二进制文件（${_size(size)}），无法以文本预览；点右侧按钮导出。';
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.uri.pathSegments.last),
        content: SizedBox(
          width: 560,
          height: 420,
          child: SingleChildScrollView(child: SelectableText(body)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _export(entry);
            },
            child: const Text('导出'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.folder_outlined, size: 18),
            title: Text(
              _relative(widget.sandboxPath).isEmpty
                  ? widget.sandboxPath
                  : widget.sandboxPath,
              style: const TextStyle(fontSize: 11),
            ),
            subtitle: const Text(
              '运行结束后会清理此目录，需要的文件请先导出（复制到用户可见的下载目录）',
              style: TextStyle(fontSize: 11),
            ),
          ),
          const Divider(height: 1),
          if (_entries.isEmpty)
            const Expanded(child: Center(child: Text('目录为空')))
          else
            Expanded(
              child: ListView.separated(
                itemCount: _entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final size = File(entry.path).lengthSync();
                  return ListTile(
                    leading: Icon(
                      entry.path.endsWith('.epub')
                          ? Icons.menu_book_outlined
                          : entry.path.endsWith('.json')
                          ? Icons.data_object
                          : entry.path.endsWith('.txt')
                          ? Icons.description_outlined
                          : Icons.insert_drive_file_outlined,
                    ),
                    title: Text(
                      _relative(entry.path),
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(_size(size)),
                    trailing: IconButton(
                      tooltip: '导出到下载目录',
                      icon: Icon(
                        _exported.contains(entry.path)
                            ? Icons.check_circle_outline
                            : Icons.save_alt,
                      ),
                      onPressed: () => _export(entry),
                    ),
                    onTap: () => _preview(entry),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
