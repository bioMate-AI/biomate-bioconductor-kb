# BioMate UI scenario — ANDV inhibitor pipeline (two-agent information flow)

**Track:** ANDV oral small-molecule inhibitor — integrated in silico triage.  
**Evidence manifest:** `research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/pipeline_manifest.json`  
**CLI orchestrator:** `research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py`

This document describes the **full chained pipeline** as users should experience it in BioMate chat (stepwise workflow cards), with the same two-agent split as Plan A and Cryo-EM E2E tests.

---

## Persona

Medicinal chemist / program lead: pocket tractability → pharmacophore screen → ADMET → Vina → optional generative follow-up.

---

## Pipeline steps (Nextflow paths)

| Step | Key | Nextflow path |
|------|-----|----------------|
| 1 | pocket | `nextflow_nfcore/subworkflows/drug_discovery/pocket_detection_druggability/main.nf` |
| 2 | pharmacophore | `…/pharmacophore_filtering/main.nf` |
| 3 | admet | `…/admet_prediction/main.nf` (or equivalent in repo) |
| 4 | docking_vina | `…/autodock_vina/main.nf` |
| 5 | gromacs_mmgbsa | optional |
| 6 | reinvent4 | generative |

**Campaign S3 inputs (manuscript run):**

- Receptor: `s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb`
- Demo library: `…/pipeline_demo_20260509/reference_actives.smi`, `compound_library.smi`

**E2E validation PDB:** `1IEP` (reliable RCSB `.pdb` download). Production ANDV builds use **9P3I** after upload or mmCIF conversion.

---

## Designed queries (one per stage)

### Step 1 — Pocket / druggability

```text
ANDV inhibitor program — step 1 pocket detection and druggability on the receptor.
pdb_input = 1IEP, min_druggability = 0.35, min_volume = 200.
Show the Pocket Detection Druggability workflow card so I can Run.
```

### Step 2 — Pharmacophore

```text
ANDV inhibitor program — step 2 pharmacophore screening.
reference_actives_s3 = s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/reference_actives.smi
compound_library_s3 = s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/compound_library.smi
Show the pharmacophore filtering workflow card with these paths prefilled.
```

### Step 3 — ADMET

```text
ANDV inhibitor program — step 3 ADMET on pharmacophore hits (or demo SMILES if empty).
Use the ADMET prediction workflow; smiles from prior step when available.
```

### Step 4 — AutoDock Vina

```text
ANDV inhibitor program — step 4 docking with AutoDock Vina.
Use the top pocket box from step 1 when available; receptor pdb_input = 1IEP for this UI test.
```

Steps 5–6 are optional / heavy; CLI `run_andv_inhibitor_pipeline_nextflow.py --through-step 6` remains the batch path for REINVENT4.

---

## Two-agent information flow

```mermaid
sequenceDiagram
  participant U as User
  participant A as Agent A — Research Planner
  participant B as Agent B — Execution Coach
  participant W as Workflow panel
  participant X as AWS Batch

  U->>A: Step N query + explicit S3/PDB params
  A->>A: Map to drug_discovery subworkflow N
  A->>B: Handoff: workflow_id, param map, prior-run hints
  B->>U: Workflow card + prereq checklist
  U->>W: Run step N
  W->>X: Execute on Batch
  X-->>W: pockets.json / filtered_compounds.smi / docking poses
  Note over U,B: User starts step N+1 in same or new session; manifest JSON links steps offline
```

### Agent A — Research Planner

- Classifies **inhibitor track** vs Plan A / cryo / generic pharma.
- Selects the correct **subworkflow** for the requested step.
- Extracts **S3 URIs** and numeric thresholds; warns if 9P3I needs upload.
- For step 4, plans **box center** from step 1 `*_pockets.json` when user asks for top pocket.

### Agent B — Execution Coach

- Renders workflow card and validates **missing** prereqs (library paths, SMILES).
- On Run, captures `run_id` and drives status UI to terminal state.
- Summarizes **handoff artifacts** for the next chat turn (e.g. path to `filtered_compounds.smi`).

---

## Expected UI sequence (per step)

Same checklist as `research/anti-virus/BIOMATE_UI_SCENARIO_ANDV_POCKETS.md`, repeated for each workflow card:

`chat-response-pending` → assistant reply → `button-run-workflow-panel` → `workflow-overall-status-badge` → `workflow-completion-banner` → downloads.

---

## Automated UI tests (Playwright)

| File | Scope |
|------|--------|
| `frontend/e2e/andv-pocket-druggability-ui.e2e.ts` | Single-test pocket smoke |
| `frontend/e2e/andv-inhibitor-pipeline-stepwise.e2e.ts` | INH-1 … INH-4 stepwise + audit JSON |

```bash
cd frontend
BIOMATE_URL=https://your-biomate.example.com \
E2E_TEST_TOKEN=<token> \
npx playwright test e2e/andv-inhibitor-pipeline-stepwise.e2e.ts --project chromium
```

Screenshots: `frontend/e2e/screenshots/andv-inhibitor-stepwise/`
