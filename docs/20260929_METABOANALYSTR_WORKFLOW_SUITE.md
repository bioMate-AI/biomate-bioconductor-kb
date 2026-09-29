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
| — | Statistical | `metaboanalystr_statistical` / `metaboanalystr/` | peak table + 2-group labels (+ optional compound list) | none | ✅ (pre-existing, fixed) | ✅ | ⏳ see below |
| 1 | Enrichment (MSEA) | `metaboanalystr_enrichment` / `metaboanalystr_enrichment/` | compound list (ORA) or conc table+labels (QEA) | **yes** (mset `.qs` + compound DB from metaboanalyst.ca) | ✅ | ✅ | ⏳ |
| 2 | Pathway (MetPA) | `metaboanalystr_pathway` / `metaboanalystr_pathway/` | compound list + KEGG org | **yes** (KEGG API + lib) | ✅ | ✅ | ⏳ |
| 3 | Biomarker (ROC) | `metaboanalystr_biomarker` / `metaboanalystr_biomarker/` | conc table + 2-group labels | none | ✅ | ✅ | ⏳ |
| 4 | Mummichog | `metaboanalystr_mummichog` / `metaboanalystr_mummichog/` | peak list (m/z, p, t) + ppm + mode | **yes** (`<lib>.qs` from metaboanalyst.ca) | ✅ | ✅ | ⏳ |
| 5 | Power / sample-size | `metaboanalystr_power` / `metaboanalystr_power/` | pilot conc table + 2-group labels | none | ✅ | ✅ | ⏳ |
| 6 | Time-series (ASCA) | `metaboanalystr_timeseries` / `metaboanalystr_timeseries/` | conc matrix + 2-factor metadata (Time/Phenotype/Subject) | none | ✅ | ✅ | ⏳ |
| 7 | Meta-analysis | `metaboanalystr_meta` / `metaboanalystr_meta/` | ≥2 datasets (shared features, same 2-group labels) | none | ✅ | ✅ | ⏳ |
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
- Sync: `scripts/sync_to_dev.sh` (workflows + DB layers). **Result: _PENDING_.**

## Validation

_Pending — updated after Batch runs complete._

## Follow-up (scoped)

- **Network module** (deferred, see above): needs pre-staged interaction SQLite + headless
  table output path.
- **Mummichog / enrichment / pathway** rely on live `metaboanalyst.ca` egress — if that host
  is ever unreachable from Batch, pre-bake the `.qs` libs into the image.
- **QEA path** of the enrichment module and the **MetPA QEA** variant are implemented in the
  ORA/pathway files' code but the default validated path is ORA/pathora; QEA exercised only
  when a concentration table is supplied.
