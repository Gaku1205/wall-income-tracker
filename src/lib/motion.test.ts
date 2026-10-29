import { describe, expect, it } from "vitest";
import {
  canvasScale,
  countUp,
  cubicBezier,
  digitDelay,
  dragTime,
  dragWall,
  ease,
  isAtRest,
  mixColor,
  parseWallInput,
  pulseWidth,
  roundWall,
  snapWall,
  springDaily,
  stepSpring,
  wobbleAmplitude,
  wobbleOffset,
  type SpringState,
} from "./motion";

const h = (hh: number, mm = 0) => hh * 60 + mm;

/** 1/60 秒ずつ ms ミリ秒ぶん進める */
function run(state: SpringState, target: number, ms: number): SpringState {
  let s = state;
  for (let t = 0; t < ms; t += 1000 / 60) s = stepSpring(s, target, 1 / 60);
  return s;
}

describe("ばね", () => {
  it("新しい値へ向かって動き、やがて止まる", () => {
    const s = run({ x: 0, v: 0 }, 100, 1000);
    expect(s.x).toBeCloseTo(100, 1);
    expect(isAtRest(s, 100, 0.5)).toBe(true);
  });

  it("動き出しは目標より手前にいる", () => {
    const s = stepSpring({ x: 0, v: 0 }, 100, 1 / 60);
    expect(s.x).toBeGreaterThan(0);
    expect(s.x).toBeLessThan(50);
  });

  it("行き過ぎはごく小さい（damping 32）", () => {
    let s: SpringState = { x: 0, v: 0 };
    let peak = 0;
    for (let i = 0; i < 120; i++) {
      s = stepSpring(s, 100, 1 / 60);
      peak = Math.max(peak, s.x);
    }
    expect(peak).toBeGreaterThan(100);
    expect(peak).toBeLessThan(104);
  });

  it("間が大きく空いても一度に飛ばない", () => {
    const s = stepSpring({ x: 0, v: 0 }, 100, 5);
    expect(s.x).toBeLessThan(100);
  });

  it("止まっているときに目標が同じなら動かない", () => {
    expect(stepSpring({ x: 5, v: 0 }, 5, 1 / 60)).toEqual({ x: 5, v: 0 });
  });

  it("動いている間は止まったとみなさない", () => {
    expect(isAtRest({ x: 50, v: 0 }, 100, 0.5)).toBe(false);
    expect(isAtRest({ x: 100, v: 30 }, 100, 0.5)).toBe(false);
  });
});

describe("曲線 cubic-bezier(.2, .8, .2, 1)", () => {
  it("はじめは0、終わりは1", () => {
    expect(ease(0)).toBe(0);
    expect(ease(1)).toBe(1);
  });

  it("前半で速く進み、ずっと増え続ける", () => {
    expect(ease(0.5)).toBeGreaterThan(0.85);
    let prev = 0;
    for (let i = 1; i <= 100; i++) {
      const v = ease(i / 100);
      expect(v).toBeGreaterThanOrEqual(prev);
      prev = v;
    }
  });

  it("linear と同じ形なら時間の割合そのまま", () => {
    const linear = cubicBezier(0, 0, 1, 1);
    expect(linear(0.3)).toBeCloseTo(0.3, 4);
  });
});

describe("数え上げ（段2）", () => {
  it("0.4秒で前の値から新しい値へ", () => {
    expect(countUp(1000, 2000, 0)).toBe(1000);
    expect(countUp(1000, 2000, 400)).toBe(2000);
    expect(countUp(1000, 2000, 1000)).toBe(2000);
    const mid = countUp(1000, 2000, 200);
    expect(mid).toBeGreaterThan(1500);
    expect(mid).toBeLessThan(2000);
  });

  it("減るときも数える", () => {
    expect(countUp(2000, 1000, 400)).toBe(1000);
    expect(countUp(2000, 1000, 100)).toBeLessThan(2000);
  });
});

describe("転がる数字（段1）", () => {
  it("右の桁ほど20msずつ遅れる", () => {
    expect(digitDelay(0)).toBe(0);
    expect(digitDelay(1)).toBe(20);
    expect(digitDelay(5)).toBe(100);
  });
});

describe("見込みの面の揺れ", () => {
  it("今日の位置で振幅0、右端で最大3px", () => {
    expect(wobbleAmplitude(300, 300, 1000)).toBe(0);
    expect(wobbleAmplitude(1000, 300, 1000)).toBe(3);
    expect(wobbleAmplitude(650, 300, 1000)).toBeCloseTo(1.5);
  });

  it("今日より左は揺れない", () => {
    expect(wobbleAmplitude(100, 300, 1000)).toBe(0);
    expect(wobbleOffset(100, 300, 1000, 1.23)).toBe(0);
  });

  it("揺れは振幅を超えない", () => {
    for (let t = 0; t < 20; t += 0.37) {
      for (let x = 300; x <= 1000; x += 50) {
        expect(Math.abs(wobbleOffset(x, 300, 1000, t))).toBeLessThanOrEqual(
          wobbleAmplitude(x, 300, 1000) + 1e-9,
        );
      }
    }
  });

  it("時間がたつと形が変わる", () => {
    expect(wobbleOffset(900, 300, 1000, 0)).not.toBeCloseTo(wobbleOffset(900, 300, 1000, 1), 3);
  });
});

describe("壁を超えた瞬間", () => {
  it("線の太さが 1.5px→3px→1.5px", () => {
    expect(pulseWidth(0)).toBeCloseTo(1.5);
    expect(pulseWidth(500)).toBeCloseTo(1.5);
    const peak = Math.max(...Array.from({ length: 51 }, (_, i) => pulseWidth(i * 10)));
    expect(peak).toBeCloseTo(3, 1);
  });

  it("色が --tide から --over へ移る", () => {
    expect(mixColor("#2B44F0", "#FF2E6E", 0)).toBe("rgb(43, 68, 240)");
    expect(mixColor("#2B44F0", "#FF2E6E", 1)).toBe("rgb(255, 46, 110)");
  });
});

describe("壁のドラッグと吸い付き", () => {
  it("1万円単位に丸める（下限1万円）", () => {
    expect(roundWall(1_234_567)).toBe(1_230_000);
    expect(roundWall(1_235_000)).toBe(1_240_000);
    expect(roundWall(2_000)).toBe(10_000);
  });

  it("候補の上下3%以内なら候補に吸い付く", () => {
    expect(snapWall(1_290_000)).toBe(1_300_000);
    expect(snapWall(1_335_000)).toBe(1_300_000);
    expect(snapWall(1_040_000)).toBe(1_060_000);
  });

  it("3%より離れていれば1万円単位", () => {
    expect(snapWall(1_400_000)).toBe(1_400_000);
    expect(snapWall(1_346_000)).toBe(1_350_000);
    expect(snapWall(500_400)).toBe(500_000);
  });

  it("2つの候補の範囲が重なるときは近い方", () => {
    // 123万の+3%（126.69万）と130万の-3%（126.1万）が重なる
    expect(snapWall(1_263_000)).toBe(1_230_000);
    expect(snapWall(1_266_000)).toBe(1_300_000);
  });

  it("指の動きに合わせて金額が変わる（上に動かすと増える）", () => {
    expect(dragWall(1_300_000, -100, 1000, 1_625_000)).toBeCloseTo(1_462_500);
    expect(dragWall(1_300_000, 100, 1000, 1_625_000)).toBeCloseTo(1_137_500);
  });

  it("1万円〜縦軸の上限に収める", () => {
    expect(dragWall(1_300_000, -5000, 1000, 1_625_000)).toBe(1_625_000);
    expect(dragWall(1_300_000, 5000, 1000, 1_625_000)).toBe(10_000);
  });
});

describe("時刻のドラッグ", () => {
  it("上に12pxごとに15分遅くなる", () => {
    expect(dragTime(h(10), -12)).toBe(h(10, 15));
    expect(dragTime(h(10), -35)).toBe(h(10, 30));
    expect(dragTime(h(10), -48)).toBe(h(11));
  });

  it("下に動かすと早くなる", () => {
    expect(dragTime(h(10), 12)).toBe(h(9, 45));
    expect(dragTime(h(10), 30)).toBe(h(9, 30));
  });

  it("12px未満は変わらない", () => {
    expect(dragTime(h(10), -11)).toBe(h(10));
    expect(dragTime(h(10), 11)).toBe(h(10));
  });

  it("半端な時刻は15分の区切りにそろえてから動く", () => {
    expect(dragTime(h(10, 10), -12)).toBe(h(10, 15));
    expect(dragTime(h(10, 10), 12)).toBe(h(10));
  });

  it("0:00〜24:00 に収める", () => {
    expect(dragTime(h(23, 45), -120)).toBe(h(24));
    expect(dragTime(h(0, 15), 120)).toBe(0);
  });
});

describe("壁の `自分で` の入力", () => {
  it("万円で打った金額を円に直す", () => {
    expect(parseWallInput("125")).toBe(1_250_000);
    expect(parseWallInput("125万")).toBe(1_250_000);
    expect(parseWallInput("103.5")).toBe(1_035_000);
    expect(parseWallInput("１４０")).toBe(1_400_000);
  });

  it("円で打った金額はそのまま", () => {
    expect(parseWallInput("1250000")).toBe(1_250_000);
    expect(parseWallInput("1,234,567円")).toBe(1_234_567);
  });

  it("読めない物・1万円未満は null", () => {
    expect(parseWallInput("")).toBeNull();
    expect(parseWallInput("abc")).toBeNull();
    expect(parseWallInput("0")).toBeNull();
    expect(parseWallInput("0.5")).toBeNull();
  });
});

describe("canvas の解像度", () => {
  it("devicePixelRatio を最大2で使い、重いときは0.5倍", () => {
    expect(canvasScale(1, false)).toBe(1);
    expect(canvasScale(3, false)).toBe(2);
    expect(canvasScale(2, true)).toBe(1);
    expect(canvasScale(1, true)).toBe(0.5);
  });
});

describe("12か月の点のばねを1日ずつに配る", () => {
  const target = [0, 0, 10, 10, 20, 30];
  const monthEnds = [2, 5];

  it("ずれが無ければ新しい値そのまま", () => {
    expect(springDaily(target, monthEnds, [0, 0])).toEqual(target);
  });

  it("月末の点はばねの位置になり、月の中は直線でつなぐ", () => {
    const out = springDaily(target, monthEnds, [-6, -9]);
    expect(out[2]).toBe(4);
    expect(out[5]).toBe(21);
    expect(out[0]).toBeCloseTo(0 - 2);
    expect(out[3]).toBeCloseTo(10 - 7);
  });
});
