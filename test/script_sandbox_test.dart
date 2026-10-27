import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/script/script_storage.dart';

/// 沙箱边界：脚本只能通过三级存储读写，且不同脚本互不可见。
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('script_sandbox_test');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('不同脚本的永久存储相互隔离', () async {
    final a = await ScriptStorage.open('script-a', rootProvider: () async => root);
    final b = await ScriptStorage.open('script-b', rootProvider: () async => root);
    a.perm.writeUtf8('k', 'A');
    b.perm.writeUtf8('k', 'B');
    expect(a.perm.readUtf8('k'), 'A');
    expect(b.perm.readUtf8('k'), 'B');
  });

  test('临时层清扫后不可见，永久层保留', () async {
    final s = await ScriptStorage.open('script-a', rootProvider: () async => root);
    s.temp.writeUtf8('t', '1');
    s.perm.writeUtf8('p', '2');
    await ScriptStorage.sweepTemp(rootProvider: () async => root);
    final again = await ScriptStorage.open('script-a', rootProvider: () async => root);
    expect(again.temp.keys(), isEmpty);
    expect(again.perm.readUtf8('p'), '2');
  });

  test('键名不会写出到目录之外', () async {
    final s = await ScriptStorage.open('script-a', rootProvider: () async => root);
    s.perm.writeUtf8('../../escape', 'x');
    final escaped = File('${root.path}/../../escape');
    expect(escaped.existsSync(), isFalse);
    expect(s.perm.readUtf8('../../escape'), 'x');
  });
}