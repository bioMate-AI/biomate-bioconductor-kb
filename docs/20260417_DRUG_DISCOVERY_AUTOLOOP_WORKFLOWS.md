# Drug Discovery Auto-Loop Workflows

**Date:** 2026-04-17  
**Total tests:** 96/96 (24 per package) + 95/95 CryoEM = 191/191  
**Packages:** `admet_autoloop`, `cyp_ddi_autoloop`, `docking_autoloop`, `nca_pk_autoloop`

---

## Architecture Pattern

All four packages share the same orchestrator pattern, differing only in domain-specific
QC gates and parameter remediations.

```
phase_runner_fn(phase, params) → metrics dict
         ↓
   QCEvaluator.evaluate_phase(phase, metrics) → PhaseQCResult
         ↓
   ParamTuner.remediate(qc_result, params) → (new_params, remediations)
         ↓
   AuditLogger.log_attempt(...)
         ↓
   retry up to max_retries_per_phase times → escalate if still failing
```

**What changes per domain:**
- `PHASES` list (1 line in `orchestrator.py`)
- `params.py` — domain-specific tunable parameters
- `qc_evaluator.py` — gate thresholds + QC profiles
- `param_tuner.py` — remediation handlers per gate

**What is reused unchanged:**
- `AuditLogger` — JSONL trail + summary report
- `LoopResult` dataclass shape
- `MockPhaseRunner` test helper
- Retry/escalation loop logic

**Production integration point:** Each domain has a corresponding gate family already
registered in `qc_trace_monitor.py`. Wire `AutoLoop.run()` into the `except QCHaltException`
block of the appropriate executor.

---

## 1. ADMET Auto-Loop

**Package:** `backend/experiments/admet_autoloop/`  
**Tests:** AL-1 to AL-24 (24/24 passing)  
**Source workflow:** `pharmacology/ADMET_pred/main.nf`  
**Output consumed:** `toxicity_report.json`  
**Production wiring:** `qc_trace_monitor.py` line 1033 (ADMET_TOXICITY gate family)

### Scientific Context

ADMET (Absorption, Distribution, Metabolism, Excretion, Toxicity) profiling is
the first pharmacological filter applied to compound libraries.  Failure here means
the compound is removed or structurally modified before downstream assays.

BioMate's `ADMET_pred/main.nf` computes worst-case metrics across all input compounds
using RDKit molecular descriptors:

- **hERG IC50** — Aronov 2008 model: `log10(IC50 [µM]) ≈ 1.4 − 0.30 × logP`  
  hERG channel blockade causes QT prolongation and arrhythmia; ICH S7B guideline
  defines concern at hERG IC50 < 30× therapeutic Cmax; BioMate empirical threshold = 10 µM.
- **DILI risk** — Lammert 2010 model: `logP > 4.0 AND MW > 400 Da → "high"` risk  
  Drug-Induced Liver Injury is the leading cause of post-market drug withdrawal.
- **Ames mutagenicity** — Kazius 2005: 29 structural alerts cover 89% of Ames-positive
  compounds; `ames_positive = True` triggers immediate flag.

### toxicity_report.json Schema

```json
{
  "herg_ic50_uM":     3.5,
  "dili_risk":        "high",
  "dili_probability": 0.78,
  "ames_positive":    false,
  "ames_probability": 0.31,
  "logP":             4.8,
  "mw":               450.0
}
```

### QC Gates

| Gate | HALT condition | Threshold source |
|---|---|---|
| `herg_ic50` | IC50 < `herg_ic50_threshold_uM` | `assay_ingestion.py:25` — `_HERG_SAFETY_THRESHOLD_uM = 10.0` |
| `dili_probability` | DILI prob > `dili_probability_max` | Lammert 2010 |
| `dili_risk_level` | risk > `dili_risk_level_max` | `assay_ingestion.py:29` — `_SAFETY_FLAG_TYPES` |
| `ames_mutagenicity` | `ames_positive=True` OR prob > max | Kazius 2005 structural alerts |
| `logp` | logP > `logp_max` | Lipinski Rule of Five — advisory only |
| `molecular_weight` | MW > `mw_max_da` | Lipinski Rule of Five — advisory only |

### QC Profiles

| Profile | hERG threshold | DILI prob max | Ames prob max | logP max | Notes |
|---|---|---|---|---|---|
| `admet_standard` | 10.0 µM | 0.50 | 0.50 | 5.0 | Default |
| `admet_cns` | 10.0 µM | 0.40 | 0.30 | 4.0 | CNS: TPSA ≤ 90 Å² for BBB |
| `admet_oncology` | 5.0 µM | 0.60 | 0.60 | 6.0 | Wider physicochemical space |

### Remediation Rules

| Gate halted | Parameter changed | Scientific rationale |
|---|---|---|
| `herg_ic50` | `logp_max − 0.5`, `mw_max_da × 0.9` | Aronov 2008: ↓logP by 0.5 → ↑IC50 by ~41% (10^0.15) |
| `dili_probability` | `logp_max → 4.0`, `mw_max_da → 400` | Lammert 2010: below logP>4 AND MW>400 → drops to "medium" |
| `dili_risk_level` | `logp_max → 4.0` | Crosses the Lammert "high" risk boundary |
| `ames_mutagenicity` | `ames_strict = True`, `num_candidates − 10` | Kazius structural pre-filter removes mutagenic scaffolds |

### Tunable Parameters (key subset)

| Parameter | Default | Description |
|---|---|---|
| `herg_ic50_threshold_uM` | 10.0 | Safety concern threshold (µM) |
| `dili_probability_max` | 0.50 | Maximum DILI probability allowed |
| `ames_probability_max` | 0.50 | Ames test probability cutoff |
| `logp_max` | 5.0 | Lipinski logP upper bound |
| `mw_max_da` | 500.0 | Molecular weight upper bound (Da) |
| `num_candidates` | 50 | Compounds submitted per iteration |

---

## 2. CYP DDI Auto-Loop

**Package:** `backend/experiments/cyp_ddi_autoloop/`  
**Tests:** CD-1 to CD-24 (24/24 passing)  
**Source workflow:** `drug_discovery/cyp_ddi_panel/main.nf`  
**Output consumed:** `cyp_panel_summary.json`, `ddi_risk_assessment.json`  
**Production wiring:** `qc_trace_monitor.py` (CYP inhibition gate family)

### Scientific Context

CYP450 enzymes metabolise ~75% of approved drugs.  When a new drug inhibits a
CYP isoform, it can dramatically alter the plasma exposure of co-administered drugs
(perpetrator DDI).  The FDA 2020 DDI guidance defines three risk tiers:

- **NOT_EXPECTED** — safe to proceed without clinical study
- **INVESTIGATE** — in vitro follow-up required (R1 ≥ 1.02 or R2 ≤ 0.79)
- **CLINICAL_STUDY_RECOMMENDED** — DDI clinical study required (R1 ≥ 1.1 or R1gut ≥ 11 or R2 ≤ 0.71)

**Risk metrics computed by `cyp_ddi_panel/main.nf`:**

```
R1     = 1 + (Cmax_ss / Ki)              -- reversible inhibition ratio
R1gut  = 1 + (f_a × Dose / (250 × Ki))  -- intestinal first-pass
R2     = 1 / (1 + kinact × [I]gut / (kdeg × (KI + [I]gut)))  -- TDI proxy
```

**7 isoforms screened:** CYP1A2, CYP2B6, CYP2C8, CYP2C9, CYP2C19, CYP2D6, CYP3A4

### cyp_panel_summary.json Schema

```json
{
  "summary": {
    "n_clinical":               1,
    "n_investigate":            2,
    "n_tdi":                    0,
    "overall_recommendation":   "CLINICAL_STUDY_RECOMMENDED",
    "highest_risk_isoform":     "CYP3A4"
  },
  "cyp_inhibition": {
    "CYP3A4": {"predicted_IC50_uM": 0.8, "flag_at_1uM": true, "flag_at_10uM": true},
    "CYP2D6": {"predicted_IC50_uM": 5.2, "flag_at_1uM": false, "flag_at_10uM": true}
  }
}
```

### QC Gates

| Gate | HALT condition | FDA reference |
|---|---|---|
| `clinical_study_isoforms` | `n_clinical > max_clinical` (default 0) | FDA 2020 guidance R1 ≥ 1.1 |
| `investigate_isoforms` | `n_investigate > max_investigate` (default 2) | FDA 2020 guidance R1 ≥ 1.02 |
| `tdi_concern` | `n_tdi > 0` | R2 ≤ 0.79 — advisory only |

### QC Profiles

| Profile | Max CLINICAL | Max INVESTIGATE | Use case |
|---|---|---|---|
| `cyp_ddi_standard` | 0 | 2 | Default drug program |
| `cyp_ddi_strict` | 0 | 0 | High-risk or CNS programs |
| `cyp_ddi_oncology` | 1 | 3 | Oncology (narrow therapeutic window) |

### Remediation Rules

| Gate halted | Parameter changed | Rationale |
|---|---|---|
| `clinical_study_isoforms` | `cmax_ss_uM × 0.5` | R1 = 1 + Cmax/Ki — halving Cmax cuts R1 by ~50% |
| `investigate_isoforms` | `cmax_ss_uM × 0.7` | Reduce R1 below the 1.02 INVESTIGATE threshold |
| `tdi_concern` | advisory only | TDI is structural — no param adjustment defined |

### Tunable Parameters (key subset)

| Parameter | Default | Description |
|---|---|---|
| `cmax_ss_uM` | 1.0 | Steady-state Cmax used for R1 calculation (µM) |
| `fu_mic` | 1.0 | Fraction unbound in microsomal assay |
| `fu_plasma` | 1.0 | Fraction unbound in plasma |
| `max_clinical_dose_mg` | 100.0 | Maximum clinical dose for R1gut calculation |
| `r1_clinical_threshold` | 1.10 | FDA CLINICAL_STUDY boundary |
| `r1_investigate_threshold` | 1.02 | FDA INVESTIGATE boundary |
| `max_clinical_isoforms` | 0 | Allowed CLINICAL_STUDY isoforms (0 = none) |
| `max_investigate_isoforms` | 2 | Allowed INVESTIGATE isoforms |

---

## 3. Docking Auto-Loop

**Package:** `backend/experiments/docking_autoloop/`  
**Tests:** DK-1 to DK-24 (24/24 passing)  
**Source workflows:** `drug_discovery/docking_autodock_vina/main.nf` + `drug_discovery/schrodinger_glide_docking/main.nf`  
**Output consumed:** `docking_autodock_vina_results.json` or `docking_summary.json`  
**Production wiring:** `qc_trace_monitor.py` (MOLECULAR_DOCKING gate family)

### Scientific Context

Structure-based virtual screening docks thousands of ligands into a protein active site
and ranks them by predicted binding affinity.  The auto-loop addresses two failure modes:

1. **No valid poses** — docking fails entirely (box too small, bad receptor prep, too few torsions sampled)
2. **All poses above hit threshold** — conformational search found binding modes but none are potent enough

**Scoring functions:**
- **AutoDock Vina** (Trott & Olson 2010): empirical force field; best affinity in kcal/mol  
  Hit threshold: < −7 kcal/mol (corresponds to ~Ki ≈ 2 µM)
- **Schrodinger Glide SP** (Friesner et al. 2004): GlideScore; hit threshold < −6  
  **Glide XP** (Halgren et al. 2004): stricter scoring for lead optimisation; < −8

### Output Schemas

**Vina — `docking_autodock_vina_results.json`:**
```json
{
  "success":            true,
  "best_score_kcal_mol": -8.3,
  "n_ligands_docked":   15,
  "mean_score":         -6.9
}
```

**Glide — `docking_summary.json`:**
```json
{
  "n_ligands_input":   20,
  "n_poses_generated":  18,
  "top_glidescore":   -7.8,
  "mean_glidescore":  -5.9,
  "interpretation":    "Strong binder (GlideScore < -8)"
}
```

### QC Gates

| Gate | HALT condition | Threshold |
|---|---|---|
| `valid_poses` | `n_poses < min_valid_poses` OR `success=False` | 1 pose minimum |
| `best_binding_score` | `best_score > min_affinity` (Vina) or `top_glidescore > min_glide_score` | Profile-dependent |

Both keys are detected automatically: `best_score_kcal_mol` (Vina) or `top_glidescore` (Glide).

### QC Profiles

| Profile | Vina threshold | Glide threshold | Min poses | Use case |
|---|---|---|---|---|
| `docking_hit_finding` | −7.0 kcal/mol | −6.0 | 1 | Virtual screening campaigns |
| `docking_lead_opt` | −8.0 kcal/mol | −8.0 | 3 | Lead optimisation |
| `docking_fragment` | −5.0 kcal/mol | −4.0 | 1 | Fragment-based screening |

### Remediation Rules

| Gate halted | Parameters changed | Rationale |
|---|---|---|
| `valid_poses` | `exhaustiveness × 2`, `center_box_expand_A + 1.0 Å` | More sampling steps + larger search volume covers missed binding modes |
| `best_binding_score` (Vina) | `exhaustiveness + 4` | Additional Monte Carlo steps for global energy minimum search |
| `best_binding_score` (Glide SP) | `exhaustiveness + 4`, `docking_precision SP → XP` | XP GlideScore is more accurate for near-threshold poses |

### Tunable Parameters (key subset)

| Parameter | Default | Description |
|---|---|---|
| `exhaustiveness` | 8 | Vina: number of independent MC runs |
| `center_box_expand_A` | 0.0 | Angstroms to add to each dimension of the binding box |
| `docking_precision` | SP | Glide precision: HTVS / SP / XP |
| `n_poses` | 9 | Poses per ligand retained |
| `energy_range_kcal` | 3.0 | Max energy above best pose to output |
| `n_ligands` | 100 | Ligands per screening run |
| `min_binding_affinity_kcal_mol` | −7.0 | Hit threshold (Vina) |
| `min_glide_score` | −6.0 | Hit threshold (Glide) |

---

## 4. NCA PK Auto-Loop

**Package:** `backend/experiments/nca_pk_autoloop/`  
**Tests:** NCA-1 to NCA-24 (24/24 passing)  
**Source workflow:** `drug_discovery/nca_pknca/main.nf`  
**Output consumed:** `nca_summary.json`  
**R package:** PKNCA (Beal et al., Denney 2022)  
**Production wiring:** `qc_trace_monitor.py` (NCA_PKNCA gate family)

### Scientific Context

Non-Compartmental Analysis (NCA) is the standard FDA-recommended method for
characterising drug PK from sparse plasma concentration–time data.  The key
regulatory quality gate is **AUCinf extrapolation**:

> FDA Guidance (2003, reaffirmed 2022): if the extrapolated AUC fraction
> (AUCinf − AUClast) / AUCinf > 20%, the estimated AUCinf is unreliable
> because insufficient terminal phase data was collected.

This typically happens when:
- Sampling was stopped too early (< 3 terminal half-lives elapsed)
- Subjects show multi-compartmental PK with a slow terminal phase
- Some subjects have no measurable terminal slope (below assay LLOQ)

The auto-loop remediation is to **extend the last sampling time** and/or **add
late sampling points** so the terminal phase is adequately characterised.

### nca_summary.json Schema

```json
{
  "study_info": {
    "n_subjects": 6,
    "software":   "PKNCA 0.11.0"
  },
  "population_summary": {
    "auc_last_mean":                    910.0,
    "auc_inf_mean":                     994.0,
    "cmax_mean":                        150.0,
    "tmax_mean":                        2.1,
    "t_half_mean":                      5.0,
    "auc_extrap_pct":                   8.5,
    "subjects_with_no_terminal_slope":  0
  }
}
```

**Key NCA parameters computed per subject by PKNCA:**

| Parameter | Definition | Unit |
|---|---|---|
| AUClast | Area under curve from t=0 to last measurable concentration (linear-log trapezoidal) | ng·h/mL |
| AUCinf | AUClast + Clast/λz (extrapolated to infinity) | ng·h/mL |
| Cmax | Maximum observed concentration | ng/mL |
| t½ | Terminal half-life = ln(2)/λz | h |
| CL/F | Apparent clearance = Dose/AUCinf | L/h/kg |

### QC Gates

| Gate | HALT condition | Regulatory basis |
|---|---|---|
| `auc_extrapolation` | `auc_extrap_pct > max_auc_extrap_pct` | FDA Guidance: > 20% → unreliable AUCinf |
| `terminal_slope_coverage` | `n_no_slope > max_no_slope_subjects` | ≥ 3 late-time points required per subject for λz |
| `t_half_plausibility` | t½ outside `[min_t_half_h, max_t_half_h]` | advisory only — flags unusual PK |

### QC Profiles

| Profile | AUC extrap max | Max no-slope subjects | t½ range (h) | Use case |
|---|---|---|---|---|
| `nca_standard` | 20% | 2 | 0.5–72 | Regulatory submission |
| `nca_exploratory` | 30% | 3 | 0.2–120 | Early discovery |
| `nca_regulatory` | 15% | 1 | 1.0–48 | NDA/BLA filing |

### Remediation Rules

| Gate halted | Parameters changed | Rationale |
|---|---|---|
| `auc_extrapolation` | `last_sampling_time_h × 1.5` | Extending to ≥3× t½ drives extrapolated fraction well below 20% |
| `terminal_slope_coverage` | `terminal_phase_points + 2`, `last_sampling_time_h × 1.3` | ≥3 points required for reliable λz; late extension captures missing subjects |
| `t_half_plausibility` | advisory only — no automated adjustment | Implausible t½ may indicate assay or data quality issues |

### Tunable Parameters (key subset)

| Parameter | Default | Description |
|---|---|---|
| `max_auc_extrap_pct` | 20.0 | FDA AUC extrapolation limit (%) |
| `max_no_slope_subjects` | 2 | Max subjects allowed to miss terminal slope |
| `last_sampling_time_h` | 24.0 | Final sample collection time (h) |
| `terminal_phase_points` | 3 | Minimum points required for λz estimation |
| `min_t_half_h` | 0.5 | Lower plausibility bound for t½ |
| `max_t_half_h` | 72.0 | Upper plausibility bound for t½ |
| `n_subjects` | 6 | Number of subjects in study |
| `dose_mg` | 100.0 | Nominal dose administered |

---

## Cross-Package Test Coverage Summary

| Package | Tests | Gate tests | Tuner tests | Orchestrator tests | Audit tests | Scenario tests | Profile tests |
|---|---|---|---|---|---|---|---|
| `admet_autoloop` | 24 | AL-1–6 | AL-7–10 | AL-11–14 | AL-15–17 | AL-18–20 | AL-21–23 |
| `cyp_ddi_autoloop` | 24 | CD-1–6 | CD-7–10 | CD-11–14 | CD-15–17 | CD-18–21 | CD-22–24 |
| `docking_autoloop` | 24 | DK-1–6 | DK-7–10 | DK-11–14 | DK-15–17 | DK-18–21 | DK-22–24 |
| `nca_pk_autoloop` | 24 | NCA-1–6 | NCA-7–10 | NCA-11–14 | NCA-15–17 | NCA-18–21 | NCA-22–24 |
| `cryo_em_autoloop_ux` | 95 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Total** | **191** | | | | | | |

---

## Production Wiring Map

```
Existing BioMate executor                 Auto-loop entry point
─────────────────────────────────────     ─────────────────────────────────────
cryosparc_executor.py:1100                CryoEMAutoLoop.run(phase_runner_fn)
  └── except QCHaltException

qc_trace_monitor.py:1033                  ADMETAutoLoop.run(phase_runner_fn)
  └── ADMET_TOXICITY / ADMET_PRED gate     ├── toxicity_report.json → metrics
                                           └── logP/MW/Ames tuning

qc_trace_monitor.py (CYP gate family)     CYPDDIAutoLoop.run(phase_runner_fn)
  └── CYP_INHIBITION / DDI_RISK gate       ├── cyp_panel_summary.json → metrics
                                           └── cmax_ss_uM tuning

qc_trace_monitor.py (MOLECULAR_DOCKING)   DockingAutoLoop.run(phase_runner_fn)
  └── DOCKING_SCORE gate                   ├── docking_results.json → metrics
                                           └── exhaustiveness / box tuning

qc_trace_monitor.py (NCA_PKNCA)           NCAPKAutoLoop.run(phase_runner_fn)
  └── AUC_EXTRAP / TERMINAL_SLOPE gate     ├── nca_summary.json → metrics
                                           └── last_sampling_time_h tuning
```

---

## How to Run All Tests

```bash
cd backend

# All 96 drug discovery auto-loop tests
python -m pytest experiments/admet_autoloop/tests/ \
                 experiments/cyp_ddi_autoloop/tests/ \
                 experiments/docking_autoloop/tests/ \
                 experiments/nca_pk_autoloop/tests/ -v
# 96 passed in 0.10s

# CryoEM auto-loop (95 tests)
python -m pytest experiments/cryo_em_autoloop_ux/tests/ -v
# 95 passed in 7s

# Full suite
python -m pytest experiments/ -v
# 191 passed
```
