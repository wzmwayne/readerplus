import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/l10n.dart';

import 'pages/crash_page.dart';
import 'pages/home_shell.dart';
import 'services/app_log.dart';
import 'services/font_store.dart';
import 'services/script/script_storage.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// 供崩溃页跳转使用（未捕获异步异常时尽力切到崩溃页）。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  final sw = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // 先装日志与崩溃兜底，保证后续一切（含崩溃）都有记录
  await AppLog.init();
  installCrashHandlers(appNavigatorKey);
  // 先把设置读出来再渲染第一帧：否则首帧会用默认主题，随后才切到用户选择的主题，
  // 表现为开屏时一闪而过的「默认主题」。
  final state = AppState();
  await state.init();
  // 注册用户导入的字体包（不内置字体，默认系统字体）
  await FontStore().registerAll();
  // 清扫脚本临时存储：tmp 层只对单次运行有效，残留一律丢弃。
  // 不阻塞首帧：清理失败也不影响启动。
  unawaited(ScriptStorage.sweepTemp().catchError((Object e) {
    AppLog.write('store', '清扫临时存储失败：$e');
  }));
  if (kDebugMode) {
    debugPrint('[startup] init=${sw.elapsedMilliseconds}ms');
  }
  runApp(ReaderApp(state: state));
  if (kDebugMode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[startup] first-frame=${sw.elapsedMilliseconds}ms');
    });
  }
}

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final theme =
              kAppThemes[state.settings.themeIndex.clamp(0, kAppThemes.length - 1)];
          final lang = state.settings.resolvedLang;
          return MaterialApp(
            navigatorKey: appNavigatorKey,
            title: L10n.of(state.settings).appTitle,
            locale: Locale(lang),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            debugShowCheckedModeBanner: false,
            theme: theme.toThemeData(),
            home: const RootPage(),
          );
        },
      ),
    );
  }
}

class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const HomeShell();
  }
}
