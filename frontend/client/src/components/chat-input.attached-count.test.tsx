/**
 * Regression tests for the "X / 32 attached" indicator in ChatInput.
 *
 * Surface contract (paired with frontend/server/dataset-cap.ts):
 *   - 0 attached → indicator NOT rendered (no noise pre-attach)
 *   - 1-24 attached → muted text
 *   - 25-31 attached → amber tone
 *   - 32+ attached → red tone + at-cap tooltip
 *   - Uses tabular-nums so the count doesn't jitter as digits change
 *   - testid stable for e2e: "chat-input-attached-count"
 */
import React from "react"
import { describe, it, expect, vi } from "vitest"
import { render, screen } from "@testing-library/react"
import { ChatInput } from "./chat-input"

function setup(sessionDatasetCount: number) {
  return render(
    <ChatInput
      onSend={vi.fn()}
      isStreaming={false}
      sessionDatasetCount={sessionDatasetCount}
    />
  )
}

describe("ChatInput — sessionDatasetCount indicator", () => {
  it("does NOT render the indicator when 0 attached", () => {
    setup(0)
    expect(screen.queryByTestId("chat-input-attached-count")).toBeNull()
  })

  it("renders 'N / 32' when 1+ attached", () => {
    setup(5)
    const el = screen.getByTestId("chat-input-attached-count")
    expect(el.textContent).toBe("5 / 32")
  })

  it("uses muted tone under 75% of the cap (≤ 24)", () => {
    setup(24)
    const el = screen.getByTestId("chat-input-attached-count")
    // Muted = the BioMate text-dim variable
    expect((el as HTMLElement).style.color).toContain("--bm-text-dim")
    expect((el as HTMLElement).style.background).toBe("transparent")
  })

  it("uses amber tone at 76–99% of the cap (25–31)", () => {
    setup(28)
    const el = screen.getByTestId("chat-input-attached-count")
    expect((el as HTMLElement).style.color).toContain("0.62 0.18 60")
    expect((el as HTMLElement).style.background).toBe("transparent")
  })

  it("uses red tone + at-cap background at 32 (the cap itself)", () => {
    setup(32)
    const el = screen.getByTestId("chat-input-attached-count")
    expect((el as HTMLElement).style.color).toContain("--bm-err")
    // Background switches to a tinted box only at cap
    expect((el as HTMLElement).style.background).toContain("0.95 0.04 25")
  })

  it("tooltip distinctly different at the cap", () => {
    setup(32)
    const el = screen.getByTestId("chat-input-attached-count")
    const tip = el.getAttribute("title") ?? ""
    expect(tip).toMatch(/At the 32-attachment cap/i)
    expect(tip).toMatch(/Galaxy collection/i)
  })

  it("tooltip names the cap on the calm path too", () => {
    setup(3)
    const el = screen.getByTestId("chat-input-attached-count")
    expect(el.getAttribute("title")).toContain("of 32")
  })

  it("uses tabular-nums so digits don't jitter as the count changes", () => {
    setup(7)
    const el = screen.getByTestId("chat-input-attached-count")
    expect((el as HTMLElement).style.fontVariantNumeric).toBe("tabular-nums")
  })
})

describe("Contract: indicator cap mirrors server cap", () => {
  it("MAX_DATASET_REFS in chat-input.tsx matches dataset-cap.ts", () => {
    const fs = require("fs") as typeof import("fs")
    const path = require("path") as typeof import("path")
    // The client uses its own const because shared/client imports are
    // boundaries we don't want to cross for one number. The test pins
    // the two values together so a refactor on either side trips.
    const clientSrc = fs.readFileSync(
      path.join(__dirname, "chat-input.tsx"), "utf-8"
    )
    const serverSrc = fs.readFileSync(
      path.join(__dirname, "..", "..", "..", "server", "dataset-cap.ts"), "utf-8"
    )
    const clientMatch = clientSrc.match(/const MAX_DATASET_REFS = (\d+)/)
    const serverMatch = serverSrc.match(/MAX_DATASET_REFS = (\d+)/)
    expect(clientMatch?.[1]).toBeDefined()
    expect(serverMatch?.[1]).toBeDefined()
    expect(clientMatch![1]).toBe(serverMatch![1])
  })
})
