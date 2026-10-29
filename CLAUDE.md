# このリポジトリでのルール

（アプリの説明を1〜2行で書く）。Next.js（App Router）＋TypeScript。（Next.js 以外で作るなら、この行と下の「コードの書き方」を言語に合わせて書き換え、`pipeline.json` に言語・確認コマンド・公開先を書く。`docs/pipeline.md`「言語と公開先」）

- 作業の前に必ず `docs/spec.md`（仕様書）を読む。画面に触る作業では `docs/design.md`（デザイン仕様）も読み、色・文字・文言はそこに書かれたものだけを使う。仕様と食い違う指示がIssueにあれば、Issueを優先し、PRの説明にその旨を書く
- Next.js固有の注意は AGENTS.md を読む。このNext.jsは学習データと違う所があるので、`node_modules/next/dist/docs/` を確認してから書く
- 見た目や挙動を新しく決める・変えるIssueでは、実装の前に `docs/spec.md`（挙動）と `docs/design.md`（見た目）を更新し、同じPRに入れる。新しい色・文字・文言・寸法も、先に `docs/design.md` に書いてから使う。書き方は既存の文章に合わせる（誰が読んでも同じ画面が作れる具体さで）。Issueに書かれていない決まりを勝手に変えない。デザインが書かれていない新しい見た目は、既存の色・文字・「避けること」に合わせてあなたが決め、PRの説明に「仮に決めた所」として書く
- 開発の流れ（AIが清書・実装・レビュー・修正・マージまで進める）は `docs/pipeline.md`

## 作業のしかた

- Issueの「やること」と「受け入れ条件」だけを実装する。頼まれていない改善や大きなリファクタはしない
- 変更は小さく、1つのPRで1つのIssue
- 終わる前に必ず確認コマンドを全部実行し、全部通ることを確認する。確認コマンドは `pipeline.json` の `checks`。`pipeline.json` が無ければ次の4つ
  - `npm run typecheck`
  - `npm run lint`
  - `npm run test`
  - `npm run build`
- 通らないまま作業を終えない。どうしても直せない場合は、その理由をIssueかPRのコメントに書く
- レビューの指摘を直すよう頼まれたら、直してpushする。指摘が間違っていると判断したら、直さずに理由をPRにコメントする

## 触ってはいけないもの

- `.github/` 配下（ワークフロー、スクリプト、テンプレート）。ただし ai-dev-template 自身だけ、下の「ai-dev-template 自身の作業」で許した物は触ってよい
- `package.json` の依存パッケージの追加・変更（必要なら理由をコメントに書いて人間に任せる）
- `pipeline.json`（言語・確認コマンド・公開先。AIに許すコマンドを決めるので、変えるときは理由と差分をPRの説明に書いて人間に任せる）
- `CLAUDE.md`、`AGENTS.md`、`docs/pipeline.md`（パイプラインの説明。ai-dev-template 自身だけ、`docs/pipeline.md` は下の節で触ってよい）。`docs/spec.md` と `docs/design.md` は、上のとおり必要なときだけ更新してよい
- APIキーやトークンなどの秘密情報。コード・コメント・テストに書かない。設定は環境変数から読む

## ai-dev-template 自身の作業（パイプライン本体のリポジトリだけ。テンプレートから新しいアプリを作ったら、この節ごと消す）

<!-- pipeline-self-edit: auto -->

- 触ってよい：`.github/scripts/`（テストの `tests/` を含む）と `docs/pipeline.md`、README
- 触ってはいけない：`.github/workflows/` と `.github/actions/`（許可と安全のため、マネージャー（人間側のClaude）が行う。GitHubの仕様で、AIはワークフローのファイルをpushできない）、`CLAUDE.md`、`AGENTS.md`（AI自身のルールを、AIが無人で書き換えない）、`package.json` の依存パッケージ。これらの変更が要るときは、PRの説明の「人間にお願いしたいこと」に、変えてほしい差分を書く
- スクリプトを変えたら、場面に合うテストを `.github/scripts/tests/` に足し、`.github/scripts/tests/run-all.sh` を通す（使い方は `tests/lib.sh`）。シェルは `shellcheck` の警告が出ない書き方にする
- 触ってよい物だけを変えるPRは、CIもレビューも通れば、アプリの作業と同じく自動でマージされる（上の印 `pipeline-self-edit` があるリポジトリだけ。マージされるかは、進行役が main の CLAUDE.md を見て決める）。ワークフロー・`CLAUDE.md`・`AGENTS.md` を触るPRは、自動ではマージされず `ai:hold` が付く
- 秘密情報（トークンなど）を、スクリプトやテストに書かない。環境変数から読む

## コードの書き方

- TypeScriptの型をちゃんと付ける。`any` は使わない
- ロジックは `src/lib/`、画面の部品は `src/components/`
- 判定ロジックなど、入力から出力が決まる関数には `*.test.ts` でテストを書く
- 画面の文言は日本語

## PRとコメント

- PRの説明は日本語で、次を書く
  - 対応したIssue（`Closes #番号`）
  - 何を変えたか（2〜3行）
  - 受け入れ条件をどう満たしたか（チェックリスト）
  - 人間が手で確認すべきこと（あれば）
- レビューの指摘に対応するときは、直した内容を短くコメントで返す
