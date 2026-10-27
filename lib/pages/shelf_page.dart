import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/book.dart';
import '../reader/reader_page.dart';
import '../services/app_log.dart';
import '../services/txt/txt_to_epub.dart';
import '../services/plugin/source_store.dart';
import '../state/app_state.dart';
import '../widgets/book_cover.dart';

/// 书架：网格 / 列表两种布局，长按书籍弹出操作菜单。
class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  /// 当前语言文案（跟随设置里的语言选项）
  L10n get l => L10n.of(context.read<AppState>().settings);

  String _keyword = '';

  static const _bookTypeGroup = XTypeGroup(
    label: '电子书',
    extensions: ['ezbk', 'txt', 'epub'],
    // 严格只放行这两种：不加 application/octet-stream，
    // 否则 Android 选择器会放行一切文件（连 .ht 脚本都能选）
    mimeTypes: ['text/plain', 'application/epub+zip'],
  );

  /// 书架只接受 txt / epub；其它后缀（例如误选的 .ht 脚本）明确拒绝并提示。
  static bool _isBookFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.ezbk') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.epub');
  }

  /// 导入入口：先选格式（ezbk / epub / txt），再选文件。
  Future<void> _pickImportKind() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择导入格式', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.auto_stories_outlined),
              title: const Text('EZBK（简单电子书）'),
              subtitle: const Text('直接导入，不转换'),
              onTap: () => Navigator.pop(ctx, 'ezbk'),
            ),
            ListTile(
              leading: const Icon(Icons.import_contacts_outlined),
              title: const Text('EPUB'),
              subtitle: const Text('导入后转换为 EZBK 存储'),
              onTap: () => Navigator.pop(ctx, 'epub'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('TXT'),
              subtitle: const Text('导入后转换为 EZBK 存储'),
              onTap: () => Navigator.pop(ctx, 'txt'),
            ),
            ListTile(
              leading: const Icon(Icons.code_outlined),
              title: const Text('用脚本导入'),
              subtitle: const Text('脚本接管：接收文件二进制，返回 EZBK 文本'),
              onTap: () => Navigator.pop(ctx, 'script'),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    await _importBook(onlyKind: kind);
  }

  /// 脚本接管导入：选脚本 → 选文件 → 脚本返回 EZBK 文本 → 建书。
  Future<void> _importWithScript(AppState state) async {
    final scripts = await SourceStore().load();
    if (!mounted) return;
    if (scripts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有可用脚本，请先在「插件」页导入 .js')),
      );
      return;
    }
    final picked = await showModalBottomSheet<SourceEntry>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择导入脚本',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final script in scripts)
              ListTile(
                title: Text(script.name),
                subtitle: Text(script.kind.label),
                onTap: () => Navigator.pop(ctx, script),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    const anyType = XTypeGroup(label: '任意文件', mimeTypes: ['*/*']);
    final file = await openFile(acceptedTypeGroups: const [anyType]);
    if (file == null || !mounted) return;
    final book = await state.importBookWithScript(
      File(file.path),
      picked.body,
      fallbackTitle: picked.name,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(book == null ? '脚本导入失败' : '已导入《${book.title}》'),
      ),
    );
  }

  Future<void> _importBook({String? onlyKind}) async {
    AppLog.info('shelf', '点击导入书籍${onlyKind == null ? '' : '（$onlyKind）'}');
    final state = context.read<AppState>();
    if (onlyKind == 'script') {
      await _importWithScript(state);
      return;
    }
    try {
      final group = switch (onlyKind) {
        'ezbk' => XTypeGroup(
            label: 'EZBK',
            extensions: ['ezbk'],
            mimeTypes: ['text/plain', 'application/octet-stream'],
          ),
        'epub' => XTypeGroup(
            label: 'EPUB',
            extensions: ['epub'],
            mimeTypes: ['application/epub+zip'],
          ),
        'txt' => XTypeGroup(
            label: 'TXT',
            extensions: ['txt'],
            mimeTypes: ['text/plain'],
          ),
        _ => _bookTypeGroup,
      };
      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null) {
        AppLog.info('shelf', '未选择文件（选择器返回空）');
        return;
      }
      final picked = File(file.path);
      AppLog.info('shelf', '选择文件：${picked.path}');
      if (!_isBookFile(picked.path)) {
        AppLog.info('shelf', '拒绝导入：书架只接受 txt/epub（脚本请在「插件」页导入）');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('书架只支持 txt / epub；脚本或规则请在「插件」页导入'),
            ),
          );
        }
        return;
      }
      // TXT：纯 Dart 管线（编码探测 → 规则清洗 → 分章 → EPUB 3 → 入库）
      // EPUB：直接导入
      final lower = picked.path.toLowerCase();
      if (lower.endsWith('.ezbk')) {
        final book = await state.importBook(picked);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              book == null ? l.shelfImportFailed : l.shelfImported(book.title),
            ),
          ),
        );
        return;
      }
      if (lower.endsWith('.txt')) {
        final bytes = await TxtToEpub.fromFile(
          picked,
          // 只做规范化（去零宽/BOM），不删正文内容
          rules: const [
            [r'[\u200b\ufeff]', ''],
          ],
        );
        final dir = Directory(
          '${(await getTemporaryDirectory()).path}/txt_import',
        );
        if (!dir.existsSync()) await dir.create(recursive: true);
        final name = picked.uri.pathSegments.last.replaceAll(
          RegExp(r'\.txt$', caseSensitive: false),
          '',
        );
        final epub = File('${dir.path}/$name.epub');
        await epub.writeAsBytes(bytes, flush: true);
        AppLog.info('shelf', l.shelfTxtDone(bytes.length));
        final book = await state.importBook(epub);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.shelfImported(book?.title ?? name))),
        );
        return;
      }
      // 其它格式（EPUB 等）交给内置导入器
      final book = await state.importBook(picked);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            book == null ? l.shelfImportFailed : l.shelfImported(book.title),
          ),
        ),
      );
    } catch (e) {
      AppLog.error('shelf', '导入失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  List<Book> _filtered(AppState state) {
    final books = state.books;
    if (_keyword.trim().isEmpty) return books;
    final kw = _keyword.trim().toLowerCase();
    return books
        .where((b) =>
            b.title.toLowerCase().contains(kw) || b.author.toLowerCase().contains(kw))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final books = _filtered(state);
    final settings = state.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(
            tooltip: '导入本地书籍（TXT / EPUB）',
            icon: const Icon(Icons.add),
            onPressed: _pickImportKind,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: '搜索书名或作者',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onChanged: (v) => setState(() => _keyword = v),
            ),
          ),
        ),
      ),
      body: books.isEmpty
          ? _emptyHint()
          : (settings.gridLayout
                ? _grid(books, MediaQuery.orientationOf(context) == Orientation.landscape
                    ? settings.gridColumnsLandscape
                    : settings.gridColumnsPortrait)
                : _list(books)),
    );
  }

  Widget _emptyHint() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.menu_book_outlined, size: 64, color: Colors.black26),
        const SizedBox(height: 12),
        const Text('书架还是空的'),
        const SizedBox(height: 2),
        Text(l.shelfFormatsHint, style: const TextStyle(fontSize: 11, color: Colors.black38)),
        const SizedBox(height: 4),
        Text(
          l.shelfEmptyHint,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _grid(List<Book> books, int columns) => GridView.builder(
    padding: const EdgeInsets.all(12),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      childAspectRatio: 0.62,
      crossAxisSpacing: 12,
      mainAxisSpacing: 16,
    ),
    itemCount: books.length,
    itemBuilder: (context, i) {
      final book = books[i];
      return GestureDetector(
        onTap: () => _open(book),
        onLongPress: () => _showActions(book),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: LayoutBuilder(
              builder: (context, c) => BookCover(book: book, width: c.maxWidth, height: c.maxHeight),
            )),
            const SizedBox(height: 6),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            Text(
              book.author.isEmpty ? '未知作者' : book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    },
  );

  Widget _list(List<Book> books) => ListView.separated(
    itemCount: books.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, i) {
      final book = books[i];
      return ListTile(
        onTap: () => _open(book),
        onLongPress: () => _showActions(book),
        leading: BookCover(book: book, width: 44, height: 60, borderRadius: 4),
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${book.author.isEmpty ? '未知作者' : book.author} · ${book.chapterCount} 章',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text('${(book.progress * 100).toStringAsFixed(0)}%'),
      );
    },
  );

  Future<void> _open(Book book) async {
    AppLog.info('shelf', '打开书籍：${book.title}（id=${book.id}）');
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderPage(book: book)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showActions(Book book) async {
    final state = context.read<AppState>();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${book.charCount} 字 · ${book.chapterCount} 章'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('开始阅读'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _open(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除书籍'),
                    content: Text('确定删除《${book.title}》及其正文吗？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
                    ],
                  ),
                );
                if (ok == true) await state.removeBook(book);
              },
            ),
          ],
        ),
      ),
    );
  }
}
