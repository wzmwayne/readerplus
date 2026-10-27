import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/script/js/js_runtime.dart';
import 'package:reader/services/script/script_storage.dart';
import 'package:reader/services/script/script_vm.dart';

void main() {
  late Directory dir;
  late ScriptStorage storage;
  late ScriptVm vm;
  late List<String> logs;
  late List<Object?> results;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('script_vm_test');
    storage = await ScriptStorage.open('s1', rootProvider: () async => dir);
    logs = [];
    results = [];
    vm = ScriptVm(
      storage: storage,
      onLog: logs.add,
      onResult: results.add,
    );
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('log 与 result 回调', () {
    vm.run('log("你好", 42); result("ok")');
    expect(logs, ['你好 42']);
    expect(results, ['ok']);
  });

  test('任务信息经 tmp.read.utf8("task") 读取', () {
    vm.injectTask(
      task: {
        'kind': 'source',
        'task': 'search',
        'params': {'key': '夜航船'},
      },
    );
    final out = vm.run('JSON.parse(tmp.read.utf8("task")).params.key');
    expect(toStringJs(out), '夜航船');
  });

  test('输入二进制经 tmp.read.raw 读取', () {
    vm.injectTask(task: {'kind': 'clean'}, inputs: {'in.txt': [65, 66, 67]});
    final out = vm.run('tmp.read.raw("input/in.txt")[0]');
    expect(toStringJs(out), '65');
  });

  test('三级存储同名方法', () {
    vm.run('mem.write.utf8("k", "m"); tmp.write.utf8("k", "t"); perm.write.utf8("k", "p")');
    expect(vm.run('perm.read.utf8("k")'), 'p');
    expect(storage.memory.readUtf8('k'), 'm');
    expect(storage.temp.readUtf8('k'), 't');
    expect(vm.run('perm.keys().length'), 1);
    vm.run('perm.remove("k")');
    expect(vm.run('perm.read.utf8("k")'), isNull);
  });

  test('二进制写入与读回', () {
    vm.run('perm.write.raw("b", [1,2,3])');
    expect(storage.perm.readRaw('b'), [1, 2, 3]);
  });

  test('保留键写入被拒', () {
    expect(() => vm.run('tmp.write.utf8("task", "x")'),
        throwsA(isA<ScriptStoreException>()));
  });

  test('decode / urlJoin / digest / base64', () {
    expect(vm.run('decode([65,66,67])'), 'ABC');
    expect(vm.run('urlJoin("https://a.com/x/", "b/c")'),
        'https://a.com/x/b/c');
    expect(vm.run('digest("md5", "abc")'), '900150983cd24fb0d6963f7d28e17f72');
    expect(vm.run('base64.encode("abc")'), 'YWJj');
    expect(vm.run('base64.decode("YWJj")[0]'), 97);
  });
}