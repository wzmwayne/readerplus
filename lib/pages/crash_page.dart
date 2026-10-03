import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_log.dart';

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
  late final String _report = AppLog.buildReport(
    error: widget.error,
    stack: widget.stack,
    context: widget.context,
  );
  List<String> _exported = const [];
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    List<String> written;
    try {
      written = await AppLog.exportToDownloads(_report);
    } catch (error) {
      written = ['导出失败：$error'];
    }
    if (!mounted) return;
    setState(() {
      _exported = written;
      _exporting = false;
    });
  }

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
              '应用遇到问题，已记录日志（可导出后反馈）',
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
          if (_exported.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SelectableText(
                '已导出：\n${_exported.join('\n')}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _exporting ? null : _export,
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: Text(_exporting ? '导出中…' : '导出报告与日志到下载目录'),
                    ),
                  ),
                ],
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

  AppLog.addCrashListener((report) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    // 已经停在崩溃页就不再叠加
    if (navigator.canPop() == false) return;
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => CrashScreen(
            error: report.split('## 崩溃问题').last,
            onRetry: () => navigator.pop(),
          ),
        ),
      ),
    );
  });
}
