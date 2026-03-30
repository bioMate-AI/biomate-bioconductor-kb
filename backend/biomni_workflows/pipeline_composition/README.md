# Pipeline Composition — Staging Area

**Status: WIP — DO NOT promote to production until all tests pass**

This folder is the staging area for the pipeline composition refactor described in:
`docs/architecture/20260305_PIPELINE_COMPOSITION_REFACTOR.md`

Nothing in this folder affects the production workflows in `nextflow_nfcore/subworkflows/`.

---

## What Is This

The production cryo-EM and ET workflows are structurally isolated: each pipeline writes outputs
to a directory, but no pipeline records what it produced in a machine-readable way. This means
the AI cannot auto-resolve input paths for a downstream pipeline from a prior run's outputs.

This staging area implements three layers to fix that:

1. **Output manifests** — every pipeline completion writes `workflow_outputs.json` with named ports
2. **Port schema registry** — `registry/pipeline_registry.json` declares every pipeline's typed inputs/outputs
3. **Module extraction** — processes extracted from monoliths into reusable `include`-able files

## Folder Structure

```
pipeline_composition/
  README.md                       ← this file
  registry/
    pipeline_registry.json        ← port schema for all cryo-EM and ET pipelines
  manifests/
    manifest_schema.json          ← JSON Schema for workflow_outputs.json
  modules/                        ← individual extracted process .nf files
    cryosparc/
      (one .nf file per process, populated in Phase 3)
  pipelines/                      ← refactored pipelines that use include
    (populated in Phases 1–3)
  tests/
    test_manifest_schema.py
    test_registry.py
    test_manifest_generation.py
    test_port_compatibility.py
    test_resolver.py
    test_regression.py
```

## Phase Progress

- [x] Phase 1: Output manifests — `write_manifest.py` + `modules/pipeline_manifest.nf` + staged SPA pipeline + 14 tests
- [x] Phase 2: Port schema registry — `pipeline_registry.json` (20 pipelines, 10 types) + 27 tests
- [x] Phase 3: Module extraction — 19 process modules in `modules/cryosparc/`; refactored `pipelines/cryosparc_standard_spa/main.nf` uses `include`; 66 regression tests
- [ ] Phase 4: Manifest resolver API — GET /api/nextflow/invocations/{id}/manifest
- [ ] Phase 5: Promote to production

## Running the Tests

```bash
cd backend
pytest biomni_workflows/pipeline_composition/tests/ -v
```

All 213 existing cryo-EM QC tests must still pass at every phase:
```bash
pytest tests/test_qc_e2e_domains.py -k cryoem -v
```
