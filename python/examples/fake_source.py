"""本地测试书源（假数据）：完全不联网，用于验证书源的搜索 / 详情 / 下载链路。

用途：
  - 应用内「脚本插件 → 内置示例 → 本地测试书源」导入后，点 🔍 在线搜索即可看到假数据；
  - 输入关键词 `fail` 可让搜索失败（测试错误提示）；
  - 输入关键词 `slow` 可让搜索慢 3 秒（测试取消/加载状态）。

约定与真实书源完全一致（见插件开发指南）：
  search   → output/result.json  {"items":[...]}
  detail   → output/result.json  + output/cover.<ext>
  download → output/<output_file>（EPUB 3）
"""

import json
import os
import struct
import time
import zlib

from readerplus_epub import EpubBook

SCRIPT = {
    "kind": "source",
    "id": "fake-local",
    "name": "本地测试书源（假数据）",
    "version": "1.0",
    "capabilities": ["search", "detail", "download"],
}

BOOKS = [
    {
        "id": "1",
        "title": "夜航船（测试书）",
        "author": "张岱（测试）",
        "intro": "测试用假数据 · 三章",
        "color": (0x3D, 0x5A, 0xFE),
    },
    {
        "id": "2",
        "title": "山中客（测试书）",
        "author": "佚名",
        "intro": "测试用假数据 · 单章",
        "color": (0x2E, 0x7D, 0x32),
    },
    {
        "id": "3",
        "title": "旧信笺（测试书）",
        "author": "测试作者",
        "intro": "测试用假数据 · 无封面示例",
        "color": (0xEF, 0x6C, 0x00),
        "no_cover": True,
    },
]

CHAPTERS = {
    "1": [
        ("第一章 夜叩门", "夜色像一层薄薄的墨，慢慢洇开在窗棂上。"),
        ("第二章 旧信笺", "茶已经凉了，他却舍不得起身。"),
        ("第三章 山中客", "灯芯爆了一下，光影晃动。"),
    ],
    "2": [("山中客", "门外忽然响起三下叩门声，不轻不重，恰好敲在人心上。")],
    "3": [("旧信笺", "这样的夜里，适合想一些很久以前的事。")],
}


def params():
    with open("params.json", encoding="utf-8") as handle:
        return json.load(handle)


def write_result(payload):
    os.makedirs("output", exist_ok=True)
    with open("output/result.json", "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False)
    print(f"[fake] 已写出 result.json")


def solid_png(width, height, rgb):
    """生成一张纯色 PNG（纯标准库，无需 Pillow）。"""
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(
            ">I", zlib.crc32(body) & 0xFFFFFFFF
        )

    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def find_book(book_id):
    for book in BOOKS:
        if book["id"] == str(book_id):
            return book
    return None


def do_search(config):
    query = str(config.get("query", ""))
    print(f"[fake] 搜索：{query}")
    if query.strip().lower() == "fail":
        raise RuntimeError("测试用的搜索失败（关键词 fail）")
    if query.strip().lower() == "slow":
        time.sleep(3)

    items = []
    for book in BOOKS:
        if query and query not in book["title"] and query not in book["author"]:
            if query not in ("", "测试", "书"):
                continue
        items.append(
            {
                "id": book["id"],
                "title": book["title"],
                "author": book["author"],
                "cover": "" if book.get("no_cover") else f"fake://cover/{book['id']}",
                "intro": book["intro"],
            }
        )
    print(f"[fake] 命中 {len(items)} 条")
    write_result({"items": items, "has_more": False, "page": int(config.get("page", 1))})


def do_detail(config):
    book = find_book(config.get("book_id"))
    if book is None:
        raise ValueError(f"没有这本书：{config.get('book_id')}")
    payload = {
        "id": book["id"],
        "title": book["title"],
        "author": book["author"],
        "intro": book["intro"],
        "description": f"{book['intro']}；这是本地假数据，用于流程测试。",
    }
    if not book.get("no_cover"):
        name = "cover.png"
        os.makedirs("output", exist_ok=True)
        with open(os.path.join("output", name), "wb") as handle:
            handle.write(solid_png(90, 128, book["color"]))
        payload["cover_file"] = name
        print(f"[fake] 已生成封面 {name}")
    write_result(payload)


def do_download(config):
    book = find_book(config.get("book_id"))
    if book is None:
        raise ValueError(f"没有这本书：{config.get('book_id')}")
    chapters = CHAPTERS.get(book["id"], [("正文", "假数据")])

    epub = EpubBook(title=book["title"], author=book["author"])
    for title, body in chapters:
        epub.add_chapter(title, body)
    if not book.get("no_cover"):
        epub.set_cover(solid_png(90, 128, book["color"]), "cover.png")
    output = os.path.join("output", config.get("output_file", "book.epub"))
    epub.save(output)
    print(f"[fake] 已写出 {output}（{len(chapters)} 章）")


def main():
    config = params()
    task = config.get("task", "")
    print(f"[fake] 任务：{task}")
    if task == "search":
        do_search(config)
    elif task == "detail":
        do_detail(config)
    elif task in ("download", "source"):
        do_download(config)
    else:
        raise ValueError(f"不认识的任务：{task}")


if __name__ == "__main__":
    main()
