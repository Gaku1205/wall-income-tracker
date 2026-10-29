"use client";

import { useLayoutEffect, useRef, type RefObject } from "react";
import { dayOfYear, daysInMonth } from "@/lib/income";
import {
  canvasScale,
  ease,
  isAtRest,
  mixColor,
  PULSE_MS,
  pulseWidth,
  SLOW_FRAME_MS,
  springDaily,
  stepSpring,
  wobbleOffset,
  type SpringState,
} from "@/lib/motion";

const TIDE = "#2B44F0";
const WALL = "#FF5A2E";
const OVER = "#FF2E6E";
const GLASS_LINE = "rgba(255, 255, 255, 0.7)";
const WALL_GLOW = "rgba(255, 90, 46, 0.25)";
const FORECAST_ALPHA = 0.38;
/** prefers-reduced-motion のときの不透明度の切り替え（ミリ秒） */
const FADE_MS = 120;
/** 重いかどうかを決めるまでに見るコマ数 */
const SLOW_SAMPLE_FRAMES = 60;

type Props = {
  year: number;
  /** 1日ずつの累計（1月1日〜12月31日） */
  cumulative: number[];
  /** 今日が1月1日から何日目か */
  todayIndex: number;
  /** 時刻の入れ物で開いている日（無ければ null） */
  openIndex: number | null;
  wall: number;
  /** 壁の線をドラッグ中か（ばねを使わず指に付いてくる） */
  dragging: boolean;
  /** 縦軸の上限 */
  max: number;
  /** prefers-reduced-motion: reduce */
  reduced: boolean;
  /** 壁の線の高さ（`--wall-y`）と縦軸の上限（`--max`）を書き込む要素 */
  varsTarget: RefObject<HTMLElement | null>;
};

type Frame = {
  w: number;
  h: number;
  daily: number[];
  max: number;
  wall: number;
  todayEnd: number;
  openIndex: number | null;
  time: number;
  wobble: boolean;
  wallWidth: number;
  overColor: string;
};

/** 全画面の面。確定・見込みの面、今日の線、壁の線を、ばねと揺れで動かしながら描く */
export function Surface(props: Props) {
  const ref = useRef<HTMLCanvasElement>(null);
  const latest = useRef(props);
  const wake = useRef<(changed: boolean) => void>(() => {});
  const drawnKey = useRef("");

  useLayoutEffect(() => {
    latest.current = props;
    const key = `${props.cumulative.join()}|${props.wall}|${props.max}|${props.openIndex}`;
    const changed = key !== drawnKey.current;
    drawnKey.current = key;
    wake.current(changed);
  });

  // 最初の1枚と名札の位置を、画面に出る前に決める
  useLayoutEffect(() => {
    const canvas = ref.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;

    const p0 = latest.current;
    const monthEnds = Array.from({ length: 12 }, (_, m) =>
      dayOfYear(p0.year, m + 1, daysInMonth(p0.year, m + 1)),
    );
    const monthTargets = (cum: number[]) => monthEnds.map((i) => cum[i] ?? 0);

    let months: SpringState[] = monthTargets(p0.cumulative).map((x) => ({ x, v: 0 }));
    let max: SpringState = { x: p0.max, v: 0 };
    let wall: SpringState = { x: p0.wall, v: 0 };
    let wasOver = (p0.cumulative[p0.cumulative.length - 1] ?? 0) > p0.wall;
    let pulseStart = -Infinity;
    let fadeStart = -Infinity;
    let snapshot: HTMLCanvasElement | null = null;
    let raf = 0;
    let last = 0;
    let t0 = 0;
    let avgMs = 1000 / 60;
    let frames = 0;
    let slow = false;
    let lastVars = "";

    const fit = (scale: number) => {
      const cw = Math.round(window.innerWidth * scale);
      const ch = Math.round(window.innerHeight * scale);
      if (canvas.width !== cw || canvas.height !== ch) {
        canvas.width = cw;
        canvas.height = ch;
      }
      ctx.setTransform(scale, 0, 0, scale, 0, 0);
    };

    const frame = (now: number) => {
      raf = 0;
      const p = latest.current;
      if (t0 === 0) t0 = now;
      const dtMs = last === 0 ? 1000 / 60 : now - last;
      last = now;

      // 重いときは 0.5倍の解像度で描く（一度決めたら戻さない）
      if (!p.reduced && dtMs < 200) {
        avgMs = avgMs * 0.9 + dtMs * 0.1;
        if (++frames > SLOW_SAMPLE_FRAMES && avgMs > SLOW_FRAME_MS) slow = true;
      }

      const targets = monthTargets(p.cumulative);
      const total = p.cumulative[p.cumulative.length - 1] ?? 0;
      let moving = false;
      if (p.reduced) {
        months = targets.map((x) => ({ x, v: 0 }));
        max = { x: p.max, v: 0 };
        wall = { x: p.wall, v: 0 };
      } else {
        const dt = dtMs / 1000;
        months = months.map((s, i) => {
          const next = stepSpring(s, targets[i], dt);
          if (isAtRest(next, targets[i], 0.5)) return { x: targets[i], v: 0 };
          moving = true;
          return next;
        });
        max = stepSpring(max, p.max, dt);
        if (isAtRest(max, p.max, 1)) max = { x: p.max, v: 0 };
        wall = p.dragging ? { x: p.wall, v: 0 } : stepSpring(wall, p.wall, dt);
        if (isAtRest(wall, p.wall, 1)) wall = { x: p.wall, v: 0 };
      }

      // 面が壁の線を初めて超えた瞬間に1回だけ脈打つ
      const over = total > p.wall;
      if (over && !wasOver && !p.reduced) pulseStart = now;
      wasOver = over;
      const pulse = now - pulseStart;
      const pulsing = pulse < PULSE_MS;

      const w = window.innerWidth;
      const h = window.innerHeight;
      fit(canvasScale(window.devicePixelRatio, slow));

      const offsets = months.map((s, i) => s.x - targets[i]);
      paint(ctx, {
        w,
        h,
        daily: springDaily(p.cumulative, monthEnds, offsets),
        max: max.x,
        wall: wall.x,
        todayEnd: p.todayIndex + 1,
        openIndex: p.openIndex,
        time: (now - t0) / 1000,
        wobble: !p.reduced,
        wallWidth: pulsing ? pulseWidth(pulse) : 1.5,
        overColor: pulsing ? mixColor(TIDE, OVER, ease(pulse / PULSE_MS)) : OVER,
      });

      // 前の絵を重ねて、0.12秒で新しい絵へ切り替える
      const fade = now - fadeStart;
      if (snapshot && fade < FADE_MS) {
        ctx.save();
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.globalAlpha = 1 - fade / FADE_MS;
        ctx.drawImage(snapshot, 0, 0, canvas.width, canvas.height);
        ctx.restore();
      } else {
        snapshot = null;
      }

      // 壁の名札が線に付いてくるように、線の高さを渡す
      const vars = `${h - (wall.x / max.x) * h}|${max.x}`;
      const target = p.varsTarget.current;
      if (target && vars !== lastVars) {
        lastVars = vars;
        target.style.setProperty("--wall-y", `${h - (wall.x / max.x) * h}px`);
        target.style.setProperty("--max", String(max.x));
      }

      // 揺れがあるのでふだんは毎コマ描く。reduced のときは切り替えの間だけ
      if (!p.reduced || snapshot || moving || pulsing) schedule();
    };

    const schedule = () => {
      if (raf === 0 && !document.hidden) raf = requestAnimationFrame(frame);
    };

    wake.current = (changed) => {
      const p = latest.current;
      if (changed && p.reduced && !p.dragging && canvas.width > 0) {
        snapshot ??= document.createElement("canvas");
        snapshot.width = canvas.width;
        snapshot.height = canvas.height;
        snapshot.getContext("2d")?.drawImage(canvas, 0, 0);
        fadeStart = performance.now();
      }
      schedule();
    };

    const onVisibility = () => {
      if (document.hidden) {
        cancelAnimationFrame(raf);
        raf = 0;
      } else {
        last = 0;
        schedule();
      }
    };
    const onResize = () => schedule();

    // 開いた直後の1枚は前の絵が無いので、切り替えずにそのまま描く
    frame(performance.now());
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("resize", onResize);
    return () => {
      cancelAnimationFrame(raf);
      wake.current = () => {};
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("resize", onResize);
    };
  }, []);

  return <canvas ref={ref} className="surface" aria-hidden="true" />;
}

function paint(ctx: CanvasRenderingContext2D, f: Frame) {
  const { w, h } = f;
  ctx.clearRect(0, 0, w, h);

  const n = f.daily.length;
  // 点 i は「i 日目の終わり」。点 0 は1月1日の始まり（0円）
  const x = (i: number) => (i / n) * w;
  const todayX = x(f.todayEnd);
  const y = (i: number) => {
    const yen = i === 0 ? 0 : f.daily[i - 1];
    const base = h - (yen / f.max) * h;
    // 見込みの面の上辺だけ揺らす（今日で0、右端で最大3px）
    return f.wobble && i > f.todayEnd ? base - wobbleOffset(x(i), todayX, w, f.time) : base;
  };
  const wallY = h - (f.wall / f.max) * h;

  const area = (from: number, to: number) => {
    ctx.beginPath();
    ctx.moveTo(x(from), h);
    for (let i = from; i <= to; i++) ctx.lineTo(x(i), y(i));
    ctx.lineTo(x(to), h);
    ctx.closePath();
  };

  // 壁の線より下は --tide、上（壁を超えた部分）は --over で塗る
  const fillArea = (from: number, to: number, alpha: number) => {
    for (const [top, bottom, color] of [
      [wallY, h, TIDE],
      [0, wallY, f.overColor],
    ] as const) {
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, top, w, bottom - top);
      ctx.clip();
      ctx.globalAlpha = alpha;
      ctx.fillStyle = color;
      area(from, to);
      ctx.fill();
      ctx.restore();
    }
  };

  fillArea(0, f.todayEnd, 1);
  fillArea(f.todayEnd, n, FORECAST_ALPHA);

  const vertical = (i: number, color: string) => {
    const px = Math.round(x(i)) + 0.5;
    ctx.beginPath();
    ctx.moveTo(px, 0);
    ctx.lineTo(px, y(i));
    ctx.strokeStyle = color;
    ctx.lineWidth = 1;
    ctx.stroke();
  };

  vertical(f.todayEnd, GLASS_LINE);
  if (f.openIndex !== null) vertical(f.openIndex + 1, TIDE);

  ctx.save();
  ctx.beginPath();
  ctx.moveTo(0, wallY);
  ctx.lineTo(w, wallY);
  ctx.strokeStyle = WALL;
  ctx.lineWidth = f.wallWidth;
  ctx.shadowColor = WALL_GLOW;
  ctx.shadowBlur = 8;
  ctx.stroke();
  ctx.restore();
}
