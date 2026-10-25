# Problem 2 — Entity-Aware Findings + Shared Provenance (Design brief)

**Date:** 2026-10-25. **For:** Claude Design. **Data contract:**
`20261025_FINDINGS_PROVENANCE_FRAMEWORK.md` (read first — the `FindingRecord` /
`FindingsDocument` schema is fixed; this brief asks only for the *visual primitive* that
renders it). Problem 2 of `20261023_UI_DESIGN_PROBLEMS_FOR_CLAUDE_DESIGN.md`; accepted
decisions in `20261024_CLAUDE_DESIGN_TAKEOVER.md`.

## What to design

**One reusable findings primitive** that renders a `FindingsDocument` (entity × metric
records + shared provenance) inside the existing after-run **Summary** area and/or
Findings surface — **not** an ADMET-specific screen, and **not** a new top-level tab.
Keep the v2 shell, the three after-run tabs (Summary / Outputs / Reproducibility record),
and the five evidence classes (Table / Figure / Structure / Report / Log). Design reusable
regions + states; the LLM/harness composes the actual content from the schema.

## Regions (what the primitive contains)

1. **Summary line** — the concise entity-aware sentence(s) (`FindingsDocument.summary`).
   This is also what the chat completion answer shows in trimmed form — keep them visually
   consistent (the chat version is already live and correct).
2. **Entity-grouped results** — the core. Records grouped by `entity` (one block/card/row-
   group per entity), each entity showing its metrics: `metric.name`, `value` (+ `units`,
   `comparator`), the `assessment.flag` (pass/liability/neutral) and a short interpretation.
   Collapsed by default when many entities; expandable. A single-entity run degrades to a
   flat list (no empty grouping chrome).
3. **Shared provenance footer** — the `provenance{}` map rendered **once**: the source
   file(s) + version, producer (tool/model + version), each linking to the full artifact in
   the **Outputs** tab via its evidence class. **Never** reprint a filename per row — rows
   reference provenance; the footer resolves it.
4. **Caveats + next steps** — existing treatment is fine; keep concise.

## States the primitive MUST cover

| State | Source field | Required visual treatment |
|---|---|---|
| Ready | `status:'ready'` | full grouped render |
| Generating | `status:'generating'` | "Analyzing outputs…" (resolves when ready; never on a failed run) |
| Unavailable | `status:'unavailable'` | static "Analysis not available — workflow did not complete" (no spinner) |
| Per-entity result | `entity.scope:'per_entity'` | attributed to the named entity (label + identifier) |
| Batch value | `entity.scope:'batch'` | shown as **batch-level**, explicitly not attributed to one entity (e.g. the hERG IC50 432.4246 µM) |
| Global/run metric | `entity.scope:'global'` | run-level (N50, resolution) — outside entity grouping |
| Unresolved identity | `identitySource:'unresolved'` | explicit "unattributed" chip — **never** a fabricated "Compound N" identity |
| Censored value | `metric.comparator` `<`/`>` | keep the inequality (`IC50 > 30 µM`), never coerced |
| Confidence | `metric.confidence` | value ± SEM/CI, or a prob/applicability/OOD chip |
| Flagged liability | `assessment.flag:'liability'` | distinct from `pass`; two-number (measured vs threshold) where a threshold exists |
| Missing metric for an entity | absent record | blank/"—", not a zero |

## Field → render map (per record)

`entity.label` (+ `identifier.scheme:value` as secondary) · `metric.name` · `metric.value`
`metric.units` `metric.comparator` · `metric.confidence` · `assessment.flag` (color) ·
`assessment.threshold` (the "vs X" comparison) · `assessment.interpretation` (one line, no
rejected boilerplate) · provenance via the shared footer (not inline per row).

## Acceptance examples (use these exact fixtures — invent no identities/values)

Three-compound ADMET run (`docs/qa/20261003-tutorial-release/{qc_metrics,toxicity_report}.json`):

- **aspirin** — DILI **0.855** (> 0.5 → liability), …
- **caffeine** — DILI **0.875** (> 0.5 → liability), hERG 0.115 (pass), oral-bioavail 0.936 (pass)
- **ibuprofen** — DILI **0.487** (< 0.5 → **pass**) — and a pass here is **not** an overall-safety conclusion
- **batch hERG IC50 432.4246 µM** — `scope:'batch'`, attributed to **no** named compound
- (demonstrate one `identitySource:'unresolved'` and one censored `IC50 > 30 µM` case)

## Deliverable

A concise **written component spec** + an **inspectable mockup**: regions, the field map,
every state above, token/color mapping (exact — color/font/space follow design), the
shared-provenance footer, and the acceptance examples rendered. State which fields exist
today vs which backend contract is pending (agree with engineering before depicting an
action). Not a generalized production renderer until the schema lands — so no hardcoded
compounds, no per-workflow layouts.

## Fixed (do not change)

Three after-run tabs; five evidence classes; one owner per control; chat stays concise
(full detail lives here, not in extra chat cards); no new top-level tabs; persistent file
identity/version in provenance.
