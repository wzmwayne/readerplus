import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../models/book.dart';

/// EPUB 解析结果，正文与章节结构与 TXT 导入保持一致（章节用字符区间定位）。
class EpubBook {
  const EpubBook({
    required this.title,
    required this.author,
    required this.content,
    required this.chapters,
    this.coverBytes,
    this.coverExtension,
  });

  final String title;
  final String author;
  final String content;
  final List<Chapter> chapters;

  /// 封面图片字节（取不到为 null）与其扩展名。
  final List<int>? coverBytes;
  final String? coverExtension;
}

/// EPUB 2 / 3 导入。
///
/// 解析流程：container.xml → OPF（manifest / spine / metadata）
/// → 目录（EPUB3 的 nav.xhtml，EPUB2 的 NCX；都取不到则用正文标题）
/// → 按 spine 顺序抽取各 XHTML 的纯文本。
class EpubImporter {
  const EpubImporter._();

  /// 视为块级元素，用于在纯文本中保留段落换行。
  static const _blockTags = {
    'address', 'article', 'aside', 'blockquote', 'body', 'br', 'caption',
    'dd', 'div', 'dl', 'dt', 'figcaption', 'figure', 'footer', 'h1', 'h2',
    'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav', 'ol', 'p',
    'pre', 'section', 'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'ul',
  };

  static const _skipTags = {'script', 'style', 'head', 'title', 'meta', 'link'};

  static EpubBook parse(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (f.isFile) files[_normalize(f.name)] = f;
    }

    final opfPath = _findOpfPath(files);
    if (opfPath == null) {
      throw const EpubException('不是有效的 EPUB：缺少 META-INF/container.xml 或 OPF');
    }
    final opfXml = _parseXml(_readText(files, opfPath));
    if (opfXml == null) throw const EpubException('OPF 文件无法解析');

    final opfDir = _dirOf(opfPath);
    final metadata = _readMetadata(opfXml);
    final manifest = _readManifest(opfXml, opfDir);
    final spine = _readSpine(opfXml);

    // 目录：EPUB3 nav 优先，其次 NCX
    var toc = <({String path, String title})>[];
    final navItem = manifest.values.firstWhere(
      (item) => item.properties.contains('nav'),
      orElse: () => const _ManifestItem(id: '', path: '', properties: ''),
    );
    if (navItem.path.isNotEmpty) {
      toc = _parseNavXhtml(_readText(files, navItem.path), _dirOf(navItem.path));
    }
    if (toc.isEmpty) {
      final ncxItem = manifest.values.firstWhere(
        (item) => item.mediaType == 'application/x-dtbncx+xml',
        orElse: () => const _ManifestItem(id: '', path: '', properties: ''),
      );
      if (ncxItem.path.isNotEmpty) {
        toc = _parseNcx(
          _parseXml(_readText(files, ncxItem.path)),
          _dirOf(ncxItem.path),
        );
      }
    }

    final content = StringBuffer();
    final chapters = <Chapter>[];
    final tocTitles = {for (final e in toc) e.path: e.title};

    for (final idref in spine) {
      final item = manifest[idref];
      if (item == null || item.path.isEmpty) continue;
      // 导航文档可能也在 spine 里（如 EbookLib 生成的书），它是目录而非正文
      if (item.properties.split(' ').contains('nav')) continue;
      final raw = _readText(files, item.path, allowMissing: true);
      if (raw == null) continue;
      final document = html_parser.parse(raw);
      final text = _extractText(document).trim();
      if (text.isEmpty) continue;

      var title = tocTitles[item.path] ?? '';
      if (title.isEmpty) title = _firstHeading(document) ?? '';
      if (title.isEmpty) title = '第${chapters.length + 1}章';

      final start = content.length;
      content.write(text);
      content.write('\n');
      final end = content.length;
      chapters.add(
        Chapter(index: chapters.length, title: title, start: start, end: end),
      );
    }

    if (chapters.isEmpty) throw const EpubException('EPUB 中没有可读取的正文');

    // 封面：EPUB3 的 properties="cover-image"、EPUB2 的 meta[name=cover]、
    // guide 的 reference[type=cover]，最后按 id/href 里含 cover 的图片兜底。
    final coverItem = _findCoverItem(opfXml, manifest, opfDir);
    List<int>? coverBytes;
    String? coverExtension;
    if (coverItem != null) {
      final coverFile = files[_normalize(coverItem.path)];
      final bytes = coverFile?.content;
      if (bytes != null && bytes.isNotEmpty) {
        coverBytes = bytes;
        coverExtension = _imageExtension(coverItem);
      }
    }

    return EpubBook(
      title: metadata.title,
      author: metadata.author,
      content: content.toString(),
      chapters: chapters,
      coverBytes: coverBytes,
      coverExtension: coverExtension,
    );
  }

  // ---------- 包结构 ----------

  static String? _findOpfPath(Map<String, ArchiveFile> files) {
    final container = _readText(files, 'META-INF/container.xml', allowMissing: true);
    if (container == null) return null;
    final xml = _parseXml(container);
    if (xml == null) return null;
    for (final e in xml.findAllElements('rootfile')) {
      final path = e.getAttribute('full-path');
      if (path != null && path.isNotEmpty) return _normalize(path);
    }
    return null;
  }

  static ({String title, String author}) _readMetadata(XmlDocument opf) {
    String pick(String local) {
      for (final e in opf.findAllElements('*')) {
        if (e.name.local == local && e.innerText.trim().isNotEmpty) {
          return e.innerText.trim();
        }
      }
      return '';
    }

    return (title: pick('title'), author: pick('creator'));
  }

  /// 定位封面图片对应的 manifest 项。
  static _ManifestItem? _findCoverItem(
    XmlDocument opf,
    Map<String, _ManifestItem> manifest,
    String opfDir,
  ) {
    // EPUB3
    for (final item in manifest.values) {
      if (item.properties
          .split(RegExp(r'\s+'))
          .contains('cover-image')) {
        return item;
      }
    }
    // EPUB2：<meta name="cover" content="itemId"/>
    for (final e in opf.findAllElements('*')) {
      if (e.name.local != 'meta') continue;
      if ((e.getAttribute('name') ?? '').toLowerCase() != 'cover') continue;
      final id = e.getAttribute('content');
      if (id != null && manifest.containsKey(id)) return manifest[id];
    }
    // guide：<reference type="cover" href="..."/>
    for (final e in opf.findAllElements('*')) {
      if (e.name.local != 'reference') continue;
      if (!(e.getAttribute('type') ?? '').toLowerCase().contains('cover')) continue;
      final href = e.getAttribute('href');
      if (href == null) continue;
      final path = _resolve(opfDir, href);
      for (final item in manifest.values) {
        if (item.path == path) return item;
      }
    }
    // 兜底：图片且 id / href 含 cover
    for (final item in manifest.values) {
      if (!item.mediaType.startsWith('image/')) continue;
      if ('${item.id} ${item.path}'.toLowerCase().contains('cover')) return item;
    }
    return null;
  }

  static String? _imageExtension(_ManifestItem item) {
    final mediaType = item.mediaType.toLowerCase();
    if (mediaType.contains('png')) return 'png';
    if (mediaType.contains('gif')) return 'gif';
    if (mediaType.contains('webp')) return 'webp';
    if (mediaType.contains('jpeg') || mediaType.contains('jpg')) return 'jpg';
    final path = item.path.toLowerCase();
    for (final ext in ['png', 'gif', 'webp', 'jpg', 'jpeg']) {
      if (path.endsWith('.$ext')) return ext == 'jpeg' ? 'jpg' : ext;
    }
    return 'jpg';
  }

  static Map<String, _ManifestItem> _readManifest(XmlDocument opf, String opfDir) {
    final result = <String, _ManifestItem>{};
    for (final e in opf.findAllElements('*')) {
      if (e.name.local != 'item') continue;
      final id = e.getAttribute('id') ?? '';
      final href = e.getAttribute('href') ?? '';
      if (id.isEmpty || href.isEmpty) continue;
      // 只处理 XHTML / NCX，图片、字体、样式表跳过
      result[id] = _ManifestItem(
        id: id,
        path: _resolve(opfDir, href),
        mediaType: e.getAttribute('media-type') ?? '',
        properties: e.getAttribute('properties') ?? '',
      );
    }
    return result;
  }

  static List<String> _readSpine(XmlDocument opf) {
    final ids = <String>[];
    for (final e in opf.findAllElements('*')) {
      if (e.name.local != 'itemref') continue;
      final idref = e.getAttribute('idref');
      if (idref != null && idref.isNotEmpty) ids.add(idref);
    }
    return ids;
  }

  // ---------- 目录 ----------

  /// 解析 EPUB3 的 nav.xhtml；目录项 href 相对 nav 文件所在目录。
  static List<({String path, String title})> _parseNavXhtml(String? raw, String baseDir) {
    if (raw == null) return const [];
    final document = html_parser.parse(raw);
    dom.Element? nav;
    for (final e in document.querySelectorAll('nav')) {
      final type = e.attributes.entries
          .where((a) => a.key.toString().endsWith('type'))
          .map((a) => a.value)
          .join(' ');
      if (type.contains('toc')) {
        nav = e;
        break;
      }
    }
    nav ??= document.querySelector('nav');
    if (nav == null) return const [];
    final result = <({String path, String title})>[];
    for (final a in nav.querySelectorAll('a')) {
      final href = a.attributes['href'];
      final title = a.text.trim();
      if (href == null || href.isEmpty || title.isEmpty) continue;
      result.add((path: _resolve(baseDir, href), title: title));
    }
    return result;
  }

  /// 解析 EPUB2 的 NCX 目录；目录项 src 相对 ncx 文件所在目录。
  static List<({String path, String title})> _parseNcx(XmlDocument? ncx, String baseDir) {
    if (ncx == null) return const [];
    final result = <({String path, String title})>[];
    for (final e in ncx.findAllElements('*')) {
      if (e.name.local != 'navPoint') continue;
      var title = '';
      for (final label in e.findAllElements('*')) {
        if (label.name.local == 'text') {
          title = label.innerText.trim();
          break;
        }
      }
      var src = '';
      for (final c in e.findAllElements('*')) {
        if (c.name.local == 'content') {
          src = c.getAttribute('src') ?? '';
          break;
        }
      }
      if (title.isEmpty || src.isEmpty) continue;
      result.add((path: _resolve(baseDir, src), title: title));
    }
    return result;
  }

  // ---------- 正文抽取 ----------

  /// 抽取 XHTML 纯文本：块级元素之间保留换行，行内元素原样拼接。
  static String _extractText(dom.Document document) {
    final buffer = StringBuffer();
    var lastIsNewline = true;

    void newline() {
      if (!lastIsNewline) {
        buffer.write('\n');
        lastIsNewline = true;
      }
    }

    void line(String text) {
      final cleaned = text.replaceAll(RegExp(r'\s+'), ' ');
      if (cleaned.trim().isEmpty) return;
      buffer.write(cleaned);
      lastIsNewline = false;
    }

    void walk(dom.Node node) {
      if (node is dom.Text) {
        line(node.data);
        return;
      }
      if (node is dom.Element) {
        final tag = (node.localName ?? '').toLowerCase();
        if (_skipTags.contains(tag)) return;
        final isBlock = _blockTags.contains(tag);
        if (isBlock) newline();
        for (final child in node.nodes) {
          walk(child);
        }
        if (isBlock) newline();
        return;
      }
      for (final child in node.nodes) {
        walk(child);
      }
    }

    final body = document.body ?? document.documentElement;
    if (body != null) {
      for (final child in body.nodes) {
        walk(child);
      }
    }
    return buffer.toString().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('\n');
  }

  static String? _firstHeading(dom.Document document) {
    for (final tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'title']) {
      final el = document.querySelector(tag);
      final text = el?.text.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  // ---------- 工具 ----------

  static String _normalize(String path) {
    final noFragment = path.split('#').first;
    final decoded = Uri.decodeFull(noFragment);
    return _join('', decoded);
  }

  static String _dirOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static String _resolve(String baseDir, String href) => _join(baseDir, href.split('#').first);

  static String _join(String baseDir, String href) {
    final parts = <String>[];
    for (final segment in '$baseDir/$href'.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    return parts.join('/');
  }

  static XmlDocument? _parseXml(String? raw) {
    if (raw == null) return null;
    try {
      return XmlDocument.parse(raw);
    } catch (_) {
      return null;
    }
  }

  static String? _readText(
    Map<String, ArchiveFile> files,
    String path, {
    bool allowMissing = false,
  }) {
    final file = files[_normalize(path)];
    if (file == null) {
      if (allowMissing) return null;
      throw EpubException('EPUB 缺少文件：$path');
    }
    return utf8.decode(file.content, allowMalformed: true);
  }
}

class _ManifestItem {
  const _ManifestItem({
    required this.id,
    required this.path,
    this.mediaType = '',
    this.properties = '',
  });

  final String id;
  final String path;
  final String mediaType;
  final String properties;
}

class EpubException implements Exception {
  const EpubException(this.message);
  final String message;

  @override
  String toString() => message;
}
