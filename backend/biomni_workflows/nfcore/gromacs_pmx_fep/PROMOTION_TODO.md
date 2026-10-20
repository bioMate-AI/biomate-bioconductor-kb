# gromacs_pmx_fep — promotion-to-executable TODO (P3)

Status: the engine is registered in the catalog and runs as a transparent, gated 7-step
chain (`run_gromacs_pmx_fep.py`), but it currently lives in the **display-only stub tree**
`backend/biomni_workflows/nfcore/gromacs_pmx_fep/`. To make it run on AWS Batch it must be
**promoted**, which is deliberately left as a TODO (not half-wired) because it becomes a
live executable path whose real Batch execution cannot be validated under the no-spend rule.

## Why it is not executable yet
`nextflow_executor.py` (resolver, ~L1481–1485) searches, in order:
1. `biomni_workflows/nextflow_nfcore`
2. `biomni_workflows/nextflow_nfcore/subworkflows`
3. `biomni_workflows/nextflow_nfcore/workflows`
…**before** the display-only stubs in `biomni_workflows/nfcore/`. The executable sibling
`openfe_rbfe` lives at
`biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/openfe_rbfe/main.nf`.

## Promotion steps (informed; mirror openfe_rbfe exactly)
1. Create a NEW dir `biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/gromacs_pmx_fep/`
   — **never edit any existing** `nextflow_nfcore/**` file; only add this new tree.
2. Author a genuinely executable `main.nf` there (the current `nfcore/.../main.nf` is a
   display stub): one Nextflow process per step that invokes `bin/run_gromacs_pmx_fep.py
   --step <name>` with the step's params, correct input/output channels, the GROMACS+pmx
   container for prepare + the GPU container/queue for equilibrate/fep_production, and the
   spot-GPU profile. Carry over `nextflow.config` + `nextflow_schema.json` (param strip).
   Every param declared MUST be consumed by the Groovy (executed files, not stubs).
3. Repoint the DB registration: `register_gromacs_pmx_fep.py` `FILENAME` →
   `nextflow_nfcore/subworkflows/drug_discovery/gromacs_pmx_fep/main.nf`, re-run registration.
4. Validate with a SMOKE run (`--mode smoke`, tiny λ/ns) on the spot queue — NOT a full
   production ΔΔG — to confirm the executor resolves + launches it, before any real run.

## What is already done (does not need promotion)
- Reviewed stepwise entrypoint with the honesty contract (`requires_tools`/`requires_gpu`,
  never a fabricated ΔΔG); the real prepare build ported + generalised; knowledge/FTO gates;
  Layer-C reward contract; catalog registration (discoverable by search); unit tests.
