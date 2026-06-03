# virtual_cell / single_cell Docker rollout — deployment status

**Date:** 2026-06-03
**Branch:** integration/next-phase
**Commits:** `75e7e267d` (Dockerfiles + handoff doc) → `b6bc83db1` (.nf container swaps)

## What landed

10 per-workflow Docker images built + pushed to ECR (all `linux/amd64`, tag `:1.0`):

| Workflow | Image | Base |
|---|---|---|
| ode_signaling_simulation | `biomate/ode-signaling-nf` | biomate-nextflow-base |
| transcriptomic_moa_lincs | `biomate/transcriptomic-moa-lincs-nf` | biomate-nextflow-base |
| virtual_patient_cohort | `biomate/virtual-patient-cohort-nf` | biomate-nextflow-base |
| cpa_synergy_gpu | `biomate/cpa-synergy-gpu-nf` | pytorch 2.2 + cu121 |
| cpa_drug_combination_synergy | `biomate/cpa-drug-combination-synergy-gpu-nf` | pytorch 2.2 + cu121 |
| gears_perturbation_gpu | `biomate/gears-perturbation-gpu-nf` | pytorch 2.2 + cu121 |
| gears_perturbation_prediction | `biomate/gears-perturbation-prediction-gpu-nf` | pytorch 2.2 + cu121 |
| transcriptformer_gpu | `biomate/transcriptformer-gpu-nf` | pytorch 2.5.1 + cu124 (Py3.11+ required) |
| transcriptformer_cell_state | `biomate/transcriptformer-cell-state-gpu-nf` | pytorch 2.5.1 + cu124 |
| physicell_tumor_tgi | `biomate/physicell-tumor-tgi-nf` | ubuntu:22.04 + OpenMP |

`state_perturbation_prediction` already pointed at the existing `biomate/ai-tools/state` image — no new build needed.

All 10 `.nf` `container` directives swapped on `integration/next-phase` and synced to dev (`scripts/sync_to_dev.sh` completed at `b6bc83db`).

## What's blocked

End-to-end smoke validation. I fired `transcriptomic_moa_lincs` (smallest CPU image, default-runnable) twice on dev — both failed instantly with `fetch failed` from Node → Galaxy. Cause:

> **Galaxy backend container is in a restart loop.** `biomate-galaxy-dev` shows `(unhealthy)` because every ~1 hour gunicorn restarts (15:27 UTC was the latest as of writing) and a full Galaxy boot takes ~12 min before the API responds. Half the day is dead time. The internal health-check `curl` also doesn't help — it's perpetually flagged unhealthy.

This is **Gap 0** from the 2026-06-02 single_cell/virtual_cell gap analysis: container instability is the systemic blocker, not workflow correctness.

## Build-sweep lessons (for future Docker rollouts)

Six sweeps were needed; the failures shake out into one-time issues that the script and tooling now handle:

1. `biomate-nextflow-base:latest` pull → 401 — fixed by re-logging into ECR **before every build** (`build-virtual-cell-images.sh` now does this; previously only logged in once at start).
2. ECR push → `ecr:InitiateLayerUpload` denied — fixed by attaching inline policy `ECRPushBiomateRepos` to `BioMateEc2DeployRole` (covers all `biomate/*` repos).
3. ECR push → `repository ... does not exist` — fixed by pre-creating the 10 repos via `aws ecr create-repository` (ECR doesn't auto-create on push).
4. `cpa-tools==0.8.6` + `scvi-tools==1.1.6` pip resolution → impossible — fixed by dropping `scvi-tools` pin and letting `cpa-tools` resolve its own compatible scvi-tools/anndata.
5. `transcriptformer==0.6.1` requires Python ≥3.11; `pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime` ships Python 3.10 — fixed by bumping the two transcriptformer images to `pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime` (Python 3.12).
6. Disk space — `biomate-deploy-test` (150 GB free) is the right build host; dev EC2 only had 12 GB.

## What still needs to happen

1. **Fix the Galaxy container restart loop.** Until then, no end-to-end validation possible. Likely candidates: gunicorn memory ceiling, periodic OOM-kill, or a script (sync hook, watchdog, cron) that bounces it. Inspect `docker events --since 24h` on dev for the trigger.
2. **Then** smoke-test 1 CPU + 1 GPU workflow on dev to confirm the new containers pull from ECR and run on AWS Batch.
3. After validation, sweep all 11 workflows with empty params (Gap-2 verification per yesterday's audit).

## Files & artifacts

- `backend/docker/build-virtual-cell-images.sh` — sweep driver, supports `all` / `cpu` / `gpu` / `<single-image-name>` targets, re-logs ECR every build
- `backend/docker/<name>-nf/Dockerfile` × 10 — per-workflow images
- `docs/20260602_GALAXY_HISTORY_AGENT_CONTEXT_HANDOFF.md` — separate handoff for the agent-context work
- ECR: `aws ecr describe-images --repository-name biomate/<name>-nf --region us-west-2`
