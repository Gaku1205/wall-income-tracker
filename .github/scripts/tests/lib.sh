#!/usr/bin/env bash
# テストの共通部品：疑似 gh の準備、状態の読み書き、判定（assert_*）
# 使い方：各テストの先頭で source して、最後に finish を呼ぶ
set -u
export PYTHONWARNINGS=ignore
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PASSED=0
FAILED=0

setup_mock() {
  MOCK_DIR="$(mktemp -d)"
  mkdir -p "$MOCK_DIR/bin"
  cp "$TESTS_DIR/fake-gh" "$MOCK_DIR/bin/gh"
  # 疑似 curl：通知（ntfy）に送る内容を curl.log に1行ずつ残す（本物のネットワークには出ない）
  printf '#!/usr/bin/env bash\ncat >> "%s/curl.log"\necho >> "%s/curl.log"\n' "$MOCK_DIR" "$MOCK_DIR" > "$MOCK_DIR/bin/curl"
  chmod +x "$MOCK_DIR/bin/curl"
  : > "$MOCK_DIR/curl.log"
  export PATH="$MOCK_DIR/bin:$PATH"
  export MOCK_STATE="$MOCK_DIR/state.json"
  export GITHUB_REPOSITORY=o/r GH_TOKEN=x READ_TOKEN=x NTFY_TOPIC=test-topic MAX_RETRY=3 RETRY_COOLDOWN_MIN=30 INTAKE_WAIT_SEC=0
  unset NOTIFY_EVENTS AGENT_DESK_URL
  trap 'rm -rf "$MOCK_DIR"' EXIT
}

# 状態を初期化する。引数は JSON（足りない項目は空で補う）
init_state() {
  python3 - "$1" <<'PY'
import json, os, sys
s = {'next_id': 0, 'comments': [], 'labels': {}, 'issue_updated': {}, 'pulls': [], 'checks': [], 'runs': [], 'jobs': [], 'branches': [], 'authors': {}}
s.update(json.loads(sys.argv[1]))
json.dump(s, open(os.environ['MOCK_STATE'], 'w'))
PY
}

# 状態を python で書き換える（変数 s が状態）。例：state_py "s['labels']['7']=[]"
state_py() {
  python3 - "$1" <<'PY'
import json, os, sys
s = json.load(open(os.environ['MOCK_STATE']))
exec(sys.argv[1])
json.dump(s, open(os.environ['MOCK_STATE'], 'w'))
PY
}

ago() { date -u -d "$1 minutes ago" +%Y-%m-%dT%H:%M:%SZ; }
labels_of() { python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print(','.join(sorted(s['labels'].get('$1',[]))))"; }
comments_of() { python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print('\n'.join(c['body'] for c in s['comments'] if c['issue']=='$1'))"; }
branch_names() { python3 -c "import json,os;s=json.load(open(os.environ['MOCK_STATE']));print(','.join(sorted(b['name'] for b in s['branches'])))"; }
# 記録のコメント（<!-- auto-retry -->）の更新時刻を、N分前に書き換える（待ち時間が過ぎたことにする）
age_retry_comments() { state_py "
for c in s['comments']:
    if 'auto-retry' in c['body']: c['updated_at'] = '$(ago "$1")'"; }
# 送った通知の数（疑似 curl の記録）
notify_count() { grep -c '"topic"' "$MOCK_DIR/curl.log" || true; }
# 記録のコメントの印を書き換える（上限の待ちの時刻をずらすのに使う）。使い方：set_mark_value limit-until 123
set_mark_value() { state_py "
import re
for c in s['comments']:
    if 'auto-retry' in c['body']: c['body'] = re.sub(r'<!-- $1=[0-9a-z]+ -->', '<!-- $1=$2 -->', c['body'])"; }
# スクリプトを、リポジトリのルートから動かす
run_script() { local script="$1"; shift; bash "$SCRIPTS_DIR/$script" "$@" 2>&1; }
run_lib() { bash -c "source '$SCRIPTS_DIR/pipeline-lib.sh'; $1" 2>&1; }

assert_eq() { # 説明 期待 実際
  if [ "$2" = "$3" ]; then PASSED=$((PASSED + 1)); echo "  ok   $1"
  else FAILED=$((FAILED + 1)); echo "  FAIL $1"; echo "       期待: $2"; echo "       実際: $3"; fi
}
assert_contains() { # 説明 全体 含むはずの文字
  if printf '%s' "$2" | grep -qF -- "$3"; then PASSED=$((PASSED + 1)); echo "  ok   $1"
  else FAILED=$((FAILED + 1)); echo "  FAIL $1"; echo "       含むはず: $3"; echo "       実際: $2"; fi
}
assert_not_contains() { # 説明 全体 含まないはずの文字
  if printf '%s' "$2" | grep -qF -- "$3"; then FAILED=$((FAILED + 1)); echo "  FAIL $1"; echo "       含まないはず: $3"; echo "       実際: $2"
  else PASSED=$((PASSED + 1)); echo "  ok   $1"; fi
}
finish() {
  echo "$(basename "$0")：成功 $PASSED / 失敗 $FAILED"
  [ "$FAILED" -eq 0 ]
}
