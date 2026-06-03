# Session 2026-06-02 / 06-03 — Docker rollout, Gap-0 fix, History handoff

## TL;DR

Three deliverables shipped on `integration/next-phase`:

1. **10 per-workflow Docker images** built + pushed to ECR (virtual_cell + single_cell). `.nf` `container` directives swapped. Eliminates runtime pip-installs for CPA/GEARS/TranscriptFormer.
2. **Gap-0 root cause found and fixed**: gunicorn `max_requests: 1000` with `workers: 1` was burning the request budget in ~30 s during Galaxy's ~12-min boot, putting the API in a perpetual restart loop. Bumped to 100000.
3. **Galaxy History → agent-context** handoff doc for another session to pick up (1 not started, 1 partial, 1 done in chain-panel worktree pending merge).

Commits on `integration/next-phase`:

| SHA | Subject |
|---|---|
| `75e7e267d` | docker+docs: per-workflow virtual_cell/single_cell images + Galaxy History handoff |
| `b6bc83db1` | wf(virtual_cell): point 10 workflows at their dedicated ECR images |
| `40530090a` | docs(20260603): virtual_cell docker rollout done; smoke blocked by Gap-0 |
| `2cff1ca97` | fix(gap-0): bump gunicorn max_requests 1000→100000 to stop restart loop |

---

## 1. Docker rollout — 10 per-workflow images

**Goal:** every virtual_cell / single_cell workflow gets its own minimal, x86-pinned image so heavy deps (scvi-tools, GEARS, TranscriptFormer, CPA) are baked in instead of pip-installed at workflow runtime.

### Images shipped

| Workflow | ECR image (`:1.0`) | Base |
|---|---|---|
| ode_signaling_simulation | `biomate/ode-signaling-nf` | biomate-nextflow-base |
| transcriptomic_moa_lincs | `biomate/transcriptomic-moa-lincs-nf` | biomate-nextflow-base |
| virtual_patient_cohort | `biomate/virtual-patient-cohort-nf` | biomate-nextflow-base |
| cpa_synergy_gpu | `biomate/cpa-synergy-gpu-nf` | `pytorch/pytorch:2.2.0-cuda12.1` |
| cpa_drug_combination_synergy | `biomate/cpa-drug-combination-synergy-gpu-nf` | `pytorch/pytorch:2.2.0-cuda12.1` |
| gears_perturbation_gpu | `biomate/gears-perturbation-gpu-nf` | `pytorch/pytorch:2.2.0-cuda12.1` |
| gears_perturbation_prediction | `biomate/gears-perturbation-prediction-gpu-nf` | `pytorch/pytorch:2.2.0-cuda12.1` |
| transcriptformer_gpu | `biomate/transcriptformer-gpu-nf` | `pytorch/pytorch:2.5.1-cuda12.4` (needs Py3.11+) |
| transcriptformer_cell_state | `biomate/transcriptformer-cell-state-gpu-nf` | `pytorch/pytorch:2.5.1-cuda12.4` |
| physicell_tumor_tgi | `biomate/physicell-tumor-tgi-nf` | `ubuntu:22.04` + OpenMP (no CUDA — pure Python ODE) |

All `FROM` lines pinned `--platform=linux/amd64`. `state_perturbation_prediction` reuses the pre-existing `biomate/ai-tools/state:latest` (no new build).

### Six sweeps to green — lessons

Failures we hit (and the fixes baked in for next time):

1. **ECR auth lost mid-sweep** — `aws ecr get-login-password | docker login` once at start wasn't enough; token state was being lost between buildx builds. Fix: re-login before every `docker buildx build`. Now baked into `backend/docker/build-virtual-cell-images.sh`.
2. **`ecr:InitiateLayerUpload` denied on `BioMateEc2DeployRole`** — build host had only pull perms. Fix: attached inline `ECRPushBiomateRepos` policy covering `*` resources.
3. **`repository ... does not exist`** — `docker buildx --push` does not auto-create ECR repos. Fix: pre-created all 10 via `aws ecr create-repository`.
4. **`cpa-tools 0.8.6` + `scvi-tools 1.1.6` pip conflict** — old cpa-tools wants old scvi/anndata. Fix: drop the `scvi-tools` pin, let cpa-tools resolve its own compatible stack.
5. **`transcriptformer==0.6.1` requires Python ≥3.11** — `pytorch/pytorch:2.2.0` ships Py3.10. Fix: only the two transcriptformer images bumped to `pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime` (Py3.12).
6. **Disk space** — dev EC2 has 12 GB free; 10 images at 1–8 GB each would have crashed it. Fix: build on `biomate-deploy-test` (i-0482a6fa98c6f301a, 150 GB free).

### Convention learned from `biomate/ai-tools/*`

Inspecting existing ECR repos showed a working convention I aligned with:

- CPU per-workflow images: `FROM biomate-nextflow-base:latest` (already provides python3.11, awscli, numpy<2 [RDKit ABI pin], scipy, pandas, biopython, rdkit, gget, cryosparc-tools).
- GPU per-workflow images: `FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime` (matches the existing `biomate/ai-tools/state` image's choice).
- Per-tool images live under `backend/docker/biomate-ai-tools/<name>/`; per-workflow images live under `backend/docker/<workflow-name>-nf/`.

### `.nf` swaps

All 10 main.nf files now use the new images:

```groovy
container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/<image>:1.0' \
    : 'biomate/<image>:latest'
```

(`state_perturbation_prediction` already pointed at `biomate/ai-tools/state:latest`.)

---

## 2. Gap 0 — the real Galaxy restart loop

**Symptom (from previous audit and today's smoke attempts):** `biomate-galaxy-dev` container reports `(unhealthy)`, every smoke run on dev fails with `TypeError: fetch failed` from Node→Galaxy.

**False leads:**
- Container restart count: 0 (so docker daemon isn't restarting it).
- No cron jobs / systemd timers touching the container.
- No OOM kills in dmesg.
- 5.2 GiB free memory.

**Actual root cause** (in `supervisord.log` on dev):

```
16:50:38 exited: gunicorn (exit status 3; not expected)
16:50:39 spawned: 'gunicorn' with pid 126816
16:50:54 success: gunicorn entered RUNNING state, process has stayed up for > than 15 seconds
16:51:19 exited: gunicorn (exit status 3; not expected)
16:51:20 spawned: ...
```

`backend/config/galaxy.yml`:

```yaml
gravity:
  gunicorn:
    workers: 1
    max_requests: 1000
    max_requests_jitter: 50
    timeout: 300
```

With **only 1 worker** and **`max_requests: 1000`**, the worker self-terminates after handling 1050±50 HTTP requests. Galaxy's own init traffic (toolbox indexing, controller registration, internal API pings) burns through that in ~30 s — well before init's ~12 min cold-boot completes. Supervisor respawns; new worker hits the same cap mid-init; loop forever. API never serves a real request.

**Fix applied:**
- Hot-patched in-container `/app/config/galaxy.yml`, `max_requests: 1000 → 100000`, then `supervisorctl restart gunicorn`.
- Durable: patched the three source-of-truth files (`backend/config/galaxy.yml`, `.template`, `.docker`) in commit `2cff1ca97` so the change survives image rebuilds.

**Update post-patch:** the `max_requests` bump did NOT stop the cycle. supervisor still shows `exited: gunicorn (exit status 3)` every ~30 s after the patch + restart. Exit code 3 isn't `max_requests`-related (that returns 0). Investigation continues: code 3 typically means worker abort; need to identify the signal source. Galaxy's own `galaxy.jobs.handler.shutdown()` (`backend/lib/galaxy/jobs/handler.py:1042`) is the *responder* to the shutdown, not the trigger. The trigger is upstream — gunicorn master signalling the worker. Candidates: gunicorn `--timeout 300` (unlikely, worker is killed at ~30 s not 300), the `--worker-class galaxy.webapps.galaxy.workers.Worker` custom class (likely — bears closer inspection), or a probe/healthcheck inducing exception. Not solved this session; documented for next handoff.

---

## 3. Galaxy History → agent-context handoff

Captured in `docs/20260602_GALAXY_HISTORY_AGENT_CONTEXT_HANDOFF.md`. Summary:

| Connection | Status | File:line | Smallest next step |
|---|---|---|---|
| C1 — `list_history` / `get_dataset` agent tools | NOT STARTED | `frontend/server/galaxy-assistant.ts:51-120` | Add `list_history` to `BIOMATE_TOOLS`, ~80 LOC + handler |
| C2 — `_buildRecentRunsBlock` prompt injection | PARTIAL (memory/correction blocks exist; runs block missing) | `frontend/server/galaxy-assistant.ts:1682-1760` | Add `_buildRecentRunsBlock(userId)`, ~30 LOC |
| C3 — Prior-run outputs as next-workflow inputs | DONE in `feature/workflow-chain-panel-4a` worktree | `~/biomate_worktrees/workflow-chain-panel/.../workflow_chain.py:234, 804` | Merge worktree → integration/next-phase |

Suggested handoff order: merge chain-panel worktree first (unblocks C3 infrastructure), then C1, C2, then a small follow-up `list_run_outputs` tool over C3. ~1 focused day total.

---

## 4. Files / commits / artifacts index

**New Dockerfiles (10):**
```
backend/docker/ode-signaling-nf/Dockerfile
backend/docker/transcriptomic-moa-lincs-nf/Dockerfile
backend/docker/virtual-patient-cohort-nf/Dockerfile
backend/docker/cpa-synergy-gpu-nf/Dockerfile
backend/docker/cpa-drug-combination-synergy-gpu-nf/Dockerfile
backend/docker/gears-perturbation-gpu-nf/Dockerfile
backend/docker/gears-perturbation-prediction-gpu-nf/Dockerfile
backend/docker/transcriptformer-gpu-nf/Dockerfile
backend/docker/transcriptformer-cell-state-gpu-nf/Dockerfile
backend/docker/physicell-tumor-tgi-nf/Dockerfile
```

**Build driver:** `backend/docker/build-virtual-cell-images.sh` (supports `all|cpu|gpu|<image>`; re-logs ECR per build).

**Workflow patches (10):** `backend/biomni_workflows/nextflow_nfcore/subworkflows/{virtual_cell,single_cell}/*/main.nf`

**Config patches (3):** `backend/config/galaxy.yml{,.template,.docker}` — `max_requests: 1000 → 100000`

**Docs:**
- `docs/20260602_GALAXY_HISTORY_AGENT_CONTEXT_HANDOFF.md`
- `docs/20260603_VC_DOCKER_DEPLOY_AND_SMOKE_BLOCK.md`
- `docs/20260603_SESSION_DOCKER_GAP0_HISTORY_HANDOFF.md` (this file)

**AWS state changes:**
- Inline policy `ECRPushBiomateRepos` attached to IAM role `BioMateEc2DeployRole`.
- 10 ECR repositories created under `biomate/*` namespace.

---

## 5. What's still open

- Smoke validation: 1 CPU image (`transcriptomic_moa_lincs`) + 1 GPU image (`cpa-synergy-gpu-nf` is the recommended GPU pick — first one to pass the build sweep) need an end-to-end run on dev confirming ECR pull works on AWS Batch and outputs land in S3. Monitor `bz5nk5r5j` is in flight as of writing.
- After validation, sweep the rest with empty params (Gap-2 verification per the 2026-06-02 single_cell/virtual_cell gap analysis).
- The agent-context work (C1/C2/C3-followup) is queued via the dedicated handoff doc — not on this session's plate.
- Mock_mode rollout phase 2 (Task #24) still pending; deferred until smoke validates that the new images actually run.
