"use client";

import { useEffect, useRef } from "react";

const TIDE = "#2B44F0";
const WALL = "#FF5A2E";
const OVER = "#FF2E6E";
const GLASS_LINE = "rgba(255, 255, 255, 0.7)";
const WALL_GLOW = "rgba(255, 90, 46, 0.25)";
const FORECAST_ALPHA = 0.38;

type Props = {
  /** 1日ずつの累計（1月1日〜12月31日） */
  cumulative: number[];
  /** 今日が1月1日から何日目か */
  todayIndex: number;
  /** 時刻の入れ物で開いている日（無ければ null） */
  openIndex: number | null;
  wall: number;
  /** 縦軸の上限 */
  max: number;
};

/** 全画面の面。確定・見込みの面、今日の線、壁の線を描く（静止画） */
export function Surface({ cumulative, todayIndex, openIndex, wall, max }: Props) {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const draw = () => paint(canvas, { cumulative, todayIndex, openIndex, wall, max });
    draw();
    window.addEventListener("resize", draw);
    return () => window.removeEventListener("resize", draw);
  }, [cumulative, todayIndex, openIndex, wall, max]);

  return <canvas ref={ref} className="surface" aria-hidden="true" />;
}

function paint(canvas: HTMLCanvasElement, p: Props) {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const w = window.innerWidth;
  const h = window.innerHeight;
  canvas.width = Math.round(w * dpr);
  canvas.height = Math.round(h * dpr);
  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);

  const n = p.cumulative.length;
  // 点 i は「i 日目の終わり」。点 0 は1月1日の始まり（0円）
  const x = (i: number) => (i / n) * w;
  const y = (yen: number) => h - (yen / p.max) * h;
  const valueAt = (i: number) => (i === 0 ? 0 : p.cumulative[i - 1]);
  const todayEnd = p.todayIndex + 1;
  const wallY = y(p.wall);

  const area = (from: number, to: number) => {
    ctx.beginPath();
    ctx.moveTo(x(from), h);
    for (let i = from; i <= to; i++) ctx.lineTo(x(i), y(valueAt(i)));
    ctx.lineTo(x(to), h);
    ctx.closePath();
  };

  // 壁の線より下は --tide、上（壁を超えた部分）は --over で塗る
  const fillArea = (from: number, to: number, alpha: number) => {
    for (const [top, bottom, color] of [
      [wallY, h, TIDE],
      [0, wallY, OVER],
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

  fillArea(0, todayEnd, 1);
  fillArea(todayEnd, n, FORECAST_ALPHA);

  const vertical = (i: number, color: string) => {
    const px = Math.round(x(i)) + 0.5;
    ctx.beginPath();
    ctx.moveTo(px, 0);
    ctx.lineTo(px, y(valueAt(i)));
    ctx.strokeStyle = color;
    ctx.lineWidth = 1;
    ctx.stroke();
  };

  vertical(todayEnd, GLASS_LINE);
  if (p.openIndex !== null) vertical(p.openIndex + 1, TIDE);

  ctx.save();
  ctx.beginPath();
  ctx.moveTo(0, wallY);
  ctx.lineTo(w, wallY);
  ctx.strokeStyle = WALL;
  ctx.lineWidth = 1.5;
  ctx.shadowColor = WALL_GLOW;
  ctx.shadowBlur = 8;
  ctx.stroke();
  ctx.restore();
}
