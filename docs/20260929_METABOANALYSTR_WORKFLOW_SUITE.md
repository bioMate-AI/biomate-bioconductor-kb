# MetaboAnalystR Workflow Suite — Metabolomics Domain Enrichment

**Date:** 2026-09-29
**Author:** Claude Opus 4.8 (1M context)
**Commit:** `80d135474` (feat(metabolomics): MetaboAnalystR workflow suite)
**Image:** `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps`
(MetaboAnalystR 4.3.0 + OptiLCMS + xcms + CAMERA baked in, validated)

## Goal

Enrich the **metabolomics** domain by building a **suite** of MetaboAnalystR workflows —
one per MetaboAnalyst analysis module — so each module is independently routable in
BioMate, mirroring the multi-workflow protein-package pattern (#217). Previously only the
**Statistical Analysis** module existed.

## What was built

Seven new Nextflow subworkflows under
`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/metaboanalystr_<module>/main.nf`,
plus registration of all eight (the seven new + the pre-existing but unregistered `stat`
module) into the workflow DB.

Every workflow mirrors the validated **stat template** exactly:
- `#!/usr/bin/env Rscript` process body, container pinned to the metabolomics image
- staged-input flattening (`stageAs '?/*'` → numbered subdirs)
- the **`.bm_finish()` Rserve-kill + clean-exit guard** on both the error path
  (`options(error = ...)`) and the success path (final `.bm_finish(0)`) — this is what
  prevents the ~30-min AWS Batch **zombie hang** (MetaboAnalystR/OptiLCMS fork an Rserve
  daemon at init that keeps the task's stdio FDs open)
- a self-contained **fixture default** (built-in HMDB-mappable compound list, or a
  synthetic table the R body generates) so each runs with **no user input**
- real outputs (CSV tables / PNG-PDF plots / `.rds` object) + `versions.yml` + a `stub` block

**Every MetaboAnalystR function call was verified `@export`ed against the package
NAMESPACE** (`/tmp/MetaboAnalystR-master/NAMESPACE`). Traps avoided: `ReplaceMin`
(not exported — use `ImputeMissingVar`), `PlotImpVars` (not exported — use
`PlotImpBiomarkers`), `PlotMetaPCA`/`PlotMetaVenn` (don't exist — use
`PlotPCAPairSummaryMeta`).

All seven pass `nextflow run … -stub` compile (Groovy + DSL2 parse verified locally).

## Module → workflow table

| # | Module | Workflow (name / .nf dir) | Input | Web dep | Built | Registered | Validated |
|---|--------|---------------------------|-------|---------|-------|------------|-----------|
| — | Statistical | `metaboanalystr_statistical` / `metaboanalystr/` | peak table + 2-group labels (+ optional compound list) | none | ✅ (pre-existing, fixed) | ✅ | ✅ **Batch 2026-09-30** |
| 1 | Enrichment (MSEA) | `metaboanalystr_enrichment` / `metaboanalystr_enrichment/` | compound list (ORA) or conc table+labels (QEA) | **yes** (mset `.qs` + compound DB from metaboanalyst.ca) | ✅ | ✅ | ✅ **Batch 2026-09-30** |
| 2 | Pathway (MetPA) | `metaboanalystr_pathway` / `metaboanalystr_pathway/` | compound list + KEGG org | **yes** (KEGG API + lib) | ✅ | ✅ | ✅ **Batch 2026-09-30** |
| 3 | Biomarker (ROC) | `metaboanalystr_biomarker` / `metaboanalystr_biomarker/` | conc table + 2-group labels | none | ✅ | ✅ | ✅ **Batch 2026-09-30** |
| 4 | Mummichog | `metaboanalystr_mummichog` / `metaboanalystr_mummichog/` | peak list (m/z, p, t) + ppm + mode | **yes** (`<lib>.qs` from metaboanalyst.ca) | ✅ | ✅ | ⏳ launch-ready (not dispatched this session) |
| 5 | Power / sample-size | `metaboanalystr_power` / `metaboanalystr_power/` | pilot conc table + 2-group labels | none | ✅ | ✅ | ⏳ launch-ready |
| 6 | Time-series (ASCA) | `metaboanalystr_timeseries` / `metaboanalystr_timeseries/` | conc matrix + 2-factor metadata (Time/Phenotype/Subject) | none | ✅ | ✅ | ⏳ launch-ready |
| 7 | Meta-analysis | `metaboanalystr_meta` / `metaboanalystr_meta/` | ≥2 datasets (shared features, same 2-group labels) | none | ✅ | ✅ | ⏳ launch-ready |
| — | Network | — | compound/gene list | — | ⛔ **DEFERRED** | — | — |

### Deferred: Network analysis

`SearchNetDB` hard-downloads a **multi-GB `MetPriCNet.sqlite` / `<org>_genes.sqlite`** from
`xialab.ca`, and the module is JSON/viewer-oriented (its primary output is an igraph JSON
for the web viewer, not standalone tables). Poor fit for a self-contained headless Batch
step. Scoped as a **follow-up**: if pursued, it needs the SQLite pre-staged into the image
or the work dir, and a headless table-only output path
(`orig_edge_list.csv` / `gene_name_map.csv`).

## Per-module call sequences (verified, exported-only)

- **Enrichment ORA:** `InitDataObjects("conc","msetora",F)` → `Setup.MapData` → `CrossReferencing("name")`
  → `CreateMappingResultTable` → `SetMetabolomeFilter(F)` → `SetCurrentMsetLib("smpdb_pathway",2)`
  → `CalculateHyperScore` → `PlotORA(…,"net",…)`. Result: `analSet$ora.mat` → `msea_ora_result.csv`.
  **QEA:** `msetqea` + `Read.TextData` + normalize + `CalculateGlobalTestScore` → `msea_qea_result.csv`.
- **Pathway (MetPA):** `InitDataObjects("conc","pathora",F)` → map → `SetKEGG.PathLib("hsa","current")`
  → `SetMetabolomeFilter(F)` → `CalculateOraScore("rbc","fisher")` → `PlotPathSummary(F,…)`.
  Result: `analSet$ora.mat` → `pathway_results.csv` (p/FDR/Impact).
- **Biomarker:** `InitDataObjects("conc","roc",F)` → `Read.TextData("rowu")` → sanity/impute/normalize →
  `SetAnalysisMode("explore")` → `PerformCV.explore(cls.method="rf")` → `PlotROC`/`PlotAccuracy`/
  `PlotImpBiomarkers`; then `SetAnalysisMode("univ")` + `CalculateFeatureRanking` → ranked-feature CSV.
- **Mummichog:** `InitDataObjects("mass_all","mummichog",F)` → `SetPeakFormat("mpt")` →
  `UpdateInstrumentParameters(ppm,mode,"yes",0.02,NA)` → `Read.PeakListData` →
  `SanityCheckMummichogData` → `SetMummichogPval(0.05)` (needs ≥11 sig features — fixture has ~50)
  → `PerformPSEA("hsa_mfn","current",3,100)` → `PlotPeaks2Paths`. Result: `mummi.resmat`.
- **Power:** `InitDataObjects("conc","power",F)` → `Read.TextData("colu")` → sanity/impute/normalize →
  `InitPowerAnal("NA")` → `PerformPowerProfiling(fdr,smpl)` → `PlotPowerProfile`/`PlotPowerStat`.
  Result: `analSet$power.mat`.
- **Time-series ASCA:** `InitDataObjects("conc","ts",F)` → `SetDesignType("time")` →
  `Read.TextDataTs("rowu")` → `ReadMetaData` → `SanityCheckMeta` → sanity/impute/normalize →
  `Perform.ASCA(1,2,2,2)` → `CalculateImpVarCutoff(0.05,0.95)` → `PlotASCAModel(a/b)` /
  `PlotASCAInteraction` / `Perform.ASCA.permute`. Result: `Sig_features_Model_*.csv`.
- **Meta-analysis:** `InitDataObjects("conc","metadata",F)` → per-study `ReadIndData("colu")` +
  `SanityCheckIndData` + `PerformIndNormalization("med",0)` → `CheckMetaDataConsistency(TRUE)`
  (ComBat merge + per-study limma DE inside) → `PerformPvalCombination("stouffer",0.05)`. Result:
  `meta.mat` → combined-signature CSV + `MetaboAnalyst_merged_data.csv`.

## Internet dependency note

Enrichment, Pathway and Mummichog download their library `.qs` files (and, for MetPA-KEGG,
call the MetaboAnalyst API) from `metaboanalyst.ca` at runtime when not on the public web
(the Batch case). **The AWS Batch compute subnets** (`subnet-0254e4c3634b41bfc` et al.,
vpc-00059887828237f1f) **route `0.0.0.0/0` via an internet gateway** (`igw-03afc8919205b3cea`),
so this outbound HTTPS works. The four no-web modules (biomarker, power, timeseries, meta)
run fully offline. On any download failure the workflows error cleanly via `.bm_finish(1)`
(Rserve killed, no zombie).

## Deploy

- Commit: `80d135474`
- Register script: `backend/scripts/register_metaboanalystr_suite.py` (idempotent
  insert/update + `workflows_fts` rebuild). Registered 8 rows (ids 14643–14650),
  domain=`metabolomics`, per-module `category`, `tools_used=MetaboAnalystR`. FTS routing
  verified locally (e.g. "metabolite set enrichment" → `metaboanalystr_enrichment`,
  "mummichog peaks pathways" → `metaboanalystr_mummichog`).
- Sync: `scripts/sync_to_dev.sh` (workflows + DB layers). **Result: HEALTHY (2026-09-30).**
  - The DB layer was already in sync on dev (md5 match) — the 8 registrations (ids 14643–14650)
    were already present in the dev `galaxy_ai_tools.db`; verified read-only on
    `biomate-galaxy-dev` (all 8 `metaboanalystr_*` rows, domain=`metabolomics`).
  - The 8 `.nf` files deployed via the workflows layer; verified present under
    `/app/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/metaboanalystr_*/main.nf`.
  - No stash was needed — the working tree had no uncommitted SOURCE files in the synced trees
    (the `voyager/main.nf` referenced in the sync-plan was already committed by the time this ran).
  - Bug-fix syncs (see Validation): commits `3155e04fe` (Input-header + missingCount guard),
    `38a5e2ae0` (FilterVariable int-return guard), `7c4462676` (GString `$` compile fix) — each
    re-deployed via a `result=healthy` sync of the workflows layer.

## Validation

**Validated on real AWS Batch, 2026-09-30** (dev dispatch via `POST /api/nextflow/execute`,
container `bioc-domain-metabolomics:3.20-deps`, `is_pilot=true`). All runs reached a terminal
state and **exited fast** — the `.bm_finish()` Rserve-kill guard works: the main analysis task
writes `.exitcode` within ~3 s of the R body finishing (no ~30-min zombie hang). **Zero Batch
orphans** after the whole campaign (verified across `biomate-nextflow-queue` /
`biomate-hpc-queue`, all active states). Total Batch spend ≈ well under the $5 cap
(each run ≈ 4–5.5 min wall, `process_medium`).

| Module | run_id | Status | Real outputs | Fast-exit |
|--------|--------|--------|-------------|-----------|
| **Enrichment (MSEA/ORA)** | `787aa206…287f` | ✅ succeeded (~5.0 min) | `msea_ora_result.csv` — top set **"Glycine and Serine Metabolism"** (12 hits, raw p=2.15e-08, FDR=2.11e-06), Warburg Effect, Arginine/Proline Metabolism; enrichment summary PNG (50 KB), mset-membership PNG (87 KB), `name_map.csv`, mSet.rds | ✅ task .exitcode 21 s after begin |
| **Pathway (MetPA)** | `1a33d1c9…2cfa` | ✅ succeeded (~5.5 min) | `pathway_results.csv` (p/`-log(p)`/Holm/FDR/Impact) — top **hsa00250** (Ala/Asp/Glu metabolism, p=3.63e-07, Impact=0.361), hsa00020 (TCA), hsa00630, hsa00260; `name_map.csv`, mSet.rds | ✅ |
| **Biomarker (ROC)** | `5bed8f91…0ccf` | ✅ succeeded (~5.5 min) | ROC curves PNG (16.9 KB), accuracy PNG, importance-feature PNG, `biomarker_feature_ranking.csv`, `metaboanalyst_roc_univ.csv` (AUC/Pval/Log2FC), mSet.rds | ✅ task .exitcode ~18 s after begin |
| **Statistical** | `5aa7c4df…2f510` | ✅ succeeded (~3.7 min) | fold-change + `t_test.csv` (top **M008/790.2644** t=-3.38, p=7.5e-4, FDR=0.045), `significant_features_foldchange.csv` (log2FC to -2.9), PLS-DA **VIP** (M008 VIP=2.33) + score/loadings + score-plot PDF, volcano, ORA enrichment, mSet.rds | ✅ task .exitcode 3 s after begin |

Modules 4–7 (mummichog, power, timeseries, meta) were **not** dispatched this session (task
scoped 3 representative modules + stat); their `.nf` + registrations are deployed and their
`// Input:` headers were cleaned the same way, so they are launch-ready. Deferred: network module.

### Bugs found & fixed during validation (all real Batch runs, root-caused)

1. **`// Input:` header prose broke the bioc launch wrapper (7 of 8 modules).**
   `_prepare_bioc_inputs` (nextflow_executor.py) parses the `// Input:` line as the
   machine-readable declared-input contract. The enrichment/pathway/biomarker/mummichog/
   power/timeseries/meta headers carried prose (`(ORA) OR …`, `one compound name per line`,
   `samples in rows, 2nd column = …`) which mis-tokenised into bogus required param names
   (`OR`, `compound`, `per`, `line)`, …). The wrapper then demanded those params, couldn't
   find them, and bailed → the plain `-entry` run can't bind the `take:` channel → the run
   died in prep with **no** `biomate_entry.nf` and `is_batch=false` (the first three
   dispatches all failed this way). **Fix (`3155e04fe`):** reduce each `// Input:` line to a
   bare comma-separated filename list (matching the working stat template); prose moved to an
   adjacent `// Input-note:` comment the parser ignores. After the fix all four re-dispatches
   reached Batch (`is_batch=true`).

2. **Stat module: `ImputeMissingVar` desynchronised `proc.cls` on clean data.**
   On a CONC table with **no** missing values, `ImputeMissingVar` (a raw/spectra-path
   function) rewrites `data_proc.qs` and re-derives the class-label vector, desyncing
   `proc.cls` from the preproc matrix; the next `FilterVariable → .get.latest.proc.matrix`
   then failed with **"Unable to resolve class labels for matrix source"** (the raw R error
   was itself masked by a secondary `object 'current.msg' not found` in MetaboAnalystR's
   `AddErrMsg`). SanityCheckData already replaces residual missing with half-min, so
   imputation is a no-op on clean data. **Fix (`3155e04fe`):** only call `ImputeMissingVar`
   when `dataSet$missingCount > 0`.

3. **Stat module: `FilterVariable` returns an INTEGER, not the mSet (off-web).**
   In MetaboAnalystR 4.x the off-web `FilterVariable` returns a status code (1 if missing
   values remain, else **2**) — it mutates via `.set.mSet()` (a pass-through no-op off-web
   whose return is discarded) and writes `data.filt.qs`/`data_proc.qs` to disk. The chained
   idiom `mSet <- FilterVariable(mSet, …)` therefore clobbered `mSet` with an atomic `2`, and
   `PreparePrenormData(mSet)` died with **"$ operator is invalid for atomic vectors"**
   (`pick.cls → mSetObj$dataSet`). **Fix (`38a5e2ae0`):** only re-bind `mSet` when the call
   returns an mSet-shaped list; otherwise keep the pre-filter object (its `proc.cls` stays
   valid; `PreparePrenormData` re-reads the filtered matrix from the `.qs` files). Verified
   the analogous `Normalization`/`PreparePrenormData` return the object, so only this call
   needed the guard.

4. **Stat module: a bare `$` in an R-body comment broke Groovy compilation.**
   The fix-3 comment contained a literal `$ operator` inside the process `"""…"""` script
   block; Nextflow's Groovy lexer treats `$` in a triple-double-quoted string as GString
   interpolation → `token recognition error at: ' '` → `MultipleCompilationErrorsException`
   (the dispatch failed in ~8 s before launching). **Fix (`7c4462676`):** rewrote the comment
   to avoid the bare `$`; verified with a local `nextflow run -stub` that DSL2 now compiles
   cleanly. (Pre-sync lesson: a comment edit inside a Groovy `"""` block is still code.)

All four fixes are genuine root-cause corrections (API-drift / parser-contract), not
workarounds — each was verified by a subsequent green Batch run.

### Fixtures used

- Enrichment / Pathway: `s3://biomate-nextflow-work/metaboanalystr_validation_20260930/compound_list.txt`
  (30 HMDB-mappable metabolite names).
- Biomarker: `…/metaboanalystr_validation_20260930/concentration_table.csv`
  (40 samples × 30 metabolites, 2-group Disease/Control, first 10 features differential).
- Statistical: `s3://biomate-nextflow-work/metaboanalystr_validation_20260929/`
  (`peak_intensity_table.csv` + `class_labels.csv` + `compound_list.txt`).

## Follow-up (scoped)

- **Network module** (deferred, see above): needs pre-staged interaction SQLite + headless
  table output path.
- **Mummichog / enrichment / pathway** rely on live `metaboanalyst.ca` egress — if that host
  is ever unreachable from Batch, pre-bake the `.qs` libs into the image.
- **QEA path** of the enrichment module and the **MetPA QEA** variant are implemented in the
  ORA/pathway files' code but the default validated path is ORA/pathora; QEA exercised only
  when a concentration table is supplied.
