import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/script/script_storage.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('script_storage_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<ScriptStorage> open() =>
      ScriptStorage.open('s1', rootProvider: () async => tmp);

  group('内存层', () {
    test('写读 raw / utf8', () {
      final mem = MemoryTier();
      mem.writeRaw('a', [1, 2, 3]);
      expect(mem.readRaw('a'), [1, 2, 3]);
      mem.writeUtf8('b', '中文');
      expect(mem.readUtf8('b'), '中文');
      expect(mem.readUtf8('missing'), isNull);
    });

    test('remove / keys / clear 与用量统计', () {
      final mem = MemoryTier();
      mem.writeUtf8('k1', 'v1');
      mem.writeUtf8('k2', 'v2');
      expect(mem.keys(), ['k1', 'k2']);
      expect(mem.usedBytes, 4);
      expect(mem.remove('k1'), isTrue);
      expect(mem.usedBytes, 2);
      expect(mem.remove('k1'), isFalse);
      mem.clear();
      expect(mem.keys(), isEmpty);
      expect(mem.usedBytes, 0);
    });

    test('超配额抛错', () {
      final mem = MemoryTier(quotaBytes: 4);
      mem.writeUtf8('a', 'abcd');
      expect(() => mem.writeUtf8('b', 'e'), throwsA(isA<ScriptStoreException>()));
    });
  });

  group('磁盘层', () {
    test('tmp 写读并落盘，重开后仍在（同进程）', () async {
      final s = await open();
      s.temp.writeUtf8('cookie', 'abc');
      expect(s.temp.readUtf8('cookie'), 'abc');
      expect(File('${s.temp.root.path}/index.json').existsSync(), isTrue);
    });

    test('perm 跨实例保留', () async {
      final s1 = await open();
      s1.perm.writeUtf8('cursor', '7');
      final s2 = await open();
      expect(s2.perm.readUtf8('cursor'), '7');
    });

    test('二进制往返不变形', () async {
      final s = await open();
      final bytes = List<int>.generate(256, (i) => i);
      s.perm.writeRaw('bin', bytes);
      expect(s.perm.readRaw('bin'), bytes);
    });

    test('保留键不可写（task / input*)', () async {
      final s = await open();
      expect(() => s.temp.writeUtf8('task', 'x'), throwsA(isA<ScriptStoreException>()));
      expect(() => s.temp.writeRaw('input/a.txt', [1]),
          throwsA(isA<ScriptStoreException>()));
    });

    test('空键与超长键被拒', () async {
      final s = await open();
      expect(() => s.temp.writeUtf8('', 'x'), throwsA(isA<ScriptStoreException>()));
      final long = 'k' * 300;
      expect(() => s.temp.writeUtf8(long, 'x'), throwsA(isA<ScriptStoreException>()));
    });

    test('remove / keys / clear', () async {
      final s = await open();
      s.perm.writeUtf8('a', '1');
      s.perm.writeUtf8('b', '2');
      expect(s.perm.keys(), ['a', 'b']);
      expect(s.perm.remove('a'), isTrue);
      expect(s.perm.keys(), ['b']);
      s.perm.clear();
      expect(s.perm.keys(), isEmpty);
    });

    test('清扫 tmp 目录但保留 perm', () async {
      final s = await open();
      s.temp.writeUtf8('x', '1');
      s.perm.writeUtf8('y', '2');
      await ScriptStorage.sweepTemp(rootProvider: () async => tmp);
      final s2 = await open();
      expect(s2.temp.keys(), isEmpty);
      expect(s2.perm.readUtf8('y'), '2');
    });
  });
}