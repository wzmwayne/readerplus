import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/app_log.dart';
import '../services/plugin/book_source.dart';
import '../services/plugin/plugin_sandbox.dart';
import 'plugin_run_page.dart';

/// 书籍详情页：封面、书名、作者、id、详细内容；底部为下载入口。
class SourceDetailPage extends StatefulWidget {
  const SourceDetailPage({
    super.key,
    required this.script,
    required this.item,
    required this.service,
  });

  final PluginScript script;
  final SourceItem item;
  final BookSourceService service;

  @override
  State<SourceDetailPage> createState() => _SourceDetailPageState();
}

class _SourceDetailPageState extends State<SourceDetailPage> {
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
    AppLog.info('search', '进入下载页：${widget.item.title}（id=${widget.item.id}）');
    await Navigator.of(context).push(
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
    final cover = detail?.coverBytes;
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                height: 170,
                child: cover != null
                    ? Image.memory(
                        Uint8List.fromList(cover),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.book_outlined),
                      )
                    : widget.item.coverUrl.isEmpty
                    ? const Icon(Icons.book_outlined, size: 48)
                    : Image.network(
                        widget.item.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.book_outlined),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('作者：${widget.item.author.isEmpty ? "佚名" : widget.item.author}'),
                    const SizedBox(height: 4),
                    Text('书籍 id：${widget.item.id}'),
                    const SizedBox(height: 4),
                    Text('来源：${widget.script.name}'),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else ...[
            const Text('详细', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              detail?.description.isNotEmpty == true
                  ? detail!.description
                  : (widget.item.intro.isEmpty ? '（脚本未提供详细内容）' : widget.item.intro),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download_outlined),
            label: const Text('下载（进入下载页面，可看脚本输出）'),
          ),
        ),
      ),
    );
  }
}
