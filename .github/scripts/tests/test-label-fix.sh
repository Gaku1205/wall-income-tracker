#!/usr/bin/env bash
# 見張り役のラベルの矛盾の修正：組み合わせごとに直る／矛盾が無ければ何もしない／20件まで／閉じた物は直近7日だけ
source "$(dirname "$0")/lib.sh"
setup_mock

recent=$(ago 60)
old=$(ago $((10 * 24 * 60)))

echo "== ai:queue と ai:implement"
init_state '{"labels":{"1":["ai:queue","ai:implement"]}}'
run_script watchdog.sh > /dev/null
assert_eq "ai:queue が外れる" "ai:implement" "$(labels_of 1)"
assert_contains "1行コメントが付く" "$(comments_of 1)" "ai:queue を外しました"

echo "== ai:plan と ai:implement"
init_state '{"labels":{"2":["ai:plan","ai:implement"]}}'
run_script watchdog.sh > /dev/null
assert_eq "ai:plan が外れる" "ai:implement" "$(labels_of 2)"
assert_contains "コメントが付く" "$(comments_of 2)" "ai:plan を外しました"

echo "== 記録の無い ai:retry"
init_state '{"labels":{"3":["ai:retry"]}}'
run_script watchdog.sh > /dev/null
assert_eq "ai:retry が外れて ai:stuck になる" "ai:stuck" "$(labels_of 3)"
assert_contains "コメントが付く" "$(comments_of 3)" "ai:stuck にしました"

echo "== 記録のある ai:retry は触らない"
init_state '{"labels":{"4":["ai:retry"]},"comments":[{"id":1,"body":"x\n<!-- auto-retry -->\n<!-- count=1 kind=plan -->","user":{"login":"github-actions[bot]"},"created_at":"'"$(ago 1)"'","updated_at":"'"$(ago 1)"'","issue":"4"}],"next_id":1}'
run_script watchdog.sh > /dev/null
assert_eq "ラベルはそのまま" "ai:retry" "$(labels_of 4)"
assert_not_contains "コメントを足さない" "$(comments_of 4)" "見張り役がラベルの矛盾"

echo "== 閉じた物（直近7日）"
init_state '{"labels":{"5":["ai:stuck","ai:retry","ai:queue","size:S"],"6":["ai:stuck"]},"issues_meta":{"5":{"state":"closed","closed_at":"'"$recent"'"},"6":{"state":"closed","closed_at":"'"$old"'"}}}'
run_script watchdog.sh > /dev/null
assert_eq "直近に閉じた物は外れる" "size:S" "$(labels_of 5)"
assert_contains "コメントが付く" "$(comments_of 5)" "閉じているのに"
assert_eq "7日より前に閉じた物は触らない" "ai:stuck" "$(labels_of 6)"
assert_eq "古い物にコメントしない" "" "$(comments_of 6)"

echo "== 矛盾が無いとき"
init_state '{"labels":{"7":["ai:implement"],"8":["ai:queue"],"9":["ai:stuck"]}}'
run_script watchdog.sh > /dev/null
assert_eq "7 のラベル" "ai:implement" "$(labels_of 7)"
assert_eq "8 のラベル" "ai:queue" "$(labels_of 8)"
assert_eq "9 のラベル" "ai:stuck" "$(labels_of 9)"
assert_not_contains "コメントしない" "$(comments_of 7)$(comments_of 8)$(comments_of 9)" "見張り役がラベルの矛盾"

echo "== 1回に直すのは20件まで"
state_py "s['labels']={str(i):['ai:queue','ai:implement'] for i in range(1,26)}"
run_script watchdog.sh > /dev/null
left=$(python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print(sum(1 for l in s['labels'].values() if 'ai:queue' in l))")
assert_eq "5件が残る" "5" "$left"

finish
