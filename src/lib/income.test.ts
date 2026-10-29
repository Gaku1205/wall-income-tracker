import { describe, expect, it } from "vitest";
import {
  axisMax,
  cumulativeByDay,
  cumulativeByMonth,
  dayLabel,
  daysInMonth,
  formatTime,
  formatYen,
  monthIncome,
  nextCandidate,
  parseTime,
  parseWage,
  shiftIncome,
  shiftMinutes,
  stepTime,
  stepWall,
  wallGap,
  wallLabel,
  wallValueText,
  WALL_CANDIDATES,
  yearIncome,
  type Shifts,
} from "./income";

const h = (hh: number, mm = 0) => hh * 60 + mm;

describe("シフトの時間と収入", () => {
  it("開始から終了までの分を出す", () => {
    expect(shiftMinutes({ start: h(10), end: h(15) })).toBe(300);
  });
  it("終了が開始以前なら0分", () => {
    expect(shiftMinutes({ start: h(15), end: h(15) })).toBe(0);
    expect(shiftMinutes({ start: h(15), end: h(10) })).toBe(0);
  });
  it("時給をかけて円未満を四捨五入する", () => {
    expect(shiftIncome({ start: h(10), end: h(15) }, 1150)).toBe(5750);
    expect(shiftIncome({ start: h(10), end: h(10, 20) }, 1000)).toBe(333);
  });
  it("時給が空なら0円", () => {
    expect(shiftIncome({ start: h(10), end: h(15) }, null)).toBe(0);
  });
});

describe("今月・今年・累計", () => {
  const shifts: Shifts = {
    "2026-01-01": { start: h(10), end: h(15) },
    "2026-10-14": { start: h(10), end: h(15) },
    "2026-10-31": { start: h(9), end: h(17) },
    "2026-12-31": { start: h(10), end: h(12) },
    "2025-10-14": { start: h(10), end: h(15) },
  };

  it("今月は今月のシフトだけ（月末日を含む）", () => {
    expect(monthIncome(shifts, 1000, 2026, 10)).toBe(5000 + 8000);
  });
  it("今年は今年のシフトだけで、過去の年は入れない", () => {
    expect(yearIncome(shifts, 1000, 2026)).toBe(5000 + 5000 + 8000 + 2000);
  });
  it("シフトが0件なら0円", () => {
    expect(monthIncome({}, 1000, 2026, 10)).toBe(0);
    expect(yearIncome({}, 1000, 2026)).toBe(0);
    expect(cumulativeByMonth({}, 1000, 2026)).toEqual(new Array(12).fill(0));
  });
  it("時給が空なら0円", () => {
    expect(yearIncome(shifts, null, 2026)).toBe(0);
    expect(cumulativeByDay(shifts, null, 2026).every((v) => v === 0)).toBe(true);
  });
  it("12か月ぶんの累計", () => {
    const c = cumulativeByMonth(shifts, 1000, 2026);
    expect(c).toHaveLength(12);
    expect(c[0]).toBe(5000);
    expect(c[8]).toBe(5000);
    expect(c[9]).toBe(18000);
    expect(c[11]).toBe(20000);
  });
  it("1日ずつの累計は年の日数ぶんで、最後が今年の合計", () => {
    const c = cumulativeByDay(shifts, 1000, 2026);
    expect(c).toHaveLength(365);
    expect(c[0]).toBe(5000);
    expect(c[364]).toBe(20000);
    expect(cumulativeByDay({}, 1000, 2028)).toHaveLength(366);
  });
  it("月の日数", () => {
    expect(daysInMonth(2026, 10)).toBe(31);
    expect(daysInMonth(2026, 2)).toBe(28);
    expect(daysInMonth(2028, 2)).toBe(29);
  });
});

describe("壁までの残り", () => {
  it("壁より下なら あと", () => {
    expect(wallGap(987_600, 1_300_000)).toEqual({ over: false, amount: 312_400 });
  });
  it("ちょうど壁の金額なら あと0円", () => {
    expect(wallGap(1_300_000, 1_300_000)).toEqual({ over: false, amount: 0 });
  });
  it("超えたら超過額", () => {
    expect(wallGap(1_300_001, 1_300_000)).toEqual({ over: true, amount: 1 });
  });
  it("aria-valuetext", () => {
    expect(wallValueText(1_300_000, 987_600)).toBe("130万円の壁まで あと312,400円");
    expect(wallValueText(1_300_000, 1_312_000)).toBe("130万円の壁まで 超過12,000円");
  });
});

describe("壁の候補と動かし方", () => {
  it("候補は106万・123万・130万・150万・160万", () => {
    expect(WALL_CANDIDATES.map(wallLabel)).toEqual(["106万", "123万", "130万", "150万", "160万"]);
  });
  it("矢印で1万円、下限は1万円", () => {
    expect(stepWall(1_300_000, 1)).toBe(1_310_000);
    expect(stepWall(1_300_000, -1)).toBe(1_290_000);
    expect(stepWall(10_000, -1)).toBe(10_000);
  });
  it("PageUp/PageDown で次の候補、端ならそのまま", () => {
    expect(nextCandidate(1_300_000, 1)).toBe(1_500_000);
    expect(nextCandidate(1_300_000, -1)).toBe(1_230_000);
    expect(nextCandidate(1_310_000, -1)).toBe(1_300_000);
    expect(nextCandidate(1_600_000, 1)).toBe(1_600_000);
    expect(nextCandidate(1_060_000, -1)).toBe(1_060_000);
  });
  it("縦軸の上限", () => {
    expect(axisMax(1_300_000, 0)).toBe(1_625_000);
    expect(axisMax(1_300_000, 2_000_000)).toBeCloseTo(2_200_000);
  });
});

describe("表示と入力", () => {
  it("金額を3桁区切りに", () => {
    expect(formatYen(312400)).toBe("312,400");
    expect(formatYen(0)).toBe("0");
  });
  it("時刻を打ち込みから読む", () => {
    expect(parseTime("1000")).toBe(h(10));
    expect(parseTime("930")).toBe(h(9, 30));
    expect(parseTime("10")).toBe(h(10));
    expect(parseTime("10:15")).toBe(h(10, 15));
    expect(parseTime("24:00")).toBe(h(24));
    expect(parseTime("24:15")).toBeNull();
    expect(parseTime("1070")).toBeNull();
    expect(parseTime("")).toBeNull();
    expect(parseTime("abc")).toBeNull();
  });
  it("時刻を15分ずつ動かす", () => {
    expect(stepTime(h(10), 1)).toBe(h(10, 15));
    expect(stepTime(h(10, 5), 1)).toBe(h(10, 15));
    expect(stepTime(h(10, 5), -1)).toBe(h(10));
    expect(stepTime(0, -1)).toBe(0);
    expect(stepTime(h(24), 1)).toBe(h(24));
  });
  it("時刻の形", () => {
    expect(formatTime(h(9, 5))).toBe("09:05");
  });
  it("時給を読む。空・0・数字でない物は空", () => {
    expect(parseWage("1150")).toBe(1150);
    expect(parseWage("1,150")).toBe(1150);
    expect(parseWage("１１５０")).toBe(1150);
    expect(parseWage("")).toBeNull();
    expect(parseWage("0")).toBeNull();
    expect(parseWage("abc")).toBeNull();
  });
  it("日の列の aria-label", () => {
    expect(dayLabel(10, 14, { start: h(10), end: h(15) })).toBe("10月14日 10:00から15:00");
    expect(dayLabel(10, 31, undefined)).toBe("10月31日");
  });
});
