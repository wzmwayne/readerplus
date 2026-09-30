import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/epub_importer.dart';

List<int> buildEpub({
  required String opf,
  required Map<String, String> extraFiles,
  Map<String, List<int>> binaryFiles = const {},
}) {
  final archive = Archive();
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));

  add('mimetype', utf8.encode('application/epub+zip'));
  add(
    'META-INF/container.xml',
    utf8.encode(
      '<?xml version="1.0"?><container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>',
    ),
  );
  add('OEBPS/content.opf', utf8.encode(opf));
  extraFiles.forEach((k, v) => add(k, utf8.encode(v)));
  binaryFiles.forEach(add);
  return ZipEncoder().encode(archive);
}

/// 1×1 像素 PNG，作为封面图内容。
final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
);

const _xhtml = '<html><body><h1>正文</h1><p>内容。</p></body></html>';

void main() {
  group('EPUB3 封面（properties=cover-image）', () {
    final epub = buildEpub(
      opf: '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>封面书</dc:title><dc:creator>作者丙</dc:creator></metadata>
  <manifest>
    <item id="cover" href="images/cover.png" media-type="image/png" properties="cover-image"/>
    <item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
      extraFiles: {'OEBPS/text/c1.xhtml': _xhtml},
      binaryFiles: {'OEBPS/images/cover.png': tinyPng},
    );

    test('读到书名与封面字节', () {
      final book = EpubImporter.parse(epub);
      expect(book.title, '封面书');
      expect(book.author, '作者丙');
      expect(book.coverBytes, isNotNull);
      expect(book.coverBytes!.length, tinyPng.length);
      expect(book.coverExtension, 'png');
    });
  });

  group('EPUB2 封面（meta name=cover）', () {
    final epub = buildEpub(
      opf: '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>二版封面</dc:title>
    <meta name="cover" content="coverimg"/>
  </metadata>
  <manifest>
    <item id="coverimg" href="img/mycover.jpg" media-type="image/jpeg"/>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
      extraFiles: {'OEBPS/c1.xhtml': _xhtml},
      binaryFiles: {'OEBPS/img/mycover.jpg': tinyPng},
    );

    test('按 meta 指向取到封面', () {
      final book = EpubImporter.parse(epub);
      expect(book.title, '二版封面');
      expect(book.coverBytes, isNotNull);
      expect(book.coverExtension, 'jpg');
    });
  });

  group('封面缺失与书名回退', () {
    final epub = buildEpub(
      opf: '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"/>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
      extraFiles: {'OEBPS/c1.xhtml': '<html><body><p>无元数据正文。</p></body></html>'},
    );

    test('没有封面与书名时不报错，交由调用方回退', () {
      final book = EpubImporter.parse(epub);
      expect(book.title, isEmpty);
      expect(book.coverBytes, isNull);
      expect(book.chapters.length, 1);
      expect(book.content, contains('无元数据正文。'));
    });
  });
}
