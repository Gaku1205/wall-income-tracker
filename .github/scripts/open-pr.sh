#!/usr/bin/env bash
# 実装AIのあと：ブランチ claude/issue-<番号>-... から main へのPRを自動で作る。
# PRの本文は、実装AIがIssueに書いた「Create PR」リンクの中身を使う（無ければ Closes #番号 だけ）。
#
# 環境変数：ISSUE（番号）、ISSUE_TITLE、AI_OUTCOME（実装AIの結果 success/failure）、EXECUTION_FILE（AIの実行記録。失敗の原因の分類に使う）
source "$(dirname "$0")/pipeline-lib.sh"
set -e

if ! has_pipeline_token; then
  # トークンが無い間は、今までどおり人間がPRを作る
  if [ "$AI_OUTCOME" = "success" ]; then
    notify manual "PRを作れます" "#${ISSUE} ${ISSUE_TITLE}：AIの作業が終わりました" 4
  else
    notify manual "AIが止まりました" "#${ISSUE} ${ISSUE_TITLE}：結果を確認してPRを作ってください" 4
  fi
  exit 0
fi

# いちばん新しいコミットがある claude/issue-<番号>- ブランチを探す
branch=""
latest=""
for b in $(gh api "repos/$REPO/branches?per_page=100" --paginate -q ".[].name | select(startswith(\"claude/issue-${ISSUE}-\"))"); do
  date=$(gh api "repos/$REPO/branches/$b" -q .commit.commit.committer.date)
  if [[ "$date" > "$latest" ]]; then
    latest="$date"
    branch="$b"
  fi
done

# 実装AIがエラーで終わって何も作れなかったときは、使用量の上限などの一時的な失敗かもしれないので、
# 人間に回す前に自動でやり直す（watchdog.sh）。AIが正常に終わったのに変更が無いときは、AIの判断なので人間に回す
if [ -z "$branch" ]; then
  if [ "$AI_OUTCOME" != "success" ]; then
    handle_ai_failure "$ISSUE" implement "実装AIが途中で止まり、変更が作られませんでした" "${EXECUTION_FILE:-}"
  else
    add_label "$ISSUE" "ai:stuck" || true
    notify stuck "AIが止まりました" "#${ISSUE} ${ISSUE_TITLE}：変更が作られませんでした。Issueのコメントを確認してください" 4
  fi
  exit 0
fi

ahead=$(gh api "repos/$REPO/compare/main...$branch" -q .ahead_by)
if [ "${ahead:-0}" -eq 0 ]; then
  if [ "$AI_OUTCOME" != "success" ]; then
    handle_ai_failure "$ISSUE" implement "実装AIが途中で止まり、ブランチに変更がありません" "${EXECUTION_FILE:-}"
  else
    add_label "$ISSUE" "ai:stuck" || true
    notify stuck "AIが止まりました" "#${ISSUE} ${ISSUE_TITLE}：ブランチに変更がありません" 4
  fi
  exit 0
fi

existing=$(find_open_pr "$branch" || true)
if [ -n "$existing" ]; then
  echo "PRはもうあります：$existing"
  remove_label "$ISSUE" "ai:retry"
  exit 0
fi

# 実装AIの最後のコメントの「Create PR」リンクから、本文を取り出す
comment=$(all_comments "$ISSUE" | jq -r 'map(select(.user.login == "claude[bot]")) | last | .body // ""')
body=$(printf '%s' "$comment" | python3 -c '
import re, sys, urllib.parse
text = sys.stdin.read()
m = re.search(r"quick_pull=1[^)\s]*", text)
if m:
    q = urllib.parse.parse_qs(m.group(0))
    print(q.get("body", [""])[0])
')
if ! printf '%s' "$body" | grep -qiE "(close[sd]?|fix(e[sd])?|resolve[sd]?) #${ISSUE}\b"; then
  body="Closes #${ISSUE}

${body}"
fi
body="${body}

---
_実装AIの作業が終わったので、自動で作ったPRです。CIが通るとレビューAIが確認し、問題がなければ自動でマージします。_"

created=$(gh api "repos/$REPO/pulls" -f title="$ISSUE_TITLE" -f head="$branch" -f base=main -f body="$body" -q .html_url)
echo "PRを作りました：$created"
remove_label "$ISSUE" "ai:retry"

if [ "$AI_OUTCOME" != "success" ]; then
  echo "実装AIは途中で止まりましたが（作業回数の上限など）、変更があるのでPRにしました。CIで確かめます"
fi
