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
  // The rich panel now defaults to EXPANDED on a research turn (evidence-forward),
  // so only click to open it when it is actually collapsed — i.e. the source rows
  // are not yet in the DOM. Idempotent + robust to the default either way.
  if (!screen.queryByTestId("source-open-0")) {
    const toggle = screen.queryByText("Citations")
    if (toggle) fireEvent.click(toggle)
  }
}

describe("live research answer → rich CitationPanel (retrieval + conflicts)", () => {
  afterEach(() => { vi.restoreAllMocks() })

  it("does not present retrieved papers as evidence for a turn still requesting clarification", () => {
    const message = researchMessage(baseResponse)
    render(<ChatMessage message={{ ...message, content: 'Please identify the scaffold first.', metadata: { ...message.metadata, needsUserFeedback: true } }} />)
    expect(screen.getByText('Please identify the scaffold first.')).toBeVisible()
    expect(screen.queryByTestId('source-open-0')).toBeNull()
    expect(screen.queryByText('Citations')).toBeNull()
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
    expect(screen.getByTestId("retrieval-source-PubMed")).toBeInTheDocument()

    // Conflict row present (collapsed summary line).
    expect(screen.getByTestId("conflict-row")).toBeInTheDocument()
    expect(screen.getByTestId("conflict-row")).toHaveTextContent(
      "Sources disagree — 1 conflicting finding"
    )

    // The always-present boundary is not regressed.
    expect(screen.getByTestId("research-answer-boundary")).toBeInTheDocument()
  })

  it("renders neither section (no crash) when retrieval/conflicts are absent", () => {
    render(<ChatMessage message={researchMessage(baseResponse)} />)
    expandCitations()

    expect(screen.queryByTestId("retrieval-transparency")).toBeNull()
    expect(screen.queryByTestId("conflict-row")).toBeNull()

    // The source list still renders (both citations), and the boundary persists.
    expect(screen.getByText("Aligner benchmark A")).toBeInTheDocument()
    expect(screen.getByTestId("research-answer-boundary")).toBeInTheDocument()
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
    fireEvent.click(screen.getByText("Study with abstract"))
    expect(screen.queryByRole("button", { name: "APA" })).toBeNull()
    expect(screen.queryByRole("button", { name: "BibTeX" })).toBeNull()
    fireEvent.click(screen.getByTestId("source-open-0"))
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
