#!/usr/bin/env bash
# 見た目のテストが落ちていたら、その差分の画像（CIの artifact「visual-diff」）を .visual-diff/ に取ってくる。
# 修正AI（claude-mention.yml）が、意図した変更か崩れかを、画像を見て決められるように。
# .visual-diff/ は git に入れない（.git/info/exclude に足す）。画像が無ければ何もしない。
# 環境変数：REPO か GITHUB_REPOSITORY、PR（PR番号）、GH_TOKEN（actions: read）、DIFF_DIR（既定 .visual-diff）
set -uo pipefail
REPO="${REPO:-${GITHUB_REPOSITORY:?}}"
pr="${PR:?PR が要ります}"
dir="${DIFF_DIR:-.visual-diff}"

head=$(gh api "repos/$REPO/pulls/$pr" -q .head.sha 2> /dev/null) || { echo "PR #$pr が読めないので、差分の画像は取りません"; exit 0; }
# 先頭コミットの CI のうち、いちばん新しい失敗した実行
run=$(gh api "repos/$REPO/actions/runs?head_sha=$head&event=pull_request&per_page=20" \
  -q '[.workflow_runs[] | select(.name == "CI" and .conclusion == "failure")] | sort_by(.created_at) | last | .id // empty' 2> /dev/null)
if [ -z "$run" ]; then
  echo "先頭コミットで落ちた CI が無いので、差分の画像は取りません"
  exit 0
fi
has=$(gh api "repos/$REPO/actions/runs/$run/artifacts" -q '[.artifacts[] | select(.name == "visual-diff" and (.expired | not))] | length' 2> /dev/null)
if [ "${has:-0}" -eq 0 ]; then
  echo "落ちた CI（$run）に見た目のテストの差分の画像が無いので、何もしません"
  exit 0
fi
mkdir -p "$dir"
if ! gh run download "$run" --repo "$REPO" --name visual-diff --dir "$dir" > /dev/null 2>&1; then
  echo "::warning::見た目のテストの差分の画像を取ってこられませんでした（$run）"
  exit 0
fi
if [ -d .git/info ] && ! grep -qxF "/${dir#./}/" .git/info/exclude 2> /dev/null; then
  echo "/${dir#./}/" >> .git/info/exclude
fi
n=$(find "$dir" -name '*.png' | wc -l | tr -d ' ')
echo "見た目のテストの差分の画像を ${dir}/ に取ってきました（${n}枚。〜-expected.png が前、〜-actual.png が今、〜-diff.png が違う所）"
