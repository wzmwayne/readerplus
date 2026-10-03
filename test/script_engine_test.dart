import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/script/hetu_engine.dart';
import 'package:reader/services/script/script_runner.dart';

void main() {
  ScriptRunner runner({void Function(String)? log}) => ScriptRunner(
    entry: HetuScriptEngine.isolateEntry,
    onLog: log,
  );

  group('Hetu 脚本引擎（isolate 内执行）', () {
    test('绑定宿主函数 + result 交回结果 + 实时日志', () async {
      final logs = <String>[];
      final result = await runner(log: logs.add).run('''
        log('开始')
        var total = 0
        for (var i = 0; i < 5; i = i + 1) { total = total + i }
        log('累加完成')
        result(JSON.stringify({'sum': total, 'name': '示例'}))
      ''');
      expect(result.ok, isTrue, reason: result.error);
      expect(logs, contains('开始'));
      expect(logs, contains('累加完成'));
      final payload = jsonDecode(result.result as String) as Map;
      expect(payload['sum'], 10);
      expect(payload['name'], '示例');
    });

    test('脚本可 await 宿主的异步能力（本地 HTTP 服务器）', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"items":[{"id":"7","title":"异步书名"}]}');
        await request.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}/search';

      final result = await runner().run('''
        var response = await httpGet('$url')
        var data = JSON.parse(response['text'])
        result(JSON.stringify({'status': response['status'], 'title': data.items[0].title}))
      ''');
      await server.close(force: true);

      expect(result.ok, isTrue, reason: result.error);
      final map = jsonDecode(result.result as String) as Map;
      expect(map['status'], 200);
      expect(map['title'], '异步书名');
    });

    test('死循环可被硬超时强制终止（真取消，App 不受影响）', () async {
      final sw = Stopwatch()..start();
      final result = await runner().run(
        'var i = 0\nwhile (true) { i = i + 1 }',
        timeout: const Duration(seconds: 2),
      );
      sw.stop();
      expect(result.ok, isFalse);
      expect(result.cancelled, isTrue);
      expect(result.error, contains('超时'));
      expect(
        sw.elapsed.inSeconds,
        lessThan(20),
        reason: '必须在超时后很快返回，而不是被死循环拖死',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('脚本异常被捕获为失败结果，不抛给宿主', () async {
      final result = await runner().run('throw "脚本内部错误"');
      expect(result.ok, isFalse);
      expect(result.error, isNotEmpty);
    });

    test('正则与 URL 工具可用', () async {
      final result = await runner().run('''
        var m = regexp('第([一二三])章', '第一章 起', '1')
        var u = urlJoin('https://a.com/x/', 'y/z')
        result(JSON.stringify({'m': m, 'u': u}))
      ''');
      expect(result.ok, isTrue, reason: result.error);
      final map = jsonDecode(result.result as String) as Map;
      expect(map['m'], '一');
      expect(map['u'], 'https://a.com/x/y/z');
    });
  });
}
