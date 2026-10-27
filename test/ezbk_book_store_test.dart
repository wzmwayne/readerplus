import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/ezbk/ezbk_document.dart';
import 'package:reader/services/ezbk_book_store.dart';

void main() {
  test('由章节构造 EZBK 再解析：标题级别与正文行不丢', () {
    const content = '第一段\n# 看起来像标题\n@ 看起来像命令\n---\n结尾';
    final doc = EzbkBookStore.fromChapters(
      title: '测试书',
      author: '作者',
      content: content,
      chapters: const [
        // 整篇一章，模拟 TXT 导入
      ],
    );
    expect(doc.meta['title'], '测试书');
    final again = EzbkCodec.parse(EzbkCodec.serialize(doc));
    final appended = again.blocks.length;
    expect(appended, greaterThan(0));
    // 控制行被转义，不会变成标题/命令/换页
    expect(again.headings, isEmpty);
    // 只应有 @meta（书名/作者），正文里的 @ 行已被转义
    expect(again.commands.where((c) => c.name != 'meta'), isEmpty);
    final plain = again.toPlainText();
    expect(plain.contains('# 看起来像标题'), isTrue);
    expect(plain.contains('@ 看起来像命令'), isTrue);
    expect(plain.contains('---'), isTrue);
  });

  test('纯文本推导：无标题时整篇一章', () {
    final doc = EzbkCodec.parse('正文甲\n正文乙');
    final derived = EzbkBookStore.derivePlainText(doc);
    expect(derived.chapters.length, 1);
    expect(derived.chapters.first.title, '正文');
    expect(derived.text.contains('正文甲'), isTrue);
  });

  test('纯文本推导：标题开章，正文不含标题行', () {
    final doc = EzbkCodec.parse('# 一\n甲\n# 二\n乙');
    final derived = EzbkBookStore.derivePlainText(doc);
    expect(derived.chapters.length, 2);
    expect(derived.chapters[0].title, '一');
    expect(derived.text.contains('# '), isFalse);
    expect(derived.text.contains('甲'), isTrue);
  });

  test('写入与读回：book.ezbk 正本 + 派生文件', () async {
    final dir = await Directory.systemTemp.createTemp('ezbk_store_test');
    final store = EzbkBookStore(root: () async => dir);
    final doc = EzbkCodec.parse('# 章一\n正文\n---\n# 章二\n更多');
    final chapters = await store.save('b1', doc);
    expect(chapters.length, 2);
    expect(File('${dir.path}/books/b1/book.ezbk').existsSync(), isTrue);
    expect(File('${dir.path}/books/b1/content.txt').existsSync(), isTrue);
    expect(File('${dir.path}/books/b1/chapters.json').existsSync(), isTrue);
    final back = await store.read('b1');
    expect(back, isNotNull);
    expect(back!.headings.length, 2);
    await dir.delete(recursive: true);
  });
}