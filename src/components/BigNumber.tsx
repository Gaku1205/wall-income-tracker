import { formatYen } from "@/lib/income";

/** 段1の数字。1文字ずつ幅を固定して、数字が変わっても幅が揺れないようにする */
export function BigNumber({ value }: { value: number }) {
  const text = formatYen(value);
  return (
    <span className="big">
      <span className="sr-only">{text}</span>
      {Array.from(text).map((ch, i) => (
        <span key={i} className={ch === "," ? "big-ch comma" : "big-ch"} aria-hidden="true">
          {ch}
        </span>
      ))}
    </span>
  );
}
