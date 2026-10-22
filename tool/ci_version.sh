#!/usr/bin/env bash
# 版本号来源：**pubspec.yaml 是唯一真相**（A 策略）。
#
# 为什么不再用时间戳：
#   F-Droid 从源码构建时只能读到仓库里的 pubspec.yaml。若 CI 用时间戳覆盖
#   versionCode，商店版的 versionCode 会低于我们发布的 APK，用户永远收不到更新。
#   现在两边读到同一个 versionName / versionCode，升级链一致。
#
# 只有显式设置 NIGHTLY=1 时才会退回时间戳版本（本地/预发构建用）。
#
# 用法：在 workflow 步骤中运行 `bash tool/ci_version.sh`，输出写入 $GITHUB_OUTPUT。
set -euo pipefail

if [ "${NIGHTLY:-0}" = "1" ]; then
  started_at="${RUN_STARTED_AT:-}"
  [ -n "$started_at" ] || started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  epoch="$(date -u -d "$started_at" +%s)"
  beijing="$(date -u -d "@$((epoch + 8 * 3600))" +%y%m%d%H%M%S)"
  code=$(( (epoch - 1577836800) / 60 ))
  echo "NIGHTLY 模式：版本名 ${beijing}，versionCode ${code}"
else
  raw="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)(\+([0-9]+))?.*$/\1 \3/p' pubspec.yaml | head -1)"
  beijing="$(echo "$raw" | cut -d' ' -f1)"
  code="$(echo "$raw" | cut -d' ' -f2)"
  if [ -z "$beijing" ]; then
    echo "::error::无法从 pubspec.yaml 解析 version 字段"
    exit 1
  fi
  # 没写 +N 时用语义版本自行折算一个稳定码
  if [ -z "$code" ]; then
    IFS='.' read -r mj mn pt <<< "$beijing"
    code=$(( mj * 10000 + mn * 100 + pt ))
    echo "警告：pubspec.yaml 未写 +build 号，按语义版本折算 versionCode=${code}"
  fi
  echo "版本名 ${beijing}，versionCode ${code}（来自 pubspec.yaml）"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${beijing}"
    echo "code=${code}"
  } >> "$GITHUB_OUTPUT"
fi
