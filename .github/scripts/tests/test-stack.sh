#!/usr/bin/env bash
# 言語・確認コマンド・公開先の読み取り（stack.sh）：pipeline.json が無いときは今までの Next.js、あるときはその中身
source "$(dirname "$0")/lib.sh"
dir="$(mktemp -d)"
cd "$dir" || exit 1
s() { bash -c "source '$SCRIPTS_DIR/stack.sh'; $1" 2>&1; }

echo "== pipeline.json が無い：今までの Next.js（Node 22・npm・Vercel）"
echo '{"scripts":{"typecheck":"x","lint":"x","test":"vitest run","build":"x"}}' > package.json
assert_eq "実行環境" "$(printf 'node\t22')" "$(s stack_tools)"
assert_eq "依存" "npm ci" "$(s stack_setup)"
assert_eq "確認コマンド（test あり）" "$(printf '型チェック\tnpm run typecheck\nリント\tnpm run lint\nテスト\tnpm run test\nビルド\tnpm run build')" "$(s stack_checks)"
assert_eq "AIの許可（今までと同じ4つ）" "Bash(npm run typecheck),Bash(npm run lint),Bash(npm run test),Bash(npm run build)" "$(s stack_allowed_tools)"
assert_eq "公開先" "vercel" "$(s stack_deploy_kinds)"
assert_eq "誤りなし" "" "$(s stack_validate)"
echo '{"scripts":{"typecheck":"x","lint":"x","build":"x"}}' > package.json
assert_not_contains "test が無ければ回さない" "$(s stack_checks)" "npm run test"
rm package.json
assert_not_contains "package.json も無ければ test は回さない" "$(s stack_checks)" "npm run test"

echo "== Python（FastAPI）＋ exe ＋ App Runner"
cat > pipeline.json <<'JSON'
{
  "tools": { "python": "3.12" },
  "setup": [ "pip install -r requirements-dev.txt" ],
  "checks": [
    { "name": "リント", "run": "ruff check ." },
    { "name": "型", "run": "mypy app" },
    { "name": "テスト", "run": "pytest -q" }
  ],
  "deploy": [
    { "kind": "aws-apprunner", "service": "hello-api", "port": 8000 },
    { "kind": "github-release", "os": ["windows-latest", "macos-latest"], "build": "pyinstaller --onefile cli.py", "files": "dist/*" }
  ]
}
JSON
assert_eq "実行環境" "$(printf 'python\t3.12')" "$(s stack_tools)"
assert_eq "依存" "pip install -r requirements-dev.txt" "$(s stack_setup)"
assert_eq "確認コマンド" "$(printf 'リント\truff check .\n型\tmypy app\nテスト\tpytest -q')" "$(s stack_checks)"
assert_eq "AIの許可" "Bash(ruff check .),Bash(mypy app),Bash(pytest -q)" "$(s stack_allowed_tools)"
assert_eq "公開先" "$(printf 'aws-apprunner\ngithub-release')" "$(s stack_deploy_kinds)"
assert_eq "公開先の設定（種類で絞る）" '{"kind":"aws-apprunner","service":"hello-api","port":8000}' "$(s 'stack_deploy aws-apprunner')"
assert_eq "誤りなし" "" "$(s stack_validate)"

echo "== 誤りを言い当てる"
echo '{ こわれた' > pipeline.json
assert_contains "JSON でない" "$(s stack_validate)" "JSON として読めない"
echo '[]' > pipeline.json
assert_contains "外側が配列" "$(s stack_validate)" "一番外側は { }"
echo '{"tools":{"ruby":"3"},"checks":[]}' > pipeline.json
out=$(s stack_validate)
assert_contains "知らない実行環境" "$out" "tools の ruby は知らない実行環境"
assert_contains "checks が空" "$out" "checks が空"
echo '{"tools":{"python":3.12},"checks":[{"name":"x"}]}' > pipeline.json
out=$(s stack_validate)
assert_contains "版が数字" "$out" "版は文字で書く"
assert_contains "run が無い" "$out" "checks の x に run が無い"
cat > pipeline.json <<'JSON'
{"checks":[{"name":"a","run":"pytest -k \"x\""},{"name":"b","run":"echo a,b"},{"name":"c","run":"echo $(id)"},{"name":"ok","run":"pytest"}]}
JSON
out=$(s stack_validate)
assert_contains "引用符" "$out" "pytest -k \"x\""
assert_contains "カンマ" "$out" "echo a,b"
assert_contains "\$( )" "$out" 'echo $(id)'
assert_eq "使えない文字のコマンドはAIに許さない" "Bash(pytest)" "$(s stack_allowed_tools)"
echo '{"checks":[{"run":"pytest"}],"deploy":[{"kind":"heroku"},{"kind":"aws-apprunner","service":"a b"},{"kind":"github-release","build":"x"},{"kind":"github-release","build":"x","files":"d/*","os":["windows-2022","linux"]}]}' > pipeline.json
out=$(s stack_validate)
assert_contains "知らない公開先" "$out" "種類「heroku」は知らない"
assert_contains "サービス名" "$out" "service（サービス名）は小文字の英数字"
echo '{"checks":[{"run":"pytest"}],"deploy":[{"kind":"aws-apprunner","service":"Hello-Api"}]}' > pipeline.json
assert_contains "大文字のサービス名は通さない（ECR が受け付けない）" "$(s stack_validate)" "大文字は使えない"
assert_contains "build と files" "$out" "build（作るコマンド）と files"
assert_contains "ランナー名" "$out" "os「linux」は GitHub のランナー名"
assert_not_contains "正しいランナー名は通す" "$out" "windows-2022"
echo '{"checks":[{"run":"pytest"}]}' > pipeline.json
assert_eq "名前が無ければコマンドを名前に" "$(printf 'pytest\tpytest')" "$(s stack_checks)"
assert_eq "公開先なし" "" "$(s stack_deploy_kinds)"
assert_eq "実行環境なし" "" "$(s stack_tools)"

cd /; rm -rf "$dir"
finish
