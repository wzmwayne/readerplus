import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_log.dart';

/// 崩溃页是否正在显示（避免重复入栈与递归）。
bool crashPageVisible = false;

/// 崩溃页：显示系统环境、应用信息、崩溃问题与崩溃前日志，并可导出到下载目录。
///
/// 同时被 `ErrorWidget.builder`（构建期异常）和全局错误监听（未捕获异步异常）使用。
class CrashScreen extends StatefulWidget {
  const CrashScreen({
    super.key,
    this.error,
    this.stack,
    this.context,
    this.onRetry,
  });

  final Object? error;
  final StackTrace? stack;
  final String? context;
  final VoidCallback? onRetry;

  /// 由 FlutterErrorDetails 构造。
  factory CrashScreen.fromDetails(FlutterErrorDetails details) => CrashScreen(
    error: details.exception,
    stack: details.stack,
    context: details.context?.toString(),
  );

  @override
  State<CrashScreen> createState() => _CrashScreenState();
}

class _CrashScreenState extends State<CrashScreen> {
  @override
  void initState() {
    super.initState();
    crashPageVisible = true;
  }

  @override
  void dispose() {
    crashPageVisible = false;
    super.dispose();
  }

  late final String _report = AppLog.buildReport(
    error: widget.error,
    stack: widget.stack,
    context: widget.context,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('出错了'),
        automaticallyImplyLeading: false,
        actions: [
          if (widget.onRetry != null)
            TextButton(onPressed: widget.onRetry, child: const Text('重试')),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.all(12),
            child: Text(
              '应用遇到问题，信息已写入日志文件',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _report,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                '日志文件（追加写入，多处同步）：\n${AppLog.logPaths.join('\n')}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 全局错误处理入口：装好钩子后，崩溃会进日志、进崩溃页、并落一份到下载目录。
void installCrashHandlers(GlobalKey<NavigatorState> navigatorKey) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    final message = details.exception.toString();
    // 布局溢出只是渲染警告（release 下同样会发生），
    // 不该把用户扔进崩溃页、也不该生成崩溃报告。
    if (message.contains('overflowed by')) {
      AppLog.info('layout', '布局溢出（已忽略）：$message');
      return;
    }
    AppLog.reportCrash(
      details.exception,
      details.stack,
      context: details.context?.toString(),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.reportCrash(error, stack);
    return true;
  };

  ErrorWidget.builder = (details) => CrashScreen.fromDetails(details);

  var queued = false;
  AppLog.addCrashListener((report) {
    // 只在下一帧推入，且崩溃页已显示时不再叠加：
    // 否则在 build/layout 期间 push 会引发二次异常，进而递归崩溃。
    if (queued || crashPageVisible) return;
    queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      queued = false;
      final navigator = navigatorKey.currentState;
      if (navigator == null || crashPageVisible) return;
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => CrashScreen(
                error: report.split('## 崩溃问题').last,
                onRetry: () => navigator.maybePop(),
              ),
            ),
          )
          .catchError((Object _) {});
    });
  });
}
