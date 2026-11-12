/**
 * §4.1 lost workflow card — server half (docs/20261110_COLDSTART_EXAMPLES_LIVE_AUDIT.md).
 * Dev evidence: 7 of 9 failing sessions were stored `partial: true` with text
 * only, although the server logged `workflowGenerated: true` for the turn —
 * the disconnect-time partial write blocked the completion write.
 */
import { describe, it, expect } from "vitest"
import { createAssistantPersister, type AssistantPersistWrite } from "./chat-stream-persistence"

function harness(writeDelayMs = 0) {
  const state = { content: "", workflowMetadata: null as any, finalPayload: null as any }
  const writes: AssistantPersistWrite[] = []
  const p = createAssistantPersister({
    snapshot: () => ({ ...state }),
    write: async (w) => {
      if (writeDelayMs) await new Promise((r) => setTimeout(r, writeDelayMs))
      writes.push(w)
      return true
    },
  })
  return { state, writes, p }
}

const FINAL = { response: "**Metaboanalystr Statistical** — …", state: "workflow_ready", workflow: { success: true, workflow_ga: { name: "m" } } }

describe("chat-stream assistant persistence ordering", () => {
  it("client disconnects after the text; the card generated afterwards is still stored", async () => {
    const { state, writes, p } = harness()
    state.content = FINAL.response
    await p.persist({ partial: true }) // socket close at ~text+20 s
    state.workflowMetadata = { workflow_name: "Metaboanalystr Statistical" }
    state.finalPayload = FINAL // generation finished server-side
    await p.persist({ partial: false })
    expect(writes.map((w) => w.partial)).toEqual([true, false])
    expect(writes.at(-1)!.finalPayload).toBe(FINAL)
  })

  it("a partial write still in flight cannot land after the final write", async () => {
    const { state, writes, p } = harness(20)
    state.content = "text"
    const partial = p.persist({ partial: true })
    state.finalPayload = FINAL
    await Promise.all([partial, p.persist({ partial: false })])
    expect(writes.map((w) => w.partial)).toEqual([true, false])
  })

  it("socket close after completion does not overwrite the final row", async () => {
    const { state, writes, p } = harness()
    state.content = "text"
    state.finalPayload = FINAL
    await p.persist({ partial: false })
    await p.persist({ partial: true })
    expect(writes).toHaveLength(1)
    expect(writes[0].partial).toBe(false)
  })

  it("never writes an empty message; final is written once", async () => {
    const { state, writes, p } = harness()
    await p.persist({ partial: true })
    expect(writes).toHaveLength(0)
    state.content = "t"
    await p.persist({ partial: false })
    await p.persist({ partial: false })
    expect(writes).toHaveLength(1)
  })
})
