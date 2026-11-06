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

## SHADOW EVIDENCE (live on dev, 2026-11-05) — CUTOVER BLOCKED for ADMET
Step 2 shadow deployed (commit 3f40e7cf7) and exercised on the ADMET run 82c1245a. Dev log:
```
[Findings][shadow] documentToLegacy vs parser flat for "Predict ADMET Properties (AI)":
  parser-only=[hERG inhibition, DILI probability, Oral bioavailability, BBB penetration, ClinTox,
               Plasma protein bind %, Caco-2 logPapp, CYP2D6 inhibitor, CYP3A4 substrate]
  doc-only=[logP]  — cutover pending
```
**The document projection produced only `logP` — it is MISSING all 9 of the parser's ADMET metrics,
including every liability (hERG, DILI, CYP2D6).** A blind cutover would have collapsed ADMET
findings to a single lipophilicity number and hidden the safety liabilities. The shadow caught this
with zero user impact (returned flat unchanged) — the exact reason for shadow-before-switch.

### Revised gate
- **Do NOT cut over** the ADMET flat to `documentToLegacy`. The ADMET_REPORT descriptor, on this
  run's sampled output shape, is not extracting the `per_compound_admet_ai` metrics (it got only
  the RDKit `logP`). Root cause to fix FIRST: the document must read the same structured block
  (`toxicity_report.json` → `per_compound_admet_ai[]`) the parser reads, so the projection reaches
  parser parity. Only then does step 3 (cutover + reconciler deletion) become safe.
- This empirically **vindicates keeping the deterministic parser** — for ADMET it is currently the
  MORE complete source (contradicts the S3#6 "dead parser" claim).
- Repeat the shadow check per domain (DESeq2 / enrichGO / raredisease) before any per-domain
  cutover — each may differ. The shadow log is the gate; `cutover-ready` (matching key set) is the
  only green light.

**Net:** the simplification direction stands (document-as-truth, delete the reconciler), but the
work is now clearly: **bring the descriptors to parser parity (shadow → cutover-ready) BEFORE
deleting anything.** The shadow turned a risky guess into a measured, safe, incremental path.

## ROOT CAUSE of the ADMET parity gap (2026-11-05 investigation) — it's the 8 KB sampling truncation, not the descriptor
Traced it: the ADMET_REPORT descriptor logic is CORRECT — `parseEntities` MERGES
`per_compound_admet_ai[]` (hERG_prob/DILI_prob/cyp2d6) with `per_compound[]` (logP/mw) by SMILES
(verified by the `merges per_compound heuristics alongside the AI probabilities` test). So on a
complete `toxicity_report.json` the document WOULD reach parity. The shadow logged `doc-only=[logP]`
because both the parser and the descriptor read `outputSamples`, which are **truncated to 8 KB**
(`routes.ts:~15828`). The parser's source (the compact `*_output.txt` key:value dump) fits all 9 AI
values in 8 KB; the descriptor's source (the verbose `toxicity_report.json`) is cut before/within
its `per_compound_admet_ai` array → the descriptor only sees the earlier `per_compound` (logP).
**Same root cause as committee Opus-1** (the variant preview-count reporting a truncated total).

### The unblocking fix (one change, two payoffs) — do this BEFORE the cutover
Decouple the **parse-source** from the **LLM-context**: read the FULL structured output file for the
deterministic parser AND the descriptor (so both see the complete `per_compound_admet_ai` and
accurate per-row counts), while keeping an 8 KB-bounded slice only for the LLM narrative context
(token budget). Fixes the Opus-1 preview-count at its root. **SHIPPED** (commit 3f33f4b6e, 1 MB cap
+ early-break). It touches the LLM context budget, so it was gated + will be committee-reviewed.

### ⚠️ CORRECTION (2026-11-05, after shipping the decouple + re-running the shadow)
**The 8 KB truncation was NOT the ADMET parity cause — hypothesis DISPROVEN by the shadow.** Probed
run `82c1245a`'s actual `toxicity_report.json`: it is **1,672 bytes** (never truncated) and CONTAINS
the full `per_compound_admet_ai` block. Then ran the DEPLOYED descriptor code locally on that real
file: `matchDescriptor` → `admet_report`, one merged entity, and **`documentToLegacy` extracts all 16
metrics** (hERG inhibition, DILI probability, CYP2D6, Oral bioavailability, ClinTox, CYP3A4, BBB,
PPB, Caco-2, hERG IC50, logP, MW, DILI risk + 3 panel) — **FULL parser parity.** So the descriptor +
projection are CORRECT; the document-as-truth projection works for ADMET at the code level.
- The one dev shadow line still showing `doc-only=[logP]` was logged at `20:37:40 UTC`, ~25 s after
  the decouple "Sync OK" (20:37:15 UTC) — i.e. at the container-swap boundary, almost certainly an
  in-flight request still on the old 8 KB container (or a per-run sampling artifact). I could not get
  a clean post-settle dev regen (cached ADMET runs don't regenerate; cancelled runs have no outputs).
- **Lesson (again):** the shadow did its job — it stopped me believing the decouple "fixed" parity
  when the real file disproved the premise. The decouple is still a valid, shipped improvement
  (large structured files, honest variant counts), just not the ADMET-parity fix it was hypothesized
  to be.

### Status of the cutover
**Code-proven safe for ADMET** (local repro: projection = 16 metrics = parser parity). Remaining
before the actual cutover (wire `documentToLegacy` as the flat source + delete the reconciler): one
CLEAN dev shadow confirmation on a freshly-regenerating ADMET run (should log `cutover-ready`), and
the per-domain shadow checks for DESeq2 / enrichGO / raredisease. Then steps 3–5 of the migration.

## PER-DOMAIN PARITY — COMPLETE for all 4 parser domains (2026-11-05, local repro on real output)
Ran the DEPLOYED descriptor code (`matchDescriptor` → `buildFindingsDocument` → `documentToLegacy`)
on real/representative output for every parser domain. Harnesses:
`scratchpad/parity.mts` (enrichGO on dev `enrich_results.csv`), `parity_var2.mts` (variant, snpeff-
shaped), plus the earlier ADMET (`toxicity_report.json`) and DESeq2 (`de_results.tsv`/`.csv`) repros.

| Domain | Parser today | documentToLegacy result | Parity verdict |
|---|---|---|---|
| **ADMET** | deterministic flat (`_parseAdmetOutput`, 9–16 key_results) | 16 metrics incl. every liability (hERG, DILI, CYP2D6) | **= parser** (code-proven) |
| **DESeq2** | deterministic flat (`_parseDeseq2Output`) | TSV→32 real ENSG ids; CSV→real ENSG ids (post autodelim+col-0 fix `84577b8e1`) | **= parser** (code-proven) |
| **enrichGO** | **LLM context only** (`_parseEnrichGoOutput` returns `{context,numbers}`, no flat) | 12 GO terms, real p.adjust/GeneRatio/Count, term names as entities | **upgrade** (deterministic vs LLM prose) |
| **variant/raredisease** | **LLM context only** (`_parseRarediseaseOutput`, no flat) | exact IMPACT buckets: HIGH→liability, MODERATE→neutral, LOW/MODIFIER→pass (S3#4 MODIFIER≠MODERATE holds) | **upgrade** (deterministic vs LLM prose) |

### Key structural finding (refines the cutover plan)
The SHADOW comparison (`routes.ts:16008`) only runs inside `if (preprocessed?.findings)` — i.e. ONLY
for ADMET + DESeq2 (the domains with a deterministic flat). enrichGO + raredisease have **no parser
flat at all** (their parsers feed the LLM a context string); today's UI flat for them is LLM-derived.
So the cutover splits into two risk classes:
- **enrichGO + raredisease — LOW RISK:** wiring `documentToLegacy` as the flat is a pure UPGRADE
  (deterministic structured records replace LLM prose). Nothing to regress against; no shadow needed.
  Code-proven correct above.
- **ADMET + DESeq2 — GATED:** these render a deterministic parser flat today. The cutover must match
  it. Code-level repro shows parity, but the live shadow is the project's gate and it only re-fires on
  a FRESH run (findings are cached in the S3 sidecar + in-memory `_findingsCache`; there is no
  `?regen` hook, so cached runs never re-emit the shadow line). The one dev shadow line captured so
  far was a deploy-boundary artifact (see correction above).

### Remaining before the destructive cutover (reconciler deletion + rewire) — NOT done here
1. Capture a clean `cutover-ready` shadow line for ADMET and for DESeq2 on a FRESH run each (or add a
   tiny read-only `?regen=1` cache-invalidation hook purely for this observability — a reviewable 1-
   line change, not the behavioral cutover itself).
2. Only then: wire `documentToLegacy` as the flat source and delete `reconcileFindingsDocument` +
   `flatLiabilities`. This is the committee-worthy behavioral change the design reserves for a focused
   session — it is deliberately NOT applied at the tail of the audit work.

**Status:** per-domain parity gate = **CLEARED (code-proven, all 4)**. Cutover gate = **one clean live
shadow for ADMET + DESeq2** (structurally blocked on a fresh run / a regen hook), then the focused
reconciler-deletion session. The reconciler remains a useful safety net until then (no-op when the
sets agree, which parity now makes the steady state).

## ⚠️⚠️ CORRECTION #2 (2026-11-05, later) — the ADMET parity gap was REAL, not an artifact
The earlier correction above (lines ~145-166) was WRONG on two counts, now disproven by a clean live
shadow + full-output repro:
1. The dev `doc-only=[logP]` line was **NOT a deploy-boundary artifact.** After adding the read-only
   `?regen=1` hook (commit `5a8bf2184`) I forced a clean, post-settle regen of ADMET run `331245f4`
   and the shadow re-logged **exactly** `parser-only=[hERG inhibition, DILI probability, …(9)] doc-only=[logP]`.
   Reproducible, not a race.
2. "Code-proven safe for ADMET (16 metrics)" was an **artifact of my repro feeding only
   toxicity_report.json.** A real ADMET run emits SEVEN files. Reproducing matchDescriptor on the full
   set showed it selected **pk_summary.json** (a PK sibling that also has a `per_compound` array with
   RDKit logP) — NOT toxicity_report.json — because ADMET_REPORT's `contentIncludes:['per_compound']`
   was too generic and matchDescriptor returned the FIRST file hitting any signal. → the ADMET
   document collapsed to a single `logP`, losing every liability.

**Root-cause fix shipped (commit `466893371`):**
- ADMET_REPORT.contentIncludes → `['per_compound_admet_ai']` (the AI block is the toxicity report's
  distinctive marker; a legacy per_compound-only report still matches via FILENAME).
- matchDescriptor now SCORES candidates (filename+content=4 > content=3 > filename=2 > wf-name=1) and
  picks the best per descriptor — a data-carrying file beats a name-only wrapper or a generic sibling.
- +3 regression tests (multi-file selection). Re-ran the full-output repro: now matches
  toxicity_report.json → **16 metrics incl. hERG/DILI/CYP2D6** (true parser parity). tsc + vitest green.

### Lessons
- **The shadow was RIGHT the whole time.** I twice talked myself out of believing it (first "8KB
  truncation", then "deploy artifact"). A repro that doesn't feed the descriptor the SAME multi-file
  input the server sees is not a repro. Always reproduce on the full `outputSamples` set.
- This is a second independent benefit of document-as-truth shadowing: it surfaced a live bug in the
  entity-aware `findings_document` (wrong file → logP-only) that the parser flat masked on the main
  card. That document bug existed in production and is now fixed regardless of the cutover.

### Revised cutover status (supersedes the "code-proven safe" line above)
- **ADMET descriptor parity:** now genuinely fixed at the code level AND must be re-confirmed by a
  CLEAN live shadow (`?regen=1` on `331245f4` after deploying `466893371`) showing `cutover-ready`.
- Until that clean `cutover-ready` line is observed on dev, the ADMET cutover stays BLOCKED. The other
  domains: DESeq2 needs a completed run on dev (only failed ones exist now) to live-shadow; enrichGO +
  raredisease have no parser flat (pure upgrade, no shadow needed).
- The destructive reconciler-deletion cutover remains reserved for its own committee-reviewed session.

## ✅ CLEAN LIVE SHADOW — ADMET is now cutover-safe (2026-11-05, after deploying 466893371)
Deployed the matchDescriptor fix to dev and forced a clean regen (`?regen=1`) of ADMET run
`331245f4`. The shadow now logs:
```
[Findings][shadow] documentToLegacy vs parser flat for "Predict ADMET Properties (AI)":
  parser-only=[] doc-only=[hERG IC50, logP, MW, DILI risk, hERG IC50 (panel),
                           DILI probability (panel), Ames probability (panel)]
```
- **parser-only=[]** — the projection now covers EVERY parser metric, including all 9 liabilities
  (hERG inhibition, DILI probability, CYP2D6, …). The pre-fix BLOCKED state (`parser-only=[9]`,
  `doc-only=[logP]`) is gone.
- **doc-only=[7]** — the document ADDS the RDKit per_compound heuristics (hERG IC50 µM, logP, MW,
  DILI risk tier) and the batch panel aggregates (panel hERG IC50 / DILI / Ames). These are
  enrichment the flat never carried — not a regression.
- Refined the shadow log (commit on this branch) to classify this correctly: `parser-only=[]` with
  doc extras ⇒ **cutover-safe (document is a superset)**, distinct from `cutover-ready` (exact match)
  and `cutover BLOCKED` (parser-only non-empty).

### Where the cutover stands now (per domain)
| Domain | Code parity | Live shadow | Gate |
|---|---|---|---|
| **ADMET** | fixed (16 metrics, real 7-file set) | **cutover-safe** (parser-only=[], doc superset) | ✅ met |
| **DESeq2** | code-proven (32 real ENSG ids) | pending — only FAILED deseq2 runs on dev; needs a completed run | ⏳ run-blocked |
| **enrichGO** | code-proven (12 GO terms) | n/a — parser emits no flat (pure upgrade) | ✅ no gate |
| **raredisease/variant** | code-proven (exact IMPACT buckets) | n/a — parser emits no flat (pure upgrade) | ✅ no gate |

### Remaining before the destructive cutover (its own committee session)
1. One completed DESeq2 run on dev to live-shadow it to `cutover-safe`/`cutover-ready` (code already
   proven; this is just the live confirmation the discipline asks for).
2. The cutover itself — wire `documentToLegacy` as the flat source + delete `reconcileFindingsDocument`
   + `flatLiabilities`. NOTE for that session: the projection must preserve the flat's liability
   MARKER contract — the UI/`flatLiabilities` detect a liability via the interpretation suffix
   "— potential liability"; `documentToLegacy` currently emits the document's own assessment strings,
   so the cutover must either keep emitting that marker or migrate every consumer to read
   `assessment.flag`. This is the main non-trivial piece and why the cutover is a focused change, not
   a tail-of-session refactor.
