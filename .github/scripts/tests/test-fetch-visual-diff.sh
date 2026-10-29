#!/usr/bin/env bash
# 見た目のテストの差分の画像を取ってくる（fetch-visual-diff.sh）：落ちた CI に画像があるときだけ、git に入れずに置く
source "$(dirname "$0")/lib.sh"
setup_mock
work="$(mktemp -d)"; cd "$work" || exit 1
mkdir -p .git/info; : > .git/info/exclude
export PR=7 GITHUB_REPOSITORY=o/r MOCK_DIR
# 偽の gh：RUNS（落ちた CI があるか）・ART（画像の artifact があるか）で切り替える
cat > "$MOCK_DIR/bin/gh" <<'GH'
#!/usr/bin/env bash
q=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[$i]}" = -q ] && q="${args[$((i + 1))]}"; done
case "$1 $2" in
  "api repos/o/r/pulls/7") json='{"head":{"sha":"abc"}}' ;;
  "api repos/o/r/actions/runs?head_sha=abc&event=pull_request&per_page=20")
    if [ -n "${RUNS:-}" ]; then json='{"workflow_runs":[{"id":1,"name":"CI","conclusion":"failure","created_at":"2026-01-01T00:00:00Z"},{"id":2,"name":"CI","conclusion":"failure","created_at":"2026-01-02T00:00:00Z"},{"id":3,"name":"Other","conclusion":"failure","created_at":"2026-01-03T00:00:00Z"}]}'; else json='{"workflow_runs":[{"id":1,"name":"CI","conclusion":"success","created_at":"2026-01-01T00:00:00Z"}]}'; fi ;;
  "api repos/o/r/actions/runs/2/artifacts")
    if [ -n "${ART:-}" ]; then json='{"artifacts":[{"name":"visual-diff","expired":false}]}'; else json='{"artifacts":[]}'; fi ;;
  "run download")
    echo "run download $*" >> "$MOCK_DIR/dl.log"
    d=""; for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[$i]}" = --dir ] && d="${args[$((i + 1))]}"; done
    mkdir -p "$d/visual"; touch "$d/visual/home-expected.png" "$d/visual/home-actual.png" "$d/visual/home-diff.png"; exit 0 ;;
  *) echo "想定外: $*" >&2; exit 1 ;;
esac
if [ -n "$q" ]; then printf '%s' "$json" | jq -r "$q"; else printf '%s' "$json"; fi
GH
chmod +x "$MOCK_DIR/bin/gh"

echo "== 落ちた CI が無い：何もしない"
out=$(bash "$SCRIPTS_DIR/fetch-visual-diff.sh" 2>&1)
assert_contains "知らせる" "$out" "落ちた CI が無い"
assert_eq "フォルダを作らない" "no" "$([ -d .visual-diff ] && echo yes || echo no)"

echo "== 落ちたが画像が無い（見た目のテスト以外で落ちた）：何もしない"
out=$(RUNS=1 bash "$SCRIPTS_DIR/fetch-visual-diff.sh" 2>&1)
assert_contains "知らせる" "$out" "差分の画像が無い"
assert_eq "取ってこない" "no" "$([ -f "$MOCK_DIR/dl.log" ] && echo yes || echo no)"

echo "== いちばん新しい落ちた CI の画像を取ってきて、git に入れない"
out=$(RUNS=1 ART=1 bash "$SCRIPTS_DIR/fetch-visual-diff.sh" 2>&1)
assert_contains "いちばん新しい実行（2）から" "$(cat "$MOCK_DIR/dl.log")" "run download 2"
assert_contains "3枚" "$out" "3枚"
assert_eq "画像がある" "yes" "$([ -f .visual-diff/visual/home-diff.png ] && echo yes || echo no)"
assert_contains "git に入れない" "$(cat .git/info/exclude)" "/.visual-diff/"
RUNS=1 ART=1 bash "$SCRIPTS_DIR/fetch-visual-diff.sh" > /dev/null 2>&1
assert_eq "2回目でも除外の行は1つ" "1" "$(grep -c visual-diff .git/info/exclude)"

cd /; rm -rf "$work"
finish
