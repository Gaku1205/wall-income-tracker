#!/usr/bin/env bash
# Vercel の本番の公開を、まとめて1回だけ頼む（deploy-vercel.yml から、続けてのマージが落ち着いたあとに呼ぶ）。
# Vercel の無料プランは「1日100回まで」なので、マージのたびに Vercel が自分で公開するのをやめ（vercel.json の
# git.deploymentEnabled: false）、ここで最新の main を1回だけ公開する。
#   - 最新の main が、もう公開に成功している（Vercel の状態が success）なら何もしない
#   - 最後に公開に成功したコミットから、パイプラインの物（.github/・docs/pipeline.md）しか変わっていなければ何もしない
#   - そうでなければ、Vercel の API で最新の main を本番に公開する（プロジェクトは、このリポジトリにつながっている物を探す）
# 環境変数：VERCEL_TOKEN、VERCEL_TEAM_ID（任意）、GITHUB_REPOSITORY、GH_TOKEN、VERCEL_API（テスト用）
# 終了コード：公開を頼んだ・何もしなくてよい → 0、頼めなかった → 1
set -uo pipefail
VERCEL_API="${VERCEL_API:-https://api.vercel.com}"
REPO="${GITHUB_REPOSITORY:?}"

if [ -z "${VERCEL_TOKEN:-}" ]; then
  echo "::notice::VERCEL_TOKEN が無いので、ここでは公開しません（vercel.json で Vercel が自分で公開する設定なら、そちらで公開されます）"
  exit 0
fi

head=$(gh api "repos/$REPO/commits/main" -q .sha) || { echo "::error::main の先頭を調べられません"; exit 1; }

# main の直近のコミットのうち、Vercel の公開に成功した物（新しい順に最大30件。飛ばした物は除く）
last_ok=""
for sha in $(gh api "repos/$REPO/commits?sha=main&per_page=30" -q '.[].sha'); do
  # 「Canceled by Ignored Build Step」（vercel.json の ignoreCommand で飛ばした物）も success になるので、公開した物には数えない
  state=$(gh api "repos/$REPO/commits/$sha/status" -q '[.statuses[] | select(.context | startswith("Vercel"))] | sort_by(.updated_at) | last
    | if . == null then "" elif .state == "success" and ((.description // "") | test("Ignored Build Step"; "i")) then "ignored" else .state end' 2> /dev/null || true)
  if [ "$state" = success ]; then last_ok="$sha"; break; fi
done
if [ "$last_ok" = "$head" ]; then
  echo "::notice::最新の main（${head:0:7}）はもう公開されています"
  exit 0
fi
head_state=$(gh api "repos/$REPO/commits/$head/status" -q '[.statuses[] | select(.context | startswith("Vercel"))] | sort_by(.updated_at) | last | .state // ""' 2> /dev/null || true)
if [ "$head_state" = pending ]; then
  echo "::notice::最新の main（${head:0:7}）は、いま公開中です"
  exit 0
fi
if [ -n "$last_ok" ]; then
  changed=$(gh api "repos/$REPO/compare/$last_ok...$head" -q '.files[].filename' 2> /dev/null || true)
  if [ -n "$changed" ] && ! printf '%s\n' "$changed" | grep -vqE '^(\.github/|docs/pipeline\.md$)'; then
    echo "::notice::前の公開（${last_ok:0:7}）から、パイプラインの更新しか変わっていないので公開しません"
    exit 0
  fi
fi

q=""; [ -n "${VERCEL_TEAM_ID:-}" ] && q="&teamId=${VERCEL_TEAM_ID}"
auth=(-H "Authorization: Bearer $VERCEL_TOKEN")
# このリポジトリにつながっている Vercel のプロジェクト（名前がリポジトリと違うことがあるので、つながりで探す）
if ! projects=$(curl -sS "${auth[@]}" "$VERCEL_API/v10/projects?repoUrl=https://github.com/$REPO&limit=5$q"); then
  echo "::error::Vercel に届きませんでした"; exit 1
fi
project=$(printf '%s' "$projects" | jq -r '.projects[0].name // empty' 2> /dev/null)
if [ -z "$project" ]; then
  echo "::error::このリポジトリにつながった Vercel のプロジェクトが見つかりません（$(printf '%s' "$projects" | jq -r '.error.message // "0件"' 2> /dev/null)）"
  exit 1
fi
repo_id=$(gh api "repos/$REPO" -q .id) || { echo "::error::リポジトリの番号を調べられません"; exit 1; }
body=$(jq -nc --arg n "$project" --arg id "$repo_id" --arg sha "$head" \
  '{name: $n, project: $n, target: "production", gitSource: {type: "github", repoId: $id, ref: "main", sha: $sha}}')
dq=""; [ -n "${VERCEL_TEAM_ID:-}" ] && dq="?teamId=${VERCEL_TEAM_ID}"
res=$(printf '%s' "$body" | curl -sS -X POST "$VERCEL_API/v13/deployments${dq}" "${auth[@]}" -H "Content-Type: application/json" --data-binary @-) || res=""
url=$(printf '%s' "$res" | jq -r '.url // empty' 2> /dev/null)
if [ -z "$url" ]; then
  echo "::error::Vercel に公開を頼めませんでした（$(printf '%s' "$res" | jq -r '.error.message // "理由不明"' 2> /dev/null)）"
  exit 1
fi
echo "::notice::最新の main（${head:0:7}）の公開を頼みました：https://$url（プロジェクト $project）"
