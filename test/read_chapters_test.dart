import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/models/book.dart';
import 'package:reader/services/library_repository.dart';
import 'package:reader/services/storage.dart';

void main() {
  group('已读章节：模型', () {
    test('标记/切换/查询语义', () {
      final book = Book(id: 'b1', title: '测试');
      expect(book.isChapterRead(3), isFalse);
      expect(book.markChapterRead(3), isTrue, reason: '首次标记应返回"有变化"');
      expect(book.markChapterRead(3), isFalse, reason: '重复标记不应再算变化');
      expect(book.isChapterRead(3), isTrue);
      expect(book.toggleChapterRead(3), isFalse, reason: '已读 → 切换为未读');
      expect(book.isChapterRead(3), isFalse);
      expect(book.toggleChapterRead(3), isTrue, reason: '未读 → 切换为已读');
      expect(book.isChapterRead(3), isTrue);
    });

    test('JSON 往返保留已读集合，且旧数据（无该字段）兼容为空', () {
      final book = Book(id: 'b2', title: '测试')
        ..readChapters.addAll({0, 2, 9});
      final restored = Book.fromJson(book.toJson());
      expect(restored.readChapters, {0, 2, 9});
      expect(restored.isChapterRead(2), isTrue);
      expect(restored.isChapterRead(1), isFalse);

      final legacy = Book.fromJson({'id': 'b3', 'title': '旧书'});
      expect(legacy.readChapters, isEmpty);
    });

    test('落盘时按序输出，便于 diff', () {
      final book = Book(id: 'b4', title: '测试')..readChapters.addAll({9, 1, 5});
      expect(book.toJson()['readChapters'], [1, 5, 9]);
    });
  });

  group('已读章节：仓储落盘', () {
    late Directory tmp;
    late Storage storage;
    late LibraryRepository repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('reader_read_chapters');
      Storage.overrideRoot(tmp);
      storage = await Storage.instance();
      repo = LibraryRepository(storage);
      await repo.load();
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('标记已读会写进 library.json，重新加载后仍在', () async {
      final book = Book(id: 'r1', title: '落盘测试');
      repo.books.add(book);
      await repo.markChapterRead(book, 7);
      expect(await repo.markChapterRead(book, 7), isFalse, reason: '第二次无变化');

      final fresh = LibraryRepository(storage);
      await fresh.load();
      final reloaded = fresh.byId('r1');
      expect(reloaded, isNotNull);
      expect(reloaded!.isChapterRead(7), isTrue, reason: '应随 library.json 持久化');
      expect(reloaded.isChapterRead(8), isFalse);
    });

    test('切换会同时落盘', () async {
      final book = Book(id: 'r2', title: '切换测试');
      repo.books.add(book);
      expect(await repo.toggleChapterRead(book, 1), isTrue);
      expect(await repo.toggleChapterRead(book, 1), isFalse);

      final fresh = LibraryRepository(storage);
      await fresh.load();
      expect(fresh.byId('r2')!.readChapters, isEmpty);
    });
  });
}
