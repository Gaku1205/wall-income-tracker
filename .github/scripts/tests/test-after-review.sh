#!/usr/bin/env bash
# レビューのあと（after-review.sh）：指摘なし・CI通過なら自動でマージ。パイプライン自体を変えるPRと ai:hold のPRは、マージを人間に任せる
source "$(dirname "$0")/lib.sh"
setup_mock
# 既存のケースは、印の無い CLAUDE.md で確かめる（実際のリポジトリの CLAUDE.md に左右されないように）
printf '%s\n' '# 普通のリポジトリ' > "$MOCK_DIR/CLAUDE_default.md"
export CLAUDE_MD="$MOCK_DIR/CLAUDE_default.md"

run_case() { # 変更ファイル（スペース区切り） ラベル（カンマ区切り、空でもよい）
  local files labels
  files=$(printf '%s\n' $1 | python3 -c "import sys,json;print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
  labels=$(python3 -c "import sys,json;print(json.dumps([l for l in sys.argv[1].split(',') if l]))" "$2")
  init_state '{"labels":{"58":'"$labels"'},"files":'"$files"',"pulls":[{"number":58,"state":"open","body":"Closes #54","head":{"sha":"abc","ref":"claude/issue-54-x"},"updated_at":"2026-01-01T00:00:00Z"}],"checks":[{"name":"check","status":"completed","conclusion":"success","app":{"slug":"github-actions"}}],"branches":[{"name":"claude/issue-54-x","date":"2026-01-01T00:00:00Z"}]}'
  state_py "s['comments'].append({'id':1,'issue':'58','body':'## Code review\n\nNo issues found.','user':{'login':'github-actions[bot]'},'created_at':'$(ago 1)','updated_at':'$(ago 1)'})"
  CONCLUSION=success HEAD_SHA=abc HEAD_BRANCH=claude/issue-54-x run_script after-review.sh > /dev/null
}
merged() { python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print(','.join(map(str,s.get('merged',[]))))"; }

echo "== アプリだけの変更：自動でマージする（マージ後、AIのブランチを消す）"
run_case "src/app/page.tsx" ""
assert_eq "マージされる" "58" "$(merged)"
assert_eq "ブランチが消える" "" "$(branch_names)"

echo "== .github/ を触るPR：マージしない。ai:hold が付き、「マージできます」の通知が出る"
run_case ".github/scripts/watchdog.sh src/a.ts" ""
assert_eq "マージされない" "" "$(merged)"
assert_eq "ai:hold が付く" "ai:hold" "$(labels_of 58)"
assert_contains "通知が出る" "$(cat "$MOCK_DIR/curl.log")" "マージできます"

echo "== docs/pipeline.md・CLAUDE.md・AGENTS.md を触るPR：同じ"
for f in docs/pipeline.md CLAUDE.md AGENTS.md; do
  run_case "$f" ""
  assert_eq "$f：マージされず、ai:hold が付く" ":ai:hold" "$(merged):$(labels_of 58)"
done

echo "== 似た名前（docs/spec.md、src/.github-note.ts）は、パイプライン自体の変更ではない"
run_case "docs/spec.md src/.github-note.ts" ""
assert_eq "マージされる" "58" "$(merged)"

echo "== ai-dev-template 自身（CLAUDE.md に印がある）：スクリプト・テスト・docs/pipeline.md は自動でマージ。ワークフロー・CLAUDE.md・AGENTS.md は人間に任せる"
printf '%s\n' '<!-- pipeline-self-edit: auto -->' > "$MOCK_DIR/CLAUDE_with_mark.md"
printf '%s\n' '# 普通のリポジトリ' > "$MOCK_DIR/CLAUDE_without_mark.md"
export CLAUDE_MD="$MOCK_DIR/CLAUDE_with_mark.md"
run_case ".github/scripts/watchdog.sh .github/scripts/tests/test-x.sh docs/pipeline.md" ""
assert_eq "スクリプト・テスト・docs は、自動でマージされる" "58:" "$(merged):$(labels_of 58)"
run_case ".github/workflows/ci.yml" ""
assert_eq "ワークフローは、マージされず ai:hold" ":ai:hold" "$(merged):$(labels_of 58)"
for f in CLAUDE.md AGENTS.md; do
  run_case "$f .github/scripts/a.sh" ""
  assert_eq "$f が混ざると、マージされず ai:hold" ":ai:hold" "$(merged):$(labels_of 58)"
done
export CLAUDE_MD="$MOCK_DIR/CLAUDE_without_mark.md"
run_case ".github/scripts/watchdog.sh" ""
assert_eq "印が無いリポジトリ（テンプレートから作ったアプリ）は、スクリプトでも ai:hold" ":ai:hold" "$(merged):$(labels_of 58)"
export CLAUDE_MD="$MOCK_DIR/CLAUDE_default.md"

echo "== ai:hold が付いているPR：アプリだけの変更でもマージしない"
run_case "src/app/page.tsx" "ai:hold"
assert_eq "マージされない" "" "$(merged)"

echo "== レビューの結果が無い：画像だけのPRは、指摘なしとして進める"
review_missing_case() { # 変更ファイル（JSON の配列）
  init_state '{"labels":{"58":[]},"files":'"$1"',"pulls":[{"number":58,"state":"open","body":"Closes #54","head":{"sha":"abc","ref":"claude/issue-54-x"},"updated_at":"2026-01-01T00:00:00Z"}],"checks":[{"name":"check","status":"completed","conclusion":"success","app":{"slug":"github-actions"}}],"branches":[{"name":"claude/issue-54-x","date":"2026-01-01T00:00:00Z"}]}'
  CONCLUSION=success HEAD_SHA=abc HEAD_BRANCH=claude/issue-54-x run_script after-review.sh > /dev/null
}
review_missing_case '[{"filename":"assets/readme/home.png","changes":0},{"filename":"assets/readme/demo.gif","changes":0}]'
assert_eq "画像だけ：マージされる" "58" "$(merged)"
assert_not_contains "画像だけ：止めない" "$(labels_of 58)" "ai:stuck"
assert_contains "画像だけ：理由をコメントする" "$(comments_of 58)" "文字で読めない変更だけ"
review_missing_case '[{"filename":"assets/readme/home.png","changes":0},"src/app/page.tsx"]'
assert_eq "文字のファイルが混ざる：マージしない" "" "$(merged)"
assert_contains "文字のファイルが混ざる：まず自動でやり直す（レビューの結果が無いので）" "$(labels_of 58)" "ai:retry"
review_missing_case '[{"filename":"src/big.ts","changes":5000}]'
assert_eq "大きすぎて patch が無い文字のファイル：マージしない" "" "$(merged)"
assert_contains "大きすぎて patch が無い文字のファイル：まず自動でやり直す" "$(labels_of 58)" "ai:retry"
review_missing_case '[]'
assert_contains "変更ファイルが読めない・無い：まず自動でやり直す" "$(labels_of 58)" "ai:retry"

echo "== マージできなかった：main と衝突なら AI に解消させ、それ以外はやり直し待ち（黙って終わらない）"
export MERGE_STATE_WAIT_SEC=0
merge_fail_case() { # mergeable_state
  run_case_state() {
    init_state '{"labels":{"58":[]},"files":["src/a.ts"],"merge_fail":"HTTP 405: Pull Request is not mergeable","pulls":[{"number":58,"state":"open","mergeable_state":"'"$1"'","body":"Closes #54","head":{"sha":"abc","ref":"claude/issue-54-x"},"updated_at":"2026-01-01T00:00:00Z"}],"checks":[{"name":"check","status":"completed","conclusion":"success","app":{"slug":"github-actions"}}],"branches":[{"name":"claude/issue-54-x","date":"2026-01-01T00:00:00Z"}]}'
    state_py "s['comments'].append({'id':1,'issue':'58','body':'## Code review\n\nNo issues found.','user':{'login':'github-actions[bot]'},'created_at':'$(ago 1)','updated_at':'$(ago 1)'})"
    CONCLUSION=success HEAD_SHA=abc HEAD_BRANCH=claude/issue-54-x run_script after-review.sh
  }
  run_case_state "$1" > /dev/null
}
merge_fail_case dirty
assert_eq "衝突：マージされない" "" "$(merged)"
assert_contains "衝突：AIに main の取り込みを頼む" "$(comments_of 58)" "@claude レビューのあとに main が進み、コンフリクトでマージできませんでした"
assert_contains "衝突：直す依頼の印が付く" "$(comments_of 58)" "auto-fix-sha: abc"
assert_not_contains "衝突：止めない" "$(labels_of 58)" "ai:stuck"
assert_contains "衝突：ブランチは消さない" "$(branch_names)" "claude/issue-54-x"
merge_fail_case blocked
assert_eq "それ以外：マージされない" "" "$(merged)"
assert_contains "それ以外：やり直し待ち" "$(labels_of 58)" "ai:retry"
assert_contains "それ以外：理由に状態が入る" "$(comments_of 58)" "状態：blocked"
assert_contains "それ以外：失敗の内容が入る" "$(comments_of 58)" "not mergeable"
merge_fail_case unknown
assert_contains "状態が分からない：やり直し待ち" "$(labels_of 58)" "ai:retry"
unset MERGE_STATE_WAIT_SEC

echo "== pipeline.json（AIに許すコマンドを決める）を触るPRは、どのリポジトリでも人間に任せる"
run_case "pipeline.json src/a.py" ""
assert_eq "印なし：マージされず ai:hold" ":ai:hold" "$(merged):$(labels_of 58)"
export CLAUDE_MD="$MOCK_DIR/CLAUDE_with_mark.md"
run_case "pipeline.json" ""
assert_eq "テンプレート自身でも：マージされず ai:hold" ":ai:hold" "$(merged):$(labels_of 58)"
run_case ".github/actions/setup-stack/action.yml" ""
assert_eq "テンプレート自身：実行環境の部品（.github/actions/）も ai:hold" ":ai:hold" "$(merged):$(labels_of 58)"
export CLAUDE_MD="$MOCK_DIR/CLAUDE_default.md"
run_case "docs/pipeline.json.md src/pipeline.json" ""
assert_eq "似た名前（直下の pipeline.json 以外）はマージする" "58" "$(merged)"

echo "== PRの説明だけを直して、もう一度レビューで「指摘なし」：前の回の行への指摘（同じコミット）は数えずにマージする"
base='{"labels":{"58":[]},"files":["src/a.ts"],"pulls":[{"number":58,"state":"open","body":"Closes #54","head":{"sha":"abc","ref":"claude/issue-54-x"},"updated_at":"2026-01-01T00:00:00Z"}],"checks":[{"name":"check","status":"completed","conclusion":"success","app":{"slug":"github-actions"}}],"branches":[{"name":"claude/issue-54-x","date":"2026-01-01T00:00:00Z"}]}'
init_state "$base"
state_py "
s['comments'].append({'id':1,'issue':'58','body':'## Code review\n\n1 issues found.','user':{'login':'claude[bot]'},'created_at':'$(ago 10)','updated_at':'$(ago 10)'})
s['comments'].append({'id':2,'issue':'58','body':'## Code review\n\nNo issues found.','user':{'login':'claude[bot]'},'created_at':'$(ago 1)','updated_at':'$(ago 1)'})
s['review_comments']=[{'user':{'login':'claude[bot]'},'original_commit_id':'abc','created_at':'$(ago 10)','body':'説明が足りない'}]"
CONCLUSION=success HEAD_SHA=abc HEAD_BRANCH=claude/issue-54-x run_script after-review.sh > /dev/null
assert_eq "マージされる" "58" "$(merged)"

echo "== この回のレビューで行への指摘がある：直すよう頼む"
init_state "$base"
state_py "
s['comments'].append({'id':1,'issue':'58','body':'## Code review\n\nNo issues found.','user':{'login':'claude[bot]'},'created_at':'$(ago 10)','updated_at':'$(ago 10)'})
s['comments'].append({'id':2,'issue':'58','body':'## Code review\n\nNo issues found.','user':{'login':'claude[bot]'},'created_at':'$(ago 1)','updated_at':'$(ago 1)'})
s['review_comments']=[{'user':{'login':'claude[bot]'},'original_commit_id':'abc','created_at':'$(ago 2)','body':'ここがバグ'}]"
CONCLUSION=success HEAD_SHA=abc HEAD_BRANCH=claude/issue-54-x run_script after-review.sh > /dev/null
assert_eq "マージされない" "" "$(merged)"
assert_contains "直す依頼" "$(comments_of 58)" "auto-fix"

echo "== まとめを書かず、行への指摘だけ（この回）：直すよう頼む"
init_state "$base"
state_py "
s['comments'].append({'id':1,'issue':'58','body':'## Code review\n\nNo issues found.','user':{'login':'claude[bot]'},'created_at':'$(ago 10)','updated_at':'$(ago 10)'})
s['review_comments']=[{'user':{'login':'claude[bot]'},'original_commit_id':'abc','created_at':'$(ago 1)','body':'ここがバグ'}]"
CONCLUSION=success HEAD_SHA=abc HEAD_BRANCH=claude/issue-54-x run_script after-review.sh > /dev/null
assert_eq "マージされない" "" "$(merged)"
assert_contains "直す依頼" "$(comments_of 58)" "auto-fix"

echo "== レビューAIが何も書かずに終わった：2回までは自動でやり直し、そのあとは人間に回す"
init_state "$base"
CONCLUSION=success HEAD_SHA=abc HEAD_BRANCH=claude/issue-54-x run_script after-review.sh > /dev/null
assert_contains "1回目：ai:retry" "$(labels_of 58)" "ai:retry"
assert_not_contains "1回目：人間には回さない" "$(labels_of 58)" "ai:stuck"
state_py "
import re
for c in s['comments']:
    if 'auto-retry' in c['body']: c['body']=re.sub(r'count=[0-9]+ kind=','count=2 kind=',c['body'])
s['labels']['58']=[]"
CONCLUSION=success HEAD_SHA=abc HEAD_BRANCH=claude/issue-54-x run_script after-review.sh > /dev/null
assert_contains "やり直しが2回を超えたら人間に回す" "$(labels_of 58)" "ai:stuck"
assert_eq "マージされない" "" "$(merged)"

finish
