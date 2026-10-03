import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';

/// 全局日志与崩溃兜底。
///
/// - 一切输出都进内存环形缓冲（界面/崩溃页可读）并落到 `logs/app.log`
/// - 覆盖框架日志（改写 [debugPrint]）、Flutter 构建异常、未捕获的异步异常
/// - 崩溃时可一键导出「报告 + 全部日志」到用户可见的下载目录
class AppLog {
  AppLog._();

  static const int maxLines = 4000;

  static final Queue<String> _buffer = Queue<String>();
  static final List<File> _files = <File>[];
  static final List<IOSink> _sinks = <IOSink>[];
  static bool _initialized = false;
  static final List<void Function(String report)> _crashListeners = [];

  /// 所有日志文件路径（Android 上会同时写内部与外部应用目录，方便取日志）。
  static List<String> get logPaths =>
      _files.isEmpty ? ['(未初始化)'] : _files.map((f) => f.path).toList();

  static String get logPath => logPaths.first;

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
    // 固定位置、单个文件、始终追加、不轮转、不可覆盖。
    // Android 同时写内部私有目录与外部应用目录：
    //   内部 /data/user/0/<包名>/files/reader/logs/app.log（一定可写，文件管理器看不到）
    //   外部 /storage/emulated/0/Android/data/<包名>/files/reader/logs/app.log（可取走）
    final dirs = <Directory>[];
    try {
      final support = await getApplicationSupportDirectory();
      dirs.add(Directory('${support.path}/reader/logs'));
    } catch (_) {}
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        dirs.add(Directory('${external.path}/reader/logs'));
      }
    } catch (_) {}

    for (final dir in dirs) {
      try {
        await dir.create(recursive: true);
        final file = File('${dir.path}/app.log');
        _files.add(file);
        _sinks.add(file.openWrite(mode: FileMode.append));
      } catch (_) {
        // 该位置不可用时跳过，其他位置继续
      }
    }

    // 框架日志（含各种 print）也写入文件
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message != null) write('fw', message);
    };

    info('app', '启动：$appVersionLabel');
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
      for (final sink in _sinks) {
        try {
          sink.writeln(entry);
        } catch (_) {}
      }
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
      '版本：$appVersionLabel\n  日志文件：\n    ${logPaths.join('\n    ')}';

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

  /// 记录一次崩溃并通知界面（尽力而为，不抛异常）。
  static void reportCrash(Object cause, StackTrace? stack, {String? context}) {
    AppLog.error('crash', cause, stack);
    final report = buildReport(error: cause, stack: stack, context: context);
    for (final listener in List.of(_crashListeners)) {
      try {
        listener(report);
      } catch (_) {}
    }
  }

  /// 卸载钩子的测试辅助。
  @visibleForTesting
  static void resetForTest() {
    _buffer.clear();
    _sinks.clear();
    _files.clear();
    _initialized = false;
    _crashListeners.clear();
  }
}
