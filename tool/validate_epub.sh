#!/usr/bin/env bash
#
# 用官方 EPUBCheck 验证内置 EPUB 生成库的产物（各平台一致，纯标准库）。
#
# 用法：tool/validate_epub.sh [epubcheck.jar 路径]
#   未提供时依次尝试：$EPUBCHECK_JAR、PATH 里的 epubcheck、常见安装路径。
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "== 生成样例 EPUB（含章节与封面）=="
python3 - "$WORK" <<'PY'
import struct, sys, zlib
sys.path.insert(0, 'python/app')
from readerplus_epub import EpubBook

def tiny_png():
    def chunk(tag, data):
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(b'\x00\x00\x00\x00')) + chunk(b'IEND', b''))

work = sys.argv[1]
book = EpubBook(title='夜航船', author='张岱')
book.add_chapter('第一章 夜叩门', '夜色像一层薄薄的墨，慢慢洇开在窗棂上。')
book.add_chapter('第二章 旧信笺', '<p>这样的夜里，适合想一些很久以前的事。</p>', is_html=True)
book.set_cover(tiny_png(), 'cover.png')
print(book.save(f'{work}/book.epub'))
PY

JAR="${1:-${EPUBCHECK_JAR:-}}"
if [ -z "${JAR}" ]; then
  JAR="$(command -v epubcheck || true)"
fi
if [ -z "${JAR}" ] || [ ! -e "${JAR}" ]; then
  echo "未找到 EPUBCheck；请设置 EPUBCHECK_JAR=/path/to/epubcheck.jar" >&2
  exit 2
fi

echo "== 验证（EPUB 3.3 规则）=="
java -jar "${JAR}" "${WORK}/book.epub"
