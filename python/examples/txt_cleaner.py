"""示例插件：把 TXT 清洗并切成章节，输出 EPUB 3。

用到的都是各平台完全一致的东西：标准库 + 内置的 readerplus_epub。

params.json（缺失字段都会走默认值）：
{
  "task": "clean",
  "input_file": "raw.txt",
  "output_file": "book.epub",
  "title": "夜航船",
  "author": "张岱",
  "encoding": "auto",
  "chapter_pattern": "^第[一二三四五六七八九十百千0-9]+章.*$",
  "clean_rules": [["[\\u200b\\ufeff]", ""], ["(?m)^\\s*广告.*$", ""]]
}
"""

import json
import os
import re

from readerplus_epub import EpubBook

SCRIPT = {
    "kind": "clean",
    "id": "txt-cleaner",
    "name": "TXT 清洗转 EPUB",
    "version": "1.0",
    "capabilities": ["clean"],
}


def load_params():
    with open("params.json", encoding="utf-8") as handle:
        return json.load(handle)


def read_text(params):
    name = params.get("input_file", "raw.txt")
    with open(os.path.join("input", name), "rb") as handle:
        raw = handle.read()

    preferred = params.get("encoding", "auto")
    if preferred and preferred != "auto":
        encoding = preferred
    else:
        encoding = "utf-8"
        for candidate in ("utf-8", "gb18030"):
            try:
                raw.decode(candidate)
                encoding = candidate
                break
            except UnicodeDecodeError:
                continue
    print(f"[clean] 输入 {name}：{len(raw)} 字节，编码 {encoding}")
    return raw.decode(encoding, "replace")


def apply_rules(text, rules):
    for pattern, replacement in rules or []:
        try:
            text = re.sub(pattern, replacement, text, flags=re.MULTILINE)
        except re.error as error:
            print(f"[clean] 跳过无效规则 {pattern}：{error}")
    return text


def split_chapters(text, pattern):
    if not pattern:
        return [("正文", text)]
    matches = list(re.compile(pattern, re.MULTILINE).finditer(text))
    if not matches:
        print("[clean] 没有匹配到章节标题，按单章处理")
        return [("正文", text)]

    chapters = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        chapters.append((match.group(0).strip(), text[match.end():end].strip()))
    print(f"[clean] 切分得到 {len(chapters)} 章")
    return chapters


def main():
    params = load_params()
    title = params.get("title") or os.path.splitext(
        params.get("input_file", "raw.txt")
    )[0]

    text = apply_rules(read_text(params), params.get("clean_rules"))
    chapters = split_chapters(text, params.get("chapter_pattern"))

    book = EpubBook(title=title, author=params.get("author", "佚名"))
    for chapter_title, body in chapters:
        book.add_chapter(chapter_title, body)

    output = os.path.join("output", params.get("output_file", "book.epub"))
    book.save(output)
    print(f"[clean] 已写出 {output}")


if __name__ == "__main__":
    main()
