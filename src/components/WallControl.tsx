"use client";

import {
  useEffect,
  useRef,
  useState,
  type CSSProperties,
  type KeyboardEvent,
  type PointerEvent,
} from "react";
import {
  nextCandidate,
  stepWall,
  WALL_CANDIDATES,
  wallLabel,
  wallValueText,
} from "@/lib/income";
import { dragWall, parseWallInput } from "@/lib/motion";

type Props = {
  wall: number;
  /** 縦軸の上限 */
  max: number;
  yearTotal: number;
  /** PC の幅か（PC は候補が常に出る） */
  wide: boolean;
  onChange: (wall: number) => void;
  /** ドラッグ中の金額（円、丸める前）と、ドラッグを始めたときの縦軸の上限 */
  onDrag: (yen: number, max: number) => void;
  /** ドラッグを離したとき */
  onDragEnd: () => void;
};

/** これだけ動いたらドラッグとみなす（px） */
const DRAG_START_PX = 3;
/** 縦軸より上にはみ出す名札を並べる間隔（px） */
const PINNED_GAP_PX = 24;

/**
 * その金額の位置（上端からの割合）。縦軸の上限は面が `--max` に書くので、
 * 上限がばねで伸び縮みする間も名札が面と一緒に動く
 */
const topOf = (yen: number): CSSProperties => ({
  top: `calc(100% * (1 - ${yen} / var(--max)))`,
});

/** 壁の線（ドラッグ・キーボードで動かす slider）と、右端の名札・候補 */
export function WallControl({ wall, max, yearTotal, wide, onChange, onDrag, onDragEnd }: Props) {
  const [open, setOpen] = useState(false);
  const [typing, setTyping] = useState(false);
  const showCandidates = wide || open;
  const drag = useRef<{ y: number; wall: number; max: number; moved: boolean } | null>(null);

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

  // ドラッグ中は縦軸の上限を止めて、線が指に遅れず付いてくるようにする
  const onPointerDown = (e: PointerEvent<HTMLDivElement>) => {
    if (e.button !== 0) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    drag.current = { y: e.clientY, wall, max, moved: false };
  };

  const onPointerMove = (e: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d) return;
    const dy = e.clientY - d.y;
    if (!d.moved && Math.abs(dy) < DRAG_START_PX) return;
    d.moved = true;
    onDrag(dragWall(d.wall, dy, window.innerHeight, d.max), d.max);
  };

  const endDrag = () => {
    const d = drag.current;
    drag.current = null;
    if (d?.moved) onDragEnd();
  };

  // 縦軸より上にはみ出す候補は、上端から順に並べる
  const above = WALL_CANDIDATES.filter((c) => c > max && c !== wall).sort((a, b) => b - a);
  const pinnedTop = (k: number): CSSProperties => ({
    top: `calc(var(--tag-top) + ${k * PINNED_GAP_PX}px)`,
  });

  // `自分で` はいちばん小さい候補のすぐ下に置く
  const lowest = WALL_CANDIDATES[0];
  const customStyle: CSSProperties =
    lowest > max
      ? pinnedTop(above.length)
      : { top: `calc(100% * (1 - ${lowest} / var(--max)) + ${PINNED_GAP_PX}px)` };

  const choose = (next: number) => {
    onChange(next);
    setOpen(false);
    setTyping(false);
  };

  return (
    <>
      <div className="wall-grab-layer">
        <div
          className="wall-slider"
          role="slider"
          tabIndex={0}
          aria-orientation="vertical"
          aria-valuemin={10_000}
          aria-valuemax={Math.max(wall, Math.ceil(max / 10_000) * 10_000)}
          aria-valuenow={wall}
          aria-valuetext={wallValueText(wall, yearTotal)}
          onKeyDown={onKeyDown}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={endDrag}
          onPointerCancel={endDrag}
        />
      </div>

      <div className="wall-layer">
        <button
          type="button"
          className="wall-tag selected"
          aria-expanded={wide ? undefined : open}
          onClick={() => setOpen((v) => !v)}
        >
          {wallLabel(wall)}
          <span className="wall-tag-pointer" aria-hidden="true" />
        </button>

        {showCandidates &&
          WALL_CANDIDATES.filter((c) => c !== wall).map((c) => {
            const k = above.indexOf(c);
            return (
              <button
                key={c}
                type="button"
                className={k >= 0 ? "wall-tag candidate pinned" : "wall-tag candidate"}
                style={k >= 0 ? pinnedTop(k) : topOf(c)}
                onClick={() => choose(c)}
              >
                {wallLabel(c)}
              </button>
            );
          })}

        {showCandidates &&
          (typing ? (
            <CustomWallInput
              style={customStyle}
              pinned={lowest > max}
              onCommit={choose}
              onCancel={() => setTyping(false)}
            />
          ) : (
            <button
              type="button"
              className={lowest > max ? "wall-tag candidate pinned" : "wall-tag candidate"}
              style={customStyle}
              onClick={() => setTyping(true)}
            >
              自分で
            </button>
          ))}
      </div>
    </>
  );
}

type CustomProps = {
  style: CSSProperties;
  pinned: boolean;
  onCommit: (wall: number) => void;
  onCancel: () => void;
};

/** `自分で`：名札の場所でその場で金額を打ち込む。Enter かフォーカスが外れたら決まる */
function CustomWallInput({ style, pinned, onCommit, onCancel }: CustomProps) {
  const [draft, setDraft] = useState("");
  const ref = useRef<HTMLInputElement>(null);
  const done = useRef(false);

  useEffect(() => {
    ref.current?.focus();
  }, []);

  const cancel = () => {
    done.current = true;
    onCancel();
  };

  const commit = () => {
    if (done.current) return;
    done.current = true;
    const next = parseWallInput(draft);
    if (next === null) onCancel();
    else onCommit(next);
  };

  return (
    <input
      ref={ref}
      className={pinned ? "wall-tag candidate pinned wall-custom" : "wall-tag candidate wall-custom"}
      style={style}
      type="text"
      inputMode="numeric"
      autoComplete="off"
      aria-label="自分で"
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => {
        if (e.key === "Enter") commit();
        else if (e.key === "Escape") cancel();
      }}
    />
  );
}
