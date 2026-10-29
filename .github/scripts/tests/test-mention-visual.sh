#!/usr/bin/env bash
# 修正AIが「基準の画像が古い。visual:update で撮り直して」と答えて変更が入らなかったとき：
# 落ちているのが見た目のテストだけなら、人間に回さず撮り直す（1つのPRで2回まで）
source "$(dirname "$0")/lib.sh"
setup_mock
pr='{"number":58,"body":"Closes #57","state":"open","head":{"sha":"abc","ref":"claude/issue-57-x"},"updated_at":"2026-01-01T00:00:00Z"}'
setup_case() { # 1: AIの返事 2: 落ちたステップ（JSONの配列）
  init_state '{"labels":{"58":[]},"pulls":['"$pr"'],"runs":[{"id":9,"name":"CI","conclusion":"failure","created_at":"2026-01-01T00:00:00Z"}],"jobs":[{"steps":'"$2"'}]}'
  state_py "
s['comments'].append({'id':50,'issue':'58','body':'@claude x\\n<!-- auto-fix -->\\n<!-- auto-fix-sha: abc -->','user':{'login':'x'},'created_at':'$(ago 2)','updated_at':'$(ago 2)'})
s['comments'].append({'id':51,'issue':'58','body':'''$1''','user':{'login':'claude[bot]'},'created_at':'$(ago 1)','updated_at':'$(ago 1)'})
s['next_id']=51"
}
visual_only='[{"name":"見た目のテスト","conclusion":"failure"},{"name":"テスト","conclusion":"success"}]'

echo "== 見た目のテストだけが落ち、AIが visual:update を頼んだ：撮り直す"
setup_case '基準の画像が古いだけです。`visual:update` ラベルで撮り直してください。' "$visual_only"
out=$(RUN_STARTED=$(ago 1) CONCLUSION=success run_script after-mention.sh)
assert_contains "撮り直しを依頼したと出す" "$out" "撮り直しを依頼しました"
assert_contains "visual:update が付く" "$(labels_of 58)" "visual:update"
assert_not_contains "人間に回さない" "$(labels_of 58)" "ai:stuck"
assert_contains "印つきのコメント（回数に数える）" "$(comments_of 58)" "auto-visual-update"

echo "== 2回撮り直したあとは、人間に回す"
setup_case '`visual:update` で撮り直してください。' "$visual_only"
state_py "
for i in (60, 61): s['comments'].append({'id':i,'issue':'58','body':'撮り直します\\n<!-- auto-visual-update -->','user':{'login':'p'},'created_at':'$(ago 30)','updated_at':'$(ago 30)'})"
RUN_STARTED=$(ago 1) CONCLUSION=success run_script after-mention.sh > /dev/null
assert_contains "ai:stuck" "$(labels_of 58)" "ai:stuck"
assert_not_contains "visual:update は付けない" "$(labels_of 58)" "visual:update"

echo "== ほかのチェックも落ちている：撮り直さず人間に回す"
setup_case '`visual:update` で撮り直してください。' '[{"name":"見た目のテスト","conclusion":"failure"},{"name":"テスト","conclusion":"failure"}]'
RUN_STARTED=$(ago 1) CONCLUSION=success run_script after-mention.sh > /dev/null
assert_contains "ai:stuck" "$(labels_of 58)" "ai:stuck"
assert_not_contains "visual:update は付けない" "$(labels_of 58)" "visual:update"

echo "== AIが撮り直しを頼んでいない：今まで通り人間に回す"
setup_case '指摘は誤りだと思います。' "$visual_only"
RUN_STARTED=$(ago 1) CONCLUSION=success run_script after-mention.sh > /dev/null
assert_contains "ai:stuck" "$(labels_of 58)" "ai:stuck"

finish
