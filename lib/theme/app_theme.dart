import 'package:flutter/material.dart';

/// 品牌色：取自 https://wzml.cc.cd/logo 的前景颜色（该 logo 是 5×4 的像素标记，
/// 主色 `fill="#76DFA1"`，即 rgb(118, 223, 161)）。
///
/// 浅色与深色两套默认主题都以它作为种子色生成整套配色。
const Color kBrandColor = Color(0xFF76DFA1);

/// 应用整体配色主题。
///
/// [seeded] 为 true 时（默认浅色/深色主题），backgroundColor 等由
/// Material 3 的种子色方案推导；为基础主题时使用显式给定的颜色。
class AppTheme {
  const AppTheme({
    required this.name,
    required this.primary,
    this.accent,
    this.background,
    this.bottomBar,
    this.isNight = false,
    this.seeded = false,
  });

  final String name;
  final Color primary;
  final Color? accent;
  final Color? background;
  final Color? bottomBar;
  final bool isNight;

  /// 是否由种子色生成整套配色。
  final bool seeded;

  ColorScheme toScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: isNight ? Brightness.dark : Brightness.light,
    );
    if (seeded) return base;
    return base.copyWith(
      primary: primary,
      secondary: accent ?? base.secondary,
      surface: background ?? base.surface,
    );
  }

  ThemeData toThemeData() {
    final scheme = toScheme();
    final background = seeded ? scheme.surface : (this.background ?? scheme.surface);
    final bar = seeded
        ? scheme.surfaceContainerHigh
        : (bottomBar ?? scheme.surfaceContainerHigh);
    final onBar = isNight ? Colors.white : Colors.black87;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: bar,
        foregroundColor: onBar,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: bar),
      navigationRailTheme: NavigationRailThemeData(backgroundColor: bar),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(backgroundColor: bar),
      splashFactory: InkRipple.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamilyFallback: kCjkFontFallback),
      primaryTextTheme:
          base.primaryTextTheme.apply(fontFamilyFallback: kCjkFontFallback),
    );
  }
}

/// 中文字形回退链。
/// Android 由系统自带中文字体覆盖，Linux 桌面依赖系统已安装的 CJK 字体，
/// 这里显式声明回退顺序，避免缺字形时渲染成方块。
const List<String> kCjkFontFallback = [
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'WenQuanYi Zen Hei',
  'Microsoft YaHei',
  'PingFang SC',
  'Heiti SC',
  'Noto Sans SC',
];

/// 前两套为由品牌色生成的默认浅色 / 深色主题，随后是若干内置配色。
const List<AppTheme> kAppThemes = [
  AppTheme(name: '浅色', primary: kBrandColor, seeded: true),
  AppTheme(name: '深色', primary: kBrandColor, seeded: true, isNight: true),
  AppTheme(
    name: '默认',
    primary: Color(0xFF795548),
    accent: Color(0xFFE53935),
    background: Color(0xFFF5F5F5),
    bottomBar: Color(0xFFEEEEEE),
  ),
  AppTheme(
    name: '典雅蓝',
    primary: Color(0xFF03A9F4),
    accent: Color(0xFFAD1457),
    background: Color(0xFFF5F5F5),
    bottomBar: Color(0xFFEEEEEE),
  ),
  AppTheme(
    name: '黑白',
    primary: Color(0xFF303030),
    accent: Color(0xFFE0E0E0),
    background: Color(0xFF424242),
    bottomBar: Color(0xFF424242),
    isNight: true,
  ),
  AppTheme(
    name: 'A屏黑',
    primary: Color(0xFF000000),
    accent: Color(0xFFFFFFFF),
    background: Color(0xFF000000),
    bottomBar: Color(0xFF000000),
    isNight: true,
  ),
];

/// 将 "#RRGGBB" / "#AARRGGBB" 解析为 Color。
Color parseHexColor(String value, {Color fallback = Colors.white}) {
  var hex = value.trim().replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return fallback;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return fallback;
  return Color(parsed);
}
