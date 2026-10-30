#!/usr/bin/env bash
# 見張り役：main とコンフリクトしていて CI が動いていないPRを、AIに解消させる（3.2）
source "$(dirname "$0")/lib.sh"
setup_mock

pr_of() { # 番号 ブランチ mergeable_state
  echo '{"number":'"$1"',"state":"open","mergeable_state":"'"$3"'","body":"Closes #5","head":{"sha":"abc123","ref":"'"$2"'"},"labels":[],"updated_at":"2026-01-01T00:00:00Z"}'
}

echo "== コンフリクトしていて CI が無い：AIに解消を頼む"
init_state '{"labels":{"58":[]},"pulls":['"$(pr_of 58 claude/issue-5-x dirty)"']}'
run_script watchdog.sh > /dev/null
c=$(comments_of 58)
assert_contains "解消を頼む" "$c" "git merge origin/main"
assert_contains "先頭の sha を記録" "$c" "auto-fix-sha: abc123"
run_script watchdog.sh > /dev/null
assert_eq "同じ先頭には2回頼まない" "1" "$(comments_of 58 | grep -c 'auto-fix-sha: abc123')"

echo "== コンフリクトしていない・配布のPR・CI が動いている：何もしない"
init_state '{"labels":{"59":[]},"pulls":['"$(pr_of 59 claude/issue-5-y clean)"']}'
run_script watchdog.sh > /dev/null
assert_not_contains "コンフリクトが無ければ頼まない" "$(comments_of 59)" "コンフリクト"
init_state '{"labels":{"60":[]},"pulls":['"$(pr_of 60 pipeline-sync/abc dirty)"']}'
run_script watchdog.sh > /dev/null
assert_not_contains "配布のPRは触らない" "$(comments_of 60)" "コンフリクト"
init_state '{"labels":{"61":[]},"pulls":['"$(pr_of 61 claude/issue-5-z dirty)"'],"runs":[{"id":1,"name":"CI","conclusion":"success","created_at":"2026-01-01T00:00:00Z"}]}'
run_script watchdog.sh > /dev/null
assert_not_contains "CI が動いていれば、after-ci に任せる" "$(comments_of 61)" "CIが動いていません"

finish
