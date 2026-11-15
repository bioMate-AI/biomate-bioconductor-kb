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
3. Strip UI `[Prepared inputs|/Attached files|/Uploaded datasets|/Routing hint]` blocks before intent detection — cold-start notes that said “diffusion train set dataset=…” were re-arming TRAIN (remeasure tip `cb472efe5c`: generate-bio-1/2, fold-complex-bio-0).
4. Rewrite cold-start catalog peptide/biologics/enzyme notes to prefer design/co-fold workflows and explicitly avoid ml_training diffusion train for bare design prompts.
5. Keep Batch F binding residual + gromacs PY_CONTAINER / 1BXL / generative≠FEP hint (prior working tree).
6. Unit tests: `test_diffusion.py` intent matrix + prepared-inputs hijack; `attachment-binding.test.ts` still green (46).

## Prep / remasure (2026-11-15 later)

- Synced merge tip `aaaf2a6b59` (DEV absorb `104915eedd` + `$` escapes + TRAIN verb gate + gromacs pep-3) → healthy, `BIOMATE_SYNC_DB=0`. Live tip later `cb472efe5c` (ancestor includes `aaaf`).
- Remasure vs `cb472`: Module-compile class closed for seqvartools path; domain-gen-2 now `example_sub.vcf` missing (runtime). TRAIN class still HONEST_FAIL until scaffold-strip + catalog rewrite sync.
- TRAIN residual synced on tip `cd5ba35a` (frontend catalog + forced backend routing strip, `BIOMATE_SYNC_DB=0`). Post-strip remasure (tip drifted `ab7e911`→`a5ace834`):

| Case | Prior | Post-strip |
|------|-------|------------|
| generate-bio-0 | Script compilation | **REAL_PASS** Antibody Antigen Complex |
| generate-bio-1 | TRAIN NotImplemented | Antibody Antigen Complex — HONEST_FAIL (NF FileHelper FS) |
| generate-bio-2 | TRAIN NotImplemented | scfv_antibody_design — HONEST_FAIL (container) |
| fold-complex-bio-2 | TRAIN | **REAL_PASS** Antibody Antigen Complex |
| predict-filter-bio-2 | structure-set/TRAIN | **REAL_PASS** Antibody Antigen Complex |
| pep-1 | TRAIN | cyclic_peptide_design — HONEST_FAIL (VALIDATE_CONSTRAINTS) |
| pep-3 | gromacs path | cyclic_peptide_design — HONEST_FAIL (RANK_CANDIDATES) |
| domain-gen-2 | Module/seqsqc VCF | seqvartools — HONEST_FAIL (R plot xy.coords) |

TRAIN hijack class closed (no ml_training TRAIN on design/fold prompts). Next root causes: seqvartools plot, cyclic_peptide RANK/VALIDATE, scfv container, NF FileHelper.

## Verify

```bash
cd backend && PYTHONPATH=lib python3.9 -m pytest lib/galaxy/ai/ml_training/tests/test_diffusion.py lib/galaxy/ai/ml_training/tests/test_routing.py -q
cd frontend && npx vitest run shared/attachment-binding.test.ts
# then PRE_SYNC + BIOMATE_SYNC_DB=0 sync + remasure closed classes
```
