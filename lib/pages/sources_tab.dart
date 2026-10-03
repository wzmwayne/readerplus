import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/app_log.dart';
import '../services/plugin/source_service.dart';
import '../services/plugin/source_store.dart';
import '../state/app_state.dart';

/// 内置书源（随应用打包，首次进入自动写入仓储）。
///
/// 注意：清洗类脚本（assets/plugins/txt_cleaner.ht）不是书源，不在此列出；
/// 书架的 TXT 导入已由内置的纯 Dart 管线承担。
const _builtinSources = <String, ({String name, SourceFormat format, String asset})>{
  'builtin:fake-source': (
    name: '内置：本地测试书源',
    format: SourceFormat.script,
    asset: 'assets/plugins/fake_source.ht',
  ),
};

/// 书源页：列表 / 导入 / 搜索（实时日志）/ 详情 / 下载入库。
///
/// 全部经 [SourceService] → [PluginExecutor]：一个 isolate 执行器、
/// 一套宿主能力，脚本与规则行为一致，脚本死循环也杀得掉。
class SourcesTab extends StatefulWidget {
  const SourcesTab({super.key, this.store, this.builtinLoader});

  /// 仓储可注入（测试用临时目录；正式运行走应用数据目录）。
  final SourceStore? store;

  /// 内置书源正文加载器（默认读打包资源；测试可注入，避免依赖 asset bundle）。
  final Future<String> Function(String asset)? builtinLoader;

  @override
  State<SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<SourcesTab> {
  late final SourceStore _store = widget.store ?? SourceStore();
  final SourceService _service = const SourceService();
  final TextEditingController _query = TextEditingController();

  List<SourceEntry> _sources = const [];
  final Set<String> _selected = {};
  final List<String> _logs = [];
  List<({String source, Map<String, String> item})> _results = const [];
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
    var entries = await _store.load();
    // 首次运行：把内置示例写入仓储（与 Python 时代的内置脚本等价）
    if (entries.isEmpty) {
      for (final entry in _builtinSources.entries) {
        final body = await (widget.builtinLoader ?? rootBundle.loadString)(
          entry.value.asset,
        );
        entries = await _store.upsert(
          SourceEntry(
            id: entry.key,
            name: entry.value.name,
            format: SourceFormat.script,
            body: body,
            description: '随应用打包的示例书源',
          ),
        );
      }
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

  Future<void> _import() async {
    const group = XTypeGroup(label: '书源脚本或规则', extensions: ['ht', 'json']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null || !mounted) return;
    final body = await File(file.path).readAsString();
    final name = file.name.replaceAll(RegExp(r'\.(ht|json)$'), '');
    final format = file.name.toLowerCase().endsWith('.json')
        ? SourceFormat.rule
        : SourceFormat.script;
    await _store.upsert(
      SourceEntry(
        id: 'user:${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        format: format,
        body: body,
      ),
    );
    AppLog.info('source', '导入书源：$name（${format.name}）');
    await _load();
  }

  Future<void> _remove(SourceEntry entry) async {
    await _store.remove(entry.id);
    await _load();
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

    final collected = <({String source, Map<String, String> item})>[];
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
          collected.add((source: entry.name, item: item));
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
        title: const Text('书源'),
        actions: [
          IconButton(
            tooltip: '导入脚本(.ht)或规则(.json)',
            icon: const Icon(Icons.add),
            onPressed: _running ? null : _import,
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
                  subtitle: const Text('点击可勾选；长按删除'),
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
                      ' · ${entry.capabilities.join('/')}',
                    ),
                    secondary: IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: _running ? null : () => _remove(entry),
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
                  ListTile(dense: true, title: Text('结果（${_results.length}）')),
                  for (final hit in _results)
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
                        final entry = _sources.firstWhere(
                          (e) => e.name == hit.source,
                          orElse: () => _sources.first,
                        );
                        _openDetail(entry, hit.item);
                      },
                    ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
