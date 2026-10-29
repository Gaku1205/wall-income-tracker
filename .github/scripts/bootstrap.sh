#!/usr/bin/env bash
# テンプレートから作ったリポジトリの、最初の1回だけの準備。
#   1. ラベルが無ければ作る  2. CLAUDE.md から「ai-dev-template 自身の作業」の節を消す  3. 診断（doctor）を出す
# ラベル（ai:plan）がもうあれば、何もしない（2回目以降の push では動かない）。
# 必要な環境変数：GH_TOKEN、REPO。出力は Summary 向けの文章。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# CLAUDE.md から「## ai-dev-template 自身の作業」で始まる節（次の「## 」の手前まで）を消す
strip_self_edit() {
  local file="$1" tmp
  [ -f "$file" ] || return 0
  tmp="$(mktemp)"
  awk '
    /^## ai-dev-template 自身の作業/ { skip = 1; next }
    /^## / { skip = 0 }
    !skip { print }
  ' "$file" > "$tmp"
  # 節の外にある、ai-dev-template 自身だけの但し書きも消す
  sed -i -e 's/。ただし ai-dev-template 自身だけ、下の「ai-dev-template 自身の作業」で許した物は触ってよい//' \
    -e 's/（パイプラインの説明。ai-dev-template 自身だけ、`docs\/pipeline.md` は下の節で触ってよい）/（パイプラインの説明）/' "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

has_label() { gh api "repos/$REPO/labels?per_page=100" --paginate --jq '.[].name' | grep -qxF "ai:plan"; }

main() {
  REPO="${REPO:?REPO を指定}"
  if has_label; then echo "準備ずみ（ラベルがある）。何もしません。"; return 0; fi
  echo "## 最初の準備（$REPO）"
  REPO="$REPO" "$HERE/labels.sh" > /dev/null && echo "- ✅ ラベルを作った"
  if [ -f CLAUDE.md ] && grep -q "^## ai-dev-template 自身の作業" CLAUDE.md; then
    strip_self_edit CLAUDE.md
    echo "- ✅ CLAUDE.md から「ai-dev-template 自身の作業」の節を消した"
    echo "CHANGED_CLAUDE_MD=1" >> "${GITHUB_ENV:-/dev/null}"
  fi
  echo
  REPO="$REPO" "$HERE/doctor.sh" || true
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi
