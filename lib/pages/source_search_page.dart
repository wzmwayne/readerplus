import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/plugin/book_source.dart';
import '../services/plugin/plugin_sandbox.dart';
import '../state/app_state.dart';
import 'plugin_run_page.dart';

/// 在线搜索：调用「书源脚本」搜索 → 看详情（含封面）→ 下载入库。
class SourceSearchPage extends StatefulWidget {
  const SourceSearchPage({super.key, required this.script});

  final PluginScript script;

  @override
  State<SourceSearchPage> createState() => _SourceSearchPageState();
}

class _SourceSearchPageState extends State<SourceSearchPage> {
  final TextEditingController _query = TextEditingController();
  List<SourceItem> _items = [];
  bool _searching = false;
  String? _error;
  int _page = 1;

  BookSourceService get _service {
    final state = context.read<AppState>();
    return BookSourceService(
      runner: state.pluginRunner,
      jobsRoot: () async =>
          Directory('${(await getTemporaryDirectory()).path}/plugin_jobs'),
      auditEnabled: () => state.settings.scriptSandboxAudit,
    );
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search({int page = 1}) async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      if (page == 1) _items = [];
    });
    try {
      final items = await _service.search(
        script: widget.script,
        query: query,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _items = page == 1 ? items : [..._items, ...items];
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openDetail(SourceItem item) async {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _DetailSheet(
        script: widget.script,
        item: item,
        service: _service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            hintText: '搜索书名或作者',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: _searching ? null : () => _search(),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.cloud_outlined, size: 18),
            title: Text('书源：${widget.script.name}'),
            subtitle: Text(
              widget.script.capabilities.isEmpty
                  ? '未声明能力（可在插件页重新导入以读取声明）'
                  : '能力：${widget.script.capabilities.join(" / ")}',
            ),
          ),
          const Divider(height: 1),
          if (_searching && _items.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_searching && _items.isEmpty && _error == null)
            const Expanded(
              child: Center(child: Text('输入关键词开始搜索')),
            ),
          if (_items.isNotEmpty)
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return ListTile(
                    leading: SizedBox(
                      width: 40,
                      height: 56,
                      child: _Cover(url: item.coverUrl),
                    ),
                    title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [item.author, item.intro]
                          .where((text) => text.isNotEmpty)
                          .join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openDetail(item),
                  );
                },
              ),
            ),
          if (_items.length >= 10 || _page > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextButton.icon(
                onPressed: _searching ? null : () => _search(page: _page + 1),
                icon: const Icon(Icons.expand_more, size: 18),
                label: const Text('加载下一页'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, this.bytes});

  final String url;
  final List<int>? bytes;

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return Image.memory(
        Uint8List.fromList(bytes!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.book_outlined),
      );
    }
    if (url.isEmpty) return const Icon(Icons.book_outlined);
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const Icon(Icons.book_outlined),
    );
  }
}

class _DetailSheet extends StatefulWidget {
  const _DetailSheet({
    required this.script,
    required this.item,
    required this.service,
  });

  final PluginScript script;
  final SourceItem item;
  final BookSourceService service;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  SourceDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.service.detail(
        script: widget.script,
        bookId: widget.item.id,
      );
      if (mounted) setState(() => _detail = detail);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => PluginRunPage(
          script: widget.script,
          extraParams: {
            'task': 'download',
            'book_id': widget.item.id,
            'output_file': 'book.epub',
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 100,
                child: _Cover(
                  url: widget.item.coverUrl,
                  bytes: detail?.coverBytes,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.item.author.isEmpty ? '佚名' : widget.item.author,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'id: ${widget.item.id}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else
            Text(
              detail?.description.isNotEmpty == true
                  ? detail!.description
                  : (widget.item.intro.isEmpty ? '（脚本未提供简介）' : widget.item.intro),
              style: const TextStyle(fontSize: 13),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _download,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('下载并入库'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
