#!/usr/bin/env bash
# 使用量の上限：上限で止まったときは、回数を使わずにリセット後に再開し、待ちに入るとき1回だけ通知する。本物のエラーは回数で止める
source "$(dirname "$0")/lib.sh"
setup_mock
export GITHUB_SERVER_URL=https://github.com GITHUB_RUN_ID=1
now=$(date +%s)
write() { printf '%s' "$2" > "$MOCK_DIR/$1.json"; }

echo "== limit_signal：上限かどうか、リセット時刻が読めるか"
write epoch '[{"type":"result","result":"Claude AI usage limit reached|1761000000"}]'
write noepoch '[{"type":"result","result":"You'"'"'ve hit your limit · resets 3pm (Asia/Tokyo)"}]'
write other '[{"type":"result","subtype":"error_max_turns","result":""}]'
assert_eq "時刻が読める" "1761000000" "$(run_lib "limit_signal '$MOCK_DIR/epoch.json'")"
assert_eq "時刻が読めない" "unknown" "$(run_lib "limit_signal '$MOCK_DIR/noepoch.json'")"
assert_eq "上限ではない" "" "$(run_lib "limit_signal '$MOCK_DIR/other.json'")"
assert_eq "記録が無い" "" "$(run_lib "limit_signal '$MOCK_DIR/none.json'")"

echo "== リセット時刻が分かる上限：時刻まで待つ。回数は使わない。通知は1回"
init_state '{"labels":{"7":["ai:implement"]}}'
until_at=$((now + 3 * 3600))
run_lib "mark_for_retry 7 implement '上限' $until_at" > /dev/null
assert_eq "ai:retry が付く" "ai:implement,ai:retry" "$(labels_of 7)"
assert_contains "リセット時刻が記録される" "$(comments_of 7)" "limit-until=$until_at"
assert_contains "待ちの開始時刻が記録される" "$(comments_of 7)" "limit-first="
assert_contains "回数は0のまま" "$(comments_of 7)" "count=0 kind=implement"
assert_eq "通知は1回" "1" "$(notify_count)"
assert_contains "通知に「使用量の上限」" "$(cat "$MOCK_DIR/curl.log")" "使用量の上限で待っています"
age_retry_comments 600
assert_contains "リセット前は、30分たっても待つ" "$(run_script watchdog.sh)" "まだ早い"
assert_eq "ラベルは変わらない" "ai:implement,ai:retry" "$(labels_of 7)"
set_mark_value limit-until $((now - 120))
out=$(run_script watchdog.sh)
assert_contains "リセットのあとはやり直す" "$out" "implement をやり直します（0/3回目）"
assert_eq "ai:implement だけになる" "ai:implement" "$(labels_of 7)"
assert_contains "回数は0のまま" "$(comments_of 7)" "count=0 kind=implement"
assert_contains "待ちの開始時刻は残る" "$(comments_of 7)" "limit-first="
assert_not_contains "リセット時刻は消える" "$(comments_of 7)" "limit-until"

echo "== 同じ出来事で、また上限に当たっても、通知は増えない"
run_lib "mark_for_retry 7 implement '上限' $((now + 3600))" > /dev/null
assert_eq "通知は1回のまま" "1" "$(notify_count)"

echo "== 上限が何度続いても、回数が減らず ai:stuck にならない"
for _ in 1 2 3 4 5; do
  set_mark_value limit-until $((now - 120))
  run_script watchdog.sh > /dev/null
  run_lib "mark_for_retry 7 implement '上限' $((now + 3600))" > /dev/null
done
assert_not_contains "ai:stuck にならない" "$(labels_of 7)" "ai:stuck"
assert_contains "回数は0のまま" "$(comments_of 7)" "count=0 kind=implement"

echo "== リセット時刻が読めない上限：LIMIT_UNKNOWN_WAIT_MIN（60分）あけてやり直す"
init_state '{"labels":{"8":["ai:implement"]}}'
run_lib "mark_for_retry 8 implement '上限' unknown" > /dev/null
assert_contains "記録は unknown" "$(comments_of 8)" "limit-until=unknown"
age_retry_comments 40
assert_contains "40分では、まだ待つ（普通の30分より長い）" "$(run_script watchdog.sh)" "まだ早い"
age_retry_comments 70
assert_contains "70分でやり直す" "$(run_script watchdog.sh)" "implement をやり直します（0/3回目）"

echo "== 本物のエラーは、今までどおり回数（3回）で人間に回る"
init_state '{"labels":{"9":["ai:implement"]}}'
for _ in 1 2 3; do
  run_lib "mark_for_retry 9 implement 'エラー'" > /dev/null
  age_retry_comments 40
  run_script watchdog.sh > /dev/null
done
run_lib "mark_for_retry 9 implement 'エラー'" > /dev/null
assert_contains "ai:stuck が付く" "$(labels_of 9)" "ai:stuck"

echo "== 上限が24時間以上続いたら、本物のエラーと同じに数える"
init_state '{"labels":{"10":["ai:implement"]}}'
run_lib "mark_for_retry 10 implement '上限' $((now + 3600))" > /dev/null
set_mark_value limit-first $((now - 25 * 3600))
run_lib "mark_for_retry 10 implement '上限' $((now + 3600))" > /dev/null
assert_contains "理由に「時間以上続いて」" "$(comments_of 10)" "時間以上続いています"
assert_not_contains "上限の待ちの印は付かない" "$(comments_of 10)" "limit-until"

echo "== 前の上限の出来事から時間があいていれば、数え直す"
init_state '{"labels":{"11":["ai:implement"]}}'
run_lib "mark_for_retry 11 implement '上限' $((now + 3600))" > /dev/null
before=$(notify_count)
set_mark_value limit-first $((now - 30 * 3600))
state_py "
for c in s['comments']: c['updated_at'] = '$(ago $((30 * 60)))'.replace('Z','Z')
import datetime
for c in s['comments']: c['updated_at'] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=30)).strftime('%Y-%m-%dT%H:%M:%SZ')"
run_lib "mark_for_retry 11 implement '上限' $((now + 3600))" > /dev/null
assert_contains "また上限の待ちとして記録される" "$(comments_of 11)" "limit-until="
assert_eq "新しい出来事なので、通知がもう1回出る" "$((before + 1))" "$(notify_count)"

finish
