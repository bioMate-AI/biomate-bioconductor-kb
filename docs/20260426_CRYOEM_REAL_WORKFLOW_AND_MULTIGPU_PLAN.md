# CryoEM Real Workflow E2E + Multi-GPU Plan

**Date:** 2026-04-26  
**Status:** In-Progress

---

## Background

The CE-1 E2E test previously "completed" in mock mode (no real CryoSPARC, no real data). The user requires:
1. A **real** CryoSPARC workflow run triggered entirely through the BioMate UX (not pre-submitted)
2. The information flow must be natural — credential input via the UX, data via S3 path
3. Multi-GPU testing runs **in parallel** as a separate task on a different instance

---

## System Architecture (Key Facts)

### Credential Flow
- **CryoSPARC license key** is required per-user; marked `user_must_provide=True` in `license_registry.py`
- UX: `LicenseGate` component fetches requirements via `GET /api/workflows/license-requirements`
- If credential missing → shows "Provide credentials" button → opens `CredentialModal`
- Modal: `<Input id="cred-license-key">` for license key type
- Submit: `POST /api/users/credentials {tool: "cryosparc", data: {license_key: "..."}}` → stored in Galaxy Vault
- At execute time: `GET /api/users/credentials/cryosparc/value` → passes to `/api/cryosparc/execute`

### Data Flow (S3 → CryoSPARC EC2)
- User specifies S3 path in their query: `movies_path=s3://bucket/path`
- Backend extracts via regex from user intent → puts in `_exec_params['movies_path']`
- At execute time: `_stage_s3_movies_on_cryosparc()` SSHs to CryoSPARC EC2, runs `aws s3 sync`
- CryoSPARC `import_movies` job receives the **local** path on EC2 (not S3 URL)
- IAM profile `CryoEMBenchmarkProfile` (S3FullAccess) is auto-attached to the EC2 instance

### Instance Sizing (Fleet Selection)
```
≤50 movies   → g6.2xlarge  (1× L4 GPU)   ← current instance, CE-1 uses this
51–500       → g6.12xlarge (4× L4 GPU)   ← multi-GPU test needs this
501–2000     → g6.48xlarge (8× L4 GPU)
>2000        → p3.16xlarge (8× V100)
```
Override: pass `instance_type` param explicitly to bypass the auto-selection.

### Execute Path (CE-1)
```
User query (S3 path in text)
  → AI extracts movies_path regex → workflow_ga.parameters.movies_path
  → Frontend: workflow card appears with CryoSPARC Standard SPA
  → LicenseGate shows (credential check)
  → User adds license via credential modal
  → User clicks "Run"
  → routes.ts: fetch license from vault → POST /api/cryosparc/execute
  → nextflow_executor.py execute_cryosparc():
      Step 1a: count movies on EC2 → select instance type
      Step 1c: start_instance() → provision/reuse EC2
      Step 2:  _stage_s3_movies_on_cryosparc() → SSH sync S3 → EC2
      Step 3:  build NF params (cryosparc_host, movies_path, license, etc.)
      Step 4:  execute_nextflow() → cryosparc_standard_spa/main.nf
  → Nextflow runs 23 CryoSPARC job types on EC2
  → Frontend polls /api/nextflow/status/{run_id} every 5s
  → Phase cards update in real-time via SSE
  → On completion: output files listed, findings card generated
```

---

## Task 1: CE-1 Real Workflow E2E Test

### What Changed (vs. Previous Broken Version)
| Before | After |
|--------|-------|
| Local `.mrc` stub upload → local file path | No upload; S3 path in query text |
| No credential step | LicenseGate "Provide credentials" → modal → save |
| Helical SPA Pipeline (Nextflow, wrong path) | CryoSPARC Standard SPA (cryosparc_executor path) |
| 10-minute timeout | 45-minute timeout |
| 5-minute status poll | 40-minute status poll |
| Expected local "completed" quickly | Expects real CryoSPARC ~30-min completion |

### Test Flow (CE-1 Updated)

```
T1: Register + login
T2: Send query with S3 movies path (no file upload)
    "Run CryoSPARC Standard SPA on my cryo-EM dataset.
     movies_path=s3://biomate-cryo-data/empiar-10028/Micrographs
     pixel_size=1.96, voltage=300, total_dose=40,
     particle_diameter_angstroms=150, symmetry=C1..."
T2b: Confirmation turn if AI didn't trigger card immediately
T3: Workflow card verification (CryoSPARC Standard SPA)
T3b: Credential UX step:
     - Find "Provide credentials" button (LicenseGate component)
     - Click → CredentialModal opens
     - Fill #cred-license-key with system license key
     - Click "Save credentials"
     - Verify green "(your credentials)" checkmark
T4: Run controls visible
T5: Parameters panel:
     - movies_path field shows S3 path from query extraction
     - If empty, fill manually with S3 path
T6: QC settings panel (auto-detected cryoem_spa_purified profile)
T7: Click "Run" button
     - Backend: start_instance() (g6.2xlarge, already running)
     - Backend: _stage_s3_movies_on_cryosparc() → SSH sync EMPIAR-10028
     - Backend: execute_nextflow() → cryosparc_standard_spa/main.nf
T8: Poll for terminal status (up to 40 min)
T9: On completion: verify completion banner, output card, findings card
```

### Data Used
- S3 path: `s3://biomate-cryo-data/empiar-10028/Micrographs`
- 20 movies, pixel_size=1.96 Å, 300 kV, ~32-min runtime (confirmed by run 716405a6)
- CryoSPARC EC2 instance: `i-0a2698b6bd30a98b2` (g6.2xlarge, 1× L4 GPU, already running)
- SSH tunnel: `54.159.243.71:30000` → `localhost:31000`

### License Key
- For E2E: use BioMate system license `f312a30e-63fc-11f0-8e36-e3c932851287`
- Flow: entered by test through the UX credential modal (natural flow)
- Stored: Galaxy Vault per test user account
- Retrieved: at execute time by `GET /api/users/credentials/cryosparc/value`

---

## Task 2: Multi-GPU Parallel Test

### Goal
Verify that the CryoSPARC pipeline correctly uses **multiple GPUs** on a multi-GPU instance, specifically that:
- `_get_lane_gpu_count()` returns the correct **per-worker** max GPU count (not sum)
- GPU job types (class_2D, homo_abinit, homo_refine_new, etc.) receive `compute_num_gpus=N`
- Nextflow pipeline completes successfully with N>1 GPUs

### Code Fixes Already Made
1. `_get_lane_gpu_count()` rewritten to use `max(per_worker GPUs)` not `sum` — handles Pydantic SchedulerTarget objects from cryosparc-tools v5 (which don't have `.get()`)
2. Both call sites in `generate_workflow_unified` now pass `uploaded_datasets` to `_return_nextflow_match`

### Instance Plan
- **g6.12xlarge**: 4× NVIDIA L4 GPUs (24 GB VRAM each)
- AMI: `ami-008607f719aaac1b0` (BioMate CryoSPARC pre-installed)
- Region: `us-east-1`
- Test: `num_gpu=2` (use 2 of 4 GPUs per job)
- Dataset: same EMPIAR-10028 (20 movies, small, quick)

### Submission
- Direct API call: `POST /api/cryosparc/execute` with:
  ```json
  {
    "parameters": {
      "movies_path": "s3://biomate-cryo-data/empiar-10028/Micrographs",
      "pixel_size": 1.96, "voltage": 300, "total_dose": 40,
      "particle_diameter_angstroms": 150, "symmetry": "C1",
      "instance_type": "g6.12xlarge",
      "num_gpu": 2
    }
  }
  ```
- This bypasses fleet sizing auto-selection and forces g6.12xlarge with 2 GPUs/job
- The `_INSTANCE_LOCK` in `cryosparc_executor.py` serializes provisioning
- A second `start_instance()` call when `CRYOSPARC_INSTANCE_TYPE=g6.12xlarge` will launch a NEW instance (not reuse the g6.2xlarge)

### Verification
- Check backend logs: `[CS] Lane 'default' max GPU/worker = 4`
- Check CryoSPARC job params: `compute_num_gpus=2` for GPU job types
- Pipeline should complete with reduced wall time vs. 1 GPU

---

## Known Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| CE-1 LLM doesn't route to CryoSPARC SPA | 3-attempt proactive follow-up from `waitForWorkflowCard`; confirmation turn sent |
| S3 staging slow (large files) | 20 movies × ~500 MB = 10 GB; allow 10 min staging window |
| CryoSPARC instance not ready | `start_instance()` waits up to 15 min with health check on port 30002 |
| Multi-GPU instance type change races CE-1 | `_INSTANCE_LOCK` in `cryosparc_executor.py`; submit multi-GPU AFTER CE-1 acquires lock |
| `g6.12xlarge` not available in us-east-1 | Instance type availability varies; fallback to `g6.4xlarge` (1 GPU, doesn't test multi-GPU) |

---

## Parallel Timeline

```
T+0:00  CE-1 test starts (register, query)
T+0:05  CE-1: workflow card + credential entry
T+0:08  CE-1: click Run → executor starts
T+0:10  CE-1: start_instance() acquires lock, g6.2xlarge provisioned
T+0:12  Submit multi-GPU test (g6.12xlarge) — lock released by CE-1 provisioning
T+0:15  Multi-GPU: g6.12xlarge launching from AMI (~8 min boot time)
T+0:23  Multi-GPU: g6.12xlarge ready, S3 staging starts
T+0:30  CE-1: CryoSPARC pipeline at ~step 8 (2D classification)
T+0:35  Multi-GPU: pipeline starts
T+0:40  CE-1: expected completion
T+1:10  Multi-GPU: expected completion
```

---

## Files Changed

| File | Change |
|------|--------|
| `frontend/e2e/cryoem-workflows-ux-e2e.e2e.ts` | CE-1 rewritten: credential UX step, S3 path, 45-min timeout |
| `backend/biomni_workflows/.../cryosparc_standard_spa/main.nf` | `_get_lane_gpu_count` fixed for Pydantic objects, uses max not sum |
| `backend/lib/galaxy/ai/ai_assistant.py` | `_return_nextflow_match` accepts `uploaded_datasets`; both call sites updated |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Added `data-testid="execution-triage-panel"` to failure card |
