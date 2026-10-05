# Can we quickly build a *scoped* on-prem deployment (selected domains / tasks / instruments)?

**Date:** 2026-10-05 · **Question:** does `integration/next-phase` already let us stand up an on-prem
BioMate limited to a *required scope* of domains, tasks, and instruments (not the full 4,200-workflow /
36-domain / all-instruments system)? · **Basis:** code + `docs/20260912_onprem_llm/20261002_ONPREM_READINESS_AUDIT.md`
+ next-phase (`.env.onprem.example`, `docker-compose.onprem.yml`, ~100 on-prem bug fixes).

## Short answer
- **On-prem deployment INFRASTRUCTURE — ✅ READY on next-phase.** You can stand up a self-contained
  on-prem BioMate quickly today.
- **SCOPING the deployment to selected domains/tasks/instruments — ❌ NOT built yet.** The on-prem stack
  currently ships the **full catalog**. There is **no mechanism** to declare "include only these
  domains/workflows/instruments," to generate a subset build, or to **enforce the scope at launch**.
  This is explicitly called out as an **open design question** in the readiness audit, not implemented.

## What IS ready (don't rebuild — next-phase)
A full self-contained stack and the cloud→local abstractions:
- `docker-compose.onprem.yml` + `.env.onprem.example`: **Postgres, Redis, MinIO (replaces S3), optional
  Ollama/vLLM, local registry, db-init (pulls the catalog DB), backend, frontend.**
- **LLM → local:** `GALAXY_AI_LLM_PROVIDER=openai_compatible` + `LLM_API_URL`/`LLM_MODEL`/`OLLAMA_BASE_URL`
  (defaults to a generic Qwen/DeepSeek/Llama; our domain-pro model plugs into the same endpoint).
- **Execution → local:** `NEXTFLOW_USE_AWS=false` + `NEXTFLOW_WORK_DIR` (local Nextflow, no Batch).
- **Storage → MinIO**, **images → `BIOMATE_LOCAL_REGISTRY`** (pre-pulled), **billing disabled**,
  **catalog DB** (`galaxy_ai_tools.db`, 322 MB, with embeddings) shippable / air-gap pre-download.
- ~100 numbered on-prem bug fixes (S3→MinIO everywhere, provider compat, PG billing). Also: a
  `DEPLOY_MODE=cloud|vpc|airgap` **network** profile is *recommended* in the audit (not domain scope).

So: **standing up an on-prem instance = fast.** It just currently contains *everything*.

## What is MISSING for *scoped* deployments (the actual gap)
The readiness audit names these directly (recommended, not built):
- *"Enforce at launch: refuse workflows/tools not in the deployment manifest (clear error, not a hang)."*
- *"ship all 2,600 workflows+containers, or a curated per-deployment subset (manifest) with add-on packs?"*

Concretely, none of the following exist:
1. **A deployment manifest** — a declarative spec of the included **domains / workflows / tasks / tools /
   instruments** for a given customer.
2. **A catalog-subsetting build step** — a tool that produces a **scoped `galaxy_ai_tools.db`** (filtered
   rows + their embeddings + FTS) plus the matching **`.nf` file set** and the **container images** needed
   — so the package only carries what's in scope.
3. **Launch-time scope enforcement** — the router/executor would surface only in-scope workflows, and a
   **direct execute of an out-of-scope `.nf` would be refused** (today direct path can run any `.nf` on disk).
4. **Instrument/connector selection per deployment** — choose which of the instrument connectors are wired
   (today: `BIOMATE_ENABLE_IT` gates Interactive Tools, and `local_only` tools are surface-gated, but there's
   no per-deployment instrument manifest).
5. **Add-on packs** — ship a base scope and add domains later.

## Building blocks that already exist (so the gap is small to close)
- The catalog (`galaxy_ai_tools.db`) is a plain **SQLite with a `domain` column** — trivially filterable
  (e.g. `DELETE FROM workflows WHERE domain NOT IN (...)` then rebuild FTS; embeddings live in the `.npz`).
  → **a domain-filtered deployment is achievable TODAY manually** by shipping a subset DB + matching `.nf`,
  but there's no tooling to generate it and nothing enforces it at launch.
- **Feature gates** pattern: `BIOMATE_ENABLE_IT`, `BIOMATE_ENABLE_AUDIT_LOG`, `BIOMATE_ENABLE_ROLLBACK`,
  `BIOMATE_ENABLE_XML_VALIDATION` — per-feature env flags (not per-domain).
- **Per-surface tool gating**: `local_only` instrument tools are excluded from cloud surfaces
  (`biomate-connector/mcp/tools_manifest.py` `to_anthropic`/`to_openai`) — a selection seam, not a manifest.
- **Deployment-profile pattern** is emerging: the `DEPLOY_MODE` network profile (proposed) and the
  **`BIOMATE_QUOTA_ENFORCEMENT`** toggle added 2026-10-05 (quota on AWS SaaS, off on-prem) show the shape a
  scope layer would take.

## Fastest path to a scoped on-prem today (manual, no new code)
1. Take the full `galaxy_ai_tools.db`, filter `workflows` to the required domains/tasks, rebuild FTS.
2. Ship only the matching `.nf` files + pre-pull only their container images into the local registry.
3. Select the instrument connectors to wire in the MCP manifest.
4. Deploy with `docker-compose.onprem.yml` + `.env.onprem` (the infra is ready).
⚠️ Caveats: no tooling automates steps 1–3, and **nothing refuses an out-of-scope workflow at launch**, so
the scope is "what's shipped," not enforced.

## Recommendation (to make scoped on-prem a first-class, quick capability)
Build a thin **deployment-scope layer** (small — it reuses the catalog DB + the deployment-profile pattern):
- a **manifest** (`deployment_scope.yml`: domains, workflow allow-list/deny, instruments, add-on packs);
- a **`build_scoped_catalog.py`** that emits the subset DB + embeddings + `.nf` set + image pull-list;
- **launch enforcement**: router shows only in-scope; executor refuses out-of-scope `.nf` with a clear error
  (closes the audit's "refuse workflows/tools not in the manifest" item).

**Net:** on-prem *deployment* is ready and quick; on-prem *scoping* (choose domains/tasks/instruments) is a
documented, recommended, **not-yet-built** capability — achievable manually today, and a small layer away
from being a one-command build.
