# Per-workflow UI dev-vs-design conformance (30 run objects) — 2026-10-28

Design ground truth = the prototype run objects (`reference/claude_design/tutorials_v2/_ui`
+ run data files) and the `data_centroid_design_v2/spec` worked examples. Dev = the live
renderers (`findings-card.tsx`, `step-output-preview.tsx`, `AfterRunReport.tsx`,
`v2/blocks/*`, `viewers/*`). Verdict per workflow: MATCH / DEVIATION / PLACEHOLDER(design) /
MISSING(dev).

## CORRECTION (2026-10-28) — the "chart gap" was over-framed
The "DEVIATION" rows below (t3 volcano, plate 4PL, d7 stability, d1 scatter) are **not missing
visualization**: the backend **produces the real plot** (`volcano_plot.png`, dose-curve `.svg`,
etc.) and dev **shows it inline** via `InlineImageViewer` (`step-output-preview.tsx:818`). The
user sees the plot — as a produced image, not a data-driven interactive chart. So the only real
difference is **static image vs. interactive chart** (a fidelity nuance), NOT a capability gap.
BioMate's file viz is strong (3D structures, density maps, VCF, sequences, PAE/pLDDT, FSC). We
did **not** build redundant inline chart primitives.
The ONE genuinely-unleveraged thing was the dataset-object **Plot** tab (`dataset-object.tsx`),
a `*-future` stub claiming "no plot data from the profiler" — but `profile.sampleRows` WAS
already fetched (the Table tab uses it). **Fixed:** `dataset-sample-plot.tsx` charts numeric
columns from those existing sample rows (histogram, selectable), honestly labelled as the N-row
sample, Jupyter/chat fallback for non-numeric. Frontend-only; leverages existing data.

## Bottom line
- **~80% conform (MATCH).** The universal **per-entity findings table** (verdict + entity×metric
  table + provenance) is 1:1 between `findings.js` and `findings-card.tsx`, and covers d2, d3,
  d4, d6, somatic, nanopore, lcms, advprot, flow, qc, micro, tid, qpcr, drugdev, b1. Ranked
  tables (d1/d3/rbboin/rbrt/tid), image/structure/sequence/VCF (d5 3Dmol, cryoem DensityMap+FSC,
  micro, somatic/nanopore VCF), and the QC gate two-number (pq, qc) all map cleanly — dev is
  often *richer* than the design's placeholder (3Dmol pose; cryo-EM FSC/motion/CTF charts).
- **The conformance gap is concentrated in statistical FIGURES.** Dev's figure vocabulary is
  frozen at **bars | composition | qc** (`v2/blocks/types.ts:32`, `AfterRunReport.tsx:669-673`;
  a generative `figure` block renders only a text label, `BlockRenderer.tsx:104-113`). So every
  *computed* chart in design degrades to a table or a **static PNG/SVG image**.

## Real DEVIATIONS (design computes a chart; dev has no equivalent → table / static image)
| id | design chart | dev |
|---|---|---|
| **t3** | **volcano** (data-driven SVG, inlined in summary) | table + static png — the headline DE case |
| **plate** | **4PL dose-response curve** (pts + fit + IC50 ref) | fit table + static svg |
| **d1** | **pred-vs-measured scatter + applicability-domain ellipse** | ranked table + static svg |
| **d7** | **projected-potency (stability) curves** | table + static image |
| drugdev, b1, m3 | **callout** block | no dev primitive (explicitly unbuilt, `BlockRenderer.tsx:115-123`, flagged `data-design-primitive="needed"`) |

## MISSING in dev (no renderer; also absent/placeholder in design)
- **m3 plan/chain card** (accession→4-workflow chain) — design shows it as phases A–D; dev has no
  accession plan-chain component.
- **Loop remediation diff** (`plat:5`/`plat:6`) — prototype-only (`dataui/Loops.jsx`); not a run
  object; no dev renderer.
- **BOIN decision matrix** (rbboin) — generic table in both (no distinctive renderer either side).

## NOT regressions (design placeholder → dev parity)
m2 & lcms volcano (design doesn't inline — png output / none authored), s4 **KM** (pdf artifact, no
inline in design), flow gate plots, qpcr rel-expr plot, s1/s2/pf (results are design placeholders).
Caveat: dev *also* has no renderer for volcano / 4PL / KM / generic heatmap, so if design promotes
these, there's nothing to adopt.

## Chart-renderer inventory in dev (grepped exhaustively)
- Findings figures: `FigBars`/`FigComposition`/`FigQc` only.
- Cryo-EM trio `FscCurveChart`/`MotionHistogramChart`/`CtfQualityChart` — **filename-gated to
  cryoSPARC**, not reused.
- DL-inference: `PlddtChart` (line), `PaeHeatmap` (AlphaFold/Boltz PAE only — not a generic
  heatmap), `SeqTracks`, `HitGrid`.
- **No renderer anywhere for: dose-response/4PL, volcano, survival KM, generic heatmap.**

## Recommended fixes (to close the conformance gap) — priority order
1. **Add figure primitives** to the findings/figure path + the `Block` `figure` catalog:
   `scatter` (d1, generic), `curve` (4PL dose-response — plate/d7, + confidence band), `volcano`
   (t3/lcms), and `applicability-domain` (d1). These are the 4 computed charts design already
   specifies. ~1 chart component each (reuse `ui/chart.tsx`/Recharts), + a `BlockFigureKind`
   extension + dispatch.
2. **Add the `callout` primitive** (drugdev/b1/m3) — currently renders nothing.
3. **Plan/chain card** for m3 (accession→workflow) — a phases-as-chain card.
4. KM + BOIN-decision-matrix are lower priority (design placeholders), but worth a generic
   `survival`/`decision-table` renderer if those domains are promoted.

## Full per-workflow table
(See the conformance run; abbreviated — MATCH unless noted)
MATCH: qpcr, pq, d2, d3, d4, d5, d6, b1, m2, somatic, nanopore, lcms, advprot, flow, qc, cryoem,
micro, tid, rbrt, rbboin(dose table).
DEVIATION (figure gap): d1, d7, t3, plate, drugdev(callout).
MISSING(dev): m3(plan-chain), loops(diff).
PLACEHOLDER(design, not a regression): s1, s2, pf, s4(KM), m2/lcms(volcano), flow(gate plot).
