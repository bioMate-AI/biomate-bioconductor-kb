# Bioc QC Phase 3d — Backfill Session (2026-06-17 → 2026-06-19)

**Branch:** `qc/coverage-and-rebuilds`
**Result:** Bioc Phase 3c-adopted workflows: **396 → 659** (+263 via 11 narrow domain filters)
**Audit + verify:** all green throughout — 7/7 audit dimensions clean, 658/658 Rscript verify, 4/4 roundtrip pytest, 7/7 S3 reader unit tests.

## Backfill ledger (chronological)

| Commit | Domain | +Adds | Cumulative | POS_DOM pattern | Labels |
|---|---|---:|---:|---|---|
| `4e47c14f8` | RNA-seq DE | +34 | 430 | `rnaseq / edger / deseq / count data / nbinom` | low-count + count-norm + dispersion |
| `e640cc38c` | Microarray DE | +11 | 441 | `affy / illumina BeadChip / agilent / limma / RMA` | between-array-norm + array-detection + low-count |
| `acfd3600c` | scRNA cell-QC | +19 | 460 | `single-cell RNA / scRNA-seq / Seurat / SCE` (POS_ACT-anchored) | cell QC metrics + count-norm + low-count |
| `23b50b2cb` | Microbiome amplicon | +4 | 464 | `microbiome / amplicon / 16S / OTU / ASV / phyloseq / dada2 / mothur` | prevalence/abundance + count-norm + MA/PCA QC |
| `033e78b47` | Methylation arrays | +13 | 477 | `methylation / bisulfite / 450K / EPIC / CpG / WGBS / RRBS / Infinium` | array detection + alignment QC + low-count |
| `235df917de` | Proteomics mass-spec | +6 | 483 | `proteomics / mass-spec / MaxQuant / MSstats / PSM / TMT / SILAC / DIA / DDA` | MV-handling + count-norm + low-count |
| `7af0add71` | ChIP-seq / ATAC-seq | +26 | 509 | `ChIP-seq / ATAC-seq / CUT&RUN / CUT&Tag / peak calling / MACS2 / TF-binding` | alignment QC + low-count + count-norm |
| `71f185618a` | Variant / CNV / WGS | +38 | 547 | `variant calling / VCF / SNP / somatic-germline / WGS-WES / SNV-indel / CNV` | alignment QC + low-count + outlier detection |
| `ce13d17b74` | Pathway enrichment | +57 | 604 | `pathway enrichment / GSEA / GO / KEGG / Reactome / MSigDB / ORA` | input validation + low-count + outlier detection |
| `34ce7b8e8` | Spatial + Splicing | +10 | 614 | `spatial transcript / Visium / MERFISH / SPE` + `alternative splicing / isoform / DTU / splice junction` | tier-appropriate per pattern |
| `627667f6d` | Cancer / oncology | +15 | 629 | `cancer / oncology / tumor / TCGA / driver gene / mutational signature` | alignment QC + low-count + outlier detection |
| `e8fb207dd` | Metabolomics + miRNA + biomarker | +14 | 643 | metabolomics + miRNA/ncRNA + biomarker classifier | tier-appropriate |
| `4b6b39d967` | Hi-C + Network + Survival | +16 | **659** | `Hi-C / 3D chromatin / TAD` + `network/GRN/WGCNA` + `survival / Kaplan-Meier / Cox` | tier-appropriate |

## Filter discipline (the actual repeatable recipe)

Every batch followed the same 5-step pattern:

1. **Define POS_DOM** — exhaustive regex of synonyms for the target domain (e.g. for ChIP/ATAC: `chip.?seq|atac.?seq|cut.?run|cut.?tag|histone\s+(mark|modif)|peak\s+(calling|caller)|narrowpeak|broadpeak|macs2|tf\s+binding`).
2. **Require POS_ACT** — analysis-intent verb (`identify|detect|quantify|estimate|score|classify|predict|differential|analy[sz]|filter|normali[sz]|cluster|annotate`). Without this, util/viz tools leak in.
3. **Apply NEG anti-rules** — exclude wrong-domain + viz + util + simulators:
   ```
   \b(visuali[sz]\w*|plot\w*|render\w*|graphic\w*|heatmap\w*|interactive\s+viewer|
      data\s+portal|access\s+(the|data)|download.*from|simulat|
      generate\s+(synthetic|fake))
   ```
   Note: use `\w*` at the prefix end (not `\b`) so suffixes match (`visualis-ing`, `plot-R`, `render-ing`).
4. **Dry-run + eyeball** — print all candidates with truncated descriptions; verify zero false positives before any DB write.
5. **Apply + verify** — `UPDATE qc_steps` → re-run patcher → re-run audit (7 dims) + Rscript verifier. Must stay green; if any dim fails, roll back.

## Label-picking discipline

Labels chosen per domain to use only LABEL_BLOCKS that the patcher can emit defensively:

- **Count-based domains** (RNA-seq, scRNA, splicing, miRNA, microbiome): `low-count filtering` + `count normalization` + (`dispersion/size-factor estimation` for bulk, `cell QC metrics` for single-cell, `prevalence/abundance filtering` for microbiome)
- **Alignment-heavy domains** (ChIP/ATAC, variant calling, Hi-C, methylation, cancer): `alignment/mapping QC` + `low-count filtering` + `outlier detection`
- **Array domains** (microarray DE, methylation arrays): `between-array normalization` + `array detection QC` + `low-count filtering`
- **Wide-input domains** (proteomics, metabolomics): `missing-value handling` + `count normalization` + `low-count filtering` (LC/MS data is 30-50% missing — MV gate is the primary check)
- **Declarative-only domains** (pathway enrichment, biomarker, network, survival): `input validation` + `outlier detection` (no count matrix for the harness to measure; declarative emit is honest)

When the actual artifact at runtime doesn't match the label's tier (e.g. a microarray workflow patched with `count normalization` produces no count matrix), the defensive block emits `status='not_computed (no matrix/data.frame .rds artifact present)'` — the gate row still lands in the audit ledger, just without a numeric value. **No invented thresholds, no fake passes.**

## What's NOT covered

- **Empty-qc_steps remaining:** ~2,400 of original 2,781 (down from 2,781 by 263 + the 396 originally declared = 659 total declared now; ~2,400 still empty)
- **Why not patched here:** these need either (a) per-workflow eyeball review because their domain is mixed / generic, or (b) a fresh narrower filter for an untapped domain (e.g. flow cytometry, drug screening, image analysis).
- **The triage CSV at `docs/20260617_BIOC_EMPTY_QC_TRIAGE.csv`** still has the original UNCLEAR + CORRECTLY_EMPTY classifications — many are genuinely correctly-empty (visualization-only, format converters, package wrappers, annotation lookups).

## Verification status (after this session)

| Layer | Coverage | Tool |
|---|---|---|
| Static audit (7 dims) | **659 / 659 clean** | `bioc_qc_harness_audit.py` |
| Rscript dynamic verify | **658 / 658 pass** (1 skip: hand-written DESeq2 canonical) | `bioc_qc_harness_verify_all.py` |
| Reader-side roundtrip pytest | 4 / 4 pass | `backend/tests/test_bioc_qc_harness_roundtrip.py` |
| S3 outdir + workdir unit tests | 7 / 7 pass | `backend/tests/test_qc_trace_monitor_s3_pagination.py` |

## Verifier extraction fix (incidental)

While running this session, the Rscript verifier surfaced 2 false-positives (`monocle`, `voyager`) with `Error: unexpected '}'`. Root cause: my regex extracted from `.qc_metrics_path` all the way through `writeLines(c(`, capturing the closing `}, error = function(e) {...})` of the workflow's wrapping `tryCatch({...})` whose opener lived upstream in the .nf. Fixed at `e640cc38c` by anchoring the extraction's end on the inject block's own final `cat(jsonlite::toJSON(.qc_payload, ..., file = .qc_metrics_path))`. Three sites updated: `bioc_qc_harness_verify_all.py`, `test_bioc_qc_harness_roundtrip.py`, `bioc_qc_harness_verify_local.sh`.

## Related infrastructure work this session

- **`5fd90cf38`** — completed Option A from `docs/20260617_BIOC_QC_PRODUCTION_BLOCKERS.md`: threaded `s3_work_dir` through `nextflow_executor._start_qc_monitor` → `NextflowQCGateHandler` so the reader-side `_read_s3_workdir_report` (`66ae809fa2`) actually receives the work-dir prefix and can fetch `qc_metrics.json` from the per-task work dir when `publishDir=null` is in effect.
- **`080a07399`** — 4 unit tests for `_read_s3_workdir_report` (happy path + non-matching hash + unset work-dir + malformed hash).
- **`68c69fd11`** — archived `ADMET_pred` (legacy) — eliminated routing non-determinism between two ADMET workflows for the auto-loop toggle e2e.
- **`3e95d94e7`** — defensive `Partial<LLMAnalysis>` parse in `workflow-prerequisites-validator.ts` — fixed the chat-stream "Connection error" JS crash that surfaced when LLM returned a response missing any expected array.
- **`c22994e65`** — auto-loop on/off toggle e2e (AL-T1 passes on dev; AL-T2 partial: OFF-suppresses-panel verified).

## Production gate-firing path

Still **gated on the `publishDir=null` constraint** (see `docs/20260617_BIOC_QC_PRODUCTION_BLOCKERS.md` for full context). The reader-side fallback I added in this session unblocks the work-dir path, BUT the actual production verification still needs a real Bioc Batch run to observe `[QC-S3] Reading work-dir qc_metrics.json for BIOC_...` in `gunicorn.log`. That's the one remaining money step.

## Related docs

- `docs/20260617_BIOC_QC_HARNESS_FULL_COVERAGE.md` — original Phase 3c writeup (396 adopted)
- `docs/20260617_BIOC_QC_PRODUCTION_BLOCKERS.md` — publishDir + work/outdir split analysis
- `docs/20260616_BIOC_PHASE_3C_ADOPTION_RECIPE.md` — hand-canonical adoption recipe (DESeq2 reference)
- `docs/20260617_BIOC_EMPTY_QC_TRIAGE.csv` — original triage of 2,781 empty-qc_steps workflows
