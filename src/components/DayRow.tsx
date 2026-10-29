"use client";

import { useEffect, useRef, type KeyboardEvent, type ReactNode } from "react";
import { dateKey, dayLabel, daysInMonth, shiftMinutes, type Shifts } from "@/lib/income";
import { useSpringStyle } from "./useMotion";

/** 8時間で板の高さの70% */
const FULL_DAY_MINUTES = 8 * 60;
const FULL_DAY_RATIO = 0.7;

type Props = {
  year: number;
  month: number;
  today: number;
  shifts: Shifts;
  openDay: number | null;
  wide: boolean;
  onOpen: (day: number) => void;
  /** スマホでは時給をこの板の1行目に置く */
  wage: ReactNode;
  /** 板の右端に出す文言 */
  message: ReactNode;
  reduced: boolean;
};

/** 今月の1日〜末日の棒 */
export function DayRow({
  year,
  month,
  today,
  shifts,
  openDay,
  wide,
  onOpen,
  wage,
  message,
  reduced,
}: Props) {
  const days = daysInMonth(year, month);
  const scroller = useRef<HTMLDivElement>(null);
  const buttons = useRef<(HTMLButtonElement | null)[]>([]);
  const focusDay = openDay ?? today;

  // スマホでは開いたとき今日の列を中央に置く
  useEffect(() => {
    if (wide) return;
    const el = scroller.current;
    const btn = buttons.current[today - 1];
    if (!el || !btn) return;
    el.scrollLeft = btn.offsetLeft + btn.offsetWidth / 2 - el.clientWidth / 2;
  }, [wide, today]);

  const onKeyDown = (e: KeyboardEvent<HTMLButtonElement>, day: number) => {
    const next = e.key === "ArrowRight" ? day + 1 : e.key === "ArrowLeft" ? day - 1 : null;
    if (next === null || next < 1 || next > days) return;
    e.preventDefault();
    buttons.current[next - 1]?.focus();
  };

  return (
    <section className="days glass">
      <div className="days-head">
        {!wide && <span className="month">{month}月</span>}
        {wage}
        <span className="days-message">{message}</span>
      </div>
      <div className="days-body">
        {wide && <span className="month">{month}月</span>}
        <div className="days-scroll" ref={scroller}>
          {Array.from({ length: days }, (_, i) => {
            const day = i + 1;
            const shift = shifts[dateKey(year, month, day)];
            const minutes = shift ? shiftMinutes(shift) : 0;
            const ratio = Math.min(1, (minutes / FULL_DAY_MINUTES) * FULL_DAY_RATIO);
            const tense = day <= today ? "past" : "future";
            return (
              <button
                key={day}
                ref={(el) => {
                  buttons.current[i] = el;
                }}
                type="button"
                className={day === openDay ? "day open" : "day"}
                tabIndex={day === focusDay ? 0 : -1}
                aria-label={dayLabel(month, day, shift)}
                aria-current={day === today ? "date" : undefined}
                onClick={() => onOpen(day)}
                onKeyDown={(e) => onKeyDown(e, day)}
              >
                <span className="bar-area">
                  <Bar percent={ratio * 100} tense={tense} reduced={reduced} />
                  {minutes === 0 && <span className="dot" />}
                </span>
                <span className="date">{day}</span>
                <span className={day === today ? "today-mark" : "today-mark none"} />
              </button>
            );
          })}
        </div>
      </div>
    </section>
  );
}

const applyHeight = (el: HTMLElement, v: number) => {
  el.style.height = `${Math.max(0, v)}%`;
};

/** 棒。シフトが入った・消えたとき、前の高さから新しい高さへばねで伸び縮みする */
function Bar({ percent, tense, reduced }: { percent: number; tense: string; reduced: boolean }) {
  const ref = useRef<HTMLSpanElement>(null);
  useSpringStyle(ref, percent, reduced, applyHeight, 0.05);
  return <span ref={ref} className={`bar ${tense}`} />;
}
