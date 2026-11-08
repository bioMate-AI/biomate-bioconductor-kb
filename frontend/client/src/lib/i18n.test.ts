import { afterEach, describe, expect, it, vi } from "vitest";
import en from "@/locales/en/common.json";
import zh from "@/locales/zh/common.json";
function keys(value: Record<string, unknown>, prefix = ""): string[] {
  return Object.entries(value).flatMap(([key, item]) => typeof item === "string" ? [prefix + key] : keys(item as Record<string, unknown>, prefix + key + "."));
}
afterEach(() => { localStorage.clear(); vi.unstubAllGlobals(); vi.resetModules(); });
describe("shared English/Chinese UI", () => {
  it("translates every English bundle key", () => { const translated = new Set(keys(zh)); expect(keys(en).filter(key => !translated.has(key))).toEqual([]); });
  it("uses a saved Chinese choice over an English browser", async () => {
    localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "chinese" }));
    vi.stubGlobal("navigator", { language: "en-US" });
    const i18n = await import("./i18n");
    expect(i18n.detectLocale()).toBe("zh");
    expect(i18n.t("nav.projects")).toBe("项目");
  });
  it("uses a saved English choice over a Chinese browser", async () => {
    localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "english" }));
    vi.stubGlobal("navigator", { language: "zh-CN" });
    expect((await import("./i18n")).detectLocale()).toBe("en");
  });
  it("uses the browser language when no explicit choice exists", async () => {
    vi.stubGlobal("navigator", { language: "zh-CN" });
    expect((await import("./i18n")).detectLocale()).toBe("zh");
  });
  it("falls back to English for an untranslated browser language", async () => {
    vi.stubGlobal("navigator", { language: "ja-JP" });
    const i18n = await import("./i18n");
    expect(i18n.detectLocale()).toBe("en");
    expect(i18n.t("nav.projects")).toBe("Projects");
  });
});
