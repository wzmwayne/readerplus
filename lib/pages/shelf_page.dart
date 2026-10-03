import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../reader/reader_page.dart';
import '../services/app_log.dart';
import '../services/txt/txt_to_epub.dart';
import '../state/app_state.dart';
import '../widgets/book_cover.dart';

/// 书架：网格 / 列表两种布局，长按书籍弹出操作菜单。
class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  String _keyword = '';

  static const _bookTypeGroup = XTypeGroup(
    label: '电子书',
    extensions: ['txt', 'epub'],
    // 部分文件管理器/网盘给出的 MIME 是 octet-stream，放宽以免选不到文件
    mimeTypes: [
      'text/plain',
      'application/epub+zip',
      'application/octet-stream',
    ],
  );

  Future<void> _importBook() async {
    AppLog.info('shelf', '点击导入书籍');
    final state = context.read<AppState>();
    try {
      final file = await openFile(acceptedTypeGroups: const [_bookTypeGroup]);
      if (file == null) {
        AppLog.info('shelf', '未选择文件（选择器返回空）');
        return;
      }
      final picked = File(file.path);
      AppLog.info('shelf', '选择文件：${picked.path}');
      // TXT：纯 Dart 管线（编码探测 → 规则清洗 → 分章 → EPUB 3 → 入库）
      // EPUB：直接导入
      if (picked.path.toLowerCase().endsWith('.txt')) {
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
        AppLog.info('shelf', 'TXT 已转为 EPUB：${epub.path}（${bytes.length} 字节）');
        final book = await state.importBook(epub);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入：${book?.title ?? name}')),
        );
        return;
      }
      // 其它格式（EPUB 等）交给内置导入器
      final book = await state.importBook(picked);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            book == null ? '导入失败，详见开发者页日志' : '已导入：${book.title}',
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
            onPressed: _importBook,
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
        const Text('支持 TXT（UTF-8 / GBK）与 EPUB 2 / 3', style: TextStyle(fontSize: 11, color: Colors.black38)),
        const SizedBox(height: 4),
        Text(
          '点击右上角 + 导入本地 TXT / EPUB 文件',
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
