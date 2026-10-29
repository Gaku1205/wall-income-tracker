#!/usr/bin/env bash
# 人間が ai:stuck を外したとき：止まった所から自動で続ける（resume.yml から呼ぶ）。
#   PR    → AIに直させる回数をリセットして、いまのCIの状態から続ける
#           （通っていればレビューへ、落ちていれば直す、承認待ちなら動かし直す）
#   Issue → PRがまだなら、企画・実装をやり直す
#
# 環境変数：NUMBER、IS_PR（true/false）、READ_TOKEN（ワークフローのトークン、actions: read）
source "$(dirname "$0")/pipeline-lib.sh"
set -e

has_pipeline_token || { echo "PIPELINE_TOKEN が無いので何もしません"; exit 0; }

# 外されたあとに、また付け直されていたら何もしない
if has_label "$NUMBER" "ai:stuck"; then
  echo "#$NUMBER：ai:stuck がまた付いているので何もしません"
  exit 0
fi

# やり直しの回数もリセットする（記録のコメントがあれば 0 に戻す）
record=$(retry_comment "$NUMBER")
if [ -n "$record" ]; then
  kind=$(printf '%s' "$record" | jq -r .body | sed -nE 's/.*kind=([a-z]+).*/\1/p' | tail -1)
  write_retry_record "$NUMBER" 0 "${kind:-implement}" "人間が再開しました"
fi
remove_label "$NUMBER" "ai:retry"

if [ "$IS_PR" = "true" ]; then
  pr_json=$(gh api "repos/$REPO/pulls/$NUMBER")
  if [ "$(printf '%s' "$pr_json" | jq -r .state)" != "open" ]; then
    echo "PR #$NUMBER は閉じているので何もしません"
    exit 0
  fi
  head=$(printf '%s' "$pr_json" | jq -r .head.sha)
  ref=$(printf '%s' "$pr_json" | jq -r .head.ref)

  # 紐づくIssueの ai:stuck も外す（残っていると順番待ちが進まない）
  issue=$(linked_issue "$NUMBER")
  if [ -n "$issue" ]; then
    remove_label "$issue" "ai:stuck"
  fi

  comment "$NUMBER" "▶ 人間の確認が済んだので、止まった所から自動で続けます（AIに自動で直させる回数もリセットしました）。

${RESUME_MARK}"

  # いまの先頭コミットの「CI」ワークフロー（このResumeや順番待ちなど、ほかのワークフローは数えない）の状態
  ci=$(GH_TOKEN="$READ_TOKEN" gh api "repos/$REPO/actions/runs?head_sha=$head&event=pull_request&per_page=50" \
    -q '[.workflow_runs[] | select(.name == "CI")] | sort_by(.created_at) | last // empty')
  status=$(printf '%s' "$ci" | jq -r '.status // ""')
  conclusion=$(printf '%s' "$ci" | jq -r '.conclusion // ""')

  if [ -z "$ci" ] || [ "$conclusion" = "action_required" ]; then
    # CIが無い／承認待ち。動かし直す
    rerun_ci_if_waiting_approval "$NUMBER" "$head" "$ref"
    echo "PR #$NUMBER：CIが終われば、そこから自動で続きます"
  elif [ "$status" != "completed" ]; then
    echo "PR #$NUMBER：CIが実行中です。終われば、そこから自動で続きます"
  elif [ "$conclusion" = "success" ]; then
    CONCLUSION=success HEAD_SHA="$head" HEAD_BRANCH="$ref" .github/scripts/after-ci.sh
  else
    CONCLUSION=failure HEAD_SHA="$head" HEAD_BRANCH="$ref" RUN_ID="$(printf '%s' "$ci" | jq -r .id)" .github/scripts/after-ci.sh
  fi
else
  state=$(gh api "repos/$REPO/issues/$NUMBER" -q .state)
  [ "$state" = "open" ] || exit 0
  if has_label "$NUMBER" "ai:plan"; then
    remove_label "$NUMBER" "ai:plan"
    add_label "$NUMBER" "ai:plan"
    echo "#$NUMBER：企画をやり直しました"
  elif has_label "$NUMBER" "ai:implement"; then
    if gh api "repos/$REPO/pulls?state=open&per_page=100" -q '.[].head.ref' | grep -q "^claude/issue-${NUMBER}-"; then
      echo "#$NUMBER：PRがあるので、実装はやり直しません"
    else
      remove_label "$NUMBER" "ai:implement"
      add_label "$NUMBER" "ai:implement"
      echo "#$NUMBER：実装をやり直しました"
    fi
  else
    echo "#$NUMBER：やり直す作業のラベルが無いので、何もしません"
  fi
fi
