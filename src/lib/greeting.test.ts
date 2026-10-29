import { describe, expect, it } from "vitest";
import { greeting } from "./greeting";

describe("greeting", () => {
  it("名前を入れたあいさつを返す", () => {
    expect(greeting("世界")).toBe("こんにちは、世界");
  });
});
