#!/usr/bin/env bash
# 工場（factory.sh）：1行のメモから、新しいサービスのリポジトリを作ってパイプラインに渡す。
# GitHub と Vercel は、このテストの中の疑似 gh・疑似 curl で真似る（呼ばれた物を calls.log に残す）。clone 先は手元の git
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$SCRIPTS_DIR/../.." && pwd)"
# 工場はテンプレート本体の物。見本（examples/python）の無いリポジトリ（工場で作ったアプリなど）では確かめない
if [ ! -d "$ROOT/examples/python" ]; then echo "見本が無いので、工場のテストは飛ばします"; finish; exit $?; fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/remotes"

# テンプレートの中身（いまの作業中の物）を、作るリポジトリの元にする
mkdir -p "$T/seed"
(cd "$ROOT" && git ls-files -co --exclude-standard | grep -v '^node_modules/' | tar -cf - -T -) | tar -xf - -C "$T/seed"
git -C "$T/seed" init -q -b main && git -C "$T/seed" add -A && git -C "$T/seed" -c user.name=t -c user.email=t@t commit -qm seed

cat > "$T/bin/gh" <<'PY'
#!/usr/bin/env python3
import sys, os, json, subprocess, shutil, re
T = os.environ["FT"]; log = open(f"{T}/calls.log", "a")
st_path = f"{T}/state.json"
st = json.load(open(st_path)) if os.path.exists(st_path) else {"repos": [], "issues": 0}
a = sys.argv[1:]
def save(): json.dump(st, open(st_path, "w"))
def arg(flag):
    return a[a.index(flag) + 1] if flag in a else None
def fields():
    out = {}
    for i, x in enumerate(a):
        if x in ("-f", "-F"): k, v = a[i + 1].split("=", 1); out[k] = v
    return out
if a[0] in ("secret", "variable"):
    val = sys.stdin.read() if a[0] == "secret" else arg("--body")
    log.write(f"{a[0]} {a[2]} {arg('--repo')} len={len(val)}\n"); sys.exit(0)
assert a[0] == "api"
method = arg("-X") or ("POST" if ("-f" in a or "-F" in a) else "GET")
path = [x for x in a[1:] if x.startswith("repos/")][0]
q = arg("-q")
def out(o):
    if q: sys.stdout.write(subprocess.run(["jq", "-r", q], input=json.dumps(o), capture_output=True, text=True).stdout)
    else: print(json.dumps(o))
base = path.split("?")[0]
log.write(f"{method} {base} {json.dumps(fields(), ensure_ascii=False)}\n")
m = re.match(r"repos/([^/]+)/([^/]+)$", base)
if m and method == "PATCH":
    open(f"{T}/homepage.txt", "w").write(fields().get("homepage", "")); print("{}"); sys.exit(0)
if m and method == "GET":
    name = f"{m.group(1)}/{m.group(2)}"
    sys.exit(0 if name in st["repos"] or name in os.environ.get("EXISTING", "").split() else 1)
if base.endswith("/generate"):
    f = fields(); new = f"{f['owner']}/{f['name']}"
    st["repos"].append(new); save()
    dst = f"{T}/remotes/{new}.git"; os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.run(["git", "clone", "-q", "--bare", f"{T}/seed", dst], check=True); print("{}"); sys.exit(0)
m = re.match(r"repos/([^/]+/[^/]+)/branches/main$", base)
if m: sys.exit(0 if m.group(1) in st["repos"] else 1)
if base.endswith("/rulesets"):
    open(f"{T}/ruleset.json", "w").write(sys.stdin.read()); print("{}"); sys.exit(0)
if base.endswith("/labels"):
    out([{"name": "ai:plan"}]); sys.exit(0)
m = re.match(r"repos/([^/]+/[^/]+)/issues$", base)
if m and method == "POST":
    st["issues"] += 1; save(); out({"number": st["issues"]}); sys.exit(0)
if re.search(r"/issues/\d+/comments$", base):
    open(f"{T}/comment.txt", "a").write(fields().get("body", "") + "\n----\n"); print("{}"); sys.exit(0)
if re.search(r"/issues/\d+$", base) and method == "PATCH":
    print("{}"); sys.exit(0)
sys.stderr.write(f"UNHANDLED {method} {path}\n"); sys.exit(1)
PY
cat > "$T/bin/curl" <<'SH'
#!/usr/bin/env bash
echo "curl $*" >> "$FT/calls.log"
case "$*" in
  */domains*) echo '{"domains":[{"name":"made-git-x.vercel.app","gitBranch":"x"},{"name":"made-abc.vercel.app","gitBranch":null}]}'; exit 0 ;;
esac
cat > "$FT/vercel-body.json"
if [ -n "${VERCEL_FAIL:-}" ]; then echo '{"error":{"message":"repo not found"}}'; else echo '{"name":"made"}'; fi
SH
# 疑似 npm：呼ばれた引数を残し、package.json に入れたことにする（NPM_FAIL があれば失敗する）
cat > "$T/bin/npm" <<'SH'
#!/usr/bin/env bash
echo "npm $*" >> "$FT/calls.log"
[ -n "${NPM_FAIL:-}" ] && { echo "npm ERR! network" >&2; echo '{"broken":1}' > package.json; exit 1; }
for a in "$@"; do case "$a" in -*|install) ;; *) echo "// $a" >> package.json ;; esac; done
SH
chmod +x "$T/bin/gh" "$T/bin/curl" "$T/bin/npm"

run_factory() { # 名前 言語 説明 [追加の環境変数...]
  rm -f "$T/calls.log" "$T/state.json" "$T/comment.txt" "$T/ruleset.json" "$T/vercel-body.json"; rm -rf "$T/remotes"; mkdir -p "$T/remotes"
  env PATH="$T/bin:$PATH" FT="$T" GH_TOKEN=x TEMPLATE=o/ai-dev-template ISSUE=7 MEMO="毎朝の天気と予定を1枚で見たい" \
    APP_NAME="$1" APP_STACK="$2" APP_DESC="$3" FACTORY_GIT_URL="$T/remotes/%s.git" FACTORY_WAIT_SEC=0 \
    S_CLAUDE_CODE_OAUTH_TOKEN=secret1 S_PIPELINE_APP_PRIVATE_KEY=pem V_PIPELINE_APP_ID=123 "${@:4}" \
    bash "$SCRIPTS_DIR/factory.sh" 2>&1
}
file_in() { git --git-dir="$T/remotes/$1.git" show "main:$2" 2> /dev/null; }

echo "== Next.js：リポジトリを作り、秘密と変数を写し、Vercel につなぎ、main を守り、最初のIssueを作る"
run_factory morning-board nextjs "毎朝の天気と予定を1枚で見るページ。" VERCEL_TOKEN=v > /dev/null
calls=$(cat "$T/calls.log")
assert_contains "テンプレートから作る" "$calls" "POST repos/o/ai-dev-template/generate"
assert_contains "秘密を写す" "$calls" "secret CLAUDE_CODE_OAUTH_TOKEN o/morning-board len=7"
assert_contains "変数を写す" "$calls" "variable PIPELINE_APP_ID o/morning-board len=3"
assert_not_contains "空の秘密は写さない" "$calls" "secret NTFY_TOPIC"
assert_contains "Vercel のプロジェクト" "$(cat "$T/vercel-body.json")" '"repo":"o/morning-board"'
assert_contains "本番の公開アドレスを報告する（ブランチの物ではない方）" "$(cat "$T/comment.txt")" "公開アドレス：https://made-abc.vercel.app"
assert_eq "Website 欄に入れる" "https://made-abc.vercel.app" "$(cat "$T/homepage.txt")"
assert_contains "main を守る：check が必須" "$(cat "$T/ruleset.json")" '"context":"check"'
assert_contains "main を守る：PR が必須" "$(cat "$T/ruleset.json")" '"pull_request"'
assert_contains "最初のIssueはメモの1行" "$calls" '"title": "毎朝の天気と予定を1枚で見たい"'
claude=$(file_in o/morning-board CLAUDE.md)
assert_eq "CLAUDE.md の説明（句点は1つ・言語の案内は消す）" "morning-board：毎朝の天気と予定を1枚で見るページ。Next.js（App Router）＋TypeScript。" "$(printf '%s\n' "$claude" | sed -n 3p)"
assert_not_contains "テンプレート本体だけの節を消す（自動マージの印も）" "$claude" "pipeline-self-edit"
assert_not_contains "その但し書きも消す" "$claude" "ai-dev-template 自身"
assert_contains "仕様書の目的に説明とメモ" "$(file_in o/morning-board docs/spec.md)" "（元のメモ：毎朝の天気と予定を1枚で見たい）"
assert_contains "README はこのサービスの説明" "$(file_in o/morning-board README.md | head -3)" "毎朝の天気と予定を1枚で見るページ"
assert_eq "工場のIssueの雛形は持ち込まない" "" "$(file_in o/morning-board .github/ISSUE_TEMPLATE/new-service.yml)"
assert_eq "見本（examples）は持ち込まない" "" "$(file_in o/morning-board examples/python/README.md)"
assert_contains "Next.js のまま" "$(file_in o/morning-board package.json)" '"next"'
assert_contains "元のIssueに結果を書く" "$(cat "$T/comment.txt")" "新しいサービス **morning-board** を作りました"
assert_contains "元のIssueを閉じる" "$calls" "PATCH repos/o/ai-dev-template/issues/7"

echo "== Vercel が断ったら、理由を書いて先へ進む"
run_factory vercel-ng nextjs "説明" VERCEL_TOKEN=v VERCEL_FAIL=1 > /dev/null
assert_contains "理由を書く" "$(cat "$T/comment.txt")" "repo not found"
assert_contains "最初のIssueまでは作る" "$(cat "$T/calls.log")" "POST repos/o/vercel-ng/issues"

echo "== 同じ名前があれば -2 を付ける。VERCEL_TOKEN が無ければ、つながずに知らせる"
run_factory morning-board nextjs "説明" EXISTING="o/morning-board" > /dev/null
assert_contains "-2 で作る" "$(cat "$T/calls.log")" '"name": "morning-board-2"'
assert_contains "Vercel につないでいないと書く" "$(cat "$T/comment.txt")" "VERCEL_TOKEN が無い"

echo "== Python：見本に切り替える（Next.js の物を消し、公開先は none、CLAUDE.md と仕様書も Python に）"
run_factory receipt-api python "レシートの写真から金額を取り出すAPI" > /dev/null
r=o/receipt-api
assert_eq "package.json は消える" "" "$(file_in $r package.json)"
assert_contains "app/ が来る" "$(file_in $r app/main.py)" "FastAPI"
assert_contains ".dockerignore も来る" "$(file_in $r .dockerignore)" ".venv"
assert_eq "公開先は none" '[{"kind":"none"}]' "$(file_in $r pipeline.json | jq -c .deploy)"
assert_contains "cli.py はテストが使うので残す" "$(file_in $r cli.py)" "def main"
assert_not_contains "pyinstaller は入れない" "$(file_in $r requirements-dev.txt)" "pyinstaller"
assert_eq "AGENTS.md は空で残る" "0" "$(file_in $r AGENTS.md | wc -c | tr -d ' ')"
claude=$(file_in $r CLAUDE.md)
assert_contains "CLAUDE.md：Python（FastAPI）" "$claude" "receipt-api：レシートの写真から金額を取り出すAPI。Python（FastAPI）。"
assert_not_contains "CLAUDE.md：テンプレート本体だけの節を消す" "$claude" "pipeline-self-edit"
assert_not_contains "CLAUDE.md：Next.js の注意の行は消す" "$claude" "Next.js固有の注意"
assert_contains "CLAUDE.md：コードの書き方も Python" "$claude" "ロジックは \`app/\`、テストは \`tests/\`"
assert_contains "仕様書の技術の欄" "$(file_in $r docs/spec.md)" "Python（FastAPI）、テストは pytest"
assert_not_contains "Python では Vercel を呼ばない" "$(cat "$T/calls.log")" "curl"

echo "== 説明に記号があっても壊れない（& / | \\ など）"
run_factory odd-chars nextjs 'A&B / C|D \ E' > /dev/null
assert_contains "そのまま書かれる" "$(file_in o/odd-chars CLAUDE.md | sed -n 3p)" 'odd-chars：A&B / C|D \ E。'

echo "== AIが決めた形が違えば、何も作らずに止める"
run_factory "Bad_Name" nextjs "x" > /dev/null
assert_not_contains "作らない" "$(cat "$T/calls.log" 2> /dev/null)" "generate"
assert_contains "理由を書く" "$(cat "$T/comment.txt")" "名前「Bad_Name」"
run_factory good-name ruby "x" > /dev/null
assert_contains "知らない言語" "$(cat "$T/comment.txt")" "nextjs か python"
run_factory good-name nextjs 'x $(id)' > /dev/null
assert_contains "危ない記号" "$(cat "$T/comment.txt")" "記号"

echo "== デザイン部門：形が正しいデザイン仕様は docs/design.md に、使う人・場面は仕様書の前提に入る。最初のIssueは size:L"
{ echo "# デザイン仕様"; for i in $(seq 1 60); do echo "- 色や文字の決まり その$i：夜の地に光る数字"; done; } > "$T/design-ok.md"
printf '%s\n' "# 使う人" "- 推定：シフト制のバイトをしている学生" "- 推定：バイト帰りの電車で、スマホを片手に30秒" "前置きの文は入れない" > "$T/context.md"
run_factory design-ok nextjs "説明" DESIGN_FILE="$T/design-ok.md" CONTEXT_FILE="$T/context.md" > /dev/null
spec=$(file_in o/design-ok docs/spec.md)
assert_contains "仕様書の前提に、使う人・場面" "$spec" "  - 推定：バイト帰りの電車で、スマホを片手に30秒"
assert_not_contains "箇条書き以外は入れない" "$spec" "前置きの文"
assert_contains "docs/design.md に入る" "$(file_in o/design-ok docs/design.md)" "夜の地に光る数字"
assert_contains "結果に書く" "$(cat "$T/comment.txt")" "デザイン仕様（docs/design.md）を書き、別の目で検査した"
assert_contains "最初のIssueは size:L" "$(cat "$T/calls.log")" '"labels[]": "size:L"'
printf '%s\n' "ちがう見出し" "短い" > "$T/design-bad.md"
run_factory design-bad nextjs "説明" DESIGN_FILE="$T/design-bad.md" > /dev/null
assert_not_contains "形が違えば雛形のまま" "$(file_in o/design-bad docs/design.md)" "ちがう見出し"
assert_contains "そう書く" "$(cat "$T/comment.txt")" "雛形のままにした"

echo "== デザイン部門が選んだ GSAP・Lenis：決まった物だけ、デザイン仕様を使うときだけ入れる"
printf '%s\n' "gsap" "lenis" "left-pad" "" > "$T/libs.txt"
run_factory libs-ok nextjs "説明" DESIGN_FILE="$T/design-ok.md" LIBS_FILE="$T/libs.txt" > /dev/null
calls=$(cat "$T/calls.log")
assert_contains "lock だけ更新して入れる（GSAP は React 用も一緒に）" "$calls" "npm install --package-lock-only --no-audit --no-fund --save @gsap/react@^2 gsap@^3 lenis@^1"
assert_not_contains "決まった物以外は入れない" "$calls" "left-pad"
pkg=$(file_in o/libs-ok package.json)
assert_contains "package.json に入って push される" "$pkg" "// lenis@^1"
assert_contains "結果に書く" "$(cat "$T/comment.txt")" "動きの道具を入れた：@gsap/react@^2 gsap@^3 lenis@^1"
assert_contains "入れなかった物も書く" "$(cat "$T/comment.txt")" "決まった物（gsap・@gsap/react・lenis）以外"
run_factory libs-nodesign nextjs "説明" DESIGN_FILE="$T/design-bad.md" LIBS_FILE="$T/libs.txt" > /dev/null
assert_not_contains "デザイン仕様が雛形のままなら入れない" "$(cat "$T/calls.log")" "npm install"
run_factory libs-py python "説明" LIBS_FILE="$T/libs.txt" > /dev/null
assert_not_contains "Python では入れない" "$(cat "$T/calls.log")" "npm install"
: > "$T/libs-empty.txt"
run_factory libs-empty nextjs "説明" DESIGN_FILE="$T/design-ok.md" LIBS_FILE="$T/libs-empty.txt" > /dev/null
assert_not_contains "空なら入れない（検査役が消した）" "$(cat "$T/calls.log")" "npm install"
run_factory libs-fail nextjs "説明" DESIGN_FILE="$T/design-ok.md" LIBS_FILE="$T/libs.txt" NPM_FAIL=1 > /dev/null
assert_not_contains "失敗したら package.json を元に戻す" "$(file_in o/libs-fail package.json)" "broken"
assert_contains "失敗しても止めずに書く" "$(cat "$T/comment.txt")" "入れられませんでした"
assert_contains "失敗してもサービスは作る" "$(cat "$T/comment.txt")" "新しいサービス **libs-fail** を作りました"

finish
