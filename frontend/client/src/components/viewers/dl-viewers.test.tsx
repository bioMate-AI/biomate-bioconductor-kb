/**
 * Rendering tests for the DL output viewers ported from the claude-design
 * prototype: PlddtChart, PaeHeatmap, SeqTracks, HitGrid.
 *
 * Each renders from a fixture matching the backend data contract. Tests assert
 * the load-bearing behaviour, not pixels:
 *   - PlddtChart: bars render, mean is shown, click fires onSelectResidue(1-based)
 *   - PaeHeatmap: n×n cells render, reliable/unresolved read-out on hover
 *   - SeqTracks: tracks + the actionable flagged list render
 *   - HitGrid: table/depiction toggle, verdict chips, "held" suppresses the score
 */

import React from "react"
import { describe, it, expect, vi } from "vitest"
import { render, screen, fireEvent, within } from "@testing-library/react"
import { PlddtChart } from "./plddt-chart"
import { PaeHeatmap } from "./pae-heatmap"
import { SeqTracks } from "./seq-tracks"
import { HitGrid } from "./hit-grid"
import type { ChemHit } from "./hit-grid"

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const PLDDT_FIXTURE = {
  plddt: [95, 92, 88, 72, 65, 48, 40, 55, 80, 91], // spans all four bands
  regions: [
    { label: "Loop 6–7", start: 6, end: 7, note: "Low confidence — flexible loop." },
    { label: "Core 1–3", start: 1, end: 3, note: "High confidence." },
  ],
}

const PAE_FIXTURE: number[][] = [
  [0, 2, 5],
  [2, 0, 12],
  [5, 12, 0],
]

const TRACKS_FIXTURE = {
  locus: "chr7:5,527,100–5,530,600",
  bp: 3500,
  tracks: [
    { kind: "line" as const, name: "Model score", values: [50, 62, 71, 60, 55] },
    { kind: "marks" as const, name: "Flagged", intervals: [[9, 12], [31, 33]] as [number, number][] },
    { kind: "ticks" as const, name: "Variants", values: [6, 11, 30] },
  ],
  flagged: [
    { start: 5527540, end: 5527690, context: "promoter-proximal", why: "score 3.1 sd above background" },
    { start: 5529700, end: 5530000, context: "intronic", why: "strongest signal in the locus" },
  ],
}

const HITS_FIXTURE: ChemHit[] = [
  { id: "BM-4471", smiles: "CC1=CC(=NO1)C(=O)Nc1ccc(F)cc1", score: 8.5, confidence: "high", herg: ">30 uM", drugLike: "4/4", verdict: "accepted" },
  { id: "BM-4488", smiles: "COc1ccc(cc1)C(=O)N1CCN(CC1)c1ncccn1", score: 8.1, confidence: "high", herg: "18 uM", drugLike: "4/4", verdict: "flagged" },
  { id: "BM-4519", smiles: "Nc1nc(nc2n(cnc12)C1CCCO1)N1CCOCC1", score: 8.8, confidence: "low", herg: "6 uM", drugLike: "3/4", verdict: "rejected" },
  { id: "BM-4541", smiles: "OC(=O)c1cc(Cl)ccc1Oc1ccccc1", score: 7.1, confidence: "out-of-domain", herg: "—", drugLike: "4/4", verdict: "held" },
]

// ---------------------------------------------------------------------------
// PlddtChart
// ---------------------------------------------------------------------------

describe("PlddtChart", () => {
  it("renders a bar per residue with the mean and regions", () => {
    render(<PlddtChart plddt={PLDDT_FIXTURE.plddt} regions={PLDDT_FIXTURE.regions} />)
    expect(screen.getByTestId("plddt-chart")).toBeInTheDocument()
    // one bar per residue
    expect(screen.getByTestId("plddt-bar-0")).toBeInTheDocument()
    expect(screen.getByTestId("plddt-bar-9")).toBeInTheDocument()
    // mean of the fixture = round(726/10) = 73
    expect(screen.getByTestId("plddt-mean")).toHaveTextContent("mean 73")
    // regions list rendered
    expect(screen.getByTestId("plddt-region-Loop 6–7")).toBeInTheDocument()
    expect(screen.getByTestId("plddt-region-Core 1–3")).toBeInTheDocument()
  })

  it("fires onSelectResidue with a 1-based residue number when a bar is clicked", () => {
    const onSelect = vi.fn()
    render(<PlddtChart plddt={PLDDT_FIXTURE.plddt} onSelectResidue={onSelect} />)
    fireEvent.click(screen.getByTestId("plddt-bar-4")) // index 4 → residue 5
    expect(onSelect).toHaveBeenCalledWith(5)
  })

  it("fires onSelectResidue from a region row (region.start, 1-based)", () => {
    const onSelect = vi.fn()
    render(<PlddtChart plddt={PLDDT_FIXTURE.plddt} regions={PLDDT_FIXTURE.regions} onSelectResidue={onSelect} />)
    fireEvent.click(screen.getByTestId("plddt-region-Loop 6–7")) // start=6 → residue 6
    expect(onSelect).toHaveBeenCalledWith(6)
  })

  it("renders an empty state when no data", () => {
    render(<PlddtChart plddt={[]} />)
    expect(screen.getByText(/No per-residue confidence data/i)).toBeInTheDocument()
  })
})

// ---------------------------------------------------------------------------
// PaeHeatmap
// ---------------------------------------------------------------------------

describe("PaeHeatmap", () => {
  it("renders an n×n grid of cells", () => {
    render(<PaeHeatmap pae={PAE_FIXTURE} />)
    expect(screen.getByTestId("pae-heatmap")).toBeInTheDocument()
    expect(screen.getByTestId("pae-cell-0-0")).toBeInTheDocument()
    expect(screen.getByTestId("pae-cell-2-2")).toBeInTheDocument()
    // 3x3 = 9 cells
    expect(screen.getByTestId("pae-grid").children.length).toBe(9)
  })

  it("reads 'reliable' below the threshold and 'unresolved' above", () => {
    render(<PaeHeatmap pae={PAE_FIXTURE} />)
    const readout = screen.getByTestId("pae-readout")
    // cell [1][2] = 12 Å → unresolved
    fireEvent.mouseEnter(screen.getByTestId("pae-cell-1-2"))
    expect(readout).toHaveTextContent("12 Å")
    expect(readout).toHaveTextContent(/unresolved/i)
    // cell [0][1] = 2 Å → reliable
    fireEvent.mouseEnter(screen.getByTestId("pae-cell-0-1"))
    expect(readout).toHaveTextContent(/reliable/i)
  })

  it("renders an empty state when no data", () => {
    render(<PaeHeatmap pae={[]} />)
    expect(screen.getByText(/No pairwise alignment error data/i)).toBeInTheDocument()
  })
})

// ---------------------------------------------------------------------------
// SeqTracks
// ---------------------------------------------------------------------------

describe("SeqTracks", () => {
  it("renders the locus, every track, and the flagged list", () => {
    render(<SeqTracks {...TRACKS_FIXTURE} />)
    expect(screen.getByTestId("seq-tracks")).toBeInTheDocument()
    expect(screen.getByText("chr7:5,527,100–5,530,600")).toBeInTheDocument()
    expect(screen.getByTestId("seq-track-Model score")).toBeInTheDocument()
    expect(screen.getByTestId("seq-track-Flagged")).toBeInTheDocument()
    expect(screen.getByTestId("seq-track-Variants")).toBeInTheDocument()
    // actionable output: both flagged intervals
    expect(screen.getByTestId("seq-flag-0")).toBeInTheDocument()
    expect(screen.getByTestId("seq-flag-1")).toBeInTheDocument()
    expect(screen.getByText("promoter-proximal")).toBeInTheDocument()
  })

  it("fires onOpenInterval with the interval when 'open' is clicked", () => {
    const onOpen = vi.fn()
    render(<SeqTracks {...TRACKS_FIXTURE} onOpenInterval={onOpen} />)
    const flag = screen.getByTestId("seq-flag-0")
    fireEvent.click(within(flag).getByText("open"))
    expect(onOpen).toHaveBeenCalledWith(TRACKS_FIXTURE.flagged[0])
  })

  it("aligns marks and ticks on one shared domain, not per-track extent", () => {
    // Regression: each track used to normalise against its OWN max, so a mark
    // and a variant tick at the SAME base rendered at different x. With bp known,
    // both map to true base coordinates.
    render(
      <SeqTracks
        locus="loc"
        bp={100}
        tracks={[
          { kind: "marks", name: "M", intervals: [[40, 50]] as [number, number][] },
          { kind: "ticks", name: "T", values: [40, 90] },
        ]}
      />,
    )
    const markX = screen.getByTestId("seq-track-M").querySelector("rect")?.getAttribute("x")
    const firstTickX = screen.getByTestId("seq-track-T").querySelectorAll("rect")[0]?.getAttribute("x")
    // base 40 on both tracks → identical x (old code: 80 vs ~44.4)
    expect(markX).toBe(firstTickX)
    expect(markX).toBe("40") // 40/100 * viewbox-100
  })
})

// ---------------------------------------------------------------------------
// HitGrid
// ---------------------------------------------------------------------------

describe("HitGrid", () => {
  it("renders the ranked table with a verdict per hit", () => {
    render(<HitGrid hits={HITS_FIXTURE} />)
    expect(screen.getByTestId("hit-grid")).toBeInTheDocument()
    expect(screen.getByTestId("hit-table")).toBeInTheDocument()
    expect(screen.getByTestId("hit-row-BM-4471")).toBeInTheDocument()
    // verdict labels present
    expect(screen.getByText("accepted")).toBeInTheDocument()
    expect(screen.getByText("rejected")).toBeInTheDocument()
  })

  it("suppresses the confident score for a 'held' (out-of-domain) hit", () => {
    render(<HitGrid hits={HITS_FIXTURE} />)
    // held hit shows no number
    expect(screen.getByTestId("hit-score-BM-4541")).toHaveTextContent("held")
    expect(screen.getByTestId("hit-score-BM-4541")).not.toHaveTextContent("7.1")
    // a non-held hit shows its number
    expect(screen.getByTestId("hit-score-BM-4471")).toHaveTextContent("8.5")
    // held-note explains why
    expect(screen.getByTestId("hit-held-note")).toHaveTextContent(/BM-4541/)
    expect(screen.getByTestId("hit-held-note")).toHaveTextContent(/applicability region/i)
  })

  it("toggles to the depiction grid keyed to each SMILES", () => {
    render(<HitGrid hits={HITS_FIXTURE} />)
    fireEvent.click(screen.getByTestId("hit-view-grid"))
    expect(screen.getByTestId("hit-depictions")).toBeInTheDocument()
    const card = screen.getByTestId("hit-depiction-BM-4471")
    expect(card).toHaveTextContent("CC1=CC(=NO1)C(=O)Nc1ccc(F)cc1")
    expect(card).toHaveTextContent(/2D depiction/i)
  })

  it("names the model behind the scores via a link stub", () => {
    const onOpenModel = vi.fn()
    render(<HitGrid hits={HITS_FIXTURE} modelName="admet-herg v3" modelId="admet-herg" onOpenModel={onOpenModel} />)
    const link = screen.getByTestId("hit-model-link")
    expect(link).toHaveTextContent("admet-herg v3")
    fireEvent.click(link)
    expect(onOpenModel).toHaveBeenCalledWith("admet-herg")
  })

  it("sorts by score when the Score header is clicked", () => {
    render(<HitGrid hits={HITS_FIXTURE} />)
    // default sort is score desc → first data row is the highest score (8.8, BM-4519)
    const firstRowId = () =>
      screen.getByTestId("hit-table").querySelectorAll("tbody tr")[0].getAttribute("data-testid")
    expect(firstRowId()).toBe("hit-row-BM-4519")
    // click to flip to ascending → lowest score first (held BM-4541 sorts by 7.1)
    fireEvent.click(screen.getByTestId("hit-sort-score"))
    expect(firstRowId()).toBe("hit-row-BM-4541")
  })

  it("sorts a null-score (held) hit to the end, never coerced to 0", () => {
    // Regression: ChemicalView coerced a held/stub null score to 0, so an
    // unscored compound sorted as the worst real score (and FIRST when ascending).
    const hits: ChemHit[] = [
      { id: "NULL1", smiles: "C", score: null, confidence: "out-of-domain", herg: "—", drugLike: "—", verdict: "held" },
      { id: "LOW", smiles: "CC", score: 2.0, confidence: "low", herg: "1", drugLike: "1/4", verdict: "rejected" },
      { id: "HIGH", smiles: "CCC", score: 9.0, confidence: "high", herg: "9", drugLike: "4/4", verdict: "accepted" },
    ]
    render(<HitGrid hits={hits} />)
    const ids = () =>
      Array.from(screen.getByTestId("hit-table").querySelectorAll("tbody tr")).map(r =>
        r.getAttribute("data-testid"),
      )
    // default desc: real 9, 2, then unscored LAST
    expect(ids()).toEqual(["hit-row-HIGH", "hit-row-LOW", "hit-row-NULL1"])
    // ascending: real 2, 9, unscored STILL last (the 0-coercion bug put it FIRST)
    fireEvent.click(screen.getByTestId("hit-sort-score"))
    expect(ids()).toEqual(["hit-row-LOW", "hit-row-HIGH", "hit-row-NULL1"])
    // the unscored hit shows "held", not a fabricated 0
    expect(screen.getByTestId("hit-score-NULL1")).toHaveTextContent("held")
    expect(screen.getByTestId("hit-score-NULL1")).not.toHaveTextContent("0")
  })
})
