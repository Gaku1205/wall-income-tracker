#!/usr/bin/env bash
# アプリの「言語・確認コマンド・公開先」を決める。リポジトリ直下の pipeline.json を読む。
# pipeline.json が無ければ、今までどおりの Next.js（Node 22・npm・Vercel）として扱う（既存のアプリは何も変えなくてよい）。
#
# pipeline.json の形（どの項目も省ける）：
#   {
#     "tools":  { "node": "22", "python": "3.12", "go": "1.23", "java": "21", "dotnet": "8.0" },   入れる実行環境と版
#     "setup":  [ "pip install -r requirements-dev.txt" ],                                       依存を入れるコマンド（AIの前・CIの前に動く）
#     "checks": [ { "name": "テスト", "run": "pytest -q" } ],                                      CIで順に回し、AIにも許すコマンド
#     "deploy": [ { "kind": "aws-apprunner", ... }, { "kind": "github-release", ... } ]           公開先（docs/pipeline.md「言語と公開先」）
#   }
#
# 使い方（source して関数を呼ぶ。どれも pipeline.json の場所は STACK_FILE、既定はカレントの pipeline.json）：
#   stack_validate        設定の誤りを1行ずつ出す（無ければ何も出さない）
#   stack_tools           入れる実行環境を「名前<TAB>版」で1行ずつ
#   stack_setup           依存を入れるコマンドを1行ずつ
#   stack_checks          確認コマンドを「名前<TAB>コマンド」で1行ずつ
#   stack_allowed_tools   AIに許す形（Bash(コマンド),Bash(...)）をカンマ区切りで1行
#   stack_deploy_kinds    公開先の種類を1行ずつ
#   stack_deploy          公開先の設定を JSON で1行ずつ（種類を指定すればその種類だけ）
STACK_FILE="${STACK_FILE:-pipeline.json}"

# 確認コマンドに使えない文字：AIの許可の書き方（--allowedTools "Bash(..),Bash(..)"）を壊すので
STACK_BAD_CHARS='[",()`$\\]'
STACK_KINDS='vercel aws-apprunner github-release expo none'
STACK_TOOL_NAMES='node python go java dotnet'

_stack_has_file() { [ -f "$STACK_FILE" ]; }

# 既定（pipeline.json が無いとき）：今までの Next.js。test は package.json にあるときだけ
_stack_default_json() {
  local test_check=""
  if [ -f package.json ] && jq -e '.scripts.test != null' package.json > /dev/null 2>&1; then
    test_check=',{"name":"テスト","run":"npm run test"}'
  fi
  printf '{"tools":{"node":"22"},"setup":["npm ci"],"checks":[{"name":"型チェック","run":"npm run typecheck"},{"name":"リント","run":"npm run lint"}%s,{"name":"ビルド","run":"npm run build"}],"deploy":[{"kind":"vercel"}]}' "$test_check"
}

_stack_json() {
  if _stack_has_file; then cat "$STACK_FILE"; else _stack_default_json; fi
}

stack_validate() {
  local json
  if ! _stack_has_file; then return 0; fi
  if ! json=$(jq -c . "$STACK_FILE" 2> /dev/null); then
    echo "pipeline.json が JSON として読めない"
    return 0
  fi
  printf '%s' "$json" | jq -r --arg kinds "$STACK_KINDS" --arg tools "$STACK_TOOL_NAMES" --arg bad "$STACK_BAD_CHARS" '
    ($kinds | split(" ")) as $K | ($tools | split(" ")) as $T |
    if type != "object" then "pipeline.json の一番外側は { } にする" else
    (
      (.tools // {} | if type != "object" then ["tools は { \"python\": \"3.12\" } の形にする"] else
        [to_entries[] | select(.key as $k | $T | index($k) | not) | "tools の \(.key) は知らない実行環境（使えるのは \($tools)）"]
        + [to_entries[] | select((.value | type) != "string" or (.value | length) == 0) | "tools の \(.key) の版は文字で書く（例：\"3.12\"）"] end),
      (.setup // [] | if type != "array" then ["setup はコマンドの配列にする"] else
        [.[] | select(type != "string" or length == 0) | "setup に空・文字でない物がある"] end),
      (.checks // [] | if type != "array" then ["checks は配列にする"] else
        (if length == 0 then ["checks が空（CIが何も確かめない。テストかリントを1つは書く）"] else [] end)
        + [.[] | select((.run | type) != "string" or (.run | length) == 0) | "checks の \(.name // "名前なし") に run が無い"]
        + [.[] | select((.run | type) == "string" and (.run | test($bad))) | "checks の「\(.run)」に使えない文字がある（\" , ( ) ` $ \\ はAIの許可の書き方を壊す。スクリプトにまとめて呼ぶ）"] end),
      (.deploy // [] | if type != "array" then ["deploy は配列にする"] else
        [.[] | select((.kind | type) != "string" or (.kind as $k | $K | index($k) | not)) | "deploy の種類「\(.kind // "なし")」は知らない（使えるのは \($kinds)）"]
        + [.[] | select(.kind == "aws-apprunner") | select((.service | type) != "string" or (.service | test("^[a-z0-9][a-z0-9_-]{3,39}$") | not)) | "aws-apprunner の service（サービス名）は小文字の英数字と - _ で4〜40文字（イメージの置き場 ECR の名前にも使うので、大文字は使えない）"]
        + [.[] | select(.kind == "github-release") | select((.build | type) != "string" or (.files | type) != "string") | "github-release には build（作るコマンド）と files（置くファイル。例：dist/*）が要る"]
        + [.[] | select(.kind == "github-release") | (.os // ["windows-latest"]) | select(type != "array") | "github-release の os は配列にする（例：[\"windows-latest\", \"macos-latest\"]）"]
        + [.[] | select(.kind == "github-release") | (.os // ["windows-latest"]) | select(type == "array") | .[] | select(test("^(ubuntu|windows|macos)-[a-z0-9.]+$") | not) | "github-release の os「\(.)」は GitHub のランナー名にする（ubuntu-latest / windows-latest / macos-latest）"] end)
    ) | .[] end'
}

stack_tools() {
  _stack_json | jq -r '.tools // {} | to_entries[] | "\(.key)\t\(.value)"'
}

stack_setup() {
  _stack_json | jq -r '.setup // [] | .[]'
}

stack_checks() {
  _stack_json | jq -r '.checks // [] | .[] | "\(.name // .run)\t\(.run)"'
}

# 使えない文字のあるコマンドは許可に入れない（stack_validate が知らせる）
stack_allowed_tools() {
  _stack_json | jq -r --arg bad "$STACK_BAD_CHARS" '[.checks // [] | .[] | .run | select(type == "string" and length > 0 and (test($bad) | not)) | "Bash(\(.))"] | join(",")'
}

stack_deploy_kinds() {
  _stack_json | jq -r '.deploy // [] | .[].kind' | awk '!seen[$0]++'
}

stack_deploy() {
  _stack_json | jq -c --arg k "${1:-}" '.deploy // [] | .[] | select($k == "" or .kind == $k)'
}
