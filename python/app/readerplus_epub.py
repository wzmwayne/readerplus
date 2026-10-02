"""内置 EPUB 3 生成库（纯标准库，各平台完全一致的 API）。

第三方 EPUB 库在移动端不可用：EbookLib 依赖 lxml（Android 无 wheel）、
epub-generator 要求 Python <3.14，因此这里用标准库提供等价的写入能力，
插件在所有平台都能 `import readerplus_epub` 并得到相同行为。

用法：

    from readerplus_epub import EpubBook

    book = EpubBook(title="夜航船", author="张岱")
    book.add_chapter("第一章 夜叩门", "夜色像一层薄薄的墨。")
    book.add_chapter("第二章 旧信笺", "<p>这样的夜里，适合想一些很久以前的事。</p>",
                     is_html=True)
    book.save("output/book.epub")

要点：`mimetype` 永远是压缩包第一个条目且不压缩（EPUB 规范要求），
容器 / OPF / 导航文档自动生成，章节顺序即写入顺序。
"""

import datetime
import html
import os
import uuid
import zipfile

MIMETYPE = "application/epub+zip"
CONTAINER = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
    '  <rootfiles>\n'
    '    <rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/>\n'
    '  </rootfiles>\n'
    "</container>"
)


class EpubBook:
    """组装并写出 EPUB 3。"""

    def __init__(self, title, author="佚名", language="zh-CN", identifier=None):
        self.title = title or "未命名"
        self.author = author or "佚名"
        self.language = language or "zh-CN"
        self.identifier = identifier or f"readerplus-{uuid.uuid4()}"
        self._chapters = []
        self._cover = None  # (filename, bytes, media_type)

    # ---------- 组装 ----------

    def add_chapter(self, title, body, is_html=False):
        """加入一章。[body] 为纯文本时按行转 <p>，为 HTML 时原样使用。"""
        self._chapters.append((title or f"第 {len(self._chapters) + 1} 章", body, is_html))
        return self

    def set_cover(self, image_bytes, filename="cover.jpg", media_type=None):
        """设置封面图（可选）。"""
        media_type = media_type or _guess_media_type(filename)
        self._cover = (filename, image_bytes, media_type)
        return self

    def save(self, path):
        """写出 EPUB；目录不存在会自动创建。"""
        directory = os.path.dirname(path)
        if directory:
            os.makedirs(directory, exist_ok=True)

        manifest, spine, nav_items, files = [], [], [], []
        if self._cover is not None:
            name, data, media = self._cover
            # EPUB 3 的规范封面声明（同时保留 EPUB 2 的 <meta name="cover"> 兼容旧阅读器）
            manifest.append(
                f'<item id="cover-image" href="images/{name}" '
                f'media-type="{media}" properties="cover-image"/>'
            )
            files.append((f"OEBPS/images/{name}", data))

        for index, (title, body, is_html) in enumerate(self._chapters, start=1):
            name = f"chapter{index}.xhtml"
            manifest.append(
                f'<item id="c{index}" href="{name}" '
                'media-type="application/xhtml+xml"/>'
            )
            spine.append(f'<itemref idref="c{index}"/>')
            nav_items.append(f'<li><a href="{name}">{html.escape(title)}</a></li>')
            files.append((f"OEBPS/{name}", _chapter_xhtml(title, body, is_html)))

        manifest.append(
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
            'properties="nav"/>'
        )
        files.append(("OEBPS/nav.xhtml", _nav_xhtml(self.title, nav_items)))
        files.append(("OEBPS/content.opf", self._opf(manifest, spine)))
        files.append(("META-INF/container.xml", CONTAINER))

        with zipfile.ZipFile(path, "w") as archive:
            # 规范要求：mimetype 第一个写入且不压缩
            archive.writestr(
                zipfile.ZipInfo("mimetype"), MIMETYPE, compress_type=zipfile.ZIP_STORED
            )
            for name, content in files:
                archive.writestr(name, content)
        return path

    def _opf(self, manifest, spine):
        cover_meta = (
            '<meta name="cover" content="cover-image"/>' if self._cover else ""
        )
        return (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
            'unique-identifier="bookid">\n'
            '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
            f'    <dc:identifier id="bookid">{html.escape(self.identifier)}</dc:identifier>\n'
            f"    <dc:title>{html.escape(self.title)}</dc:title>\n"
            f"    <dc:creator>{html.escape(self.author)}</dc:creator>\n"
            f"    <dc:language>{html.escape(self.language)}</dc:language>\n"
            "    <meta property=\"dcterms:modified\">"
            f'{datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}'
            "</meta>\n"
            f"    {cover_meta}\n"
            "  </metadata>\n"
            "  <manifest>\n    " + "\n    ".join(manifest) + "\n  </manifest>\n"
            "  <spine>\n    " + "\n    ".join(spine) + "\n  </spine>\n"
            "</package>"
        )


def _chapter_xhtml(title, body, is_html):
    if is_html:
        content = body
    else:
        content = "\n".join(
            f"<p>{html.escape(line.strip())}</p>"
            for line in str(body).splitlines()
            if line.strip()
        )
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN">\n'
        f"  <head><title>{html.escape(title)}</title>"
        '    <meta charset="utf-8"/></head>\n'
        f"  <body>\n    <h2>{html.escape(title)}</h2>\n{content}\n  </body>\n</html>"
    )


def _nav_xhtml(title, nav_items):
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN">\n'
        f"  <head><title>{html.escape(title)}</title></head>\n"
        "  <body>\n"
        '    <nav epub:type="toc"><h1>目录</h1>\n      <ol>\n        '
        + "\n        ".join(nav_items)
        + "\n      </ol>\n    </nav>\n  </body>\n</html>"
    )


def _guess_media_type(filename):
    lowered = filename.lower()
    if lowered.endswith(".png"):
        return "image/png"
    if lowered.endswith(".gif"):
        return "image/gif"
    if lowered.endswith(".webp"):
        return "image/webp"
    return "image/jpeg"
