/**
 * Integration test: the LIVE chat research answer renders the rich CitationPanel,
 * and surfaces retrieval transparency ("How this was searched") + conflict rows
 * ("Sources disagree") ONLY when the backend supplied real data — and renders
 * neither (without crashing) when that data is absent.
 *
 * This proves the honest-empty contract end-to-end through chat-message ->
 * ResearchResponseDisplay -> CitationPanel: fabricated retrieval/conflicts are
 * impossible because the panel only renders what the response object carries.
 */
import { describe, it, expect, vi, afterEach } from "vitest"
import { render, screen, fireEvent } from "@testing-library/react"

// chat-message transitively imports the 3Dmol viewer (window.URL.createObjectURL);
// jsdom lacks it. Stub before import.
vi.mock("3dmol", () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))

import { ChatMessage, type Message } from "./chat-message"
import { api } from "@/lib/api"

function researchMessage(rr: Record<string, any>): Message {
  return {
    id: "m-research-panel",
    role: "assistant",
    content: "",
    timestamp: new Date(),
    metadata: {
      type: "research_response",
      research_response: rr,
    } as any,
  } as Message
}

const baseResponse = {
  answer: "STAR and HISAT2 both align RNA-seq reads with comparable accuracy.",
  citations: [
    { title: "Aligner benchmark A", year: 2023, doi: "10.1/a" },
    { title: "Aligner benchmark B", year: 2024, pmid: "12345" },
  ],
  confidence: 0.8,
}

function expandCitations() {
  // Sources are COLLAPSED by default (one quiet "N sources" line); open them.
  const toggle = screen.getByTestId("citations-toggle")
  if (toggle.getAttribute("aria-expanded") !== "true") fireEvent.click(toggle)
}

describe("live research answer → rich CitationPanel (retrieval + conflicts)", () => {
  afterEach(() => { vi.restoreAllMocks() })

  it("does not present retrieved papers as evidence for a turn still requesting clarification", () => {
    const message = researchMessage(baseResponse)
    render(<ChatMessage message={{ ...message, content: 'Please identify the scaffold first.', metadata: { ...message.metadata, needsUserFeedback: true } }} />)
    expect(screen.getByText('Please identify the scaffold first.')).toBeVisible()
    expect(screen.queryByTestId('citations-toggle')).toBeNull()
    expect(screen.queryByTestId('reference-list')).toBeNull()
  })

  it("renders retrieval transparency + conflicts when the response supplies them", () => {
    render(
      <ChatMessage
        message={researchMessage({
          ...baseResponse,
          retrieval: [
            { name: "PubMed", found: 20, kept: 2 },
            { name: "Europe PMC", found: 8, kept: 0 },
          ],
          conflicts: [
            {
              topic: "Accuracy at low coverage",
              positions: [
                { claim: "STAR is more accurate", source: "Benchmark A" },
                { claim: "HISAT2 is more accurate", source: "Benchmark B" },
              ],
            },
          ],
        })}
      />
    )
    expandCitations()

    // "How this was searched" with a real N-of-M summary.
    expect(screen.getByTestId("retrieval-transparency")).toBeInTheDocument()
    // 2 + 0 kept of 20 + 8 found.
    expect(screen.getByTestId("retrieval-summary")).toHaveTextContent("2 of 28 kept")
    // Per-source breakdown lives in the footnote's tooltip / accessible label.
    expect(screen.getByTestId("retrieval-transparency")).toHaveAttribute(
      "aria-label", expect.stringContaining("PubMed: 20 found · 2 kept"),
    )

    // Conflict row present (collapsed summary line).
    expect(screen.getByTestId("conflict-row")).toBeInTheDocument()
    expect(screen.getByTestId("conflict-row")).toHaveTextContent(
      "Sources disagree — 1 conflicting finding"
    )

    // The Boundary banner was removed from research answers (2026-11-10).
    expect(screen.queryByTestId("research-answer-boundary")).toBeNull()
  })

  it("renders neither section (no crash) when retrieval/conflicts are absent", () => {
    render(<ChatMessage message={researchMessage(baseResponse)} />)
    expandCitations()

    expect(screen.queryByTestId("retrieval-transparency")).toBeNull()
    expect(screen.queryByTestId("conflict-row")).toBeNull()

    // The source list still renders (both citations); no Boundary banner.
    expect(screen.getByText("Aligner benchmark A")).toBeInTheDocument()
    expect(screen.queryByTestId("research-answer-boundary")).toBeNull()
  })

  it("does not fabricate retrieval from the citation list (empty array → no section)", () => {
    render(
      <ChatMessage
        message={researchMessage({ ...baseResponse, retrieval: [], conflicts: [] })}
      />
    )
    expandCitations()
    expect(screen.queryByTestId("retrieval-transparency")).toBeNull()
    expect(screen.queryByTestId("conflict-row")).toBeNull()
  })
})

describe("research source detail", () => {
  it("preserves the retrieved abstract into the reader and omits unavailable formats", () => {
    render(<ChatMessage message={researchMessage({ ...baseResponse, citations: [{ title: "Study with abstract", doi: "10.1/a", abstract: "Measured inhibition across two experimental conditions." }] })} />)
    expandCitations()
    expect(screen.queryByText("Tool Citations")).toBeNull()
    expect(screen.queryByText("Methods Section")).toBeNull()
    expect(screen.queryByRole("button", { name: "APA" })).toBeNull()
    expect(screen.queryByRole("button", { name: "BibTeX" })).toBeNull()
    vi.spyOn(api, "request").mockResolvedValue({ found: false, fullTextStatus: "not_found", sections: [], links: { publisher: null, europepmc: null } } as any)
    fireEvent.click(screen.getByTestId("source-read-0"))
    expect(screen.getByTestId("reader-abstract")).toHaveTextContent("Measured inhibition across two experimental conditions.")
  })

  it("streams the answer visibly (no folded 'Writing response…') and keeps it after completion", () => {
    const message = { ...researchMessage(baseResponse), content: "A detailed analysis is being written." }
    const { rerender } = render(<ChatMessage message={message} isStreaming />)
    expect(screen.queryByText("Writing response…")).toBeNull()
    expect(screen.getByText(message.content)).toBeVisible()
    rerender(<ChatMessage message={message} isStreaming={false} />)
    expect(screen.queryByText("Writing response…")).toBeNull()
    expect(screen.getByText(message.content)).toBeVisible()
  })
})

describe("one action row under every assistant answer", () => {
  it("research answers get the single quiet icon row — and no Save-to-project / Plan / Save-to-notes / Make-instruction buttons", () => {
    const message = { ...researchMessage(baseResponse), content: "Answer text." }
    render(<ChatMessage message={message} isLatestAssistantMessage />)
    expectCitationsAbsentButtons()
    const rows = screen.getAllByTestId("message-action-row")
    expect(rows).toHaveLength(1)
    for (const id of ["button-copy-response-icon", "button-save-response", "button-regenerate-message-icon"]) {
      expect(screen.getByTestId(id)).toBeInTheDocument()
    }
    expect(screen.getByTestId("inline-feedback-thumbs-up")).toBeInTheDocument()
    expect(screen.getByTestId("inline-feedback-thumbs-down")).toBeInTheDocument()
  })

  it("no action row while the turn is still running (live dev 2026-11-12: copy/retry/rate under a half-finished reply)", () => {
    const msg = { id: "m-run", role: "assistant", content: "我来对您的 ADMET 数据文件进行质量控制分析。", timestamp: new Date() } as Message
    const { rerender } = render(<ChatMessage message={msg} isStreaming />)
    expect(screen.queryByTestId("message-action-row")).toBeNull()
    rerender(<ChatMessage message={msg} isStreaming={false} />)
    expect(screen.getByTestId("message-action-row")).toBeInTheDocument()
  })

  it("plain text answers get the same row with thumbs (feedback is not workflow-only)", () => {
    render(<ChatMessage message={{ id: "m-plain", role: "assistant", content: "Plain answer.", timestamp: new Date() } as Message} />)
    expect(screen.getByTestId("message-action-row")).toBeInTheDocument()
    expect(screen.getByTestId("inline-feedback-thumbs-up")).toBeInTheDocument()
  })
})

function expectCitationsAbsentButtons() {
  for (const id of ["research-answer-save", "research-answer-check-data", "answer-save-notes", "answer-make-instruction"]) {
    expect(screen.queryByTestId(id)).toBeNull()
  }
  fireEvent.click(screen.getByTestId("citations-toggle"))
  for (const id of ["answer-save-notes", "answer-make-instruction"]) expect(screen.queryByTestId(id)).toBeNull()
}
