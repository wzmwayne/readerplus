"""示例脚本：把 TXT 清洗并切成章节，输出 EPUB 3。

演示宿主约定的用法：
  - 参数从 params.json 读取（缺失字段要有默认值，见下）
  - 输入文件在 input/（只读），产物写入 output/
  - 只用标准库（zipfile 手工构建 EPUB 3：mimetype 必须第一个写入且不压缩）
  - 打印的内容会进入前台日志

params.json 约定（本脚本）：
{
  "task": "clean",
  "input_file": "raw.txt",          # input/ 下的文件名
  "output_file": "book.epub",       # 产物文件名（写入 output/）
  "title": "夜航船",                 # 可选，缺省用输入文件名
  "author": "佚名",                  # 可选
  "encoding": "auto",               # auto / utf-8 / gbk
  "chapter_pattern": "^第[一二三四五六七八九十百千0-9]+章.*$",
  "clean_rules": [["[\\u200b\\ufeff]", ""], ["(?m)^\\s*广告.*$", ""]]
}
"""

import json
import os
import re
import zipfile

MIMETYPE = "application/epub+zip"


def load_params():
    with open("params.json", encoding="utf-8") as handle:
        return json.load(handle)


def detect_encoding(raw, preferred):
    if preferred and preferred != "auto":
        return preferred
    for candidate in ("utf-8", "gb18030"):
        try:
            raw.decode(candidate)
            return candidate
        except UnicodeDecodeError:
            continue
    return "utf-8"


def read_text(params):
    name = params.get("input_file", "raw.txt")
    with open(os.path.join("input", name), "rb") as handle:
        raw = handle.read()
    encoding = detect_encoding(raw, params.get("encoding", "auto"))
    print(f"[clean] 输入 {name}（{len(raw)} 字节，编码 {encoding}）")
    return raw.decode(encoding, "replace")


def apply_rules(text, rules):
    for pattern, replacement in rules or []:
        try:
            text = re.sub(pattern, replacement, text, flags=re.MULTILINE)
        except re.error as error:
            print(f"[clean] 规则无效已跳过：{pattern}（{error}）")
    return text


def split_chapters(text, pattern):
    if not pattern:
        return [("正文", text)]
    regex = re.compile(pattern, re.MULTILINE)
    matches = list(regex.finditer(text))
    if not matches:
        print("[clean] 未匹配到章节标题，作为单章处理")
        return [("正文", text)]
    chapters = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        title = match.group(0).strip()
        body = text[match.end():end].strip()
        chapters.append((title, body))
    print(f"[clean] 切分得到 {len(chapters)} 章")
    return chapters


def xhtml(title, body):
    paragraphs = "\n".join(
        f"<p>{escape(line.strip())}</p>"
        for line in body.splitlines()
        if line.strip()
    )
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN">\n'
        f"<head><title>{escape(title)}</title>"
        '<meta charset="utf-8"/></head>\n'
        f"<body><h2>{escape(title)}</h2>\n{paragraphs}\n</body></html>"
    )


def escape(text):
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def write_epub(path, title, author, chapters):
    manifest_items = []
    spine_items = []
    nav_items = []
    for index, (chapter_title, body) in enumerate(chapters, start=1):
        name = f"chapter{index}.xhtml"
        manifest_items.append(
            f'<item id="c{index}" href="{name}" media-type="application/xhtml+xml"/>'
        )
        spine_items.append(f'<itemref idref="c{index}"/>')
        nav_items.append(f'<li><a href="{name}">{escape(chapter_title)}</a></li>')

    nav = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN">\n'
        "<head><title>目录</title></head><body>\n"
        '<nav epub:type="toc"><h1>目录</h1><ol>\n'
        + "\n".join(nav_items)
        + "\n</ol></nav></body></html>"
    )

    opf = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="bookid">\n'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
        '<dc:identifier id="bookid">readerplus-script</dc:identifier>\n'
        f"<dc:title>{escape(title)}</dc:title>\n"
        f"<dc:creator>{escape(author)}</dc:creator>\n"
        '<dc:language>zh-CN</dc:language>\n'
        "</metadata>\n<manifest>\n"
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>\n'
        + "\n".join(manifest_items)
        + "\n</manifest>\n<spine>\n"
        + "\n".join(spine_items)
        + "\n</spine>\n</package>"
    )

    container = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>'
    )

    os.makedirs("output", exist_ok=True)
    with zipfile.ZipFile(path, "w") as archive:
        # EPUB 规范：mimetype 必须是第一个条目且不压缩
        archive.writestr(
            zipfile.ZipInfo("mimetype"),
            MIMETYPE,
            compress_type=zipfile.ZIP_STORED,
        )
        archive.writestr("META-INF/container.xml", container)
        archive.writestr("OEBPS/content.opf", opf)
        archive.writestr("OEBPS/nav.xhtml", nav)
        for index, (chapter_title, body) in enumerate(chapters, start=1):
            archive.writestr(
                f"OEBPS/chapter{index}.xhtml",
                xhtml(chapter_title, body),
            )
    print(f"[clean] 已写出 {path}（{len(chapters)} 章）")


def main():
    params = load_params()
    title = params.get("title") or os.path.splitext(
        params.get("input_file", "raw.txt")
    )[0]
    author = params.get("author", "佚名")

    text = read_text(params)
    text = apply_rules(text, params.get("clean_rules"))
    chapters = split_chapters(text, params.get("chapter_pattern"))

    output_name = params.get("output_file", "book.epub")
    write_epub(os.path.join("output", output_name), title, author, chapters)


main()
