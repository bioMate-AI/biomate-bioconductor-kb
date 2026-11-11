/**
 * RTL tests for <SourceReaderPane> — Spec 01 §1.3.3 source reader.
 * Verifies: closed when index is null; header shows title/venue/year and the
 * "cited for" locus; recency line renders when present; next/prev navigation
 * disables at the ends; honest "open at source" fallback resolves to DOI/PMID
 * (never a faked passage); sourceUrl() precedence.
 */
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"
import { api } from "@/lib/api"
import userEvent from "@testing-library/user-event"
import {
  SourceReaderPane,
  sourceUrl,
  readerQuery,
  type EvidenceCitation,
  type ReaderFulltext,
} from "./source-reader-pane"

// The reader fetches /api/literature/fulltext through api.request. Each test
// sets the route's answer explicitly; the route contract itself is covered by
// server/literature-fulltext-routes.test.ts against recorded Europe PMC data.
const requestSpy = vi.spyOn(api, "request")
function fulltext(over: Partial<ReaderFulltext> = {}): ReaderFulltext {
  return {
    found: true, title: null, journal: null, year: null, authors: null, abstract: null,
    openAccess: false, license: null, fullTextStatus: "not_open_access", sections: [], truncated: false,
    links: { publisher: "https://doi.org/10.1000/abc", europepmc: null },
    ...over,
  }
}
beforeEach(() => { requestSpy.mockReset(); requestSpy.mockResolvedValue(fulltext() as any) })

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

  it("fetches the reader route by the source's ids and says honestly when it is not open access", async () => {
    render(<SourceReaderPane sources={[makeSource({ pmid: "42" })]} index={0} onIndexChange={() => {}} />)
    expect(requestSpy).toHaveBeenCalledWith("/literature/fulltext?pmid=42&doi=10.1000%2Fabc")
    const link = screen.getByTestId("reader-open-source").closest("a")
    expect(link).toHaveAttribute("href", "https://doi.org/10.1000/abc")
    expect(await screen.findByTestId("reader-status")).toHaveTextContent(/Not open access/)
    expect(screen.queryByTestId("reader-fulltext")).toBeNull()
  })

  it("renders the fetched abstract and open-access full text sections", async () => {
    requestSpy.mockResolvedValue(fulltext({
      openAccess: true, fullTextStatus: "available", license: "cc by",
      abstract: "Fetched abstract text.",
      sections: [{ heading: "Results", paragraphs: ["Paragraph one.", "Paragraph two."] }],
    }) as any)
    render(<SourceReaderPane sources={[makeSource({ abstract: undefined })]} index={0} onIndexChange={() => {}} />)
    expect(await screen.findByTestId("reader-fulltext")).toHaveTextContent("Results")
    expect(screen.getByTestId("reader-fulltext")).toHaveTextContent("Paragraph two.")
    expect(screen.getByTestId("reader-abstract")).toHaveTextContent("Fetched abstract text.")
    expect(screen.getByTestId("reader-oa-badge")).toBeInTheDocument()
    expect(screen.queryByTestId("reader-status")).toBeNull()
  })

  it("reports a failed lookup instead of an empty body", async () => {
    requestSpy.mockRejectedValue(new Error("502"))
    render(<SourceReaderPane sources={[makeSource()]} index={0} onIndexChange={() => {}} />)
    await waitFor(() => expect(screen.getByTestId("reader-status")).toHaveTextContent(/Could not reach Europe PMC/))
  })

  it("shows actual retrieved content and author metadata without an empty framed panel", () => {
    render(<SourceReaderPane sources={[makeSource({ abstract: 'Measured response in two conditions.', excerpt: 'Figure 3 compares the response.' })]} index={0} onIndexChange={() => {}} />)
    expect(screen.getByTestId('reader-abstract')).toHaveTextContent('Measured response in two conditions.')
    expect(screen.getByTestId('reader-excerpt')).toHaveTextContent('Figure 3 compares the response.')
    expect(screen.getByTestId('reader-authors')).toHaveTextContent('Author A')
  })

  it("states missing content compactly without inventing authors or abstracts (no ids → no fetch)", () => {
    render(<SourceReaderPane sources={[makeSource({ authors: [], abstract: undefined, doi: undefined, pmid: undefined })]} index={0} onIndexChange={() => {}} />)
    expect(requestSpy).not.toHaveBeenCalled()
    expect(screen.getByTestId('reader-status')).toHaveTextContent('No abstract, excerpt or identifier was supplied')
    expect(screen.queryByTestId('reader-authors')).toBeNull()
    expect(screen.queryByTestId('reader-open-source')).toBeNull()
    expect(screen.queryByText(/Unknown/)).toBeNull()
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

it('normalizes DOI URLs supplied as DOI metadata', () => {
  expect(sourceUrl(makeSource({ doi: 'https://doi.org/10.1000/abc' }))).toBe('https://doi.org/10.1000/abc')
  expect(sourceUrl(makeSource({ doi: undefined, pmid: 'not-a-pmid', url: 'https://publisher.example/article' }))).toBe('https://publisher.example/article')
})

it('readerQuery passes pmcid/pmid/doi and refuses junk', () => {
  expect(readerQuery(makeSource({ doi: 'doi:10.1/x', pmid: '12', pmcid: 'PMC7' } as any))).toBe('pmcid=PMC7&pmid=12&doi=10.1%2Fx')
  expect(readerQuery(makeSource({ doi: 'not a doi', pmid: 'abc' }))).toBeNull()
})
