import { describe, it, expect } from "vitest"
import { computeTurnIndicators } from "./chat-turn-state"

describe("agent tool turn keeps the indicator between steps (live dev 2026-11-12)", () => {
  it("shows typing while the stream is open and tools have run, even with text present", () => {
    const r = computeTurnIndicators({ streamOpen: true, showWorkflowCue: false, phase: "thinking" as any,
      lastMessage: { role: "assistant", content: "我来帮您查看这张图片。", metadata: { toolBlocks: [{ tool_use_id: "t1", name: "read_file" }] } } })
    expect(r.displayTyping).toBe(true)
    expect(r.turnBusy).toBe(true)
  })
  it("plain text streaming (no tools) does not show the extra indicator", () => {
    const r = computeTurnIndicators({ streamOpen: true, showWorkflowCue: false, phase: "thinking" as any,
      lastMessage: { role: "assistant", content: "Hello", metadata: {} } })
    expect(r.displayTyping).toBe(false)
  })
  it("a finished turn shows nothing", () => {
    const r = computeTurnIndicators({ streamOpen: false, showWorkflowCue: false, phase: "thinking" as any,
      lastMessage: { role: "assistant", content: "Done.", metadata: { toolBlocks: [{ tool_use_id: "t1" }] } } })
    expect(r).toEqual({ displayTyping: false, turnBusy: false })
  })
})
