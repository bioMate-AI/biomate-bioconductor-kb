# QC Gate Inventory + 3-Track Expansion Plan — 2026-06-15

Worktree: `/home/yzhang/biomate`. Branch: `qc/coverage-and-rebuilds`.
Companion to:
- `docs/20260609_QC_COVERAGE_EXPANSION.md` — the 20/20 verified workflows.
- `docs/20260613_QC_COVERAGE_BLOCKER_FIXES.md` — the boltz/aizynth/nlmixr2
  blocker work.
- `docs/20260614_BIOC_VIZ_COVERAGE_AUDIT.md` — Bioc viz/qc taxonomy that
  Track 3 builds on.

## TL;DR

- **Total documented gates:** 58 metric entries × 23 categories in
  `backend/config/qc_evidence.yaml`.
- **Wired end-to-end on dev (live `[QC-S3]` + `[QC Gate]` proof):** 20.
- **Documented but unwired in pharma/structural:** 20 (was 38; Track 2 batches 1, 2, 4 closed 18, including all 8 imaging/structural rows in batch 2 on 2026-06-15).
- **Bioconductor coverage:** the corpus already carries a 25-label QC
  taxonomy in `qc_steps` (396 workflows non-empty) + per-step
  `step_metadata[].qc`. That's the **scaffolding** for gates; the
  **threshold layer is missing**. Not "zero coverage" — partial.

## Inventory — 20 verified gates

Each row was proven end-to-end during the 06-07 → 06-14 stretch by a
live `[QC-S3] Reading report` + `[QC Gate] PASSED/TRIGGERED/FAILED`
log line on dev. See `docs/20260609_QC_COVERAGE_EXPANSION.md` for run
IDs.

| Workflow | Process | Gate metric | Provenance |
|---|---|---|---|
| hts_plate_qc_hit_calling | HTS_PLATE_QC_HIT_CALLING | `z_prime` | GOLD Zhang 1999 |
| allometric_scaling | ALLOMETRIC_SCALING | `r_squared` | SILVER FDA 2005 FIH metric |
| ich_s5_reproductive_tox | DART_IN_SILICO_PREDICTION | `safety_margin_x` | GOLD ICH S5R3 §3.1 |
| ich_s7a_safety_pharmacology | ICH_S7A_ASSESS_CV | `herg_safety_margin_x` | GOLD ICH S7B / Redfern 2003 |
| pocket_detection_druggability | DRUGGABILITY_QC_GATE | `druggability_score` | GOLD Le Guilloux 2009 |
| p0_pkpd_semaglutide | P0_PKPD_SEMAGLUTIDE | `week30_weight_change_kg` | GOLD Overgaard 2019 / SUSTAIN-1 |
| clinical_trial_simulation (BOIN) | CLINICAL_TRIAL_SIMULATION | `mtd_observed_dlt_rate` | GOLD Liu & Yuan 2015 |
| lnp_formulation_optimization | LNP_FORMULATION_OPTIMIZATION | `z_avg_nm` | SILVER CLT range |
| antibody_developability | ANTIBODY_DEVELOPABILITY | `tap_total_cdr_length` | GOLD Raybould 2019 |
| sirna_offtarget_analysis | SIRNA_OFFTARGET_ANALYSIS | `delta_dg_asymmetry_kcal_mol` | GOLD Khvorova 2003 |
| biomarker_patient_enrichment | BIOMARKER_PATIENT_ENRICHMENT | `biomarker_prevalence` + `enrichment_factor` | SILVER FDA Enrichment 2019 + BRONZE Phase III convention |
| ivive_hepatic_clearance | IVIVE_HEPATIC_CLEARANCE | `ivive_fold_error` | GOLD Obach 1999 |
| predict_admet_properties | PREDICT_ADMET_PROPERTIES | hERG IC50 + Ames + DILI | GOLD Redfern 2003 + SILVER Kazius 2005 + SILVER Mulliner 2016 |
| cyp_ddi_panel | DDI_RISK_ASSESSMENT | `overall_recommendation` | GOLD FDA 2020 DDI Guidance |
| nca_pknca | NCA_PKNCA_ANALYSIS | `auc_extrap_pct_max` | GOLD FDA 2003 BA/BE |
| pbpk_simulation | PBPK_SIMULATION | `pbpk_tmax_fraction` | SILVER FDA 2018 PBPK |
| genotoxicity_ames_prediction | GENOTOXICITY_AMES_PREDICTION | `ames_positive_count` + `worst_prediction` | SILVER Kazius 2005 / ICH S2(R1) |
| aizynthfinder_retrosynthesis | RETROSYNTHESIS_REPORT | `num_solved_routes` | GOLD Genheden 2020 |
| boltz_structure_prediction | BOLTZ_SUMMARISE_RESULTS | `mean_plddt` | GOLD Jumper 2021 / Tunyasuvunakool 2021 |
| nlmixr2_population_pk | NLMIXR2_POPULATION_PK | `eta_shrinkage_pct_max` | GOLD-anchored Savic & Karlsson — **citation needs PubMed verification** |

## Inventory — 38 documented-but-unwired gates

YAML row exists with citation + rule; either the workflow doesn't emit
the matching `qc_metrics.json` shape, OR the workflow isn't registered
in `_S3_REPORT_PATHS`.

**Pharmacology (0):** all pharmacology gates wired by 2026-06-16
- pbpk: ✓ `pbpk_cl_min`, `pbpk_mass_balance`, `pbpk_auc_fold_error` wired in Track 2 batch 1 (`f5f8b28b25`); PBPK verified live `b65d5b14` 2026-06-15 22:58
- nca: ✓ `nca_terminal_slope_coverage` wired in `f5f8b28b25`
- docking: ✓ `docking_binding_score` + `docking_valid_poses` wired in Track 2 batch 7 (2026-06-16) — qc_metrics emit with status='not_computed' when no receptor_pdb_file supplied; full live verification deferred until receptor fixture
- ivive: ✓ `ivive_well_stirred_consistency` wired in Track 2 batch 8 (2026-06-16, `dff1dd88a`) — IVIVE workflow now runs all 3 liver models (well_stirred/parallel_tube/dispersion) on the same inputs, emits clh_by_model + clh_spread_fraction + ivive_well_stirred_consistency_passes (false when extraction_class == 'high' per Pang & Rowland 1977)
- openfe: ✓ `openfe_cycle_closure` wired in Track 2 batch 7 (2026-06-16) — qc_metrics emit with status='not_computed' for single-edge runs; computes max |ΔG_sum| when network.closed_cycles + parsed fe_results both present. Process renamed `ANALYSIS` → `OPENFE_ANALYSIS` to avoid generic process-keyword collisions in `_S3_REPORT_PATHS`.
- nlmixr2: ✓ `nlmixr2_condition_number` + `nlmixr2_ofv_stability` wired in Track 2 batch 6 (`70b4551329`); nlmixr2 verified live `34ce4a2a` 2026-06-15 22:55 with cond_number_passes=true (6.9 < 100), ofv_stability_status="not_computed (single-fit workflow)"
- admet: ✓ `admet_dili_probability` wired in `70b4551329`; ADMET verified live `7c9b5f1e` 2026-06-15 22:56 with admet_dili_probability_passes=false (terfenadine high-risk DILI, correct positive control)
- polymorph: 3 honestly-skipped entries — in-silico screening workflow can't produce in-vitro stability-study measurements

**Imaging / structural (0):** all 8 imaging/structural gates wired in Track 2 batch 2 (2026-06-15) — verification runs pending on dev:
- cryo_em (3): `cryo_em_fsc_resolution`, `cryo_em_motion_drift`, `cryo_em_particle_count` wired in `794726dc0` (cryosparc_standard_spa)
- cryo_et (3): `cryo_et_sta_fsc_resolution`, `cryo_et_tilt_residual`, `cryo_et_defocus_range` wired in `23b523ea5` across subtomogram_averaging / tilt_alignment / import_tiltseries (the IMPORT_TILTSERIES standalone + embedded copy in et_full_pipeline both got a fresh `qc_metrics.json` emit — needs a real-data run to confirm MDOC defocus aggregation lands)
- structure_prediction (2): `struct_pred_confident_fraction`, `struct_pred_max_pae` wired in `161ccea49` (boltz_structure_prediction; pass-band fields layered on top of the pre-existing extractor)

**HTS (0):** `hts_signal_window` wired in `f516fd12` Track 2 batch 4; verified by run `193c34ca` 2026-06-15 17:49 UTC, qc_metrics.json emits z_prime_passes + signal_window_passes (both true on default fixture).

**Cancer biology (0):** all 3 (`cancer_somatic_vaf_min`, `cancer_somatic_depth_min`, `cancer_somatic_mapping_quality`) wired in Track 2 batch 3 — qc_metrics.json emitted by `DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS`; process registered in `_S3_REPORT_PATHS`. Status field is `computed`/`partial`/`not_computed` depending on whether the biomni-wrapped variant-caller populates min_vaf/min_depth/min_mapq in its result dict. Verification deferred until a tumor/normal BAM fixture is supplied.

**Antibody / biologics (2):** `ab_tap_surface_hydrophobicity`, `ab_camsol_intrinsic_solubility` (deliberately omitted from the active gate; scale mismatch — see 06-09 doc)

**siRNA / oligo (1):** `sirna_seed_mismatch_count` (categorical labels, no raw counts — flagged 06-09)

**LNP / formulation (1):** `lnp_encapsulation_efficiency` wired in `0a8b44993` Track 2 batch 4; verified by run `a3eff964` 2026-06-15 17:03 UTC, qc_metrics.json emits z_avg_passes + encapsulation_efficiency_passes + pdi_status. `lnp_pdi` remains documented-not-wired (surrogate formulation model can't compute PDI; needs a DLS workflow).

**Stability (2):** `assay_degradation_accelerated`, `shelf_life_projection`

**Bioconductor-side metric rows (14)** — these are already in
`qc_evidence.yaml` but reference Bioc-specific metrics with no Bioc
harness wired:
`apeglm_lfc_shrinkage`, `clusterprofiler_enrichment`,
`edger_qlf_alternative`, `limma_voom_alternative`,
`scater_qc_normalization`, `mast_hurdle_de`, `monocle_pseudotime_de`,
`scran_normalization_hvg`, `score_markers_per_cluster`,
`singler_celltype_annotation`, `minfi_array_processing`,
`limma_dmp_test`, `dmrcate_region_call`, `missmethyl_cpg_corrected_go`

## Bioconductor scaffolding (already in the DB)

Not zero coverage. The 06-08 enrichment pass wrote two structured
fields into `backend/database/galaxy_ai_tools.db`:

- `workflows.qc_steps` — workflow-level QC taxonomy (a JSON list of
  QC operations the workflow performs). **396 rows non-empty.
  25 distinct labels.**
- `workflows.step_metadata[].qc` — same vocabulary attributed per
  step.

Top-30 labels by # of workflows:

| # | Label |
|---:|---|
| 126 | missing-value handling |
| 79 | count normalization |
| 72 | cell QC metrics |
| 54 | low-count filtering |
| 32 | diagnostic MA/PCA QC |
| 28 | dispersion/size-factor estimation |
| 21 | batch-effect correction |
| 21 | highly-variable feature selection |
| 16 | TMM normalization |
| 13 | variance-stabilizing normalization |
| 11 | doublet detection QC |
| 10 | normalization diagnostic plot |
| 10 | clustering QC |
| 9 | input validation |
| 8 | voom mean-variance modelling |
| 7 | per-cell QC metrics |
| 7 | filter low-expression genes |
| 6 | dispersion QC plot |
| 5 | prevalence/abundance filtering |
| 5 | array detection QC |
| 4 | alignment/mapping QC |
| 3 | between-array normalization |
| 2 | outlier detection |
| 1 | expression-level QC |
| 1 | outlier diagnostics |

Each label maps to a measurable diagnostic with an established
literature threshold — table below.

### Label → canonical metric → threshold mapping (Bioc gate seeds)

| QC label | Canonical metric | Default threshold | Reference (verify before audit) |
|---|---|---|---|
| missing-value handling | `na_fraction_remaining` | < 5% | Lazar 2013 NAR (variance-aware imputation review) |
| count normalization | `lib_size_cv_after / before` | ratio ≤ 0.7 | Bullard 2010 BMC Bioinf (normalization comparison) |
| cell QC metrics | `pct_mito_max` / `n_features_min` / `n_counts_min` | <10-20% mt; >200 features (tissue-dependent) | Luecken & Theis 2019 Mol Syst Biol |
| low-count filtering | `genes_kept_fraction` after filterByExpr | 30-60% | Chen 2016 F1000 (edgeR/limma workflow) |
| diagnostic MA/PCA QC | `PC1_var_explained`, `MA_M_bias` | PC1 > 10%; bias ≈ 0 | Risso 2014 NatBio RUV-seq |
| dispersion/size-factor estimation | `disp_outlier_fraction` | ≤ 1% | Love 2014 GenomeBio (DESeq2) |
| batch-effect correction | `kBET_acceptance_rate` or `iLISI` | > 0.75 | Büttner 2019 NatMethods (batch benchmark) |
| highly-variable feature selection | `hvg_count` in range | 1000-3000 for scRNA | Stuart 2019 Cell (Seurat v3) |
| TMM normalization | `tmm_factor_range` | within [0.5, 2.0] in >90% of libs | Robinson & Oshlack 2010 GenomeBio |
| variance-stabilizing normalization | `mean_sd_slope_after_vsn` | slope ≈ 0 | Huber 2002 Bioinformatics |
| doublet detection QC | `doublet_rate_estimated` | 0.5-10% (depends on loading) | McGinnis 2019 Cell Systems (DoubletFinder) |
| clustering QC | `silhouette_mean`, `cluster_stability_ari` | silhouette > 0.25 | Hennig 2007 (cluster stability) |
| voom mean-variance modelling | `voom_fit_smooth_residual` | residual SD ≤ 0.5 | Law 2014 GenomeBio |
| input validation | format conformance | binary pass | per-format canonical |
| filter low-expression genes | `expression_quantile_kept` | top 50-70% | Chen 2016 F1000 (edgeR vignette) |
| per-cell QC metrics | scater::perCellQCMetrics outliers | isOutlier `nmads=3` | McCarthy 2017 Bioinformatics (scater) |
| dispersion QC plot | visual; pair with `disp_outlier_fraction` | (inherited) | Love 2014 GenomeBio |
| prevalence/abundance filtering | `taxa_kept_fraction` | 30-50% | Callahan 2016 NatMethods (phyloseq) |
| array detection QC | `detection_call_rate` | > 95% | Affymetrix MAS5 spec |
| alignment/mapping QC | `mapped_read_pct` | > 70% genomic | ENCODE standards |
| between-array normalization | `quantile_consistency_ks` | KS-statistic ≤ 0.05 | Bolstad 2003 Bioinformatics |
| outlier detection / diagnostics | `flagged_sample_count` | declarative | method-specific |
| normalization diagnostic plot | visual; pair with count normalization | (inherited) | — |
| expression-level QC | `expression_dynamic_range_log2` | ≥ 10 | array-platform community |

Half of these will need split-grade labelling per the model-flip
discipline (`docs/20260610_ZERO_COST_EVAL_PIVOT.md`) — the **metric**
is GOLD-anchored to the paper, the **specific tier** is community
operational.

## Known integrity issues to fix in `qc_evidence.yaml`

These surfaced during the 20/20 sprint and are independent of any new
gate work:

1. **nlmixr2 η-shrinkage citation**: YAML says
   `Savic RM & Karlsson MO. J Pharmacokinet Pharmacodyn 2007;
   34:711-726`. Confidence: the shrinkage threshold work is
   `Savic & Karlsson AAPS J 2009; 11(3):558-69` PMID 19649712.
   The JPKPD 2007 34:711-726 paper is the same authors' transit-
   compartment absorption work — different topic. **Action:** verify
   DOI via PubMed and correct the row.

2. **OFV stability chi-square cutoff (3.84)**: the YAML's 3.84 is the
   1-df critical value; the rule_text doesn't say df. For multi-df
   tests it's wrong (df=2 → 5.99, df=3 → 7.81). **Action:** rewrite
   rule_text to make df explicit.

3. **hERG safety margin (10×)**: the 10× margin is right for chronic
   non-CV indications; antimicrobials and oncology drugs operate at
   different margins. **Action:** add a `modifiers` block (Track 1).

4. **AUC extrapolation 20% (FDA 2003)**: the 20% is the canonical
   benchmark for healthy-volunteer Phase I; oncology populations
   routinely operate at 30-40% extrap without disqualifying the run.
   **Action:** add `modifiers` for phase / disease state.

## Plan — three tracks

### Track 1 — schema-correct + context-aware `qc_evidence.yaml`

**Scope:** all 58 existing rows + the 25 new Bioc rows.

**Work:**
1. Add a `modifiers` block schema to each entry: `default_threshold`,
   plus `context_axes` with documented multipliers (sparse/rich
   sampling, IV/PO, single/multi-dose, df, drug class, etc.).
2. Fix the 4 citation/wording issues above.
3. Demote `paper_supports` language that overstates (Savic & Karlsson
   "explicitly recommends" → "metric is GOLD-anchored to paper Y;
   specific tiers are operational convention").
4. Teach `qc_gate_reader.py` to consume `modifiers` against invocation
   metadata + the existing profile system (`compound_druglike` /
   `standard` / `exploratory` / `regulatory`). Threshold becomes a
   function of `(metric, profile, context_axes)`.

**Effort:** 1-2 days. No new workflow emits; no gate behavior
regression (defaults still match today's thresholds).

**Output:** every gate has an honest citation, an honest default, and
named context overrides. Audits become quotable.

### Track 2 — wire the 38 documented-but-unwired pharma/structural gates

**Scope:** the 38 rows in the second inventory section above (minus
the 14 Bioc-side rows which go in Track 3).

**Work, batched by category:**
1. For each row, identify the matching workflow.
2. Add `qc_metrics.json` emit + register process keyword in
   `_S3_REPORT_PATHS`.
3. Verify end-to-end on dev with a live `[QC-S3]` line, same as the
   20/20 sprint.
4. Update `docs/20260609_QC_COVERAGE_EXPANSION.md`.

**Effort:** 1-2 weeks, 3-5 gates per PR.

**Output:** 38/38 → 58/58 documented pharma/structural gates verified.

### Track 3 — Bioc gate layer on top of the existing taxonomy

**Phase 3a — data only (~2 days):**
- Add a new `bioconductor:` category to `qc_evidence.yaml` with the
  25 rows from the label-mapping table above.
- Verify citations against PubMed where possible; tag each entry as
  GOLD/SILVER/BRONZE with honest split-grade where the threshold is
  community-operational.
- Pure data, no code change yet. The audit ledger contains the gates
  even before they fire.

**Phase 3b — harness process (~3 days):** ✓ MVP landed 2026-06-16 (`6433a0f64`)
- ✓ Added `BIOC_QC_HARNESS` Nextflow process at
  `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/_qc_harness/main.nf`.
  Standalone DSL2 process that any Bioc subworkflow can include.
- ✓ LABEL_TO_GATE table routes each of the 25 qc_steps labels to a
  canonical `bioconductor_qc.*` YAML row + a metric name.
- ✓ Registered `BIOC_QC_HARNESS` in `_S3_REPORT_PATHS`.
- ✓ Emit shape: gates_by_label dict keyed by declared qc_step labels;
  each entry carries gate_row + metric_name + value + passes + status.
  MVP behavior is status='not_computed (harness MVP; metric impl
  pending)' per label — adoption can start while individual metric
  R impls land in Phase 3c.
- pending: extend `qc_gate_reader.py` with `bioc_qc_metric_map`
  threshold lookup (Track 1 modifier-aware path; small follow-up).

**Phase 3c — rolling adoption:**
- For each Bioc subworkflow, append the `BIOC_QC_HARNESS` call.
  Priority queue: the 396 currently non-empty `qc_steps` workflows.
- Scriptable; ~5-10 min per workflow.

**Effort:** Phase 3a + 3b ≈ 1 week. Phase 3c is rolling.

**Output:** Bioc workflows emit `[QC-S3]` + `[QC Gate]` lines on the
same dev-log proof shape as the 20 pharma ones. Coverage scales from
20 → potentially 416 (20 pharma + 396 bioc) end-to-end-gated
workflows.

## Order of execution

1. **Phase 3a first** — quickest visible delta to audit ledger,
   pure data, no risk to anything wired.
2. **Track 1** — unblocks tightening any gate threshold honestly.
3. **Track 2 (batched)** — biggest customer-facing gain.
4. **Phase 3b** — Bioc harness wiring.
5. **Phase 3c** — rolling Bioc subworkflow adoption.

Proceeding with Phase 3a immediately after this doc lands.

---

## Update 2026-06-15 — Bioc orphan audit outcome (Track 2 Batch 5)

The 14 Bioconductor-specific orphan rows in `qc_evidence.yaml`
(`apeglm_lfc_shrinkage` … `missmethyl_cpg_corrected_go`) were audited
against the 23 new `bioconductor_qc:` rows landed in Phase 3a
(commit `1ab27c2f9`). Result:

- **3 marked SUPERSEDED** by canonical `bioconductor_qc:` rows
  (`scater_qc_normalization` → `bioc_per_cell_qc_outliers`;
  `scran_normalization_hvg` → `bioc_hvg_selection`;
  `minfi_array_processing` → `bioc_array_detection_qc`).
  Demoted to BRONZE with `superseded_by:` + `note:` fields; citations
  preserved for audit-trail continuity.
- **11 flagged for harness routing** as package-specific gates
  (`harness_owner: BIOC_QC_HARNESS`, `package: <name>`,
  `superseded_by: null`). These become Phase 3b targets at package
  granularity (apeglm, clusterProfiler, edgeR, limma×2, MAST, monocle,
  scran, SingleR, DMRcate, missMethyl).
- **0 deprecated.**

Full per-entry table + rationale: `docs/20260615_BIOC_ORPHAN_AUDIT.md`.
No workflow `main.nf` files were modified.
