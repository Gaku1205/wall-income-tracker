#!/usr/bin/env bash
# ワークフローの安全の確認：秘密（PIPELINE_TOKEN・AIのトークン）を使うワークフローが、
# PRの中身で書き換えられる版（pull_request）で動かないこと。
#   pull_request は、PRのブランチにある版のワークフローが動く。PRが書き換えたワークフローで秘密を使われる恐れがある。
#   pull_request_target は、main にある版が動くので安全。
source "$(dirname "$0")/lib.sh"
WORKFLOWS="$(cd "$SCRIPTS_DIR/../workflows" && pwd)"

# pull_request で動かしてよい物（理由つき）。増やすときは、秘密がPRの変更で使われないかを確かめてから
#   visual-update.yml：同じリポジトリのPR（フォークではない）だけを、if で絞っている
#   claude-review.yml：同じリポジトリのPRだけが秘密を受け取る（フォークのPRには GitHub が秘密を渡さない）。レビューは読むだけで、トークンでは書き換えない
ALLOWED_PULL_REQUEST="visual-update.yml claude-review.yml"

echo "== 秘密を使うワークフローは、pull_request で動かない（許可の一覧にある物だけ例外）"
for f in "$WORKFLOWS"/*.yml; do
  name=$(basename "$f")
  uses_secret=$(grep -cE 'secrets\.(PIPELINE_TOKEN|CLAUDE_CODE_OAUTH_TOKEN)' "$f" || true)
  [ "$uses_secret" -eq 0 ] && continue
  triggers=$(python3 -c "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True, d.get('on', {}))
print(' '.join(on if isinstance(on, (list, dict)) else [on]))" "$f")
  if printf ' %s ' "$triggers" | grep -q ' pull_request '; then
    case " $ALLOWED_PULL_REQUEST " in
      *" $name "*) assert_eq "$name：pull_request（許可の一覧にある）" "ok" "ok" ;;
      *) assert_eq "$name：秘密を使うのに pull_request で動く（pull_request_target にするか、許可の一覧に理由つきで足す）" "pull_request_target" "pull_request" ;;
    esac
  else
    assert_eq "$name：pull_request で動かない" "ok" "ok"
  fi
done

echo "== 再開・順番待ちは pull_request_target"
for name in queue.yml resume.yml; do
  assert_contains "$name：pull_request_target を使う" "$(cat "$WORKFLOWS/$name")" "pull_request_target:"
done

echo "== visual-update.yml：PRのコードを動かすジョブには Secret を渡さない"
result=$(python3 - "$WORKFLOWS/visual-update.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
bad = []
for name, job in d['jobs'].items():
    text = yaml.dump(job)
    runs_code = any(w in text for w in ('npm ci', 'npm run', 'npx '))
    uses_secret = 'secrets.' in text
    if runs_code and uses_secret:
        bad.append(name)
print(','.join(bad) or 'ok')
PY
)
assert_eq "npm を動かすジョブが Secret を使わない" "ok" "$result"
assert_contains "撮り直しはトークンを残さない" "$(cat "$WORKFLOWS/visual-update.yml")" "persist-credentials: false"

echo "== doctor.yml：診断の失敗（❌）が、tee で隠れず、実行の失敗になる"
assert_contains "pipefail を使う" "$(cat "$WORKFLOWS/doctor.yml")" "set -o pipefail"

echo "== AIが動くジョブには PIPELINE_TOKEN を渡さない（AIの後の処理は、main の版を別のジョブで動かす）"
result=$(python3 - "$WORKFLOWS" <<'PY'
import sys, os, yaml
bad = []
for f in sorted(os.listdir(sys.argv[1])):
    if not f.endswith('.yml'): continue
    d = yaml.safe_load(open(os.path.join(sys.argv[1], f)))
    for name, job in (d.get('jobs') or {}).items():
        text = yaml.dump(job)
        if 'claude-code-action' in text and 'secrets.PIPELINE_TOKEN' in text:
            bad.append(f + ':' + name)
print(','.join(bad) or 'ok')
PY
)
assert_eq "AIのジョブに PIPELINE_TOKEN が無い" "ok" "$result"
for name in claude-plan.yml claude-implement.yml; do
  assert_contains "$name：AIのジョブが飛ばされたら後の処理も動かない" "$(cat "$WORKFLOWS/$name")" ".result != 'skipped'"
  assert_contains "$name：後の処理は main を取り直して動かす" "$(cat "$WORKFLOWS/$name")" "ref: \${{ github.event.repository.default_branch }}"
done

echo "== sync.yml：CIが通った版だけを配る"
sync="$(cat "$WORKFLOWS/sync.yml")"
assert_contains "CIの完了で動く" "$sync" "workflows: [CI]"
assert_contains "成功のときだけ" "$sync" "conclusion == 'success'"
assert_not_contains "push では動かない" "$sync" "  push:"

echo "== claude-review.yml：大きい・危ない変更は強いモデルでレビューする"
review="$(cat "$WORKFLOWS/claude-review.yml")"
assert_contains "モデルを決める段がある" "$review" "steps.weight.outputs.model"
assert_not_contains "sonnet 固定ではない" "$review" "--model sonnet --max-turns"

echo "== パイプラインの鍵を使うジョブは、GitHub App の鍵を先に作る（無ければ PIPELINE_TOKEN）"
result=$(python3 - "$WORKFLOWS" <<'PY'
import sys, os, yaml
bad = []
for f in sorted(os.listdir(sys.argv[1])):
    if not f.endswith('.yml'): continue
    d = yaml.safe_load(open(os.path.join(sys.argv[1], f)))
    for name, job in (d.get('jobs') or {}).items():
        # 工場（factory.yml）は PIPELINE_TOKEN を新しいリポジトリへ写すだけで、使わない（S_ で始まる名前で渡す）
        text = yaml.dump(job).replace('S_PIPELINE_TOKEN: ${{ secrets.PIPELINE_TOKEN }}', '')
        if 'secrets.PIPELINE_TOKEN' in text and 'create-github-app-token' not in text:
            bad.append(f + ':' + name)
        for st in job.get('steps') or []:
            if 'create-github-app-token' in str(st.get('uses', '')) and not st.get('continue-on-error'):
                bad.append(f + ':' + name + '(鍵が作れないと止まる)')
print(','.join(bad) or 'ok')
PY
)
assert_eq "鍵を使うジョブに App の鍵の段がある" "ok" "$result"

echo "== AIのアクションは、パイプラインの App が起こした実行を断らない（AI自身は除く）"
for name in claude-plan.yml claude-implement.yml claude-review.yml claude-mention.yml; do
  wf="$(cat "$WORKFLOWS/$name")"
  assert_contains "$name：allowed_bots を渡す" "$wf" "allowed_bots: \${{ steps.bots.outputs.list }}"
  assert_contains "$name：claude[bot] は許可しない" "$wf" '"$SENDER" != "claude[bot]"'
done

echo "== @claude を呼べるのは、オーナー・メンバー・共同作業者とパイプラインのボットだけ"
wf="$(cat "$WORKFLOWS/claude-mention.yml")"
assert_contains "claude-mention.yml：コメントした人の立場を見る" "$wf" "github.event.comment.author_association"
assert_contains "claude-mention.yml：OWNER・MEMBER・COLLABORATOR だけ" "$wf" "fromJSON('[\"OWNER\",\"MEMBER\",\"COLLABORATOR\"]')"
assert_contains "claude-mention.yml：ボットは claude[bot] 以外" "$wf" "github.event.comment.user.login != 'claude[bot]'"

echo "== 清書AIの質問には、ダッシュボードが拾う印を付けさせる"
wf="$(cat "$WORKFLOWS/claude-plan.yml")"
assert_contains "claude-plan.yml：質問の1行目は <!-- human-request -->" "$wf" "<!-- human-request -->"

echo "== 配り先は sync-targets.sh で決める（テンプレートから作ったリポジトリは自動）"
wf="$(cat "$WORKFLOWS/sync.yml")"
assert_contains "sync.yml：sync-targets.sh を使う" "$wf" "list=\$(.github/scripts/sync-targets.sh .github/sync-targets)"
assert_not_contains "sync.yml：配り先の失敗をプロセス置換で隠さない" "$wf" "< <(.github/scripts/sync-targets.sh"

echo "== 実装AI・修正AIは、push の前に main を取り込む（作業中に配布でワークフローが変わっても push が拒否されない）"
for name in claude-implement.yml claude-mention.yml; do
  wf="$(cat "$WORKFLOWS/$name")"
  assert_contains "$name：履歴を全部取る" "$wf" "fetch-depth: 0"
  assert_contains "$name：git fetch を許す" "$wf" "Bash(git fetch:*)"
  assert_contains "$name：git merge を許す" "$wf" "Bash(git merge:*)"
  assert_contains "$name：push の前に main を取り込む指示" "$wf" "git merge origin/main で最新の main を取り込んでから"
done

echo "== 修正AIは、見た目のテストの差分の画像を見てから決める"
wf="$(cat "$WORKFLOWS/claude-mention.yml")"
assert_contains "claude-mention.yml：差分の画像を取ってくる" "$wf" ".github/scripts/fetch-visual-diff.sh"
assert_contains "claude-mention.yml：画像を見る指示" "$wf" "Read で開いて見る"
assert_contains "claude-mention.yml：artifact を読む権限" "$wf" "actions: read"

echo "== 見張り役は、何もしなかった実行（skipped）の後には動かない"
wf="$(cat "$WORKFLOWS/watchdog.yml")"
assert_contains "watchdog.yml：skipped の後は動かない" "$wf" "github.event.workflow_run.conclusion != 'skipped'"

echo "== 配る（sync.yml）は、待ってから。新しい方が来たら古い待ちは止まり、配る本体は途中で止めない"
result=$(python3 - "$WORKFLOWS/sync.yml" <<'PY2'
import sys, yaml
j = yaml.safe_load(open(sys.argv[1]))['jobs']
w, s = j['wait'], j['sync']
print('wait-cancel' if w['concurrency']['cancel-in-progress'] is True else 'wait-no-cancel')
print('sync-needs-wait' if s.get('needs') == 'wait' else 'sync-no-needs')
print('sync-no-cancel' if s['concurrency']['cancel-in-progress'] is False else 'sync-cancel')
print('template-only' if 'is_template' in str(w.get('if', '')) else 'any-repo')
PY2
)
assert_eq "sync.yml の待ちと配る本体" "$(printf 'wait-cancel\nsync-needs-wait\nsync-no-cancel\ntemplate-only')" "$result"

echo "== やり直しの目覚まし：見張り役は目覚ましを動かせる（actions: write）。目覚ましは1つだけ"
assert_contains "watchdog.yml：actions: write" "$(cat "$WORKFLOWS/watchdog.yml")" "actions: write"
assert_contains "retry-timer.yml：新しい物が古い物を止める" "$(cat "$WORKFLOWS/retry-timer.yml")" "cancel-in-progress: true"
assert_contains "retry-timer.yml：見張り役が探す名前" "$(cat "$WORKFLOWS/retry-timer.yml")" "run-name: やり直しの目覚まし \${{ inputs.at }}"

echo "== 見た目の撮り直しは、通っている画像も含めて全部撮り直す（古い基準の画像を残さない）"
assert_contains "visual-update.yml：--update-snapshots=all" "$(cat "$WORKFLOWS/visual-update.yml")" "--update-snapshots=all"

echo "== 工場：強い鍵は Environment「factory」のジョブだけ。AIのジョブには渡さない。オーナーのIssueでだけ動く"
result=$(python3 - "$WORKFLOWS/factory.yml" <<'PY2'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])); j = d["jobs"]
out = []
out.append("build-env" if j["build"].get("environment") == "factory" else "build-no-env")
out.append("plan-no-factory" if "FACTORY_TOKEN" not in yaml.dump(j["plan"]) + yaml.dump(j["design"]) else "plan-has-factory")
out.append("owner-only" if "github.event.issue.user.login == github.repository_owner" in j["plan"]["if"] else "anyone")
out.append("template-only" if "is_template" in j["plan"]["if"] else "any-repo")
print(",".join(out))
PY2
)
assert_eq "factory.yml の守り" "build-env,plan-no-factory,owner-only,template-only" "$result"

echo "== デザイン部門：AIが動かせるコマンドは taste-skill の draw.mjs だけ。動かす前にスキルと手順書を読み取り専用にする"
result=$(python3 - "$WORKFLOWS/factory.yml" <<'PY2'
import sys, re, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["design"]["steps"]
out = []
bash = set()
for st in steps:
    args = (st.get("with") or {}).get("claude_args", "")
    bash |= set(re.findall(r"Bash\(([^)]*)\)", args))
out.append("bash=" + "|".join(sorted(bash)))
names = [st.get("id") or st.get("name") or st.get("uses", "") for st in steps]
ro = names.index("スキルと手順書を読み取り専用にする")
out.append("ro-first" if ro < names.index("designer") else "ro-late")
out.append("chmod" if "chmod -R a-w .claude/skills .github" in steps[ro]["run"] else "no-chmod")
print(",".join(out))
PY2
)
assert_eq "factory.yml のデザイン部門" "bash=node .claude/skills/taste-skill/scripts/draw.mjs:*,ro-first,chmod" "$result"

echo "== 「新サービス：」のIssue：テンプレート自身の企画・実装には回さない（工場が受け持つ）"
result=$(python3 - "$WORKFLOWS" <<'PY2'
import sys, yaml
w = sys.argv[1]
out = []
for f, job in (("claude-plan.yml", "plan"), ("claude-implement.yml", "implement")):
    cond = yaml.safe_load(open(f"{w}/{f}"))["jobs"][job]["if"]
    out.append(f"{job}:" + ("guarded" if "is_template" in cond and "新サービス：" in cond and "新サービス:" in cond else "open"))
fj = yaml.safe_load(open(f"{w}/claude-plan.yml"))["jobs"].get("factory-issue")
out.append("factory-issue:" + ("yes" if fj and "is_template" in fj["if"] else "no"))
print(",".join(out))
PY2
)
assert_eq "企画・実装は受けず、ラベルを外す" "plan:guarded,implement:guarded,factory-issue:yes" "$result"

echo "== 見た目のテスト：AIは動かせるが基準の画像は撮り直せない。撮り直しが失敗したらAIに直させる"
result=$(python3 - "$WORKFLOWS" <<'PY2'
import sys, yaml
w = sys.argv[1]; out = []
for f, job in (("claude-implement.yml", "implement"), ("claude-mention.yml", "mention")):
    d = yaml.safe_load(open(f"{w}/{f}"))["jobs"]
    j = d[job] if job in d else list(d.values())[0]
    args = [st for st in j["steps"] if "claude-code-action" in st.get("uses", "")][0]["with"]["claude_args"]
    names = [st.get("name", "") for st in j["steps"]]
    vis = [st for st in j["steps"] if st.get("id") == "visual"]
    ok = ("${{ steps.visual.outputs.allowed }}" in args and vis and "Bash(npm run test:visual)" in vis[0]["run"]
          and "--update-snapshots:*" in args.split("--disallowedTools")[1] and "見た目のテスト用のブラウザを入れる" in names)
    out.append(f"{f.split('.')[0]}:" + ("ok" if ok else "ng"))
steps = yaml.safe_load(open(f"{w}/visual-update.yml"))["jobs"]["unlabel"]["steps"]
h = [st for st in steps if st.get("name") == "撮り直しが失敗したら、AIに直させる"]
out.append("handoff:" + ("ok" if h and "needs.shoot.result == 'failure'" in h[0]["if"] and "request_fix_or_stop" in h[0]["run"] else "ng"))
print(",".join(out))
PY2
)
assert_eq "見た目のテストの扱い" "claude-implement:ok,claude-mention:ok,handoff:ok" "$result"

finish
