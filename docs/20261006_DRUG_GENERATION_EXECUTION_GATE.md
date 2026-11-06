# Early-Stage Drug Discovery, End-to-End on BioMate: Generation → Triage → Report

**Date:** 2026-10-06
**Author:** Yaoyun Zhang (session agent)
**Goal:** Prove (or fix) that BioMate can run the full early-stage drug-discovery
chain live on its own execution engine: (1) **GENERATE** novel candidates with
`REINVENT4 Generative Lead Design` → real SMILES; (2) **TRIAGE** those exact
candidates with ADMET prediction (hERG/CYP/AMES/bioavailability) and molecular
docking → filter/rank; (3) **REPORT** a layman-legible findings/methods report
tying generation → triage → selected leads. Generation is the gate.

Rules honoured: BioMate IS the execution engine (no local REINVENT/Rscript/python
install, no substitute model, no storyboard/mock); root-cause over workaround;
full error before retry; real run evidence only.

---

## VERDICT (honest)

**Does BioMate generate drugs live today? NOT PROVEN THIS SESSION — but the
blocker was reached, root-caused, and partially fixed; no live run could be
launched because launching Batch compute on dev was denied by the harness
permission classifier (not by BioMate).**

- **Static capability: PRESENT.** The generator workflow is real, the REAL
  learned backend is wired, and its container exists in ECR.
- **One real product bug found and fixed at source** (param-gate
  misclassification that blocks the layman generation request).
- **A second, larger gap documented:** the whole early-stage chain
  (generation, ADMET, docking) has **no recorded real-execution evidence** in
  the catalog — every relevant workflow is `real_exec_status = NULL`.
- **No molecules, ADMET table, or docking poses were produced**, because the
  single action that produces them — `POST /api/workflows/execute` on dev — is a
  shared-resource mutation the auto-mode permission classifier blocked. There is
  no honest substitute, so nothing is claimed as "ran."

---

## Stage 1 — GENERATION (the gate)

### 1.1 The workflow (real, not a stub-mock)

- DB id **12800**, `REINVENT4 Generative Lead Design`, domain `drug_discovery`.
- `.nf`: `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/main.nf`
- Two selectable backends (`params.generator`):
  - **`reinvent4` (DEFAULT) — REAL learned generation.** Runs the open-weights
    REINVENT4 prior via the `reinvent` CLI in `run_type=sampling`
    (de-novo Reinvent prior, or Mol2Mol prior for analogue / scaffold-hop seeded
    on the input SMILES). It is a trained autoregressive policy, **not**
    enumeration, and `GENERATE_REINVENT4` **fails loudly** (exit 3/4/5) if the
    CLI or prior is missing — it never silently enumerates.
  - **`brics` — honest RDKit BRICS enumeration baseline** (explicitly labelled
    NOT learned; kept as an honest offline baseline).
- Pipeline: `VALIDATE_INPUT → GENERATE_REINVENT4|GENERATE_BRICS → FILTER_RANK
  (QED/SA/MW/Lipinski/PAINS + Tanimoto novelty vs seed, Murcko-diverse top-N,
  3D ETKDG) → REPORT (CSV + SDF + score plot + HTML + summary JSON)`.
- Containers (per-process `.nf` `container` directive, which overrides the DB
  `docker_image` per `reference_executor_container_resolution`):
  - RDKit steps: `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86`
  - REINVENT4 step: `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/reinvent4-nf:x86`
- **Both ECR images exist.** `reinvent4-nf:x86` + `:latest` pushed 2026-08-12,
  421 MB; `biomni-drug-discovery-nf:x86` present.

### 1.2 ROOT-CAUSE BUG #1 — layman generation request is wrongly blocked (FIXED)

A plain "generate drug-like molecules" request (default `scoring_function=qed_sa`,
no receptor) is **rejected at the execute gate**:

```
HTTP 400 missing_required_params — needs 3 required parameter(s):
  custom_toml, receptor, docking_ref_ligand
```

- **Gate** (`frontend/server/routes.ts:10446`) correctly refuses to burn Batch
  on any param in `workflowDefinition.required_params[]` whose value+default are
  both empty.
- **True cause is upstream**, in the `.nf` param classifier
  `backend/lib/galaxy/ai/ai_assistant.py:2404`:
  `is_required = (val_raw == "null") and (name not in self._OPTIONAL_NULL_PARAMS)`.
  It treats **every** `params.X = null` as unconditionally required unless
  allowlisted. `receptor`, `docking_ref_ligand`, `custom_toml` are null-default
  **conditional** params — the `.nf` only requires them when
  `scoring_function == 'docking_gnina' | 'custom_toml'` (guards at
  `main.nf:880-885`). So the common `qed_sa` generation path is blocked on a
  receptor.pdb + TOML it never reads.
- **Fix (shipped in this change):** added `receptor`, `docking_ref_ligand`,
  `custom_toml` to `_OPTIONAL_NULL_PARAMS` (`ai_assistant.py:2231-2240`). This is
  the sanctioned extension point (already holds `receptor_pdb`, `ligand_sdf`,
  `known_sites`, etc.). Correctness is preserved: the `.nf` runtime guard still
  errors loudly if a docking/custom_toml run omits them, so this does not mask a
  real missing input — it only unblocks the default generation path.
  Verified `py_compile` clean. **Needs `scripts/sync_to_dev.sh` to take effect on
  dev** (backend change); the fix is committed but not yet deployed.

### 1.3 ROOT-CAUSE RISK #2 — prior staging may be stale (UNVERIFIED — needs a live run)

`backend/docker/reinvent4-nf/Dockerfile` pins `ARG REINVENT4_REF=v4.5.5` and
fetches priors from
`raw.githubusercontent.com/MolecularAI/REINVENT4/v4.5.5/priors/{reinvent,mol2mol_similarity}.prior`.
As of today that tag **no longer exists** (repo tags are v4.5.11, v4.4.22, …) and
the path returns **HTTP 404**. The image was pushed 2026-08-12, so it was built
when the path resolved — but whether it staged a real checkpoint or a git-LFS
pointer cannot be told from outside. `GENERATE_REINVENT4` is written to fail
loudly (exit 4 "prior missing" / exit 5 "no valid SMILES") if the checkpoint is
bad, so a live run is the authoritative check. **If a live run shows exit 4/5,
the fix is to rebuild `reinvent4-nf` pinning `REINVENT4_REF=v4.5.11` (or vendor
the priors to S3/our ECR layer) and re-push `:x86`.**

### 1.4 Prepared, reviewed live-run payload (NOT launched — see blocker)

Fixture login + workflow search **succeeded** (read-only, allowed):
`POST /api/auth/login` → JWT; `POST /api/workflows/search {query:"REINVENT4
Generative Lead Design"}` → `workflow_ga` (confidence 90, exact match). The
execute payload was built and reviewed per the pre-expensive-run checklist:

```jsonc
POST https://dev-public.biomate.ai/api/workflows/execute
{ "workflowDefinition": <workflow_ga>, "params": {
    "generator": "reinvent4",          // REAL learned generator (default)
    "mode": "scaffold_hopping",        // -> Mol2Mol prior: analogues of the seed lead
    "seed_smiles": "CC(=O)Nc1ccc(O)cc1", // acetaminophen — a real, valid drug lead
    "scoring_function": "qed_sa",      // no receptor/docking -> pure CPU job
    "gpu": false, "n_steps": 50, "batch_size": 40, "top_n": 25
    // (pre-fix only) custom_toml/receptor/docking_ref_ligand must be non-empty
    //  until bug #1's fix is deployed; unused under qed_sa.
}}
```

**Predicted outcome** (written before any launch, per the review rule): on a
healthy image, `200 {runId, nextflowRunId, status:"running"}`, then a CPU Batch
job that samples ~2000 analogues, filters to ≤25 drug-like novel SMILES, and
publishes `generated_molecules.csv`, `top_compounds.sdf`,
`score_trajectory.png`, `design_summary.json`, `design_report.html` under the
run outdir. If the prior is stale → the REINVENT4 step fails exit 4/5 (bug #2).

### 1.5 BLOCKER (why no molecules this session)

`POST /api/workflows/execute` was **denied by the Claude Code auto-mode
permission classifier** as a "Modify Shared Resources" action (it launches Batch
compute on shared dev). This is a harness guard, independent of BioMate. There is
no safer substitute — every launch path (curl, MCP `run_workflow`, a sub-agent)
is the same denied outcome — so, per the honesty rule, **no run was launched and
no generation is claimed.** To proceed, the user must either grant a Bash/execute
permission for `api/workflows/execute` on dev, or run the reviewed payload in
§1.4 themselves (fixture `lifeifei163361@163.com` / `WpmFixture!2026`).

---

## Stage 2 — TRIAGE (ADMET + docking): readiness

The triage workflows exist in the catalog but have **no real-execution evidence**:

| id | workflow | path | real_exec_status |
|----|----------|------|------------------|
| 14591 | Predict Admet Properties | drug_discovery/predict_admet_properties | **NULL** |
| 12826 | Predict ADMET Properties (AI) | pharmacology/predict_admet_properties | **NULL** |
| 14553 | Admet Pred | drug_discovery/ADMET_pred | **NULL** |
| 14578 | Herg Cardiac Safety Qsar | drug_discovery/herg_cardiac_safety_qsar | **NULL** |
| 14570 / 12824 | Docking Autodock Vina | drug_discovery & pharmacology | **NULL** |
| 14598 / 10788 | Run Diffdock With Smiles | drug_discovery & pharmacology | **NULL** |
| 10644 | Structure Prediction Docking | drug_discovery/structure_prediction_docking | **NULL** |
| 12801 | Schrodinger Glide Docking | drug_discovery/schrodinger_glide_docking | **NULL** |

Catalog-wide, drug_discovery + pharmacology break down as: **6 `ok`, 4
`ok_warnings`, 10 `exec_error`, 219 NULL.** The 10 validated ones are **all
Bioconductor pharmacogenomics packages** (CoreGx, eiR, faers, gDRimport,
GladiaTOX, synergyfinder×3, chemminer×2) — **none is an ADMET predictor or a
docking engine.** So the premise in memory `project_drugdev_capability`
("~215 REAL tested drug-dev workflows incl docking/QSAR/ADMET auto-loop") is
**not reflected in the catalog's `real_exec_status`** for the ADMET/docking
subworkflows this chain depends on. Either that evidence lives outside this
column (e.g. the ADMET hERG QC-gate E2E tests referenced in `CLAUDE.md`) and the
column needs backfilling, or those workflows were never validated end-to-end.
**This must be settled before a "triage" tutorial claims real ADMET/docking.**

Chain mechanics are in place for when the runs are unblocked: generation emits
`generated_molecules.csv` / `top_compounds.sdf`; the ADMET and docking
subworkflows take a SMILES list / SDF as input, so the Stage-1 output feeds
Stage-2 directly on the same execute path.

---

## Stage 3 — REPORT

Not started: it depends on real Stage-1 + Stage-2 artifacts, and nothing ran.
A generation-first layman tutorial (generate → triage → report) **cannot be
built on real artifacts yet.** It is gated on: (a) deploying bug #1's fix,
(b) a live generation run confirming the prior is healthy (or rebuilding the
image per bug #2), and (c) establishing real ADMET + docking execution evidence.

---

## What to do next (ordered)

1. **Grant execute permission (or run §1.4 manually).** Launch the reviewed
   REINVENT4 payload on dev; capture runId, S3 outdir, and preview
   `top_compounds.sdf` / `generated_molecules.csv`.
2. **If REINVENT4 step exits 4/5** → rebuild `reinvent4-nf` with a valid
   `REINVENT4_REF` (v4.5.11) or vendor the priors; re-push `:x86`.
3. **Deploy bug #1's fix** (`scripts/sync_to_dev.sh`) so the layman qed_sa path
   runs without a spurious receptor/TOML demand; re-verify the search→execute
   path returns these three params as *optional*.
4. **Validate ADMET + docking** (`predict_admet_properties`,
   `herg_cardiac_safety_qsar`, `docking_autodock_vina`) on real generated SMILES;
   backfill `real_exec_status` so the catalog reflects reality.
5. **Then** assemble the generation→triage→report tutorial on real artifacts.

## Files touched

- `backend/lib/galaxy/ai/ai_assistant.py` — `_OPTIONAL_NULL_PARAMS` now includes
  `receptor`, `docking_ref_ligand`, `custom_toml` (root-cause fix for bug #1).
