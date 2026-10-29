#!/usr/bin/env bash
# 失敗の原因の分類（classify_failure）と、コメントの理由（failure_reason）
source "$(dirname "$0")/lib.sh"
setup_mock
export GITHUB_SERVER_URL=https://github.com GITHUB_RUN_ID=123

write() { printf '%s' "$2" > "$MOCK_DIR/$1.json"; }
write limit '[{"type":"result","subtype":"success","is_error":true,"result":"Claude AI usage limit reached|1761000000","permission_denials":[]}]'
write denied '[{"type":"result","subtype":"error_during_execution","result":"","permission_denials":[{"tool_name":"Bash"},{"tool_name":"Edit"}]}]'
write denied_cmd '[{"type":"result","subtype":"error_during_execution","result":"","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"git rebase main | tee log"}}]}]'
write denied_long '[{"type":"result","subtype":"error_during_execution","result":"","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"npx some-very-long-command --with --many --flags --that --goes --on --and --on"}}]}]'
write turns '[{"type":"result","subtype":"error_max_turns","result":""}]'
write other '[{"type":"result","subtype":"error_during_execution","result":"boom"}]'
write nores '[{"type":"assistant"}]'
write broken 'これはJSONではない'

assert_eq "使用量の上限" "使用量の上限" "$(run_lib "classify_failure '$MOCK_DIR/limit.json'")"
assert_contains "許可不足（件数つき）" "$(run_lib "classify_failure '$MOCK_DIR/denied.json'")" "許可不足（AIが許可されていない操作を試した：2件。"
assert_contains "許可不足：最初の操作を出す" "$(run_lib "classify_failure '$MOCK_DIR/denied_cmd.json'")" "最初の1件：Bash(git rebase main   tee log)"
assert_contains "許可不足：| は区切りを壊さない" "$(run_lib "classify_failure '$MOCK_DIR/denied_cmd.json'")" "許可不足（AIが許可されていない操作を試した：1件。"
assert_contains "許可不足：長い操作は切る" "$(run_lib "classify_failure '$MOCK_DIR/denied_long.json'")" "…）"
assert_contains "許可不足：中身が無ければ道具の名前だけ" "$(run_lib "classify_failure '$MOCK_DIR/denied.json'")" "最初の1件：Bash）"
assert_contains "作業回数の上限" "$(run_lib "classify_failure '$MOCK_DIR/turns.json'")" "作業回数の上限"
assert_contains "その他（種類つき）" "$(run_lib "classify_failure '$MOCK_DIR/other.json'")" "その他（error_during_execution）"
assert_contains "結果が無い" "$(run_lib "classify_failure '$MOCK_DIR/nores.json'")" "その他（結果が読み取れません）"
assert_contains "壊れたファイル" "$(run_lib "classify_failure '$MOCK_DIR/broken.json'")" "その他"
assert_contains "ファイルが無い" "$(run_lib "classify_failure '$MOCK_DIR/none.json'")" "不明"
assert_contains "指定が無い" "$(run_lib "classify_failure ''")" "不明"

reason=$(run_lib "failure_reason '企画AIが止まりました' '$MOCK_DIR/limit.json'")
assert_contains "理由に説明が入る" "$reason" "企画AIが止まりました"
assert_contains "理由に分類が入る" "$reason" "原因：使用量の上限"
assert_contains "理由にログのURLが入る" "$reason" "https://github.com/o/r/actions/runs/123"
assert_contains "記録が無くてもURLは入る" "$(run_lib "failure_reason 'x'")" "/actions/runs/123"

finish
