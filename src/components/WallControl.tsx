"use client";

import { useState, type CSSProperties, type KeyboardEvent } from "react";
import {
  nextCandidate,
  stepWall,
  WALL_CANDIDATES,
  wallLabel,
  wallValueText,
} from "@/lib/income";

type Props = {
  wall: number;
  /** 縦軸の上限 */
  max: number;
  yearTotal: number;
  /** PC の幅か（PC は候補が常に出る） */
  wide: boolean;
  onChange: (wall: number) => void;
};

/** 画面の高さに対する、その金額の位置（上端からの割合） */
const topOf = (yen: number, max: number): CSSProperties => ({
  top: `${(1 - yen / max) * 100}%`,
});

/** 壁の線（キーボードで動かす slider）と、右端の名札・候補 */
export function WallControl({ wall, max, yearTotal, wide, onChange }: Props) {
  const [open, setOpen] = useState(false);
  const showCandidates = wide || open;

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    const next =
      e.key === "ArrowUp"
        ? stepWall(wall, 1)
        : e.key === "ArrowDown"
          ? stepWall(wall, -1)
          : e.key === "PageUp"
            ? nextCandidate(wall, 1)
            : e.key === "PageDown"
              ? nextCandidate(wall, -1)
              : null;
    if (next === null) return;
    e.preventDefault();
    onChange(next);
  };

  // 縦軸より上にはみ出す候補は、上端から順に並べる
  const above = WALL_CANDIDATES.filter((c) => c > max && c !== wall).sort((a, b) => b - a);

  return (
    <div className="wall-layer">
      <div
        className="wall-slider"
        style={topOf(wall, max)}
        role="slider"
        tabIndex={0}
        aria-orientation="vertical"
        aria-valuemin={10_000}
        aria-valuemax={Math.max(wall, Math.ceil(max / 10_000) * 10_000)}
        aria-valuenow={wall}
        aria-valuetext={wallValueText(wall, yearTotal)}
        onKeyDown={onKeyDown}
      />

      <button
        type="button"
        className="wall-tag selected"
        style={topOf(wall, max)}
        aria-expanded={wide ? undefined : open}
        onClick={() => setOpen((v) => !v)}
      >
        {wallLabel(wall)}
        <span className="wall-tag-pointer" aria-hidden="true" />
      </button>

      {showCandidates &&
        WALL_CANDIDATES.filter((c) => c !== wall).map((c) => {
          const k = above.indexOf(c);
          const style: CSSProperties =
            k >= 0 ? { top: `calc(var(--tag-top) + ${k * 24}px)` } : topOf(c, max);
          return (
            <button
              key={c}
              type="button"
              className={k >= 0 ? "wall-tag candidate pinned" : "wall-tag candidate"}
              style={style}
              onClick={() => {
                onChange(c);
                setOpen(false);
              }}
            >
              {wallLabel(c)}
            </button>
          );
        })}
    </div>
  );
}
