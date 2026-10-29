/** 1日のシフト。時刻はその日の0時からの分 */
export type Shift = { start: number; end: number };

/** 日付（`YYYY-MM-DD`）ごとのシフト。1日に1つ */
export type Shifts = Record<string, Shift>;

/** 壁の候補（円）。小さい順 */
export const WALL_CANDIDATES: readonly number[] = [
  1_060_000, 1_230_000, 1_300_000, 1_500_000, 1_600_000,
];

export const DEFAULT_WALL = 1_300_000;

/** 壁の線を矢印キーで動かす幅（円） */
export const WALL_STEP = 10_000;

/** `前と同じ` で直前のシフトが無いときに入れる時刻 */
export const DEFAULT_SHIFT: Shift = { start: 10 * 60, end: 15 * 60 };

const pad2 = (n: number): string => String(n).padStart(2, "0");

/** 年・月（1〜12）・日から `YYYY-MM-DD` を作る */
export function dateKey(year: number, month: number, day: number): string {
  return `${year}-${pad2(month)}-${pad2(day)}`;
}

/** `YYYY-MM-DD` を年・月・日に分ける。形が違えば null */
export function parseDateKey(
  key: string,
): { year: number; month: number; day: number } | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key);
  if (!m) return null;
  return { year: Number(m[1]), month: Number(m[2]), day: Number(m[3]) };
}

/** その月の日数（month は 1〜12） */
export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** その年の日数 */
export function daysInYear(year: number): number {
  return (Date.UTC(year + 1, 0, 1) - Date.UTC(year, 0, 1)) / 86_400_000;
}

/** 1月1日を0とした、その年の何日目か */
export function dayOfYear(year: number, month: number, day: number): number {
  return (Date.UTC(year, month - 1, day) - Date.UTC(year, 0, 1)) / 86_400_000;
}

/** 開始・終了が正しいシフトか（同じ日の中で、終了が開始より後） */
export function isValidShift(shift: Shift): boolean {
  return (
    Number.isInteger(shift.start) &&
    Number.isInteger(shift.end) &&
    shift.start >= 0 &&
    shift.end <= 24 * 60 &&
    shift.end > shift.start
  );
}

/** 働く時間（分）。正しくないシフトは0 */
export function shiftMinutes(shift: Shift): number {
  return isValidShift(shift) ? shift.end - shift.start : 0;
}

/** 1日の収入（円）。時給が空なら0 */
export function shiftIncome(shift: Shift, wage: number | null): number {
  if (wage === null || wage <= 0) return 0;
  return Math.round((shiftMinutes(shift) / 60) * wage);
}

/** 今月の収入（month は 1〜12） */
export function monthIncome(
  shifts: Shifts,
  wage: number | null,
  year: number,
  month: number,
): number {
  let total = 0;
  for (const [key, shift] of Object.entries(shifts)) {
    const d = parseDateKey(key);
    if (d && d.year === year && d.month === month) total += shiftIncome(shift, wage);
  }
  return total;
}

/** 今年の収入（1月1日〜12月31日の入力済みのシフトの合計） */
export function yearIncome(shifts: Shifts, wage: number | null, year: number): number {
  let total = 0;
  for (const [key, shift] of Object.entries(shifts)) {
    const d = parseDateKey(key);
    if (d && d.year === year) total += shiftIncome(shift, wage);
  }
  return total;
}

/** 1日ずつの累計（面の描画用）。i 番目は1月1日から i 日目の終わりまでの合計 */
export function cumulativeByDay(
  shifts: Shifts,
  wage: number | null,
  year: number,
): number[] {
  const daily = new Array<number>(daysInYear(year)).fill(0);
  for (const [key, shift] of Object.entries(shifts)) {
    const d = parseDateKey(key);
    if (d && d.year === year) daily[dayOfYear(year, d.month, d.day)] += shiftIncome(shift, wage);
  }
  let sum = 0;
  return daily.map((v) => (sum += v));
}

/** 12か月ぶんの累計。i 番目は (i+1) 月末までの合計 */
export function cumulativeByMonth(
  shifts: Shifts,
  wage: number | null,
  year: number,
): number[] {
  let sum = 0;
  return Array.from({ length: 12 }, (_, i) => (sum += monthIncome(shifts, wage, year, i + 1)));
}

/** 壁までの残り。ちょうど壁なら あと0円、超えたら超過額 */
export function wallGap(income: number, wall: number): { over: boolean; amount: number } {
  return income > wall
    ? { over: true, amount: income - wall }
    : { over: false, amount: wall - income };
}

/** 縦軸の上限：壁×1.25 と 12月末の見込み×1.1 の大きい方 */
export function axisMax(wall: number, yearTotal: number): number {
  return Math.max(wall * 1.25, yearTotal * 1.1);
}

/** 矢印キーで壁を1万円動かす（下限1万円） */
export function stepWall(wall: number, direction: 1 | -1): number {
  return Math.max(WALL_STEP, wall + direction * WALL_STEP);
}

/** PageUp(1)/PageDown(-1) で次の候補へ。無ければそのまま */
export function nextCandidate(wall: number, direction: 1 | -1): number {
  if (direction === 1) return WALL_CANDIDATES.find((c) => c > wall) ?? wall;
  return [...WALL_CANDIDATES].reverse().find((c) => c < wall) ?? wall;
}

/** 金額を3桁区切りに（例：312400 → `312,400`） */
export function formatYen(n: number): string {
  return Math.round(n).toLocaleString("en-US");
}

/** 壁の名札（例：1300000 → `130万`） */
export function wallLabel(wall: number): string {
  const man = wall / 10_000;
  return `${Number.isInteger(man) ? man : man.toFixed(1)}万`;
}

/** 壁の線の `aria-valuetext` */
export function wallValueText(wall: number, yearTotal: number): string {
  const gap = wallGap(yearTotal, wall);
  return `${wallLabel(wall)}円の壁まで ${gap.over ? "超過" : "あと"}${formatYen(gap.amount)}円`;
}

/** 分を `10:00` の形に */
export function formatTime(minutes: number): string {
  return `${pad2(Math.floor(minutes / 60))}:${pad2(minutes % 60)}`;
}

/**
 * 打ち込んだ時刻を分に直す。`1000` `10:00` `10` `930` `9:30` を受け付ける。
 * 0:00〜24:00 の外や読めない物は null
 */
export function parseTime(text: string): number | null {
  const t = text.trim().replace("：", ":");
  let h: number;
  let m: number;
  const colon = /^(\d{1,2}):(\d{1,2})$/.exec(t);
  if (colon) {
    h = Number(colon[1]);
    m = Number(colon[2]);
  } else if (/^\d{1,2}$/.test(t)) {
    h = Number(t);
    m = 0;
  } else if (/^\d{3,4}$/.test(t)) {
    h = Number(t.slice(0, -2));
    m = Number(t.slice(-2));
  } else {
    return null;
  }
  if (m >= 60) return null;
  const total = h * 60 + m;
  return total <= 24 * 60 ? total : null;
}

/** 時刻を15分ずつ動かす（0:00〜24:00 に収める） */
export function stepTime(minutes: number, direction: 1 | -1): number {
  const next = Math.round(minutes / 15) * 15 === minutes
    ? minutes + direction * 15
    : (direction === 1 ? Math.ceil(minutes / 15) : Math.floor(minutes / 15)) * 15;
  return Math.min(24 * 60, Math.max(0, next));
}

/** 時給の入力を数に直す。空・0以下・数字でない物は null */
export function parseWage(text: string): number | null {
  const t = text.replace(/[,，\s円]/g, "").replace(/[０-９]/g, (c) =>
    String.fromCharCode(c.charCodeAt(0) - 0xfee0),
  );
  if (!/^\d+$/.test(t)) return null;
  const n = Number(t);
  return n > 0 ? n : null;
}

/** 日の列のボタンの `aria-label`（例：`10月14日 10:00から15:00`） */
export function dayLabel(month: number, day: number, shift: Shift | undefined): string {
  const date = `${month}月${day}日`;
  return shift ? `${date} ${formatTime(shift.start)}から${formatTime(shift.end)}` : date;
}
