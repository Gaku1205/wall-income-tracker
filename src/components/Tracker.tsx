"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import {
  axisMax,
  cumulativeByDay,
  dateKey,
  dayOfYear,
  formatYen,
  monthIncome,
  wallGap,
  yearIncome,
  type Shift,
} from "@/lib/income";
import { countUp, COUNT_UP_MS, roundWall, snapWall } from "@/lib/motion";
import { loadState, saveState, type SavedState } from "@/lib/storage";
import { BigNumber } from "./BigNumber";
import { DayRow } from "./DayRow";
import { Surface } from "./Surface";
import { TimeEditor } from "./TimeEditor";
import { useIsClient, useIsWide } from "./useClient";
import { fadeIn, useReducedMotion } from "./useMotion";
import { WageInput } from "./WageInput";
import { WallControl } from "./WallControl";

const MESSAGE_MS = 4000;

/** ページの中身。`localStorage` と今日の日付を使うので、ブラウザでだけ描く */
export function Tracker() {
  const isClient = useIsClient();
  return isClient ? <TrackerBody /> : null;
}

function TrackerBody() {
  const [state, setState] = useState<SavedState>(loadState);
  const [today] = useState(() => new Date());
  const [openDay, setOpenDay] = useState<number | null>(null);
  const [failed, setFailed] = useState(false);
  const failTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isWide = useIsWide();
  const reduced = useReducedMotion();
  /** 壁の線をドラッグ中の金額（丸める前）と、始めたときの縦軸の上限 */
  const [drag, setDrag] = useState<{ yen: number; max: number } | null>(null);
  const layer = useRef<HTMLDivElement>(null);

  const year = today.getFullYear();
  const month = today.getMonth() + 1;
  const todayDate = today.getDate();
  const todayIndex = dayOfYear(year, month, todayDate);

  const showFailure = useCallback(() => {
    setFailed(true);
    if (failTimer.current) clearTimeout(failTimer.current);
    failTimer.current = setTimeout(() => setFailed(false), MESSAGE_MS);
  }, []);

  useEffect(
    () => () => {
      if (failTimer.current) clearTimeout(failTimer.current);
    },
    [],
  );

  const update = useCallback(
    (fn: (prev: SavedState) => SavedState) => {
      const next = fn(state);
      setState(next);
      if (!saveState(next)) showFailure();
    },
    [state, showFailure],
  );

  const { wage, shifts } = state;
  // ドラッグ中は名札と数字を1万円単位で変える
  const wall = drag ? roundWall(drag.yen) : state.wall;
  const thisMonth = monthIncome(shifts, wage, year, month);
  const thisYear = yearIncome(shifts, wage, year);
  const gap = wallGap(thisYear, wall);
  const cumulative = cumulativeByDay(shifts, wage, year);
  const max = drag ? drag.max : axisMax(wall, thisYear);
  const hasShift = Object.keys(shifts).length > 0;

  const setWall = (next: number) => update((s) => ({ ...s, wall: next }));
  const endDrag = () => {
    if (!drag) return;
    setDrag(null);
    setWall(snapWall(drag.yen));
  };
  const setWage = (next: number | null) => update((s) => ({ ...s, wage: next }));

  const putShift = (day: number, shift: Shift) =>
    update((s) => ({
      ...s,
      shifts: { ...s.shifts, [dateKey(year, month, day)]: shift },
      last: shift,
    }));

  const removeShift = (day: number) =>
    update((s) => {
      const rest = { ...s.shifts };
      delete rest[dateKey(year, month, day)];
      return { ...s, shifts: rest };
    });

  const wageInput = <WageInput wage={wage} label={!isWide} onChange={setWage} />;
  const yen = (n: number) => (wage === null ? null : n);

  return (
    <div className="tracker" ref={layer}>
      <Surface
        year={year}
        cumulative={cumulative}
        todayIndex={todayIndex}
        openIndex={openDay === null ? null : dayOfYear(year, month, openDay)}
        wall={drag ? drag.yen : wall}
        dragging={drag !== null}
        max={max}
        reduced={reduced}
        varsTarget={layer}
      />

      <WallControl
        wall={wall}
        max={max}
        yearTotal={thisYear}
        wide={isWide}
        onChange={setWall}
        onDrag={(yen, dragMax) => setDrag({ yen, max: dragMax })}
        onDragEnd={endDrag}
      />

      <section className="numbers glass">
        <p className={gap.over ? "lead over" : "lead"}>{gap.over ? "超過" : "あと"}</p>
        <p className={gap.over ? "remain over" : "remain"}>
          <BigNumber value={gap.amount} reduced={reduced} />
          <span className="remain-unit">円</span>
        </p>
        <dl className="rows">
          <div className="row">
            <dt>今月</dt>
            <dd>
              <Amount value={yen(thisMonth)} reduced={reduced} />
            </dd>
          </div>
          <div className="row">
            <dt>今年</dt>
            <dd>
              <Amount value={yen(thisYear)} reduced={reduced} />
            </dd>
          </div>
          {isWide && (
            <div className="row">
              <dt>時給</dt>
              <dd>{wageInput}</dd>
            </div>
          )}
        </dl>
      </section>

      <div className="bottom">
        {openDay !== null && (
          <TimeEditor
            key={openDay}
            month={month}
            day={openDay}
            shift={shifts[dateKey(year, month, openDay)]}
            last={state.last}
            onSave={(shift) => putShift(openDay, shift)}
            onRemove={() => removeShift(openDay)}
            onInvalid={showFailure}
            onClose={() => setOpenDay(null)}
          />
        )}
        <DayRow
          year={year}
          month={month}
          today={todayDate}
          shifts={shifts}
          openDay={openDay}
          wide={isWide}
          reduced={reduced}
          onOpen={setOpenDay}
          wage={isWide ? null : wageInput}
          message={
            failed ? (
              <span className="message error" role="status">
                保存できませんでした
              </span>
            ) : hasShift ? null : (
              <span className="message">日を押してシフトを入れる</span>
            )
          }
        />
      </div>
    </div>
  );
}

/** 段2の金額。null なら `—` */
function Amount({ value, reduced }: { value: number | null; reduced: boolean }) {
  if (value === null) return <span className="amount">—</span>;
  return (
    <span className="amount">
      <CountUp value={value} reduced={reduced} />
      <span className="unit">円</span>
    </span>
  );
}

/** 数値を前の値から新しい値へ 0.4秒で数え上げる */
function CountUp({ value, reduced }: { value: number; reduced: boolean }) {
  const ref = useRef<HTMLSpanElement>(null);
  const shown = useRef<number | null>(null);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const from = shown.current;
    const show = (v: number) => {
      shown.current = v;
      el.textContent = formatYen(v);
    };
    if (from === null || reduced) {
      show(value);
      if (from !== null && from !== value) fadeIn(el);
      return;
    }
    if (from === value) return;
    const start = performance.now();
    let raf = 0;
    const tick = (now: number) => {
      const elapsed = now - start;
      show(countUp(from, value, elapsed));
      if (elapsed < COUNT_UP_MS) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value, reduced]);

  return <span ref={ref} />;
}
