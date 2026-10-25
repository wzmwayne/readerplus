import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../services/app_log.dart';
import '../services/font_store.dart';
import '../state/app_state.dart';
import 'developer_page.dart';
import 'script_consent_page.dart';
import 'scripts_page.dart';
import 'settings_read_aloud_section.dart';
import '../theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l = L10n.of(state.settings);
    final settings = state.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _SectionTitle('主题配色'),
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
          _SectionTitle(l.settingsSectionUi),
          SwitchListTile(
            value: settings.portraitLabels,
            onChanged: (v) {
              settings.portraitLabels = v;
              state.saveSettings();
            },
            title: Text(l.settingsPortraitLabels),
            subtitle: Text(l.settingsPortraitOnly),
          ),
          const Divider(),
          _SectionTitle(l.settingsSectionShelf),
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
          _SectionTitle('界面'),
          Builder(
            builder: (context) {
              final l = L10n.of(state.settings);
              return ListTile(
                leading: const Icon(Icons.translate),
                title: Text(l.language),
                subtitle: Text(_langLabel(l, state.settings.langMode)),
                onTap: () => _pickLanguage(context, state),
              );
            },
          ),
          _SectionTitle('字体'),
          ListTile(
            leading: const Icon(Icons.font_download_outlined),
            title: const Text('导入字体包'),
            subtitle: Text(
              state.readerSettings.fontFamily.isEmpty
                  ? '当前使用系统字体'
                  : '当前字体：${state.readerSettings.fontFamily}',
            ),
            onTap: () => _importFontPackage(context, state),
          ),
          ListTile(
            leading: const Icon(Icons.font_download_off_outlined),
            title: const Text('恢复系统字体'),
            enabled: state.readerSettings.fontFamily.isNotEmpty,
            onTap: () {
              state.readerSettings.fontFamily = '';
              state.saveReaderSettings();
            },
          ),
          _SectionTitle('脚本'),
          SwitchListTile(
            value: settings.scriptsEnabled == true,
            onChanged: (value) => _setScriptsEnabled(context, value),
            secondary: const Icon(Icons.code),
            title: Text(l.enableScripts),
            subtitle: Text(_scriptsStatusText(l, settings.scriptsEnabled)),
          ),
          ListTile(
            leading: const Icon(Icons.hourglass_empty),
            title: const Text('下载脚本运行上限'),
            subtitle: Text(
              state.settings.downloadTimeoutSeconds == 0
                  ? '不限制（默认）· 可随时在搜索页点「取消」强制停止'
                  : '${state.settings.downloadTimeoutSeconds ~/ 60} 分钟',
            ),
            onTap: () => _pickDownloadTimeout(context),
          ),
          const Divider(),
          _SectionTitle(l.settingsSectionAbout),
          ListTile(
            title: Text('阅读 readerplus'),
            subtitle: Text(l.settingsAppDescription),
          ),
          const _VersionTile(),
          ListTile(
            title: Text('数据格式'),
            subtitle: Text(
              l.settingsCustomJson,
            ),
          ),
          ListTile(
            title: Text(l.settingsCredits),
            subtitle: Text(
              l.settingsLegadoNotice,
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

  static String _langLabel(L10n l, AppLangMode mode) {
    switch (mode) {
      case AppLangMode.system:
        return l.languageSystem;
      case AppLangMode.zh:
        return l.languageZh;
      case AppLangMode.en:
        return l.languageEn;
    }
  }

  /// 语言选择：跟随系统 / 中文 / English（立即生效并持久化）。
  static Future<void> _pickLanguage(BuildContext context, AppState state) async {
    final l = L10n.of(state.settings);
    final current = state.settings.langMode;
    final picked = await showDialog<AppLangMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.language),
        children: [
          for (final mode in AppLangMode.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(mode),
              child: ListTile(
                title: Text(_langLabel(l, mode)),
                trailing: mode == current ? const Icon(Icons.check) : null,
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    state.settings.langMode = picked;
    await state.saveSettings();
    AppLog.info('settings', l.settingsLangSwitched(picked.name));
  }

  /// 开关状态文案：关掉之后会发生什么、怎么重新打开，都说清楚。
  static String _scriptsStatusText(L10n l, bool? scriptsEnabled) {
    switch (scriptsEnabled) {
      case true:
        return l.scriptsOnDetail;
      case false:
        return l.scriptsOffDetail;
      case null:
        return l.scriptsUndecidedDetail;
    }
  }

  /// 关 → 开必须过闸门（通过才置 true）；开 → 关直接置 false。
  Future<void> _setScriptsEnabled(BuildContext context, bool value) async {
    final state = context.read<AppState>();
    final l = L10n.of(state.settings);
    if (!value) {
      state.settings.scriptsEnabled = false;
      await state.saveSettings();
      AppLog.info('script', l.settingsScriptTurnedOff);
      return;
    }
    // 闸门页自己负责落盘：通过 ⇒ true，暂不启用 ⇒ false
    await ScriptConsentPage.show(context);
  }

  /// 下载脚本运行上限：0 = 不限制（默认）。
  Future<void> _pickDownloadTimeout(BuildContext context) async {
    final state = context.read<AppState>();
    const options = <({String label, int seconds})>[
      (label: '不限制（默认）', seconds: 0),
      (label: '5 分钟', seconds: 5 * 60),
      (label: '30 分钟', seconds: 30 * 60),
      (label: '2 小时', seconds: 2 * 60 * 60),
    ];
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('下载脚本运行上限'),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(option.seconds),
              child: ListTile(
                title: Text(option.label),
                trailing: state.settings.downloadTimeoutSeconds == option.seconds
                    ? const Icon(Icons.check)
                    : null,
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    state.settings.downloadTimeoutSeconds = picked;
    await state.saveSettings();
    AppLog.info(
      'settings',
      L10n.of(state.settings).settingsDownloadLimitSet(picked),
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


/// 导入 TTF/OTF 字体包并立即启用（APK 不内置字体，默认系统字体）。
Future<void> _importFontPackage(BuildContext context, AppState state) async {
  const group = XTypeGroup(
    label: '字体文件',
    extensions: ['ttf', 'otf'],
  );
  final file = await openFile(acceptedTypeGroups: const [group]);
  if (file == null) return;
  try {
    final imported = await FontStore().import(File(file.path));
    state.readerSettings.fontFamily = imported.family;
    state.saveReaderSettings();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导入并启用：' + imported.label)),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('导入失败：' + e.toString())),
    );
  }
}
