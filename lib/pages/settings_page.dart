import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../state/app_state.dart';
import 'settings_read_aloud_section.dart';
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
          const _SectionTitle('界面'),
          SwitchListTile(
            value: settings.portraitLabels,
            onChanged: (v) {
              settings.portraitLabels = v;
              state.saveSettings();
            },
            title: const Text('底部标签显示文字'),
            subtitle: const Text('仅竖屏生效；横屏用左侧标签栏的展开按钮'),
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
          const _SectionTitle('TXT 格式清理'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '导入 TXT 时按下列规则依次清理正文（规则形式参考 Legado 的替换净化）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          for (final rule in state.cleanRules)
            SwitchListTile(
              dense: true,
              value: rule.enabled,
              onChanged: (v) {
                rule.enabled = v;
                state.saveCleanRules();
              },
              title: Text(rule.name),
              subtitle: rule.note.isEmpty ? null : Text(rule.note),
            ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('恢复默认清理规则'),
            onTap: state.resetCleanRules,
          ),
          const Divider(),
          const SettingsReadAloudSection(),
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
            title: Text('阅读 readerplus'),
            subtitle: Text('多平台小说阅读器：Android 与 Linux 桌面共用一套自适应界面'),
          ),
          ListTile(
            title: const Text('版本'),
            subtitle: Text(appVersionLabel),
          ),
          const ListTile(
            title: Text('数据格式'),
            subtitle: Text(
              '自定义 JSON（library / settings / reader_settings / webdav / cleaning_rules）'
              '＋ zip 备份包，保存在应用私有目录',
            ),
          ),
          const ListTile(
            title: Text('来源与致谢'),
            subtitle: Text(
              '部分设计思路来自开源项目 Legado（开源阅读）：排版预设数值、主题配色、'
              '页眉页脚与翻页方式等交互设计；品牌色取自 wzml.cc.cd/logo 的前景颜色 #76DFA1',
            ),
          ),
          const ListTile(
            title: Text('许可'),
            subtitle: Text('GPL-3.0，保留 Legado 原始版权声明，详见仓库 LICENSE'),
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
