/**
 * RTL tests for <CitationPanel> — literature sources under a research answer.
 *
 * Verifies the founder-review (2026-11-10) shape:
 *  - collapsed by default to one quiet "N sources" line;
 *  - expanded = numbered one-line references "[n] title · journal · year",
 *    the title linking to DOI / PubMed, plus one "Read" per source;
 *  - no per-item expand cards, no duplicated open/Read pair, no APA/BibTeX
 *    noise on literature, and NO "Save to notes" / "Make instruction" buttons;
 *  - Read opens the source reader at that source (cited-for locus visible).
 */
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { CitationPanel } from "./citation-panel"
import { api } from "@/lib/api"
import type { EvidenceCitation } from "./source-reader-pane"
import type { Citation } from "@shared/schema"

function makeCitation(over: Partial<EvidenceCitation> = {}): Citation {
  return {
    tool_id: "t1",
    tool_name: "Interferon signalling in disease",
    title: "Interferon signalling in disease",
    authors: ["Author A"],
    year: 2023,
    journal: "Cell Rep",
    doi: "10.1000/abc",
    formatted_apa: "",
    formatted_short: "",
    formatted_bibtex: "",
    locus: "Fig 3B",
    ...over,
  } as unknown as Citation
}

beforeEach(() => {
  vi.spyOn(api, "request").mockResolvedValue({ found: false, fullTextStatus: "not_found", sections: [], links: { publisher: null, europepmc: null } } as any)
})

describe("<CitationPanel kind=literature>", () => {
  it("is collapsed by default to a single 'N sources' line", () => {
    render(<CitationPanel kind="literature" citations={[makeCitation(), makeCitation({ tool_id: "t2", doi: "10.1/b" })]} />)
    expect(screen.getByTestId("citations-toggle")).toHaveTextContent("2 sources")
    expect(screen.queryByTestId("reference-list")).toBeNull()
  })

  it("expands to numbered one-line references linking to DOI / PubMed", async () => {
    const user = userEvent.setup()
    render(<CitationPanel kind="literature" citations={[
      makeCitation(),
      makeCitation({ tool_id: "b", title: "Second paper", doi: undefined, pmid: "999", journal: undefined, year: 2021 }),
    ]} />)
    await user.click(screen.getByTestId("citations-toggle"))
    const first = screen.getByTestId("reference-0")
    expect(first).toHaveTextContent("[1]Interferon signalling in disease · Cell Rep · 2023")
    expect(within(first).getByRole("link", { name: "Interferon signalling in disease" })).toHaveAttribute("href", "https://doi.org/10.1000/abc")
    expect(within(screen.getByTestId("reference-1")).getByRole("link", { name: "Second paper" })).toHaveAttribute("href", "https://pubmed.ncbi.nlm.nih.gov/999")
    // One Read per source; no "open ▸" duplicate, no expand cards, no formats.
    expect(screen.getAllByText("Read")).toHaveLength(2)
    expect(screen.queryByText("open")).toBeNull()
    expect(screen.queryByRole("button", { name: "APA" })).toBeNull()
    expect(screen.queryByRole("button", { name: "BibTeX" })).toBeNull()
    expect(screen.queryByText("Export BibTeX")).toBeNull()
  })

  it("never renders the removed answer→project buttons", async () => {
    render(<CitationPanel kind="literature" citations={[makeCitation()]} isCollapsed={false} answerText="x" />)
    expect(screen.queryByTestId("answer-save-notes")).toBeNull()
    expect(screen.queryByTestId("answer-make-instruction")).toBeNull()
    expect(screen.queryByText(/save to notes|make instruction/i)).toBeNull()
  })

  it("Read opens the source reader at the clicked source with its cited-for locus", async () => {
    const user = userEvent.setup()
    render(<CitationPanel kind="literature" isCollapsed={false} citations={[
      makeCitation({ tool_id: "a", title: "First paper", locus: "Fig 3B" }),
      makeCitation({ tool_id: "b", title: "Second paper", locus: "Table 2", doi: "10.1/b" }),
    ]} />)
    expect(screen.queryByTestId("source-reader-pane")).not.toBeInTheDocument()
    await user.click(screen.getByTestId("source-read-1"))
    expect(screen.getByTestId("source-reader-pane")).toBeInTheDocument()
    expect(screen.getByTestId("reader-locus")).toHaveTextContent("Table 2")
    expect(screen.getByTestId("reader-prev")).not.toBeDisabled()
    expect(screen.getByTestId("reader-next")).toBeDisabled()
  })

  it("hides Read when the source has nothing the reader could show", async () => {
    render(<CitationPanel kind="literature" isCollapsed={false} citations={[makeCitation({ doi: undefined, pmid: undefined, url: "https://x.org" } as any)]} />)
    expect(screen.queryByTestId("source-read-0")).toBeNull()
  })
})

describe("<CitationPanel kind=workflow>", () => {
  it("has no save/instruction buttons and no duplicated open affordance", () => {
    render(<CitationPanel citations={[makeCitation({ formatted_apa: "A (2023)." })]} isCollapsed={false} />)
    expect(screen.queryByTestId("answer-save-notes")).toBeNull()
    expect(screen.queryByTestId("answer-make-instruction")).toBeNull()
    expect(screen.queryByTestId("source-open-0")).toBeNull()
  })
})
