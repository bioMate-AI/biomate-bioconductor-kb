/**
 * RTL tests for <CitationPanel> — Spec 09 "How this was searched", reduced to a
 * one-line footnote next to the "N sources" toggle (founder review 2026-11-10):
 * the "N of M kept" summary is visible, the per-source breakdown lives in the
 * tooltip / accessible label.
 *
 * Honesty contract (unchanged): renders ONLY when real per-source counts are
 * supplied; omitted when `retrieval` is absent or empty; the summary is the sum
 * of the per-source counts; malformed rows are dropped.
 */
import { describe, it, expect } from "vitest"
import { render, screen } from "@testing-library/react"
import { CitationPanel, type RetrievalSource } from "./citation-panel"
import type { Citation } from "@shared/schema"

function makeCitation(over: Partial<Citation> = {}): Citation {
  return {
    tool_id: "t1", tool_name: "Interferon signalling in disease", title: "Interferon signalling in disease",
    authors: ["Author A"], year: 2023, journal: "Cell Rep", doi: "10.1000/abc",
    formatted_apa: "", formatted_short: "", formatted_bibtex: "",
    ...over,
  } as unknown as Citation
}

const RETRIEVAL: RetrievalSource[] = [
  { name: "PubMed", found: 214, kept: 18 },
  { name: "Europe PMC", found: 96, kept: 11 },
  { name: "bioRxiv", found: 40, kept: 3 },
]

const lit = (retrieval?: RetrievalSource[]) =>
  render(<CitationPanel kind="literature" citations={[makeCitation()]} retrieval={retrieval} />)

describe("<CitationPanel> — retrieval footnote", () => {
  it("is visible even while the sources are collapsed, as a single footnote", () => {
    lit(RETRIEVAL)
    expect(screen.getByTestId("retrieval-transparency")).toBeInTheDocument()
    expect(screen.queryByTestId("reference-list")).toBeNull()
    expect(screen.queryByText(/How this was searched/i)).toBeNull()
  })

  it("summarises 'N of M kept' as the sum of per-source counts", () => {
    lit(RETRIEVAL)
    // 18 + 11 + 3 = 32 kept of 214 + 96 + 40 = 350 found.
    expect(screen.getByTestId("retrieval-summary")).toHaveTextContent("32 of 350 kept")
  })

  it("carries the per-source breakdown in its accessible label (tooltip content)", () => {
    lit(RETRIEVAL)
    const label = screen.getByTestId("retrieval-transparency").getAttribute("aria-label") || ""
    expect(label).toContain("PubMed: 214 found · 18 kept")
    expect(label).toContain("Europe PMC: 96 found · 11 kept")
    expect(label).toContain("bioRxiv: 40 found · 3 kept")
  })

  it("renders NOTHING when retrieval is omitted or empty (no fabricated transparency)", () => {
    const { unmount } = lit()
    expect(screen.queryByTestId("retrieval-transparency")).toBeNull()
    unmount()
    lit([])
    expect(screen.queryByTestId("retrieval-transparency")).toBeNull()
  })

  it("drops malformed source rows (missing name or non-finite counts)", () => {
    lit([
      { name: "PubMed", found: 100, kept: 10 },
      { name: "", found: 5, kept: 5 } as RetrievalSource,
      { name: "Broken", found: Number.NaN, kept: 0 } as RetrievalSource,
    ])
    expect(screen.getByTestId("retrieval-summary")).toHaveTextContent("10 of 100 kept")
    expect(screen.getByTestId("retrieval-transparency").getAttribute("aria-label")).not.toContain("Broken")
  })
})
