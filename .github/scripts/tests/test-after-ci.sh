#!/usr/bin/env bash
# CIが落ちたあと（after-ci.sh）：見た目だけが落ちて、意図した変更なら基準画像を自動で撮り直す。それ以外はAIに直させる
source "$(dirname "$0")/lib.sh"
setup_mock

run_case() { # PR本文 落ちたステップ名
  python3 - "$1" "$2" <<'PY'
import json, os, sys
pr = {'number': 58, 'body': sys.argv[1], 'state': 'open', 'head': {'sha': 'abc', 'ref': 'claude/issue-54-x'}, 'updated_at': '2026-01-01T00:00:00Z'}
steps = [{'name': '型チェック', 'conclusion': 'success'}, {'name': sys.argv[2], 'conclusion': 'failure'}, {'name': '見た目のテストの結果（差分の画像）を残す', 'conclusion': 'success'}]
s = {'next_id': 0, 'comments': [], 'labels': {'58': []}, 'issue_updated': {}, 'pulls': [pr], 'jobs': [{'steps': steps}], 'checks': [], 'runs': [], 'branches': [], 'authors': {}}
json.dump(s, open(os.environ['MOCK_STATE'], 'w'))
PY
  RUN_ID=1 CONCLUSION=failure HEAD_SHA=abc HEAD_BRANCH=claude/issue-54-x run_script after-ci.sh > /dev/null
}

echo "== 見た目だけ落ちた・PRに visual:update の記載あり → 撮り直しのラベル"
run_case "Closes #1 基準の画像は visual:update で" "見た目のテスト"
assert_contains "visual:update が付く" "$(labels_of 58)" "visual:update"

echo "== 見た目だけ落ちた・記載なし → 撮り直さず、AIに直させる"
run_case "Closes #1" "見た目のテスト"
assert_not_contains "visual:update は付かない" "$(labels_of 58)" "visual:update"
assert_contains "直す依頼のコメントが付く" "$(comments_of 58)" "auto-fix"

echo "== 型チェックが落ちた → 記載があっても AIに直させる"
run_case "visual:update" "型チェック"
assert_not_contains "visual:update は付かない" "$(labels_of 58)" "visual:update"
assert_contains "直す依頼のコメントが付く" "$(comments_of 58)" "auto-fix"

sync_case() { # CIの結果 mainとの差
  python3 - "$2" <<'PY'
import json, os, sys
pr = {'number': 70, 'body': os.environ.get('SYNC_BODY', '<!-- pipeline-sync -->'), 'user': {'login': os.environ.get('SYNC_AUTHOR', 'gaku-ai-pipeline[bot]')}, 'state': 'open', 'head': {'sha': 'abc', 'ref': 'pipeline-sync/123abcd'}, 'updated_at': '2026-01-01T00:00:00Z'}
s = {'next_id': 0, 'comments': [], 'labels': {'70': []}, 'issue_updated': {}, 'pulls': [pr], 'jobs': [], 'checks': [], 'runs': [], 'branches': [{'name': 'pipeline-sync/123abcd'}], 'authors': {}, 'ahead_by': int(sys.argv[1])}
if os.environ.get('MERGE_FAIL'): s['merge_fail'] = os.environ['MERGE_FAIL']
json.dump(s, open(os.environ['MOCK_STATE'], 'w'))
PY
  RUN_ID=1 CONCLUSION="$1" HEAD_SHA=abc HEAD_BRANCH=pipeline-sync/123abcd run_script after-ci.sh > /dev/null
}
merged_of() { python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print(','.join(map(str,s.get('merged',[]))))"; }

echo "== パイプラインの更新のPR：CIが通ればレビューなしでマージする"
sync_case success 0
assert_eq "マージされる" "70" "$(merged_of)"
assert_not_contains "レビューに回さない" "$(labels_of 70)" "ai:review"
assert_not_contains "ブランチが消える" "$(branch_names)" "pipeline-sync/123abcd"

echo "== パイプラインの更新のPR：CIが落ちたら、AIに直させず人間に回す"
sync_case failure 0
assert_eq "マージしない" "" "$(merged_of)"
assert_contains "ai:stuck が付く" "$(labels_of 70)" "ai:stuck"
assert_not_contains "AIに直させない" "$(comments_of 70)" "auto-fix"

echo "== AIが作った pipeline-sync/ のPRは、近道にしない（ふつうにレビューへ）"
SYNC_AUTHOR='claude[bot]' sync_case success 0
assert_eq "マージしない" "" "$(merged_of)"
assert_contains "レビューに回す" "$(labels_of 70)" "ai:review"
echo "== 印の無い pipeline-sync/ のPRも、近道にしない"
SYNC_BODY='x' sync_case success 0
assert_eq "マージしない" "" "$(merged_of)"

echo "== パイプラインの更新のPR：マージできなかったら、黙らず人間に回す"
MERGE_FAIL='HTTP 405: Merge conflict' sync_case success 0
assert_eq "マージされない" "" "$(merged_of)"
assert_contains "ai:stuck が付く" "$(labels_of 70)" "ai:stuck"
assert_contains "理由をコメントする" "$(comments_of 70)" "マージできませんでした"
assert_not_contains "AIに直させない" "$(comments_of 70)" "auto-fix"

finish
