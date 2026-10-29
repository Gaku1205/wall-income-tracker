#!/usr/bin/env bash
# AIの許可の確認：ワークフローの --allowedTools と、docs/pipeline.md の「AIの許可」の表が食い違っていないこと
#   食い違うと、表を見て直す人（とAI）が、実際と違う許可を前提にしてしまう
source "$(dirname "$0")/lib.sh"
WORKFLOWS="$(cd "$SCRIPTS_DIR/../workflows" && pwd)"
DOC="$(cd "$SCRIPTS_DIR/../.." && pwd)/docs/pipeline.md"

section=$(python3 - "$DOC" <<'PY'
import re, sys
t = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'## AIの許可.*?(?=\n## )', t, re.S)
print(m.group(0) if m else '')
PY
)
assert_contains "docs に「AIの許可」の節がある" "$section" "## AIの許可"

for f in "$WORKFLOWS"/claude-*.yml; do
  name=$(basename "$f")
  tools=$(python3 - "$f" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'--allowedTools\s+\\?"([^"\\]*)', s)
print('\n'.join(m.group(1).split(',')) if m else '')
PY
)
  if [ -z "$tools" ]; then
    assert_eq "$name：--allowedTools が書いてある" "あり" "なし"
    continue
  fi
  # その行（ワークフローの名前を含む表の行）に、許可している操作が全部あるか
  row=$(printf '%s\n' "$section" | grep -F "\`$name\`" | head -1)
  assert_contains "$name：表に行がある" "$row" "$name"
  while IFS= read -r tool; do
    # 確認コマンドは pipeline.json から入る（setup-stack の出力）。表では「pipeline.json の checks」と書く
    if [ "$tool" = '${{ steps.stack.outputs.allowed }}' ]; then
      assert_contains "$name：確認コマンド（pipeline.json の checks）が表にある" "$row" "pipeline.json の checks"
      continue
    fi
    assert_contains "$name：$tool が表にある" "$row" "\`$tool\`"
  done <<< "$tools"
  # 表に書いてあるのに、ワークフローに無い操作（古い記述）が無いか。「許可している操作」の列だけを見る
  listed=$(printf '%s' "$row" | awk -F'|' '{print $3}' | grep -oE '`[^`]+`' | tr -d '`')
  while IFS= read -r tool; do
    [ -z "$tool" ] && continue
    if printf '%s\n' "$tools" | grep -qxF "$tool"; then PASSED=$((PASSED + 1)); else assert_eq "$name：表の $tool は、ワークフローにもある" "ある" "ない"; fi
  done <<< "$listed"
done

finish
