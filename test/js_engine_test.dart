import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/script/js_engine.dart';

Future<Map<String, Object?>> runJob(Map<String, Object?> job) async {
  final port = ReceivePort();
  final completer = Completer<Map<String, Object?>>();
  port.listen((message) {
    if (message is String) return;
    if (message is Map && message['ok'] != null) {
      if (!completer.isCompleted) completer.complete(message.cast<String, Object?>());
      return;
    }
    if (message is Map && message['type'] == 'ask') {
      (message['replyTo'] as SendPort).send({'ok': true, 'answer': 'auto'});
    }
  });
  JsScriptEngine.isolateEntry(job, port.sendPort);
  final result = await completer.future.timeout(const Duration(seconds: 20));
  port.close();
  return result;
}

void main() {
  late Directory storageRoot;

  setUp(() async {
    storageRoot = await Directory.systemTemp.createTemp('js_engine_test');
  });

  tearDown(() async {
    if (storageRoot.existsSync()) await storageRoot.delete(recursive: true);
  });

  Map<String, Object?> job(Map<String, Object?> extra) => {
    ...extra,
    'storageRoot': storageRoot.path,
  };

  test('脚本：读任务参数并 result', () async {
    final out = await runJob(job({
      'id': 'e2e-1',
      'source': 'var t = JSON.parse(tmp.read.utf8("task")); result(t.params.key)',
      'params': {'key': '夜航船'},
      'kind': 'source',
      'task': 'search',
    }));
    expect(out['ok'], isTrue, reason: '${out['error']}');
    expect(out['result'], '夜航船');
  });

  test('脚本：log 与 ask 往返', () async {
    final out = await runJob(job({
      'id': 'e2e-2',
      'source': 'log("开始"); var a = ask("名字"); result(a)',
    }));
    expect(out['ok'], isTrue, reason: '${out['error']}');
    expect(out['result'], 'auto');
  });

  test('脚本：语法错误返回 ok=false 且带信息', () async {
    final out = await runJob(job({'id': 'e2e-3', 'source': 'if (a {'}));
    expect(out['ok'], isFalse);
    expect('${out['error']}'.contains('语法错误'), isTrue);
  });
}