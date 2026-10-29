#!/usr/bin/env bash
# 配り先の決め方（sync-targets.sh）：書いた物＋テンプレートから作った物、! で外す、本体とアーカイブは配らない
source "$(dirname "$0")/lib.sh"
setup_mock
export GITHUB_REPOSITORY=o/tpl

# このテスト用の偽の gh：URL ごとに決まった JSON を返し、-q の jq を当てる。
# APP=no のときは installation の一覧を 403 にする（個人の鍵のとき）
cat > "$MOCK_DIR/bin/gh" <<'GH'
#!/usr/bin/env bash
url="" q=""
while [ $# -gt 0 ]; do
  case "$1" in
    api | --paginate) ;;
    -q) q="$2"; shift ;;
    *) url="$1" ;;
  esac
  shift
done
case "$url" in
  installation/repositories*)
    [ "${APP:-yes}" = no ] && { echo "HTTP 403" >&2; exit 1; }
    json='{"repositories":[{"full_name":"o/tpl","archived":false},{"full_name":"o/app1","archived":false},{"full_name":"o/old","archived":true},{"full_name":"o/other","archived":false},{"full_name":"o/Skipme","archived":false},{"full_name":"o/broken","archived":false}]}' ;;
  users/o/repos*)
    json='[{"full_name":"o/app1","archived":false},{"full_name":"o/app2","archived":false}]' ;;
  repos/o/app1 | repos/o/app2 | repos/o/skipme | repos/o/Skipme)
    json='{"template_repository":{"full_name":"O/TPL"}}' ;;
  repos/o/other)
    json='{"template_repository":null}' ;;
  repos/o/broken)
    echo "HTTP 500" >&2; exit 1 ;;
  *)
    echo "想定外の URL: $url" >&2; exit 1 ;;
esac
if [ -n "$q" ]; then printf '%s' "$json" | jq -r "$q"; else printf '%s' "$json"; fi
GH
chmod +x "$MOCK_DIR/bin/gh"

targets="$MOCK_DIR/targets"
printf '# コメント\nGaku1205/agent-desk\n\n  o/app1  # 自動でも見つかる（重ならない）\n!o/skipme\n' > "$targets"

echo "== App の鍵：書いた物と、テンプレートから作った物"
out=$(bash "$SCRIPTS_DIR/sync-targets.sh" "$targets" 2> "$MOCK_DIR/err")
assert_eq "配り先" "Gaku1205/agent-desk,o/app1" "$(printf '%s' "$out" | paste -sd, -)"
assert_not_contains "本体には配らない" "$out" "o/tpl"
assert_not_contains "アーカイブ済みは配らない" "$out" "o/old"
assert_not_contains "別のテンプレート・テンプレート無しは配らない" "$out" "o/other"
assert_not_contains "! で外した物は（大文字小文字が違っても）配らない" "$out" "Skipme"
assert_not_contains "読めないリポジトリは飛ばす" "$out" "o/broken"
assert_contains "自動で見つけた物を知らせる" "$(cat "$MOCK_DIR/err")" "自動で見つけた配り先：o/app1"
assert_contains "外した物を知らせる" "$(cat "$MOCK_DIR/err")" "配らない：o/Skipme"

echo "== 個人の鍵（App の一覧が読めない）：オーナーのリポジトリから探す"
out=$(APP=no bash "$SCRIPTS_DIR/sync-targets.sh" "$targets" 2> /dev/null)
assert_eq "配り先" "Gaku1205/agent-desk,o/app1,o/app2" "$(printf '%s' "$out" | paste -sd, -)"

echo "== sync-targets が無くても、自動の分は配る"
out=$(bash "$SCRIPTS_DIR/sync-targets.sh" "$MOCK_DIR/none" 2> /dev/null)
assert_eq "配り先" "o/app1,o/Skipme" "$(printf '%s' "$out" | paste -sd, -)"

echo "== 最後の行に改行が無くても読む"
printf 'o/last' > "$targets"
out=$(bash "$SCRIPTS_DIR/sync-targets.sh" "$targets" 2> /dev/null)
assert_contains "最後の行" "$out" "o/last"

finish
