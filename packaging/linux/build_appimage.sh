#!/usr/bin/env bash
# 把 flutter build linux --release 的产物打成 AppImage。
#
# 用法：packaging/linux/build_appimage.sh <版本号>
# 环境变量：
#   APPIMAGETOOL_VERSION  appimagetool 版本（固定，默认 1.9.1）
#
# 说明：CI 容器内没有 FUSE，appimagetool 本身也是 AppImage，
# 因此用 APPIMAGE_EXTRACT_AND_RUN=1 让它自解包后运行。
set -euo pipefail

VERSION="${1:-0.0.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
APPDIR="$ROOT/build/appimage/readerplus.AppDir"
TOOL_VERSION="${APPIMAGETOOL_VERSION:-1.9.1}"
TOOL="/tmp/appimagetool-x86_64.AppImage"
OUT="$ROOT/readerplus-${VERSION}-x86_64.AppImage"

if [ ! -d "$BUNDLE" ]; then
  echo "找不到构建产物：$BUNDLE（请先执行 flutter build linux --release）" >&2
  exit 1
fi

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Flutter 产物整体作为 usr/bin，并补一个 readerplus 别名
cp -r "$BUNDLE"/. "$APPDIR/usr/bin/"
ln -sf reader "$APPDIR/usr/bin/readerplus"

install -m 755 "$ROOT/packaging/linux/AppRun" "$APPDIR/AppRun"
install -m 644 "$ROOT/packaging/linux/readerplus.desktop" "$APPDIR/readerplus.desktop"
install -m 644 "$ROOT/packaging/linux/readerplus.desktop" \
  "$APPDIR/usr/share/applications/readerplus.desktop"
install -m 644 "$ROOT/packaging/linux/readerplus.png" "$APPDIR/readerplus.png"
install -m 644 "$ROOT/packaging/linux/readerplus.png" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps/readerplus.png"

if [ ! -x "$TOOL" ]; then
  echo "下载 appimagetool ${TOOL_VERSION}"
  curl -fsSL -o "$TOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/${TOOL_VERSION}/appimagetool-x86_64.AppImage"
  chmod +x "$TOOL"
fi

ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" "$APPDIR" "$OUT"
echo "已生成：$OUT"
