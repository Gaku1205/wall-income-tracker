#!/usr/bin/env bash
# 見張り役のブランチ掃除（claude/* だけ、開いているPRと新しい物は消さない）と、delete_branch_if_ai
source "$(dirname "$0")/lib.sh"
setup_mock

old=$(ago $((3 * 24 * 60)))
recent=$(ago 60)
pr='{"number":5,"state":"open","body":"","head":{"sha":"abc","ref":"claude/issue-5-open"},"updated_at":"'"$recent"'"}'
init_state '{"pulls":['"$pr"'],"branches":[
 {"name":"main","date":"'"$old"'"},
 {"name":"feature/mine","date":"'"$old"'"},
 {"name":"claude/issue-1-old","date":"'"$old"'"},
 {"name":"claude/issue-2-recent","date":"'"$recent"'"},
 {"name":"claude/issue-5-open","date":"'"$old"'"}]}'
run_script watchdog.sh > /dev/null
assert_eq "古くてPRが無い claude/* だけ消える" "claude/issue-2-recent,claude/issue-5-open,feature/mine,main" "$(branch_names)"

echo "== 1回に消すのは20本まで"
state_py "s['pulls']=[]; s['branches']=[{'name':'claude/issue-%d-x' % i,'date':'$old'} for i in range(25)]"
run_script watchdog.sh > /dev/null
assert_eq "5本残る" "5" "$(branch_names | tr ',' '\n' | grep -c .)"

echo "== delete_branch_if_ai は claude/ 以外を消さない"
init_state '{"branches":[{"name":"main","date":"'"$old"'"},{"name":"claude/issue-1-x","date":"'"$old"'"}]}'
run_lib 'delete_branch_if_ai main; delete_branch_if_ai ""; delete_branch_if_ai claude/issue-1-x; delete_branch_if_ai claude/nothing' > /dev/null
assert_eq "claude/ だけ消え、無い物は何もしない" "main" "$(branch_names)"

finish
