#!/usr/bin/env bash
# 公開（deploy-plan / deploy-status / deploy-apprunner / deploy-release）：偽の gh・aws・docker で確かめる
source "$(dirname "$0")/lib.sh"
setup_mock
work="$(mktemp -d)"
cd "$work" || exit 1
LOG="$MOCK_DIR/calls.log"
: > "$LOG"
export LOG

# 偽の gh：呼ばれた内容を記録する。コミットの説明だけ返す
cat > "$MOCK_DIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"
case "$*" in
  *"commits/"*"-q .commit.message"*) printf 'Merge pull request #9\n\nあいさつを足す\n' ;;
  "release create"*) [ -n "${RELEASE_FAIL:-}" ] && exit 1 ;;
esac
exit 0
GH
# 偽の aws：サービスの有無（APPRUNNER_EXISTS）と操作の結果（OP_STATUS）を切り替える
cat > "$MOCK_DIR/bin/aws" <<'AWS'
#!/usr/bin/env bash
echo "aws $*" >> "$LOG"
case "$1 $2" in
  "sts get-caller-identity") echo 123456789012 ;;
  "configure get") echo ap-northeast-1 ;;
  "ecr describe-repositories") [ -n "${ECR_EXISTS:-}" ] || exit 254 ;;
  "ecr create-repository") echo '{}' ;;
  "ecr get-login-password") echo pw ;;
  "apprunner list-services") [ -n "${APPRUNNER_EXISTS:-}" ] && echo "arn:svc" || echo None ;;
  "apprunner create-service") echo '{"Service":{"ServiceArn":"arn:new"},"OperationId":"op-create"}' ;;
  "apprunner update-service") echo op-update ;;
  "apprunner list-operations") echo "${OP_STATUS:-SUCCEEDED}" ;;
  "apprunner describe-service") echo abc.ap-northeast-1.awsapprunner.com ;;
esac
AWS
# 偽の docker：本物と同じく、login はパスワードを標準入力から読む（読まないとパイプが切れる）
printf '#!/usr/bin/env bash\necho "docker $*" >> "$LOG"\n[ "$1" = login ] && cat > /dev/null\nexit 0\n' > "$MOCK_DIR/bin/docker"
chmod +x "$MOCK_DIR/bin/gh" "$MOCK_DIR/bin/aws" "$MOCK_DIR/bin/docker"
export SHA=0123456789abcdef GITHUB_REPOSITORY=o/app APPRUNNER_WAIT_SEC=0 APPRUNNER_WAIT_MAX=3
plan() { CHANGED_FILES="$1" GITHUB_OUTPUT="$work/out" bash "$SCRIPTS_DIR/deploy-plan.sh" > /dev/null 2>&1; cat "$work/out"; rm -f "$work/out"; }

echo "== 計画：pipeline.json が無ければ Vercel（ここでは何も動かさない）"
out=$(plan "src/a.ts")
assert_contains "App Runner は動かさない" "$out" "apprunner=false"
assert_contains "Releases も動かさない" "$out" "release=false"

echo "== 計画：App Runner と exe"
echo '{"checks":[{"run":"pytest"}],"deploy":[{"kind":"aws-apprunner","service":"hello-api","port":8000},{"kind":"github-release","os":["windows-latest","macos-latest"],"build":"make","files":"dist/*"}]}' > pipeline.json
out=$(plan "app/main.py")
assert_contains "App Runner を動かす" "$out" "apprunner=true"
assert_contains "Releases を動かす" "$out" "release=true"
assert_contains "OS の一覧" "$out" 'release_os=["windows-latest","macos-latest"]'
assert_contains "App Runner の設定" "$out" '"service":"hello-api"'
assert_contains "Expo は動かさない" "$out" "expo=false"

echo "== 計画：パイプラインの更新だけのコミットは公開しない"
out=$(plan "$(printf '.github/workflows/ci.yml\ndocs/pipeline.md')")
assert_contains "App Runner は動かさない" "$out" "apprunner=false"
assert_contains "理由" "$out" "skip_reason=パイプラインの更新だけ"
out=$(plan "$(printf '.github/workflows/ci.yml\napp/main.py')")
assert_contains "アプリも変わっていれば公開する" "$out" "apprunner=true"

echo "== 計画：pipeline.json が壊れていれば失敗"
echo '{"deploy":[{"kind":"heroku"}],"checks":[{"run":"x"}]}' > pipeline.json
CHANGED_FILES=x GITHUB_OUTPUT=/dev/null bash "$SCRIPTS_DIR/deploy-plan.sh" > "$work/err" 2>&1; rc=$?
assert_eq "終了コード 1" "1" "$rc"
assert_contains "理由" "$(cat "$work/err")" "heroku"

echo "== 状態：deploy/<種類> で書き、終わったら通知"
: > "$LOG"; : > "$MOCK_DIR/curl.log"
bash "$SCRIPTS_DIR/deploy-status.sh" aws-apprunner pending "公開中" > /dev/null 2>&1
assert_contains "状態を書く" "$(cat "$LOG")" "repos/o/app/statuses/0123456789abcdef -f state=pending -f context=deploy/aws-apprunner"
assert_eq "公開中は通知しない" "0" "$(notify_count)"
bash "$SCRIPTS_DIR/deploy-status.sh" aws-apprunner success "公開しました" "https://x.example" > /dev/null 2>&1
assert_contains "URL を付ける" "$(cat "$LOG")" "target_url=https://x.example"
assert_contains "成功の通知" "$(cat "$MOCK_DIR/curl.log")" "公開されました（aws-apprunner）"
assert_contains "通知にPRのタイトル" "$(cat "$MOCK_DIR/curl.log")" "あいさつを足す"
bash "$SCRIPTS_DIR/deploy-status.sh" github-release failure "$(printf 'x%.0s' $(seq 1 200))" > /dev/null 2>&1
assert_contains "失敗の通知" "$(cat "$MOCK_DIR/curl.log")" "公開に失敗しました（github-release）"
desc=$(grep "context=deploy/github-release" "$LOG" | tail -1 | sed -E 's/.*description=([x]*).*/\1/')
assert_eq "説明は140文字まで" "140" "${#desc}"

echo "== App Runner：最初の公開はサービスを作る"
echo 'FROM scratch' > Dockerfile
export CONFIG='{"kind":"aws-apprunner","service":"hello-api","port":8000,"health":"/health"}' ACCESS_ROLE_ARN=arn:access
: > "$LOG"
out=$(GITHUB_OUTPUT="$work/o" bash "$SCRIPTS_DIR/deploy-apprunner.sh" 2>&1); rc=$?
assert_eq "終了コード 0" "0" "$rc"
assert_contains "ECR が無ければ作る" "$(cat "$LOG")" "aws ecr create-repository --repository-name hello-api"
assert_contains "イメージの名前にコミット" "$(cat "$LOG")" "docker push 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/hello-api:0123456789abcdef"
assert_contains "サービスを作る" "$(cat "$LOG")" "aws apprunner create-service --service-name hello-api"
assert_contains "ポート" "$(cat "$LOG")" '"Port":"8000"'
assert_contains "ヘルスチェック" "$(cat "$LOG")" '"Path":"/health"'
assert_contains "自動の公開は切る（このワークフローが出す）" "$(cat "$LOG")" '"AutoDeploymentsEnabled":false'
assert_contains "URL を出す" "$(cat "$work/o")" "url=https://abc.ap-northeast-1.awsapprunner.com"

echo "== App Runner：2回目からは差し替える"
: > "$LOG"
ECR_EXISTS=1 APPRUNNER_EXISTS=1 GITHUB_OUTPUT=/dev/null bash "$SCRIPTS_DIR/deploy-apprunner.sh" > /dev/null 2>&1; rc=$?
assert_eq "終了コード 0" "0" "$rc"
assert_contains "差し替える" "$(cat "$LOG")" "aws apprunner update-service --service-arn arn:svc"
assert_not_contains "作り直さない" "$(cat "$LOG")" "create-service"
assert_not_contains "ECR も作らない" "$(cat "$LOG")" "create-repository"

echo "== App Runner：失敗・時間切れ・設定の不足は失敗にする"
out=$(ECR_EXISTS=1 APPRUNNER_EXISTS=1 OP_STATUS=ROLLBACK_SUCCEEDED GITHUB_OUTPUT=/dev/null bash "$SCRIPTS_DIR/deploy-apprunner.sh" 2>&1); rc=$?
assert_eq "巻き戻った：終了コード 1" "1" "$rc"
assert_contains "巻き戻った：理由" "$out" "ROLLBACK_SUCCEEDED"
out=$(ECR_EXISTS=1 APPRUNNER_EXISTS=1 OP_STATUS=IN_PROGRESS GITHUB_OUTPUT=/dev/null bash "$SCRIPTS_DIR/deploy-apprunner.sh" 2>&1); rc=$?
assert_eq "時間切れ：終了コード 1" "1" "$rc"
assert_contains "時間切れ：理由" "$out" "時間内に終わりませんでした"
rm Dockerfile
out=$(GITHUB_OUTPUT=/dev/null bash "$SCRIPTS_DIR/deploy-apprunner.sh" 2>&1); rc=$?
assert_contains "Dockerfile が無い" "$out" "Dockerfile が無い"
echo 'FROM scratch' > Dockerfile
out=$(ACCESS_ROLE_ARN='' GITHUB_OUTPUT=/dev/null bash "$SCRIPTS_DIR/deploy-apprunner.sh" 2>&1); rc=$?
assert_contains "読み取りの役割が無い" "$out" "AWS_APPRUNNER_ACCESS_ROLE_ARN が無い"

echo "== Releases：OS ごとの物に OS の名前を付けて置く"
mkdir -p all/build-windows-latest/sub all/build-macos-14 all/build-ubuntu-latest
echo exe > all/build-windows-latest/hello.exe
echo bin > all/build-macos-14/hello
echo bin > all/build-ubuntu-latest/hello
echo txt > all/build-windows-latest/sub/README.txt
: > "$LOG"
out=$(NOW=20261029-0300 GITHUB_OUTPUT="$work/r" bash "$SCRIPTS_DIR/deploy-release.sh" all 2>&1); rc=$?
assert_eq "終了コード 0" "0" "$rc"
created=$(grep "gh release create" "$LOG")
assert_contains "タグ" "$created" "release create build-20261029-0300-0123456"
assert_contains "Windows の exe" "$created" "hello-windows.exe"
assert_contains "Mac" "$created" "hello-macos "
assert_contains "Linux" "$created" "hello-ubuntu"
assert_contains "下のフォルダの物も" "$created" "README-windows.txt"
assert_contains "そのコミットに付ける" "$created" "--target 0123456789abcdef"
assert_contains "タイトルにPRのタイトル" "$created" "あいさつを足す"
assert_contains "URL を出す" "$(cat "$work/r")" "url=https://github.com/o/app/releases/tag/build-20261029-0300-0123456"
rm -rf all; mkdir -p all/build-windows-latest
out=$(GITHUB_OUTPUT=/dev/null bash "$SCRIPTS_DIR/deploy-release.sh" all 2>&1); rc=$?
assert_eq "置く物が無い：終了コード 1" "1" "$rc"
assert_contains "置く物が無い：理由" "$out" "置く物がありません"

cd /; rm -rf "$work"
finish
