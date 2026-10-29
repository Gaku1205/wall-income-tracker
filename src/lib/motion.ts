import { stepTime, WALL_CANDIDATES, WALL_STEP } from "./income";

/** ばねの決まり（docs/design.md「動き」） */
export type SpringConfig = { stiffness: number; damping: number; mass: number };
export const SPRING: SpringConfig = { stiffness: 420, damping: 32, mass: 1 };

/** ばねの今の位置と速さ */
export type SpringState = { x: number; v: number };

/** 1回の計算で進める最大の時間（秒）。タブの切り替えなどで間が空いても飛ばない */
const MAX_FRAME_SEC = 0.064;
/** 細かく刻む幅（秒） */
const SUB_STEP_SEC = 1 / 240;

/** ばねを dtSec 秒だけ進める（半陰的オイラー法を細かく刻む） */
export function stepSpring(
  state: SpringState,
  target: number,
  dtSec: number,
  config: SpringConfig = SPRING,
): SpringState {
  let { x, v } = state;
  let remaining = Math.min(Math.max(0, dtSec), MAX_FRAME_SEC);
  while (remaining > 1e-9) {
    const h = Math.min(remaining, SUB_STEP_SEC);
    const a = (-config.stiffness * (x - target) - config.damping * v) / config.mass;
    v += a * h;
    x += v * h;
    remaining -= h;
  }
  return { x, v };
}

/** 止まったとみなせるか（位置のずれも速さも precision 未満） */
export function isAtRest(state: SpringState, target: number, precision: number): boolean {
  return Math.abs(state.x - target) < precision && Math.abs(state.v) < precision * 10;
}

/** cubic-bezier(x1, y1, x2, y2) の曲線。0〜1 の時間の割合から進み具合を返す */
export function cubicBezier(x1: number, y1: number, x2: number, y2: number): (t: number) => number {
  const bez = (t: number, a: number, b: number) =>
    3 * a * t * (1 - t) ** 2 + 3 * b * t ** 2 * (1 - t) + t ** 3;
  const slope = (t: number, a: number, b: number) =>
    3 * a * (1 - t) ** 2 + 6 * (b - a) * t * (1 - t) + 3 * (1 - b) * t ** 2;
  return (p: number) => {
    if (p <= 0) return 0;
    if (p >= 1) return 1;
    // 時間の割合 p になる曲線の位置 t を探す（ニュートン法、だめなら二分法）
    let t = p;
    for (let i = 0; i < 8; i++) {
      const d = slope(t, x1, x2);
      if (Math.abs(d) < 1e-6) break;
      const next = t - (bez(t, x1, x2) - p) / d;
      if (next < 0 || next > 1) break;
      t = next;
    }
    if (Math.abs(bez(t, x1, x2) - p) > 1e-5) {
      let lo = 0;
      let hi = 1;
      for (let i = 0; i < 40; i++) {
        t = (lo + hi) / 2;
        if (bez(t, x1, x2) < p) lo = t;
        else hi = t;
      }
    }
    return bez(t, y1, y2);
  };
}

/** CSS の切り替えと同じ曲線 `cubic-bezier(.2, .8, .2, 1)` */
export const ease = cubicBezier(0.2, 0.8, 0.2, 1);

/** 段2の数え上げにかける時間（ミリ秒） */
export const COUNT_UP_MS = 400;

/** 数え上げの途中の値（elapsedMs ミリ秒たったとき） */
export function countUp(from: number, to: number, elapsedMs: number): number {
  return from + (to - from) * ease(Math.min(1, Math.max(0, elapsedMs / COUNT_UP_MS)));
}

/** 段1の数字の、桁ごとの遅れ（ミリ秒） */
export const DIGIT_DELAY_MS = 20;

/** 段1の index 番目（左から）の桁が動き出すまでの遅れ。右の桁ほど遅れて止まる */
export function digitDelay(index: number): number {
  return index * DIGIT_DELAY_MS;
}

/** 見込みの面の上辺の揺れの最大の振幅（px） */
export const WOBBLE_MAX_PX = 3;

/** 揺れの振幅。今日の位置で0、右端で最大 3px。今日より左は0 */
export function wobbleAmplitude(x: number, todayX: number, width: number): number {
  if (x <= todayX || width <= todayX) return 0;
  return (Math.min(x, width) - todayX) / (width - todayX) * WOBBLE_MAX_PX;
}

/** 2つの正弦波（周期 5.2秒・8.7秒、横の波長は画面幅の0.6倍・0.27倍） */
const WAVES = [
  { period: 5.2, wavelength: 0.6 },
  { period: 8.7, wavelength: 0.27 },
] as const;

/** 揺れの高さ（px、上向きが正）。timeSec は開いてからの秒 */
export function wobbleOffset(x: number, todayX: number, width: number, timeSec: number): number {
  const amp = wobbleAmplitude(x, todayX, width);
  if (amp === 0) return 0;
  let sum = 0;
  for (const w of WAVES) {
    sum += Math.sin(2 * Math.PI * (timeSec / w.period + x / (width * w.wavelength)));
  }
  return (amp * sum) / WAVES.length;
}

/** 壁を超えた瞬間の脈打ちにかける時間（ミリ秒） */
export const PULSE_MS = 500;

/** 脈打ちの途中の壁の線の太さ。1.5px→3px→1.5px */
export function pulseWidth(elapsedMs: number): number {
  const p = Math.min(1, Math.max(0, elapsedMs / PULSE_MS));
  return 1.5 + 1.5 * Math.sin(Math.PI * ease(p));
}

/** 2つの `#RRGGBB` の色を混ぜる（t=0 で a、t=1 で b） */
export function mixColor(a: string, b: string, t: number): string {
  const ca = parseHex(a);
  const cb = parseHex(b);
  const k = Math.min(1, Math.max(0, t));
  const ch = (i: number) => Math.round(ca[i] + (cb[i] - ca[i]) * k);
  return `rgb(${ch(0)}, ${ch(1)}, ${ch(2)})`;
}

function parseHex(hex: string): [number, number, number] {
  const n = parseInt(hex.replace("#", ""), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/** 吸い付く範囲（候補の金額の上下 3%） */
export const SNAP_RATIO = 0.03;

/** 1万円単位に丸める（下限1万円） */
export function roundWall(yen: number): number {
  return Math.max(WALL_STEP, Math.round(yen / WALL_STEP) * WALL_STEP);
}

/** ドラッグを離した金額。いちばん近い候補の上下3%以内ならその候補、それ以外は1万円単位 */
export function snapWall(yen: number, candidates: readonly number[] = WALL_CANDIDATES): number {
  let best: number | null = null;
  for (const c of candidates) {
    if (Math.abs(yen - c) > c * SNAP_RATIO) continue;
    if (best === null || Math.abs(yen - c) < Math.abs(yen - best)) best = c;
  }
  return best ?? roundWall(yen);
}

/**
 * ドラッグ中の壁の金額。startWall から指が dy px（下向きが正）動いたとき。
 * 画面の高さ height が縦軸の 0〜max にあたる。1万円〜max に収める
 */
export function dragWall(startWall: number, dy: number, height: number, max: number): number {
  const yen = startWall - (dy / height) * max;
  return Math.min(max, Math.max(WALL_STEP, yen));
}

/** 時刻の数字を上下ドラッグするとき、何pxで15分動くか */
export const TIME_DRAG_PX = 12;

/** 時刻のドラッグ。上に dy px（下向きが正）動かすと 12px ごとに15分遅くなる */
export function dragTime(start: number, dy: number): number {
  const steps = Math.trunc(-dy / TIME_DRAG_PX);
  let t = start;
  for (let i = 0; i < Math.abs(steps); i++) t = stepTime(t, steps > 0 ? 1 : -1);
  return t;
}

/** 壁の `自分で` の入力を円に直す。`125万` `125` は万円、`1250000` は円。読めなければ null */
export function parseWallInput(text: string): number | null {
  const t = text
    .replace(/[０-９．]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xfee0))
    .replace(/[,，\s円]/g, "");
  const m = /^(\d+(?:\.\d+)?)(万)?$/.exec(t);
  if (!m) return null;
  const n = Number(m[1]);
  const yen = m[2] || n < WALL_STEP ? n * WALL_STEP : n;
  const rounded = Math.round(yen);
  return rounded >= WALL_STEP ? rounded : null;
}

/** canvas の解像度の倍率。devicePixelRatio（最大2）、重いときは 0.5倍 */
export function canvasScale(devicePixelRatio: number, slow: boolean): number {
  const base = Math.min(2, Math.max(1, devicePixelRatio || 1));
  return slow ? base * 0.5 : base;
}

/** 1コマの平均がこれを超えたら重いとみなす（ミリ秒） */
export const SLOW_FRAME_MS = 25;

/** 12か月の累計のばねのずれを、1日ずつの点へ配る。
 *  target は1日ずつの累計（i 番目は i 日目の終わり）、monthEnds は各月末の日の番号（0始まり）、
 *  offsets は各月末の「ばねの位置 − 新しい値」。月の中は前の月末と今の月末のずれを直線でつなぐ */
export function springDaily(
  target: readonly number[],
  monthEnds: readonly number[],
  offsets: readonly number[],
): number[] {
  const out = new Array<number>(target.length);
  let m = 0;
  for (let i = 0; i < target.length; i++) {
    while (m < monthEnds.length - 1 && i > monthEnds[m]) m++;
    const start = m === 0 ? -1 : monthEnds[m - 1];
    const prev = m === 0 ? 0 : offsets[m - 1];
    const t = (i - start) / (monthEnds[m] - start);
    out[i] = target[i] + prev + (offsets[m] - prev) * t;
  }
  return out;
}
