# Test deploy pipeline + the `_os` stale-image incident (2026-06-26)

## TL;DR

`/api/ai_assistant/search_nextflow_workflow` (hit by the MCP `search_workflow`
tool) was returning **HTTP 500** on the **test** env
(`test.stage-public.biomate.ai`) with:

```
UnboundLocalError: local variable '_os' referenced before assignment
  ai_assistant.py  _infer_params_from_intent_llm  →  api_key = _os.getenv("ANTHROPIC_API_KEY")
```

Root cause was **a stale image**, not current code. The stray
`import os as _os` *inside* `_infer_params_from_intent_llm` shadowed the
module-level `import os as _os`, so the earlier `_os` read became an
unbound-local reference and 500'd every workflow search. That line was a real
regression — **introduced in `8cb3723fe`, fixed in `cd58c07f4`** — but the test
container was running an image built in the buggy window. Fixed by getting the
image-build CI green again and deploying a fresh image from `integration/next-phase`.

## Why the env was stale

The image-build CI had been failing for ~2 weeks, so no fresh `sha-*` image
shipped and the env kept (re)deploying a 2026-06-15 image. Two breakages:

1. **ENOSPC** — `backend-image.yml` builds a ~4.7GB image; `requirements.txt`
   pulls `torch` + the `nvidia-cuda-*` stack + `transformers`. On stock
   `ubuntu-latest` (~14GB free) `pip install` died with
   `[Errno 28] No space left on device` at `Dockerfile:126`. Fix: a
   **"Free up runner disk space"** step before the build (PR #55).
2. **L4 lint** — `backend/scripts/enrich_bioc_{step_params,step_metadata,viz_qc}.py`
   hardcoded `/home/yzhang/biomate/backend/database/galaxy_ai_tools.db`.
   `scripts/` ships in the image (Galaxy `run.sh` sources it at boot — see
   `backend/.dockerignore`), so the "no `/home/<user>/` literals" guard
   refused to push. Fix: derive the DB path from `__file__` (PR #56).

> A previous guard PR (#52, adding an "HEAD must be on origin" check to
> `sync_to_dev.sh`) was based on the wrong premise that the bug arrived via an
> unpushed local commit, and was **reverted (#54)**. `sync_to_dev.sh` targets
> **dev-public (prod)** and was left byte-for-byte unchanged.

## `/image-build-info` is the source of truth

ECR `sha-*` tags **can lie** — a stale image was observed re-tagged with a newer
commit sha. The image bakes in `/image-build-info` (`git_sha=…`, `build_date=…`)
at build time. When the backend behaves unlike `origin`, check it first:

```
docker run --rm --entrypoint cat <image> /image-build-info
```

## Environments — do not confuse

| | test / stage | dev-public (PROD) |
|---|---|---|
| URL | `test.stage-public.biomate.ai` | `dev-public.biomate.ai` |
| EC2 | `i-0482a6fa98c6f301a` | `i-06696b0d91f4346e0` |
| container | `biomate-galaxy-deploy` | — |
| deploy path | GH Actions `deploy.yml` (below) | `scripts/sync_to_dev.sh` |

The MCP connector points at **test**. In-container repro: code is at `/app/lib`,
set `PYTHONPATH=/app/lib` (import is heavy, ~90s).

## Standard TEST deploy pipeline (GitHub Actions)

Driven with `gh` (token needs `workflow` scope), `--ref integration/next-phase`:

1. **`backend-image.yml`** (workflow_dispatch) → builds + pushes
   `dev-backend:sha-<headsha12>` to ECR.
2. **`frontend-image.yml`** (workflow_dispatch) → `dev-frontend:sha-<headsha12>`.
   **Both images at the same sha are required**: `deploy.sh` pulls backend AND
   frontend at one tag and fails if either is missing. (The "Verify both images
   exist" step is skipped on `workflow_dispatch`, so a missing image surfaces
   later as a `docker pull ... not found`.)
3. **`deploy.yml`** (workflow_dispatch, `-f env=test -f tag=sha-<headsha12>`) →
   `scripts/deploy.sh` SSM-targets the EC2 tagged `Env=test`, pulls the images,
   force-recreates compose, healthchecks, and auto-rolls-back on failure. Only
   `test` is wired.

### Example

```bash
gh workflow run backend-image.yml  --ref integration/next-phase
gh workflow run frontend-image.yml --ref integration/next-phase
# wait for both sha-<headsha12> tags to land in ECR, then:
gh workflow run deploy.yml --ref integration/next-phase -f env=test -f tag=sha-<headsha12>
```

Verify after deploy:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  https://test.stage-public.biomate.ai/api/workflows/search \
  -H 'Authorization: Bearer <key>' -H 'Content-Type: application/json' \
  -d '{"query":"ADMET hERG CYP3A4","limit":2}'   # expect 200
```
