#!/usr/bin/env bash
# レビューAIが終わったあと：
#   指摘なし → CIも全部通っていれば自動でマージ（ai:hold が付いていたら、マージは人間に任せて通知）
#   指摘あり → AIに直させる（上限を超えたら人間に回す）
#
# 環境変数：CONCLUSION、HEAD_SHA、HEAD_BRANCH、READ_TOKEN（ワークフローのトークン）
source "$(dirname "$0")/pipeline-lib.sh"
set -e

has_pipeline_token || { echo "PIPELINE_TOKEN が無いので何もしません"; exit 0; }

read -r pr head < <(find_open_pr "$HEAD_BRANCH") || true
if [ -z "${pr:-}" ]; then
  echo "openのPRがありません"
  exit 0
fi
if [ "$head" != "$HEAD_SHA" ]; then
  echo "レビューのあとに新しいコミットが来ているので、何もしません"
  exit 0
fi
if has_label "$pr" "ai:stuck"; then
  echo "人間の確認待ち（ai:stuck）なので、何もしません"
  exit 0
fi

if [ "$CONCLUSION" != "success" ]; then
  # 使用量の上限などの一時的な失敗かもしれないので、人間に回す前に自動でやり直す（watchdog.sh）
  mark_for_retry "$pr" review "$(failure_reason "レビューAIがエラーで止まりました（ログは、レビューAIの実行の方を見てください）")"
  exit 0
fi

# いまの先頭コミットのあとに書かれた、最新のレビュー結果（「## Code review」で始まる）を探す。
# まとめのコメントは、レビューAIが gh で書くので github-actions[bot] の名前で付く（行への指摘は claude[bot]）。
# 「この実行で書かれた物」ではなく「先頭コミットより新しい物」を見る
head_date=$(gh api "repos/$REPO/commits/$HEAD_SHA" -q .commit.committer.date)
review=$(all_comments "$pr" | jq -r --arg since "$head_date" \
  'map(select((.user.login == "claude[bot]" or .user.login == "github-actions[bot]") and (.body | startswith("## Code review")) and .created_at >= $since)) | last | .body // ""')

# 指摘があるとき、レビューAIはまとめのコメントを書かず、コードの行への指摘（インラインコメント）だけを残すことがある。
# 数えるのは、この回のレビューで書かれた行への指摘だけ。PRの説明だけを直したときは先頭コミットが変わらないので、
# 前の回の行への指摘も同じコミットに付いたまま残る（それを数えると、直ったのにまた直すよう頼んでしまう）。
#   この回の区切り：最新のまとめがこの回の物なら、その1つ前のまとめの時刻。まとめが無ければ、最後のまとめの時刻
cutoff=$(all_comments "$pr" | jq -r --arg has "$([ -n "$review" ] && echo 1)" \
  '[.[] | select((.user.login == "claude[bot]" or .user.login == "github-actions[bot]") and (.body | startswith("## Code review"))) | .created_at] | sort
   | if $has == "1" then (.[-2] // "") else (.[-1] // "") end')
inline=$(gh api "repos/$REPO/pulls/$pr/comments?per_page=100" --paginate --slurp \
  | jq --arg sha "$HEAD_SHA" --arg cut "$cutoff" 'add // [] | map(select(.user.login == "claude[bot]" and .original_commit_id == $sha and .created_at > $cut)) | length')

if [ "$inline" -gt 0 ] || { [ -n "$review" ] && ! printf '%s' "$review" | grep -q "No issues found"; }; then
  request_fix_or_stop "$pr" "$HEAD_SHA" "レビューで指摘がありました。このPRの「Code review」のコメントと、コードの行に付いた指摘を読んで直してください。指摘が間違っていると判断した場合は、直さずにその理由をこのPRにコメントしてください。"
  echo "PR #$pr：指摘があったので直すよう依頼しました（行への指摘 ${inline} 件）"
  exit 0
fi

# 画像など、文字で読めない変更だけのPR（README のスクショの撮り直しなど）は、レビューAIに読む差分が無く、
# 結果のコメントを書かずに終わる。そのときは、指摘なしとして進める。
# 「文字で読めない」＝差分（patch）が無く、変更の行数も 0。大きすぎて patch が省かれた文字のファイルは、行数があるので含めない
if [ -z "$review" ]; then
  if kinds=$(gh api "repos/$REPO/pulls/$pr/files?per_page=100" --paginate     -q '.[] | if (.patch == null and (.changes // 0) == 0) then "binary" else "text" end')     && [ -n "$kinds" ] && ! printf '%s\n' "$kinds" | grep -q '^text$'; then
    comment "$pr" "画像など、文字で読めない変更だけなので、レビューする差分がありません。指摘なしとして進めます。" || true
    review="No issues found"
    echo "PR #$pr：文字で読めない変更だけなので、指摘なしとして進めます"
  fi
fi
if [ -z "$review" ]; then
  # レビューAIが、エラーにならずに何も書かずに終わることがある（一時的な不調）。2回までは自動でやり直し、続くなら人間に回す
  if [ "$(retry_count "$pr")" -lt 2 ]; then
    mark_for_retry "$pr" review "レビューAIが、結果のコメントを書かずに終わりました"
  else
    stop_for_human "$pr" "レビューAIの結果のコメントが見つかりませんでした（自動のやり直しでも書かれませんでした）"
  fi
  exit 0
fi

# CI（レビュー以外のチェック）が全部通っているか、もう一度確かめる
# チェックの読み取りはワークフロー自身のトークン（checks: read）で行う（PIPELINE_TOKEN に Checks の権限は付けていない）
checks=$(GH_TOKEN="$READ_TOKEN" gh api "repos/$REPO/commits/$HEAD_SHA/check-runs?per_page=100" \
  -q '[.check_runs[] | select(.name != "review")]')
actions_count=$(printf '%s' "$checks" | jq '[.[] | select(.app.slug == "github-actions")] | length')
not_ok=$(printf '%s' "$checks" | jq '[.[] | select(.status != "completed" or (.conclusion | IN("success", "neutral", "skipped") | not))] | length')
if [ "$actions_count" -eq 0 ] || [ "$not_ok" -gt 0 ]; then
  echo "CIがまだ全部通っていないので、マージしません（CIが終わればもう一度レビューから進みます）"
  exit 0
fi

title=$(issue_title "$pr")
# 仕組みそのもの（.github/・docs/pipeline.md・CLAUDE.md・AGENTS.md・pipeline.json）を変えるPRは、AIの判断だけでは自動でマージしない。
# 普通のIssue（アプリの作業）は今までどおり全自動。これらを触るPRだけ、マージを人間に任せて通知する
# 変更ファイルの一覧を取れなかったら、マージせずに再試行へ回す（取れないまま「該当なし」と扱って自動でマージしない）
if ! files=$(gh api "repos/$REPO/pulls/$pr/files?per_page=100" --paginate -q '.[].filename'); then
  mark_for_retry "$pr" review "変更ファイルの一覧を取得できませんでした（APIエラーなどの可能性）"
  exit 0
fi
# ai-dev-template 自身（main の CLAUDE.md に「pipeline-self-edit: auto」の印がある）は、スクリプト・テスト・docs/pipeline.md の変更を自動でマージしてよい。
# ワークフロー・実行環境の部品（.github/actions/）・CLAUDE.md・AGENTS.md・pipeline.json（AIの許可とルール。pipeline.json の checks はAIに許すコマンドになる）は、どのリポジトリでも人間に任せる。印は main の物を見るので、PRの変更で印を足してもすり抜けられない
hold_pattern='^(\.github/|docs/pipeline\.md$|CLAUDE\.md$|AGENTS\.md$|pipeline\.json$)'
if grep -q 'pipeline-self-edit: auto' "${CLAUDE_MD:-$(dirname "$0")/../../CLAUDE.md}" 2> /dev/null; then
  hold_pattern='^(\.github/workflows/|\.github/actions/|CLAUDE\.md$|AGENTS\.md$|pipeline\.json$)'
fi
if printf '%s\n' "$files" | grep -qE "$hold_pattern"; then
  # ai:hold を付けておく（画面で「マージ待ち（人間）」と分かる。人間がマージするまで、自動ではマージされない）
  has_label "$pr" "ai:hold" || add_label "$pr" "ai:hold" || true
  notify hold "マージできます" "PR #${pr} ${title}：CIもレビューもOK。パイプライン自体を変えるPRなので、マージはあなたが押してください" 4
  echo "PR #$pr：パイプライン自体を変えるので、自動でマージしません"
  exit 0
fi
if has_label "$pr" "ai:hold"; then
  notify hold "マージできます" "PR #${pr} ${title}：CIもレビューもOK。ai:hold なのでマージはあなたが押してください" 4
  exit 0
fi

merge_or_handle "$pr" "$HEAD_SHA" review || exit 0
notify merged "マージしました" "PR #${pr} ${title}：CIもレビューもOKだったので自動でマージしました" 2
# 使い終わったブランチを消す（リポジトリの「Automatically delete head branches」が先に消していても構わない）
delete_branch_if_ai "$HEAD_BRANCH"
echo "PR #$pr：自動でマージしました（次の順番待ちは、Issueが閉じたときに queue.yml が始める）"
