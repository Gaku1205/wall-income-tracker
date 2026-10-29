import { describe, expect, it } from "vitest";
import { INITIAL_STATE, parseSaved, serializeState, type SavedState } from "./storage";

describe("保存した中身を読む", () => {
  it("書いた物をそのまま読める", () => {
    const state: SavedState = {
      wage: 1150,
      wall: 1_060_000,
      shifts: { "2026-10-14": { start: 600, end: 900 } },
      last: { start: 600, end: 900 },
    };
    expect(parseSaved(serializeState(state))).toEqual(state);
  });
  it("無い・壊れているときは初期値（壁130万・時給空）", () => {
    expect(parseSaved(null)).toEqual(INITIAL_STATE);
    expect(parseSaved("{")).toEqual(INITIAL_STATE);
    expect(INITIAL_STATE.wall).toBe(1_300_000);
    expect(INITIAL_STATE.wage).toBeNull();
  });
  it("おかしなシフトは捨てる", () => {
    const s = parseSaved(
      JSON.stringify({
        wage: -1,
        wall: "x",
        shifts: { "2026-10-14": { start: 900, end: 600 }, bad: { start: 0, end: 60 } },
      }),
    );
    expect(s).toEqual(INITIAL_STATE);
  });
});
