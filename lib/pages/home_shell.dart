import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'search_tab.dart';
import 'shelf_page.dart';
import 'settings_page.dart';

/// 应用外壳：标签页 + 内容。
///
/// 竖屏：标签在底部（`NavigationBar`），默认只显示图标，可在设置里改为显示文字。
/// 横屏：标签在左侧（`NavigationRail`），默认只显示图标，点击左上角按钮展开为图标 + 文字。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = <({IconData icon, IconData selected, String label})>[
    (icon: Icons.menu_book_outlined, selected: Icons.menu_book, label: '书架'),
    (icon: Icons.search_outlined, selected: Icons.search, label: '搜索'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    final pages = const [ShelfPage(), SearchTab(), SettingsPage()];
    if (_index >= pages.length) _index = 0;

    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (isLandscape) {
      final expanded = settings.landscapeExpanded;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: expanded,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: IconButton(
                  tooltip: expanded ? '收起标签栏' : '展开标签栏',
                  icon: Icon(expanded ? Icons.chevron_left : Icons.menu),
                  onPressed: () {
                    settings.landscapeExpanded = !expanded;
                    state.saveSettings();
                  },
                ),
              ),
              destinations: [
                for (final tab in _tabs)
                  NavigationRailDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selected),
                    label: Text(tab.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: pages[_index]),
          ],
        ),
      );
    }

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelBehavior: settings.portraitLabels
            ? NavigationDestinationLabelBehavior.alwaysShow
            : NavigationDestinationLabelBehavior.alwaysHide,
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selected),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
