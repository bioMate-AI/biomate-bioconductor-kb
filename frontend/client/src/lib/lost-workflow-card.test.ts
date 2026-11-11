/**
 * §4.1 "workflow card lost in the browser" (docs/20261110_COLDSTART_EXAMPLES_LIVE_AUDIT.md).
 *
 * Measured on dev 2026-11-11: a workflow turn streams its full summary text at
 * ~10 s and the card (`workflow_ready` + `final`) at ~72 s. Two client defects
 * turned that gap into a lost card:
 *   1. the turn looked finished as soon as text existed (no typing cue, no
 *      Stop, soft-queue off), so people left before the card arrived;
 *   2. a reload rebuilt messages only from the browser-written `metadata`, so
 *      the server's own completed copy (`finalPayload`) never produced a card.
 */
import { describe, it, expect } from "vitest"
import { computeTurnIndicators, signalsPendingWorkflow } from "./chat-turn-state"
import { buildAssistantMessageFromFinal } from "./assistant-message-from-final"
import { restoreServerFinal } from "./chat-history"

// Trimmed from a real dev `final` event (metaboanalystr, 2026-11-11).
const FINAL = {
  response: "**Metaboanalystr Statistical** — Comprehensive metabolomic profiling …\n\n- **Input:** human_cachexia",
  state: "workflow_ready",
  suggestions: ["Run it", "Show details"],
  workflow: {
    success: true,
    workflow_type: "nextflow",
    nextflow_path: "nextflow_nfcore/subworkflows/bioconductor/metaboanalystr/main.nf",
    source: "template_reuse",
    confidence: 0.9,
    workflow_ga: {
      name: "metaboanalystr_statistical",
      nextflow_path: "nextflow_nfcore/subworkflows/bioconductor/metaboanalystr/main.nf",
      steps: {
        "0": { id: "0", name: "Initialise mSet + read peak-intensity table", tool_id: "INITIALISE_MSET" },
        "1": { id: "1", name: "Normalise", tool_id: "NORMALISE" },
      },
    },
  },
  prerequisitesValidation: { fulfilled: false, canRun: true },
  metadata: { intentType: "workflow_generation", sources: { workflowGenerated: true } },
}

describe("turn state while the card is still on its way", () => {
  // State between the text delta (~10 s) and `final` (~72 s): stream open, the
  // placeholder holds the full summary, and its earlier progress line
  // ("Matched a workflow") is still in metadata but no longer rendered.
  const midTurn = {
    streamOpen: true,
    showWorkflowCue: false,
    lastMessage: { role: "assistant", content: FINAL.response, metadata: { progressStatus: "Matched a workflow" } },
  }

  it("server 'matched' progress marks the workflow phase", () => {
    expect(signalsPendingWorkflow("progress", { stage: "matched", detail: "metaboanalystr" })).toBe(true)
    expect(signalsPendingWorkflow("progress", { stage: "plan" })).toBe(false)
    expect(signalsPendingWorkflow("delta", { stage: "matched" })).toBe(false)
  })

  it("keeps the turn busy and shows the workflow cue after the text has streamed", () => {
    const r = computeTurnIndicators({ ...midTurn, phase: "workflow" })
    expect(r.turnBusy).toBe(true)
    expect(r.displayTyping).toBe(true)
  })

  it("keeps Stop/queue on for any open stream, even a text-only one", () => {
    const r = computeTurnIndicators({ ...midTurn, phase: "thinking" })
    expect(r.turnBusy).toBe(true)
    expect(r.displayTyping).toBe(false) // text is streaming; no extra loader
  })

  it("does not double up with the visible progress line before any text", () => {
    const r = computeTurnIndicators({
      streamOpen: true, showWorkflowCue: false, phase: "workflow",
      lastMessage: { role: "assistant", content: "", metadata: { progressStatus: "Matched a workflow" } },
    })
    expect(r.displayTyping).toBe(false)
    expect(r.turnBusy).toBe(true)
  })

  it("is idle once the stream closes", () => {
    expect(computeTurnIndicators({ ...midTurn, streamOpen: false, phase: "thinking" })).toEqual({ displayTyping: false, turnBusy: false })
  })
})

describe("reload rebuilds the card from the server's completed copy", () => {
  it("builder yields a workflow card from the real final payload", () => {
    const { message, workflowSuccess, stepsArray } = buildAssistantMessageFromFinal(FINAL, "assistant-stream-1")
    expect(workflowSuccess).toBe(true)
    expect(message.metadata.type).toBe("workflow")
    expect(message.metadata.workflow?.name).toBe("metaboanalystr_statistical")
    expect(stepsArray).toHaveLength(2)
  })

  it("stored server row with finalPayload and no metadata gets the card back", () => {
    const stored = { message_id: "assistant-stream-1", role: "assistant", content: FINAL.response, partial: false, finalPayload: FINAL }
    const restored = restoreServerFinal({ id: stored.message_id, role: "assistant", content: stored.content } as any, stored)
    expect(restored.metadata?.type).toBe("workflow")
    expect(restored.metadata?.workflow?.nextflow_path).toBe(FINAL.workflow.nextflow_path)
    expect(restored.content).toBe(FINAL.response)
  })

  it("browser-written metadata wins; text-only partial rows stay text-only", () => {
    const own = { id: "a", role: "assistant", content: "x", metadata: { type: "workflow", workflow: { name: "mine" } } }
    expect(restoreServerFinal(own as any, { role: "assistant", finalPayload: FINAL })).toBe(own)
    const partial = { id: "b", role: "assistant", content: "x" }
    expect(restoreServerFinal(partial as any, { role: "assistant", partial: true })).toBe(partial)
  })
})
