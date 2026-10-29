#!/usr/bin/env bash
# 再開（resume.sh）：人間が ai:stuck を外したあと、止まった所から自動で続ける
# 「Resume が自分を数える」不具合：Resume 自身の実行を、CIの結果や実行中として数えてしまう。それが再び入ったら落ちる
source "$(dirname "$0")/lib.sh"
setup_mock
# resume.sh は after-ci.sh を .github/scripts/ から呼ぶので、リポジトリのルートで動かす
cd "$SCRIPTS_DIR/../.." || exit 1

# PR #58（先頭コミット abc）の状態を作る。引数は actions の実行（runs）の JSON 配列
setup_pr() {
  init_state "$(python3 - "$1" <<'PY'
import json, sys
pr = {'number': 58, 'body': 'Closes #54', 'state': 'open', 'head': {'sha': 'abc', 'ref': 'claude/issue-54-x'}, 'updated_at': '2026-01-01T00:00:00Z'}
print(json.dumps({'labels': {'58': [], '54': ['ai:stuck']}, 'pulls': [pr], 'runs': json.loads(sys.argv[1])}))
PY
)"
}
run_resume() { NUMBER="$1" IS_PR="$2" run_script resume.sh; }

# CI の実行と、そのあとに始まった Resume 自身の実行（実行中）
ci_run() { printf '{"id":11,"name":"CI","status":"%s","conclusion":%s,"created_at":"2026-01-01T00:00:00Z"}' "$1" "$2"; }
resume_run='{"id":12,"name":"Resume","status":"in_progress","conclusion":null,"created_at":"2026-01-01T00:05:00Z"}'

echo "== PR・CIが成功している → ai:review が付く（あとに始まった Resume 自身の実行は数えない）"
setup_pr "[$(ci_run completed '"success"'),$resume_run]"
out=$(run_resume 58 true)
assert_eq "ai:review が付く" "ai:review" "$(labels_of 58)"
assert_contains "レビューを依頼した" "$out" "CIが通ったのでレビューを依頼しました"
assert_not_contains "実行中とは見なさない" "$out" "CIが実行中"
assert_not_contains "直す依頼は出ない" "$(comments_of 58)" "@claude"
assert_not_contains "紐づくIssueの ai:stuck が外れる" "$(labels_of 54)" "ai:stuck"
assert_contains "再開の記録が残る" "$(comments_of 58)" "auto-resume"

echo "== PR・CIが失敗している → 直す依頼（@claude のコメント）が出る"
setup_pr "[$(ci_run completed '"failure"'),$resume_run]"
out=$(run_resume 58 true)
assert_contains "直す依頼が出る" "$(comments_of 58)" "@claude CIが失敗しました"
assert_contains "自動の依頼の印が付く" "$(comments_of 58)" "auto-fix"
assert_contains "依頼1回目" "$(comments_of 58)" "自動の依頼 1/3"
assert_not_contains "ai:review は付かない" "$(labels_of 58)" "ai:review"

echo "== PR・CIが実行中 → 何もせず待つ（Resume 自身が終わっていても、CIの結果とは見なさない）"
resume_done='{"id":12,"name":"Resume","status":"completed","conclusion":"success","created_at":"2026-01-01T00:05:00Z"}'
setup_pr "[$(ci_run in_progress null),$resume_done]"
out=$(run_resume 58 true)
assert_contains "実行中なので待つ" "$out" "CIが実行中です"
assert_not_contains "ai:review は付かない" "$(labels_of 58)" "ai:review"
assert_not_contains "直す依頼は出ない" "$(comments_of 58)" "@claude"

echo "== PRではなくIssue（ai:implement・PRなし）→ ai:implement が付き直る"
init_state '{"labels":{"7":["ai:implement"]}}'
out=$(run_resume 7 false)
assert_contains "実装をやり直した" "$out" "実装をやり直しました"
assert_eq "ai:implement が付いている" "ai:implement" "$(labels_of 7)"

echo "== Issue・すでにPRがある → 実装はやり直さない"
init_state '{"labels":{"7":["ai:implement"]},"pulls":[{"number":9,"head":{"ref":"claude/issue-7-x","sha":"abc"}}]}'
out=$(run_resume 7 false)
assert_contains "やり直さない" "$out" "PRがあるので、実装はやり直しません"

echo "== 再開で回数を0に戻すとき、「AIが止まった」とは書かない"
run_lib "write_retry_record 40 0 implement '人間が再開しました'" > /dev/null
assert_contains "再開の文" "$(comments_of 40)" "▶ 人間が再開しました。自動のやり直しの回数を0に戻しました。"
assert_not_contains "止まったとは書かない" "$(comments_of 40)" "AIが止まったので"
assert_contains "印は残る（次のやり直しで書き換える）" "$(comments_of 40)" "<!-- count=0 kind=implement -->"

finish
