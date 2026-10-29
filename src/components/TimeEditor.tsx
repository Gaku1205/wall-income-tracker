"use client";

import { useRef, useState, type KeyboardEvent, type PointerEvent } from "react";
import {
  DEFAULT_SHIFT,
  formatTime,
  isValidShift,
  parseTime,
  stepTime,
  type Shift,
} from "@/lib/income";
import { dragTime } from "@/lib/motion";

/** これだけ動いたらドラッグとみなす（px） */
const DRAG_START_PX = 4;

type Props = {
  month: number;
  day: number;
  shift: Shift | undefined;
  /** 直前に入れたシフト */
  last: Shift | null;
  onSave: (shift: Shift) => void;
  onRemove: () => void;
  /** 終了が開始以前など、保存できない入力のとき */
  onInvalid: () => void;
  onClose: () => void;
};

type Field = "start" | "end";

type Drag = {
  field: Field;
  y: number;
  /** ドラッグを始めたときの時刻（分） */
  start: number;
  /** ドラッグで変えた入力（動かしていなければ null） */
  values: Record<Field, string> | null;
};

/** 時刻の入れ物。日の列の上に出るすりガラスの帯 */
export function TimeEditor({ month, day, shift, last, onSave, onRemove, onInvalid, onClose }: Props) {
  const [text, setText] = useState<Record<Field, string>>({
    start: shift ? formatTime(shift.start) : "",
    end: shift ? formatTime(shift.end) : "",
  });
  const drag = useRef<Drag | null>(null);

  const save = (next: Shift) => {
    setText({ start: formatTime(next.start), end: formatTime(next.end) });
    onSave(next);
  };

  const commit = (values: Record<Field, string>) => {
    if (values.start.trim() === "" || values.end.trim() === "") return;
    const start = parseTime(values.start);
    const end = parseTime(values.end);
    const next = start === null || end === null ? null : { start, end };
    if (!next || !isValidShift(next)) {
      onInvalid();
      return;
    }
    if (next.start !== shift?.start || next.end !== shift?.end) save(next);
    else setText({ start: formatTime(next.start), end: formatTime(next.end) });
  };

  const current = (field: Field): number =>
    parseTime(text[field]) ?? shift?.[field] ?? DEFAULT_SHIFT[field];

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>, field: Field) => {
    if (e.key === "Enter") {
      commit(text);
      return;
    }
    if (e.key !== "ArrowUp" && e.key !== "ArrowDown") return;
    e.preventDefault();
    const values = {
      ...text,
      [field]: formatTime(stepTime(current(field), e.key === "ArrowUp" ? 1 : -1)),
    };
    setText(values);
    commit(values);
  };

  // 数字を上下にドラッグすると 12px ごとに15分。動かさずに離したらその場で打ち込める
  const onPointerDown = (e: PointerEvent<HTMLInputElement>, field: Field) => {
    if (e.button !== 0 || document.activeElement === e.currentTarget) return;
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    drag.current = { field, y: e.clientY, start: current(field), values: null };
  };

  const onPointerMove = (e: PointerEvent<HTMLInputElement>) => {
    const d = drag.current;
    if (!d) return;
    const dy = e.clientY - d.y;
    if (d.values === null && Math.abs(dy) < DRAG_START_PX) return;
    const values = { ...text, [d.field]: formatTime(dragTime(d.start, dy)) };
    d.values = values;
    setText(values);
  };

  const onPointerUp = (e: PointerEvent<HTMLInputElement>) => {
    const d = drag.current;
    drag.current = null;
    if (!d) return;
    if (d.values) {
      commit(d.values);
    } else {
      e.currentTarget.focus();
      e.currentTarget.select();
    }
  };

  const timeInput = (field: Field, label: string) => (
    <input
      className="time-input amount"
      type="text"
      inputMode="numeric"
      autoComplete="off"
      aria-label={label}
      value={text[field]}
      onChange={(e) => setText({ ...text, [field]: e.target.value })}
      onBlur={() => commit(text)}
      onKeyDown={(e) => onKeyDown(e, field)}
      onPointerDown={(e) => onPointerDown(e, field)}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={() => {
        drag.current = null;
      }}
    />
  );

  return (
    <div
      className="editor glass"
      role="group"
      aria-label={`${month}月${day}日`}
      onKeyDown={(e) => {
        if (e.key === "Escape") onClose();
      }}
    >
      <span className="editor-date">
        {month}月{day}日
      </span>
      <span className="editor-times">
        {timeInput("start", "開始")}
        <span className="editor-dash">–</span>
        {timeInput("end", "終了")}
      </span>
      <span className="editor-actions">
        <button type="button" className="text-button" onClick={() => save(last ?? DEFAULT_SHIFT)}>
          前と同じ
        </button>
        <button
          type="button"
          className="text-button danger"
          onClick={() => {
            setText({ start: "", end: "" });
            onRemove();
          }}
        >
          消す
        </button>
        <button type="button" className="text-button" onClick={onClose}>
          閉じる
        </button>
      </span>
    </div>
  );
}
