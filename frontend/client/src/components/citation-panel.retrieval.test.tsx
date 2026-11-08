/**
 * RTL tests for <CitationPanel> — Spec 09 "How this was searched"
 * retrieval-transparency section.
 *
 * v2 gap (docs/20260909_V2GAP_SEARCH_FILES_REPORTS_CONNECTORS.md, Surface B):
 * the deployed citation panel showed reference cards but no retrieval
 * transparency — per-source found/kept. This section surfaces exactly that,
 * driven by a `retrieval` prop supplied by the retrieval path.
 *
 * Honesty contract verified here:
 *  - the section renders ONLY when real per-source counts are supplied;
 *  - it is omitted entirely when `retrieval` is absent or empty (no fabricated
 *    "kept" derived from the citation list);
 *  - the "N of M kept" summary is the sum of the per-source counts;
 *  - malformed source rows (missing name / non-finite counts) are dropped.
 *
 * These tests do NOT touch the other citation-panel test files.
 */
import { describe, it, expect } from "vitest"
import { render, screen, within } from "@testing-library/react"
import { CitationPanel, type RetrievalSource } from "./citation-panel"
import type { Citation } from "@shared/schema"

function makeCitation(over: Partial<Citation> = {}): Citation {
  return {
    tool_id: "t1",
    tool_name: "DESeq2",
    title: "Interferon signalling in disease",
    authors: ["Author A"],
    year: 2023,
    journal: "Cell Rep",
    doi: "10.1000/abc",
    formatted_apa: "Author A et al. (2023).",
    formatted_short: "Author A et al., 2023",
    formatted_bibtex: "@article{a2023}",
    ...over,
  } as unknown as Citation
}

const RETRIEVAL: RetrievalSource[] = [
  { name: "PubMed", found: 214, kept: 18 },
  { name: "Europe PMC", found: 96, kept: 11 },
  { name: "bioRxiv", found: 40, kept: 3 },
]

describe("<CitationPanel> — Spec 09 retrieval transparency", () => {
  it("renders 'How this was searched' with one row per source", () => {
    render(
      <CitationPanel citations={[makeCitation()]} retrieval={RETRIEVAL} isCollapsed={false} />,
    )
    const panel = screen.getByTestId("retrieval-transparency")
    expect(panel).toHaveTextContent(/How this was searched/i)
    expect(screen.getByTestId("retrieval-source-PubMed")).toBeInTheDocument()
    expect(screen.getByTestId("retrieval-source-Europe PMC")).toBeInTheDocument()
    expect(screen.getByTestId("retrieval-source-bioRxiv")).toBeInTheDocument()
  })

  it("keeps retrieval details folded and avoids a redundant tab bar for a source-only panel", () => {
    render(<CitationPanel citations={[makeCitation()]} retrieval={RETRIEVAL} isCollapsed={false} />)
    expect(screen.getByTestId('retrieval-transparency')).not.toHaveAttribute('open')
    expect(screen.queryByRole('tab', { name: 'Tool Citations' })).toBeNull()
    expect(screen.queryByRole('tab', { name: 'Methods Section' })).toBeNull()
    expect(screen.getAllByText('Citations')).toHaveLength(1)
  })

  it("shows per-source found · kept counts", () => {
    render(
      <CitationPanel citations={[makeCitation()]} retrieval={RETRIEVAL} isCollapsed={false} />,
    )
    const pubmed = screen.getByTestId("retrieval-source-PubMed")
    expect(pubmed).toHaveTextContent("214 found")
    expect(pubmed).toHaveTextContent("18 kept")
  })

  it("summarises 'N of M kept' as the sum of per-source counts", () => {
    render(
      <CitationPanel citations={[makeCitation()]} retrieval={RETRIEVAL} isCollapsed={false} />,
    )
    // 18 + 11 + 3 = 32 kept of 214 + 96 + 40 = 350 found.
    expect(screen.getByTestId("retrieval-summary")).toHaveTextContent("32 of 350 kept")
  })

  it("renders NOTHING when retrieval is omitted (honest — no fabricated transparency)", () => {
    render(<CitationPanel citations={[makeCitation()]} isCollapsed={false} />)
    expect(screen.queryByTestId("retrieval-transparency")).not.toBeInTheDocument()
  })

  it("renders NOTHING when retrieval is an empty array", () => {
    render(<CitationPanel citations={[makeCitation()]} retrieval={[]} isCollapsed={false} />)
    expect(screen.queryByTestId("retrieval-transparency")).not.toBeInTheDocument()
  })

  it("drops malformed source rows (missing name or non-finite counts)", () => {
    render(
      <CitationPanel
        citations={[makeCitation()]}
        retrieval={[
          { name: "PubMed", found: 100, kept: 10 },
          { name: "", found: 5, kept: 5 } as RetrievalSource,
          { name: "Broken", found: Number.NaN, kept: 0 } as RetrievalSource,
        ]}
        isCollapsed={false}
      />,
    )
    const panel = screen.getByTestId("retrieval-transparency")
    // Only the one valid row survives.
    expect(within(panel).getByTestId("retrieval-source-PubMed")).toBeInTheDocument()
    expect(within(panel).queryByTestId("retrieval-source-Broken")).not.toBeInTheDocument()
    // Summary reflects only the valid row.
    expect(screen.getByTestId("retrieval-summary")).toHaveTextContent("10 of 100 kept")
  })
})
