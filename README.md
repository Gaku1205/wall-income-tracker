# ai-dev-template

**Issueにやりたいことを1行書くだけで、AIが清書・実装・レビュー・修正・マージ・公開まで進める**、個人開発用のリポジトリの土台です。

人間がやるのは「何を作るか決める」ことと、AIが判断に迷って止まったときの確認だけ。合否はAIではなくCI（確認コマンド。Next.js なら型チェック・リント・テスト・ビルド）が決めます。

**言語も公開先も選べます。** 何も書かなければ Next.js＋Vercel。リポジトリ直下の `pipeline.json` に書けば、Python・Go・Java・.NET などで動き、公開先は AWS App Runner（Web・API）、GitHub Releases（exe などの配布物）、Expo（スマホアプリ）から選べます（`docs/pipeline.md`「言語と公開先」）。

## 流れ

```
メモを書く ─▶ 企画AIが清書 ─▶ 実装AI ─▶ PR ─▶ CI ─▶ レビューAI ─▶ 自動マージ ─▶ 公開（Vercel／App Runner／Releases／Expo）─▶ スマホに通知
 (人間)                                           ▲            │           │
                                                  └── AIが修正 ◀┴── 失敗・指摘（3回まで。最後の1回は opus）
                                                                  │
                                                      直らなければ ai:stuck ─▶ 人間に通知して止まる

止まったら自動で再開する
  使用量の上限・AIのエラー・時間切れ ─▶ ai:retry ─▶ 見張り役が30分以上あけてやり直す（10回まで）
  人間が ai:stuck を外す ─▶ 止まった所から続ける
```

- **自動**：清書、実装、PR作成、CI、レビュー、修正、マージ、公開、通知、一時的な失敗からのやり直し
- **人間が判断**：何を作るか（メモを書く）。止まって通知が来たとき（`ai:stuck`）の確認。`ai:hold` を付けた大事な変更の最後のマージ
- 順番待ち（`ai:queue`）を付けると、前の作業が終わってから番号順に始まります。まとめて頼んで寝ておけます

詳しい流れ・ラベル・止まる条件は [docs/pipeline.md](docs/pipeline.md)。

## 1行で新しいサービスを作る（工場）

最初の1回だけ準備（[docs/pipeline.md「工場」](docs/pipeline.md#工場1行から新しいサービスを作る)）をしたら、あとはこのリポジトリに **「新サービス：〜」というタイトルのIssueを1行書くだけ**。リポジトリの作成・鍵の登録・main の保護・Vercel・最初のIssueまで自動で進み、そこからはいつものパイプラインが実装・公開まで進める。下の「使い方」は、手で1つずつ作るときの手順。

## 使い方

1. このリポジトリの **Use this template** から新しいリポジトリを作る
2. **言語を決める**：Next.js ならこのまま。**Python（FastAPI）なら [examples/python/README.md](examples/python/README.md) の手順で切り替える**（ほかの言語も `pipeline.json` に書けば動く。[docs/pipeline.md「言語と公開先」](docs/pipeline.md#言語と公開先pipelinejson)）
3. GitHubの Claude アプリを、そのリポジトリに入れる
4. Settings → Secrets and variables → Actions に登録する（詳細は [docs/pipeline.md](docs/pipeline.md#必要な設定リポジトリの-settings--secrets-and-variables--actions)）

   | 名前 | 種類 | 作り方 |
   | --- | --- | --- |
   | `CLAUDE_CODE_OAUTH_TOKEN` | Secret | パソコンに Claude Code を入れ（入れ方は [Claude Code の説明](https://docs.claude.com/en/docs/claude-code/overview)）、ターミナル（Windows なら PowerShell）で `claude setup-token` を実行し、出てきたトークンを貼る。Claude のサブスクで AI を動かす |
   | パイプラインの鍵 | Secret と Variable | **おすすめは GitHub App**（10分・1回だけ。期限切れなし）：[作り方](docs/pipeline.md#パイプライン用の-github-app-の作り方1回だけ)。手軽に試すなら代わりに Secret `PIPELINE_TOKEN`：GitHub の Settings → Developer settings → Fine-grained tokens で、このリポジトリだけを選び、Actions・Checks・Commit statuses を Read、Contents・Issues・Pull requests・Workflows を Read and write にして作る |
   | `NTFY_TOPIC` | Secret | スマホ通知（ntfyアプリ）で購読するトピック名（好きな英数字）。無ければ通知しない |

5. **最初の push** で「Bootstrap」が自動で動く。`ai:` などのラベルを作り、`CLAUDE.md` の「ai-dev-template 自身の作業」の節を消し、診断（Doctor）の結果を実行画面の Summary に出す。手で何かを実行する必要はない
   - Bootstrap は `ai:plan` ラベルが無いときだけ動く。2回目以降の push では何もしない
6. **main を守る**：Settings → Branches → **Add classic branch protection rule** で、Branch name pattern に `main`、「Require a pull request before merging」（承認の人数は 0 のまま）と「Require status checks to pass」（検索欄で `check` を選ぶ。CI のジョブの名前）を付けて Create。無いと、AI が PR とレビューを通さずに main へ入れられてしまう
7. `CLAUDE.md` の1行目と `docs/spec.md`・`docs/design.md` にアプリのことを書く
8. 公開先をつなぐ：Next.js なら Vercel でリポジトリを読み込む（main にマージされるたびに公開される）。ほかの公開先（AWS App Runner・exe・スマホ）は [docs/pipeline.md「言語と公開先」](docs/pipeline.md#言語と公開先pipelinejson)。まず試すだけなら、公開はつながなくてよい
9. Actions の **Doctor** を手で実行して、Summary の ✅／⚠️／❌ を確かめる
   - ❌ は Summary の「→」のとおりに直して、もう一度 Doctor を実行する
   - ⚠️ は動くが直したほうがよい物（例：通知の Secret が無い、ブランチの自動削除がオフ）
10. Issueの「メモ（AIにおまかせ）」から、やりたいことを書く

### 言葉

| 言葉 | 意味 |
| --- | --- |
| 進行役 | AIの作業のあいだをつなぐスクリプト（`pipeline.yml`・`.github/scripts/`）。次にどのAIを動かすか、マージするかを決める |
| 見張り役 | 30分ごとと、ほかの作業が終わるたびに動き、止まった物・取りこぼした物を拾ってやり直す（`watchdog.yml`） |
| 配る・配り先 | テンプレートの仕組み（`.github/`）の更新を、テンプレートから作ったリポジトリへ PR で届けること |
| 清書 | 1行のメモを、AIが実装できる Issue（やること・受け入れ条件）に書き直すこと |
| opus・sonnet・haiku | Claude のモデルの名前。大きい作業ほど強いモデルを使う |

**補足：Setup Labels（必要なら）**
ラベルが足りないときだけ、Actions の **Setup Labels** を手で1回実行する。ただし、Bootstrap より先にこれを実行すると、Bootstrap は「ラベルがもうある」として何もしないので、`CLAUDE.md` の節の削除と診断も飛ばされる。その場合は、`CLAUDE.md` の「ai-dev-template 自身の作業」の節を手で消し、Doctor を手で実行する。

テンプレート（本体）の更新は、本体の main でCIが通った版だけが、このテンプレートから作ったリポジトリ（自動）と、本体の `.github/sync-targets` に書いた配り先へ自動で配られる（この自動配布は本体だけが動かす）。

### Vercelの公開回数について

Vercelの無料プランには、1日に公開できる回数の上限があります。AIは `claude/*` ブランチに何度もpushするので、そのたびにプレビューを作ると上限をすぐ使い切ってしまいます。`vercel.json` は、`claude/*` ブランチのプレビューを作らず、mainにマージされたときだけ公開するための設定です。また、直前のコミットが `.github/` と `docs/pipeline.md` の変更だけなら、アプリは変わらないので公開を飛ばします（`ignoreCommand`）。

## 安全のしくみ

- 合否を決めるのはCI。AIの「できました」は信じない
- `.github/`・`docs/pipeline.md`・`CLAUDE.md`・`AGENTS.md`・`pipeline.json` を変えるPRは、CIとレビューが通っても自動でマージせず、人間に任せて通知する。仕組みそのものがAIの判断だけで書き換わらないようにするため。例外はテンプレートから配られた更新の PR（人間が書いてテンプレートの CI を通った物なので、配り先の CI が通れば自動でマージする）
- AIは `.github/`・`docs/pipeline.md`・`CLAUDE.md`・依存パッケージを触らない
- 進行役（`pipeline.yml`）はmainにある版が動くので、PRの中身で判断を書き換えられない
- 自動の修正は3回まで（最後の1回は opus）、自動のやり直しは10回まで。無限に回らない。超えたら `ai:stuck` で人間に回す
- `ai:hold` を付けると、最後のマージだけ人間が押す
- 公開後に壊れていたら、Vercelの画面から前の版にすぐ戻せる

詳細は [docs/pipeline.md](docs/pipeline.md#安全のしくみ)。

実際に動いた例：[agent-desk](https://github.com/Gaku1205/agent-desk)（AIに開発を任せるときの進行状況と「人間の判断待ち」を1画面で見るダッシュボード）は、このテンプレートで作りました。

## 中身

| 場所 | 内容 |
| --- | --- |
| `.github/workflows/` | 企画・実装・レビュー・修正のAI（[anthropics/claude-code-action](https://github.com/anthropics/claude-code-action)）、CI、進行役、公開通知 |
| `.github/scripts/` | 進行役の判断（PR作成、CI後・レビュー後・修正後の次の一手、通知） |
| `CLAUDE.md` | AIが守るルール（触ってはいけない場所、作業の終わらせ方、PRの書き方） |
| `docs/` | 仕様書・デザイン仕様・パイプラインの説明 |
| `src/` | 最小の Next.js（App Router）＋TypeScript＋Vitest |
| `vercel.json` | `claude/*` ブランチのVercelプレビューを作らない設定と、`.github/`・`docs/pipeline.md` だけの変更では公開を飛ばす設定（`ignoreCommand`） |
| `LICENSE` | MIT License（Copyright (c) 2026 Gaku1205） |
