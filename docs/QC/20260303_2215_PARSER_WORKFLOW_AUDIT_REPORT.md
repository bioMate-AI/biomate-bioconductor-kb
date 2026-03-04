# QC Parser–Workflow Alignment Audit Report
**Date:** 2026-03-03 22:15
**Branch:** `connection_formal`
**Author:** Claude (audit + fix session)

---

## Summary

A full audit of all QC parsers in `qc_trace_monitor.py` against actual Nextflow workflow output files. Found and fixed **6 mismatches** where parsers returned `None` silently — meaning QC gates would never fire in production even though tests passed.

---

## Findings

### ✅ REAL (verified parser↔workflow alignment)

| Domain | Parser method | Workflow file | Status |
|---|---|---|---|
| Population PK | `_parse_nlmixr2_results()` | `nlmixr2_population_pk/main.nf` | MATCH |
| NCA PK | `_parse_nca_results()` | `nca_pknca/main.nf` | MATCH |
| IVIVE | `_parse_ivive_results()` | `ivive_hepatic_clearance/main.nf` | MATCH |
| ADMET | `_parse_admet_toxicity_metrics()` | `predict_admet_properties/main.nf` | MATCH |
| SMILES QC | `_parse_smiles_metrics()` | In-process validation (no JSON needed) | MATCH |
| Motion correction | `_parse_motion_correction_metrics()` | SPA pipeline `.txt` output | MATCH |
| RNA-seq alignment | `_parse_alignment_metrics()` | `*.txt` + STAR `Log.final.out` | MATCH |
| Coverage | `_parse_coverage_metrics()` | `*.mosdepth.summary.txt` | MATCH |
| scRNA CellRanger | `_parse_cellranger_metrics()` | `cellranger_metrics.json` / CSV | MATCH |
| Kraken2 | `_parse_kraken2_metrics()` | `kraken2_report.txt` | MATCH |
| ATAC-seq FRiP | `_parse_chip_seq_metrics()` | `*.flagstat` / `*.idxstats` | MATCH |

---

### ✗ FIXED (were silently returning None in production)

#### Fix 1 — Sharpening (SPA step 23)
- **Was:** Parser searched `sharpening_results.json` with `bfactor_angstrom_squared`
- **Reality:** Workflow writes `sharpening_report.json` with `b_factor_applied`
- **Fix:** Added `sharpening_report.json` to search list; added `b_factor_applied` as field alias
- **Test fix:** `_sharpen_writer` now writes `sharpening_report.json` + `b_factor_applied`

#### Fix 2 — Local resolution (SPA step 22)
- **Was:** Parser searched `local_resolution_results.json` with `std_spread_angstrom`
- **Reality:** Workflow writes `local_resolution_report.json` with `std_resolution_angstroms`
- **Fix:** Added `local_resolution_report.json` to search list; mapped `std_resolution_angstroms` → `std_spread_angstrom`
- **Test fix:** `_localres_writer` now writes `local_resolution_report.json` + `std_resolution_angstroms`

#### Fix 3 — Molecular docking (AutoDock Vina)
- **Was:** Parser searched `docking_results.json` with `best_score_kcal_mol`
- **Reality:** Workflow writes `docking_autodock_vina_results.json`; scores dict was computed in subprocess but discarded in outer function
- **Fix:** (a) Workflow now saves `best_score_kcal_mol = min(scores.values())` and `n_poses_generated` to top-level JSON; (b) parser now reads `docking_autodock_vina_results.json` first, with fallback derivation from nested `scores` dict
- **Test fix:** `_docking_writer` now writes `docking_autodock_vina_results.json` in actual workflow format

#### Fix 4 — QSAR (phantom workflow)
- **Was:** Parser and tests existed for `qsar_results.json` but NO Nextflow workflow existed
- **Fix:** Created `pharmacology/qsar_rf_model/main.nf` — scikit-learn RandomForest with 5-fold CV, Morgan fingerprints, writes `qsar_results.json` with `cv_r2_score`, `cv_rmse`, `n_compounds`, `model_type`
- **Test format:** Already correct — QSAR test writers pre-dated the workflow; no test changes needed

#### Fix 5 — CTF estimation (CryoSPARC SPA pipeline)
- **Was:** Parser only read CTFFIND4-format `.txt` files
- **Reality:** SPA pipeline writes `micrographs_ctf.cs` (per-micrograph JSON) and `ctf_report.json` (summary)
- **Fix:** Parser now reads `micrographs_ctf.cs` first (aggregates mean defocus/astigmatism/CC), falls back to `ctf_report.json`, then `.txt` files
- **Scale note:** CryoSPARC `ctf_cross_correlation` (0.05–0.20 range) is stored as its own metric, NOT mapped to `fit_quality` (CTFFIND4 0–1 scale), to avoid false gates

#### Fix 6 — 2D classification (CLASSIFY_2D not routed)
- **Was:** `CLASSIFY_2D_R1` and `CLASSIFY_2D_R2` hit `else: return None` in routing — never parsed
- **Reality:** Workflow writes `class2d_report.json` with `num_good_classes` / `num_classes`
- **Fix:** (a) New routing in `_get_qc_metrics()` for `CLASSIFY_2D`/`CLASS_2D`; (b) New `_parse_2d_classification_metrics()` deriving `junk_class_fraction = 1 - num_good/num_total`; (c) New `CLASSIFY_2D` block in `_check_qc_thresholds()` gating on `junk_class_fraction > 0.5` [BRONZE advisory]

---

### ⚠ ORPHANED (parser exists, no workflow yet)

| Domain | Parser | Status |
|---|---|---|
| Chemoproteomics pulldown | `_parse_pulldown_metrics()` | Parser ready; no pulldown workflow implemented yet |
| Phase plate CTF | No parser | Memory.md claimed implementation; neither parser nor workflow emits `avg_phase_shift_rad` |

These are documented gaps, not bugs — gates return `None` gracefully.

---

## Test Quality Assessment

### Before this session
Tests in `TestCryoEMSharpenLocalResolution`, `TestMolecularDockingQCGates` wrote mock files
that matched what the parser expected (e.g., `sharpening_results.json`) — NOT what workflows
actually write. Tests passed but proved the gate logic only, not end-to-end connectivity.

### After this session
All test writers now use **exact filenames and field names** written by the corresponding
Nextflow workflows. Tests now serve as integration coverage, not just unit logic coverage.

---

## Test Count History

| Session | Tests passing |
|---|---|
| Start of this session | 533 |
| After drug discovery + PK/PD additions | 537 |
| After this audit + 6 fixes | **542** |

---

## Remaining Items for Future Sessions

1. **Phase plate CTF gate**: Implement `avg_phase_shift_rad` in SPA CTF process (`params.phase_plate=true` branch) and create `_parse_phase_plate_metrics()`
2. **CryoSPARC CC scale**: The `ctf_cross_correlation` gate threshold needs calibration against real CryoSPARC data (threshold likely ~0.03, not 0.7)
3. **Chemoproteomics pulldown workflow**: Create `chemoproteomics_pulldown/main.nf` writing `enrichment_ratios.tsv` in format expected by `_parse_pulldown_metrics()`
4. **QSAR workflow validation**: Run `qsar_rf_model` locally to verify scikit-learn output matches parser expectations
