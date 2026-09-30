#!/usr/bin/env python3
"""生成应用图标。

设计：极简黑白抽象书本，沿中线分割，左右反色
  - 左半：纯黑底 + 纯白书页
  - 右半：纯白底 + 纯黑书页

用法：
    python3 packaging/icon/generate_icons.py
会同时输出
    packaging/linux/readerplus.png                      （256×256，AppImage/桌面项用）
    android/app/src/main/res/mipmap-*/ic_launcher.png   （Android 启动图标）
"""
from __future__ import annotations

import os
from PIL import Image, ImageDraw

SS = 4  # 超采样倍数，用于抗锯齿
BLACK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# 书本轮廓（以 256 为基准的坐标，之后按尺寸缩放）
# 左右两页在中线处相接，外侧边略短，形成抽象“翻开的书”的透视
SEAM = 128
PAGE_TOP_OUT, PAGE_BOTTOM_OUT = 50, 206
PAGE_TOP_IN, PAGE_BOTTOM_IN = 44, 212
PAGE_OUTER_LEFT, PAGE_OUTER_RIGHT = 40, 216


def draw_icon(size: int) -> Image.Image:
    s = size * SS
    k = s / 256.0

    def sc(v: float) -> float:
        return v * k

    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 左右两半背景
    d.rectangle([0, 0, sc(SEAM) - 1, s], fill=BLACK)
    d.rectangle([sc(SEAM), 0, s, s], fill=WHITE)

    # 左页：白（描出稍带内收的四边形）
    d.polygon(
        [
            (sc(PAGE_OUTER_LEFT), sc(PAGE_TOP_OUT)),
            (sc(SEAM) - 1, sc(PAGE_TOP_IN)),
            (sc(SEAM) - 1, sc(PAGE_BOTTOM_IN)),
            (sc(PAGE_OUTER_LEFT), sc(PAGE_BOTTOM_OUT)),
        ],
        fill=WHITE,
    )
    # 右页：黑（与左页镜像）
    d.polygon(
        [
            (sc(PAGE_OUTER_RIGHT), sc(PAGE_TOP_OUT)),
            (sc(SEAM), sc(PAGE_TOP_IN)),
            (sc(SEAM), sc(PAGE_BOTTOM_IN)),
            (sc(PAGE_OUTER_RIGHT), sc(PAGE_BOTTOM_OUT)),
        ],
        fill=BLACK,
    )

    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    # 桌面/AppImage 图标
    linux_png = os.path.join(ROOT, "packaging/linux/readerplus.png")
    os.makedirs(os.path.dirname(linux_png), exist_ok=True)
    draw_icon(256).save(linux_png)
    print("已生成", linux_png)

    # Android 启动图标
    sizes = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for bucket, px in sizes.items():
        out = os.path.join(
            ROOT, f"android/app/src/main/res/mipmap-{bucket}/ic_launcher.png"
        )
        if not os.path.isdir(os.path.dirname(out)):
            print("跳过（目录不存在）", out)
            continue
        draw_icon(px).save(out)
        print("已生成", out, f"({px}×{px})")


if __name__ == "__main__":
    main()
