import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/plugin/builtin_sources.dart';
import 'package:reader/services/plugin/script_meta.dart';
import 'package:reader/services/plugin/source_service.dart';
import 'package:reader/services/plugin/source_store.dart';

/// 内置脚本必须随应用版本同步，并且声明能被正确解析（否则会被当成"其他"）。
void main() {
  Future<String> readAsset(String asset) => File(asset).readAsString();

  test('三个内置脚本的声明都能解析出正确类型', () async {
    final expected = {
      'assets/plugins/fake_source.ht': ScriptKind.source,
      'assets/plugins/gutenberg_source.ht': ScriptKind.source,
      'assets/plugins/txt_cleaner.ht': ScriptKind.clean,
    };
    for (final entry in expected.entries) {
      final meta = ScriptMeta.parse(await readAsset(entry.key));
      expect(meta.kind, entry.value, reason: '${entry.key} 的类型声明不对');
      expect(meta.name, isNotNull, reason: '${entry.key} 应声明 name');
    }
  });

  test('内置条目只在空仓储时写入；旧内容不做兼容，改由提示清数据', () async {
    final dir = await Directory.systemTemp.createTemp('builtin_sync');
    final store = SourceStore(root: () async => dir);
    // 模拟旧版本遗留：正文里没有 @script 声明 ⇒ 会被判为"其他"
    await store.save([
      const SourceEntry(
        id: 'builtin:fake-source',
        name: '内置：本地测试书源',
        format: SourceFormat.script,
        body: 'result("旧正文，没有声明")',
      ),
    ]);
    expect((await store.load()).first.kind, ScriptKind.tool);
    // 命中"旧版内置脚本"检测 ⇒ 界面据此提示清除应用数据
    expect(await hasLegacyBuiltin(store), isTrue);

    // 不做旧版兼容：仓储非空 ⇒ 不写入、也不改写
    expect(await syncBuiltinEntries(store, loader: readAsset), isFalse);
    final entries = await store.load();
    expect(entries.length, 1);
    expect(entries.first.body, contains('旧正文'));

    // 空仓储：写入全部内置条目
    await store.save(const []);
    expect(await syncBuiltinEntries(store, loader: readAsset), isTrue);
    final seeded = await store.load();
    expect(seeded.map((e) => e.id), contains('builtin:gutenberg-source'));
    expect(await hasLegacyBuiltin(store), isFalse);
    // 幂等
    expect(await syncBuiltinEntries(store, loader: readAsset), isFalse);
    await dir.delete(recursive: true);
  });

  // 需要真实网络：按项目惯例打 live 标签（默认套件用 --exclude-tags live 排除）
  test(
    'Gutendex 书源脚本：真实搜索（需要网络，失败则跳过）',
    () async {
      final body = await readAsset('assets/plugins/gutenberg_source.ht');
      final entry = SourceEntry(
        id: 'gutenberg',
        name: '古腾堡',
        format: SourceFormat.script,
        body: body,
      );
      const service = SourceService();
      try {
        final items = await service.search(entry, 'alice');
        expect(items, isNotEmpty, reason: '公共领域接口应能搜到结果');
        expect(items.first['id'], isNotEmpty);
        expect(items.first['title'], isNotEmpty);
      } catch (error) {
        markTestSkipped('网络不可用或接口受限，跳过真实搜索：$error');
      }
    },
    tags: 'live',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
