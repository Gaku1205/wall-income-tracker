#!/usr/bin/env bash
# 自動のやり直し：失敗の印 → 待ち時間 → 見張り役がやり直す → 上限で人間に回す
source "$(dirname "$0")/lib.sh"
setup_mock

echo "== 実装AIが止まる → 待ち時間のあいだはやり直さない → 過ぎたらやり直す（回数が増える）"
init_state '{"labels":{"7":["ai:implement"]}}'
run_lib 'mark_for_retry 7 implement "上限"' > /dev/null
assert_eq "ai:retry が付く" "ai:implement,ai:retry" "$(labels_of 7)"
assert_contains "記録は回数0" "$(comments_of 7)" "count=0 kind=implement"

out=$(run_script watchdog.sh)
assert_contains "待ち時間のうちは「まだ早い」" "$out" "まだ早い"
assert_eq "ラベルは変わらない" "ai:implement,ai:retry" "$(labels_of 7)"

age_retry_comments 40
out=$(run_script watchdog.sh)
assert_contains "やり直す" "$out" "implement をやり直します（1/3回目）"
assert_eq "ai:retry が外れ、ai:implement が付いている" "ai:implement" "$(labels_of 7)"
assert_contains "記録は回数1" "$(comments_of 7)" "count=1 kind=implement"
assert_eq "記録のコメントは1つのまま" "1" "$(comments_of 7 | grep -c 'auto-retry -->')"

echo "== 失敗を繰り返すと、上限（MAX_RETRY）で人間に回す"
for _ in 1 2; do
  run_lib 'mark_for_retry 7 implement "上限"' > /dev/null
  age_retry_comments 40
  run_script watchdog.sh > /dev/null
done
assert_contains "回数3まで増える" "$(comments_of 7)" "count=3 kind=implement"
run_lib 'mark_for_retry 7 implement "上限"' > /dev/null
labels=$(labels_of 7)
assert_contains "ai:stuck が付く" "$labels" "ai:stuck"
assert_not_contains "ai:retry は付かない" "$labels" "ai:retry"

echo "== ai:stuck が付いた物は、見張り役が触らず ai:retry の印だけ外す"
init_state '{"labels":{"9":["ai:stuck","ai:retry"]}}'
run_script watchdog.sh > /dev/null
assert_eq "印だけ外れる" "ai:stuck" "$(labels_of 9)"

echo "== 企画AIが止まったとき：ai:plan を付け直す"
init_state '{"labels":{"3":["ai:plan"]}}'
run_lib 'mark_for_retry 3 plan "上限"' > /dev/null
age_retry_comments 40
run_script watchdog.sh > /dev/null
assert_eq "ai:plan だけが付いている" "ai:plan" "$(labels_of 3)"

echo "== 上限以外の失敗が1時間に2件そろったら、1回だけ通知する（3件目では鳴らさない）"
init_state '{"labels":{"21":["ai:plan"],"22":["ai:plan"],"23":["ai:plan"]}}'
before=$(notify_count)
run_lib 'mark_for_retry 21 plan "企画AIがエラーで止まりました"' > /dev/null
assert_eq "1件目では鳴らない" "$before" "$(notify_count)"
out=$(run_lib 'mark_for_retry 22 plan "企画AIがエラーで止まりました"')
assert_eq "2件目で1回鳴る" "$((before + 1))" "$(notify_count)"
assert_contains "どれが失敗したか書く" "$(cat "$MOCK_DIR/curl.log")" "#21 #22"
run_lib 'mark_for_retry 23 plan "企画AIがエラーで止まりました"' > /dev/null
assert_eq "3件目では鳴らない" "$((before + 1))" "$(notify_count)"

echo "== 1時間より前の失敗は数えない"
init_state '{"labels":{"31":["ai:plan"],"32":["ai:plan"]}}'
run_lib 'mark_for_retry 31 plan "x"' > /dev/null
age_retry_comments 90
before=$(notify_count)
run_lib 'mark_for_retry 32 plan "x"' > /dev/null
assert_eq "古い物と合わせても鳴らない" "$before" "$(notify_count)"

finish
