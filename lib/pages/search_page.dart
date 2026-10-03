import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/app_log.dart';
import '../services/plugin/source_service.dart';
import '../services/plugin/builtin_sources.dart';
import '../services/plugin/source_store.dart';
import 'scripts_page.dart';
import '../state/app_state.dart';

/// 内置书源（随应用打包，首次进入自动写入仓储）。
///
/// 注意：清洗类脚本（assets/plugins/txt_cleaner.ht）不是书源，不在此列出；
/// 书架的 TXT 导入已由内置的纯 Dart 管线承担。
/// 搜索页：选书源 → 搜索（实时日志）→ 结果 → 详情 → 下载入库。
///
/// 书源（含脚本与规则）的**管理**在「脚本」标签页；这里只负责搜与用。
///
/// 全部经 [SourceService] → [PluginExecutor]：一个 isolate 执行器、
/// 一套宿主能力，脚本与规则行为一致，脚本死循环也杀得掉。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.store, this.builtinLoader});

  /// 仓储可注入（测试用临时目录；正式运行走应用数据目录）。
  final SourceStore? store;

  /// 内置书源正文加载器（默认读打包资源；测试可注入，避免依赖 asset bundle）。
  final Future<String> Function(String asset)? builtinLoader;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final SourceStore _store = widget.store ?? SourceStore();
  final SourceService _service = const SourceService();
  final TextEditingController _query = TextEditingController();

  List<SourceEntry> _sources = const [];
  final Set<String> _selected = {};
  final List<String> _logs = [];
  List<({String sourceId, Map<String, String> item})> _results = const [];
  bool _loading = true;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (await hasLegacyBuiltin(_store)) {
      AppLog.info('source', '检测到旧版内置脚本：请清除应用数据后重新进入（不做旧版兼容）');
    }
    final changed = await syncBuiltinEntries(
      _store,
      loader: widget.builtinLoader,
    );
    final entries = await _store.load();
    if (changed) {
      AppLog.info('source', '已写入 ${entries.length} 条内置条目');
    }
    if (!mounted) return;
    final onlySources = entries.where((e) => e.isSource).toList();
    setState(() {
      _sources = onlySources;
      _loading = false;
      _selected
        ..clear()
        ..addAll(onlySources.where((e) => e.enabled).map((e) => e.id));
    });
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty || _running) return;
    final picked = _sources.where((e) => _selected.contains(e.id)).toList();
    setState(() {
      _running = true;
      _results = const [];
      _logs
        ..clear()
        ..add('开始搜索：$query（${picked.length} 个书源）');
    });

    final collected = <({String sourceId, Map<String, String> item})>[];
    for (final entry in picked) {
      if (!mounted) return;
      _append('── ${entry.name} ──');
      try {
        final items = await _service.search(
          entry,
          query,
          onLog: _append,
        );
        for (final item in items) {
          collected.add((sourceId: entry.id, item: item));
        }
        _append('完成：${items.length} 条');
      } catch (error) {
        AppLog.error('source', '书源 ${entry.name} 失败：$error');
        _append('失败：$error');
      }
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _results = collected;
      _logs.add('全部结束：共 ${collected.length} 条');
    });
  }

  /// 按脚本分组（保持书源列表顺序，便于对照）。
  List<
    ({
      String id,
      String name,
      List<({String sourceId, Map<String, String> item})> items,
    })
  >
  _grouped() {
    final groups =
        <
          ({
            String id,
            String name,
            List<({String sourceId, Map<String, String> item})> items,
          })
        >[];
    for (final entry in _sources) {
      final items = _results.where((hit) => hit.sourceId == entry.id).toList();
      if (items.isEmpty) continue;
      groups.add((id: entry.id, name: entry.name, items: items));
    }
    return groups;
  }

  void _append(String message) {
    if (!mounted) return;
    setState(() => _logs.add(message));
  }

  Future<void> _openDetail(SourceEntry entry, Map<String, String> item) async {
    final id = item['id'] ?? '';
    if (id.isEmpty) return;
    setState(() => _logs.add('取详情：${item['title'] ?? id}'));
    try {
      final detail = await _service.detail(entry, id, onLog: _append);
      if (!mounted) return;
      await _showDetailSheet(entry, item, detail, id);
    } catch (error) {
      _append('详情失败：$error');
    }
  }

  Future<void> _showDetailSheet(
    SourceEntry entry,
    Map<String, String> item,
    Map<String, String> detail,
    String id,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail['title']?.isNotEmpty == true
                  ? detail['title']!
                  : (item['title'] ?? id),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text('作者：${detail['author'] ?? item['author'] ?? '佚名'}'),
            Text('书籍 id：$id'),
            Text('来源：${entry.name}'),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final intro = detail['description'] ?? item['intro'] ?? '';
                return Text(intro.isEmpty ? '（无简介）' : intro);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _download(entry, id, detail['title'] ?? item['title'] ?? id);
                    },
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('下载并入库'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(SourceEntry entry, String id, String title) async {
    _append('开始下载：$title');
    try {
      final chapters = await _service.downloadChapters(
        entry,
        id,
        onLog: _append,
      );
      if (chapters.isEmpty) {
        _append('下载失败：脚本未返回章节');
        return;
      }
      final bytes = _service.buildEpub(
        title: title,
        author: '佚名',
        chapters: chapters,
      );
      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/sources_download',
      );
      if (!dir.existsSync()) await dir.create(recursive: true);
      final file = File('${dir.path}/${title.replaceAll(RegExp(r'[/\\]'), '_')}.epub');
      await file.writeAsBytes(bytes, flush: true);
      _append('已生成 EPUB：${file.path}（${bytes.length} 字节）');
      if (!mounted) return;
      await context.read<AppState>().importBook(file);
      _append('已入库：$title');
    } catch (error) {
      AppLog.error('source', '下载失败：$error');
      _append('下载失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        actions: [
          IconButton(
            tooltip: '管理脚本与书源',
            icon: const Icon(Icons.extension_outlined),
            onPressed: _running
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScriptsPage(store: widget.store),
                    ),
                  ),
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _running ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      labelText: '搜索书名或作者',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _running ? null : _search,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  dense: true,
                  title: Text('书源（已选 ${_selected.length}/${_sources.length}）'),
                  subtitle: const Text('勾选参与搜索的书源；管理请点右上角'),
                ),
                for (final entry in _sources)
                  CheckboxListTile(
                    value: _selected.contains(entry.id),
                    onChanged: _running
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _selected.add(entry.id);
                            } else {
                              _selected.remove(entry.id);
                            }
                          }),
                    title: Text(entry.name),
                    subtitle: Text(
                      '${entry.format == SourceFormat.script ? '脚本' : '规则'}'
                      ' · ${entry.kind.label}'
                      ' · ${entry.kind.label}',
                    ),

                  ),
                if (_logs.isNotEmpty) ...[
                  const Divider(),
                  const ListTile(dense: true, title: Text('执行过程（实时）')),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101418),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        _logs.join('\n'),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFFD7E2EA),
                        ),
                      ),
                    ),
                  ),
                ],
                if (_running)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_results.isNotEmpty) ...[
                  const Divider(),
                  ListTile(
                    dense: true,
                    title: Text('结果（${_results.length}）'),
                    subtitle: const Text('按脚本分组：每条结果都用搜出它的脚本取详情与下载'),
                  ),
                  for (final group in _grouped())
                    ...[
                      ListTile(
                        dense: true,
                        tileColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        leading: const Icon(Icons.extension_outlined, size: 18),
                        title: Text('${group.name}（${group.items.length} 条）'),
                      ),
                      for (final hit in group.items)
                        ListTile(
                          title: Text(hit.item['title'] ?? ''),
                          subtitle: Text(
                            '${hit.item['author'] ?? ''} · id: ${hit.item['id'] ?? ''}\n${hit.item['intro'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            final matches = _sources.where(
                              (e) => e.id == hit.sourceId,
                            );
                            if (matches.isEmpty) {
                              _append('该脚本已不可用，无法取详情');
                              return;
                            }
                            _openDetail(matches.first, hit.item);
                          },
                        ),
                    ],
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
