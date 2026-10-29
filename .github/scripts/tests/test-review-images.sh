#!/usr/bin/env bash
# レビューの前に、見た目の画像（*.png）の前と後を取ってくる（claude-review.yml の「見た目の画像の前と後を用意する」）
# ワークフローに直接書いてある処理なので、YAML から取り出して疑似 gh で動かす
source "$(dirname "$0")/lib.sh"
setup_mock
WF="$SCRIPTS_DIR/../workflows/claude-review.yml"
step="$MOCK_DIR/images.sh"
python3 - "$WF" "$step" <<'PY'
import sys, yaml
for st in yaml.safe_load(open(sys.argv[1]))['jobs']['review']['steps']:
    if st.get('id') == 'images':
        open(sys.argv[2], 'w').write(st['run'])
PY
work="$MOCK_DIR/work"; mkdir -p "$work/.git/info"
run_step() {
  : > "$MOCK_DIR/out"
  (cd "$work" && rm -rf .review-images && PR=5 BASE=b1 HEAD=h1 DIR=.review-images MAX="${MAX:-12}" \
    GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$MOCK_DIR/out" RUNNER_TEMP="$MOCK_DIR" bash -e "$step" 2>&1)
}
listed() { sed -n '/^list<<LIST_END$/,/^LIST_END$/p' "$MOCK_DIR/out" | sed '1d;$d'; }

echo "== 変わった画像・足した画像・消した画像・名前を変えた画像"
init_state '{"files":[
  "src/app/page.tsx",
  {"filename":"tests/visual/__screenshots__/pc/home.png","status":"modified"},
  {"filename":"tests/visual/__screenshots__/sp/new.png","status":"added"},
  {"filename":"tests/visual/__screenshots__/sp/old.png","status":"removed"},
  {"filename":"img/b.PNG","status":"renamed","previous_filename":"img/a.PNG"}],
  "contents":{"b1":{"tests/visual/__screenshots__/pc/home.png":"BEFORE","tests/visual/__screenshots__/sp/old.png":"OLD","img/a.PNG":"A"},
              "h1":{"tests/visual/__screenshots__/pc/home.png":"AFTER","tests/visual/__screenshots__/sp/new.png":"NEW","img/b.PNG":"B"}}}'
out=$(run_step)
assert_contains "何組用意したか" "$out" "4 組用意しました"
assert_eq "前（元のPRの版）" "BEFORE" "$(cat "$work/.review-images/tests__visual____screenshots____pc__home.before.png")"
assert_eq "後（PRの先頭の版）" "AFTER" "$(cat "$work/.review-images/tests__visual____screenshots____pc__home.after.png")"
l=$(listed)
assert_contains "足した画像は前なし" "$l" "sp/new.png（added）： 前 なし ・ 後 .review-images/"
assert_contains "消した画像は後なし" "$l" "sp/old.png（removed）： 前 .review-images/tests__visual____screenshots____sp__old.before.png ・ 後 なし"
assert_eq "名前を変えた画像の前は、元の名前から" "A" "$(cat "$work/.review-images/img__b.before.png")"
assert_not_contains "画像でない物は入れない" "$l" "page.tsx"
assert_contains "git に入れない" "$(cat "$work/.git/info/exclude")" "/.review-images/"

echo "== 多すぎるときは MAX 枚まで、残りの数を書く"
MAX=2 run_step > /dev/null
assert_eq "2組だけ" "2" "$(listed | grep -c '）：')"
assert_contains "残りの数" "$(listed)" "ほか 2 枚"

echo "== 画像の変更が無いときは、何も作らず list は空"
init_state '{"files":["src/app/page.tsx"]}'
out=$(run_step)
assert_contains "変更なし" "$out" "画像の変更はありません"
assert_contains "list は空" "$(cat "$MOCK_DIR/out")" "list="
assert_eq "フォルダを作らない" "no" "$([ -d "$work/.review-images" ] && echo yes || echo no)"

echo "== レビューAIへの指示：画像があるときだけ見比べさせる"
wf=$(cat "$WF")
assert_contains "画像の一覧を指示に入れる" "$wf" "steps.images.outputs.list"
assert_contains "Read で開いて見比べる" "$wf" "Read で全部開いて見比べる"

finish
