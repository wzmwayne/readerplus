import 'package:flutter/services.dart' show rootBundle;

import 'source_store.dart';

/// 内置脚本/规则条目（随应用打包）。
///
/// 内置条目**随应用版本自动同步**：仓储里若存在同名内置 id，但正文与本次打包的
/// 内容不同，则用打包内容覆盖（保留启用状态与用户改过的名称）。
/// 这样升级应用后，内置脚本的声明/修复会立即生效，不会一直沿用旧正文。
const builtinEntries = <String, ({String name, SourceFormat format, String asset})>{
  'builtin:fake-source': (
    name: '内置：本地测试书源',
    format: SourceFormat.script,
    asset: 'assets/plugins/fake_source.ht',
  ),
  'builtin:gutenberg-source': (
    name: '内置：古腾堡（公共领域示例）',
    format: SourceFormat.script,
    asset: 'assets/plugins/gutenberg_source.ht',
  ),
  'builtin:txt-cleaner': (
    name: '内置：TXT 清洗转 EPUB',
    format: SourceFormat.script,
    asset: 'assets/plugins/txt_cleaner.ht',
  ),
};

/// 写入内置条目（**仅在仓储为空时**）。返回是否发生写入。
///
/// 设计取舍：**不做旧版兼容**。仓储里若已有内容就原样保留 ——
/// 按约定，遇到不兼容请**清除应用数据**后重新进入。
Future<bool> syncBuiltinEntries(
  SourceStore store, {
  Future<String> Function(String asset)? loader,
}) async {
  final read = loader ?? rootBundle.loadString;
  final existing = await store.load();
  if (existing.isNotEmpty) return false;
  final entries = <SourceEntry>[];
  for (final entry in builtinEntries.entries) {
    entries.add(
      SourceEntry(
        id: entry.key,
        name: entry.value.name,
        format: entry.value.format,
        body: await read(entry.value.asset),
        description: '随应用打包的内置示例',
      ),
    );
  }
  await store.save(entries);
  return true;
}

/// 是否存在"旧版内置脚本"（正文缺少 `@script` 声明）⇒ 提示用户清除应用数据。
Future<bool> hasLegacyBuiltin(SourceStore store) async {
  final entries = await store.load();
  for (final entry in entries) {
    if (!builtinEntries.containsKey(entry.id)) continue;
    if (entry.format != SourceFormat.script) continue;
    if (!entry.body.contains('@script')) return true;
  }
  return false;
}
