#!/usr/bin/env bash
# パイプラインのスクリプトのテストを全部動かす（疑似 gh を使うので、本物のGitHubには触らない）
# 使い方：.github/scripts/tests/run-all.sh
set -u
cd "$(dirname "$0")" || exit 1
fail=0
for t in test-*.sh; do
  echo "### $t"
  bash "$t" || fail=1
done
if [ "$fail" -ne 0 ]; then
  echo "テストに失敗した物があります"
  exit 1
fi
echo "全部のテストが通りました"
