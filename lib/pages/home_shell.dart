import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'scripts_page.dart';
import 'search_page.dart';
import 'shelf_page.dart';
import 'settings_page.dart';

/// 应用外壳：标签页 + 内容。
///
/// 竖屏：标签在底部（`NavigationBar`），默认只显示图标，可在设置里改为显示文字。
/// 横屏：标签在左侧（`NavigationRail`），默认只显示图标，点击左上角按钮展开为图标 + 文字。
///
/// **横竖屏切换必须保留各页状态**（搜索中的实时日志、结果、插件页勾选等）：
/// 因此两端的"内容树"完全一致 —— 同一个 [IndexedStack]、同一组子索引，
/// 只有导航条本身在 `NavigationRail` / 空占位之间切换（占位保证 Row 的
/// 子索引稳定，否则 Flutter 会按索引错配导致内容被重建、State 丢失）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// 只创建一次：配合 IndexedStack，切标签与转屏都不重建页面。
  late final List<Widget> _pages = const [
    ShelfPage(),
    SearchPage(),
    ScriptsPage(),
    SettingsPage(),
  ];

  static const _tabs = <({IconData icon, IconData selected, String label})>[
    (icon: Icons.menu_book_outlined, selected: Icons.menu_book, label: '书架'),
    (icon: Icons.search_outlined, selected: Icons.search, label: '搜索'),
    (icon: Icons.extension_outlined, selected: Icons.extension, label: '插件'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    if (_index >= _pages.length) _index = 0;

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final expanded = settings.landscapeExpanded;

    return Scaffold(
      body: Row(
        children: [
          // 子索引 0：横屏为导航栏，竖屏为空占位（保持子索引稳定 ⇒ 内容不被重建）
          isLandscape
              ? NavigationRail(
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
                )
              : const SizedBox.shrink(),
          // 子索引 1
          isLandscape
              ? const VerticalDivider(width: 1, thickness: 1)
              : const SizedBox.shrink(),
          // 子索引 2：内容（四种页面都在同一棵 IndexedStack 里，状态不丢）
          Expanded(
            child: IndexedStack(index: _index, children: _pages),
          ),
        ],
      ),
      bottomNavigationBar: isLandscape
          ? null
          : NavigationBar(
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
