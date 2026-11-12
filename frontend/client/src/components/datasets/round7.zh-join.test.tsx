/**
 * Audit round 7: the "expected" qualifier was joined to the finding with a space — right in
 * English ("…: gene. Expected with this few rows…"), wrong after a Chinese full stop
 * ("…：gene。 行数这么少时…").
 */
import { describe, it, expect, vi, afterEach } from "vitest"

afterEach(() => { localStorage.clear(); vi.resetModules() })

const F = { section: "signal" as const, code: "constant_columns", level: "info" as const, params: { count: 1, columns: ["gene"], expected: "few_rows" } }

async function lineText(language: string) {
  vi.resetModules()
  localStorage.setItem("biomate-user-settings", JSON.stringify({ language }))
  const React = await import("react")
  const rtl = await import("@testing-library/react")
  const { DataPerception } = await import("@/components/data-perception")
  rtl.render(React.createElement(DataPerception, {
    profile: { shape: { rows: 5, cols: 2 }, quality: "good", notes: [], columns: ["id", "gene"], findings: [F] } as any,
  }))
  const line = rtl.screen.getAllByTestId("perception-finding").find((e) => e.getAttribute("data-code") === "constant_columns")!
  const text = line.textContent ?? ""
  rtl.cleanup()
  return text
}

describe("expected qualifier join", () => {
  it("zh: no space after the full-width full stop", async () => {
    const text = await lineText("chinese")
    expect(text).toContain("gene。行数这么少时属于正常情况")
    expect(text).not.toMatch(/[。：；！？] /)
  })
  it("en: one space between the sentences", async () => {
    expect(await lineText("english")).toContain("gene. Expected with this few rows — not flagged.")
  })
})
