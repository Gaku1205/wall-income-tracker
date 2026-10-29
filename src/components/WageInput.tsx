"use client";

import { useState } from "react";
import { formatYen, parseWage } from "@/lib/income";

type Props = {
  wage: number | null;
  /** 呼び名 `時給` を前に付けるか（スマホ） */
  label: boolean;
  onChange: (wage: number | null) => void;
};

/** 時給。数字そのものが入力欄で、Enter かフォーカスが外れたときに決まる */
export function WageInput({ wage, label, onChange }: Props) {
  const [draft, setDraft] = useState<string | null>(null);
  const value = draft ?? (wage === null ? "" : formatYen(wage));

  const commit = () => {
    if (draft === null) return;
    const next = parseWage(draft);
    setDraft(null);
    if (next !== wage) onChange(next);
  };

  return (
    <span className="wage">
      {label && <span className="wage-label">時給</span>}
      <input
        className="wage-input amount"
        type="text"
        inputMode="numeric"
        autoComplete="off"
        aria-label="時給"
        placeholder="—"
        value={value}
        style={{ width: `${Math.max(1.2, value.length * 0.62)}em` }}
        onFocus={() => setDraft(wage === null ? "" : String(wage))}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === "Enter") e.currentTarget.blur();
        }}
      />
      {wage !== null && draft === null && <span className="unit">円</span>}
    </span>
  );
}
