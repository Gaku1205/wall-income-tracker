#!/usr/bin/env bash
# 企画AIのあと（after-plan.sh）：清書の結果のサイズを付けて実装へ。先に決まっているサイズ（工場の size:L など）は残す
source "$(dirname "$0")/lib.sh"
setup_mock
work="$MOCK_DIR/work"; mkdir -p "$work"
run_plan() { (cd "$work" && if [ -n "$1" ]; then printf '%s\n%s\n' "$1" PARALLEL > plan-result.txt; else rm -f plan-result.txt; fi && ISSUE=3 PLAN_OUTCOME=success GITHUB_TOKEN_FOR_LABELS=x bash "$SCRIPTS_DIR/after-plan.sh" 2>&1); }

echo "== サイズが無ければ、企画AIの決めたサイズを付けて実装へ"
init_state '{"labels":{"3":["ai:plan"]}}'
run_plan "READY size:S" > /dev/null
assert_eq "size:S と ai:implement" "ai:implement,size:S" "$(labels_of 3)"

echo "== 工場が size:L を付けていれば、企画AIが size:S と言っても size:L のまま"
init_state '{"labels":{"3":["ai:plan","size:L"]}}'
run_plan "READY size:S" > /dev/null
assert_eq "size:L のまま" "ai:implement,size:L" "$(labels_of 3)"

echo "== 結果を書かずに終わった（質問も無い）：黙って止めず、2回までは自動でやり直す"
init_state '{"labels":{"3":["ai:plan"]}}'
run_plan "" > /dev/null
assert_contains "やり直し待ち" "$(labels_of 3)" "ai:retry"
assert_not_contains "人間に回さない" "$(labels_of 3)" "ai:stuck"
state_py "
import re
for c in s['comments']:
    if 'auto-retry' in c['body']: c['body']=re.sub(r'count=[0-9]+ kind=','count=2 kind=',c['body'])
s['labels']['3']=['ai:plan']"
run_plan "" > /dev/null
assert_contains "やり直しのあとも書かなければ人間に回す" "$(labels_of 3)" "ai:stuck"
assert_contains "理由を書く" "$(comments_of 3)" "清書の結果を書きませんでした"

finish
