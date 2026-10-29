#!/usr/bin/env bash
# CIの確認（run-checks.sh）：checks を順に全部回し、落ちた物をまとめて出す
source "$(dirname "$0")/lib.sh"
dir="$(mktemp -d)"
cd "$dir" || exit 1
export GITHUB_STEP_SUMMARY="$dir/summary.md"

echo "== 全部通る"
echo '{"checks":[{"name":"一つ目","run":"true"},{"name":"二つ目","run":"echo hello"}]}' > pipeline.json
out=$(bash "$SCRIPTS_DIR/run-checks.sh" 2>&1); rc=$?
assert_eq "終了コード 0" "0" "$rc"
assert_contains "通った" "$out" "確認は全部通りました"
assert_contains "まとめに書く" "$(cat "$GITHUB_STEP_SUMMARY")" "| ✅ | 一つ目 |"

echo "== 1つ落ちても最後まで回し、落ちた物を全部出す"
: > "$GITHUB_STEP_SUMMARY"
echo '{"checks":[{"name":"リント","run":"false"},{"name":"テスト","run":"touch ran"},{"name":"ビルド","run":"exit 3"}]}' > pipeline.json
out=$(bash "$SCRIPTS_DIR/run-checks.sh" 2>&1); rc=$?
assert_eq "終了コード 1" "1" "$rc"
assert_eq "落ちた後も回す" "yes" "$([ -f ran ] && echo yes)"
assert_contains "落ちた物の一覧" "$out" "落ちた確認：リント ビルド"
assert_contains "注釈" "$out" "::error title=リント::"
assert_contains "まとめに ❌" "$(cat "$GITHUB_STEP_SUMMARY")" "| ❌ | ビルド |"

echo "== パイプの途中の失敗も落ちたとみなす"
echo '{"checks":[{"name":"p","run":"false | cat"}]}' > pipeline.json
bash "$SCRIPTS_DIR/run-checks.sh" > /dev/null 2>&1; rc=$?
assert_eq "終了コード 1" "1" "$rc"

cd /; rm -rf "$dir"
finish
