#!/usr/bin/env bash
# 工場：ai-dev-template に書いた1行のIssue（「新サービス：〜」）から、新しいサービスのリポジトリを作って、パイプラインに渡す。
# factory.yml の build ジョブから呼ぶ（AIが決めた名前と言語は、ここで形を確かめてから使う）。
#   1. テンプレートからリポジトリを作る（同じ名前があれば -2, -3 … を付ける）
#   2. パイプラインの秘密と変数を、テンプレートの物から写す
#   3. Vercel のプロジェクトを作ってつなぐ（Next.js で VERCEL_TOKEN があるとき）
#   4. 中身を整えて main に push する（CLAUDE.md・仕様書の説明、デザイン仕様、デザイン部門が選んだ GSAP・Lenis、Python なら見本に切り替え）。この push で Bootstrap が動く
#   5. main を守る（PRとCIの check を必須にする。管理者は通れる）
#   6. Bootstrap がラベルを作るのを待って、1行のメモを最初のIssueにする（そこから先はいつものパイプライン）
#   7. 元のIssueに結果を書いて閉じる
#
# 環境変数：
#   GH_TOKEN（FACTORY_TOKEN：リポジトリを作れる鍵）、TEMPLATE（owner/repo）、ISSUE（元のIssueの番号）、MEMO（1行のメモ）
#   APP_NAME・APP_STACK（nextjs か python）・APP_DESC（1行の説明）：AIが決めた物
#   S_<名前>：写す秘密の値（S_CLAUDE_CODE_OAUTH_TOKEN など）、V_<名前>：写す変数の値（V_PIPELINE_APP_ID など）
#   DESIGN_FILE・CONTEXT_FILE・LIBS_FILE（任意）：デザイン部門が書いたデザイン仕様・使う人と場面・入れる動きの道具（1行1つ）
#   VERCEL_TOKEN・VERCEL_TEAM_ID（任意）、COMMENT_TOKEN（元のIssueにコメントする鍵。無ければ GH_TOKEN）
#   テスト用：FACTORY_GIT_URL（clone 先の書式。%s にリポジトリ名）、VERCEL_API、FACTORY_WAIT_SEC
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OWNER="${TEMPLATE%%/*}"
WAIT="${FACTORY_WAIT_SEC:-5}"
GIT_URL="${FACTORY_GIT_URL:-https://x-access-token:${GH_TOKEN}@github.com/%s.git}"
VERCEL_API="${VERCEL_API:-https://api.vercel.com}"
COPY_SECRETS="CLAUDE_CODE_OAUTH_TOKEN PIPELINE_APP_PRIVATE_KEY PIPELINE_TOKEN NTFY_TOPIC VERCEL_TOKEN"
COPY_VARS="PIPELINE_APP_ID NOTIFY_EVENTS AGENT_DESK_URL VERCEL_TEAM_ID"
report=()
note() { report+=("$1"); echo "$1"; }
fail() {
  note "❌ $1"
  say_result "⚠️ 新しいサービスを作る途中で止まりました"
  exit 1
}
say_result() {
  local body
  body="$1

$(printf -- '- %s\n' "${report[@]}")"
  GH_TOKEN="${COMMENT_TOKEN:-$GH_TOKEN}" gh api "repos/$TEMPLATE/issues/$ISSUE/comments" -f body="$body" > /dev/null 2>&1 || true
}

# ---- 0. AIが決めた物の形を確かめる（ここで使う値は、この形の物だけ） ----
valid_plan() {
  [[ "$APP_NAME" =~ ^[a-z][a-z0-9-]{2,38}$ ]] || { echo "名前「$APP_NAME」は小文字の英数字と - で3〜39文字にする"; return 1; }
  case "$APP_STACK" in nextjs | python) ;; *) echo "言語「$APP_STACK」は nextjs か python"; return 1 ;; esac
  [ -n "$APP_DESC" ] && [ "${#APP_DESC}" -le 120 ] || { echo "説明は1〜120文字"; return 1; }
  case "$APP_DESC" in *$'\n'* | *'`'* | *'$('*) echo "説明に改行・記号（\` \$( ）は使わない"; return 1 ;; esac
}
why=$(valid_plan) || fail "AIが決めた名前・言語・説明の形が正しくありません：$why"

# ---- 1. リポジトリを作る ----
name="$APP_NAME"
for i in 2 3 4 5 6 7 8 9; do
  gh api "repos/$OWNER/$name" > /dev/null 2>&1 || break
  name="${APP_NAME}-$i"
done
gh api "repos/$OWNER/$name" > /dev/null 2>&1 && fail "同じ名前のリポジトリがもうあります（$OWNER/$APP_NAME から -9 まで）"
NEW="$OWNER/$name"
if ! out=$(gh api -X POST "repos/$TEMPLATE/generate" -f owner="$OWNER" -f name="$name" -f description="$APP_DESC" -F private=false 2>&1); then
  fail "リポジトリを作れませんでした（$(printf '%s' "$out" | tail -1 | cut -c1-160)）。FACTORY_TOKEN に、全部のリポジトリへの Administration（Read and write）が要ります"
fi
note "✅ リポジトリを作った：https://github.com/$NEW（${APP_STACK}）"
ready=no
for _ in $(seq 1 30); do
  if gh api "repos/$NEW/branches/main" > /dev/null 2>&1; then ready=yes; break; fi
  sleep "$WAIT"
done
[ "$ready" = yes ] || fail "作ったリポジトリの main が用意できません"

# ---- 2. 秘密と変数を写す ----
copied=()
for n in $COPY_SECRETS; do
  v="S_$n"; val="${!v:-}"
  [ -z "$val" ] && continue
  # Vercel の鍵は、Vercel で公開する物（Next.js）にだけ入れる（公開をまとめて頼む deploy-vercel.yml が使う）
  [ "$n" = VERCEL_TOKEN ] && [ "$APP_STACK" != nextjs ] && continue
  if printf '%s' "$val" | gh secret set "$n" --repo "$NEW" > /dev/null 2>&1; then copied+=("$n"); else note "⚠️ 秘密 $n を写せませんでした（FACTORY_TOKEN に Secrets（Read and write）が要ります）"; fi
done
for n in $COPY_VARS; do
  v="V_$n"; val="${!v:-}"
  [ -z "$val" ] && continue
  if gh variable set "$n" --repo "$NEW" --body "$val" > /dev/null 2>&1; then copied+=("$n"); else note "⚠️ 変数 $n を写せませんでした（FACTORY_TOKEN に Variables（Read and write）が要ります）"; fi
done
[ "${#copied[@]}" -gt 0 ] && note "✅ 秘密と変数を写した：${copied[*]}"

# ---- 3. Vercel ----
vercel_note=""
if [ "$APP_STACK" = nextjs ]; then
  if vout=$(REPO_FULL="$NEW" PROJECT="$name" "$HERE/factory-vercel.sh" 2>&1); then
    note "✅ Vercel のプロジェクトを作ってつないだ"
    vercel_note="Vercel：$vout"
  else
    note "⚠️ $vout"
  fi
fi

# ---- 4. 中身を整えて push ----
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# shellcheck disable=SC2059
if ! git clone -q "$(printf "$GIT_URL" "$NEW")" "$work/app" 2> /dev/null; then fail "作ったリポジトリを clone できません"; fi
(
  cd "$work/app" || exit 1
  # CLAUDE.md の1行目の説明と、仕様書の「目的」を書く（説明やメモの記号で壊れないよう、置き換えは python で文字のまま行う）
  NAME="$name" python3 - <<'PY2'
import os
name, desc, memo = os.environ["NAME"], os.environ["APP_DESC"], os.environ["MEMO"]
def swap(path, old, new):
    s = open(path, encoding="utf-8").read()
    open(path, "w", encoding="utf-8").write(s.replace(old, new, 1))
swap("CLAUDE.md", "（アプリの説明を1〜2行で書く）。", f"{name}：{desc.rstrip('。')}。")
# テンプレート本体だけの物を消す：「ai-dev-template 自身の作業」の節（自分のスクリプトを自動でマージしてよい印を含む）、その但し書き、
# Next.js 以外の言語への案内（工場が言語を決めて切り替えるので要らない）。Bootstrap も消すが、作った直後の Bootstrap は
# 鍵が写される前に動いてコミットできないことがあるので、ここで確実に消す
import re
s = open("CLAUDE.md", encoding="utf-8").read()
s = re.sub(r"\n## ai-dev-template 自身の作業.*?(?=\n## )", "\n", s, count=1, flags=re.S)
s = s.replace("。ただし ai-dev-template 自身だけ、下の「ai-dev-template 自身の作業」で許した物は触ってよい", "")
s = s.replace("（パイプラインの説明。ai-dev-template 自身だけ、`docs/pipeline.md` は下の節で触ってよい）", "（パイプラインの説明）")
s = re.sub(r"（Next\.js 以外で作るなら[^）]*）", "", s, count=1)
open("CLAUDE.md", "w", encoding="utf-8").write(s)
swap("docs/spec.md", "（誰の、どんな困りごとを、どう減らすか）", f"{desc}（元のメモ：{memo}）")
# README は、テンプレートの説明ではなく、このサービスの説明にする
template = os.environ["TEMPLATE"]
open("README.md", "w", encoding="utf-8").write(f"""# {name}

{desc}

- 仕様：[docs/spec.md](docs/spec.md)
- 見た目：[docs/design.md](docs/design.md)

[{template.split('/')[1]}](https://github.com/{template}) の工場で、1行のメモ（{memo}）から作ったサービスです。Issue を書くと、AI が清書・実装・レビュー・マージまで進めます（[docs/pipeline.md](docs/pipeline.md)）。
""")
PY2
  if [ "$APP_STACK" = python ]; then
    "$HERE/factory-python.sh" . || exit 1
  fi
  # デザイン部門が書いた「使う人・使う場面」を、仕様書の「前提」の「使う人：」に入れる（短い箇条書きだけ）
  if [ -n "${CONTEXT_FILE:-}" ] && [ -f "$CONTEXT_FILE" ] && [ ! -L "$CONTEXT_FILE" ] && [ "$(wc -c < "$CONTEXT_FILE")" -le 2000 ]; then
    CONTEXT_FILE="$CONTEXT_FILE" python3 - <<'PY3'
import os
ctx = [l.rstrip() for l in open(os.environ["CONTEXT_FILE"], encoding="utf-8") if l.strip().startswith(("-", "*"))][:6]
if ctx:
    body = "\n".join("  " + l.lstrip().replace("* ", "- ", 1) for l in ctx)
    s = open("docs/spec.md", encoding="utf-8").read()
    s = s.replace("- 使う人：\n", "- 使う人・使う場面（デザイン部門の分析。推定を含む）：\n" + body + "\n", 1)
    open("docs/spec.md", "w", encoding="utf-8").write(s)
PY3
  fi
  # デザイン部門が書いたデザイン仕様（形が正しいときだけ。だめなら雛形のまま）
  if [ -n "${DESIGN_FILE:-}" ] && [ -f "$DESIGN_FILE" ] && [ ! -L "$DESIGN_FILE" ]; then
    size=$(wc -c < "$DESIGN_FILE")
    if [ "$(head -1 "$DESIGN_FILE")" = "# デザイン仕様" ] && [ "$size" -ge 800 ] && [ "$size" -le 60000 ]; then
      cp "$DESIGN_FILE" docs/design.md
      echo "DESIGN=yes" > "$work/design.flag"
    else
      echo "DESIGN=bad" > "$work/design.flag"
    fi
  fi
  # デザイン部門が選んだ動きの道具（GSAP・Lenis）。デザイン仕様を使うときだけ、決まった3つの中からだけ入れる
  # （アプリの AI は依存パッケージを足せないので、作るときに工場が入れておく）
  if [ "$APP_STACK" = nextjs ] && [ "$(cat "$work/design.flag" 2> /dev/null)" = DESIGN=yes ] &&
    [ -n "${LIBS_FILE:-}" ] && [ -f "$LIBS_FILE" ] && [ ! -L "$LIBS_FILE" ] && [ "$(wc -c < "$LIBS_FILE")" -le 200 ]; then
    pkgs=()
    while IFS= read -r lib; do
      lib="$(printf '%s' "$lib" | tr -d '[:space:]')"
      case "$lib" in
        gsap) pkgs+=("gsap@^3" "@gsap/react@^2") ;;
        @gsap/react) pkgs+=("gsap@^3" "@gsap/react@^2") ;;
        lenis) pkgs+=("lenis@^1") ;;
        "") ;;
        *) echo "LIBS_SKIPPED=yes" >> "$work/libs.flag" ;;
      esac
    done < "$LIBS_FILE"
    if [ "${#pkgs[@]}" -gt 0 ]; then
      mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
      if npm install --package-lock-only --no-audit --no-fund --save "${pkgs[@]}" > "$work/npm.log" 2>&1; then
        echo "LIBS=${pkgs[*]}" >> "$work/libs.flag"
      else
        git checkout -q -- package.json package-lock.json 2> /dev/null || true
        echo "LIBS_FAILED=yes" >> "$work/libs.flag"
      fi
    fi
  fi
  # Vercel の鍵を入れたら、Vercel がマージのたびに自分で公開するのを止め、deploy-vercel.yml が落ち着いてから1回だけ公開する
  # （無料プランの「1日100回まで」に当たらないように）。鍵が無いときは今までどおり Vercel が自分で公開する
  if [ "$APP_STACK" = nextjs ] && [ -n "${S_VERCEL_TOKEN:-}" ] && [ -f vercel.json ]; then
    jq '.git.deploymentEnabled = false' vercel.json > vercel.json.new && mv vercel.json.new vercel.json
  fi
  # 工場は テンプレートの例（examples/）を新しいサービスには持ち込まない
  rm -rf examples
  # 工場のIssueの雛形も、テンプレート本体だけの物
  rm -f .github/ISSUE_TEMPLATE/new-service.yml
  git add -A
  git -c user.name="pipeline-factory" -c user.email="noreply@github.com" commit -q -m "工場：${name} の最初の準備（${APP_STACK}）"
  git push -q origin HEAD:main
) || fail "最初の準備を push できませんでした"
note "✅ CLAUDE.md・仕様書・README に説明を書いて push した（Bootstrap が動く）"
# Vercel が自分で公開しない形（上の deploymentEnabled: false）にしたので、最初の公開はここで頼む（あとは deploy-vercel.yml）
if [ -n "$vercel_note" ] && [ -n "${S_VERCEL_TOKEN:-}" ]; then
  if dout=$(GITHUB_REPOSITORY="$NEW" VERCEL_TOKEN="$S_VERCEL_TOKEN" VERCEL_TEAM_ID="${VERCEL_TEAM_ID:-}" "$HERE/deploy-vercel.sh" 2>&1); then
    note "✅ 最初の公開を頼んだ（このあとは、マージが落ち着いてから最新の main を1回だけ公開する）"
  else
    note "⚠️ 最初の公開を頼めませんでした（$(printf '%s' "$dout" | tail -1 | sed 's/^::error:://' | cut -c1-160)）。次のマージのあとに公開されます"
  fi
fi
case "$(cat "$work/design.flag" 2> /dev/null)" in
  DESIGN=yes) note "✅ デザイン部門：使う場面を分析して、このサービスのデザイン仕様（docs/design.md）を書き、別の目で検査した" ;;
  DESIGN=bad) note "⚠️ デザイン部門が書いたデザイン仕様の形が違ったので、雛形のままにした" ;;
esac
libs_line=$(grep '^LIBS=' "$work/libs.flag" 2> /dev/null | head -1)
[ -n "$libs_line" ] && note "✅ デザイン部門が選んだ動きの道具を入れた：${libs_line#LIBS=}"
grep -q '^LIBS_FAILED=' "$work/libs.flag" 2> /dev/null && note "⚠️ 動きの道具（GSAP・Lenis）を入れられませんでした（npm install が失敗。入れずに進めた）"
grep -q '^LIBS_SKIPPED=' "$work/libs.flag" 2> /dev/null && note "⚠️ デザイン部門が、決まった物（gsap・@gsap/react・lenis）以外の道具を書いていたので、それは入れなかった"

# ---- 5. main を守る ----
ruleset=$(jq -nc '{
  name: "main を守る", target: "branch", enforcement: "active",
  conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
  rules: [
    {type: "pull_request", parameters: {required_approving_review_count: 0, dismiss_stale_reviews_on_push: false, require_code_owner_review: false, require_last_push_approval: false, required_review_thread_resolution: false}},
    {type: "required_status_checks", parameters: {strict_required_status_checks_policy: false, required_status_checks: [{context: "check"}]}}
  ],
  bypass_actors: [{actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "always"}]
}')
if printf '%s' "$ruleset" | gh api -X POST "repos/$NEW/rulesets" --input - > /dev/null 2>&1; then
  note "✅ main を守った（PRと CI の check が必須。管理者は通れる）"
else
  note "⚠️ main を守る設定を作れませんでした（Settings → Rules → Rulesets で作る。README の手順6）"
fi

# ---- 6. 最初のIssue ----
labels=no
for _ in $(seq 1 36); do
  if gh api "repos/$NEW/labels?per_page=100" -q '.[].name' 2> /dev/null | grep -qx "ai:plan"; then labels=yes; break; fi
  sleep "$WAIT"
done
[ "$labels" = yes ] || note "⚠️ Bootstrap のラベルがまだできていません（Actions の Bootstrap を見る）。Issue は先に作ります"
first=$(gh api "repos/$NEW/issues" -f title="$MEMO" -f "labels[]=size:L" \
  -f body="工場（${TEMPLATE}#${ISSUE}）で作ったサービスの、最初のメモです。企画AIが清書して、そのまま実装まで進めます。最初の画面を一から作る大きい作業なので size:L（強いモデル）にしています。見た目は docs/design.md のとおりに作ってください。" -q .number 2>&1) \
  || fail "最初のIssueを作れませんでした"
note "✅ 最初のIssue：https://github.com/$NEW/issues/$first（自動で企画に回る）"
# 公開アドレス：Vercel が最初の公開でアドレスを決めるまで待って調べる（同じ名前がほかの人に使われていると、名前の後ろに文字が付く）
if [ -n "$vercel_note" ]; then
  if site=$(PROJECT="${vercel_note#Vercel：}" REPO_FULL="$NEW" "$HERE/factory-vercel-url.sh"); then
    note "🌐 公開アドレス：$site（リポジトリの Website 欄にも入れた。最初の画面は、最初のIssueがマージされると出る）"
  else
    note "⚠️ 公開アドレスがまだ決まっていません（Vercel の画面の Domains で確かめる）"
  fi
fi

# ---- 7. 結果 ----
say_result "🏭 新しいサービス **${name}** を作りました。ここから先は、いつものパイプラインが進めます。"
GH_TOKEN="${COMMENT_TOKEN:-$GH_TOKEN}" gh api -X PATCH "repos/$TEMPLATE/issues/$ISSUE" -f state=closed > /dev/null 2>&1 || true
echo "NEW_REPO=$NEW" >> "${GITHUB_OUTPUT:-/dev/null}"
