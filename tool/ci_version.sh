#!/usr/bin/env bash
# 计算本次构建的自动版本号并写入 $GITHUB_OUTPUT。
#
# 版本名：yymmddhhmmss（上海时区/UTC+8，取本次运行开始时间；同一 run 内各 job 一致）
# 版本号：Android versionCode，用「自 2020-01-01 起的分钟数」。
#         12 位时间戳会超过 Android versionCode 上限 2100000000，故改用分钟数，
#         既单调递增又远离上限（当前约 355 万）。
#
# 说明：中国没有夏令时，这里用 epoch + 8 小时换算，避免依赖容器里的 tzdata。
#
# 用法（在 workflow 步骤中）：
#   env:
#     RUN_STARTED_AT: ${{ github.run_started_at }}
#   run: bash tool/ci_version.sh
set -euo pipefail

started_at="${RUN_STARTED_AT:-}"
if [ -z "$started_at" ]; then
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
epoch="$(date -u -d "$started_at" +%s)"
beijing="$(date -u -d "@$((epoch + 8 * 3600))" +%y%m%d%H%M%S)"
code=$(( (epoch - 1577836800) / 60 ))

echo "版本名 ${beijing}（上海时区），versionCode ${code}（自 2020-01-01 起的分钟数）"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${beijing}"
    echo "code=${code}"
  } >> "$GITHUB_OUTPUT"
fi
