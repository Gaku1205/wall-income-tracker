import { useSyncExternalStore } from "react";

const noopSubscribe = () => () => {};

/** ブラウザで描いているか（サーバーの描画では false） */
export function useIsClient(): boolean {
  return useSyncExternalStore(
    noopSubscribe,
    () => true,
    () => false,
  );
}

/** メディアクエリに合っているか */
export function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const list = window.matchMedia(query);
      list.addEventListener("change", onChange);
      return () => list.removeEventListener("change", onChange);
    },
    () => window.matchMedia(query).matches,
    () => false,
  );
}

/** PC の幅（1024px〜）か */
export function useIsWide(): boolean {
  return useMediaQuery("(min-width: 1024px)");
}
