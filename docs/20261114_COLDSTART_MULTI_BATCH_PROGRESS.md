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

## All batches A–H: code-complete locally

**Next (not done):** lease free → `docs/PRE_SYNC_CHECKLIST.md` → `scripts/sync_to_dev.sh` → filtered coldstart deep re-run. Optional: rebuild `reinvent4-nf:x86` to drop runtime Zenodo.

**Concurrency note:** parallel agents kept reverting `_PER_PROCESS_CONTAINER_WORKFLOWS` and the samplesheet helper — parent re-applied both; verified intact after H (`tsc` exit 0).

## Local verification this session

- `npx tsc --noEmit -p .` → exit 0 (after restoring missing samplesheet export)
- `npx vitest run` on attachment-binding + coldstart-run-id + coldstart-deep-grade → **53 passed**

## Sync gate (do not sync yet)

Wait for C/D/F/G/H agents to finish, then PRE_SYNC checklist + one-writer lease before `scripts/sync_to_dev.sh`. Reinvent class still needs sync of `main.nf` + executor allow-list to close live DEV fails.
