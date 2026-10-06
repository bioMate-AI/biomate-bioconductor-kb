# Implementation plan — on-prem SCOPE layer (domain/task/instrument delivery)

**Date:** 2026-10-05 · **Status:** plan (not built). **Prereq context:** `docs/20261005_ONPREM_SCOPED_DEPLOYMENT.md`
(verified state). The **compute** layer is already built on `integration/next-phase` (Slurm/K8s executors)
and is now documented (PR #271). This plan covers the **remaining** unbuilt piece: delivering an on-prem
instance scoped to a required subset of domains/tasks/instruments, with runtime enforcement.

## Goal
Turn "ship the full catalog, hand-filter" into a one-command **scoped** build:
declare scope → emit a lean, self-consistent package → the running instance refuses anything out-of-scope.

## What already exists (reuse, don't rebuild)
- `evaluation/local_trial/export_deployment_manifest.py` (on this feature branch): `--domains`/`--workflows`
  → workflow set + `tool_allowlist` + `container_mirror_resolved` + `license_gated_tools`. This is the
  **scope-declaration + allow-list generation** half. (Note: it is NOT on next-phase yet — land it there too.)
- `galaxy_ai_tools.db` is plain SQLite with a `domain` column → trivially filterable; embeddings live in the `.npz`.
- On-prem stack (compose/env/registry/db-init) on next-phase.

## The four pieces to build

### 1. Scope manifest (input) — `deployment_scope.yml`
A single declarative file the build + runtime both read:
```yaml
domains: [transcriptomics, variant_calling]     # or
workflows: [nf-core/rnaseq, nf-core/sarek]      # explicit allow-list (overrides domains)
deny: []                                         # optional subtractive
instruments: [illumina_novaseq, thermo_orbitrap] # per-deployment instrument set
addons: []                                        # future: domain packs added later
```
Reuse `export_deployment_manifest.py`'s resolution to expand this into the concrete workflow/tool/image sets.

### 2. `build_scoped_catalog.py` (offline packaging) — NEW
Input: `deployment_scope.yml` + full `galaxy_ai_tools.db` + `.npz`. Output: a package containing
- **scoped DB**: copy the DB, `DELETE FROM workflows WHERE <not in scope>`, rebuild FTS5, `VACUUM`.
- **scoped embeddings**: filter the `.npz` rows to the surviving workflow ids (keep index alignment).
- **`.nf` bundle**: resolve each in-scope workflow's `nextflow_path` → copy only those `.nf`/subworkflow files.
- **image pull-list**: from `container_mirror_resolved` + each `.nf`'s `container` directive (the executor
  honors the `.nf` directive over the DB — see `reference_executor_container_resolution`); emit a
  `docker pull && docker tag localhost:5050/... && docker push` script to seed the on-prem registry.
- **manifest.json**: the frozen allow-list the runtime enforces (workflows + tools + instruments).
Writes everything under a `scoped_package/` the on-prem `db-init` can consume.

### 3. Launch-time enforcement (runtime) — NEW, the critical gap
Nothing today refuses an out-of-scope workflow; the direct-execute path runs any `.nf` on disk.
Add a single gate read once at startup and checked on every dispatch:
- Load `manifest.json` (path via env, e.g. `BIOMATE_SCOPE_MANIFEST`); if unset → no enforcement (SaaS default).
- In `nextflow_executor.py` execute entrypoint + the router/search surface:
  - **router/search**: filter results to in-scope workflows (don't surface what can't run).
  - **execute**: before dispatch, resolve the request to a workflow/tool id; if not in the manifest →
    return a clear `409 OUT_OF_SCOPE` (not a hang, not a silent run). Cover BOTH the catalog path and the
    direct `nextflow_path`/`file_content` path (resolve the on-disk `.nf` to its catalog identity or reject
    unknown `.nf`).
- Unit tests: in-scope passes; out-of-scope (catalog id, raw `.nf`, tool) → 409; no manifest → allow (SaaS).

### 4. Per-deployment instrument manifest — NEW (smaller)
The instrument/connector set is currently global/external (`biomate-connector`, `tools_manifest.py`).
Add an `instruments:` allow-list from `deployment_scope.yml` that gates which instrument tools the
MCP/connector surface exposes per deployment (mirror the existing `local_only` surface-gating pattern).

## Sequencing (smallest-risk first)
1. **Launch-time enforcement (#3)** — highest value, smallest surface, independently testable with a
   hand-written `manifest.json`. Ship this first; it makes any scoping real.
2. **`build_scoped_catalog.py` (#2)** — automates producing the manifest + lean package the gate consumes.
3. **`deployment_scope.yml` (#1)** — the ergonomic front-end over #2.
4. **Instrument manifest (#4)** — last; depends on connector-repo coordination.

## Acceptance
- `build_scoped_catalog.py deployment_scope.yml` produces a package whose DB/`.npz`/`.nf`/images are
  self-consistent (every in-scope workflow resolves + every referenced image is in the pull-list).
- On an instance started with that package's `manifest.json`, an out-of-scope workflow request returns
  `409 OUT_OF_SCOPE` on both the catalog and raw-`.nf` paths; an in-scope one runs normally.
- With no manifest set, behavior is unchanged (SaaS full-catalog).

## Explicitly out of scope of this plan
- PBS/SGE/LSF executors (compute layer; separate, lower priority — Slurm+K8s already cover on-prem HPC).
