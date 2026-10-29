# hello-python（Python の見本）

ai-dev-template を Next.js 以外で使う見本。`pipeline.json` で言語と公開先を選んでいる。

- `app/`：API（FastAPI）。`/health` と `/hello?name=...`。**AWS App Runner** で動かす（`Dockerfile`）
- `cli.py`：同じ処理の CLI。**exe にして GitHub Releases** に置く（Windows・Mac）
- 確認コマンド：`ruff check .`・`mypy`・`pytest -q`（CI で全部回し、AI にもこれだけ許す）

テンプレート本体では、`.github/workflows/stack-selftest.yml` がこの見本を本物の GitHub のランナーで通す（確認・Windows と Mac の exe・Docker のイメージの起動）。

## Python のアプリを作るとき

テンプレートから作ったリポジトリを手元に clone して、その中で作業する。

1. **Next.js の物を消す**：`src/`・`package.json`・`package-lock.json`・`next.config.ts`・`tsconfig.json`・`eslint.config.mjs`・`vitest.config.ts`・`vercel.json`
2. **AGENTS.md は空にする**（ファイルは消さない。中身は全部 Next.js 向けの注意。ファイルが無いと Doctor が ❌ を出す）
3. **見本をルートに移す**。`.` で始まるファイル（`.gitignore`・`.dockerignore`）も移すこと。ルートの `README.md`（テンプレートの説明）はアプリの説明に書き換えるので、見本の README は移さなくてよい

   ```bash
   # Git Bash・Mac・Linux
   cp -r examples/python/app examples/python/tests examples/python/cli.py \
         examples/python/pyproject.toml examples/python/requirements.txt examples/python/requirements-dev.txt \
         examples/python/Dockerfile examples/python/.dockerignore examples/python/pipeline.json .
   cat examples/python/.gitignore >> .gitignore      # ルートの .gitignore に足す（上書きしない）
   rm -r examples
   ```

   ```powershell
   # Windows（PowerShell）
   Copy-Item -Recurse examples\python\app, examples\python\tests, examples\python\cli.py, examples\python\pyproject.toml, `
     examples\python\requirements.txt, examples\python\requirements-dev.txt, examples\python\Dockerfile, `
     examples\python\.dockerignore, examples\python\pipeline.json -Destination .
   Get-Content examples\python\.gitignore | Add-Content .gitignore
   Remove-Item -Recurse examples
   ```

4. **公開先を決める**（`pipeline.json` の `deploy`）
   - まず試すだけなら、`"deploy": [ { "kind": "none" } ]` にする（AWS の設定が無いと Doctor が ❌ を出すため）
   - App Runner を使うなら、`service` をアプリの名前（小文字の英数字と `-`）にする。AWS 側の準備は `docs/pipeline.md`「AWS App Runner」
   - exe が要らなければ、`github-release` の行と一緒に `cli.py`・`pyproject.toml` の `files` の `"cli.py"`・`requirements-dev.txt` の `pyinstaller` も消す（`cli.py` だけ消すと mypy が「cli.py が読めない」で落ちる）
5. **CLAUDE.md を Python 向けに直す**
   - 1行目：アプリの説明と「Python（FastAPI）」
   - 「Next.js固有の注意は AGENTS.md を読む…」の行を消す
   - 「コードの書き方」：例として「型ヒントを付ける」「ロジックは `app/`、テストは `tests/`」「判定ロジックには `tests/` にテストを書く」
   - 「終わる前に実行する」は、`pipeline.json` の `checks` を見るので直さなくてよい
6. **docs/spec.md の「技術」の欄**を Python（FastAPI・pytest）に直す
7. commit して push し、Actions の Doctor を実行する

## 手元で動かす

Git Bash・Mac・Linux：

```bash
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
ruff check . && mypy && pytest -q       # CI と同じ確認
uvicorn app.main:app --reload           # http://localhost:8000/hello?name=you
python cli.py you                       # Hello, you!
```

Windows（PowerShell）：

```powershell
python -m venv .venv; .venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
ruff check .; mypy; pytest -q
uvicorn app.main:app --reload
python cli.py you
```

CI と全く同じ順に回すなら、Git Bash で `.github/scripts/run-checks.sh`（`bash` と `jq` が要る。依存は先に入れておく）。
