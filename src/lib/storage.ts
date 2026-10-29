import { DEFAULT_WALL, isValidShift, parseDateKey, type Shift, type Shifts } from "./income";

/** `localStorage` に保存する中身 */
export type SavedState = {
  wage: number | null;
  wall: number;
  shifts: Shifts;
  /** 直前に入れたシフト（`前と同じ` で使う） */
  last: Shift | null;
};

export const STORAGE_KEY = "wall-income-tracker:v1";

export const INITIAL_STATE: SavedState = {
  wage: null,
  wall: DEFAULT_WALL,
  shifts: {},
  last: null,
};

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

function toShift(v: unknown): Shift | null {
  if (!isRecord(v) || typeof v.start !== "number" || typeof v.end !== "number") return null;
  const shift = { start: v.start, end: v.end };
  return isValidShift(shift) ? shift : null;
}

/** 保存した文字列を読む。壊れた所は初期値に戻す */
export function parseSaved(text: string | null): SavedState {
  if (!text) return INITIAL_STATE;
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    return INITIAL_STATE;
  }
  if (!isRecord(data)) return INITIAL_STATE;

  const wage = typeof data.wage === "number" && data.wage > 0 ? data.wage : null;
  const wall = typeof data.wall === "number" && data.wall > 0 ? data.wall : DEFAULT_WALL;
  const shifts: Shifts = {};
  if (isRecord(data.shifts)) {
    for (const [key, value] of Object.entries(data.shifts)) {
      const shift = toShift(value);
      if (parseDateKey(key) && shift) shifts[key] = shift;
    }
  }
  return { wage, wall, shifts, last: toShift(data.last) };
}

export function serializeState(state: SavedState): string {
  return JSON.stringify(state);
}

/** 読み込み。`localStorage` が使えなければ初期値 */
export function loadState(): SavedState {
  try {
    return parseSaved(window.localStorage.getItem(STORAGE_KEY));
  } catch {
    return INITIAL_STATE;
  }
}

/** 書き込み。できなければ false */
export function saveState(state: SavedState): boolean {
  try {
    window.localStorage.setItem(STORAGE_KEY, serializeState(state));
    return true;
  } catch {
    return false;
  }
}
