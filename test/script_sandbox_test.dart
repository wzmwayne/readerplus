import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/plugin/plugin_executor.dart';
import 'package:reader/services/script/script_host.dart';

/// 脚本工作目录（沙箱）：脚本可完全操控，但出不去。
void main() {
  const executor = PluginExecutor();

  test('工作目录可自由读写增删（无需自带产物目录）', () async {
    final result = await executor.run(
      const PluginJob.script(
        // 用显式字节数组，避免依赖 Hetu 的字符串 API
        source: r'''
          log('工作目录：' + sandboxDir())
          fileWrite('a.txt', [228, 189, 160, 229, 165, 189])
          fileWrite('sub/b.bin', [1, 2, 3])
          var list = fileList()
          var payload = {}
          payload['hasA'] = fileExists('a.txt')
          payload['hasSub'] = fileExists('sub/b.bin')
          payload['sizeA'] = fileSize('a.txt')
          payload['textA'] = fileText('a.txt')
          payload['count'] = list.length
          payload['deleted'] = fileDelete('a.txt')
          payload['hasAAfterDelete'] = fileExists('a.txt')
          result(payload)
        ''',
        timeout: Duration(seconds: 30),
      ),
    );
    expect(result.ok, isTrue, reason: result.error);
    final payload = result.result as Map;
    expect(payload['hasA'], isTrue);
    expect(payload['hasSub'], isTrue, reason: '应能自动创建子目录');
    expect(payload['sizeA'], 6, reason: '“你好”是 6 字节 UTF-8');
    expect(payload['textA'], '你好');
    expect(payload['count'], greaterThanOrEqualTo(1));
    expect(payload['deleted'], isTrue);
    expect(payload['hasAAfterDelete'], isFalse);
  });

  test('路径穿越防护：..、绝对路径、盘符一律拒绝（直接测宿主，不经过脚本）', () async {
    final dir = await Directory.systemTemp.createTemp('sandbox_guard');
    final host = ScriptHost(onLog: (_) {}, outputDir: dir);
    try {
      expect(() => host.fileWrite('../escape.txt', [1]), throwsArgumentError);
      expect(() => host.fileRead('/etc/passwd'), throwsArgumentError);
      expect(() => host.fileWrite('a/../../b.txt', [1]), throwsArgumentError);
      expect(() => host.fileWrite('c:/x.txt', [1]), throwsArgumentError);
      // 合法路径仍可写
      expect(host.fileWrite('ok.txt', [1, 2]), contains('ok.txt'));
      expect(host.fileExists('ok.txt'), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
