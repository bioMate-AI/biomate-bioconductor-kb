# Findings + QC simplification — design (the refactor that stops the bug class)

Date 2026-11-05. The audit sweep fixed 18+15 instances of a bug class; this is the architectural
change that stops the class recurring. **Design, not applied** — it is behavioral + consumer-
migrating and should be executed as its own focused session, not blind-refactored at the tail of
the audit session. Premises here are verified against current code + live dev (correcting two
agent claims that turned out false).

## Verified current architecture (not the agent's version)

### Findings — TWO independently-computed verdicts + a reconciler
1. **Flat** `{summary, key_results}` — from EITHER a deterministic parser (`preProcessForFindings`
   → `_parseAdmetOutput` / `_parseDeseq2Output` / `_parseEnrichGoOutput` / `_parseRarediseaseOutput`)
   OR the LLM fallback. **This is the PRIMARY UI source** — `findings-card.tsx:218` and
   `AfterRunReport.tsx:2654` render `data.key_results`.
2. **`findings_document`** — entity-aware, from `buildFindingsDocument(matchDescriptor(...))` over
   `findings-descriptors.ts`. An ADDITIVE layer for the newer per-entity renderer.
3. **`reconcileFindingsDocument`** — arbitrates (1) vs (2) when their liability sets disagree (now,
   post audit-S3#1, document-primary when the flat is LLM-sourced).
Plus an on-demand in-memory `_findingsCache` (per-worker) + a persisted S3 `findings_data.json`
sidecar.

**Corrected premises:** `_parseAdmetOutput` is NOT dead — verified live (`deterministic parse
succeeded for "Predict ADMET Properties"`, 9 key_results). And the dual-verdict is real: for ADMET,
the flat (parser) AND the document (ADMET_REPORT descriptor) BOTH compute the verdict from the same
`toxicity_report.json`, then get reconciled. That redundancy is the complexity, not a dead path.

### QC — TWO metric-extraction paths that can diverge
- **Live in-process:** `qc_trace_monitor.py` reads `herg_inhibition_prob`, etc.
- **Completion/S3:** `nextflow_executor.py:_extract` (4741) copies a FIXED key list that OMITS
  `herg_inhibition_prob` (audit S2#2) → the two paths evaluate different gates on the same run.

## Why this produces the bug class
- Two verdicts computed independently + a referee → they can disagree; the referee itself had a bug
  (S3#1). A referee exists only because there are two sources.
- Two QC key lists that must stay in lockstep → they drifted (hERG).
- Heuristic-seeded aggregates with a conditional override (DILI, BOIN, phase2, repeated-tox) → a
  missing `else`/`or`-default silently keeps a wrong value.

## Target — one source of truth per verdict

### Findings: compute once (structured), PROJECT the flat
- A single structured verdict per run = the entity-aware document (it already carries per-entity
  metrics + thresholds + per-compound provenance). Deterministic parsers feed the DOCUMENT, not a
  parallel flat.
- The flat `{summary, key_results}` the UI reads becomes a **pure projection** of the document
  (flatten records → key_results; derive summary from the document's liabilities). One computation,
  one projection → **the reconciler is deleted** (nothing to reconcile).
- The LLM is used ONLY for narrative prose (an optional `summary` embellishment), NEVER to compute
  the verdict or key_results — removing the "LLM says no liabilities" clobber class entirely and
  the response-contract/echo fragility (audit #5a-D).
- Net deletions: `reconcileFindingsDocument` + `flatLiabilities`; the parallel flat parsers either
  feed the document or are retired once the descriptors cover their domains (keep whichever is
  more complete per domain — DESeq2/variant descriptors already exist).

### QC: one shared metric-extraction
- Extract metrics with ONE function used by both the live and completion paths (a single canonical
  key list), so a prob-only hERG (or any future metric) is evaluated identically everywhere. This
  is the structural version of the audit B2 patch.

### Aggregates: pure function of per-entity values
- No heuristic seed + conditional override. Compute every aggregate as `bucket(worst_over(per_entity))`
  via ONE bucketer (the DILI-fix pattern), so there is no stale default a later step must remember
  to overwrite. Applies to DILI, the BOIN/phase2 dose selection (≤ MTD), repeated-tox margin.

## Migration (incremental, each step gated + deployable)
1. Add the flat-from-document projection behind a flag; assert projection == current flat on the 4
   parser domains (ADMET/DE/enrichGO/raredisease) in tests. (no behavior change yet)
2. Switch the UI consumers (`findings-card`, `AfterRunReport`) to the projected flat; keep the old
   flat as a shadow and log any divergence on live runs for one cycle.
3. Delete the reconciler + `flatLiabilities` + the independent flat computation once shadow shows
   zero divergence.
4. QC: extract the shared key list; make `_extract` call it; delete the duplicate list.
5. Aggregates: apply the DILI-bucketer pattern uniformly (this overlaps the C review patches —
   do them as part of this, not twice).

## Decisions that are yours (not mine to pick)
- **Source of truth = the entity-aware document?** (recommended — it has thresholds + provenance)
  or keep the flat and derive the document? Picking the document means migrating the main UI to a
  projection; picking the flat means the per-entity renderer loses its native source.
- **Retire the deterministic parsers, or keep them as the document's feeders?** (They work; the
  question is whether the descriptors fully cover each domain.)
- **LLM-for-prose-only** — confirm the LLM should never influence the verdict (recommended, given
  the echo/no-liabilities failures).

## Risk / what to verify
- The flat projection must reproduce today's key_results for the 4 parser domains EXACTLY before
  cutover (step 1 assertion) — else the main FindingsCard regresses.
- Shadow-logging (step 2) catches any divergence on real runs before deletion.
- QC extraction consolidation must not drop a key any current consumer reads — diff the two lists
  first.

**Recommendation:** execute as a focused session using this plan; steps 1–2 are safe (additive +
shadow), step 3+ delete only after zero-divergence is shown. Do NOT delete the reconciler or a
parser before the projection is proven equal. This is the change that converts today's "more
correct" into "structurally can't be wrong this way again."
