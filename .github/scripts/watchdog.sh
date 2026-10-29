#!/usr/bin/env bash
# 見張り役（watchdog.yml が、定期的に・ほかのワークフローが終わるたびに動かす）：パイプラインが止まったまま動かなくなっていないか見て、自動で再開させる。
#   1. ai:retry が付いた物（使用量の上限・AIのエラーで止まった物）を、待ち時間が過ぎていたらやり直す
#   2. 失敗の知らせも無いまま止まっている物（時間切れなど）を見つけて、ai:retry を付ける
#   3. CIが「承認待ち」で止まっている物を動かし直す
#   4. ラベルが無いまま放置されたIssueを企画（ai:plan）に回す
#   5. 使い終わった claude/* ブランチを掃除する
#   6. ラベルの矛盾（ai:queue と ai:implement など）を直す
#   7. 順番待ち（ai:queue）を進める
#   8. 次のやり直しの時刻に、自分を起こす目覚まし（retry-timer.yml）をかける
# 人間の確認待ち（ai:stuck）の物は触らない。
#
# 環境変数：READ_TOKEN（ワークフローのトークン、actions: write。CIの実行を読む・目覚ましを動かす）、RETRY_TIMER（off で目覚ましを使わない）
source "$(dirname "$0")/pipeline-lib.sh"

has_pipeline_token || { echo "PIPELINE_TOKEN が無いので何もしません"; exit 0; }

# これだけ何の動きも無ければ「止まっている」とみなす（分）
IDLE_PLAN_MIN="${IDLE_PLAN_MIN:-30}"
IDLE_IMPLEMENT_MIN="${IDLE_IMPLEMENT_MIN:-45}"
IDLE_REVIEW_MIN="${IDLE_REVIEW_MIN:-30}"
IDLE_CI_MIN="${IDLE_CI_MIN:-5}"

now=$(date +%s)
idle_min() {
  echo $(( (now - $(date -d "$1" +%s)) / 60 ))
}

open_prs=$(gh api "repos/$REPO/pulls?state=open&per_page=100")
# 実装AIのブランチ（claude/issue-N-...）のPRがopenであるか
has_open_pr_for_issue() {
  printf '%s' "$open_prs" | jq -e --arg p "claude/issue-$1-" 'any(.[]; .head.ref | startswith($p))' > /dev/null
}

# ---- 1. ai:retry が付いた物をやり直す ----
handled=" "   # この実行でやり直した番号（同じ実行で、すぐ次の確認に引っかからないように）
for n in $(gh api "repos/$REPO/issues?state=open&per_page=100&labels=ai%3Aretry" -q '.[].number'); do
  if has_label "$n" "ai:stuck"; then
    remove_label "$n" "ai:retry"
    continue
  fi
  retry_due "$n" || { echo "#$n：やり直すにはまだ早いです"; continue; }

  record=$(retry_comment "$n")
  # やり直しの記録が無い物は、ここでは触らない（3.9 が ai:stuck にして人間に回す）
  [ -z "$record" ] && continue
  body=$(printf '%s' "$record" | jq -r .body)
  kind=$(printf '%s' "$body" | sed -nE 's/.*kind=([a-z]+).*/\1/p' | tail -1)
  reason=$(printf '%s' "$body" | sed -nE 's/^理由：(.*)$/\1/p' | head -1)
  count=$(retry_count "$n")
  next=$((count + 1))
  # 使用量の上限で待っていたぶんは、やり直しの回数を使わない（上限の待ちを始めた時刻は、次の失敗のために残す）
  limit_first=$(retry_mark_value "$body" limit-first)
  if [ -n "$(retry_mark_value "$body" limit-until)" ]; then
    next=$count
  fi
  echo "#$n：${kind} をやり直します（${next}/${MAX_RETRY}回目）"
  handled="${handled}${n} "

  case "$kind" in
    plan)
      write_retry_record "$n" "$next" "$kind" "$reason" "" "$limit_first"
      remove_label "$n" "ai:retry"
      remove_label "$n" "ai:plan"
      add_label "$n" "ai:plan"
      ;;
    implement)
      write_retry_record "$n" "$next" "$kind" "$reason" "" "$limit_first"
      remove_label "$n" "ai:retry"
      if has_open_pr_for_issue "$n"; then
        echo "#$n：PRができているので、実装はやり直しません"
      else
        remove_label "$n" "ai:implement"
        add_label "$n" "ai:implement"
      fi
      ;;
    review)
      write_retry_record "$n" "$next" "$kind" "$reason" "" "$limit_first"
      remove_label "$n" "ai:retry"
      remove_label "$n" "ai:review"
      add_label "$n" "ai:review"
      ;;
    mention)
      pr_json=$(gh api "repos/$REPO/pulls/$n")
      head=$(printf '%s' "$pr_json" | jq -r .head.sha)
      # 前回の依頼の文を、そのままもう一度出す（印のコメント行は除く）
      last_request=$(all_comments "$n" | jq -r 'map(select(.body | test("<!-- auto-fix(-retry)? -->"))) | last | .body // ""')
      request=$(printf '%s' "$last_request" | sed -e '/^<!--/d' -e '/^（前回は応答がなかったので/d')
      model_mark=""
      if printf '%s' "$last_request" | grep -q 'auto-fix-model: opus'; then
        model_mark="
<!-- auto-fix-model: opus -->"
      fi
      write_retry_record "$n" "$next" "$kind" "$reason" "" "$limit_first"
      remove_label "$n" "ai:retry"
      comment "$n" "${request}

（前回は応答がなかったので、同じ依頼をもう一度出します。自動のやり直し ${next}/${MAX_RETRY}）

<!-- auto-fix-retry -->
<!-- auto-fix-sha: ${head} -->
<!-- auto-fix-body: $(pr_body_hash "$n") -->${model_mark}"
      ;;
    *)
      echo "#$n：やり直しの種類が分からないので、印だけ外します"
      remove_label "$n" "ai:retry"
      ;;
  esac
done

# ---- 2. 失敗の知らせも無いまま止まっている物 ----
# 企画AI：ai:plan が付いたまま動きが無い
for n in $(gh api "repos/$REPO/issues?state=open&per_page=100&labels=ai%3Aplan" -q '.[] | select(.pull_request | not) | .number'); do
  case "$handled" in *" $n "*) continue ;; esac
  has_label "$n" "ai:stuck" && continue
  has_label "$n" "ai:retry" && continue
  m=$(idle_min "$(gh api "repos/$REPO/issues/$n" -q .updated_at)")
  [ "$m" -lt "$IDLE_PLAN_MIN" ] && continue
  mark_for_retry "$n" plan "企画AIの終了が確認できないまま${m}分たちました"
done

# 実装AI：ai:implement が付いたまま、PRもできず動きが無い
for n in $(gh api "repos/$REPO/issues?state=open&per_page=100&labels=ai%3Aimplement" -q '.[] | select(.pull_request | not) | .number'); do
  case "$handled" in *" $n "*) continue ;; esac
  has_label "$n" "ai:stuck" && continue
  has_label "$n" "ai:retry" && continue
  has_open_pr_for_issue "$n" && continue
  m=$(idle_min "$(gh api "repos/$REPO/issues/$n" -q .updated_at)")
  [ "$m" -lt "$IDLE_IMPLEMENT_MIN" ] && continue
  mark_for_retry "$n" implement "実装AIの終了が確認できないまま${m}分たちました"
done

# PRごとの確認
for pr in $(printf '%s' "$open_prs" | jq -r '.[].number'); do
  case "$handled" in *" $pr "*) continue ;; esac
  has_label "$pr" "ai:stuck" && continue
  pr_json=$(printf '%s' "$open_prs" | jq -c --argjson n "$pr" '.[] | select(.number == $n)')
  head=$(printf '%s' "$pr_json" | jq -r .head.sha)
  ref=$(printf '%s' "$pr_json" | jq -r .head.ref)
  m=$(idle_min "$(printf '%s' "$pr_json" | jq -r .updated_at)")

  # ---- 3. CIが承認待ちで止まっている ----
  if [ "$m" -ge "$IDLE_CI_MIN" ]; then
    runs=$(GH_TOKEN="$READ_TOKEN" gh api "repos/$REPO/actions/runs?head_sha=$head&event=pull_request&per_page=50" \
      -q '[.workflow_runs[] | select(.name == "CI")]')
    waiting=$(printf '%s' "$runs" | jq '[.[] | select(.conclusion == "action_required")] | length')
    running=$(printf '%s' "$runs" | jq '[.[] | select(.conclusion != "action_required")] | length')
    if [ "$waiting" -gt 0 ] && [ "$running" -eq 0 ]; then
      rerun_ci_if_waiting_approval "$pr" "$head" "$ref"
      continue
    fi
  fi

  # レビューAI：ai:review を付けたのに結果が出ないまま止まっている
  if has_label "$pr" "ai:review" && ! has_label "$pr" "ai:retry" && [ "$m" -ge "$IDLE_REVIEW_MIN" ]; then
    head_date=$(gh api "repos/$REPO/commits/$head" -q .commit.committer.date)
    reviewed=$(all_comments "$pr" | jq --arg since "$head_date" \
      '[.[] | select((.user.login == "claude[bot]" or .user.login == "github-actions[bot]") and (.body | startswith("## Code review")) and .created_at >= $since)] | length')
    if [ "$reviewed" -eq 0 ]; then
      mark_for_retry "$pr" review "レビューAIの結果が出ないまま${m}分たちました"
    fi
  fi
done

# ---- 3.5 ラベルが無いまま放置されたIssueを、企画に回す（受付 intake.yml が動かなかったとき・ai:skip を外したとき） ----
for n in $(gh api "repos/$REPO/issues?state=open&per_page=100" -q '.[] | select(.pull_request | not) | .number'); do
  case "$handled" in *" $n "*) continue ;; esac
  m=$(idle_min "$(gh api "repos/$REPO/issues/$n" -q .updated_at)")
  [ "$m" -lt "${IDLE_INTAKE_MIN:-10}" ] && continue
  needs_intake "$n" || continue
  add_label "$n" "ai:plan"
  echo "#$n：ラベルが無いまま${m}分たったので、企画に回しました"
  # 受付（intake.yml）が拾えなかったということ。Secretsやトークンの期限切れなどに気づけるように知らせる
  notify intake "頼まれていないIssueがありました" "#${n} $(issue_title "$n")：ラベルが無いまま${m}分たったので、企画に回しました（受付が動いていないかもしれません。Secretsとトークンの期限を確認してください）" 3
done

# ---- 3.8 使い終わった claude/* ブランチを掃除する ----
# 開いているPRが無く、最後のコミットから2日以上たった物だけ（作業中の物は消さない）。1回に消すのは20本まで
cleaned=0
for b in $(gh api "repos/$REPO/branches?per_page=100" --paginate -q '.[].name | select(startswith("claude/"))'); do
  [ "$cleaned" -ge 20 ] && break
  if printf '%s' "$open_prs" | jq -e --arg b "$b" 'any(.[]; .head.ref == $b)' > /dev/null; then
    continue
  fi
  last=$(gh api "repos/$REPO/branches/$b" -q .commit.commit.committer.date 2> /dev/null) || continue
  [ "$(idle_min "$last")" -lt $(( 2 * 24 * 60 )) ] && continue
  delete_branch_if_ai "$b"
  cleaned=$(( cleaned + 1 ))
done

# ---- 3.9 ラベルの矛盾を直す（人が手でラベルを付け外ししたとき） ----
# 直したら、その Issue・PR に1行コメントする。矛盾が無ければ何もしない。1回に直すのは、Issue と PR を合わせて20件まで
fixed=0
fix_labels() { # 番号 コメント 外すラベル...
  local num="$1" msg="$2" l
  shift 2
  for l in "$@"; do remove_label "$num" "$l"; done
  comment "$num" "🔧 ${msg}（見張り役がラベルの矛盾を直しました）"
  echo "#$num：${msg}"
  fixed=$(( fixed + 1 ))
}
open_items=$(gh api "repos/$REPO/issues?state=open&per_page=100" -q '.[] | [.number, ([.labels[].name] | join(","))] | @tsv')
while IFS=$'\t' read -r n labels; do
  [ -z "$n" ] && continue
  [ "$fixed" -ge 20 ] && break
  case ",$labels," in
    *,ai:implement,*)
      case ",$labels," in
        *,ai:queue,*) fix_labels "$n" "ai:queue と ai:implement が両方付いていたので、ai:queue を外しました" ai:queue; continue ;;
      esac
      case ",$labels," in
        *,ai:plan,*) fix_labels "$n" "ai:plan と ai:implement が両方付いていたので、ai:plan を外しました" ai:plan; continue ;;
      esac
      ;;
  esac
  case ",$labels," in
    *,ai:retry,*)
      if [ -z "$(retry_comment "$n")" ]; then
        fix_labels "$n" "ai:retry が付いていますが、やり直しの記録が無いので、ai:retry を外して ai:stuck にしました。人間が確認してください" ai:retry
        add_label "$n" "ai:stuck"
      fi
      ;;
  esac
done <<< "$open_items"

# 閉じた物（直近7日に閉じた物だけ）に、ai:stuck・ai:retry・ai:queue が残っている
since=$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)
closed_items=$(gh api "repos/$REPO/issues?state=closed&since=${since}&per_page=100" \
  -q ".[] | select(.closed_at != null and .closed_at >= \"$since\") | [.number, ([.labels[].name] | join(\",\"))] | @tsv")
while IFS=$'\t' read -r n labels; do
  [ -z "$n" ] && continue
  [ "$fixed" -ge 20 ] && break
  stale=()
  for l in ai:stuck ai:retry ai:queue; do
    case ",$labels," in *,"$l",*) stale+=("$l") ;; esac
  done
  [ "${#stale[@]}" -eq 0 ] && continue
  fix_labels "$n" "閉じているのに ${stale[*]} が残っていたので、外しました" "${stale[@]}"
done <<< "$closed_items"

# ---- 4. 順番待ちを進める ----
start_next_in_queue || echo "順番待ちを進められませんでした"

# ---- 8. 次のやり直しの時刻に、見張り役を起こす目覚ましをかける ----
# GitHub の定期の起動（30分ごと）は、混んでいると数時間遅れる。待ちが明ける時刻が分かっているので、
# その時刻に retry-timer.yml（待ってから見張り役を動かすだけ）を動かしておく。目覚ましは1つだけ（新しい物が古い物を止める）。
# 公開していないリポジトリでは待つあいだも Actions の時間を使うので、変数 RETRY_TIMER に off を入れれば止められる
set_retry_timer() {
  local earliest="" n t now_s runs
  [ "${RETRY_TIMER:-on}" = "off" ] && return 0
  now_s=$(date +%s)
  for n in $(gh api "repos/$REPO/issues?state=open&per_page=100&labels=ai%3Aretry" -q '.[].number'); do
    has_label "$n" "ai:stuck" && continue
    t=$(retry_due_at "$n")
    [ "$t" -gt "$now_s" ] || continue
    if [ -z "$earliest" ] || [ "$t" -lt "$earliest" ]; then earliest="$t"; fi
  done
  [ -z "$earliest" ] && return 0
  # 1回の待ちは最大 RETRY_TIMER_MAX_MIN 分（ジョブの時間の上限 6時間に収める）。それより先なら、起きた見張り役がかけ直す
  local cap=$(( now_s + ${RETRY_TIMER_MAX_MIN:-340} * 60 ))
  [ "$earliest" -gt "$cap" ] && earliest="$cap"
  # もう同じかそれより早い時刻の目覚ましが待っていれば、かけ直さない
  runs=$(GH_TOKEN="$READ_TOKEN" gh api "repos/$REPO/actions/workflows/retry-timer.yml/runs?per_page=20" \
    -q '[.workflow_runs[] | select(.status != "completed") | .display_title | capture("目覚まし (?<at>[0-9]+)") | .at | tonumber]' 2> /dev/null) || runs="[]"
  if printf '%s' "${runs:-[]}" | jq -e --argjson e "$earliest" --argjson n "$now_s" 'any(.[]; . > $n and . <= $e + 120)' > /dev/null 2>&1; then
    echo "次のやり直しの目覚ましは、もうかかっています"
    return 0
  fi
  if GH_TOKEN="$READ_TOKEN" gh api -X POST "repos/$REPO/actions/workflows/retry-timer.yml/dispatches" \
       -f ref="${GITHUB_REF_NAME:-main}" -f "inputs[at]=$earliest" > /dev/null 2>&1; then
    echo "次のやり直しの目覚ましを $(TZ=Asia/Tokyo date -d "@$earliest" +%H:%M) にかけました"
  else
    echo "::warning::やり直しの目覚まし（retry-timer.yml）を動かせませんでした。定期の見張りでやり直します"
  fi
}
set_retry_timer
