import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/plugin/book_source.dart';
import '../services/plugin/plugin_runner.dart';
import '../services/plugin/plugin_sandbox.dart';
import '../services/app_log.dart';
import '../state/app_state.dart';
import 'source_detail_page.dart';

/// 在线搜索标签页：选书源（可多选）→ 依次执行并分别实时输出 → 全部成功后展示结果。
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final TextEditingController _query = TextEditingController();
  List<PluginScript> _sources = [];
  final Set<String> _selected = {};
  final Map<String, String> _logs = {};
  final Map<String, String?> _errors = {};
  final Map<String, List<SourceItem>> _hits = {};
  List<SourcedItem> _merged = [];
  bool _running = false;
  bool _showResults = false;
  PluginRunner? _current;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSources());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  BookSourceService _service(PluginRunner runner) {
    final state = context.read<AppState>();
    return BookSourceService(
      runner: runner,
      jobsRoot: () async =>
          Directory('${(await getTemporaryDirectory()).path}/plugin_jobs'),
      auditEnabled: () => state.settings.scriptSandboxAudit,
    );
  }

  Future<void> _loadSources() async {
    if (!mounted) return;
    final scripts = await context.read<AppState>().plugins.load();
    if (!mounted) return;
    final usable = scripts.where(canSearch).toList();
    AppLog.info('search', '可用书源 ${usable.length} 个：${usable.map((s) => s.name).join('、')}');
    setState(() {
      _sources = usable;
      _selected.removeWhere((id) => !usable.any((s) => s.id == id));
      if (_selected.isEmpty) {
        _selected.addAll(usable.map((s) => s.id));
      }
    });
  }

  /// 依次执行选中的书源；每个书源各自一个运行器，日志分别实时显示。
  ///
  /// 内置的 Python 运行时是单个解释器进程，因此无法真正并行；
  /// 逐个执行既避免互相污染，也能让每个书源的过程独立可见。
  Future<void> _start() async {
    final query = _query.text.trim();
    if (query.isEmpty || _selected.isEmpty || _running) return;
    final picked = _sources.where((s) => _selected.contains(s.id)).toList();
    AppLog.info(
      'search',
      '开始搜索：关键词="$query" 书源=${picked.map((s) => s.name).join('、')}',
    );
    setState(() {
      _running = true;
      _showResults = false;
      _merged = [];
      _logs
        ..clear()
        ..addEntries(picked.map((s) => MapEntry(s.id, '等待执行…\n')));
      _errors
        ..clear()
        ..addEntries(picked.map((s) => MapEntry(s.id, null)));
      _hits.clear();
    });

    for (final script in picked) {
      if (!mounted) return;
      final runner = PluginRunner();
      _current = runner;
      final subscription = runner.logs.listen((chunk) {
        if (!mounted) return;
        setState(() => _logs[script.id] = (_logs[script.id] ?? '') + chunk);
      });
      try {
        final items = await _service(runner).search(
          script: script,
          query: query,
        );
        _hits[script.id] = items;
        if (mounted) {
          setState(() => _logs[script.id] = '${_logs[script.id]}完成：${items.length} 条\n');
        }
      } catch (error, stack) {
        AppLog.error('search', '书源 ${script.name} 执行异常：$error', stack);
        if (mounted) setState(() => _errors[script.id] = '$error');
      } finally {
        await subscription.cancel();
        await runner.dispose();
        _current = null;
      }
    }

    if (!mounted) return;
    AppLog.info(
      'search',
      '全部结束：成功=${_errors.values.where((e) => e == null).length}/${picked.length}'
      '${_errors.entries.where((e) => e.value != null).map((e) => ' 失败[${e.key}]=${e.value}').join()}',
    );
    final allOk = allSourcesOk(_errors);
    setState(() {
      _running = false;
      if (allOk) {
        _merged = mergeSourceResults({
          for (final script in picked)
            script.id: (name: script.name, items: _hits[script.id] ?? const []),
        });
        _showResults = true;
      }
    });
  }

  void _cancel() {
    _current?.cancel();
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线搜索'),
        actions: [
          if (_showResults)
            TextButton(
              onPressed: () => setState(() => _showResults = false),
              child: const Text('重新搜索'),
            ),
          IconButton(
            tooltip: '刷新书源列表',
            icon: const Icon(Icons.refresh),
            onPressed: _running ? null : _loadSources,
          ),
        ],
      ),
      body: _showResults ? _buildResults() : _buildSetup(),
    );
  }

  Widget _buildSetup() {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _start(),
            decoration: InputDecoration(
              labelText: '书名或作者',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _running ? null : _start,
              ),
            ),
          ),
        ),
        ListTile(
          dense: true,
          title: const Text('选择书源（可多选）'),
          subtitle: Text('共 ${_sources.length} 个可用书源，已选 ${_selected.length} 个'),
        ),
        if (_sources.isEmpty)
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('还没有可用的书源'),
            subtitle: Text('到「设置 → 脚本插件 → 内置示例」导入本地测试书源，或用「导入 .py」添加'),
          ),
        for (final script in _sources)
          CheckboxListTile(
            value: _selected.contains(script.id),
            onChanged: _running
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _selected.add(script.id);
                    } else {
                      _selected.remove(script.id);
                    }
                  }),
            title: Text(script.name),
            subtitle: Text(
              script.capabilities.isEmpty
                  ? '未声明能力（按可搜索处理）'
                  : script.capabilities.join(' / '),
            ),
          ),
        if (_sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_running || _selected.isEmpty) ? null : _start,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(_running ? '执行中…' : '开始搜索'),
                  ),
                ),
                const SizedBox(width: 12),
                if (_running)
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('取消'),
                  ),
              ],
            ),
          ),
        if (_logs.isNotEmpty) ...[
          const Divider(height: 24),
          const ListTile(dense: true, title: Text('执行过程（各书源独立输出）')),
          for (final script in _sources.where((s) => _logs.containsKey(s.id)))
            _logPanel(script),
        ],
        if (_errors.values.any((error) => error != null))
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '有书源执行失败，修正后重试；全部成功才会展示汇总结果',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _logPanel(PluginScript script) {
    final error = _errors[script.id];
    final log = _logs[script.id] ?? '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  error == null
                      ? (_running ? Icons.hourglass_top : Icons.check_circle_outline)
                      : Icons.error_outline,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    script.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (error != null)
                  TextButton(
                    onPressed: _running ? null : _start,
                    child: const Text('重试'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF101418),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  error == null ? log : '$log\n$error',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFFD7E2EA),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_merged.isEmpty) {
      return const Center(child: Text('没有搜索到结果'));
    }
    return ListView.separated(
      itemCount: _merged.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final hit = _merged[index];
        return ListTile(
          leading: SizedBox(
            width: 44,
            height: 62,
            child: hit.item.coverUrl.isEmpty
                ? const Icon(Icons.book_outlined)
                : Image.network(
                    hit.item.coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.book_outlined),
                  ),
          ),
          title: Text(hit.item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  if (hit.item.author.isNotEmpty) hit.item.author,
                  'id: ${hit.item.id}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12),
              ),
              if (hit.item.intro.isNotEmpty)
                Text(
                  hit.item.intro,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              Text(
                '来源：${hit.sourceName}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          isThreeLine: true,
          onTap: () {
            // 书源可能已被删除：找不到就给出提示而不是抛异常
            final matches = _sources.where((s) => s.id == hit.sourceId);
            if (matches.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('书源已不可用：${hit.sourceName}')),
              );
              return;
            }
            final script = matches.first;
            final runner = PluginRunner();
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (_) => SourceDetailPage(
                      script: script,
                      item: hit.item,
                      service: _service(runner),
                    ),
                  ),
                )
                .whenComplete(() async => runner.dispose());
          },
        );
      },
    );
  }
}
