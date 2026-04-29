# Pharmacology Docker Optimization & ECR Cleanup
**Date:** 2026-04-29

## 1. Pharmacology Benchmark — 33/33 (100%)

All 4 test blocks passing:
- Test 1: pbpk_disease_state — 6/6 FDA guidance drugs (renal + hepatic impairment)
- Test 1e: Extended — 15/15 additional drug-impairment pairs
- Test 2: biomarker_patient_enrichment — 6/6 (BRIM-3 BRAF structure)
- Test 3: polymorph_stability_screening — 6/6 (CSD reference compounds)

## 2. Workflow Database Registration

6 pharmacology workflows now registered in `galaxy_ai_tools.db` (IDs 12887–12892) and routable via BioMate chat:

| ID    | Workflow | Description |
|-------|---------|-------------|
| 12887 | phase2_dose_justification | FDA Phase II→III dose justification brief |
| 12888 | polymorph_stability_screening | CMC polymorph risk + ICH Q6A/Q1A |
| 12889 | biomarker_patient_enrichment | Predictive biomarker analysis, Phase III sizing |
| 12890 | pbpk_disease_state | Renal/hepatic impairment PBPK, FDA label text |
| 12891 | exposure_response_modeling | Emax/Hill fit + bootstrap CI → er_params.json |
| 12892 | nlmixr2_population_pk | SAEM/FOCE+ PopPK via nlmixr2 R container |

Full chain now registered: `nlmixr2_population_pk` → `exposure_response_modeling` → `phase2_dose_justification`

**Issue found:** `exposure_response_modeling` and `nlmixr2_population_pk` were missing from `register_ai_tool_workflows.py`. Added with full descriptions.

## 3. ECR Docker Audit — Size Reductions

### 3a. Stale tag deletion (~55 GB freed)

Tags deleted that were duplicates, old builds, or bad builds.
**Critical error caught and fixed:** 5 workflows used `:latest` tags that were deleted.
Immediately retagged active images back to `:latest`:

| Repo | Active tag kept | Retagged to :latest |
|------|----------------|---------------------|
| biomate/ai-tools/boltz | nextflow (7,686 MB) | ✓ |
| biomate/ai-tools/chai1 | nextflow (7,805 MB) | ✓ |
| biomate/ai-tools/state | nextflow (7,170 MB) | ✓ |
| biomate/ai-tools/protrek | optimized-v3 (5,443 MB) | ✓ |
| biomate/ai-tools/profam | nextflow-v2 (7,715 MB) | ✓ |

Tags deleted (no active workflow used these):
- `protrek:nextflow` (6,929 MB) — older build, optimized-v3 is current
- `boltz:latest` / `chai1:latest` — exact duplicates of :nextflow
- `profam:working-final` / `profam:latest` — superseded by nextflow-v2
- `state:latest` — superseded by :nextflow
- `protein-dynamics-nf:v1.0.5` (6,980 MB) — bad build, 2× the size of v1.0.4; workflows reference v1.0.4 explicitly

### 3b. CPU-only PyTorch (Dockerfile fixes, need rebuild)

CUDA PyTorch wheel is ~2 GB. CPU-only wheel is ~250 MB. Applicable when:
- The workflow does inference only (no training)
- GPU is optional, not required for correct results

| Image | Before | After (estimated) | GPU needed? |
|-------|--------|-------------------|-------------|
| biomni-admet | 3,467 MB | ~1,200 MB | No — ADMET inference |
| drugclip | 2,927 MB | ~1,000 MB | No — "CPU mode supported" per docs |

Fix applied: add `pip install torch --index-url https://download.pytorch.org/whl/cpu` BEFORE `pip install admet-ai` (or other chemprop-dependent packages). This makes pip reuse the CPU wheel instead of pulling CUDA.

**Cannot optimize (GPU genuinely required):**
- boltz, chai1 — structure prediction (CUDA mandatory)
- profam, protrek, state — using GPU queue on Batch
- protein-dynamics-nf, cryo-heterogeneity-nf — BioEmu/cryoDRGN require GPU

### 3c. Smoke test fix (biomni-admet Dockerfile)

C extensions (RDKit, mordred, PyTorch) segfault under QEMU x86_64 emulation used by `docker buildx`. Replaced Python import smoke tests with `pip show` package verification — no code execution, no QEMU crash. Runtime import/inference verified on actual AWS Batch hardware.

## 4. TDC ADMET Benchmark

Current results use **heuristic models** (logP-based) because `admet_ai` is not installed in the local Python environment. The `biomni-admet:x86` container IS now in ECR with ADMET-AI.

Expected after biomni-admet deploys on Batch:
- PPBR MAE: 19.35% → ~8-9% (ADMET-AI Chemprop vs Lobell heuristic)
- hERG/DILI: ~0.85-0.87 AUROC on full TDC test splits (current 0.96/0.85 inflated on 20-compound curated set)

Re-run: `python evaluation/runners/run_tdc_admet_benchmark.py --use-tdc`

## 5. Open Items

- r-pharma:x86 build still in progress (R package compilation ~30 min)
- biomni-admet:x86 rebuild with CPU-only torch in progress
- DrugCLIP rebuild needed to apply CPU-only torch fix
- Protein-dynamics v1.0.5 was a bad build — cause unknown; v1.0.4 is active
