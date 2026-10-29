#!/usr/bin/env bash
# AIの許可の不足：何を足せばいいかを書いて人間に回す／同じ不足が2回起きたらIssueを自動で作る
source "$(dirname "$0")/lib.sh"
setup_mock
export GITHUB_SERVER_URL=https://github.com GITHUB_RUN_ID=1
write() { printf '%s' "$2" > "$MOCK_DIR/$1.json"; }

echo "== permission_key_for_command：コマンドを許可の書き方にする"
assert_eq "git は2語" "Bash(git merge:*)" "$(run_lib "permission_key_for_command 'git merge origin/main'")"
assert_eq "gh は3語" "Bash(gh pr edit:*)" "$(run_lib "permission_key_for_command 'gh pr edit 77 --body x'")"
assert_eq "npm は3語で完全一致" "Bash(npm run readme:shots)" "$(run_lib "permission_key_for_command 'npm run readme:shots'")"
assert_eq "ほかは1語" "Bash(curl:*)" "$(run_lib "permission_key_for_command 'curl https://x'")"
assert_eq "語が足りないgit" "Bash(git:*)" "$(run_lib "permission_key_for_command 'git'")"

echo "== denied_tools：実行記録から、拒否された操作を読む"
write d1 '[{"type":"result","subtype":"error_during_execution","result":"","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"git merge origin/main"}},{"tool_name":"Bash","tool_input":{"command":"git merge x"}},{"tool_name":"WebFetch","tool_input":{}}]}]'
write d0 '[{"type":"result","subtype":"error_max_turns","result":"","permission_denials":[]}]'
assert_eq "重複をまとめて、1行ずつ" "Bash(git merge:*)
WebFetch" "$(run_lib "denied_tools '$MOCK_DIR/d1.json'")"
write d2 '[{"type":"result","subtype":"error_during_execution","result":"","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"python3 - <<'"'"'EOF'"'"'\nimport re\nassert a in s,(p,a)\n    return x;\nEOF"}}]}]'
assert_eq "複数行のコマンドは1行目だけを見る（2行目以降を別の操作と読まない）" "Bash(python3:*)" "$(run_lib "denied_tools '$MOCK_DIR/d2.json'")"
assert_eq "拒否が無ければ何も出ない" "" "$(run_lib "denied_tools '$MOCK_DIR/d0.json'")"
assert_eq "記録が無くても何も出ない" "" "$(run_lib "denied_tools '$MOCK_DIR/none.json'")"

echo "== permission_hints_from_text：AIのコメントから、許可の不足を読む"
txt=$(printf '%s\n' '指摘は正しいです。' '`gh pr edit` を許可されていないため、PRの説明を書き換えられませんでした。' '別の話です。')
hints=$(printf '%s' "$txt" | run_lib "permission_hints_from_text")
assert_contains "不足を言っている行が出る" "$hints" "許可されていないため"
assert_contains "コマンドの許可の書き方が出る" "$hints" "KEY: Bash(gh pr edit:*)"
assert_not_contains "関係ない行は出ない" "$hints" "別の話"
assert_eq "許可の話が無ければ何も出ない" "" "$(printf '%s' '直しました。' | run_lib "permission_hints_from_text")"

echo "== 企画AI・実装AIが許可の不足で止まる：やり直さず、足りない許可を書いて人間に回す"
init_state '{"labels":{"7":["ai:implement"]}}'
run_lib "handle_ai_failure 7 implement '実装AIが止まりました' '$MOCK_DIR/d1.json'" > /dev/null
labels=$(labels_of 7)
assert_contains "ai:stuck が付く" "$labels" "ai:stuck"
assert_not_contains "ai:retry は付かない（やり直しても直らない）" "$labels" "ai:retry"
assert_contains "コメントに足りない許可が書かれる" "$(comments_of 7)" "足りない許可：Bash(git merge:*)、WebFetch"
assert_contains "通知にも書かれる" "$(cat "$MOCK_DIR/curl.log")" "足りない許可：Bash(git merge:*)"

echo "== 許可の不足ではない失敗は、今までどおりやり直す"
init_state '{"labels":{"8":["ai:implement"]}}'
run_lib "handle_ai_failure 8 implement '実装AIが止まりました' '$MOCK_DIR/d0.json'" > /dev/null
assert_eq "やり直しの印が付く" "ai:implement,ai:retry" "$(labels_of 8)"

echo "== 同じ不足が1回目：記録だけ（Issueは作らない）。2回目：Issueを自動で作る"
init_state '{"labels":{"7":["ai:implement"],"9":["ai:implement"]}}'
run_lib "report_permission_gap 7 'Bash(git merge:*)'" > /dev/null
issues=$(python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print('\n'.join(m['title']+'|'+m['state'] for m in s['issues_meta'].values()))")
assert_contains "記録用のIssueが閉じたまま作られる" "$issues" "AIの許可の不足（自動の記録）|closed"
assert_not_contains "1回目では、直すIssueは作らない" "$issues" "AIの許可が足りない："
run_lib "report_permission_gap 9 'Bash(git merge:*)'" > /dev/null
issues=$(python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print('\n'.join(m['title']+'|'+m['state'] for m in s['issues_meta'].values()))")
assert_contains "2回目で、直すIssueが作られる" "$issues" "AIの許可が足りない：Bash(git merge:*)|open"
assert_eq "記録用のIssueは1つだけ" "1" "$(printf '%s\n' "$issues" | grep -c '自動の記録')"
new=$(python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print([n for n,m in s['issues_meta'].items() if '許可が足りない' in m['title']][0])")
assert_eq "直すIssueには ai:skip が付く（AIを動かさない）" "ai:skip" "$(labels_of "$new")"
run_lib "report_permission_gap 7 'Bash(git merge:*)'" > /dev/null
assert_eq "3回目でも、直すIssueは増えない" "1" "$(python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print(sum('許可が足りない' in m['title'] for m in s['issues_meta'].values()))")"

echo "== 違う不足は、別々に数える"
init_state '{}'
run_lib "report_permission_gap 7 'Bash(git merge:*)'" > /dev/null
run_lib "report_permission_gap 7 'Bash(gh pr edit:*)'" > /dev/null
assert_not_contains "別の不足なので、直すIssueは作らない" "$(python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print(' '.join(m['title'] for m in s['issues_meta'].values()))")" "AIの許可が足りない："

echo "== 修正AIが「許可されていない」と報告して、変更が入らなかった：足りない許可の候補を書いて人間に回す"
pr='{"number":58,"body":"x","state":"open","head":{"sha":"abc","ref":"claude/issue-54-x"},"updated_at":"2026-01-01T00:00:00Z"}'
init_state '{"labels":{"58":[]},"pulls":['"$pr"']}'
state_py "
s['comments'].append({'id':50,'issue':'58','body':'@claude x\\n<!-- auto-fix -->\\n<!-- auto-fix-sha: abc -->','user':{'login':'x'},'created_at':'$(ago 2)','updated_at':'$(ago 2)'})
s['comments'].append({'id':51,'issue':'58','body':'説明を直そうとしました。\\n\`gh pr edit\` を許可されていないため、PRの説明を書き換えられません。','user':{'login':'claude[bot]'},'created_at':'$(ago 1)','updated_at':'$(ago 1)'})
s['next_id']=51"
RUN_STARTED=$(ago 1) CONCLUSION=success run_script after-mention.sh > /dev/null
assert_contains "ai:stuck が付く" "$(labels_of 58)" "ai:stuck"
assert_contains "コメントに足りない許可の候補が書かれる" "$(comments_of 58)" "足りない許可の候補：Bash(gh pr edit:*)"
assert_contains "AIの報告の行も書かれる" "$(comments_of 58)" "許可されていないため"

echo "== 修正AIが許可の話をせず、変更も入らなかった：今までどおりの文言"
init_state '{"labels":{"58":[]},"pulls":['"$pr"']}'
state_py "
s['comments'].append({'id':50,'issue':'58','body':'@claude x\\n<!-- auto-fix -->\\n<!-- auto-fix-sha: abc -->','user':{'login':'x'},'created_at':'$(ago 2)','updated_at':'$(ago 2)'})
s['comments'].append({'id':51,'issue':'58','body':'指摘は誤りだと思います。','user':{'login':'claude[bot]'},'created_at':'$(ago 1)','updated_at':'$(ago 1)'})
s['next_id']=51"
RUN_STARTED=$(ago 1) CONCLUSION=success run_script after-mention.sh > /dev/null
assert_contains "変更が入りませんでした、の文言" "$(comments_of 58)" "変更が入りませんでした"
assert_not_contains "許可の候補は出さない" "$(comments_of 58)" "足りない許可"

echo "== 多すぎる不足：記録は3件まで、コメントは「ほかN件」。先に止めてから記録する"
init_state '{"labels":{"7":["ai:implement"]}}'
many=$(python3 -c "import json;print(json.dumps([{'type':'result','subtype':'error_during_execution','result':'','permission_denials':[{'tool_name':'Bash','tool_input':{'command':f'tool{i} x'}} for i in range(8)]}]))")
printf '%s' "$many" > "$MOCK_DIR/many.json"
run_lib "handle_ai_failure 7 implement '実装AIが止まりました' '$MOCK_DIR/many.json'" > /dev/null
assert_contains "止める" "$(labels_of 7)" "ai:stuck"
assert_contains "コメントは3件と、ほか5件" "$(comments_of 7)" "Bash(tool0:*)、Bash(tool1:*)、Bash(tool2:*)、ほか5件"
ledger_comments=$(python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print(sum(1 for c in s['comments'] if 'perm-gap:' in c['body']))")
assert_eq "記録は3件まで" "3" "$ledger_comments"
first_stop=$(python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));b=[c['body'] for c in s['comments']];print(next(i for i,x in enumerate(b) if '自動で進めるのを止めました' in x) < next(i for i,x in enumerate(b) if 'perm-gap:' in x))")
assert_eq "止めるコメントが記録より先" "True" "$first_stop"
assert_eq "permission_list_short：3件以下はそのまま" "a、b" "$(run_lib "permission_list_short \"\$(printf 'a\\nb')\"")"

finish
