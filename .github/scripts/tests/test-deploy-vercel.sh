#!/usr/bin/env bash
# Vercel の本番の公開をまとめて1回だけ頼む（deploy-vercel.sh）
# GitHub と Vercel は、このテストの中の疑似 gh・疑似 curl で真似る
source "$(dirname "$0")/lib.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'PY'
#!/usr/bin/env python3
import sys, os, json, subprocess, re
st = json.load(open(os.environ["FT"] + "/state.json"))
a = sys.argv[1:]; assert a[0] == "api"
q = a[a.index("-q") + 1] if "-q" in a else None
path = [x for x in a[1:] if x.startswith("repos/")][0]
base = re.sub(r"^repos/o/r", "", path.split("?")[0])
def out(o):
    sys.stdout.write(subprocess.run(["jq", "-r", q], input=json.dumps(o), capture_output=True, text=True).stdout if q else json.dumps(o))
commits = st["commits"]  # 新しい順 [{sha, state}]
if base == "/commits/main": out({"sha": commits[0]["sha"]})
elif base == "/commits": out([{"sha": c["sha"]} for c in commits])
elif m := re.match(r"/commits/(\w+)/status$", base):
    c = [c for c in commits if c["sha"] == m.group(1)][0]
    out({"statuses": [{"context": "Vercel", "state": c["state"], "updated_at": "2026-01-01T00:00:00Z"}] if c.get("state") else []})
elif m := re.match(r"/compare/(\w+)\.\.\.(\w+)$", base): out({"files": [{"filename": f} for f in st["changed"]]})
elif base == "": out({"id": 4242})
else: sys.stderr.write("UNHANDLED " + path + "\n"); sys.exit(1)
PY
cat > "$T/bin/curl" <<'SH'
#!/usr/bin/env bash
echo "curl $*" >> "$FT/calls.log"
case "$*" in
  *v10/projects*) if [ -n "${NO_PROJECT:-}" ]; then echo '{"projects":[]}'; else echo '{"projects":[{"name":"agent-desk-ip1u"}]}'; fi ;;
  *v13/deployments*) cat > "$FT/deploy-body.json"; echo '{"url":"agent-desk-abc.vercel.app"}' ;;
esac
SH
chmod +x "$T/bin/gh" "$T/bin/curl"
run() { # 状態のJSON [追加の環境変数...]
  printf '%s' "$1" > "$T/state.json"; rm -f "$T/calls.log" "$T/deploy-body.json"
  env PATH="$T/bin:$PATH" FT="$T" GITHUB_REPOSITORY=o/r GH_TOKEN=x VERCEL_TOKEN=v "${@:2}" bash "$SCRIPTS_DIR/deploy-vercel.sh" 2>&1
}
deployed() { [ -f "$T/deploy-body.json" ] && echo yes || echo no; }

echo "== アプリの変更が公開されていない：最新の main を本番に1回だけ公開する"
out=$(run '{"commits":[{"sha":"c3"},{"sha":"c2"},{"sha":"c1","state":"success"}],"changed":["src/app/page.tsx",".github/x.yml"]}')
assert_eq "公開を頼む" "yes" "$(deployed)"
assert_contains "最新の main の sha" "$(cat "$T/deploy-body.json")" '"sha":"c3"'
assert_contains "本番" "$(cat "$T/deploy-body.json")" '"target":"production"'
assert_contains "つながったプロジェクトの名前" "$(cat "$T/deploy-body.json")" '"name":"agent-desk-ip1u"'
assert_contains "GitHub のリポジトリ番号" "$(cat "$T/deploy-body.json")" '"repoId":"4242"'
assert_contains "知らせる" "$out" "公開を頼みました"

echo "== 何もしなくてよいとき"
run '{"commits":[{"sha":"c3","state":"success"},{"sha":"c2"}],"changed":["src/a.ts"]}' > /dev/null
assert_eq "最新がもう公開済み" "no" "$(deployed)"
run '{"commits":[{"sha":"c3","state":"pending"},{"sha":"c2","state":"success"}],"changed":["src/a.ts"]}' > /dev/null
assert_eq "最新がいま公開中" "no" "$(deployed)"
run '{"commits":[{"sha":"c3"},{"sha":"c2","state":"success"}],"changed":[".github/scripts/x.sh","docs/pipeline.md"]}' > /dev/null
assert_eq "パイプラインの更新しか変わっていない" "no" "$(deployed)"
out=$(run '{"commits":[{"sha":"c3"}],"changed":[]}' VERCEL_TOKEN=)
assert_eq "VERCEL_TOKEN が無い" "no" "$(deployed)"
assert_contains "そう書く" "$out" "VERCEL_TOKEN が無い"

echo "== 前の公開が失敗している（回数の上限など）：最新を公開し直す"
run '{"commits":[{"sha":"c3","state":"failure"},{"sha":"c2","state":"success"}],"changed":["src/a.ts"]}' > /dev/null
assert_eq "公開し直す" "yes" "$(deployed)"

echo "== プロジェクトが見つからない：失敗として終わる"
run '{"commits":[{"sha":"c3"},{"sha":"c2","state":"success"}],"changed":["src/a.ts"]}' NO_PROJECT=1 > /dev/null; code=$?
assert_eq "失敗で終わる" "1" "$code"
assert_eq "公開は頼まない" "no" "$(deployed)"

echo "== チームのとき：teamId を付ける"
run '{"commits":[{"sha":"c3"},{"sha":"c2","state":"success"}],"changed":["src/a.ts"]}' VERCEL_TEAM_ID=team_1 > /dev/null
assert_contains "deployments に teamId" "$(cat "$T/calls.log")" "v13/deployments?teamId=team_1"

finish
