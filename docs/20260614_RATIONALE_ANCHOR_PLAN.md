# Bioconductor `(why?)` Rationale Anchor — Phased Implementation Plan

**Branch target:** `bioc/v2-qc-audit-panel` (current worktree is on
`qc/coverage-and-rebuilds` — rebase/cherry-pick the plan commit onto the
target branch before further work).
**Effort estimate:** ≤2 engineer-weeks total (1 BE, 1 FE, overlapping).
**Date:** 2026-06-14
**Scope:** ship the hoverable `(why?)` anchor that opens a curated
4-section popover ("Why this method · Live events · Parameters · Cost")
on every Bioconductor chat line, sourced from already-populated
backend data — no LLM generation, no new prose.

---

## 0. Source-of-truth inventory (cited)

| Source | What it gives us |
|---|---|
| `backend/config/qc_evidence.yaml:963–1032` (transcriptomics) | 5 gates: deseq2_negative_binomial_fit, apeglm_lfc_shrinkage, clusterprofiler_enrichment, edger_qlf_alternative, limma_voom_alternative — each with `paper_ref`, `paper_doi`, `paper_supports`, `rule_text` |
| `backend/config/qc_evidence.yaml:1034–1135` (single_cell) | 7 gates: scater_qc_normalization (1035), mast_hurdle_de (1048), monocle_pseudotime_de (1062), scran_normalization_hvg (1077), score_markers_per_cluster (1091), singler_celltype_annotation (1105), pseudobulk_aggregation_deseq2 (1119) |
| `backend/config/qc_evidence.yaml:1137–1191` (epigenomics) | 4 gates: minfi_array_processing (1138), limma_dmp_test (1152), dmrcate_region_call (1164), missmethyl_cpg_corrected_go (1178) |
| `reference/claude_design/src/BiocTours.jsx:101–188` (bioc-kb-routing) | Per-phase callout `body` prose for the 6-phase bulk DESeq2 chain |
| `reference/claude_design/src/BiocTours.jsx:193–268` (bioc-sc-routing) | Per-phase callout `body` prose for the 7-phase scRNA OSCA pseudobulk chain |
| `reference/claude_design/src/BiocTours.jsx:273–348` (bioc-methyl-routing) | Per-phase callout `body` prose for the 5-phase 450k methylation chain |
| `reference/claude_design/src/ChatStream.jsx:45–83,110–114` | Canonical popover data shape: `{ text, cite: { title, doi } }`; anchor class `why-anchor`; `rationaleId` keys the lookup |
| `frontend/client/src/components/ui/popover.tsx:8–29` | Radix `Popover`, `PopoverTrigger`, `PopoverContent` are exported and reusable (no new primitive needed) |
| `backend/lib/galaxy/ai/bioc_chain_templates.py:29–291` | Authoritative chain names + step `role` + `params_template` for the 4 chains we target — Wave 1 anchors |
| `backend/scripts/add_scrna_pseudobulk_chain.py:27` | `scrna_pseudobulk_de_bioc` inserted into `workflow_chains`; id printed at run-time (memory note: id 60) |
| `backend/scripts/differentiate_ambiguous_chains.py:8–46` | Disambig text for `bulk_rnaseq_de_analysis` vs `bulk_rnaseq_consensus_de_bioc` — used by the `(why this not that?)` micro-section if added later |

**Open verification (pre-implementation, 30 min):** the script
`backend/scripts/pin_bioc_chain_workflow_ids.py` referenced in the task
brief **does not exist in the tree** today. The four chain
workflow_ids must instead be looked up at population time via a
`SELECT id FROM workflow_chains WHERE name = ?` against
`backend/database/galaxy_ai_tools.db` (the canonical chain name lives
in `bioc_chain_templates.py` for the v2 chains; the
non-v2 chains `bulk_rnaseq_consensus_de_bioc`,
`scrna_consensus_de_bioc`, `methylation_450k_array_analysis` are
referenced by name in `qc_evidence.yaml:956–958`). The migration
script in §5 below uses this lookup pattern so a missing pin script is
a non-blocker.

---

## 1. Schema

New table in `backend/database/galaxy_ai_tools.db`:

```sql
CREATE TABLE IF NOT EXISTS workflow_phase_rationale (
  workflow_id      INTEGER NOT NULL,
  phase_id         TEXT    NOT NULL,   -- e.g. "A", "B", ... or "qc", "de", "enrich"
  rationale_text   TEXT    NOT NULL,   -- curated prose, plain text (no JSX)
  citation_doi     TEXT,               -- nullable: gates without a DOI still allowed
  citation_title   TEXT,               -- short paper_ref string for tooltip footer
  qc_gate_name     TEXT,               -- nullable: qc_evidence.yaml gate key linkage
  last_curated_at  INTEGER NOT NULL,   -- unix epoch seconds; bumps on every re-populate
  PRIMARY KEY (workflow_id, phase_id)
);
CREATE INDEX IF NOT EXISTS idx_wpr_workflow ON workflow_phase_rationale(workflow_id);
```

**FK discussion:** SQLite FOREIGN KEYs in this DB are advisory (PRAGMA
foreign_keys is OFF by default in the BioMate Galaxy connection — see
existing `workflow_chains` table, no FK there either). We therefore
mirror the existing convention: `workflow_id` references
`workflow_chains.id` (chain rows) **or** `workflows.id` (individual
nf-core workflows) by integer value but no `REFERENCES` clause. The
population script resolves IDs once at insert time; if a chain is
deleted, the rationale row is orphaned but harmless (endpoint returns
404). A future cleanup job can `DELETE WHERE workflow_id NOT IN
(SELECT id FROM workflow_chains UNION SELECT id FROM workflows)`.

**Why a separate table rather than a column on `workflow_chains`:**
phase-keyed (one row per phase per chain), and we want to extend to
non-chain nf-core workflows in week 3 without altering an existing
schema-stable table.

---

## 2. Curation source mapping (no new prose — quotes only)

Row count estimate: **6 + 7 + 5 + 6 = 24 rows** across the 4 chains
(matches "6 phases × 4 chains ≈ 24" sizing).

### Chain 1 — `bulk_rnaseq_consensus_de_bioc` (transcriptomics, 6 phases)

| phase_id | rationale_text source (quote) | citation source (qc_evidence gate) |
|---|---|---|
| A_qc | `BiocTours.jsx:135` body — *"Execution starts and the active phase auto-expands. `edgeR::filterByExpr` drops genes under 10 counts; as each step finishes its parameters and output files appear inline."* | none (QC filter has no paper) |
| B_norm | `BiocTours.jsx:141` body — *"After normalisation, counts + metadata + size factors fold into a single `DESeqDataSet`. That object class is the contract every downstream DESeq2 step reads from."* | `deseq2_negative_binomial_fit` (`qc_evidence.yaml:964`) → Love 2014 / `10.1186/s13059-014-0550-8` |
| C_de | `BiocTours.jsx:147` body — *"The Wald test runs on design `~ condition` — **2,841 genes** at FDR < 0.05 — producing a `DESeqResults` table of log₂FC, p-adj and baseMean per gene."* | `deseq2_negative_binomial_fit` (`qc_evidence.yaml:964`) |
| D_shrink | `BiocTours.jsx:153` body — *"Before ranking, `apeglm` shrinks low-count fold-changes toward zero, so the gene list feeding enrichment isn't dominated by noisy extremes."* | `apeglm_lfc_shrinkage` (`qc_evidence.yaml:979`) → Zhu 2019 / `10.1093/bioinformatics/bty895` |
| E_enrich | `BiocTours.jsx:159` body — *"clusterProfiler `gseGO` runs on the shrunk, ranked list — top GO term *regulation of apoptotic process*. Phase F then renders the volcano, dotplot and heatmap."* | `clusterprofiler_enrichment` (`qc_evidence.yaml:992`) → Yu 2012 / `10.1089/omi.2012.0118` |
| F_viz | `BiocTours.jsx:166` previewBody — *"Clicking **view** on `volcano.png` renders it inline — log₂ fold-change vs −log₁₀ p.adj, up genes in red, down in blue, cutoff lines drawn."* | none (visualisation step) |

### Chain 2 — `scrna_consensus_de_bioc` (single_cell, 7 phases)

| phase_id | rationale_text source | citation gate |
|---|---|---|
| A_qc | `BiocTours.jsx:215` body — *"`emptyDrops` separates real cells from ambient barcodes, then `perCellQCMetrics` flags high-mito / low-count cells — **9,814 of 12,402** retained."* | `scater_qc_normalization` (`qc_evidence.yaml:1035`) → McCarthy 2017 / `10.1093/bioinformatics/btw777` |
| B_norm | `BiocTours.jsx:221` body — *"QC + normalisation fold into a single `SingleCellExperiment` carrying counts, logcounts, metadata and size factors. Every step below — including pseudobulk DESeq2 — reads from this one object."* | `scran_normalization_hvg` (`qc_evidence.yaml:1077`) — Lun 2016 |
| C_cluster | `BiocTours.jsx:227` body — *"Normalisation, HVG selection + PCA, and graph-based clustering (`buildSNNGraph` + Louvain) are complete — **11 clusters**, with a UMAP for visualisation only."* | `scran_normalization_hvg` (`qc_evidence.yaml:1077`) |
| D_markers | `BiocTours.jsx:233` body — *"Phases E and F open together: `scoreMarkers` and `SingleR` (vs the Human Primary Cell Atlas) both read the clustered object, so the engine fans them out and tracks the join."* | `score_markers_per_cluster` (`qc_evidence.yaml:1091`) |
| E_annotate | `BiocTours.jsx:233` body (same parallel-branch callout, annotation arm) | `singler_celltype_annotation` (`qc_evidence.yaml:1105`) → Aran 2019 / `10.1038/s41590-018-0276-y` |
| F_pseudobulk_de | `BiocTours.jsx:239` body — *"the **QC** block flags the trap — testing thousands of cells as replicates is **pseudoreplication** — and the **AGENT** block gives the fix: aggregate to pseudobulk so the 6 samples are the real replicates, then DESeq2 per cell type."* | `pseudobulk_aggregation_deseq2` (`qc_evidence.yaml:1119`) → Crowell 2020 / `10.1038/s41467-020-19894-4` |
| G_report | `BiocTours.jsx:248` completeBody — *"All seven phases done — routed to OSCA, clustered, annotated in parallel, then pseudobulk DE. CD8⁺ T cells are the strongest responder (214 DE genes on true replicates)."* | none |

### Chain 3 — `methylation_450k_array_analysis` (epigenomics, 5 phases)

| phase_id | rationale_text source | citation gate |
|---|---|---|
| A_read | `BiocTours.jsx:295` body — *"`minfi::read.metharray.exp` reads the IDAT pairs into a `MethylSet` — raw methylated + unmethylated intensities, 450k probes × 24 samples."* | `minfi_array_processing` (`qc_evidence.yaml:1138`) → Aryee 2014 / `10.1093/bioinformatics/btu049` |
| B_qc_norm | `BiocTours.jsx:301` body — *"After QC + normalisation the object is a `GenomicRatioSet`: β-values *with* each probe's genomic coordinate. That GRanges backbone is what lets the next step collapse CpGs into regions."* | `minfi_array_processing` (`qc_evidence.yaml:1138`) |
| C_dmp | `BiocTours.jsx:307` body — *"Per-CpG differential methylation with `limma` eBayes on **M-values** (design `~ group`) — **12,403** significant CpGs at FDR < 0.05, passed on to bumphunter."* | `limma_dmp_test` (`qc_evidence.yaml:1152`) → Ritchie 2015 / `10.1093/nar/gkv007` |
| D_dmr | `BiocTours.jsx:313` body — *"`bumphunter` (1,000 bootstraps) collapses adjacent significant CpGs into **847 regions** — a `GRanges` object of DMRs, ready for enrichment."* | `dmrcate_region_call` (`qc_evidence.yaml:1164`) → Peters 2015 / `10.1186/1756-8935-8-6` |
| E_enrich | `BiocTours.jsx:319` body — *"the **AGENT** block gives the fix: `missMethyl::gometh` weights genes by CpG count so enrichment p-values stay calibrated."* | `missmethyl_cpg_corrected_go` (`qc_evidence.yaml:1178`) → Phipson 2016 / `10.1093/bioinformatics/btv560` |

### Chain 4 — `scrna_pseudobulk_de_bioc` (single_cell, 6 phases — id 60 per `qc_evidence.yaml:1076`)

Reuses **the same** BiocTours.jsx:193–268 quotes as chain 2 (the OSCA
tour *is* the pseudobulk arc), but omits the `D_markers` phase because
this chain's `steps` (per `add_scrna_pseudobulk_chain.py:27`) drop the
parallel markers branch:

| phase_id | rationale_text source | citation gate |
|---|---|---|
| A_qc | `BiocTours.jsx:215` (as above) | `scater_qc_normalization` (1035) |
| B_norm_hvg | `BiocTours.jsx:221` (as above) | `scran_normalization_hvg` (1077) |
| C_cluster | `BiocTours.jsx:227` (as above) | `scran_normalization_hvg` (1077) |
| D_annotate | `BiocTours.jsx:233` (annotation arm) | `singler_celltype_annotation` (1105) |
| E_pseudobulk | `BiocTours.jsx:239` (as above) | `pseudobulk_aggregation_deseq2` (1119) |
| F_report | `BiocTours.jsx:248` (as above) | none |

**Total: 24 rows.** Each row's `rationale_text` is a verbatim
extraction from BiocTours.jsx — the population script (§5) strips JSX
tags via a regex pass and stores plain UTF-8 text. **No new prose is
authored.**

---

## 3. Endpoint

`GET /api/workflows/:name/phases/:phase_id/rationale`

Mounted on the Galaxy backend (port 8081) — sibling to
`/api/nextflow/steps` in
`backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`. Resolves
`:name` against both `workflow_chains.name` and `workflows.name`.

**Response shape** (matches `ChatStream.jsx:82–83` `{ text, cite:
{ title, doi } }` plus the three extra sections the task brief
specifies for the popover):

```json
{
  "workflow_id": 60,
  "phase_id": "E_pseudobulk",
  "why_this_method": {
    "text": "the AGENT block gives the fix: aggregate to pseudobulk ...",
    "cite": {
      "title": "Crowell HL, Soneson C, et al. Nature Communications 2020; 11(1):6077",
      "doi":   "10.1038/s41467-020-19894-4"
    }
  },
  "live_events":  { "qc_gate": "pseudobulk_aggregation_deseq2", "events_url": "/api/workflows/runs/{run_id}/events?phase=E_pseudobulk" },
  "parameters":   { "lookup_url": "/api/nextflow/steps?nextflow_path=...&phase=E_pseudobulk" },
  "cost":         { "lookup_url": "/api/billing/jobs/{run_id}/cost?phase=E_pseudobulk" },
  "last_curated_at": 1718323200
}
```

The endpoint returns ONLY the `why_this_method` section from the DB
table. The three other sections are **URL pointers** — the frontend
fetches them lazily on popover open, so the rationale endpoint stays
cheap and cacheable (`Cache-Control: max-age=3600`). 404 if no row.

---

## 4. Frontend `<WhyAnchor>` component

**File:** `frontend/client/src/components/why-anchor.tsx` (new).
**Props:** `{ workflowName: string; phaseId: string; runId?: string }`.
**Primitive:** `Popover` / `PopoverTrigger` / `PopoverContent` from
`frontend/client/src/components/ui/popover.tsx:29` (verified exists,
exports confirmed).

Render:
- Trigger: `<span className="why-anchor">(why?)</span>` (mirrors
  `ChatStream.jsx:66` CSS class so existing reference-design styles
  apply).
- Content: 4 stacked sections with headings *"Why this method · Live
  events · Parameters · Cost"*, lazy-loading the three pointer URLs
  on `onOpenChange(true)`.
- If the `GET /rationale` returns 404, the component renders nothing
  (no anchor at all), so non-bioc chains are unaffected.

Wire-in: edit `frontend/client/src/components/chat-message.tsx` to
render `<WhyAnchor>` after the headline of any AI message whose
`metadata.workflow_name` is in the 4-bioc allow-list (week 2 of
rollout — see §6).

---

## 5. Population migration script

**File:** `backend/scripts/populate_bioc_phase_rationale.py` (new).

Steps:

1. Open `backend/database/galaxy_ai_tools.db` (sqlite3).
2. `CREATE TABLE IF NOT EXISTS workflow_phase_rationale (...)` per §1.
3. Resolve the 4 chain ids:
   ```python
   ids = {name: row[0] for (name,) in CHAIN_NAMES
          for row in cur.execute(
              "SELECT id FROM workflow_chains WHERE name = ?", (name,))}
   ```
   where `CHAIN_NAMES = ["bulk_rnaseq_consensus_de_bioc",
   "scrna_consensus_de_bioc", "methylation_450k_array_analysis",
   "scrna_pseudobulk_de_bioc"]`.
4. Hard-code the 24 `(workflow_id, phase_id, qc_gate_name,
   source_file_line)` tuples derived from the §2 mapping table — no
   prose strings in this script; instead each tuple references a
   slice into a one-time-extracted JSON file
   `backend/scripts/data/bioc_tour_quotes.json` produced by a sibling
   script `extract_bioc_tour_quotes.py` that runs a small JSX→text
   regex pass over `reference/claude_design/src/BiocTours.jsx` and
   emits `{ "bioc-kb-routing:135": "...quoted body..." }`. This keeps
   the prose canonically sourced from BiocTours.jsx, not retyped.
5. Load `backend/config/qc_evidence.yaml`; for each row, pull
   `paper_ref` and `paper_doi` from the named gate.
6. Insert with `ON CONFLICT(workflow_id, phase_id) DO UPDATE` so the
   script is idempotent; bump `last_curated_at = int(time.time())` on
   every run.
7. Print a summary: *"Upserted 24 rationale rows across 4 chains"*.

Total LOC estimate: ~120 (script) + ~60 (extractor) = ~180.

---

## 6. Phased rollout

### Week 1 — backend foundation (4 BE-days)
- Day 1: ship schema migration `0007_workflow_phase_rationale.sql`
  shipping in the existing migration runner; add CREATE-IF-NOT-EXISTS
  guard.
- Day 2: write `extract_bioc_tour_quotes.py` + commit the produced
  JSON snapshot.
- Day 3: write `populate_bioc_phase_rationale.py`; run it; verify 24
  rows in DB.
- Day 4: add `GET /api/workflows/:name/phases/:phase_id/rationale`
  endpoint in `ai_assistant.py`; `kill -HUP` gunicorn; smoke-test via
  curl on dev.
- **Exit criterion:** `curl /api/workflows/scrna_pseudobulk_de_bioc/phases/E_pseudobulk/rationale`
  returns the Crowell 2020 citation block.

### Week 2 — frontend anchor for bioc (3 FE-days)
- Day 5: build `<WhyAnchor>` with `ui/popover.tsx`; mock fetch in a
  Vitest unit test.
- Day 6: wire into `chat-message.tsx` behind the 4-chain allow-list;
  add E2E test in `frontend/e2e/bioc-rationale-anchor.e2e.ts`
  asserting (a) anchor renders on bulk_rnaseq message, (b) popover
  opens on hover and shows section headings, (c) citation footer
  displays Love 2014 for phase C_de.
- Day 7: pre-sync checklist (`docs/PRE_SYNC_CHECKLIST.md`), sync to
  dev, manual audit screenshots.
- **Exit criterion:** the 5 use-case scenarios from CLAUDE.md UX
  Completeness Standard still pass; 4 bioc chats render `(why?)`
  anchors that open the correct citation.

### Week 3 — extend to cryo + admet (3 BE+FE-days)
- Day 8: add `cryo_em` and `drug_discovery` sections to
  `bioc_tour_quotes.json` extraction (sources:
  `reference/claude_design/cro/Tour.jsx` for ADMET phases;
  `tutorials-work/cyro_tutorial/src/Tour.jsx` for cryoEM).
- Day 9: re-run `populate_*` with extended allow-list; remove the
  bioc-only allow-list gate in `chat-message.tsx` (anchor now appears
  for any workflow with a rationale row, naturally 404-suppressed
  elsewhere).
- Day 10: regression + ship.

**Headroom:** 2 days slack across the 10 working days for review +
fixes — fits inside the ≤2-engineer-week ceiling.

---

## 7. Risks + open questions

| # | Risk / Question | Mitigation |
|---|---|---|
| R1 | **TTL / staleness.** `qc_evidence.yaml` is hand-curated; if a citation gets updated, the DB row goes stale silently. | `last_curated_at` column exposed via the endpoint; CI job runs the populate script weekly and fails the build if a row's hash changes without bumping `last_curated_at` in the source YAML. |
| R2 | **Who edits the table?** | Edits flow through `qc_evidence.yaml` (citations) and `BiocTours.jsx` (prose) ONLY — never direct SQL. Re-run the populate script after any merge that touches those two files (CI hook). This keeps the canonical sources of truth singular. |
| R3 | **Chain id drift.** `scrna_pseudobulk_de_bioc` id is 60 today (MEMORY note) but is assigned at insert time by `add_scrna_pseudobulk_chain.py:128`; on a fresh DB the id could differ. | Populate script resolves by `name`, never by hard-coded id (see §5 step 3). |
| R4 | **Live-events / cost lookup URLs return 404 in the popover.** | Frontend renders an em-dash placeholder per section that 404s; the "Why this method" section still renders standalone. Tested in E2E. |
| R5 | **JSX-tag stripping mangles prose.** BiocTours quotes contain `<code>`, `<b>`, `<div className="hint">` etc. | Extractor preserves `<code>` content as backtick-wrapped plain text; strips `<b>` to plain text; drops the `<div className="hint">…</div>` block entirely (hints are tour-specific UX scaffolding, not rationale). Unit-test the extractor on all 24 quotes. |
| R6 | **Pin-script that doesn't exist.** Task brief cites `backend/scripts/pin_bioc_chain_workflow_ids.py`; the file is absent today. | §5 replaces the implicit pin lookup with a runtime `SELECT id FROM workflow_chains WHERE name = ?`. If a pin script is added later, populate script can switch trivially. |
| R7 | **Branch mismatch.** Worktree is on `qc/coverage-and-rebuilds` but the brief specifies `bioc/v2-qc-audit-panel`. | Commit this plan here, then `git cherry-pick` it onto `bioc/v2-qc-audit-panel` before week 1 begins. Flagged to the operator in the final report. |

---

## Acceptance summary

After week 2:
- 24 rows live in `workflow_phase_rationale`.
- 4 bioc chains render `(why?)` anchors backed by Wave 1-2 citations.
- E2E test asserts the anchor + popover for ≥1 phase of each chain.
- Zero new prose was authored; every string is traceable to either
  `qc_evidence.yaml` or `BiocTours.jsx`.
