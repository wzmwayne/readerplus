import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/app_log.dart';

void main() {
  setUp(AppLog.resetForTest);
  tearDown(AppLog.resetForTest);

  group('日志缓冲', () {
    test('记录并按行拆分，带时间戳与标签', () {
      AppLog.info('app', '启动');
      AppLog.write('plugin', '第一行\n第二行');
      expect(AppLog.lines.length, 3);
      expect(AppLog.lines.first, contains('[app] 启动'));
      expect(AppLog.lines[1], contains('[plugin] 第一行'));
      expect(AppLog.lines[2], contains('[plugin] 第二行'));
    });

    test('环形缓冲有上限，旧日志被丢弃', () {
      for (var i = 0; i < AppLog.maxLines + 50; i++) {
        AppLog.info('t', '第 $i 行');
      }
      expect(AppLog.lines.length, AppLog.maxLines);
      expect(AppLog.lines.first, contains('第 50 行'));
    });

    test('错误记录包含异常与堆栈', () {
      AppLog.error('crash', 'boom', StackTrace.fromString('#0  up'));
      final text = AppLog.lines.join('\n');
      expect(text, contains('错误：boom'));
      expect(text, contains('#0  up'));
    });
  });

  group('崩溃报告', () {
    test('包含系统环境、应用信息、崩溃问题与崩溃前日志四部分', () {
      AppLog.info('app', '崩溃前的最后一条日志');
      final report = AppLog.buildReport(
        error: 'StateError: 出错了',
        stack: StackTrace.fromString('#1  frame'),
        context: '导入 TXT 时',
      );
      expect(report, contains('# 崩溃报告'));
      expect(report, contains('## 系统环境'));
      expect(report, contains('平台：'));
      expect(report, contains('## 应用信息'));
      expect(report, contains('版本：'));
      expect(report, contains('## 崩溃问题'));
      expect(report, contains('导入 TXT 时'));
      expect(report, contains('StateError: 出错了'));
      expect(report, contains('#1  frame'));
      expect(report, contains('## 崩溃前日志'));
      expect(report, contains('崩溃前的最后一条日志'));
    });

    test('没有异常信息时也能生成报告', () {
      final report = AppLog.buildReport();
      expect(report, contains('# 崩溃报告'));
      expect(report, contains('## 崩溃前日志'));
    });

    test('未初始化时给出占位路径，初始化后列出全部位置', () {
      expect(AppLog.logPaths, ['(未初始化)']);
    });

    test('环境与应用摘要都有内容', () {
      expect(AppLog.environmentSummary(), contains('平台：'));
      expect(AppLog.environmentSummary(), contains('运行环境：'));
      expect(AppLog.appSummary(), contains('版本：'));
    });
  });

  group('崩溃监听', () {
    test('reportCrash 通知监听者并记录日志', () {
      final reports = <String>[];
      AppLog.addCrashListener(reports.add);
      AppLog.reportCrash('炸了', StackTrace.fromString('#0  x'));
      expect(reports.length, 1);
      expect(reports.first, contains('炸了'));
      expect(AppLog.lines.join('\n'), contains('炸了'));
      AppLog.removeCrashListener(reports.add);
    });
  });
}
