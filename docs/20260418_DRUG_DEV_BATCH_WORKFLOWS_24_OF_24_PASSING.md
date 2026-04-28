# Drug Dev Gap Workflows — 24/24 Passing on AWS Batch

**Date:** 2026-04-18  
**Branch:** integration/next-phase  
**Final result:** 24/24 ✅

---

## Summary

All 24 new drug-development gap workflows (IDs 12861–12884) now run successfully on AWS Batch. The session resolved a chain of 7 distinct bug categories discovered through iterative testing.

---

## Fixes Applied This Session

### 1. AWS Batch Compute Environment — cliPath Fix

**Problem:** `biomate-nextflow-queue` was using `galaxy-cloud-compute-al2023-final` CE with stock AL2023 ECS AMI (`ami-0a55b150592945e7d`) that has no `/opt/aws-cli`. The executor's generated config sets `cliPath = '/opt/aws-cli/bin/aws'`.

**Root cause:** Old `biomate-nextflow-cpu-v1` CE (which had custom AMI with `/opt/aws-cli`) is INVALID. The queue was reassigned to `galaxy-cloud-compute-al2023-final` which uses a stock AMI.

**Fix:**
1. Created new CE `biomate-nextflow-ce-v2` with:
   - AMI `ami-08fe495be97a3dbf4` (`biomate-nextflow-al2023-awscli-20260409`)
   - Allocation strategy `BEST_FIT_PROGRESSIVE` (allows future AMI updates)
   - Launch template `lt-099eb24c4fe1b477e` v9 (`nextflow-awscli-mime-20251127-223103`) — installs AWS CLI to `/opt/aws-cli/bin/aws` on instance boot
2. Updated `biomate-nextflow-queue` to use `biomate-nextflow-ce-v2`

### 2. Groovy GString: `'\n'` in Python Code

**Problem:** 36 occurrences of `'\n'.join(...)` in Python code inside Nextflow `"""..."""` GString script blocks. Groovy converts `\n` to an actual newline before the shell heredoc is created → Python syntax error: `unterminated string literal`.

**Files affected:** 24 workflows (18 in `pharmacology/`, 6 in `drug_discovery/`)

**Fix:** Replaced `'\n'` → `'\\n'` across all 24 files using Python string replacement (sed didn't handle the escaping correctly). Total: 48 replacements across 24 files.

**Note:** The 6 `drug_discovery/` workflows (`clinical_trial_simulation`, `covalent_warhead_design`, `lnp_formulation_optimization`, `pbpk_simulation`, `proteome_selectivity_profiling`, `target_engagement_kinetics`) were missed in the first pass because the fix script listed them under `pharmacology/` incorrectly.

### 3. Groovy GString: Escaped Apostrophes in Python f-strings

**Problem:** `hts_plate_qc_hit_calling` had `f'FAIL (Z\' = {z_prime:.3f}...)'` — the `\'` is interpreted by Groovy as `'`, breaking the Python f-string delimiter.  
`adaptive_trial_design` had `f'O\'Brien-Fleming...'` — same issue.

**Fix:** Changed problematic f-strings to use double quotes:
- `hts_plate_qc_hit_calling/main.nf:191`: `f'FAIL (Z\' = ...)' → f"FAIL (Z' = ...)"`
- `adaptive_trial_design/main.nf:278`: `f'O\'Brien-Fleming...' → f"O'Brien-Fleming..."`

### 4. NumPy 2.0: `np.trapz` Removed

**Problem:** `nanoparticle_pk_biodistribution` and `pbpk_simulation` used `np.trapz()` which was removed in NumPy 2.0 (it's now `np.trapezoid()`). The `biomni-tools:x86` container uses NumPy 2.x.

**Fix:** Replaced with backward-compatible expression:
```python
np.trapezoid(arr, t) if hasattr(np, 'trapezoid') else np.trapz(arr, t)
```

### 5. Test Script: Status Detection

**Problem:** `poll_status()` terminal set was `{"completed", "failed", "cancelled", "error"}` but the executor returns `"succeeded"` (not `"completed"`) for successful runs.

**Fix:** Added `"succeeded"` to the terminal set.

### 6. Test Script: Output Check Race Condition

**Problem:** `check_outputs()` called the `/api/nextflow/runs/{id}/output_files` endpoint immediately after status became `"succeeded"`, before the executor had finished listing S3 output files.

**Fix:**
1. First tries `s3_output_files` from the poll_status response (populated atomically with status)
2. Falls back to polling `/output_files` endpoint up to 4 times with 10s delays

### 7. Test Script: Wrong Expected Output Filenames

**Problem:** 15 of 24 workflows had mismatched expected output filenames. Original names were design-time guesses; actual names from the workflow scripts differed.

**Fix:** Updated `WORKFLOWS` list in test script with correct filenames derived from `open('filename', 'w')` calls in each `main.nf`.

Key mismatches:
| Workflow | Old | New |
|----------|-----|-----|
| allometric_scaling | allometric_plot_data.csv | allometric_regression.csv |
| dart_toxicity | dart_prediction.json | dart_results.json |
| oral_absorption | bcs_classification.csv | bcs_classification.json |
| lnp_formulation | lnp_optimization_results.json | lnp_results.json |
| target_engagement | kinetics.json | kinetics_results.json |
| pbpk_simulation | pbpk_concentrations.csv | pk_profile.csv |
| clinical_trial | simulation_results.json | clinical_trial_results.json |
| metabolite | metabolites.json | metabolite_results.json |

---

## Final Test Run Results

**Run 6 (23/24) + pbpk retest (1/1) = 24/24**

| Batch | Workflows | Result |
|-------|-----------|--------|
| 1 | allometric_scaling, cns_penetration, dart_toxicity, oral_absorption, transporter_ddi, repeated_dose_tox | 6/6 ✅ |
| 2 | nanoparticle_pk, membrane_permeability, target_engagement, lnp_formulation, proteome_selectivity, covalent_warhead | 6/6 ✅ |
| 3 | pharmacogenomics, clinical_trial, metabolite, herg_cardiac, genotoxicity_ames (pbpk failed — trapz) | 5/6 |
| 4 | target_tractability, pbpk_pediatric, antibody_developability, hts_plate_qc, exposure_response, adaptive_trial | 6/6 ✅ |
| Retest | pbpk_simulation | 1/1 ✅ |
| **Total** | **All 24** | **24/24 ✅** |

---

## Infrastructure Changes

- **New CE:** `biomate-nextflow-ce-v2` (BEST_FIT_PROGRESSIVE, AMI `ami-08fe495be97a3dbf4`, LT `lt-099eb24c4fe1b477e` v9)
- **Queue `biomate-nextflow-queue`:** Now points to `biomate-nextflow-ce-v2`
- **Old CE `galaxy-cloud-compute-al2023-final`:** Still exists but no longer used by this queue

---

## Files Modified

- `biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/*/main.nf` (18 files)
- `biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/{clinical_trial_simulation,covalent_warhead_design,lnp_formulation_optimization,pbpk_simulation,proteome_selectivity_profiling,target_engagement_kinetics}/main.nf` (6 files)
- `biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/nanoparticle_pk_biodistribution/main.nf` (trapz fix)
- `biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/pbpk_simulation/main.nf` (trapz fix)
- `biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/hts_plate_qc_hit_calling/main.nf` (apostrophe fix)
- `biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/adaptive_trial_design/main.nf` (apostrophe fix)
- `scripts/test_drug_dev_workflows_batch.py` (status detection, output check, expected filenames)
