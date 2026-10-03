import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import 'export_dir.dart';

/// 全局日志与崩溃兜底。
///
/// - 一切输出都进内存环形缓冲（界面/崩溃页可读）并落到 `logs/app.log`
/// - 覆盖框架日志（改写 [debugPrint]）、Flutter 构建异常、未捕获的异步异常
/// - 崩溃时可一键导出「报告 + 全部日志」到用户可见的下载目录
class AppLog {
  AppLog._();

  static const int maxLines = 4000;
  static const int maxFileBytes = 2 * 1024 * 1024;

  static final Queue<String> _buffer = Queue<String>();
  static File? _file;
  static IOSink? _sink;
  static bool _initialized = false;
  static final List<void Function(String report)> _crashListeners = [];

  static String get logPath => _file?.path ?? '(未初始化)';

  static List<String> get lines => _buffer.toList(growable: false);

  /// 崩溃监听（界面层用它切到崩溃页）。
  static void addCrashListener(void Function(String report) listener) {
    _crashListeners.add(listener);
  }

  static void removeCrashListener(void Function(String report) listener) {
    _crashListeners.remove(listener);
  }

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/readerplus-logs');
      await dir.create(recursive: true);
      final file = File('${dir.path}/app.log');
      _file = file;
      // 超大日志先轮转，避免无限增长
      if (file.existsSync() && file.lengthSync() > maxFileBytes) {
        final rotated = File('${dir.path}/app.log.1');
        if (rotated.existsSync()) rotated.deleteSync();
        file.renameSync(rotated.path);
      }
      _sink = file.openWrite(mode: FileMode.append);
    } catch (error) {
      _file = null;
    }

    // 框架日志（含各种 print）也写入文件
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message != null) write('fw', message);
    };

    info('app', '启动：${appVersionLabel}');
    info('app', '环境：${environmentSummary()}');
  }

  static void write(String tag, String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    for (final line in message.split('\n')) {
      final entry = '[$timestamp][$tag] $line';
      _buffer.addLast(entry);
      while (_buffer.length > maxLines) {
        _buffer.removeFirst();
      }
      try {
        _sink?.writeln(entry);
      } catch (_) {}
    }
  }

  static void info(String tag, String message) => write(tag, message);

  static void error(String tag, Object error, [StackTrace? stack]) {
    write(tag, '错误：$error');
    if (stack != null) write(tag, stack.toString());
  }

  /// 环境摘要（崩溃报告用）。
  static String environmentSummary() => [
    '平台：${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    '运行环境：${Platform.version}',
    'CPU 核数：${Platform.numberOfProcessors}',
  ].join('\n  ');

  /// 应用信息摘要。
  static String appSummary() =>
      '版本：${appVersionLabel}\n  日志文件：$logPath';

  /// 组装崩溃报告（系统环境 + 应用信息 + 崩溃问题 + 崩溃前日志）。
  static String buildReport({
    Object? error,
    StackTrace? stack,
    String? context,
  }) {
    final buffer = StringBuffer()
      ..writeln('# 崩溃报告')
      ..writeln()
      ..writeln('时间：${DateTime.now().toIso8601String()}')
      ..writeln()
      ..writeln('## 系统环境')
      ..writeln(environmentSummary())
      ..writeln()
      ..writeln('## 应用信息')
      ..writeln(appSummary())
      ..writeln()
      ..writeln('## 崩溃问题');
    if (context != null && context.isNotEmpty) buffer.writeln(context);
    if (error != null) buffer.writeln('$error');
    if (stack != null) {
      buffer
        ..writeln()
        ..writeln('```')
        ..writeln(stack.toString())
        ..writeln('```');
    }
    buffer
      ..writeln()
      ..writeln('## 崩溃前日志（最近 ${_buffer.length} 行）')
      ..writeln('```')
      ..writeln(_buffer.join('\n'))
      ..writeln('```');
    return buffer.toString();
  }

  /// 导出报告 + 全部日志到下载目录；返回写出路径。
  static Future<List<String>> exportToDownloads(String report) async {
    final dir = await userVisibleDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .substring(0, 15);
    final written = <String>[];

    final reportFile = File('${dir.path}/crash-$stamp.md');
    await reportFile.writeAsString(report, flush: true);
    written.add(reportFile.path);

    final log = _file;
    if (log != null && log.existsSync()) {
      final target = File('${dir.path}/app-log-$stamp.txt');
      await log.copy(target.path);
      written.add(target.path);
    }
    return written;
  }

  /// 记录一次崩溃并通知界面（尽力而为，不抛异常）。
  static void reportCrash(Object cause, StackTrace? stack, {String? context}) {
    AppLog.error('crash', cause, stack);
    final report = buildReport(error: cause, stack: stack, context: context);
    for (final listener in List.of(_crashListeners)) {
      try {
        listener(report);
      } catch (_) {}
    }
    // 无论界面是否成功展示，都先落一份到下载目录兜底
    unawaited(exportToDownloads(report).catchError((_) => <String>[]));
  }

  /// 卸载钩子的测试辅助。
  @visibleForTesting
  static void resetForTest() {
    _buffer.clear();
    _sink = null;
    _file = null;
    _initialized = false;
    _crashListeners.clear();
  }
}
