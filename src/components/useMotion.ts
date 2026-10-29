import { useLayoutEffect, useRef, type RefObject } from "react";
import { isAtRest, stepSpring, type SpringState } from "@/lib/motion";
import { useMediaQuery } from "./useClient";

/** prefers-reduced-motion: reduce か */
export function useReducedMotion(): boolean {
  return useMediaQuery("(prefers-reduced-motion: reduce)");
}

/** prefers-reduced-motion のときの、0.12秒の不透明度の切り替え */
export function fadeIn(el: HTMLElement): void {
  el.animate?.([{ opacity: 0 }, {}], { duration: 120, easing: "cubic-bezier(.2, .8, .2, 1)" });
}

/**
 * target が変わったら、ばねで新しい値へ動かし、毎コマ apply で要素に書く。
 * 最初の1回と reduced のときは動かさずに書く（reduced では不透明度だけ切り替える）。
 * apply はモジュールの外側で決めた変わらない関数を渡す
 */
export function useSpringStyle(
  ref: RefObject<HTMLElement | null>,
  target: number,
  reduced: boolean,
  apply: (el: HTMLElement, value: number) => void,
  precision: number,
  delayMs = 0,
): void {
  const state = useRef<SpringState | null>(null);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const prev = state.current;
    if (prev === null || reduced) {
      state.current = { x: target, v: 0 };
      apply(el, target);
      if (prev !== null && prev.x !== target) fadeIn(el);
      return;
    }
    if (prev.x === target && prev.v === 0) return;

    const startAt = performance.now() + delayMs;
    let last = 0;
    let raf = 0;
    const tick = (now: number) => {
      if (now < startAt) {
        raf = requestAnimationFrame(tick);
        return;
      }
      const dt = last === 0 ? 1 / 60 : (now - last) / 1000;
      last = now;
      const next = stepSpring(state.current ?? { x: target, v: 0 }, target, dt);
      if (isAtRest(next, target, precision)) {
        state.current = { x: target, v: 0 };
        apply(el, target);
        return;
      }
      state.current = next;
      apply(el, next.x);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [ref, target, reduced, apply, precision, delayMs]);
}
