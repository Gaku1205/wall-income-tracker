#!/usr/bin/env bash
# 工場のデザイン部門が写真を取ってくる（fetch-photos.sh）
# Openverse は、このテストの中の疑似 curl で真似る（本物のネットワークには出ない）
source "$(dirname "$0")/lib.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/work"
cat > "$T/bin/curl" <<'SH'
#!/usr/bin/env bash
echo "curl $*" >> "$FT/calls.log"
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; https://*|http://*) url="$1"; shift ;; *) shift ;; esac
done
case "$url" in
  */v1/images/) cat "$FT/api.json" ;;
  */good*.jpg) { printf '\xff\xd8\xff\xe0'; head -c 20000 /dev/zero; } > "$out" ;;
  */good*.png) { printf '\x89PNG\r\n\x1a\n'; head -c 20000 /dev/zero; } > "$out" ;;
  */fake.jpg) { printf '<html>not an image</html>'; head -c 20000 /dev/zero; } > "$out" ;;
  */tiny.jpg) printf '\xff\xd8\xff\xe0tiny' > "$out" ;;
  *) exit 22 ;;
esac
SH
chmod +x "$T/bin/curl"
run() { (cd "$T/work" && env PATH="$T/bin:$PATH" FT="$T" OPENVERSE_API=https://api.test bash "$SCRIPTS_DIR/fetch-photos.sh" "$@" 2>&1); }
api() { printf '%s' "$1" > "$T/api.json"; }

echo "== CC0・パブリックドメインで、横幅 1200px 以上の本物の画像だけを入れ、出どころを残す"
api '{"results":[
 {"url":"https://img.test/good1.jpg","title":"Night river","creator":"A","license":"cc0","foreign_landing_url":"https://src.test/1","width":2400,"height":1600},
 {"url":"https://img.test/small.jpg","title":"Small","creator":"B","license":"cc0","width":800,"height":600},
 {"url":"https://img.test/byncsa.jpg","title":"NC","creator":"C","license":"by-nc-sa","width":3000,"height":2000},
 {"url":"https://img.test/fake.jpg","title":"Fake","creator":"D","license":"pdm","width":3000,"height":2000},
 {"url":"https://img.test/tiny.jpg","title":"Tiny","creator":"E","license":"pdm","width":3000,"height":2000},
 {"url":"http://img.test/good-http.jpg","title":"Plain http","creator":"F","license":"cc0","width":3000,"height":2000},
 {"url":"https://img.test/good2.png","title":"Lanterns","creator":"G","license":"pdm","foreign_landing_url":"https://src.test/2","width":1600,"height":1200}]}'
out=$(run "Night Street, Fukuoka!" 4)
assert_contains "取った枚数を書く" "$out" "2 枚取りました"
assert_eq "入った写真" "01-night-street-fukuoka.jpg 02-night-street-fukuoka.png" "$(cd "$T/work/factory-proto/photos" && find . -maxdepth 1 \( -name "*.jpg" -o -name "*.png" \) -printf "%f\n" | sort | paste -sd " ")"
credits=$(cat "$T/work/factory-proto/photos/CREDITS.md")
assert_contains "出どころ（CC0）" "$credits" '`01-night-street-fukuoka.jpg`：Night river（A、CC0、2400×1600）https://src.test/1'
assert_contains "出どころ（パブリックドメイン）" "$credits" "パブリックドメイン"
assert_contains "ライセンスを絞って探す" "$(cat "$T/calls.log")" "license=cc0,pdm"

echo "== 続けて取ると番号が続く。合わせて 12 枚まで"
api '{"results":[{"url":"https://img.test/good3.jpg","title":"x","creator":"x","license":"cc0","width":2000,"height":1000}]}'
run "lantern" 1 > /dev/null
assert_eq "番号が続く" "yes" "$([ -f "$T/work/factory-proto/photos/03-lantern.jpg" ] && echo yes || echo no)"
for i in $(seq 4 12); do printf 'x' > "$T/work/factory-proto/photos/$(printf %02d "$i")-x.jpg"; done
out=$(run "more" 1); code=$?
assert_eq "12 枚あれば取らない" "1" "$code"
assert_contains "そう書く" "$out" "もう 12 枚あります"

echo "== 使い方の間違い・見つからない"
rm -rf "$T/work/factory-proto"
out=$(run "" 2); assert_eq "検索語が無い" "2" "$?"
run "x" 9 > /dev/null; assert_eq "枚数は 1〜6" "2" "$?"
api '{"results":[]}'
out=$(run "nothing" 2); code=$?
assert_eq "見つからなければ失敗" "1" "$code"
assert_contains "検索語を変えるよう書く" "$out" "検索語を変えてください"

finish
