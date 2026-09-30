import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  final sw = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // 先把设置读出来再渲染第一帧：否则首帧会用默认主题，随后才切到用户选择的主题，
  // 表现为开屏时一闪而过的「默认主题」。
  final state = AppState();
  await state.init();
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
          return MaterialApp(
            title: '阅读',
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
