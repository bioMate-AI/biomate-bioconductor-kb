# Bioconductor handoff — 3 curated chain designs

This document captures the three Bioconductor chains the BioMate handoff
showcases, as they exist today in `backend/database/galaxy_ai_tools.db`
(table `workflow_chains`). Each chain is a curated, ordered set of
sub-workflows wired together by typed data-flow connections — the chain
runs end-to-end and emits a multi-tab After-run report.

The terms used here match the DB schema:

- **steps** — ordered list of `{order, workflow_name, role, params_template}`
- **connections** — typed data hops: `{from_step, from_output, to_step, to_input}`
- **required_inputs / expected_outputs** — what the user must provide / what the chain produces

The three chains live alongside ~120 other domain chains in the same
table. They are surfaced by the Bioconductor handoff tutorials (`bioc_kb`,
`bioc_sc`, `bioc_methyl`) in the design prototype at
`reference/claude_design/bioconductor-handoff/`.

---

## 1. `bulk_rnaseq_consensus_de_bioc`

**Display name:** Bulk RNA-seq → Consensus DE (Bioconductor)
**Domain:** transcriptomics
**One-liner:** salmon quants → DESeq2 → clusterProfiler enrichment

Standard bulk RNA-seq processing followed by DESeq2 differential
expression and clusterProfiler functional enrichment. The Bioconductor
multi-method consensus alternative set (edgeR, limma, DSS, EBSeq, baySeq,
IHW) is explicitly named in the example queries; substitute any one in
step 2 when the experimental design calls for it.

### Steps

| # | workflow_name | role |
|---|---|---|
| 1 | `nf-core/rnaseq` | primary_processing |
| 2 | `deseq2` | differential_expression |
| 3 | `clusterprofiler` | pathway_enrichment |

### Connections (data flow)

```
step1.counts_matrix → step2.counts
step2.de_table      → step3.gene_list
```

### Required inputs

| name | type |
|---|---|
| `fastq_files` | fastq |
| `sample_sheet` | csv |
| `contrast` | string |

### Expected outputs

| name | type |
|---|---|
| `de_results` | tsv |
| `enrichment_results` | tsv |
| `volcano_plot` | pdf |

### Per-step substitution policy

Step 2 (`deseq2`) is the swap point. The example queries enumerate
edgeR / limma / DSS / EBSeq / baySeq / IHW as alternatives; the router
resolves the user's stated method into step 2 while keeping steps 1 and
3 fixed. Step 3's `clusterprofiler` reads the DE table by `gene` and
`log2FoldChange` columns — every substitute must emit those.

---

## 2. `scrna_consensus_de_bioc`

**Display name:** scRNA-seq → Multi-Method Cell-Type DE (Bioc)
**Domain:** single_cell
**One-liner:** SCE → scater QC → MAST + Monocle pseudotime DE in parallel

Single-cell RNA-seq processing followed by per-method differential
expression: scater (population-aware QC and normalization), MAST (hurdle
model for zero-inflation), and Monocle (pseudotime-aware DE). Use this
chain when scRNA DE robustness across method choice is required
(publication-grade single-cell studies).

### Steps

| # | workflow_name | role |
|---|---|---|
| 1 | `nf-core/scrnaseq` | scrna_processing |
| 2 | `scater` | qc_normalization |
| 3 | `mast` | de_hurdle_model |
| 4 | `monocle` | pseudotime_aware_de |

### Connections (data flow)

```
step1.sce_or_h5ad      → step2.sce
step2.normalized_sce   → step3.sce        ← MAST
step2.normalized_sce   → step4.sce        ← Monocle  (parallel to MAST)
```

Steps 3 and 4 are **fan-out from step 2**. They consume the same
normalized SCE and run independently. Their outputs are not re-joined
in this chain — each method's DE table is a top-level chain output.

### Required inputs

| name | type |
|---|---|
| `scrna_fastq` | fastq |
| `sample_sheet` | csv |
| `reference_transcriptome` | string |

### Expected outputs

| name | type |
|---|---|
| `mast_de_results` | tsv |
| `monocle_trajectory` | rds |
| `qc_report` | html |

### Substitution policy

This chain is intentionally **not** swap-friendly — the two-DE-methods
shape is the value proposition (cross-method robustness check). The
router treats step 2 → step 3 → step 4 as a unit.

---

## 3. `methylation_450k_array_analysis`

**Display name:** Illumina 450k/EPIC Methylation Array DMR Analysis (methylationArrayAnalysis)
**Domain:** epigenomics
**One-liner:** minfi → limma DMPs → DMRcate DMRs → missMethyl gometh

Bioc Workflow `methylationArrayAnalysis` analog: read IDAT files via
minfi, QC, normalize (SWAN or noob), call DMPs (limma), DMRs (DMRcate),
gene-set test (missMethyl).

### Steps

| # | workflow_name | role |
|---|---|---|
| 1 | `BIOC_minfi` | read_idats_and_qc |
| 2 | `BIOC_limma` | differential_methylation_position |
| 3 | `BIOC_DMRcate` | differential_methylation_region |
| 4 | `missmethyl_region_level_gsa` | gometh_gene_set_test |

### Connections (data flow)

```
step1.GenomicMethylSet → step2.beta
step1.GenomicMethylSet → step3.beta        (parallel to step2)
step2.dmps             → step4.dmp_ids
```

Step 1's `GenomicMethylSet` (β-values + probe coordinates) fans out to
**both** step 2 (per-CpG limma test) and step 3 (region-level DMRcate).
DMRcate does its own probe-level smoothing internally, so it does not
depend on step 2's DMPs. Step 4 (gometh) takes the DMP IDs from step 2
to compute a CpG-density-corrected GO enrichment.

### Required inputs

| name | type | description |
|---|---|---|
| `idat_paths` | directory | Directory containing IDAT files |
| `sample_sheet` | csv | Illumina sample sheet with condition labels |

### Expected outputs

| name | type | description |
|---|---|---|
| `dmps` | tsv | Differentially methylated positions |
| `dmrs` | tsv | Differentially methylated regions |
| `enriched_terms` | tsv | GO/KEGG enriched for DMP-overlapping genes |

### CpG-bias correction (the teaching beat)

A generic GO enrichment would over-call CpG-rich promoters because the
450k array oversamples them. `missMethyl::gometh` weights each gene by
its CpG-island content so the null distribution matches the array's
probe density. This is the chain's headline pedagogical point and is
highlighted in the `bioc_methyl` tour script.

---

## Cross-chain shape summary

| Chain | Steps | Topology | Parallelism |
|---|---|---|---|
| `bulk_rnaseq_consensus_de_bioc` | 3 | linear | none |
| `scrna_consensus_de_bioc` | 4 | linear with fan-out at step 2 | MAST ∥ Monocle |
| `methylation_450k_array_analysis` | 4 | DAG: step 1 fan-out, step 4 joins | limma ∥ DMRcate |

All three chains follow the same orchestration contract: the chain
runner picks up `required_inputs` from the user, drives each step in
data-flow order (running fan-outs concurrently), and finalises with the
After-run report assembling `expected_outputs` + per-step methods +
software pins + citations.

---

## Workflow resolution — integrity check

Each chain step references a `workflow_name` that the chain runner
resolves against the `workflows` table at routing time. Verified counts
as of 2026-06-12 (`SELECT COUNT(*) FROM workflows WHERE name=…`):

| Chain | Step | workflow_name | rows in `workflows` | Status |
|---|---|---|---|---|
| `bulk_rnaseq_consensus_de_bioc` | 1 | `nf-core/rnaseq` | 1 | ✅ resolves |
| | 2 | `deseq2` | 12 | ⚠️ ambiguous — router needs tie-break |
| | 3 | `clusterprofiler` | 3 | ⚠️ ambiguous |
| `scrna_consensus_de_bioc` | 1 | `nf-core/scrnaseq` | 1 | ✅ |
| | 2 | `scater` | 1 | ✅ |
| | 3 | `mast` | 6 | ⚠️ ambiguous |
| | 4 | `monocle` | 1 | ✅ |
| `methylation_450k_array_analysis` | 1 | `BIOC_minfi` | **0** | ❌ missing |
| | 2 | `BIOC_limma` | **0** | ❌ missing |
| | 3 | `BIOC_DMRcate` | **0** | ❌ missing |
| | 4 | `missmethyl_region_level_gsa` | 1 | ✅ |

**Blocker on the methylation chain.** Three step workflows
(`BIOC_minfi`, `BIOC_limma`, `BIOC_DMRcate`) have no rows in
`workflows`. The chain cannot run end-to-end until they're added.
Either the names need to be remapped to existing workflow rows (e.g.
the `minfi`, `limma`, `DMRcate` workflows that *do* exist under
different naming), or the workflow stubs need to be authored.

The ambiguous cases (`deseq2`, `clusterprofiler`, `mast`) resolve fine
when the chain runner picks the row with the highest match-confidence,
but the design should pin them with stable IDs to make the chain
deterministic.

---

## Handoff product wiring

The three chains are surfaced through the design prototype at
`reference/claude_design/bioconductor-handoff/`. Tour scripts
(`src/BiocTours.jsx`) drive a four-act narration over each chain:

| Tour ID | Chain | Acts |
|---|---|---|
| `bioc-kb-routing` | `bulk_rnaseq_consensus_de_bioc` | Understand → Choose → Run → Found |
| `bioc-sc-routing` | `scrna_consensus_de_bioc` | same |
| `bioc-methyl-routing` | `methylation_450k_array_analysis` | same |

The "Choose" act renders a `WorkflowDisambiguationCard` listing the
alternates for the swap-point step (DESeq2 vs edgeR vs limma for chain 1;
no swap for chain 2 by design). After 1-1 ships, the production chat
honours `workflow_type='disambiguation'` payloads and renders the same
card.

### Chat narrator → speaker pill mapping

The chain runner emits SSE events via `workflow_chat_narrator` over
`/api/workflows/:invocationId/events`. The four acts map onto existing
event kinds — no new "section" event is needed:

| Act | Event kinds | Speaker pill |
|---|---|---|
| Understand | `plan.*` (decompose, pilot offer) | `plan` |
| Choose | `workflow.submitted`, disambig card | `wf` / `agent` |
| Run | `workflow.phase_started/completed/failed`, `workflow.qc_*`, `workflow.autoloop_*`, `step_state` | `wf` / `qc` / `loop` |
| Found | `workflow.completed`, `findings.*` | `find` |

---

## After-run report — per-chain mapping

The 7-tab After-run report (`v2/AfterRunReport.tsx`) is fed by
chain-agnostic endpoints. Below is what each chain produces into each
tab today:

| Tab | Source | bulk_rnaseq | scrna | methylation |
|---|---|---|---|---|
| Findings | `findings_data.json` sidecar (`findings_analysis` job) | DE genes + top GO BP | 11 clusters + monocyte DEGs | 847 DMRs + CpG-corrected GO |
| Outputs | `expected_outputs` walk on chain workdir | `de_results.tsv`, `enrichment_results.tsv`, `volcano_plot.pdf` | `mast_de_results.tsv`, `monocle_trajectory.rds`, `qc_report.html` | `dmps.tsv`, `dmrs.tsv`, `enriched_terms.tsv` |
| Methods | `/api/invocations/:id/methods-report` | IMRaD prose with DESeq2 design, alpha, shrinkage | scater normalize → MAST hurdle, Monocle pseudotime | minfi read, preprocessQuantile, limma eBayes, DMRcate, gometh |
| Parameters | per-step `params_template` ∪ user overrides | `design`, `reference`, `fdr`, `shrinkage` | `mito_max`, `min_features`, `cluster_resolution` | `detect_p`, `bumphunter B`, `gometh array.type` |
| Software | `pipeline_info/software_versions.yml` (NF-core terminal) | nf-core/rnaseq version, R/Bioc pins | nf-core/scrnaseq, scater, MAST, Monocle versions | minfi, limma, DMRcate, missMethyl versions |
| Citations | `qc_evidence.yaml` keyed by domain | Love 2014 DESeq2, Yu 2012 clusterProfiler | McDavid 2013 MAST, Trapnell 2014 Monocle, McCarthy 2017 scater | Aryee 2014 minfi, Peters 2015 DMRcate, Phipson 2016 missMethyl |
| QC audit | `qc-events` keyed by invocation | size factors, FDR cutoff hit | per-cell QC metrics, HVG count | detection-p QC, probe retention, sig-CpG count |

### Citations gap

`qc_evidence.yaml` currently has 22 domains (pbpk, admet, cryo_em, hts,
…) but **no `bioconductor`/`transcriptomics`/`epigenomics`** entries.
Until those are added the Citations tab will be empty for all three
chains. Wave 1-2 in the closure plan ships exactly those entries — one
YAML block per chain with the references listed in the table above.

### Findings figures gap

The findings sidecar already carries `key_results` (structured).
FigBars / FigComposition / FigQc (v2 components) read a `figures[]`
field which doesn't yet exist on the payload. The adapter is small:
map `key_results` → `figures[]` shapes inside the `findings_analysis`
handler. No new ML inference; just a re-projection.

---

## Open questions for the reviewing session

1. **methylation step names** — remap `BIOC_minfi` / `BIOC_limma` /
   `BIOC_DMRcate` to existing workflow rows, or author 3 new stubs?
2. **DESeq2 swap mechanic** — should the chain hold an explicit
   `alternates: ['edgeR','limma','DSS','EBSeq','baySeq']` list, or
   continue relying on the DisambigCard candidate scoring at routing
   time?
3. **scRNA fan-out join** — the design today emits MAST and Monocle
   as separate top-level outputs. Is a downstream consensus/merge step
   ever wanted, or is "two independent DE tables for cross-check"
   the intended deliverable?
4. **methylation parallelism** — DMRcate runs in parallel with the
   limma DMP test, but the After-run "Methods" prose narrates them
   sequentially. Match the prose to the DAG, or vice-versa?

---

## DB source of truth

```sql
SELECT name, display_name, domain, description,
       steps, connections, required_inputs, expected_outputs
FROM   workflow_chains
WHERE  name IN (
  'bulk_rnaseq_consensus_de_bioc',
  'scrna_consensus_de_bioc',
  'methylation_450k_array_analysis'
);
```

To re-emit this doc from the DB after any chain edit:

```bash
sqlite3 backend/database/galaxy_ai_tools.db \
  "SELECT name, steps, connections FROM workflow_chains WHERE name LIKE '%bioc%' OR name LIKE '%450k%';"
```
