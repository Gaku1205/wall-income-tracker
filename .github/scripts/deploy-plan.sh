#!/usr/bin/env bash
# 公開の計画：pipeline.json の deploy から、どの公開先を動かすかを決めて GITHUB_OUTPUT に書く。deploy.yml から呼ぶ。
#   apprunner=true/false、release=true/false、release_os=["windows-latest",...]、expo=true/false、skip_reason=...
# パイプラインの更新だけのコミット（.github/ と docs/pipeline.md だけ）は公開しない（Vercel の ignoreCommand と同じ考え）。
# 環境変数：GITHUB_OUTPUT（無ければ標準出力に書く）、CHANGED_FILES（テスト用。無ければ git diff HEAD^ HEAD で調べる）
source "$(dirname "$0")/stack.sh"
out="${GITHUB_OUTPUT:-/dev/stdout}"

errs=$(stack_validate)
if [ -n "$errs" ]; then
  while IFS= read -r e; do echo "::error title=pipeline.json::$e"; done <<< "$errs"
  exit 1
fi

if [ -n "${CHANGED_FILES+x}" ]; then
  changed="$CHANGED_FILES"
else
  changed=$(git diff --name-only HEAD^ HEAD 2> /dev/null || true)
fi
skip=""
if [ -n "$changed" ] && ! printf '%s\n' "$changed" | grep -vqE '^(\.github/|docs/pipeline\.md$)'; then
  skip="パイプラインの更新だけのコミットなので公開しません"
fi

kinds=$(stack_deploy_kinds)
has() { [ -z "$skip" ] && printf '%s\n' "$kinds" | grep -qx "$1" && echo true || echo false; }
{
  echo "apprunner=$(has aws-apprunner)"
  echo "release=$(has github-release)"
  echo "expo=$(has expo)"
  # 公開先の設定（同じ種類が複数あれば最初の1つ）
  echo "apprunner_config=$(stack_deploy aws-apprunner | head -n 1)"
  echo "release_config=$(stack_deploy github-release | head -n 1)"
  echo "expo_config=$(stack_deploy expo | head -n 1)"
  echo "release_os=$(stack_deploy github-release | head -n 1 | jq -c '.os // ["windows-latest"]' 2> /dev/null || echo '[]')"
  echo "skip_reason=$skip"
} >> "$out"
[ -n "$skip" ] && echo "$skip"
echo "公開先：$(printf '%s' "$kinds" | paste -sd, - || true)"
