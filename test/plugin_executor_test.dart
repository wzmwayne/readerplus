import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/plugin/plugin_executor.dart';

/// 统一入口：脚本作业与规则作业必须走**同一个** isolate 执行器。
void main() {
  const executor = PluginExecutor();

  test('脚本作业：内置假书源在新执行器上可搜索', () async {
    final source = await File('assets/plugins/fake_source.ht').readAsString();
    final result = await executor.run(
      PluginJob.script(
        source: source,
        params: {'task': 'search', 'query': '测试'},
      ),
    );
    expect(result.ok, isTrue, reason: result.error);
    final items = ((result.result as Map)['items'] as List).cast<Map>();
    expect(items.length, 3);
    expect(result.logs.join('\n'), contains('命中 3 条'));
  });

  test('规则作业：同一执行器 + 同一套宿主 HTTP（本地服务器）', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"results":[{"id":"1","title":"规则书名"},{"id":"2","title":"第二本"}]}');
      await request.response.close();
    });
    final ruleJson = jsonEncode({
      'id': 'rule-demo',
      'name': '规则示例',
      'version': 1,
      'search': {
        'url': 'http://127.0.0.1:${server.port}/search?q={{query}}',
        'format': 'json',
        'list': 'results[*]',
        'fields': {'id': 'id', 'title': 'title'},
      },
    });

    final result = await executor.run(
      PluginJob.rule(
        ruleJson: ruleJson,
        params: {'task': 'search', 'query': 'x'},
        timeout: const Duration(seconds: 30),
      ),
    );
    await server.close(force: true);

    expect(result.ok, isTrue, reason: result.error);
    final items = ((result.result as Map)['items'] as List).cast<Map>();
    expect(items.length, 2);
    expect(items.first['title'], '规则书名');
    expect(result.logs.join('\n'), contains('规则执行：task=search'));
  });

  test('两种作业都具备硬超时真取消（规则死循环不可能，但脚本可以）', () async {
    final result = await executor.run(
      PluginJob.script(
        source: 'while (true) {}',
        timeout: const Duration(seconds: 2),
      ),
    );
    expect(result.ok, isFalse);
    expect(result.error, contains('超时'));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
