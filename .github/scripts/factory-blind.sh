#!/usr/bin/env bash
# 工場の審査役に、画像だけを見せる（factory.yml の design ジョブ）。
#   factory-blind.sh hide     仕様・使う場面・道具の指定・前の採点・試作の HTML・作業用の物を、作業フォルダの外へ移す
#   factory-blind.sh restore  審査のあとで元に戻す（前の採点は戻さない。審査役が書いた新しい factory-critique.md を残す）
# 環境変数：BLIND_DIR（移す先。既定は $RUNNER_TEMP/factory-blind）
set -euo pipefail
DIR="${BLIND_DIR:-${RUNNER_TEMP:?}/factory-blind}"
FILES="factory-design.md factory-context.md factory-libs.txt"
case "${1:-}" in
  hide)
    rm -rf "$DIR"
    mkdir -p "$DIR/proto"
    for f in $FILES; do [ -e "$f" ] && mv "$f" "$DIR/"; done
    [ -e factory-critique.md ] && mv factory-critique.md "$DIR/old-critique.md"
    [ -e .taste-skill ] && mv .taste-skill "$DIR/taste-skill"
    for f in factory-proto/*.html; do [ -e "$f" ] && mv "$f" "$DIR/proto/"; done
    echo "審査役に見せない物を隠しました"
    ;;
  restore)
    [ -d "$DIR" ] || { echo "隠した物がありません"; exit 0; }
    for f in $FILES; do [ -e "$DIR/$f" ] && mv -f "$DIR/$f" .; done
    [ -e "$DIR/taste-skill" ] && { rm -rf .taste-skill; mv "$DIR/taste-skill" .taste-skill; }
    mkdir -p factory-proto
    for f in "$DIR"/proto/*.html; do [ -e "$f" ] && mv -f "$f" factory-proto/; done
    rm -rf "$DIR"
    echo "隠した物を戻しました"
    ;;
  *) echo "使い方：factory-blind.sh hide|restore" >&2; exit 2 ;;
esac
