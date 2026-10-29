---
name: web-design-guidelines
description: Review UI code against the Web Interface Guidelines (accessibility, focus, forms, animation, typography, content handling, touch, theming, hydration). Use when building or reviewing screens, or when asked to "review my UI", "check accessibility", "audit design", "review UX" or "check against best practices".
---

# Web Interface Guidelines（画面の作法の点検）

元は Vercel の web-design-guidelines スキル（https://github.com/vercel-labs/agent-skills 、規則の本体は https://github.com/vercel-labs/web-interface-guidelines 、MIT）。元のスキルは毎回 URL から規則を取りに行くが、パイプラインの AI はネットから取れないので、規則を `guidelines.md` に写して置いてある。

## 使い方

1. `guidelines.md`（このフォルダ）を全部読む
2. 点検するファイル（画面の `.tsx`・`.css` など）を読む。指定が無ければ、今の作業で変えた画面のファイル
3. 規則に1つずつ当てる
4. 見つけた物を `file:line - 何がだめか` の形で、ファイルごとに短く書く（`guidelines.md` の Output Format）

## このリポジトリでの読み替え（規則より優先）

- いちばん上の決まりは `CLAUDE.md` と `docs/design.md`。食い違ったら、そちらが勝つ
- 文言は日本語。英語向けの規則は読み替える
  - 「Title Case」「Curly quotes」「Second person」「`&` over "and"」は使わない。日本語の引用は「」、省略は「…」（`...` は使わない）
  - 読み込み中の文言は「…」で終える（例：「読み込み中…」）
  - ボタンは何が起きるかを書く（「保存」「シフトを足す」）。エラーは何が起きて、どうすればいいか
- 依存パッケージは足さない（`virtua`・`nuqs` などの名前は例。足すときは人間に任せる。`content-visibility: auto` や URL のクエリなど、今ある物でできる方法を使う）
- 日付と数字は `Intl.DateTimeFormat`・`Intl.NumberFormat`（`ja-JP`）で書く。ただし design.md が書式を決めていればそれに従う

## レビューで使うとき

レビューの指摘は「直さないとまずい物」だけにする。次のような、使う人が実際に困る物を優先する。

- キーボードで操作できない（`div` に onClick、フォーカスが見えない、`outline: none` だけ）
- 入力欄にラベルが無い、アイコンだけのボタンに `aria-label` が無い
- `prefers-reduced-motion` を無視した動き、`transition: all`
- ズームの禁止（`user-scalable=no`・`maximum-scale=1`）
- 長い文字・空のデータで崩れる、取り消せない削除
- 日付の表示がサーバーとブラウザで食い違う（hydration の不一致）

細かい好み（見出しの折り返し方など）は、レビューでは指摘しない。
