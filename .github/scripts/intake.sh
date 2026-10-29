#!/usr/bin/env bash
# 新しいIssueを、人間がラベルを付けなくても自動で企画AI（ai:plan）に回す。intake.yml から呼ぶ。
# ai: で始まるラベルが1つでも付いていれば何もしない（自分で ai:queue などを付けた物、ai:skip で止めている物）。
#
# 公開リポジトリでは誰でもIssueを作れるので、オーナー（とパイプライン自身が作る分割Issue）以外が
# 作ったIssueは、自動で動かさず ai:skip で止める。オーナーが ai:skip を外せば、そのまま企画に回る。
#
# 環境変数：NUMBER、ACTION（opened か unlabeled）
source "$(dirname "$0")/pipeline-lib.sh"
has_pipeline_token || { echo "PIPELINE_TOKEN が無いので何もしません"; exit 0; }

if [ "${ACTION:-opened}" = "opened" ]; then
  author=$(gh api "repos/$REPO/issues/$NUMBER" -q '.user.login') || exit 1
  case "${author,,}" in
    "${OWNER,,}" | "claude[bot]") ;;
    *)
      has_label "$NUMBER" "ai:skip" || add_label "$NUMBER" "ai:skip"
      echo "#$NUMBER：オーナー以外（$author）が作ったので、ai:skip で止めました"
      exit 0
      ;;
  esac
fi

# 作った直後にラベルを付ける人・スクリプトがいるので、少し待ってから見る
sleep "${INTAKE_WAIT_SEC:-15}"
if needs_intake "$NUMBER"; then
  # オーナーのトークンで付けるので、企画AIのワークフローが動く
  add_label "$NUMBER" "ai:plan"
  echo "#$NUMBER：ラベルが無かったので、企画に回しました"
else
  echo "#$NUMBER：すでにパイプラインのラベルがあるので何もしません"
fi
