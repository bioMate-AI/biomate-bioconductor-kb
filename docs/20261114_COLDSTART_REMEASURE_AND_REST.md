# Coldstart fail remasure + remaining fixes

**Timestamp:** 2026-11-14T22:12Z  
**DEV tip under test:** `4867407ddb` (A–H synced)  
**Local HEAD:** `de208a32bb` + uncommitted JsonSlurper/gromacs/catalog/routing polish

## Remasure harness

| Item | Detail |
|------|--------|
| Filter | 71 non-`REAL_PASS` IDs in `/tmp/coldstart_fail_filter.txt` |
| Runner | `frontend/e2e/run_coldstart_deep.sh` (flocked) |
| Spot OK | `design-generate-sm-0` completed on tip (3.7 m) → Script compilation |
| Full remasure | **Blocked** — Data volume ~100% full (~159 Mi free) + RAM pressure (~60 Mi free pages). Runner aborts `BIOMATE_DEEP_MIN_FREE_GI`; Chrome/playwright dies under jetsam when forced. |
| Prior false starts | (1) 1ms cascade = lock wiped mid-suite; (2) `nohup` children killed when short tool shells exit — use persistent background Shell. |

**Do not** `rm -rf /tmp/biomate_coldstart_deep.lock` while the suite is running.

**Unblock remasure:** free ≥3 Gi on `/System/Volumes/Data` (Empty Trash, quit heavy apps, prune Docker/VM images), then:

```bash
cd frontend
BIOMATE_DEEP_FILTER="$(cat /tmp/coldstart_fail_filter.txt)" BIOMATE_URL=https://dev-public.biomate.ai \
  ./e2e/run_coldstart_deep.sh
```

## Spot evidence on tip `4867407d`

| Case | Grade | Error class |
|------|-------|-------------|
| `design-generate-sm-0` | `HONEST_FAIL` | **Script compilation** (not CLI-missing). Root cause: comment still contained `"""` inside Nextflow `script: """` — fixed in `de208a32bb` (not on DEV yet). |

So reinvent moved past CLI/package-not-found on synced tip, then hit the triple-quote compile landmine. Next sync of `de208a` is required to close invent.

## Local fixes pending next commit+sync

| Area | Change |
|------|--------|
| JsonSlurper / JsonOutput | Drop top-level `import groovy.json.*` in `variant_therapy_annotation`, `viral_genome_integration`, `ebv_cfdna_mrd`, `mhc_binding_prediction`, `surface_epitope_mapping`, `cyclic_peptide_cofold`, `neoantigen_vaccine_design` — use FQN |
| gromacs_pmx_fep | Default receptor/edge for peptide FEP; `DEFINE_EDGE`/`PREPARE`/`ANALYZE` → `workflow-tools` Python image (not GROMACS CUDA without python3) |
| cold-start catalog | Explicit `dataset=*.pdb` (never `*_constraints.json`); prefer `cyclic_peptide_design` over FEP for generate prompts |
| ai_assistant | Generative routing hint excludes gromacs_pmx_fep / openfe_rbfe |
| reinvent | `de208a32bb` already committed — scrub `"""` from comments |

## Expected after next sync

- invent SM / optimise-sm: past Script compilation (then Zenodo prior fetch / scoring path)
- fold-complex-bio antibody: already FQN on tip — remasure should confirm
- structure-set bio/pep: Batch F rebind on tip — remasure should confirm
- DEFINE_EDGE pep-3: needs gromacs container split sync
- Batch G bioconductor: on tip — remasure should confirm

## Honest non-bugs (still in filter)

- `NO_LAUNCH` ad-hoc / some domain cards (no Confirm — routing/UX)
- `BLOCKED_REQUIRED` Cryo Movies Path, crisprseq, chemoproteomics, openfe ligand when seed incomplete
- RFdiffusion `NotImplementedError` on diffusion-training GPU image (product/infra, not binding)
