#!/usr/bin/env bash
# スマホ通知（ntfy）。使い方：notify.sh 種類 "タイトル" "本文" [優先度 1〜5]
# 秘密の NTFY_TOPIC（ntfyアプリで購読するトピック名）が無ければ何もしない。
# 通知に失敗しても、ワークフロー自体は失敗にしない。
#
# 種類（どれを鳴らすかは、リポジトリの Actions の Variable「NOTIFY_EVENTS」にカンマ区切りで書く。
# agent-desk の設定画面から変えられる。無ければ DEFAULT_EVENTS）
#   stuck         止まった（確認が必要）
#   question      企画AIから質問がある
#   hold          ai:hold のPRがマージできる
#   manual        PIPELINE_TOKEN が無いので、次の操作（PR作成・実装の依頼）を人間がする
#   deployed      本番に公開された
#   deploy_failed 公開に失敗した
#   merged        自動でマージした
#   ci_failed     CIが失敗した（AIが直す前）
#   intake        ラベルの無いIssueが受付に拾われないまま放置されていて、見張り役が企画に回した（受付やトークンの不調に気づくため）
#   limit         使用量の上限で待っている（リセット後に自動で再開する。待ちに入った最初の1回だけ）
#   repeat_fail   上限以外の理由で、1時間のうちに2件以上がやり直し待ちになった（仕組みの不調に早く気づくため。2件目のときに1回だけ）
set -uo pipefail
DEFAULT_EVENTS="stuck,question,hold,manual,deployed,deploy_failed,limit,intake,repeat_fail"
event="$1"
shift
events="${NOTIFY_EVENTS:-$DEFAULT_EVENTS}"
if ! printf ',%s,' "$events" | tr -d ' ' | grep -q ",${event},"; then
  echo "通知の種類「${event}」は NOTIFY_EVENTS（${events}）に無いので鳴らしません"
  exit 0
fi
if [ -z "${NTFY_TOPIC:-}" ]; then
  echo "NTFY_TOPIC が設定されていないので通知しません"
  exit 0
fi
if [ -n "${AGENT_DESK_URL:-}" ]; then
  click="${AGENT_DESK_URL}/repos/${GITHUB_REPOSITORY}"
else
  click="https://github.com/${GITHUB_REPOSITORY}"
fi
jq -n \
  --arg topic "$NTFY_TOPIC" \
  --arg title "$1" \
  --arg message "$2" \
  --arg click "$click" \
  --argjson priority "${3:-3}" \
  '{topic: $topic, title: $title, message: $message, click: $click, priority: $priority}' \
  | curl -fsS -X POST -H "Content-Type: application/json" --data-binary @- https://ntfy.sh > /dev/null \
  || echo "通知の送信に失敗しました（作業には影響しません）"
exit 0
