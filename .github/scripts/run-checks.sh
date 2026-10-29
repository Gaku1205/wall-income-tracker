#!/usr/bin/env bash
# CIの確認：pipeline.json の checks（無ければ npm の typecheck・lint・test・build）を順に全部回す。
# 1つ落ちても最後まで回し、どれが落ちたかをまとめて出す（AIが直すときに全部の失敗が見える）。1つでも落ちたら終了コード 1。
# 使い方：run-checks.sh（リポジトリのルートで）
source "$(dirname "$0")/stack.sh"

failed=()
summary=""
while IFS=$'\t' read -r name cmd; do
  [ -z "$cmd" ] && continue
  echo "::group::${name}（${cmd}）"
  if bash -eo pipefail -c "$cmd"; then
    result="✅"
  else
    result="❌"
    failed+=("$name")
    echo "::error title=${name}::「${cmd}」が失敗しました"
  fi
  echo "::endgroup::"
  summary="${summary}| ${result} | ${name} | \`${cmd}\` |"$'\n'
done < <(stack_checks)

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '| | 確認 | コマンド |\n| --- | --- | --- |\n%s' "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
printf '%s' "$summary"
if [ "${#failed[@]}" -gt 0 ]; then
  echo "落ちた確認：${failed[*]}"
  exit 1
fi
echo "確認は全部通りました"
