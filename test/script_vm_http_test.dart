import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/script/js/js_runtime.dart';
import 'package:reader/services/script/script_storage.dart';
import 'package:reader/services/script/script_vm.dart';

void main() {
  late Directory dir;
  late ScriptVm vm;
  late List<Object?> results;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('script_vm_http_test');
    final storage = await ScriptStorage.open('s1', rootProvider: () async => dir);
    results = [];
    vm = ScriptVm(storage: storage, onLog: (_) {}, onResult: results.add);
    vm.httpImpl = (options) async => {
      'status': 200,
      'headers': {'x-test': 'yes'},
      'text': 'hello ${options['url']}',
      'bytes': [65, 66],
    };
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('http.get 返回 {status, headers, text, bytes}', () async {
    final out = await vm.runAsync(
      'var r = http.get("https://a.com/x"); r.status + "|" + r.text + "|" + r.bytes.length',
    );
    expect(toStringJs(out), '200|hello https://a.com/x|2');
  });

  test('http.request 高自定义（headers / wantBytes / timeout）', () async {
    final out = await vm.runAsync(
      'var r = http.request({url: "u", method: "POST", headers: {a: "b"}, '
      'body: "d", wantBytes: true, timeoutMs: 5000}); r.headers["x-test"]',
    );
    expect(toStringJs(out), 'yes');
  });

  test('网络失败降级为 status=0 且脚本可继续', () async {
    vm.httpImpl = (options) async => throw const SocketException('boom');
    final out = await vm.runAsync(
      'var r = http.get("u"); "status=" + r.status + " err=" + (r.error != null)',
    );
    expect(toStringJs(out), 'status=0 err=true');
  });

  test('ask 可被透明等待', () async {
    vm.onAsk = (question, {secret = false, preset = ''}) async =>
        '答案:$question:${secret ? 'S' : 'P'}';
    final out = await vm.runAsync('ask("你的名字", {secret: true, preset: "x"})');
    expect(toStringJs(out), '答案:你的名字:S');
  });

  test('异步脚本仍可读写三级存储', () async {
    await vm.runAsync('perm.write.utf8("k", "v"); result(perm.read.utf8("k"))');
    expect(results.last, 'v');
  });
}