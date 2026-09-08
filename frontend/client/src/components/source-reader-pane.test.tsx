/**
 * RTL tests for <SourceReaderPane> — Spec 01 §1.3.3 source reader.
 * Verifies: closed when index is null; header shows title/venue/year and the
 * "cited for" locus; recency line renders when present; next/prev navigation
 * disables at the ends; honest "open at source" fallback resolves to DOI/PMID
 * (never a faked passage); sourceUrl() precedence.
 */
import { describe, it, expect, vi } from "vitest"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import {
  SourceReaderPane,
  sourceUrl,
  type EvidenceCitation,
} from "./source-reader-pane"

function makeSource(over: Partial<EvidenceCitation> = {}): EvidenceCitation {
  return {
    tool_id: "t1",
    tool_name: "Tool One",
    title: "Interferon signalling in disease",
    authors: ["Author A"],
    year: 2023,
    journal: "Cell Rep",
    doi: "10.1000/abc",
    formatted_apa: "",
    formatted_short: "",
    formatted_bibtex: "",
    locus: "Fig 3B",
    retrieval_date: "2026-09-01",
    ...over,
  } as EvidenceCitation
}

describe("sourceUrl()", () => {
  it("prefers DOI over PubMed", () => {
    expect(sourceUrl(makeSource({ doi: "10.1/x", pmid: "999" }))).toBe(
      "https://doi.org/10.1/x",
    )
  })
  it("falls back to PubMed when no DOI", () => {
    expect(sourceUrl(makeSource({ doi: undefined, pmid: "999" }))).toBe(
      "https://pubmed.ncbi.nlm.nih.gov/999",
    )
  })
  it("returns null when neither is present", () => {
    expect(sourceUrl(makeSource({ doi: undefined, pmid: undefined }))).toBeNull()
  })
})

describe("<SourceReaderPane>", () => {
  it("renders nothing when index is null", () => {
    render(
      <SourceReaderPane sources={[makeSource()]} index={null} onIndexChange={() => {}} />,
    )
    expect(screen.queryByTestId("source-reader-pane")).not.toBeInTheDocument()
  })

  it("shows title, venue/year and the cited-for locus", () => {
    render(
      <SourceReaderPane sources={[makeSource()]} index={0} onIndexChange={() => {}} />,
    )
    expect(screen.getByText("Interferon signalling in disease")).toBeInTheDocument()
    expect(screen.getByText("Cell Rep · 2023")).toBeInTheDocument()
    expect(screen.getByTestId("reader-locus")).toHaveTextContent("Fig 3B")
    expect(screen.getByText(/Retrieved 2026-09-01/)).toBeInTheDocument()
  })

  it("offers an honest open-at-source link (no faked passage)", () => {
    render(
      <SourceReaderPane sources={[makeSource()]} index={0} onIndexChange={() => {}} />,
    )
    const link = screen.getByTestId("reader-open-source").closest("a")
    expect(link).toHaveAttribute("href", "https://doi.org/10.1000/abc")
    expect(screen.getByText(/Full text is not available/i)).toBeInTheDocument()
  })

  it("navigates next/prev and disables at the ends", async () => {
    const user = userEvent.setup()
    const onIndexChange = vi.fn()
    const sources = [
      makeSource({ tool_id: "a", title: "First" }),
      makeSource({ tool_id: "b", title: "Second" }),
    ]
    render(
      <SourceReaderPane sources={sources} index={0} onIndexChange={onIndexChange} />,
    )
    // At index 0: prev disabled, next enabled.
    expect(screen.getByTestId("reader-prev")).toBeDisabled()
    expect(screen.getByTestId("reader-next")).not.toBeDisabled()
    await user.click(screen.getByTestId("reader-next"))
    expect(onIndexChange).toHaveBeenCalledWith(1)
  })

  it("omits recency and locus lines when absent (no fabrication)", () => {
    render(
      <SourceReaderPane
        sources={[makeSource({ locus: null, retrieval_date: null, corpus_version: null })]}
        index={0}
        onIndexChange={() => {}}
      />,
    )
    expect(screen.queryByTestId("reader-locus")).not.toBeInTheDocument()
    expect(screen.queryByText(/Retrieved/)).not.toBeInTheDocument()
  })
})
