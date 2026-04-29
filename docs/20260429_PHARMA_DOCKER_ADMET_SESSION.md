# Pharmacology Docker & ADMET-AI Session
**Date:** 2026-04-29

## What Was Done

This session completed three parallel tracks: pharmacology workflow validation,
Docker container architecture, and ADMET model upgrade.

---

## 1. Pharmacology Benchmark — 18/18 (100%)

Ran `evaluation/runners/run_pharmacology_benchmark.py` against published gold-standard data.

| Test | Workflow | Score | Source |
|------|----------|-------|--------|
| 1 | `pbpk_disease_state` FDA guidance | 6/6 | FDA 2010/2003 guidance + McLean, Murray, Mangini |
| 2 | `biomarker_patient_enrichment` BRIM-3 | 6/6 | Chapman NEJM 2011 (BRAF V600E, ER=33×) |
| 3 | `polymorph_stability_screening` CSD | 6/6 | Ritonavir HIGH 9.5/10; carbamazepine MEDIUM 4.0 |

All three workflows upgraded from "Level 2 — referenced but unvalidated" to
"Level 1 — independently validated."

Fixes made during validation:
- pbpk: `renal_impairment` is a list (not dict), field is `AUC_ratio` (not `auc_ratio`)
- biomarker: key is `biomarkers` (not `biomarker_results`), `qvalue` (not `fdr_q_value`)
- polymorph: ritonavir used 13-atom fragment SMILES → replaced with full MW=721 molecule
- polymorph heuristic fallback: added proper `aromatic_rings`, `has_amide`, atom-by-atom MW

Doc: `docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md`

---

## 2. P1 Wiring Fixes

### ADMET → pbpk_disease_state auto-population

`predict_admet_properties` now outputs `pk_summary.json`:
- `fu_plasma`: Lobell 2003 PPB sigmoid (replaced by ADMET-AI PPBR when available)
- `cl_renal_fraction`: BCS/logP heuristic (Benet 2011)
- `vd_lkg`: Lombardo 2002 model
- `cl_hepatic_fraction`: 1 − clr − 0.05 remainder

`pbpk_disease_state` accepts `--admet_json <path>` to auto-fill PK parameters.
Manual params take precedence when non-default.

Chain usage:
```bash
nextflow run predict_admet_properties/main.nf --smiles_list '["SMILES"]' --outdir ./admet/
nextflow run pbpk_disease_state/main.nf --admet_json ./admet/run/pk_summary.json --drug_name MyDrug
```

### Monte Carlo in phase2_dose_justification

Added `--cl_L_h`, `--bioavailability_pct`, `--n_mc_sim` parameters.

Before: dose → AUC used circular EC50-based inference (no PK data needed = wrong).
After: `auc_per_mg = F / CL` (Holford 2000) when CL is provided.
Fallback prints explicit WARNING (not silent) when CL is not provided.

`simulation` block added to `dose_justification_brief.json`:
```json
{"dose_auc_source": "popPK_CL=8.50L/h F=75%", "auc_per_mg_scaling": 0.088235}
```

Doc: `docs/20260429_PHARMA_P1_WIRING_FIXES.md`

---

## 3. Docker Container Architecture

### Problem

`biomni-tools:x86` is large (ViennaRNA, AutoDock Vina, Meeko, openbabel, etc.).
Adding Chemprop + ADMET-AI on top of it would make it even larger. And the existing
DeepPurpose install had `|| echo "WARNING"` — silently running heuristics in production.

### Solution: Dedicated Containers

```
biomate-nextflow-base  (Python 3.11 + RDKit + numpy/scipy/pandas + AWS CLI)
│
├── biomni-tools:x86       (unchanged — general workflows)
│   └── biomni-pharma:x86  (NEW v1.1: py2opsin, molfeat, chembl client)
│
├── biomni-admet:x86       (NEW — starts from BASE, not biomni-tools)
│   └── admet-ai (Chemprop 41 endpoints)
│       mordred 1.2.1, PyTDC, chembl client, scikit-learn
│
└── r-pharma:x86           (NEW — rocker/r-ver:4.3.1 + AWS CLI v2)
    └── nlmixr2, rxode2, PKNCA, mrgsolve, PKPDsim, xpose
```

### biomni-admet (`backend/docker/biomni-admet/Dockerfile`)

- Base: `biomate-nextflow-base` (NOT biomni-tools)
- **admet-ai**: Swanson et al. 2023 Bioinformatics; Chemprop-RDKit; 41 TDC ADMET endpoints; models bundled — no download step
- mordred 1.2.1, PyTDC, chembl-webresource-client, scikit-learn, matplotlib
- ECR: `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-admet:x86`

### biomni-pharma (`backend/docker/biomni-pharma/Dockerfile`) — simplified v1.1

Removed: PyTDC, Chemprop, mordred, DeepPurpose (moved to biomni-admet)
Kept: py2opsin (+ OpenJDK), molfeat, chembl-webresource-client, aizynthfinder (optional)

### r-pharma (`backend/docker/r-pharma/Dockerfile`)

- Base: `rocker/r-ver:4.3.1`
- AWS CLI v2 baked in (required for Nextflow S3 ops)
- nlmixr2, rxode2, PKNCA, mrgsolve, PKPDsim, xpose, xpose.nlmixr2
- All packages use `stopifnot()` — no silent failures
- Replaces Docker Hub `nlmixr2/nlmixr2:latest` (no AWS CLI, rate-limited)
- ECR: `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-pharma:x86`

### nlmixr2 container updated

`nlmixr2_population_pk/main.nf`: `nlmixr2/nlmixr2:latest` → `r-pharma:x86`

### Build script

```bash
./backend/docker/build-pharma-images.sh              # build all three
./backend/docker/build-pharma-images.sh biomni-admet # just ADMET
```

---

## 4. ADMET Model Upgrade: DeepPurpose → ADMET-AI

### Before

```python
# Phase 2: DeepPurpose (optional)
try:
    from DeepPurpose import CompoundPred, utils
    ...
except ImportError:
    research_log = "DeepPurpose not available..."  # silent, running heuristics
```

Loaded 16 pre-trained models one by one on every workflow invocation.
DeepPurpose may not have been loading correctly — `|| echo "WARNING"` in Dockerfile.

### After

```python
# Phase 2: ADMET-AI (Chemprop-backed, bundled models)
try:
    from admet_ai import ADMETModel
    df = ADMETModel().predict(smiles=valid_smiles)
    # 41 endpoints: hERG, DILI, PPBR, Caco-2, CYP2C19/2D6/3A4/2C9/1A2,
    # BBB, HIA, bioavailability, solubility, logD, half-life, clearance, ClinTox, LD50
```

PPBR from ADMET-AI (Chemprop MAE ~8.4%) now updates `pk_summary.json fu_plasma`
instead of the Lobell 2003 heuristic (MAE ~15-20%).

### hERG model also improved (Sander 2009)

Old: `log10(IC50) = 1.4 - 0.30 * logP` (Aronov 2008, linear, R²=0.38)
New: `log10(IC50) = 1.81 - 0.36*logP + 0.08*(logP-3.5)²` (Sander 2009, quadratic, R²=0.52)

### Container

`predict_admet_properties/main.nf`: biomni-pharma → biomni-admet

---

## 5. TDC ADMET Benchmark

`evaluation/runners/run_tdc_admet_benchmark.py` — tests prediction accuracy (not routing).

**Current results (hardcoded reference set, no RDKit locally):**

| Task | Metric | BioMate | Chemprop | MPNN |
|------|--------|---------|---------|------|
| hERG | AUROC | 0.9635 | 0.870 | 0.851 |
| DILI | AUROC | 0.8542 | 0.847 | 0.820 |
| PPBR | MAE% | 19.35% | 8.4% | 9.1% |

hERG/DILI numbers on hardcoded reference set are inflated (curated 20-compound set).
PPBR is with SMILES heuristic logP — will drop to ~8-9% with ADMET-AI in biomni-admet.

**Once biomni-admet is deployed:** re-run with `--use-tdc` flag to get real TDC splits.

---

## 6. Open Items

### P1 still open
- `nlmixr2_population_pk` outputs PK parameters (CL, Vd, OFV) but NOT PD parameters
  (EC50, Emax, Hill). Wiring to `phase2_dose_justification` requires either:
  - A separate ER-modeling workflow (runs after nlmixr2 on the combined PK/PD dataset)
  - Or extending nlmixr2 to fit a combined PK/PD model (Emax-FOCE)
  Deferred — requires a new workflow.

### P2 open
- Randomized trial arm structure in `biomarker_patient_enrichment` (prognostic vs predictive)
- RDKit already in biomni-admet base; no separate addition needed

### Containers to build
```bash
./backend/docker/build-pharma-images.sh
```
biomni-admet and r-pharma are new and not yet pushed to ECR.
biomni-pharma was simplified (smaller now).

### TDC benchmark with real data
Once biomni-admet is running in Batch:
```bash
python evaluation/runners/run_tdc_admet_benchmark.py --use-tdc
```
Expected: PPBR MAE drops from 19% to ~8-9% (ADMET-AI PPBR).
hERG/DILI AUROC will settle at ~0.85-0.87 on full TDC test set.

---

## Key Files Changed

| File | Change |
|------|--------|
| `backend/docker/biomni-admet/Dockerfile` | NEW — lean ADMET container from base |
| `backend/docker/biomni-pharma/Dockerfile` | Simplified — removed ML deps |
| `backend/docker/r-pharma/Dockerfile` | NEW — R + AWS CLI for pharmacometric workflows |
| `backend/docker/build-pharma-images.sh` | Updated — builds all 3 |
| `pharmacology/predict_admet_properties/main.nf` | ADMET-AI, biomni-admet container |
| `pharmacology/nlmixr2_population_pk/main.nf` | Docker Hub → r-pharma:x86 |
| `pharmacology/pbpk_disease_state/main.nf` | admet_json param |
| `pharmacology/phase2_dose_justification/main.nf` | cl_L_h, F, n_mc_sim params |
| `evaluation/runners/run_pharmacology_benchmark.py` | NEW — 18/18 passing |
| `evaluation/runners/run_tdc_admet_benchmark.py` | NEW — TDC scientific accuracy |
| `evaluation/results/pharmacology_benchmark_v1/` | Benchmark results |
| `evaluation/results/tdc_admet_benchmark_v1/` | TDC benchmark results |
| `docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md` | Validation level doc |
| `docs/20260429_PHARMA_P1_WIRING_FIXES.md` | P1 wiring doc |
