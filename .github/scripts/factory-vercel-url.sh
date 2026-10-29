#!/usr/bin/env bash
# 工場：Vercel のプロジェクトの、本番の公開アドレスを調べる（最初の公開が終わるまで、少し待つ）。
# 見つかったら GitHub のリポジトリの Website 欄にも入れる（リポジトリの画面から開けるように）。
# 環境変数：VERCEL_TOKEN、PROJECT、REPO_FULL（owner/repo。Website 欄に入れる先）、GH_TOKEN、VERCEL_TEAM_ID（任意）、
#           URL_WAIT_TRIES（既定 36）・FACTORY_WAIT_SEC（既定 5）、VERCEL_API（テスト用）
# 出力：https://〜（見つからなければ何も出さず、終了コード 1）
set -uo pipefail
VERCEL_API="${VERCEL_API:-https://api.vercel.com}"
[ -n "${VERCEL_TOKEN:-}" ] || exit 1
q=""; [ -n "${VERCEL_TEAM_ID:-}" ] && q="?teamId=${VERCEL_TEAM_ID}"
for _ in $(seq 1 "${URL_WAIT_TRIES:-36}"); do
  # 本番のドメイン（ブランチに結び付いていない物）。独自ドメインがあればそれを、無ければ *.vercel.app を選ぶ
  domain=$(curl -sS "$VERCEL_API/v9/projects/${PROJECT:?}/domains$q" -H "Authorization: Bearer $VERCEL_TOKEN" 2> /dev/null \
    | jq -r '[.domains // [] | .[] | select(.gitBranch == null) | .name] | (map(select(endswith(".vercel.app") | not)) + map(select(endswith(".vercel.app")))) | .[0] // empty' 2> /dev/null)
  if [ -n "$domain" ]; then
    url="https://$domain"
    [ -n "${REPO_FULL:-}" ] && gh api -X PATCH "repos/$REPO_FULL" -f homepage="$url" > /dev/null 2>&1
    echo "$url"
    exit 0
  fi
  sleep "${FACTORY_WAIT_SEC:-5}"
done
exit 1
