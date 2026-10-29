"use client";

import { useRef } from "react";
import { formatYen } from "@/lib/income";
import { digitDelay } from "@/lib/motion";
import { useSpringStyle } from "./useMotion";

const DIGITS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];

/** 0〜9 の縦の帯を、v 文字ぶん上へずらす（1文字の高さは行の高さ 0.9em） */
const applyRoll = (el: HTMLElement, v: number) => {
  el.style.transform = `translateY(${-v * 0.9}em)`;
};

/**
 * 段1の数字。1文字ずつ幅を固定して、数字が変わっても幅が揺れないようにする。
 * 各桁は縦に転がり、右の桁ほど 20ms ずつ遅れて止まる
 */
export function BigNumber({ value, reduced }: { value: number; reduced: boolean }) {
  const text = formatYen(value);
  const chars = Array.from(text);
  let digitIndex = 0;
  return (
    <span className="big">
      <span className="sr-only">{text}</span>
      {chars.map((ch, i) => {
        // 右から数えた位置で覚えておくと、桁が増えても一の位は一の位のまま転がる
        const key = chars.length - 1 - i;
        if (ch === ",") {
          return (
            <span key={key} className="big-ch comma" aria-hidden="true">
              ,
            </span>
          );
        }
        return (
          <RollDigit key={key} digit={Number(ch)} delay={digitDelay(digitIndex++)} reduced={reduced} />
        );
      })}
    </span>
  );
}

function RollDigit({ digit, delay, reduced }: { digit: number; delay: number; reduced: boolean }) {
  const strip = useRef<HTMLSpanElement>(null);
  useSpringStyle(strip, digit, reduced, applyRoll, 0.002, delay);
  return (
    <span className="big-ch roll" aria-hidden="true">
      {/* 幅とベースラインを決めるための見えない数字 */}
      <span className="roll-ghost">{digit}</span>
      <span className="roll-window">
        <span className="roll-strip" ref={strip}>
          {DIGITS.map((d) => (
            <span key={d}>{d}</span>
          ))}
        </span>
      </span>
    </span>
  );
}
