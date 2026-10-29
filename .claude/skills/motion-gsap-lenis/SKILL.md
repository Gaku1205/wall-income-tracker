---
name: motion-gsap-lenis
description: How to use GSAP (with @gsap/react and ScrollTrigger) and Lenis smooth scroll in this Next.js App Router project. Use when package.json already has gsap or lenis and a screen needs scroll-driven or timeline animation, or when deciding whether a service should use them at all.
---

# GSAP と Lenis の使い方

- GSAP：時間に沿った動き・スクロールに合わせた動き（ScrollTrigger）を作る。https://gsap.com （3.13 から全部無料。「Standard 'no charge' license」。Webflow と競う、動きを作る道具そのものを作るのには使えない）
- Lenis：スクロールをなめらかにする。https://github.com/darkroomengineering/lenis （MIT）

## 使ってよいとき

- `package.json` の dependencies に `gsap`（と `@gsap/react`）・`lenis` が**もう入っている**ときだけ使う。入っていなければ使わない（依存パッケージは AI が足さない。CSS の transition・animation、`@keyframes` で作る）
- 入っていても、`docs/design.md` の「動き」に書かれた動きだけを作る。新しい動きは、先に design.md に書いてから
- 工場のデザイン部門が入れるかを決めるのは、型が「鑑賞・作品・体験」のサービスだけ（スクロールして見せるページ、作品、遊び）。管理・記録の道具・調べる・手続きでは入れない（なめらかなスクロールは、表や入力の多い画面では邪魔になる）

## 決まり

- `prefers-reduced-motion: reduce` では、動きを止めるか、すぐ終わる形にする（GSAP は `gsap.matchMedia()`、Lenis は既定の `respectReducedMotion: true` のまま）
- 動かすのは `transform`（x・y・scale・rotate）と `opacity` だけ。width・height・top・left などは動かさない
- 内容を隠したままにしない：JS が動かなくても、最後の状態（全部見える）で読めるようにする。最初の状態を CSS で隠すなら、`prefers-reduced-motion` と JS の失敗のときに見えるようにする
- 文字を読む前に動きが終わる（入ってくる動きは 0.6 秒以内が目安）。スクロールを奪わない（pin は 1 画面分まで）
- アンマウントで必ず片付ける（`useGSAP` は自動。Lenis は `destroy()`）
- サーバーでは動かさない：GSAP・Lenis を使う部品は `"use client"` にする

## 書き方（Next.js App Router）

### GSAP（部品の中の動き）

```tsx
"use client";
import { useRef } from "react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useGSAP } from "@gsap/react";

gsap.registerPlugin(useGSAP, ScrollTrigger);

export function Reveal({ children }: { children: React.ReactNode }) {
  const root = useRef<HTMLDivElement>(null);
  useGSAP(
    () => {
      const mm = gsap.matchMedia();
      mm.add("(prefers-reduced-motion: no-preference)", () => {
        gsap.from(".reveal-item", {
          y: 24,
          opacity: 0,
          duration: 0.5,
          ease: "power2.out",
          stagger: 0.06,
          scrollTrigger: { trigger: root.current, start: "top 80%" },
        });
      });
    },
    { scope: root },
  );
  return <div ref={root}>{children}</div>;
}
```

- セレクタは `scope` の中だけに効く。押したときの動きなど、あとで作る動きは `contextSafe` で包む
- `@gsap/react` が無ければ、`useEffect` の中で `const ctx = gsap.context(() => { ... }, root)` を作り、`return () => ctx.revert()` で片付ける

### Lenis（ページ全体のなめらかなスクロール）

`src/components/SmoothScroll.tsx` を作り、`src/app/layout.tsx` の `<body>` の中に1つだけ置く。CSS は layout.tsx で `import "lenis/dist/lenis.css";`。

```tsx
"use client";
import { useEffect } from "react";
import Lenis from "lenis";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

gsap.registerPlugin(ScrollTrigger);

export function SmoothScroll() {
  useEffect(() => {
    const lenis = new Lenis({ autoRaf: false, anchors: true });
    lenis.on("scroll", ScrollTrigger.update);
    const tick = (time: number) => lenis.raf(time * 1000);
    gsap.ticker.add(tick);
    gsap.ticker.lagSmoothing(0);
    return () => {
      gsap.ticker.remove(tick);
      lenis.destroy();
    };
  }, []);
  return null;
}
```

- GSAP が入っていなくて Lenis だけなら、`new Lenis({ autoRaf: true, anchors: true })` にして、ticker の行は書かない
- 中で別にスクロールする箱（一覧・モーダル）には `data-lenis-prevent` を付ける
- `position: sticky` はそのまま効く。`scroll-behavior: smooth` は CSS に書かない（Lenis と二重になる）

## 確かめること

- `npm run build` が通る（サーバー部品から GSAP・Lenis を import していない）
- 見た目のテスト（`npm run test:visual`）があるなら、動きの途中で撮らない：テストの側で `prefers-reduced-motion: reduce` にしているか、動きが終わってから撮っているかを確かめる
