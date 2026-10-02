"""示例书源脚本：用公开的 Gutendex（Project Gutenberg 的公开接口）演示书源标准。

脚本内必须声明自己的类型与能力（宿主通过 describe 任务读取）：

    SCRIPT = {
        "kind": "source",                       # clean（清洗转 EPUB）/ source（书源）
        "id": "gutenberg",
        "name": "古腾堡（示例）",
        "version": "1.0",
        "capabilities": ["search", "detail", "download"],
    }

三种调用（由 params.json 的 task 区分，参数与产物都是文件）：
    search   : params {query, page}   → output/result.json  {"items": [...]}
    detail   : params {book_id}       → output/result.json  {..., "cover_file": "cover.jpg"}
    download : params {book_id}       → output/<output_file>（EPUB 3）

只抓取公共领域的公开内容；请遵守目标站点的条款与频率限制。
"""

import json
import os
import re
import time

import requests

from readerplus_epub import EpubBook

SCRIPT = {
    "kind": "source",
    "id": "gutenberg",
    "name": "古腾堡（示例）",
    "version": "1.0",
    "capabilities": ["search", "detail", "download"],
}

API = "https://gutendex.com/books"
TIMEOUT = (5, 20)


def params():
    with open("params.json", encoding="utf-8") as handle:
        return json.load(handle)


def write_result(payload):
    os.makedirs("output", exist_ok=True)
    with open("output/result.json", "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False)
    print(f"[source] 已写出 result.json（{len(payload.get('items', []))} 项）")


def get_json(url, retries=3):
    for attempt in range(1, retries + 1):
        try:
            resp = requests.get(url, timeout=TIMEOUT, headers={"User-Agent": "readerplus-plugin"})
            resp.raise_for_status()
            return resp.json()
        except Exception as error:  # noqa: BLE001 - 重试后仍失败就抛给宿主
            print(f"[source] 第 {attempt} 次请求失败：{error}")
            if attempt == retries:
                raise
            time.sleep(1.5 * attempt)


def cover_url(book):
    for key, url in (book.get("formats") or {}).items():
        if key.startswith("image/"):
            return url
    return ""


def to_item(book):
    authors = ", ".join(a.get("name", "") for a in book.get("authors") or [])
    return {
        "id": str(book.get("id", "")),
        "title": book.get("title", ""),
        "author": authors,
        "cover": cover_url(book),
        "intro": ", ".join(book.get("subjects") or [])[:200],
        "extra": {"download_count": book.get("download_count", 0)},
    }


def do_search(config):
    query = config.get("query", "").strip()
    page = int(config.get("page", 1))
    if not query:
        write_result({"items": []})
        return
    data = get_json(f"{API}?search={requests.utils.quote(query)}&page={page}")
    items = [to_item(book) for book in data.get("results") or []]
    print(f"[source] 搜索「{query}」第 {page} 页：{len(items)} 条 / 共 {data.get('count', 0)} 条")
    write_result({"items": items, "has_more": bool(data.get("next")), "page": page})


def do_detail(config):
    book_id = str(config.get("book_id", "")).strip()
    if not book_id:
        raise ValueError("缺少 book_id")
    book = get_json(f"{API}/{book_id}/")
    item = to_item(book)
    item["description"] = re.sub(r"\s+", " ", book.get("summaries", [""])[0] if book.get("summaries") else "")
    item["chapters_url"] = (book.get("formats") or {}).get("text/plain; charset=utf-8", "")

    # 封面单独落盘，宿主按 cover_file 读取
    url = item.get("cover") or ""
    if url:
        try:
            resp = requests.get(url, timeout=TIMEOUT, headers={"User-Agent": "readerplus-plugin"})
            resp.raise_for_status()
            extension = "png" if url.lower().endswith(".png") else "jpg"
            name = f"cover.{extension}"
            os.makedirs("output", exist_ok=True)
            with open(os.path.join("output", name), "wb") as handle:
                handle.write(resp.content)
            item["cover_file"] = name
            print(f"[source] 封面已保存：{name}（{len(resp.content)} 字节）")
        except Exception as error:  # noqa: BLE001 - 封面失败不影响详情
            print(f"[source] 封面下载失败：{error}")

    print(f"[source] 详情：{item['title']} / {item['author']}")
    write_result(item)


def do_download(config):
    book_id = str(config.get("book_id", "")).strip()
    if not book_id:
        raise ValueError("缺少 book_id")
    book = get_json(f"{API}/{book_id}/")
    title = book.get("title") or f"gutenberg-{book_id}"
    author = ", ".join(a.get("name", "") for a in book.get("authors") or []) or "佚名"

    text_url = (book.get("formats") or {}).get("text/plain; charset=utf-8") or ""
    if not text_url:
        raise ValueError("该书没有纯文本格式")
    print(f"[source] 下载正文：{text_url}")
    resp = requests.get(text_url, timeout=(5, 60), headers={"User-Agent": "readerplus-plugin"})
    resp.raise_for_status()
    text = resp.content.decode("utf-8", "replace")

    # 按 Gutendex 常见的章节写法粗略分章；分不出来就整本当一章
    blocks = re.split(r"\n(?=(?:CHAPTER|Chapter|第[一二三四五六七八九十百千0-9]+章)\b)", text)
    chapters = [(blocks[0].strip().splitlines() or [title])[0][:60], blocks[0]] if blocks else [("正文", text)]
    if len(blocks) > 1:
        chapters = [("前言", blocks[0])] + [
            ((block.strip().splitlines() or [f"第 {i} 章"])[0][:60], block)
            for i, block in enumerate(blocks[1:], start=1)
        ]
    print(f"[source] 切分得到 {len(chapters)} 章")

    output = os.path.join("output", config.get("output_file", "book.epub"))
    book_out = EpubBook(title=title, author=author)
    for chapter_title, body in chapters:
        book_out.add_chapter(chapter_title, body)
    if config.get("cover_bytes"):
        book_out.set_cover(config["cover_bytes"], config.get("cover_name", "cover.jpg"))
    book_out.save(output)
    print(f"[source] 已写出 {output}")


def main():
    config = params()
    task = config.get("task", "")
    print(f"[source] 任务：{task}")
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
