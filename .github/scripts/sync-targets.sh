#!/usr/bin/env bash
# 配り先を決めて、1行に1つ（owner/repo）出す。sync.yml から呼ぶ。
#   1. .github/sync-targets に書いた物（テンプレートより前からあるリポジトリなど）
#   2. このテンプレートから作られ、パイプラインの鍵で見えるリポジトリ（自動。新しいアプリを作っても書き足さなくてよい）
#   sync-targets に「!owner/repo」と書いた物は、どちらで見つかっても配らない。本体自身とアーカイブ済みは配らない
# 使い方：sync-targets.sh [sync-targets のパス]
# 環境変数：GITHUB_REPOSITORY（本体）、GH_TOKEN（App の鍵か PIPELINE_TOKEN）
set -euo pipefail

file="${1:-.github/sync-targets}"
self="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY が要ります}"
listed=()
skip=()
if [ -f "$file" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [ -z "$line" ] && continue
    case "$line" in
      '!'*) skip+=("${line#!}") ;;
      *) listed+=("$line") ;;
    esac
  done < "$file"
fi

# 候補：App の鍵なら、App を入れたリポジトリ。PIPELINE_TOKEN（個人の鍵）なら、オーナーのリポジトリ
if ! candidates=$(gh api --paginate "installation/repositories?per_page=100" \
  -q '.repositories[] | select(.archived | not) | .full_name' 2> /dev/null); then
  candidates=$(gh api --paginate "users/${self%%/*}/repos?per_page=100&type=owner" \
    -q '.[] | select(.archived | not) | .full_name' 2> /dev/null) || candidates=""
fi

auto=()
while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  [ "${repo,,}" = "${self,,}" ] && continue
  # 一覧には「どのテンプレートから作ったか」が無いので、1つずつ見る（リポジトリの数だけ呼ぶ）
  from=$(gh api "repos/$repo" -q '.template_repository.full_name // ""' 2> /dev/null) || continue
  if [ -n "$from" ] && [ "${from,,}" = "${self,,}" ]; then
    auto+=("$repo")
    echo "自動で見つけた配り先：$repo（$self から作ったリポジトリ）" >&2
  fi
done <<< "$candidates"

skipped() {
  local s
  for s in "${skip[@]}"; do
    [ "${s,,}" = "${1,,}" ] && return 0
  done
  return 1
}

printf '%s\n' "${listed[@]}" "${auto[@]}" | awk 'NF' | sort -fu | while IFS= read -r repo; do
  [ "${repo,,}" = "${self,,}" ] && continue
  if skipped "$repo"; then
    echo "配らない：$repo（sync-targets の ! 指定）" >&2
    continue
  fi
  echo "$repo"
done
