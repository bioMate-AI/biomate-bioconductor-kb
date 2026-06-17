/**
 * Integration test for the rationale_id flow through chat-message → WhyAnchor.
 *
 * Covers L week-3 + Phase 2 wiring end-to-end at the React layer:
 *   - a workflow_progress message carrying technical.rationale_id renders
 *     the WhyAnchor with that id
 *   - clicking the anchor triggers the fetch
 *   - popover renders the rationale text + DOI link
 *
 * RTL + jsdom; no real backend — fetch is mocked.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"
import userEvent from "@testing-library/user-event"

// ChatMessage transitively imports the 3Dmol structure-viewer module,
// which calls window.URL.createObjectURL at module load. jsdom doesn't
// ship that API, so we stub the whole 3Dmol module before chat-message
// is imported.
vi.mock("3dmol", () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))

import { ChatMessage, type Message } from "./chat-message"

const FAKE_RATIONALE = {
  rationale_id: "bulk_rnaseq_consensus_de_bioc:B",
  rationale_text:
    "After normalisation, counts + metadata + size factors fold into a single DESeqDataSet.",
  citation: { doi: "10.1186/s13059-014-0550-8", title: "Love MI et al. 2014" },
  qc_gate_name: "deseq2_negative_binomial_fit",
  last_curated_at: 1718360000,
}

function makeProgressMessage(extras: Record<string, any> = {}): Message {
  return {
    id: "msg-test-1",
    role: "assistant",
    content: "Phase B · Normalise — counts + metadata + size factors fold into a single DESeqDataSet.",
    timestamp: new Date(),
    metadata: {
      type: "workflow_progress",
      kind: "workflow.phase_started",
      ts: Date.now() / 1000,
      technical: { phase_name: "Normalise", ...extras },
    },
  } as Message
}

describe("chat-message → <WhyAnchor> rationale_id flow", () => {
  beforeEach(() => {
    // jsdom doesn't ship fetch — install a controllable mock
    const fetchMock = vi.fn(async (url: string) => {
      if (url.startsWith("/api/rationale/")) {
        return {
          ok: true,
          json: async () => FAKE_RATIONALE,
        } as Response
      }
      return { ok: false, json: async () => ({}) } as Response
    })
    ;(globalThis as any).fetch = fetchMock
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("renders <WhyAnchor> when technical.rationale_id is present", async () => {
    const msg = makeProgressMessage({ rationale_id: "bulk_rnaseq_consensus_de_bioc:B" })
    render(<ChatMessage message={msg} />)
    // testid uses '-' substitution for ':'
    expect(screen.getByTestId("why-anchor-bulk_rnaseq_consensus_de_bioc-B")).toBeInTheDocument()
  })

  it("does NOT render WhyAnchor on non-progress messages", () => {
    const userMsg: Message = {
      id: "u1", role: "user", content: "Run DESeq2", timestamp: new Date(),
    } as Message
    render(<ChatMessage message={userMsg} />)
    expect(screen.queryByText("(why?)")).not.toBeInTheDocument()
  })

  it("hover fetches /api/rationale/:id + renders text and DOI link", async () => {
    const msg = makeProgressMessage({ rationale_id: "bulk_rnaseq_consensus_de_bioc:B" })
    const user = userEvent.setup()
    render(<ChatMessage message={msg} />)
    await user.click(screen.getByTestId("why-anchor-bulk_rnaseq_consensus_de_bioc-B"))
    await waitFor(() =>
      expect((globalThis as any).fetch).toHaveBeenCalledWith(
        expect.stringContaining("/api/rationale/bulk_rnaseq_consensus_de_bioc%3AB"),
        expect.any(Object),
      ),
    )
    // Radix renders popover content in a portal — query the document, not the
    // mounted tree.
    await waitFor(() => {
      expect(document.body.textContent || "").toMatch(/DESeqDataSet/)
    })
    const link = document.querySelector(
      'a[href="https://doi.org/10.1186/s13059-014-0550-8"]',
    )
    expect(link).not.toBeNull()
  })

  it("falls back to legacy URL when only phase_name is present (no rationale_id)", async () => {
    const msg = makeProgressMessage({}) // phase_name only, no rationale_id
    render(<ChatMessage message={msg} currentExecutionRun={{ workflowName: "x_chain" } as any} />)
    const anchor = screen.queryByTestId("why-anchor-Normalise")
    // Anchor renders since fallback path has both wfName + phaseId
    expect(anchor).toBeInTheDocument()
    const user = userEvent.setup()
    await user.click(anchor!)
    await waitFor(() =>
      expect((globalThis as any).fetch).toHaveBeenCalledWith(
        expect.stringContaining("/api/workflows/x_chain/phases/Normalise/rationale"),
        expect.any(Object),
      ),
    )
  })

  it("renders nothing visible if neither rationale_id nor workflowName+phaseId resolve", async () => {
    const msg = makeProgressMessage({}) // phase_name only, no chain context
    render(<ChatMessage message={msg} />) // no currentExecutionRun
    expect(screen.queryByText("(why?)")).not.toBeInTheDocument()
  })
})
