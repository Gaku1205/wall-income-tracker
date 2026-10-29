#!/usr/bin/env bash
# セットアップの診断：新しいリポジトリでパイプラインが動く状態かを、1回で全部チェックする。
# 結果は ✅（OK）・⚠️（動くが直したほうがよい）・❌（これが無いと動かない）で出す。❌ が1つでもあれば終了コード 1。
# 環境変数：REPO（owner/name）、GH_TOKEN、HAS_OAUTH / HAS_PIPELINE_TOKEN / HAS_NTFY（Secret が入っていれば 1）、PIPELINE_TOKEN（権限の確認用）
set -uo pipefail

NG=0
ok()   { echo "- ✅ $1"; }
warn() { echo "- ⚠️ $1 → $2"; }
ng()   { echo "- ❌ $1 → $2"; NG=$((NG + 1)); }

# 外に出る部分（テストでは差し替える）
fetch_labels()        { gh api "repos/$REPO/labels?per_page=100" --paginate --jq '.[].name'; }
# この設定は管理者の権限が無いと見えない（空で返る）。PIPELINE_TOKEN で見て、だめなら標準のトークンで見る
fetch_delete_branch() {
  local v=""
  [ -n "${PIPELINE_TOKEN:-}" ] && v=$(GH_TOKEN="$PIPELINE_TOKEN" gh api "repos/$REPO" --jq '.delete_branch_on_merge // empty' 2> /dev/null)
  [ -z "$v" ] && v=$(gh api "repos/$REPO" --jq '.delete_branch_on_merge // empty' 2> /dev/null)
  echo "$v"
}
# 既定のブランチ（main）が保護されているか：true / false / 空（読めない）。読み取りの権限で見える
fetch_main_protected() {
  local b
  b=$(gh api "repos/$REPO" --jq '.default_branch // empty' 2> /dev/null) || b=""
  [ -n "$b" ] || return 0
  gh api "repos/$REPO/branches/$b" --jq '.protected' 2> /dev/null || true
}
is_template_repo()    { [ "$(gh api "repos/$REPO" --jq '.is_template' 2> /dev/null)" = true ]; }
# Fine-grained トークンの期限（GitHub が返事のヘッダーで教えてくれる。期限なしなら空）
token_expiration()    { GH_TOKEN="${PIPELINE_TOKEN:-}" gh api -i "repos/$REPO" 2> /dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="github-authentication-token-expiration"{print $2; exit}'; }
# App の鍵では、リポジトリの情報に permissions が付かない。App が入っているリポジトリの一覧に、このリポジトリがあるかで見る
app_installed_here()  { GH_TOKEN="${PIPELINE_TOKEN:-}" gh api "installation/repositories?per_page=100" --paginate --jq '.repositories[].full_name' 2> /dev/null | grep -qixF "$REPO"; }
token_can_push()      { GH_TOKEN="${PIPELINE_TOKEN:-}" gh api "repos/$REPO" --jq '.permissions.push' 2>/dev/null; }

check_secrets() {
  if [ "${HAS_OAUTH:-}" = 1 ]; then ok "CLAUDE_CODE_OAUTH_TOKEN が登録されている"
  else ng "CLAUDE_CODE_OAUTH_TOKEN が無い" "Settings → Secrets → Actions に、claude setup-token で作ったトークンを登録"; fi
  if [ "${APP_TOKEN_FAILED:-0}" = 1 ]; then
    ng "GitHub App の鍵を作れない（PIPELINE_TOKEN で代わりに動いている）" "App ID（Variable PIPELINE_APP_ID）と秘密鍵（Secret PIPELINE_APP_PRIVATE_KEY：.pem の中身を -----BEGIN から -----END ... KEY----- まで全部）を確かめ、App をこのリポジトリに Install する"
  fi
  if [ "${HAS_PIPELINE_TOKEN:-}" != 1 ]; then
    ng "パイプラインの鍵が無い" "GitHub App（Variable PIPELINE_APP_ID と Secret PIPELINE_APP_PRIVATE_KEY）か、Secret PIPELINE_TOKEN を登録（docs/pipeline.md の「必要な設定」）"
  elif [ "${USING_APP:-0}" = 1 ]; then
    if app_installed_here; then ok "GitHub App の鍵でこのリポジトリを操作できる（回数制限はオーナーと別・期限切れなし）"
    else ng "GitHub App がこのリポジトリに入っていない" "App の設定（Install App → ⚙️）で、このリポジトリを選ぶ"; fi
  elif [ "$(token_can_push)" = true ]; then
    ok "PIPELINE_TOKEN でこのリポジトリに書き込める"; check_token_expiration
    warn "GitHub App ではなく PIPELINE_TOKEN を使っている" "回数制限をオーナーと共有し、期限もある。GitHub App に切り替えるとよい（docs/pipeline.md）"
  else ng "PIPELINE_TOKEN でこのリポジトリに書き込めない" "トークンの Repository access にこのリポジトリを足す"; fi
  if [ "${HAS_NTFY:-}" = 1 ]; then ok "NTFY_TOPIC が登録されている（通知が届く）"
  else warn "NTFY_TOPIC が無い" "スマホ通知が鳴らない。ntfy のトピック名を Secret に登録"; fi
}

# 期限が来るとパイプラインが全部止まるので、30日前から警告する
check_token_expiration() {
  local exp days
  exp="$(token_expiration)"
  if [ -z "$exp" ]; then ok "PIPELINE_TOKEN に期限が無い（または期限を読めない）"; return; fi
  days=$(( ( $(date -d "$exp" +%s 2> /dev/null || echo 0) - $(date +%s) ) / 86400 ))
  if [ "$days" -lt 0 ]; then ng "PIPELINE_TOKEN の期限が切れている（$exp）" "トークンを作り直し（Regenerate）、Secret を登録し直す"
  elif [ "$days" -lt 30 ]; then warn "PIPELINE_TOKEN の期限まであと ${days} 日（$exp）" "期限が来るとパイプラインが止まる。トークンの設定で期限を延ばす（Regenerate）"
  else ok "PIPELINE_TOKEN の期限まであと ${days} 日（$exp）"; fi
}

check_labels() {
  local have missing="" l
  have="$(fetch_labels)"
  for l in ai:plan ai:implement ai:review ai:queue ai:hold ai:stuck ai:skip ai:retry visual:update size:S size:L; do
    printf '%s\n' "$have" | grep -qxF "$l" || missing="$missing $l"
  done
  if [ -z "$missing" ]; then ok "ラベルが全部ある"
  else ng "ラベルが足りない:${missing}" "Actions の「Setup Labels」を1回実行"; fi
}

check_settings() {
  local v
  v="$(fetch_delete_branch)"
  if [ "$v" = true ]; then ok "マージ後にブランチを自動で消す設定がオン"
  elif [ "$v" = false ]; then warn "「Automatically delete head branches」がオフ" "Settings → General → Pull Requests でオン（オフでも進行役が掃除はする）"
  else echo "- ➖ 「Automatically delete head branches」はトークンの権限では見えないので確かめていない（オフでも進行役が掃除はする）"; fi
  v="$(fetch_main_protected)"
  if [ "$v" = true ]; then ok "main が保護されている（PRを通さないと入らない）"
  elif [ "$v" = false ]; then warn "main が保護されていない（AIが PR とレビューを通さずに main へ push できてしまう）" "Settings → Branches → Add classic branch protection rule で、main に「Require a pull request before merging」（承認0人でよい）と「Require status checks to pass」を付け、検索欄で check（CI のジョブの名前）を選ぶ"
  else echo "- ➖ main の保護は読めなかったので確かめていない"; fi
}

check_files() {
  local f s
  for f in CLAUDE.md AGENTS.md docs/spec.md; do
    if [ -f "$f" ]; then ok "$f がある"
    elif [ "$f" = AGENTS.md ]; then ng "AGENTS.md が無い" "空のファイルでよいので作る（中身は Next.js 向けの注意。Next.js 以外なら空のままでよい）"
    else ng "$f が無い" "テンプレートから作り、アプリのことを書く"; fi
  done
  # テンプレート（本体）の CLAUDE.md は、わざと書きかけのまま（作ったリポジトリで書く）
  if [ -f CLAUDE.md ] && grep -q "（アプリの説明を1〜2行で書く）" CLAUDE.md && ! is_template_repo; then
    ng "CLAUDE.md がテンプレートのまま" "アプリの説明を書き、「ai-dev-template 自身の作業」の節を消す"
  fi
  if [ -f CLAUDE.md ] && grep -q "pipeline-self-edit: auto" CLAUDE.md && ! is_template_repo; then
    warn "CLAUDE.md に pipeline-self-edit の印が残っている" "ai-dev-template 自身の節ごと消す（残るとパイプラインの変更が自動でマージされる）"
  fi
  check_stack
}

# 言語と確認コマンド：pipeline.json があればその中身を、無ければ今までの Next.js（package.json）を見る
check_stack() {
  local s errs n
  if [ -f pipeline.json ]; then
    errs=$(bash -c "source '$(dirname "${BASH_SOURCE[0]}")/stack.sh'; stack_validate")
    if [ -n "$errs" ]; then
      while IFS= read -r s; do ng "pipeline.json：$s" "docs/pipeline.md「言語と公開先」の形に直す"; done <<< "$errs"
      return
    fi
    n=$(jq '.checks | length' pipeline.json)
    ok "pipeline.json がある（実行環境：$(jq -r '.tools // {} | to_entries | map("\(.key) \(.value)") | join("・") | if . == "" then "なし" else . end' pipeline.json)・確認コマンド ${n} 個）"
    check_deploy
    return
  fi
  if [ -f package.json ]; then
    for s in typecheck lint build; do
      if grep -q "\"$s\"[[:space:]]*:" package.json; then ok "npm run $s がある"
      else ng "package.json に $s のスクリプトが無い" "CLAUDE.md の「終わる前に実行する」コマンドと同じ名前で足す"; fi
    done
    # テストは無くても動く（CIは、無ければ飛ばす）。ただし無いと、AIの変更を確かめる物が減る
    if grep -q "\"test\"[[:space:]]*:" package.json; then ok "npm run test がある"
    else warn "package.json に test のスクリプトが無い" "動くが、AIの変更を確かめにくい。vitest を入れて \"test\": \"vitest run\" を足す"; fi
  else
    ng "pipeline.json も package.json も無い" "Next.js 以外なら、pipeline.json に言語・確認コマンド・公開先を書く（docs/pipeline.md「言語と公開先」）"
  fi
}

# 公開先ごとに、要る設定がそろっているか
check_deploy() {
  local kind
  while IFS= read -r kind; do
    case "$kind" in
      vercel) echo "- ➖ 公開先：Vercel（Vercel の画面でこのリポジトリを読み込む。ここからは確かめられない）" ;;
      none) ok "公開先：なし" ;;
      github-release) ok "公開先：GitHub Releases（追加の設定は要らない）" ;;
      aws-apprunner)
        if [ "${HAS_AWS_ROLE:-0}" = 1 ] && [ "${HAS_AWS_REGION:-0}" = 1 ] && [ "${HAS_APPRUNNER_ACCESS:-0}" = 1 ]; then
          ok "公開先：AWS App Runner（Variable の AWS_ROLE_ARN・AWS_REGION・AWS_APPRUNNER_ACCESS_ROLE_ARN がある）"
        else
          ng "公開先 AWS App Runner の設定が足りない" "Settings → Secrets and variables → Actions → Variables に AWS_ROLE_ARN・AWS_REGION・AWS_APPRUNNER_ACCESS_ROLE_ARN（docs/pipeline.md「AWS App Runner」。CloudFormation で1回作れば出てくる）"
        fi ;;
      expo)
        if [ "${HAS_EXPO:-0}" = 1 ]; then ok "公開先：Expo（Secret の EXPO_TOKEN がある）"
        else ng "公開先 Expo の鍵が無い" "expo.dev → Access tokens で作り、Secret の EXPO_TOKEN に登録"; fi ;;
    esac
  done < <(bash -c "source '$(dirname "${BASH_SOURCE[0]}")/stack.sh'; stack_deploy_kinds")
}

main() {
  REPO="${REPO:?REPO を指定}"
  echo "## パイプラインの診断（$REPO）"
  echo; echo "### Secret"; check_secrets
  echo; echo "### ラベル・設定"; check_labels; check_settings
  echo; echo "### ファイル"; check_files
  echo
  if [ "$NG" -eq 0 ]; then echo "**問題なし。Issue を書けば動く。**"
  else echo "**❌ が ${NG} 件。上の「→」のとおり直してから、もう一度実行。**"; fi
  [ "$NG" -eq 0 ]
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi
