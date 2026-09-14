/**
 * RTL tests for <CitationPanel> — Spec 01 §1.3.2 / §1.3.3 / §1.5 answer→project
 * exits and the per-source reader affordance.
 *
 * Verifies:
 *  - each source row exposes an inline "open" affordance (data-testid
 *    source-open-<i>) that mounts the right-hand SourceReaderPane at that
 *    source (title + "cited for" locus visible);
 *  - the two answer→project actions render with their stable test ids;
 *  - "Save to notes" is disabled (honest) when no active project is mounted;
 *  - "Make a project instruction" is disabled (no backend endpoint yet).
 *
 * No network and no active-project provider are mounted, so the safe hook
 * returns null and the save action is honestly disabled rather than firing a
 * fabricated success.
 */
import { describe, it, expect } from "vitest"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { CitationPanel } from "./citation-panel"
import type { EvidenceCitation } from "./source-reader-pane"
import type { Citation } from "@shared/schema"

function makeCitation(over: Partial<EvidenceCitation> = {}): Citation {
  return {
    tool_id: "t1",
    tool_name: "DESeq2",
    title: "Interferon signalling in disease",
    authors: ["Author A"],
    year: 2023,
    journal: "Cell Rep",
    doi: "10.1000/abc",
    pmid: undefined,
    formatted_apa: "Author A et al. (2023).",
    formatted_short: "Author A et al., 2023",
    formatted_bibtex: "@article{a2023}",
    // widened evidence fields (see source-reader-pane.tsx)
    locus: "Fig 3B",
    retrieval_date: "2026-09-01",
    ...over,
  } as unknown as Citation
}

describe("<CitationPanel> — Spec 01 answer→project exits", () => {
  it("mounts the source reader at the clicked source with its cited-for locus", async () => {
    const user = userEvent.setup()
    const citations = [
      makeCitation({ tool_id: "a", tool_name: "DESeq2", title: "First paper", locus: "Fig 3B" }),
      makeCitation({ tool_id: "b", tool_name: "edgeR", title: "Second paper", locus: "Table 2" }),
    ]
    render(<CitationPanel citations={citations} isCollapsed={false} />)

    // Reader is closed initially.
    expect(screen.queryByTestId("source-reader-pane")).not.toBeInTheDocument()

    // Each source has an inline "open" affordance.
    expect(screen.getByTestId("source-open-0")).toBeInTheDocument()
    expect(screen.getByTestId("source-open-1")).toBeInTheDocument()

    // Open the second source → reader mounts showing its title + locus.
    await user.click(screen.getByTestId("source-open-1"))
    expect(screen.getByTestId("source-reader-pane")).toBeInTheDocument()
    expect(screen.getByText("Second paper")).toBeInTheDocument()
    expect(screen.getByTestId("reader-locus")).toHaveTextContent("Table 2")
    // next/prev navigation is present so the whole answer can be audited.
    expect(screen.getByTestId("reader-prev")).not.toBeDisabled()
    expect(screen.getByTestId("reader-next")).toBeDisabled()
  })

  it("renders both answer→project actions", () => {
    render(<CitationPanel citations={[makeCitation()]} isCollapsed={false} />)
    expect(screen.getByTestId("answer-save-notes")).toBeInTheDocument()
    expect(screen.getByTestId("answer-make-instruction")).toBeInTheDocument()
  })

  it("keeps save-to-notes honestly disabled when no project is active", () => {
    // No ActiveProjectProvider is mounted → useActiveProjectIdSafe() === null.
    render(<CitationPanel citations={[makeCitation()]} isCollapsed={false} />)
    expect(screen.getByTestId("answer-save-notes")).toBeDisabled()
  })

  it("keeps make-instruction disabled when no project is active", () => {
    // Like save-to-notes: the exit is honest — disabled without a project, and
    // enabled (wired to POST a project_instruction) once one is active.
    render(<CitationPanel citations={[makeCitation()]} isCollapsed={false} />)
    expect(screen.getByTestId("answer-make-instruction")).toBeDisabled()
  })
})
