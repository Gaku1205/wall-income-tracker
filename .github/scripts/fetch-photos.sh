#!/usr/bin/env bash
# 工場のデザイン部門が、自由に使える写真（CC0・パブリックドメインだけ）を取ってくる。
#   .github/scripts/fetch-photos.sh "<英語の検索語>" [枚数（1〜6、既定 4）]
# Openverse（https://openverse.org、鍵は要らない）で探し、横幅 1200px 以上の写真を factory-proto/photos/ に入れる。
# 出どころは factory-proto/photos/CREDITS.md に足す（CC0・パブリックドメインは表記の義務は無いが、元を残す）。
# 置き場所は決まっていて変えられない。合わせて 12 枚まで、1枚 5MB まで、JPEG・PNG・WebP だけ。
# 環境変数（テスト用）：OPENVERSE_API（既定 https://api.openverse.org）、PHOTOS_DIR（既定 factory-proto/photos）
set -uo pipefail
API="${OPENVERSE_API:-https://api.openverse.org}"
DIR="${PHOTOS_DIR:-factory-proto/photos}"
MAX_TOTAL=12
MAX_BYTES=5242880

query="${1:-}"
want="${2:-4}"
if [ -z "$query" ] || [ "${#query}" -gt 100 ] || ! [[ "$want" =~ ^[1-6]$ ]]; then
  echo "使い方：.github/scripts/fetch-photos.sh \"<英語の検索語（100文字まで）>\" [枚数 1〜6]" >&2
  exit 2
fi
mkdir -p "$DIR"
have=$(find "$DIR" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.webp' \) | wc -l)
if [ "$have" -ge "$MAX_TOTAL" ]; then
  echo "もう ${MAX_TOTAL} 枚あります。要らない写真を消してから取ってください" >&2
  exit 1
fi

slug=$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-30)
[ -n "$slug" ] || slug=photo
res=$(curl -sS --max-time 30 -G "$API/v1/images/" \
  --data-urlencode "q=$query" --data-urlencode "license=cc0,pdm" --data-urlencode "size=large" \
  --data-urlencode "mature=false" --data-urlencode "page_size=20") || { echo "Openverse に届きませんでした" >&2; exit 1; }
list=$(printf '%s' "$res" | jq -c '.results // [] | .[] | select((.width // 0) >= 1200 and (.license == "cc0" or .license == "pdm"))
  | {url, title: (.title // ""), creator: (.creator // "不明"), license, page: (.foreign_landing_url // ""), w: .width, h: .height}' 2> /dev/null)
if [ -z "$list" ]; then
  echo "「$query」で、使える写真が見つかりませんでした。検索語を変えてください" >&2
  exit 1
fi

got=0
n=$((have + 1))
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
while IFS= read -r item; do
  [ "$got" -ge "$want" ] && break
  [ $((have + got)) -ge "$MAX_TOTAL" ] && break
  url=$(printf '%s' "$item" | jq -r .url)
  case "$url" in https://*) ;; *) continue ;; esac
  curl -sSL --max-time 60 --max-filesize "$MAX_BYTES" -A "ai-dev-template-factory/1.0" -o "$tmp" "$url" 2> /dev/null || continue
  size=$(wc -c < "$tmp")
  [ "$size" -gt 10000 ] && [ "$size" -le "$MAX_BYTES" ] || continue
  magic=$(head -c 12 "$tmp" | od -An -tx1 | tr -d ' \n')
  case "$magic" in
    ffd8ff*) ext=jpg ;;
    89504e470d0a1a0a*) ext=png ;;
    52494646????????57454250) ext=webp ;;
    *) continue ;;
  esac
  name=$(printf '%02d-%s.%s' "$n" "$slug" "$ext")
  cp "$tmp" "$DIR/$name"
  printf '%s' "$item" | jq -r --arg f "$name" '"- `\($f)`：\(.title)（\(.creator)、\(if .license == "cc0" then "CC0" else "パブリックドメイン" end)、\(.w)×\(.h)）\(.page)"' >> "$DIR/CREDITS.md"
  echo "$DIR/$name（$(printf '%s' "$item" | jq -r '"\(.w)×\(.h)"')）"
  got=$((got + 1))
  n=$((n + 1))
done <<< "$list"
if [ "$got" -eq 0 ]; then
  echo "写真を取れませんでした（どれも取れないか、形が違いました）。検索語を変えてください" >&2
  exit 1
fi
echo "${got} 枚取りました。Read で見て、良い物だけを試作で使ってください（試作の HTML で使った写真だけが新しいリポジトリに入ります）"
