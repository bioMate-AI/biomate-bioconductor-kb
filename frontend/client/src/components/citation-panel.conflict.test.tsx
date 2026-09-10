/**
 * RTL tests for <CitationPanel> — Spec 01 §1.3.2 "Sources disagree" ConflictRow.
 *
 * Audit gap #6 (2026-09-09): the conflict affordance had ZERO tests anywhere.
 * It is an honesty feature — when the retrieval path detects that sources
 * materially disagree, the panel must surface both positions rather than
 * smoothing them into one confident sentence.
 *
 * Verifies:
 *  - the conflict row renders with the "Sources disagree — N conflicting
 *    findings" summary and pluralises N correctly (0 conflicts → no row,
 *    1 → "finding", 2 → "findings");
 *  - collapsed by default (positions hidden), expands on click to reveal BOTH
 *    positions and the source each rests on;
 *  - a conflicts prop whose entries have no positions is treated as no conflict
 *    (honest — never fabricate a disagreement the retrieval path didn't mark).
 *
 * These tests do NOT touch citation-panel.evidence.test.tsx or
 * citation-panel.save-notes.test.tsx.
 */
import { describe, it, expect } from "vitest"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { CitationPanel, type CitationConflict } from "./citation-panel"
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

const twoWayConflict: CitationConflict = {
  topic: "Effect at physiological dose",
  positions: [
    { claim: "Compound X inhibits CYP3A4 at 1 µM.", source: "Smith 2021 (PMID 111)" },
    { claim: "No measurable CYP3A4 inhibition below 10 µM.", source: "Lee 2023 (PMID 222)" },
  ],
}

describe("<CitationPanel> — Spec 01 §1.3.2 ConflictRow", () => {
  it("renders the 'Sources disagree' row with the conflict count (plural)", () => {
    render(
      <CitationPanel
        citations={[makeCitation()]}
        conflicts={[twoWayConflict]}
        isCollapsed={false}
      />,
    )
    const row = screen.getByTestId("conflict-row")
    expect(row).toBeInTheDocument()
    // Exactly one conflict → singular "finding".
    expect(row).toHaveTextContent("Sources disagree — 1 conflicting finding")
  })

  it("keeps both positions hidden until the row is expanded, then shows BOTH", async () => {
    const user = userEvent.setup()
    render(
      <CitationPanel
        citations={[makeCitation()]}
        conflicts={[twoWayConflict]}
        isCollapsed={false}
      />,
    )

    // Collapsed by default — neither position claim is in the DOM yet.
    expect(screen.queryByText(/inhibits CYP3A4 at 1 µM/)).not.toBeInTheDocument()
    expect(screen.queryByText(/No measurable CYP3A4 inhibition/)).not.toBeInTheDocument()

    // Expand.
    await user.click(screen.getByTestId("conflict-row").querySelector("button")!)

    // Both opposing positions AND both sources are now visible side by side.
    expect(screen.getByText(/inhibits CYP3A4 at 1 µM/)).toBeInTheDocument()
    expect(screen.getByText(/No measurable CYP3A4 inhibition/)).toBeInTheDocument()
    expect(screen.getByText(/Smith 2021 \(PMID 111\)/)).toBeInTheDocument()
    expect(screen.getByText(/Lee 2023 \(PMID 222\)/)).toBeInTheDocument()
    // The topic label frames the disagreement.
    expect(screen.getByText("Effect at physiological dose")).toBeInTheDocument()
  })

  it("pluralises the count when multiple conflicts are present", () => {
    const second: CitationConflict = {
      topic: "Half-life",
      positions: [
        { claim: "t½ ≈ 2 h", source: "A" },
        { claim: "t½ ≈ 6 h", source: "B" },
      ],
    }
    render(
      <CitationPanel
        citations={[makeCitation()]}
        conflicts={[twoWayConflict, second]}
        isCollapsed={false}
      />,
    )
    expect(screen.getByTestId("conflict-row")).toHaveTextContent(
      "Sources disagree — 2 conflicting findings",
    )
  })

  it("renders NO conflict row when conflicts is omitted (honest — no fabricated disagreement)", () => {
    render(<CitationPanel citations={[makeCitation()]} isCollapsed={false} />)
    expect(screen.queryByTestId("conflict-row")).not.toBeInTheDocument()
  })

  it("ignores conflict entries that carry no positions (honest empty)", () => {
    // The retrieval path passes an entry but marked no actual positions — the
    // panel must not manufacture a "Sources disagree" banner from it.
    render(
      <CitationPanel
        citations={[makeCitation()]}
        conflicts={[{ topic: "unresolved", positions: [] }]}
        isCollapsed={false}
      />,
    )
    expect(screen.queryByTestId("conflict-row")).not.toBeInTheDocument()
  })
})
