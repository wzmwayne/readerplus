import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/app_log.dart';
import '../services/plugin/builtin_sources.dart';
import '../services/plugin/source_service.dart';
import '../services/plugin/source_store.dart';
import '../services/script/script_runner.dart';
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

  /// 当前搜索的取消令牌：点「取消」即强制停止所有在跑的脚本 isolate。
  ScriptCancelToken? _token;

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
    final token = ScriptCancelToken();
    setState(() {
      _running = true;
      _token = token;
      _results = const [];
      _logs
        ..clear()
        ..add('开始搜索：$query（${picked.length} 个书源）');
    });

    final collected = <({String sourceId, Map<String, String> item})>[];
    for (final entry in picked) {
      if (!mounted || token.cancelled) break;
      _append('── ${entry.name} ──');
      try {
        final items = await _service.search(
          entry,
          query,
          onLog: _append,
          token: token,
        );
        for (final item in items) {
          collected.add((sourceId: entry.id, item: item));
        }
        _append('完成：${items.length} 条');
      } catch (error) {
        if (token.cancelled) {
          _append('已取消');
          break;
        }
        AppLog.error('source', '书源 ${entry.name} 失败：$error');
        _append('失败：$error');
      }
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _token = null;
      _results = collected;
      _logs.add(
        token.cancelled
            ? '已强制停止：保留已完成的 ${collected.length} 条'
            : '全部结束：共 ${collected.length} 条',
      );
    });
  }

  /// 强制停止：杀掉当前正在跑的脚本 isolate，并终结后续书源。
  void _cancel() {
    final token = _token;
    if (token == null) return;
    AppLog.info('source', '用户点击取消：强制停止所有运行中的脚本');
    _append('用户取消：强制停止所有运行中的脚本');
    token.cancelAll();
    setState(() {}); // 立刻刷新按钮状态
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

  /// 点击结果：**直接用搜索带回的字段**展示详情（不再有独立的"取详情"）。
  Future<void> _openDetail(SourceEntry entry, Map<String, String> item) async {
    final id = item['id'] ?? '';
    if (id.isEmpty) return;
    AppLog.info('source', '展示详情（来自搜索结果）：${item['title'] ?? id}');
    await _showDetailSheet(entry, item, id);
  }

  Future<void> _showDetailSheet(
    SourceEntry entry,
    Map<String, String> item,
    String id,
  ) async {
    final title = item['title']?.isNotEmpty == true ? item['title']! : id;
    final author = item['author']?.isNotEmpty == true ? item['author']! : '佚名';
    final cover = item['cover'] ?? '';
    final intro = (item['description']?.isNotEmpty == true
        ? item['description']!
        : (item['intro'] ?? ''));
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _coverImage(
                  cover,
                  data: item['coverData'] ?? '',
                  width: 84,
                  height: 112,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('作者：$author'),
                      Text('书籍 id：$id'),
                      Text('来源：${entry.name}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(intro.isEmpty ? '（无简介）' : intro),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _download(
                        entry,
                        id,
                        title,
                        author: author,
                        cover: cover,
                      );
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

  Future<void> _download(
    SourceEntry entry,
    String id,
    String title, {
    String author = '',
    String cover = '',
  }) async {
    _append('开始下载：$title');
    try {
      final settings = context.read<AppState>().settings;
      final result = await _service.downloadChapters(
        entry,
        id,
        onLog: _append,
        // 0 = 不限制（默认）；可在设置里收紧
        timeout: Duration(seconds: settings.downloadTimeoutSeconds),
        token: _token,
      );
      if (result.chapters.isEmpty) {
        _append('下载失败：脚本未返回章节');
        return;
      }
      // 作者/封面：脚本在下载步骤补充的优先，其次用搜索结果里的
      final finalAuthor = result.author.isNotEmpty
          ? result.author
          : (author.isNotEmpty ? author : '佚名');
      final coverBytes = await _service.fetchCoverBytes(result, onLog: _append) ??
          await _fetchCoverFromUrl(result.coverUrl.isEmpty ? cover : '');
      _append(
        '元数据：作者=$finalAuthor，封面=${coverBytes == null ? '无（用默认）' : '${coverBytes.length} 字节'}',
      );
      final bytes = _service.buildEpub(
        title: title,
        author: finalAuthor,
        chapters: result.chapters,
        cover: coverBytes,
      );
      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/sources_download',
      );
      if (!dir.existsSync()) await dir.create(recursive: true);
      final file = File('${dir.path}/${title.replaceAll(RegExp(r'[/\\]'), '_')}.epub');
      await file.writeAsBytes(bytes, flush: true);
      _append('已生成 EPUB：${file.path}（${bytes.length} 字节）');
      if (!mounted) return;
      final book = await context.read<AppState>().importBook(file);
      _append(book == null ? '入库失败' : '已入库：${book.title}（作者 ${book.author}）');
    } catch (error) {
      AppLog.error('source', '下载失败：$error');
      _append('下载失败：$error');
    }
  }

  /// 搜索结果里的封面地址：下载步骤没给封面时兜底抓取。
  Future<List<int>?> _fetchCoverFromUrl(String url) async {
    if (url.trim().isEmpty) return null;
    try {
      return await _service.fetchCoverBytes(
        DownloadResult(chapters: const [], coverUrl: url),
        onLog: _append,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        actions: [
          if (_running)
            IconButton(
              tooltip: '取消：强制停止所有运行中的脚本',
              icon: const Icon(Icons.stop_circle_outlined),
              color: Theme.of(context).colorScheme.error,
              onPressed: _cancel,
            ),
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
                    subtitle: const Text('按脚本分组：详情已在搜索时带回，点击直接查看'),
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
                          leading: _coverImage(
                            hit.item['cover'] ?? '',
                            data: hit.item['coverData'] ?? '',
                          ),
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
                              _append('该脚本已不可用');
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

  /// 封面：支持 ①coverData(裸 base64) ②cover 为 data: URI ③cover 为图片地址；
  /// 都没有或加载失败时用占位图（保证每条结果都有封面）。
  Widget _coverImage(
    String url, {
    String data = '',
    double width = 44,
    double height = 58,
  }) {
    final placeholder = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.menu_book_outlined,
        size: width * 0.5,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
    // 内联数据优先（coverData 优先于 cover 里的 data URI）
    final inline = SourceService.decodeInlineCover(
      data.trim().isNotEmpty ? data : url,
    );
    if (inline != null && inline.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          Uint8List.fromList(inline),
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => placeholder,
        ),
      );
    }
    if (url.trim().isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        url.trim(),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => placeholder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}
