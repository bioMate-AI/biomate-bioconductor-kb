# QC Tracks 1 / 2 / 3 — Session Writeup, 2026-06-15

Worktree: `/home/yzhang/biomate`. Branch: `qc/coverage-and-rebuilds`.
Companion to:
- `docs/20260615_QC_GATE_INVENTORY_AND_PLAN.md` — the master plan that
  scoped this session.
- `docs/20260615_BIOC_ORPHAN_AUDIT.md` — Batch 5 audit ledger.
- `docs/20260609_QC_COVERAGE_EXPANSION.md` — the 20/20 verified
  workflows table (run IDs).

## TL;DR

- **Coverage went 20 → 24+ verified end-to-end** during the session,
  plus 20+ additional gate rows wired in the schema but pending fixture
  / context for an end-to-end run.
- **Documented-but-unwired collapsed 38 → 2** (docking + openfe — both
  need fixtures).
- All three audit-honesty tracks landed at least one production-shaped
  proof:
  - **Track 1**: schema-correct + context-aware `qc_evidence.yaml` with
    the worked-example modifier system + reader plumb.
  - **Track 2**: wired 22+ documented-but-unwired pharma/structural/
    cancer/Bioc gates across 6 batches.
  - **Track 3**: 23 new Bioconductor QC gate rows + classification of
    the 14 legacy orphan rows.
- **Monitor S3 pagination race fixed** as a side-effect of the HTS
  verification — pre-existing bug that would silently miss
  qc_metrics.json files on busy runs.

## Commits — full session log on `qc/coverage-and-rebuilds`

In reverse chronological order (most recent first):

| Commit | Subject | Notes |
|---|---|---|
| `0d9d2617c6` | fix(nlmixr2): NULL → NA serialization | Same jsonlite gotcha that hit ofv/cond_number earlier |
| `70b4551329` | feat(qc): Track 2 batch 6 — nlmixr2 cond_number + ofv + admet_dili + antibody documentation | Last 4 of the 6 trailing gaps |
| `8ab8f6853a` | feat(qc): Track 2 batch 3 — wire 3 cancer biology somatic gates | VAF / depth / MAPQ |
| `e8935ada1a` | docs(qc-inventory): mark imaging/structural batch wired (8 → 0) | Bookkeeping for Batch 2 |
| `161ccea493` | feat(qc): Track 2 batch 2 — wire structure_prediction gates | Boltz confident_fraction + max_pae pass-band |
| `23b523ea54` | feat(qc): Track 2 batch 2 — wire cryo_et gates | sta_fsc_resolution + tilt_residual + defocus_range |
| `3ceadca9d9` | docs(qc): Track 2 Batch 5 — Bioc orphan audit ledger | Audit doc + inventory update |
| `98ac767749` | chore(qc-evidence): Track 2 Batch 5 — audit 14 Bioc orphan rows | YAML edits, 3 SUPERSEDED + 11 PACKAGE-SPECIFIC |
| `794726dc09` | feat(qc): Track 2 batch 2 — wire cryo_em gates | fsc_resolution + motion_drift + particle_count |
| `b658aedbe3` | fix(qc-monitor): paginate S3 list when probing for qc_metrics.json | Root cause of the HTS race |
| `cbcb91f11a` | docs(qc-coverage): mark batch 4 verified | HTS + LNP live verification |
| `f516fd12a0` | fix(hts): coerce numpy bools to Python bool for JSON serialization | numpy.bool_ → bool() |
| `0a8b449934` | feat(qc): Track 2 batch 4 — wire HTS signal_window + LNP encap_efficiency gates | First batch with explicit threshold + pass-band fields |
| `f5f8b28b25` | feat(qc): Track 2 batch 1 — wire 4 pharmacology gate gaps | PBPK cl_min + mass_balance + auc_fold_error + NCA terminal_slope |
| `d6ca1e5882` | feat(qc-monitor): Track 1 step 4 — plumb modifier context end-to-end | _get_threshold_with_context + _build_modifier_context |
| `5c8e19359c` | feat(qc-gate): Track 1 step 2 — modifiers reader + first wired gate | hERG margin proof |
| `f0203099e0` | fix(qc-evidence): Track 1 step 1 — citation integrity + modifiers schema seed | nlmixr2 + nca + hERG citations corrected |
| `1ab27c2f97` | feat(qc-evidence): Track 3 Phase 3a — 23 bioconductor QC gate rows added | New `bioconductor_qc` category |
| `b87d08ed21` | docs(qc): full QC gate inventory + 3-track expansion plan | The plan doc that scoped this session |

(Plus several parallel-session commits not enumerated above that the
branch carries: rationale_registry, WhyAnchor, etc.)

## Track 1 — schema-correct + context-aware `qc_evidence.yaml`

**Goal**: every gate has an honest citation, an honest default, and
named context overrides.

| Sub-step | Status | Commit |
|---|---|---|
| 1. Citation integrity fixes (4 entries: η-shrinkage venue/year, OFV chi-square df, hERG by indication, AUC extrap by phase) | ✓ | `f0203099e` |
| 2. Modifiers reader + 1 wired gate (hERG via `resolve_thresholds`) | ✓ | `5c8e19359` |
| 3. Demote overclaiming `paper_supports` across ~70 entries | ~partial (4 fixed entries + 23 new Bioc entries got split-grade language; remaining ~70 still need audit) | — |
| 4. Plumb context from caller through `qc_trace_monitor` to gate functions | ✓ | `d6ca1e5882` |

**Standalone smoke-test result** (recorded in the Track 1 commits):

| Context | fail_min | Effect |
|---|---:|---|
| (none) | 20.0% | legacy default — unchanged |
| `phase=discovery` | 50.0% | early screening, loose |
| `phase=regulatory` | 20.0% | pre-NDA, default-strict |
| `population=oncology` | 50.0% | sicker patients sample harder |

Same metric, different verdict by context — the audit-honest behavior
the user asked for.

## Track 2 — wire the 38 documented-but-unwired pharma/structural gates

**Goal**: workflow main.nf files emit `qc_metrics.json` against every
documented gate row, then the QC monitor reads them on dev.

Batched by domain for minimum sync cycles:

| Batch | Scope | Commit(s) | Live verification |
|---|---|---|---|
| 1 | Pharmacology — PBPK ×3 + NCA ×1 | `f5f8b28b25` | ✓ PBPK live `b65d5b14` 2026-06-15 22:58 UTC |
| 2 | Imaging / structural — cryo_em ×3, cryo_et ×3, struct_pred ×2 | `794726dc09`, `23b523ea54`, `161ccea493`, `e8935ada1a` | pending fixtures |
| 3 | Cancer biology — somatic VAF / depth / MAPQ | `8ab8f6853a` | pending tumor/normal BAM fixture |
| 4 | HTS signal_window + LNP encap_efficiency | `0a8b449934`, `f516fd12a` (bool fix), `cbcb91f11a` (doc) | ✓ both live |
| 5 | Bioc 14 orphans — classify against Phase 3a canonical rows | `98ac767749`, `3ceadca9d9` | doc-only, no run needed |
| 6 | nlmixr2 cond_number + ofv + admet_dili + antibody documentation | `70b4551329`, `0d9d2617c6` (NULL fix) | ✓ nlmixr2 + ADMET live |
| 7 | docking + openfe gates (2026-06-16) | `dd6a885c23` | pending receptor PDB / closed-cycle fixtures |

### Final live verification run IDs

| Workflow | Run ID | UTC | qc_metrics fields confirmed |
|---|---|---|---|
| HTS | `193c34ca-bc46-42a8-85b9-f903c62ff9de` | 06-15 17:49 | z_prime + threshold + passes, signal_window + threshold + passes |
| LNP | `a3eff964-5d8e-4945-975c-345d6e9f23cd` | 06-15 17:03 | z_avg_passes, pdi_status, encapsulation_efficiency_passes |
| nlmixr2 | `34ce4a2a-dd7f-4add-89e2-28b7e6430b2d` | 06-15 22:55 | eta_shrinkage_passes=false (87.2% > 20%), condition_number_passes=true (6.9 < 100), ofv_stability_status="not_computed (..)" |
| ADMET | `7c9b5f1e-bfea-436d-b431-a00a235a5733` | 06-15 22:56 | admet_dili_probability_passes=false (terfenadine high-risk DILI; correct positive control), updated 3-citation tier |
| PBPK | `0c9d4120-b808-4b2e-ae8a-917e592a5e2a` | 06-15 22:58 | tmax_within_window=true, cl_within_floor=true, mass_balance_passes=true, auc_fold_error=null (no observed supplied) |

### Honestly skipped rows (5 — workflow can't compute, won't fabricate)

- `lnp_pdi` — surrogate formulation model can't compute polydispersity;
  needs a DLS workflow.
- `polymorph_stability` (2 entries) — in-silico screening can't produce
  in-vitro stability-study measurements.
- `ab_tap_surface_hydrophobicity` — workflow's agg_score has inverted
  semantics vs Raybould 2019 TAP PSH.
- `ab_camsol_intrinsic_solubility` — CamSol-proxy patch score on a
  different numeric scale vs the real CamSol gate.

Each row emits a structured `*_status: not_used (…)` field in
qc_metrics.json so the audit trail records why the gate didn't fire
instead of leaving it silently dark.

### Batch 7 closure (2026-06-16) — docking + openfe wired

**Commit:** `dd6a885c23`

- `DOCKING_AUTODOCK_VINA` now emits `docking_binding_score_passes`
  (best_score ≤ -7 kcal/mol; BRONZE Trott & Olson 2010) and
  `docking_valid_poses_passes` (n_poses ≥ 3; BRONZE AutoDock community)
  alongside the existing best_score / n_ligands_docked fields. Status
  becomes `not_computed (no receptor supplied; gate awaits
  receptor_pdb_file fixture)` when no receptor PDB is given.
- `OPENFE_ANALYSIS` (renamed from generic `ANALYSIS` to avoid a
  `_S3_REPORT_PATHS` keyword collision risk) emits
  `openfe_cycle_closure_passes` (max |ΔG_sum| ≤ 1 kcal/mol; GOLD
  Mey 2020) plus context (ddg + sem + MBAR overlap quality). When the
  run is a single edge (no closed-cycle topology) the status records
  `not_computed (single-edge run; cycle closure needs ≥3-edge closed
  loop)`.
- Both registered in `_S3_REPORT_PATHS`.

### Remaining unwired after batch 7 — exactly 1

- `ivive_well_stirred_consistency` — gate requires the IVIVE workflow
  to compute the same CL prediction under multiple liver models
  (well-stirred vs parallel-tube vs dispersion) and compare. That's
  workflow-logic work, not a metric emit. Deferred — different shape
  of work than batches 1-7.

## Track 3 — Bioc gate layer

**Goal**: bring the 2,450-workflow Bioconductor corpus into the
gate-coverage story by leveraging the existing `qc_steps` taxonomy
(396 workflows non-empty, 25 distinct labels).

| Phase | Status | Commit |
|---|---|---|
| 3a — Data only: add `bioconductor_qc:` category with 23 rows | ✓ | `1ab27c2f97` |
| 3b — Harness process + reader wiring | pending | — |
| 3c — Rolling adoption per Bioc subworkflow | pending | — |

The audit doc `docs/20260615_BIOC_ORPHAN_AUDIT.md` (Batch 5) classified
the 14 pre-existing orphan rows:
- 3 marked SUPERSEDED — point to a canonical `bioconductor_qc.*` row,
  demoted to BRONZE for audit continuity.
- 11 marked PACKAGE-SPECIFIC — gain a `harness_owner` + `package` field
  so Phase 3b's BIOC_QC_HARNESS can route to them.
- 0 deprecated.

## Monitor S3 pagination race fix

**Surface**: HTS run `193c34ca` 2026-06-15 17:49 UTC published
`qc_metrics.json` correctly to S3, but the QC monitor logged "No
report found" and didn't fire the gate.

**Root cause** (commit `b658aedbe3`): `_read_s3_report_metrics` called
`list_objects_v2` exactly once and inspected only the first page. S3
caps a page at 1000 keys; HTS's per-plate output keys pushed
`qc_metrics.json` past page 1, while the alphabetically-earlier LNP
run fit on page 1 (which is why LNP's same code path worked).

**Fix**: switch to `s3.get_paginator("list_objects_v2").paginate(...)`
accumulation. Smoke test at
`backend/tests/test_qc_trace_monitor_s3_pagination.py` (3/3 PASS)
covers (1) HTS regression where qc_metrics.json appears only on page
2 after 1000 sibling keys; (2) LNP-style single-page hit at a step
prefix; (3) true-absence returns None.

## Honest scoring of what improved

| Bucket | Session start | Session end |
|---|---:|---:|
| Verified end-to-end live (with [QC-S3] + [QC Gate] proof) | 20 | 24+ |
| Documented-but-unwired pharma | 12 | 1 (only `ivive_well_stirred_consistency` — needs workflow-logic change, not just an emit) |
| Documented-but-unwired imaging/structural | 8 | 0 |
| Documented-but-unwired cancer biology | 3 | 0 |
| Documented-but-unwired HTS/LNP | 3 | 0 |
| Documented-but-unwired antibody/biologics | 2 | 0 (documented-not-used) |
| Documented-but-unwired Bioc orphans | 14 | 0 (classified) |
| Documented-but-unwired total | 38 | **1** (`ivive_well_stirred_consistency`) |
| Honestly skipped (workflow-scope mismatch) | 0 | 5 |
| New Bioc gate rows (Phase 3a) | 0 | 23 |
| Citations corrected | 0 | 4 |
| Modifier-aware gates in YAML | 0 | 4 |

## Discipline observations worth keeping

1. **Always wrap booleans with Python `bool(...)`** in workflow Python
   blocks that produce `qc_metrics.json`. Numpy comparison returns
   `numpy.bool_` which `json.dump` rejects. Cost me a re-sync on the
   HTS first attempt (commit `f516fd12a`).

2. **Always use `NA_real_` / `NA`, not `NULL`, in R when emitting via
   `jsonlite::write_json(..., auto_unbox = TRUE)`**. NULL serializes
   as `{}` (empty dict) and silently corrupts the schema. Cost me a
   second nlmixr2 run cycle (commit `0d9d2617c6`).

3. **The "emit schema; status=not_computed" pattern** is the right
   answer for gates whose workflow has scope mismatches (in-silico vs
   in-vitro, surrogate vs measured). It keeps the gate row in the
   audit ledger without fabricating a verdict. Used in cancer biology,
   antibody, polymorph stability, PBPK auc_fold_error, nlmixr2 OFV.

4. **Parallel agents are highly effective** for non-conflicting work —
   the agent team (Batch 2 + Batch 5 + monitor fix) landed three real
   commits + a 3/3 PASS smoke test while I was reviewing the LNP
   verification artifact.

5. **Provenance split-grading** ("GOLD-metric / SILVER-tier") needs to
   become the default formatting for every gate row that has a
   community-operational threshold attached to a literature-anchored
   metric. The 4 retrofitted entries are the worked examples.

## What's left for next session

1. ~~Wire docking + openfe gates with the emit-schema pattern.~~ ✓ done 06-16 (`dd6a885c23`)
2. **Implement `ivive_well_stirred_consistency`** — gate the IVIVE
   workflow to run the well-stirred prediction alongside parallel-tube
   and dispersion models, then compare. Pure workflow-logic change;
   the metric is `(CL_ws - CL_pt) / CL_ws` or similar tolerance check
   per Pang & Rowland 1977.
3. Complete Track 1 step 3 — sweep the remaining ~70 entries to demote
   overclaiming `paper_supports` language.
4. Track 3 Phase 3b — build `BIOC_QC_HARNESS` process + wire the
   `qc_gate_reader.bioc_qc_metric_map` lookup.
5. Schedule end-to-end verification runs for the gate batches that
   landed schema-only but didn't get a live run (Batch 2 imaging/
   structural; Batch 3 cancer biology; Batch 7 docking + openfe — all
   need fixtures).
6. Audit-grade PubMed cross-check for the citations tagged
   `NEEDS_PUBMED_VERIFY` (mainly the η-shrinkage 2009 AAPS J entry).
