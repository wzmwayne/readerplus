import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../models/app_settings.dart';
import '../state/app_state.dart';
import 'developer_page.dart';
import 'scripts_page.dart';
import 'settings_read_aloud_section.dart';
import '../theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
              // 竖屏与横屏各自记忆（竖屏默认 3、横屏默认 6，范围 1-10）
              value: (MediaQuery.orientationOf(context) == Orientation.landscape
                      ? settings.gridColumnsLandscape
                      : settings.gridColumnsPortrait)
                  .clamp(kShelfColumnsMin, kShelfColumnsMax)
                  .toDouble(),
              min: kShelfColumnsMin.toDouble(),
              max: kShelfColumnsMax.toDouble(),
              divisions: 9,
              label: MediaQuery.orientationOf(context) == Orientation.landscape
                  ? '横屏 ${settings.gridColumnsLandscape}'
                  : '竖屏 ${settings.gridColumnsPortrait}',
              onChanged: settings.gridLayout
                  ? (v) {
                      if (MediaQuery.orientationOf(context) ==
                          Orientation.landscape) {
                        settings.gridColumnsLandscape = v.round();
                      } else {
                        settings.gridColumnsPortrait = v.round();
                      }
                      state.saveSettings();
                    }
                  : null,
            ),
            trailing: Text(
              MediaQuery.orientationOf(context) == Orientation.landscape
                  ? '横屏 ${settings.gridColumnsLandscape}'
                  : '竖屏 ${settings.gridColumnsPortrait}',
            ),
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
          const SettingsReadAloudSection(),
          const Divider(),
          const _SectionTitle('关于'),
          const ListTile(
            title: Text('阅读 readerplus'),
            subtitle: Text('多平台小说阅读器：Android 与 Linux 桌面共用一套自适应界面'),
          ),
          const _VersionTile(),
          const ListTile(
            title: Text('数据格式'),
            subtitle: Text(
              '自定义 JSON（library / settings / reader_settings / sources）'
              '，保存在应用私有目录',
            ),
          ),
          const ListTile(
            title: Text('来源与致谢'),
            subtitle: Text(
              '部分设计思路来自开源项目 Legado（开源阅读）：排版预设数值、主题配色、'
              '页眉页脚与翻页方式等交互设计；品牌色取自 wzml.cc.cd/logo 的前景颜色 #76DFA1',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.terminal_outlined),
            title: const Text('脚本管理'),
            subtitle: const Text('按类型查看 / 编辑 / 删除 / 添加脚本'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScriptsPage()),
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

/// 版本一栏：连点 7 次进入开发者页面。
class _VersionTile extends StatefulWidget {
  const _VersionTile();

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  int _taps = 0;

  void _onTap() {
    _taps++;
    if (_taps >= 7) {
      _taps = 0;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DeveloperPage()),
      );
      return;
    }
    if (_taps >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('再点 ${7 - _taps} 次进入开发者页面'),
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('版本'),
    subtitle: Text(appVersionLabel),
    onTap: _onTap,
  );
}
