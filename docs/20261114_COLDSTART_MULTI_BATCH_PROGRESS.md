# Coldstart multi-batch fix progress

**Timestamp:** 2026-11-14T15:12Z  
**Tip context:** fail inventory on `0b63d793` evidence; fixes in working tree (not yet DEV-synced).

## Easy batches

| Batch | Status | What landed |
|-------|--------|-------------|
| **A** soft_pass / runId | **Done** | `data-run-id` on panel; harness extracts bare `/api/workflows/runs` arrays; `confirm_noop` → `NO_LAUNCH`; helpers in `e2e/lib/coldstart-run-id*`; vitest include for `e2e/lib/**/*.test.ts` |
| **B** sarek/proteinfold params | **Done** (re-applied after concurrent wipe) | `buildResolvedNfcoreInputSamplesheet` + galaxy-assistant call site; fixture/schema work from Batch B agent |
| **C** BLOCKED_REQUIRED seed | **Done** | 4/5 seeded (Cryo SPA, crisprseq, chemoproteomics, openfe); str-2 Cryo postprocess stays honest BLOCKED; `prepared-inputs-params.ts` |
| **D** path / storage / PRODUCTION_MD | **Done** | Vendored chipseq + mg_demo; DE blank→local demo; PRODUCTION_MD gate; Accuri FCS default — `docs/20261114_BATCH_D_PATH_STORAGE.md` |
| **E** reinvent polish | **Done (code)** (allow-list re-applied after wipe) | Zenodo prior + PYTHONPATH bridge; `reinvent4_runtime.py`; needs DEV sync + optional ECR rebuild |

## Harder batches

| Batch | Status |
|-------|--------|
| **F** structure-set JSON→PDB | **Done** — kind-aware rebind JSON→PDB/CIF (`docs/20261114_BATCH_F_STRUCTURE_SET.md`); fold-complex-bio compile left for H |
| **G** Bioconductor R exits | **Done** — cox/deqms/multigsea/mageckflute staging+script fixes; 6 pytest green (`docs/20261114_BATCH_G_BIOCONDUCTOR.md`) |
| **H** generic NF fails | **Done (code)** | `docs/20261114_BATCH_H_GENERIC_NF.md` — count-matrix remap, seqvartools VCF/ped, bcell P03200, vina 1IEP+symlink, antibody JsonSlurper, prompt-as-name, gromacs pep-3 seeds |

## All batches A–H: synced to DEV

| Gate | Result |
|------|--------|
| Commit | `ae4dbfd12a` (A–H) + `4867407ddb` (reinvent docstring) |
| PRE_SYNC | `tsc` 0; targeted vitest **235** green; full vitest has unrelated tip-drift fails (i18n/LLM/catalog) |
| Sync | `BIOMATE_SYNC_DB=0` → **healthy** at `4867407d` (waited out stale remote lease from deploy-images worktree) |
| Public tip | `{"commit":"4867407ddb868b0d7b820d90da51f999fa9f194e"}` |

**In flight:** full **71-fail** remasure on DEV tip `4867407d` — log `/tmp/coldstart_fail_remeasure_20261114_1613.log` (pid 89051). Details: `docs/20261114_COLDSTART_REMEASURE_AND_REST.md`.

**Spot (pre-full remasure):** `design-generate-sm-0` on tip → `HONEST_FAIL` **Script compilation** (CLI class closed; needs `de208a32bb` sync to scrub residual `"""` in comments).

**Local pending sync:** JsonSlurper/JsonOutput FQN sweep; gromacs `DEFINE_EDGE` → workflow-tools; catalog dataset=PDB hints; generative routing excludes FEP.

**Still optional:** rebuild `reinvent4-nf:x86` to drop runtime Zenodo egress.

**Concurrency note:** never wipe `/tmp/biomate_coldstart_deep.lock` mid-suite (causes 1ms refuse cascade).

## Local verification this session

- `npx tsc --noEmit -p .` → exit 0 (after restoring missing samplesheet export)
- `npx vitest run` on attachment-binding + coldstart-run-id + coldstart-deep-grade → **53 passed**

## Sync gate (do not sync yet)

Wait for C/D/F/G/H agents to finish, then PRE_SYNC checklist + one-writer lease before `scripts/sync_to_dev.sh`. Reinvent class still needs sync of `main.nf` + executor allow-list to close live DEV fails.
