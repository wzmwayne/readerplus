import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 自制 EPUB 3 写出模块（严格按 EPUB 3.3 规范组织）。
///
/// 规范要点（本模块逐条落实）：
/// 1. ZIP 中 `mimetype` 必须是**第一个**条目、**不压缩（STORED）**，内容为 `application/epub+zip`；
/// 2. `META-INF/container.xml` 指向包文档（OPF），命名空间必须是
///    `urn:oasis:names:tc:opendocument:xmlns:container`；
/// 3. 包文档 `<package version="3.0">` 必须含 `dc:identifier`（与 unique-identifier 一致）、
///    `dc:title`、`dc:language`，以及 EPUB 3 必需的 `<meta property="dcterms:modified">`
///    （UTC、形如 `2026-10-03T06:00:00Z`）；
/// 4. 必须有 `properties="nav"` 的导航文档，其 `<nav epub:type="toc">` 内为 `<ol><li><a>`；
/// 5. 所有 XHTML 内容文档必须是良构 XML、带 `xmlns`、`<head><title>` 非空；
/// 6. 封面图条目带 `properties="cover-image"`（EPUB 3 方式），不再用 2.0 的 guide。
class EpubWriter {
  EpubWriter({
    required this.title,
    this.author = '佚名',
    this.language = 'zh-CN',
    this.identifier,
    this.modified,
  });

  final String title;
  final String author;
  final String language;
  final String? identifier;

  /// 注入时间便于测试（必须为 UTC）。
  final DateTime? modified;

  final List<EpubChapter> _chapters = [];
  Uint8List? _cover;
  String _coverName = 'cover.jpg';
  String _coverMediaType = 'image/jpeg';

  void addChapter(String title, String body) =>
      _chapters.add(EpubChapter(title: title, body: body));

  void setCover(Uint8List bytes, {String fileName = 'cover.jpg'}) {
    _cover = bytes;
    _coverName = fileName;
    _coverMediaType = fileName.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
  }

  String get _bookId => identifier ?? 'urn:uuid:${_uuid()}';

  Uint8List build() {
    final archive = Archive();

    // 1) mimetype：第一个条目且不压缩
    archive.add(
      ArchiveFile.string('mimetype', 'application/epub+zip')
        ..compression = CompressionType.none,
    );

    // 2) META-INF/container.xml
    archive.add(
      ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
    );

    final manifest = StringBuffer();
    final spine = StringBuffer();

    if (_cover != null) {
      archive.add(ArchiveFile.bytes('OEBPS/$_coverName', _cover!));
      manifest.writeln(
        '    <item id="cover-image" href="$_coverName" '
        'media-type="$_coverMediaType" properties="cover-image"/>',
      );
      archive.add(
        ArchiveFile.string('OEBPS/cover.xhtml', _xhtml('封面', '''
    <div class="cover">
      <img src="$_coverName" alt="封面"/>
    </div>''')),
      );
      manifest.writeln(
        '    <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>',
      );
      spine.writeln('    <itemref idref="cover" linear="no"/>');
    }

    for (var i = 0; i < _chapters.length; i++) {
      final chapter = _chapters[i];
      final href = 'chapter${i + 1}.xhtml';
      final body = chapter.body
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) => '    <p>${escape(line)}</p>')
          .join('\n');
      final content = _chapters.length > 1 || chapter.title.isNotEmpty
          ? '    <h1>${escape(chapter.title)}</h1>\n$body'
          : body;
      archive.add(
        ArchiveFile.string('OEBPS/$href', _xhtml(chapter.title, content)),
      );
      manifest.writeln(
        '    <item id="c${i + 1}" href="$href" media-type="application/xhtml+xml"/>',
      );
      spine.writeln('    <itemref idref="c${i + 1}"/>');
    }

    // 4) 导航文档（EPUB 3 必需）
    final navItems = _chapters
        .asMap()
        .entries
        .map(
          (e) =>
              '        <li><a href="chapter${e.key + 1}.xhtml">${escape(e.value.title)}</a></li>',
        )
        .join('\n');
    archive.add(
      ArchiveFile.string('OEBPS/nav.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="$language" lang="$language">
  <head>
    <meta charset="utf-8"/>
    <title>目录</title>
  </head>
  <body>
    <nav epub:type="toc" id="toc">
      <h1>目录</h1>
      <ol>
$navItems
      </ol>
    </nav>
  </body>
</html>
'''),
    );
    manifest.writeln(
      '    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
    );

    // 3) 包文档
    archive.add(
      ArchiveFile.string('OEBPS/package.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="$language">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">${escape(_bookId)}</dc:identifier>
    <dc:title>${escape(title)}</dc:title>
    <dc:language>$language</dc:language>
    <dc:creator>${escape(author)}</dc:creator>
    <meta property="dcterms:modified">${_modifiedStamp()}</meta>
  </metadata>
  <manifest>
$manifest  </manifest>
  <spine>
$spine  </spine>
</package>
'''),
    );

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  String _xhtml(String title, String body) => '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="$language" lang="$language">
  <head>
    <meta charset="utf-8"/>
    <title>${escape(title.isEmpty ? '正文' : title)}</title>
  </head>
  <body>
$body
  </body>
</html>
''';

  String _modifiedStamp() {
    final utc = (modified ?? DateTime.now()).toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}'
        'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }

  static String escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _uuid() {
    // 32 位十六进制（时间戳来源，保证唯一性足够）
    final seed = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final hex = (seed * 2).padLeft(32, '0');
    final tail = hex.substring(hex.length - 32);
    return '${tail.substring(0, 8)}-${tail.substring(8, 12)}-4'
        '${tail.substring(13, 16)}-8${tail.substring(17, 20)}-'
        '${tail.substring(20, 32)}';
  }
}

class EpubChapter {
  const EpubChapter({required this.title, required this.body});

  final String title;
  final String body;
}
