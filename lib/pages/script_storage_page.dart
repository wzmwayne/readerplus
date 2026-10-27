import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/script/script_storage.dart';

/// 脚本永久存储的查看 / 编辑 / 清除。
///
/// 规则（docs/script-storage-api.md §6）：
/// - 先尝试 UTF-8 解码：成功则按纯文本显示并可编辑保存；
/// - 解码失败显示 `(raw)`，只提供只读十六进制预览，避免误改二进制。
class ScriptStoragePage extends StatefulWidget {
  const ScriptStoragePage({super.key, required this.scriptId, required this.title});

  final String scriptId;
  final String title;

  @override
  State<ScriptStoragePage> createState() => _ScriptStoragePageState();
}

class _ScriptStoragePageState extends State<ScriptStoragePage> {
  ScriptStorage? _storage;
  List<String> _keys = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final storage = await ScriptStorage.open(widget.scriptId);
    final keys = storage.perm.keys();
    if (!mounted) return;
    setState(() {
      _storage = storage;
      _keys = keys;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('存储 · ${widget.title}'),
        actions: [
          IconButton(
            tooltip: '清空全部',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _keys.isEmpty ? null : _clearAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _keys.isEmpty
          ? const Center(child: Text('暂无永久存储'))
          : ListView.separated(
              itemCount: _keys.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final key = _keys[index];
                final bytes = _storage!.perm.readRaw(key);
                final text = _tryDecode(bytes);
                return ListTile(
                  title: Text(key),
                  subtitle: Text(
                    '${bytes?.length ?? 0} 字节 · ${text == null ? '(raw)' : '文本'}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(key),
                  ),
                  onTap: () => _open(key, bytes, text),
                );
              },
            ),
    );
  }

  static String? _tryDecode(List<int>? bytes) {
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _open(String key, List<int>? bytes, String? text) async {
    final raw = bytes ?? const <int>[];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(key),
        content: SizedBox(
          width: 520,
          child: text != null
              ? _TextEditor(
                  initial: text,
                  onSave: (value) async {
                    _storage!.perm.writeUtf8(key, value);
                    await _reload();
                  },
                )
              : _RawViewer(bytes: raw),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _delete(String key) async {
    _storage!.perm.remove(key);
    await _reload();
  }

  Future<void> _clearAll() async {
    _storage!.perm.clear();
    await _reload();
  }
}

class _TextEditor extends StatefulWidget {
  const _TextEditor({required this.initial, required this.onSave});

  final String initial;
  final Future<void> Function(String value) onSave;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          maxLines: 12,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () async {
              await widget.onSave(_controller.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ),
      ],
    );
  }
}

class _RawViewer extends StatelessWidget {
  const _RawViewer({required this.bytes});

  final List<int> bytes;

  @override
  Widget build(BuildContext context) {
    final preview = bytes.take(512).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('(raw) 非 UTF-8 内容，只读'),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: SingleChildScrollView(
            child: SelectableText(
              preview,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        if (bytes.length > 512) Text('（仅显示前 512 字节，共 ${bytes.length} 字节）'),
      ],
    );
  }
}