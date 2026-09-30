import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'webdav_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _zipTypeGroup = XTypeGroup(
    label: '备份文件',
    extensions: ['zip'],
    mimeTypes: ['application/zip'],
  );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionTitle('主题配色'),
          for (var i = 0; i < kAppThemes.length; i++)
            ListTile(
              onTap: () => state.setAppTheme(i),
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: kAppThemes[i].primary,
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(kAppThemes[i].name),
              trailing: settings.themeIndex == i ? const Icon(Icons.check) : null,
            ),
          const Divider(),
          const _SectionTitle('书架'),
          SwitchListTile(
            value: settings.gridLayout,
            onChanged: (v) {
              settings.gridLayout = v;
              state.saveSettings();
            },
            title: const Text('网格布局'),
          ),
          ListTile(
            title: const Text('每行数量'),
            subtitle: Slider(
              value: settings.gridColumns.toDouble(),
              min: 2,
              max: 6,
              divisions: 4,
              label: '${settings.gridColumns}',
              onChanged: settings.gridLayout
                  ? (v) {
                      settings.gridColumns = v.round();
                      state.saveSettings();
                    }
                  : null,
            ),
            trailing: Text('${settings.gridColumns}'),
          ),
          ListTile(
            title: const Text('排序方式'),
            trailing: DropdownButton<String>(
              value: settings.sortMode,
              onChanged: (v) {
                settings.sortMode = v ?? 'recent';
                state.saveSettings();
              },
              items: const [
                DropdownMenuItem(value: 'recent', child: Text('最近阅读')),
                DropdownMenuItem(value: 'title', child: Text('书名')),
                DropdownMenuItem(value: 'author', child: Text('作者')),
                DropdownMenuItem(value: 'added', child: Text('加入时间')),
              ],
            ),
          ),
          const Divider(),
          const _SectionTitle('数据与同步'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('导出备份'),
            subtitle: const Text('导出为单个 zip 备份包'),
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('导入备份'),
            subtitle: const Text('从备份包恢复书架与设置'),
            onTap: () => _import(context),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('WebDAV 同步'),
            subtitle: Text(
              state.webdav.configured ? state.webdav.url : '未配置',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WebDavPage()),
            ),
          ),
          const Divider(),
          const _SectionTitle('关于'),
          const ListTile(
            title: Text('版本'),
            trailing: Text('1.0.0'),
          ),
          const ListTile(
            title: Text('数据格式'),
            subtitle: Text('自定义 JSON + zip 备份，保存于应用私有目录'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await getSaveLocation(
        suggestedName: 'reader-backup.zip',
        acceptedTypeGroups: const [_zipTypeGroup],
      );
      if (location == null) return;
      final path = await state.exportBackupTo(File(location.path));
      messenger.showSnackBar(SnackBar(content: Text('已导出到 $path')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _import(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await openFile(acceptedTypeGroups: const [_zipTypeGroup]);
      if (file == null) return;
      final count = await state.importBackupFrom(File(file.path));
      messenger.showSnackBar(SnackBar(content: Text('已恢复 $count 个文件')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
