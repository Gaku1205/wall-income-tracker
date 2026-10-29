#!/usr/bin/env bash
# ai-dev-template の .github と docs/pipeline.md を、アプリのリポジトリへ配る。
# 使い方: sync-to-apps.sh owner/repo [owner/repo ...]
# 必要な環境変数: GH_TOKEN（配る先に push と PR 作成ができる鍵。ワークフローも配るので Workflows 権限が要る）
# 配り先の main には直接入れず、PR（ブランチ pipeline-sync/<sha>）を作る。配り先の CI が通ったら after-ci.sh がマージする。
# 配る先に .github/sync-keep があれば、そこに書かれたファイル名（1行1つ）は消さずに残す。
# CLAUDE.md / AGENTS.md / docs/spec.md / docs/design.md は配らない。
set -euo pipefail

src_root="$(cd "$(dirname "$0")/../.." && pwd)"
src_sha="$(git -C "$src_root" rev-parse --short HEAD)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

for repo in "$@"; do
  echo "== $repo"
  dir="$work/${repo//\//_}"
  if ! git clone -q --depth 1 "https://x-access-token:${GH_TOKEN}@github.com/${repo}.git" "$dir"; then
    echo "::error::$repo を取得できません"; fail=1; continue
  fi
  # テンプレート本体だけの物（配り先では動かない）：工場のIssueの雛形と、デザイン部門だけが読む参考（大きいので配らない）
  excludes=(--exclude=sync-keep --exclude=sync-targets --exclude=ISSUE_TEMPLATE/new-service.yml --exclude=factory/references/)
  if [ -f "$dir/.github/sync-keep" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] && excludes+=("--exclude=$name")
    done < "$dir/.github/sync-keep"
  fi
  rsync -a --delete "${excludes[@]}" "$src_root/.github/" "$dir/.github/"
  mkdir -p "$dir/docs"
  cp "$src_root/docs/pipeline.md" "$dir/docs/pipeline.md"
  # 共通のスキル（.claude/skills/）も配る。配り先だけのスキルは消さない（同じ名前の物だけ上書き）
  if [ -d "$src_root/.claude/skills" ]; then
    mkdir -p "$dir/.claude/skills"
    cp -R "$src_root/.claude/skills/." "$dir/.claude/skills/"
  fi

  if [ -z "$(git -C "$dir" status --porcelain)" ]; then
    echo "変更なし"; continue
  fi
  # main には直接 push しない（main の保護で、App は CI を通らないコミットを入れられない）。
  # ブランチに push して PR を作り、配り先の CI が通ったら進行役（after-ci.sh）がマージする
  branch="pipeline-sync/${src_sha}"
  git -C "$dir" checkout -q -b "$branch"
  git -C "$dir" add -A
  git -C "$dir" -c user.name="pipeline-sync" -c user.email="noreply@github.com" \
    commit -q -m "パイプラインの更新を ai-dev-template から取り込む（${src_sha}）"
  if ! git -C "$dir" push -q -f origin "HEAD:refs/heads/$branch"; then
    echo "::error::$repo へ push できません（App が入っているか、Contents・Workflows の権限を確認）"; fail=1; continue
  fi
  # 前の配布のPRがまだ開いていたら、新しい物に置き換える
  gh api "repos/$repo/pulls?state=open&per_page=100" --jq '.[] | select(.head.ref | startswith("pipeline-sync/")) | "\(.number) \(.head.ref)"' \
    | while read -r old_pr old_branch; do
        [ "$old_branch" = "$branch" ] && continue
        gh api -X PATCH "repos/$repo/pulls/$old_pr" -f state=closed > /dev/null && echo "古い配布のPR #$old_pr を閉じました"
        gh api -X DELETE "repos/$repo/git/refs/heads/$old_branch" > /dev/null 2>&1 || true
      done
  if gh api "repos/$repo/pulls?state=open&head=${repo%%/*}:$branch" --jq 'length' | grep -qx 0; then
    gh api "repos/$repo/pulls" -f title="パイプラインの更新を取り込む（${src_sha}）" -f head="$branch" -f base=main \
      -f body="ai-dev-template の main（${src_sha}）で CI が通ったパイプラインの更新（\`.github/\` と \`docs/pipeline.md\`）です。このリポジトリの CI が通ったら、進行役が自動でマージします。<!-- pipeline-sync -->" > /dev/null \
      && echo "配った（PR）: $repo" || { echo "::error::$repo にPRを作れません"; fail=1; }
  else
    echo "配った（PRを更新）: $repo"
  fi
done
exit "$fail"
