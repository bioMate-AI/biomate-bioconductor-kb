/** English UI: every chat surface Track D touched renders in English only — no CJK, no missing key. */
import { describe, expect, it, vi } from "vitest"
vi.mock("3dmol", () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))
vi.mock("@/lib/i18n", async () => {
  const { strictI18n } = await import("./i18n-strict-mock")
  const en = (await import("@/locales/en/common.json")).default
  return strictI18n(en as any, "en")
})
vi.mock("@/lib/api", () => ({ api: { request: vi.fn(async () => ({ found: true, openAccess: false, fullTextStatus: "not_open_access", sections: [], abstract: null, links: { publisher: "https://doi.org/10.1/x", europepmc: null } })) } }))
import { renderChatSurfaces } from "./chat-surfaces.harness"

describe("chat surfaces — en locale", () => {
  it("contain no Chinese characters and no missing keys", async () => {
    const text = await renderChatSurfaces("The answer, in English.", "EPAR approvals by year")
    expect(text).not.toMatch(/⟦MISSING:[^⟧]+⟧/)
    const cjk = text.match(/[^\n]*[㐀-鿿　-〿＀-￯][^\n]*/g) || []
    expect(cjk).toEqual([])
    // Spot-check the surfaces actually rendered.
    for (const s of ["1 sources", "Searched · 4 of 24 kept", "Read", "Running", "Open", "New Chat", "What went wrong?", "What are you trying to do?"]) {
      expect(text).toContain(s)
    }
  }, 60_000)
})
