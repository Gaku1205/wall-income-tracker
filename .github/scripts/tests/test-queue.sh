#!/usr/bin/env bash
# 順番待ち（queue-next.sh）：進めてよいとき・いけないとき
source "$(dirname "$0")/lib.sh"
setup_mock

pr='{"number":5,"state":"open","body":"","head":{"sha":"abc","ref":"claude/issue-5-x"},"updated_at":"2026-01-01T00:00:00Z"}'

echo "== 何も進行中でなければ、順番待ちの先頭（番号が小さい方）を実装に回す"
init_state '{"labels":{"2":["ai:queue"],"3":["ai:queue"]}}'
run_script queue-next.sh > /dev/null
assert_eq "#2 が実装に回る" "ai:implement" "$(labels_of 2)"
assert_eq "#3 は待ったまま" "ai:queue" "$(labels_of 3)"

echo "== 企画の段階で止まった物（人間の作業待ち・質問）があっても、止まらない"
init_state '{"labels":{"1":["ai:stuck"],"2":["ai:queue"]}}'
run_script queue-next.sh > /dev/null
assert_eq "#2 が実装に回る" "ai:implement" "$(labels_of 2)"

echo "== 実装中の物があるあいだは進めない"
init_state '{"labels":{"1":["ai:implement"],"2":["ai:queue"]}}'
run_script queue-next.sh > /dev/null
assert_eq "#2 は待ったまま" "ai:queue" "$(labels_of 2)"

echo "== 実装で止まった物（ai:implement が残っている）があるあいだも進めない"
init_state '{"labels":{"1":["ai:implement","ai:stuck"],"2":["ai:queue"]}}'
run_script queue-next.sh > /dev/null
assert_eq "#2 は待ったまま" "ai:queue" "$(labels_of 2)"

echo "== openのPRがあるあいだは進めない"
init_state '{"labels":{"2":["ai:queue"]},"pulls":['"$pr"']}'
run_script queue-next.sh > /dev/null
assert_eq "#2 は待ったまま" "ai:queue" "$(labels_of 2)"

echo "== 順番待ちが無ければ何もしない"
init_state '{"labels":{"1":["ai:stuck"]}}'
out=$(run_script queue-next.sh)
assert_contains "「ありません」と出る" "$out" "順番待ちはありません"

echo "== 同時に2回進めても、順番待ちは1回だけ始まる（コメントも1回）"
init_state '{"labels":{"30":["ai:queue"]}}'
run_lib "start_next_in_queue" > /dev/null
run_lib "start_next_in_queue" > /dev/null
assert_eq "実装に回る" "ai:implement" "$(labels_of 30)"
assert_eq "コメントは1回" "1" "$(comments_of 30 | grep -c '順番が来たので')"

finish
