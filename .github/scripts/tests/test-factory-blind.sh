#!/usr/bin/env bash
# 工場の審査役に、画像だけを見せる（factory-blind.sh）
source "$(dirname "$0")/lib.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
W="$T/work"; mkdir -p "$W/factory-proto/shots" "$W/factory-proto/photos" "$W/.taste-skill"
cd "$W" || exit 1
echo spec > factory-design.md; echo ctx > factory-context.md; echo three > factory-libs.txt; echo "点数: 6" > factory-critique.md
echo '<html>' > factory-proto/01-hero.html; echo png > factory-proto/shots/01-hero-390.png; echo jpg > factory-proto/photos/01-x.jpg
echo dir > .taste-skill/direction.json
run() { BLIND_DIR="$T/blind" bash "$SCRIPTS_DIR/factory-blind.sh" "$@" > /dev/null; }

echo "== 隠す：仕様・HTML・前の採点・作業用の物が見えなくなり、画像と写真は残る"
run hide
left=$(find . -type f | sort | xargs)
assert_eq "残るのは画像と写真だけ" "./factory-proto/photos/01-x.jpg ./factory-proto/shots/01-hero-390.png" "$left"

echo "== 戻す：審査役の新しい採点を残し、前の採点は戻さない"
echo "点数: 8.2" > factory-critique.md
run restore
assert_eq "仕様が戻る" "spec" "$(cat factory-design.md)"
assert_eq "試作の HTML が戻る" "<html>" "$(cat factory-proto/01-hero.html)"
assert_eq "作業用の物が戻る" "dir" "$(cat .taste-skill/direction.json)"
assert_eq "新しい採点が残る" "点数: 8.2" "$(cat factory-critique.md)"
assert_eq "隠し場所は片付く" "no" "$([ -e "$T/blind" ] && echo yes || echo no)"

echo "== 2回目：前の採点も隠す"
run hide
assert_eq "前の採点は見えない" "no" "$([ -e factory-critique.md ] && echo yes || echo no)"
run restore
assert_eq "審査役が書かなければ、採点は無いまま" "no" "$([ -e factory-critique.md ] && echo yes || echo no)"

finish
