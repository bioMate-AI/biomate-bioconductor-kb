/** Audit round 9: zh group_nested put spaces around the interpolated column names
 *  ("无法区分 批次 与 分组 的效应"); the names are quoted like the first half of the sentence. */
import { describe, it, expect, vi, afterEach } from "vitest"

afterEach(() => { localStorage.clear(); vi.resetModules() })

describe("zh group_nested", () => {
  it("quotes the names and adds no spaces around Chinese names", async () => {
    localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "chinese" }))
    const { findingText } = await import("@/components/data-perception")
    const text = findingText({ section: "leakage", code: "group_nested", level: "watch", params: { column: "批次", label: "分组" } })
    expect(text).toContain("无法区分“批次”与“分组”的效应")
    expect(text).not.toMatch(/ 批次 | 分组 /)
  })
})
