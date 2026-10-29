#!/usr/bin/env bash
# 工場：GitHub のリポジトリを、新しい Vercel のプロジェクトにつなぐ（Next.js）。つないだあとの push で、Vercel が公開を始める。
# factory.sh（新しく作るとき）と factory-vercel.yml（あとからつなぐとき）から呼ぶ。
# 環境変数：VERCEL_TOKEN、REPO_FULL（owner/repo）、PROJECT（プロジェクト名）、VERCEL_TEAM_ID（任意）、VERCEL_API（テスト用）
# 出力：つないだらプロジェクト名、だめなら理由（終了コード 1）
set -uo pipefail
VERCEL_API="${VERCEL_API:-https://api.vercel.com}"
if [ -z "${VERCEL_TOKEN:-}" ]; then
  echo "VERCEL_TOKEN が無いので、Vercel にはつないでいません（Vercel の画面で Import するまで公開されません）"
  exit 1
fi
q=""; [ -n "${VERCEL_TEAM_ID:-}" ] && q="?teamId=${VERCEL_TEAM_ID}"
body=$(jq -nc --arg n "${PROJECT:?}" --arg r "${REPO_FULL:?}" '{name: $n, framework: "nextjs", gitRepository: {type: "github", repo: $r}}')
if ! res=$(printf '%s' "$body" | curl -sS -X POST "$VERCEL_API/v11/projects$q" -H "Authorization: Bearer $VERCEL_TOKEN" -H "Content-Type: application/json" --data-binary @- 2>&1); then
  echo "Vercel に届きませんでした"
  exit 1
fi
name=$(printf '%s' "$res" | jq -r '.name // empty' 2> /dev/null)
# もうつないである（同じ名前のプロジェクトがある）なら、それを使う（あとからアドレスだけ調べ直すとき）
if [ -z "$name" ] && [ "$(printf '%s' "$res" | jq -r '.error.code // empty' 2> /dev/null)" = "conflict" ]; then
  name="$PROJECT"
fi
if [ -z "$name" ]; then
  msg=$(printf '%s' "$res" | jq -r '.error.message // empty' 2> /dev/null)
  echo "Vercel のプロジェクトを作れませんでした（${msg:-理由不明}）。Vercel の GitHub 連携が、このリポジトリを見られるか確かめる"
  exit 1
fi
echo "$name"
