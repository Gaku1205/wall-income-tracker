"use client";

import { useState, type KeyboardEvent } from "react";
import {
  DEFAULT_SHIFT,
  formatTime,
  isValidShift,
  parseTime,
  stepTime,
  type Shift,
} from "@/lib/income";

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

/** 時刻の入れ物。日の列の上に出るすりガラスの帯 */
export function TimeEditor({ month, day, shift, last, onSave, onRemove, onInvalid, onClose }: Props) {
  const [text, setText] = useState<Record<Field, string>>({
    start: shift ? formatTime(shift.start) : "",
    end: shift ? formatTime(shift.end) : "",
  });

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

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>, field: Field) => {
    if (e.key === "Enter") {
      commit(text);
      return;
    }
    if (e.key !== "ArrowUp" && e.key !== "ArrowDown") return;
    e.preventDefault();
    const current = parseTime(text[field]) ?? shift?.[field] ?? DEFAULT_SHIFT[field];
    const values = { ...text, [field]: formatTime(stepTime(current, e.key === "ArrowUp" ? 1 : -1)) };
    setText(values);
    commit(values);
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
