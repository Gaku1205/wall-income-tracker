#!/usr/bin/env bash
# 工場：テンプレートから作ったリポジトリを、Python（FastAPI）の見本（examples/python）に切り替える。
# examples/python/README.md の「Python のアプリを作るとき」の手順を、そのまま自動でやる。使い方：factory-python.sh <リポジトリのフォルダ>
# 公開先は、まず none（AWS の準備が無くても Doctor が ❌ にならないように）。exe は作らない（必要になったら pipeline.json に足し、pyinstaller を戻す）
set -euo pipefail
cd "${1:?フォルダを指定}"
[ -d examples/python ] || { echo "examples/python がありません"; exit 1; }

# 1. Next.js の物を消す
rm -rf src package.json package-lock.json next.config.ts tsconfig.json eslint.config.mjs vitest.config.ts vercel.json next-env.d.ts public
# 2. AGENTS.md は空にする（ファイルは残す）
: > AGENTS.md
# 3. 見本をルートへ（. で始まるファイルも）。.gitignore は足す
cp -r examples/python/app examples/python/tests examples/python/cli.py examples/python/pyproject.toml \
  examples/python/requirements.txt examples/python/requirements-dev.txt examples/python/Dockerfile \
  examples/python/.dockerignore examples/python/pipeline.json .
cat examples/python/.gitignore >> .gitignore
rm -rf examples
# 4. 公開先は none。exe は作らないので pyinstaller は入れない（cli.py は、テストが使うので残す）
jq '.deploy = [{"kind": "none"}]' pipeline.json > pipeline.json.tmp && mv pipeline.json.tmp pipeline.json
python3 - <<'PY'
import json, re
# requirements-dev から pyinstaller を外す
lines = [l for l in open("requirements-dev.txt", encoding="utf-8") if not l.lower().startswith("pyinstaller")]
open("requirements-dev.txt", "w", encoding="utf-8").writelines(lines)
# 5. CLAUDE.md を Python 向けに
s = open("CLAUDE.md", encoding="utf-8").read()
s = s.replace("Next.js（App Router）＋TypeScript。", "Python（FastAPI）。", 1)
s = re.sub(r"（Next\.js 以外で作るなら[^\n]*?）", "", s, count=1)
s = "\n".join(l for l in s.split("\n") if not l.startswith("- Next.js固有の注意は AGENTS.md を読む"))
code = """## コードの書き方

- 型ヒントを付ける（mypy が通ること）。`Any` は使わない
- ロジックは `app/`、テストは `tests/`
- 判定ロジックなど、入力から出力が決まる関数には `tests/` に pytest でテストを書く
- 画面・APIの文言は日本語
"""
s = re.sub(r"## コードの書き方\n.*?(?=\n## )", code, s, count=1, flags=re.S)
open("CLAUDE.md", "w", encoding="utf-8").write(s)
# 6. 仕様書の技術の欄
s = open("docs/spec.md", encoding="utf-8").read()
s = s.replace("- 技術：Next.js（App Router）＋TypeScript、テストはVitest", "- 技術：Python（FastAPI）、テストは pytest", 1)
open("docs/spec.md", "w", encoding="utf-8").write(s)
PY
echo "Python（FastAPI）に切り替えた"
