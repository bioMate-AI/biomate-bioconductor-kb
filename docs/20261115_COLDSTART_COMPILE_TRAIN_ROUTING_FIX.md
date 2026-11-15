# Coldstart: Script/Module `$` compile + TRAIN routing + pep-3

**Timestamp:** 2026-11-15  
**Local tip before sync:** working tree on `sync/pr398-onto-dev` (post-remeasure against DEV `25a03a72c7`)

## Remasure evidence (tip `25a03a72c7`)

| Class | Cases | Root cause |
|-------|-------|------------|
| **Script compilation** | `design-fold-complex-bio-0/1`, `design-generate-bio-0` (Antibody Antigen Complex) | Unescaped `$(find …)` inside Nextflow `script: """` GString — Groovy rejects bare `$` (`illegal string body…` / Script compilation). JsonSlurper FQN was already correct. |
| **Module compilation** | `analysis-try-sample-data-7` (cox), `analysis-domain-gen-2` (seqvartools); deqms same pattern | Unescaped regex end-anchors `$` inside R code in `script: """` when the `.nf` is `include`d via `biomate_entry.nf`. |
| **TRAIN NotImplementedError** | `design-generate-bio-1/2`, `design-fold-complex-bio-2`, `design-optimise-*-pep-1`, … | `_DIFFUSION_HINTS` alone treated bare “design a binder / peptide structure” as ml_training → TRAIN process without diffusion-training GPU image. |
| **structure-set `*_constraints.json`** | `design-optimise-*-pep-0`, `design-predict-filter-bio-2` | Batch F residual when schema lacked structure-set label — local `rebindFilenameValues` remap (uncommitted on tip). |
| **pep-3 path** | `design-predict-filter-pep-3` | gromacs `DEFINE_EDGE` on CUDA image without python3; missing default receptor/edge — fixed locally (PY_CONTAINER + 1BXL defaults). |

## Fixes

1. Escape bare `$` → `\$` in `script:`/`shell:`/`stub:` GStrings for: antibody, cox, deqms, seqvartools, atacseq stub, nonmem_poppk, wsi_he_nuclei_segmentation.
2. `detect_training_intent`: structure-diffusion hints require a train/fine-tune verb; bare design/sample falls through to catalog.
3. Keep Batch F binding residual + gromacs PY_CONTAINER / 1BXL / generative≠FEP hint (prior working tree).
4. Unit tests: `test_diffusion.py` intent matrix; `attachment-binding.test.ts` still green (46).

## Verify

```bash
cd backend && PYTHONPATH=lib python3.9 -m pytest lib/galaxy/ai/ml_training/tests/test_diffusion.py lib/galaxy/ai/ml_training/tests/test_routing.py -q
cd frontend && npx vitest run shared/attachment-binding.test.ts
# then PRE_SYNC + BIOMATE_SYNC_DB=0 sync + remasure closed classes
```
