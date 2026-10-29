"use client";

import { useCallback, useEffect, useRef, useState } from "react";
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
import { loadState, saveState, type SavedState } from "@/lib/storage";
import { BigNumber } from "./BigNumber";
import { DayRow } from "./DayRow";
import { Surface } from "./Surface";
import { TimeEditor } from "./TimeEditor";
import { useIsClient, useIsWide } from "./useClient";
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

  const { wage, wall, shifts } = state;
  const thisMonth = monthIncome(shifts, wage, year, month);
  const thisYear = yearIncome(shifts, wage, year);
  const gap = wallGap(thisYear, wall);
  const cumulative = cumulativeByDay(shifts, wage, year);
  const max = axisMax(wall, thisYear);
  const hasShift = Object.keys(shifts).length > 0;

  const setWall = (next: number) => update((s) => ({ ...s, wall: next }));
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
    <>
      <Surface
        cumulative={cumulative}
        todayIndex={todayIndex}
        openIndex={openDay === null ? null : dayOfYear(year, month, openDay)}
        wall={wall}
        max={max}
      />

      <WallControl wall={wall} max={max} yearTotal={thisYear} wide={isWide} onChange={setWall} />

      <section className="numbers glass">
        <p className={gap.over ? "lead over" : "lead"}>{gap.over ? "超過" : "あと"}</p>
        <p className={gap.over ? "remain over" : "remain"}>
          <BigNumber value={gap.amount} />
          <span className="remain-unit">円</span>
        </p>
        <dl className="rows">
          <div className="row">
            <dt>今月</dt>
            <dd>
              <Amount value={yen(thisMonth)} />
            </dd>
          </div>
          <div className="row">
            <dt>今年</dt>
            <dd>
              <Amount value={yen(thisYear)} />
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
    </>
  );
}

/** 段2の金額。null なら `—` */
function Amount({ value }: { value: number | null }) {
  if (value === null) return <span className="amount">—</span>;
  return (
    <span className="amount">
      {formatYen(value)}
      <span className="unit">円</span>
    </span>
  );
}
