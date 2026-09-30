import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub_importer.dart';

/// 构造一个最小可用的 EPUB 包（内存中生成 zip）。
List<int> buildEpub({
  required String opf,
  required Map<String, String> extraFiles,
  String opfPath = 'OEBPS/content.opf',
}) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add(
    'META-INF/container.xml',
    '<?xml version="1.0"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        '  <rootfiles>\n'
        '    <rootfile full-path="$opfPath" media-type="application/oebps-package+xml"/>\n'
        '  </rootfiles>\n'
        '</container>',
  );
  add(opfPath, opf);
  extraFiles.forEach(add);
  return ZipEncoder().encode(archive);
}

void main() {
  group('EPUB 2（NCX 目录）', () {
    final epub = buildEpub(
      opf: '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试书</dc:title>
    <dc:creator>某作者</dc:creator>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''',
      extraFiles: {
        'OEBPS/toc.ncx': '''
<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="n1"><navLabel><text>第一章 起点</text></navLabel><content src="chapter1.xhtml"/></navPoint>
    <navPoint id="n2"><navLabel><text>第二章 转折</text></navLabel><content src="chapter2.xhtml"/></navPoint>
  </navMap>
</ncx>''',
        'OEBPS/chapter1.xhtml':
            '<html><head><title>ch1</title></head><body><h1>第一章 起点</h1>'
            '<p>正文甲。</p><p>正文乙。</p></body></html>',
        'OEBPS/chapter2.xhtml':
            '<html><body><h1>第二章 转折</h1><p>正文丙。</p></body></html>',
      },
    );

    test('读取书名与作者', () {
      final book = EpubImporter.parse(epub);
      expect(book.title, '测试书');
      expect(book.author, '某作者');
    });

    test('按 spine 生成章节并取 NCX 标题', () {
      final book = EpubImporter.parse(epub);
      expect(book.chapters.length, 2);
      expect(book.chapters[0].title, '第一章 起点');
      expect(book.chapters[1].title, '第二章 转折');
    });

    test('正文按段落保留换行且区间可切出内容', () {
      final book = EpubImporter.parse(epub);
      final first = book.content.substring(
        book.chapters[0].start,
        book.chapters[0].end,
      );
      expect(first, contains('第一章 起点'));
      expect(first, contains('正文甲。'));
      expect(first, contains('正文乙。'));
      expect(first.split('\n').where((l) => l.isNotEmpty).length, greaterThanOrEqualTo(3));
      final second = book.content.substring(
        book.chapters[1].start,
        book.chapters[1].end,
      );
      expect(second, contains('正文丙。'));
    });
  });

  group('EPUB 3（nav.xhtml 目录）', () {
    final epub = buildEpub(
      opf: '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>三版书</dc:title>
    <dc:creator>作者乙</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="text/part1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/part2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>''',
      extraFiles: {
        'OEBPS/nav.xhtml':
            '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
            '<body><nav epub:type="toc"><ol>'
            '<li><a href="text/part1.xhtml">卷首</a></li>'
            '<li><a href="text/part2.xhtml#top">卷尾</a></li>'
            '</ol></nav></body></html>',
        'OEBPS/text/part1.xhtml':
            '<html><body><div><p>第一段。</p><p>第二段。</p></div></body></html>',
        'OEBPS/text/part2.xhtml':
            '<html><body><p>尾段。</p></body></html>',
      },
    );

    test('读取 nav 目录标题（含跨目录与片段链接）', () {
      final book = EpubImporter.parse(epub);
      expect(book.title, '三版书');
      expect(book.chapters.length, 2);
      expect(book.chapters[0].title, '卷首');
      expect(book.chapters[1].title, '卷尾');
    });

    test('正文内容与段落换行正确', () {
      final book = EpubImporter.parse(epub);
      expect(book.content, contains('第一段。'));
      expect(book.content, contains('第二段。'));
      expect(book.content, contains('尾段。'));
    });
  });

  group('异常处理', () {
    test('缺少 container.xml 时抛出可读异常', () {
      final archive = Archive();
      final bytes = utf8.encode('not an epub');
      archive.addFile(ArchiveFile('hello.txt', bytes.length, bytes));
      expect(
        () => EpubImporter.parse(ZipEncoder().encode(archive)),
        throwsA(isA<EpubException>()),
      );
    });
  });
}
