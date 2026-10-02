#!/usr/bin/env bash
#
# 打包 Python 运行时与插件依赖（serious_python）。
#
# 用法：
#   tool/package_python.sh <平台>        # Linux | Android | Darwin | iOS | Windows
#
# 约定：
#   - 产物暂存目录固定为 <仓库根>/build/python-app，并需要以同名环境变量
#     SERIOUS_PYTHON_APP 传给随后的平台构建（各端原生构建会把它拷进应用包）。
#   - 依赖清单在这里维护；CI 只调用本脚本（本地与线上同一份逻辑）。
#
set -euo pipefail

PLATFORM="${1:-Linux}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING="${SERIOUS_PYTHON_APP:-${REPO_ROOT}/build/python-app}"

# 插件源码与预置依赖（脚本作者可直接 import）
APP_SRC="${REPO_ROOT}/python/app"
REQUIREMENTS=(
  requests
  charset-normalizer
  epub-generator
)

if [ ! -d "${APP_SRC}" ]; then
  echo "找不到插件源码目录：${APP_SRC}" >&2
  exit 1
fi

mkdir -p "${STAGING}"
export SERIOUS_PYTHON_APP="${STAGING}"

echo "平台：${PLATFORM}"
echo "暂存目录：${SERIOUS_PYTHON_APP}"
echo "依赖：${REQUIREMENTS[*]}"
echo "（构建前请确保 SERIOUS_PYTHON_APP 指向同一路径）"

args=()
for requirement in "${REQUIREMENTS[@]}"; do
  args+=(-r "${requirement}")
done

cd "${REPO_ROOT}"
dart run serious_python:main package "${APP_SRC}" -p "${PLATFORM}" "${args[@]}"

echo "完成：${STAGING}"
