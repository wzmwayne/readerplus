import 'package:flutter/material.dart';

/// 整体配色主题，取自原版 themeConfig 默认数据。
class AppTheme {
  const AppTheme({
    required this.name,
    required this.primary,
    required this.accent,
    required this.background,
    required this.bottomBar,
    this.isNight = false,
  });

  final String name;
  final Color primary;
  final Color accent;
  final Color background;
  final Color bottomBar;
  final bool isNight;

  Color get onBackground => isNight ? const Color(0xFFE0E0E0) : const Color(0xFF212121);

  ThemeData toThemeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: isNight ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: primary,
      secondary: accent,
      surface: background,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: bottomBar,
        foregroundColor: isNight ? Colors.white : Colors.black87,
        elevation: 0,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bottomBar,
      ),
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

const List<AppTheme> kAppThemes = [
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
