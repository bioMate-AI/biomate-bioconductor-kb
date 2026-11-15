# 2026-11-15 — design-generate-sm-0 remasure + Cryo license stop

## 1. design-generate-sm-0 — PASS (API harness)

Playwright `./e2e/run_coldstart_deep.sh` remains **blocked locally**: Data volume ~0.8 Gi free (`BIOMATE_DEEP_MIN_FREE_GI=3`); prior attempt Chrome **SIGABRT**. No ECR rebuild.

**Documented harness** (login once, one project, generous LLM timeout):

| Step | Result |
|------|--------|
| DEV tip | `25a03a72c7efd5166c2d7001c44b89d75a04e503` |
| Fixture | `lifeifei163361@163.com` |
| Project | `d110b3ca-4faa-422d-84d9-f5a3fc571161` |
| Workflow card | **REINVENT4 Generative Lead Design** (`…/reinvent4_lead_design/main.nf`) |
| Overrides | `n_steps=2`, `batch_size=8`, `mode=de_novo`, `generator=reinvent4`, `gpu=false` (review-before-expensive) |
| **runId** | **`b152afe2-6401-4d4f-a06b-6638522feb2c`** |
| Status | **`completed`** (~5 min) |
| Processes | VALIDATE → **GENERATE_REINVENT4** → FILTER_RANK → REPORT (all COMPLETED) |
| Outputs | 11 files (html/json/csv/sdf/**log**/png) — includes reinvent sampling artifacts |

Evidence: `/tmp/design_generate_sm0_harness_20261115T055207Z/` (`result.json`, `status_final.json`, `generate_workflow.json`).

Prior cheap smoke `9acec9ab-…` remains valid; this remasure re-confirms card + Batch path on current public tip.

### Playwright unblock (ops, not code)

Free ≥3 Gi on `/System/Volumes/Data` (many biomate worktrees + Cursor/Chrome caches), then:

```bash
cd frontend
BIOMATE_URL=https://dev-public.biomate.ai \
BIOMATE_DEEP_FILTER='^design-generate-sm-0$' \
  ./e2e/run_coldstart_deep.sh
```

## 2. Cryo — movies_path OK; **BLOCKED on license**

### movies_path seed (closed)

Live frontend `cryo_inputs.json`:

- `movies_path`: `s3://biomate-cryo-data/empiar-10028/Micrographs/`
- `staged_movies_s3`: same
- Catalog cryo context includes `movies_path=s3://…` (confirmed in shipped bundle)

Generate with that URI → **CryoSPARC Standard Single-Particle Analysis** (`workflow_type=cryosparc`).

### GPU / Confirm — stop here (no workaround)

| Probe | Result |
|-------|--------|
| Fixture execute | **HTTP 402** `cryosparc_license_required` — “Add yours at Settings → Credentials → CryoSPARC.” |
| `BIOMATE_ALLOW_SHARED_CRYOSPARC_LICENSE` | **unset** on frontend/galaxy (correct fail-closed; env `CRYOSPARC_LICENSE` present but must not be silently injected) |
| `CRYOSPARC_AMI_ID` / host | Present on containers (infra keys exist; execution still gated on **user** BYOL credential) |
| S3 list from deploy role | `AccessDenied` on `s3://biomate-cryo-data` ListBucket — ops/IAM separate from license; Batch job role may still read at runtime |

**Root cause of stop:** product policy requires a per-user CryoSPARC license credential before Confirm/execute. Fixture account has none. Enabling shared license or planting a key would be a workaround — **not done**.

**Resume when:** operator attaches a real CryoSPARC license to the fixture (or a dedicated cryo test user) via Settings → Credentials, then re-probe Confirm → Batch/GPU SPA with `movies_path` already bound.

## Commits

None this pass (no code fix required for verification).
