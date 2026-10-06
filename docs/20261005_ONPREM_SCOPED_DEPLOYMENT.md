# Can we quickly build a *scoped* on-prem deployment (selected domains / tasks / instruments)?

**Date:** 2026-10-05 · **Question:** does `integration/next-phase` already let us stand up an on-prem
BioMate limited to a *required scope* of domains, tasks, and instruments (not the full 4,200-workflow /
36-domain / all-instruments system)? · **Basis:** code + `docs/20260912_onprem_llm/20261002_ONPREM_READINESS_AUDIT.md`
+ next-phase (`.env.onprem.example`, `docker-compose.onprem.yml`, ~100 on-prem bug fixes).

## Short answer
- **On-prem deployment INFRASTRUCTURE — ✅ READY on next-phase.** You can stand up a self-contained
  on-prem BioMate quickly today.
- **SCOPING the deployment to selected domains/tasks/instruments — ⚠️ PARTIALLY built.** A manifest
  generator exists (`evaluation/local_trial/export_deployment_manifest.py`: `--domains`/`--workflows` →
  workflow set + tool allow-list + container mirror-list — see the corrected section below). What's still
  missing is the rest of the one-command build: emitting a **filtered catalog DB** + `.nf`/image bundle,
  an instrument manifest, and crucially **launch-time enforcement** (nothing yet refuses an out-of-scope
  workflow). So the stack still effectively ships/serves the full catalog until that enforcement + packaging
  is added.

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

## What EXISTS (partial) and what is MISSING — corrected 2026-10-05

**CORRECTION (committee audit):** a partial manifest/subsetter DOES already exist — I missed it in the
first pass. `evaluation/local_trial/export_deployment_manifest.py` (committed 2026-09-19, `fa54934b8`):
given `--domains` or `--workflows`, it computes the exact workflow set + the **tool ALLOW-LIST** (to
enforce at run time) + the **container MIRROR-LIST** (to seed a private registry), explicitly to "avoid
shipping all 2,600 workflows / all biocontainers." So the *scope-declaration + allow-list/mirror-list
generation* half is built.

The readiness audit still names the enforcement gap directly:
- *"Enforce at launch: refuse workflows/tools not in the deployment manifest (clear error, not a hang)."*

What **exists (partial):**
- ✅ **Scope declaration + manifest generation** — `export_deployment_manifest.py` (`--domains`/`--workflows`
  → workflow set + tool allow-list + container mirror-list).

What is **still missing** (the genuine remaining gaps):
1. **Scoped `galaxy_ai_tools.db` emission** — the manifest lists the in-scope workflows/tools but does not
   yet emit a *filtered* catalog DB (filtered rows + their embeddings/`.npz` + FTS) for the package.
2. **`.nf`-set packaging + image-URI resolution** — the manifest emits tool NAMES; resolving them to
   `.nf` files + concrete container image URIs (quay/biocontainers or the `.nf` `container` directive)
   to actually bundle is a documented follow-up (the script itself flags this).
3. **Launch-time scope enforcement** — the generated allow-list is NOT enforced at dispatch: the
   router/executor should surface only in-scope workflows and **refuse a direct execute of an
   out-of-scope `.nf`** (today the direct path can run any `.nf` on disk). This is the core gap.
4. **Instrument/connector selection per deployment** — `BIOMATE_ENABLE_IT` gates Interactive Tools and
   `local_only` tools are surface-gated, but there is no per-deployment instrument manifest.
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
- a **`build_scope_manifest.py`** that emits `manifest.json` (allow-list) + the in-scope **image** mirror-list.
  **Decision 2026-10-05: do NOT subset the DB** — it ships whole (~324 MB, tiny vs the GB-scale images, and
  FTS/`.npz`-alignment surgery isn't worth it). The only thing trimmed is the container-image set.
- **launch enforcement**: router shows only in-scope; executor refuses out-of-scope `.nf` with a clear error
  (closes the audit's "refuse workflows/tools not in the manifest" item). This is what makes scoping real,
  since the full DB is still present. See `docs/20261005_ONPREM_SCOPE_LAYER_PLAN.md`.

**Net:** on-prem *deployment* is ready and quick; on-prem *scoping* (choose domains/tasks/instruments) is a
documented, recommended, **not-yet-built** capability — achievable manually today, and a small layer away
from being a one-command build.

---

## VERIFIED 2026-10-05 (code-grounded, cross-branch) + COMPUTE-RESOURCE CONFIG

Follow-up to answer two user questions precisely: (1) how convenient is *scoped* on-prem delivery, and
(2) is there convenient configuration of **local/remote compute** on-prem. Verified against actual code on
both `cursor/tutorial-live-recording-and-report-editing-4ea7` (this worktree) and `integration/next-phase`.

### Branch location (correction to the first pass)
The on-prem *stack* is on **`integration/next-phase`**, NOT this feature branch. Confirmed present on
next-phase: `docker-compose.onprem.yml`, `.env.onprem.example`, `backend/docker/biomni-tools/Dockerfile.onprem`,
`.github/workflows/build-biomni-tools-onprem-image.yml`, `docs/ONPREM_SETUP.md` (full bilingual setup guide:
quick-start, LLM-provider config, admin panel, storage, DB updates, Ollama offline, HTTPS, backup/restore),
`docs/ONPREM_IP_PROTECTION.md`, `docs/20260926_ONPREM_SIM_TEST_RESULTS.md`, and a single-node admin UI. So the
on-prem footprint is **more complete than this doc's first pass implied** — a full-catalog on-prem appliance
is genuinely deployable+documented today. (On *this* branch those files are absent; only `infra/local-trial/`
+ the `BIOMATE_LOCAL_ONLY` local-LLM hook exist here.)

### Q2 — Compute-resource configuration on-prem: local-only appliance, no cluster/sizing knobs
Executor selection (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`): if `NEXTFLOW_USE_AWS=true`
OR `executor=awsbatch` OR any S3 path → **AWS Batch**; else → **local subprocess**. `.env.onprem.example`
exposes exactly this surface: `NEXTFLOW_USE_AWS=false` (local Docker on the node), `NEXTFLOW_WORK_DIR`
(default `/app/nf-work`, host bind-mount), `BIOMATE_LOCAL_REGISTRY` (`localhost:5050`), `BIOMATE_NFCORE_URL`
(air-gap workflow bundle), `BIOMATE_BIOC_CONTAINER` (point at local-registry images), Ollama/vLLM for the LLM.

**Gaps (the real answer to "convenient local/remote compute config"):**
1. **No remote-cluster option.** Only `awsbatch` and `local` get a generated executor config
   (`_generate_executor_config` returns `None` for anything else → plain local). **Slurm is half-wired**:
   there is a config-gen branch (`executor='slurm'` + `slurm_partition`/`slurm_qos` → `clusterOptions`) and
   per-workflow `slurm` profiles ship in many `nextflow.config` files, but it is **not env-selectable, injects
   no resource tiers, and is undocumented**. **PBS/SGE/LSF/Kubernetes/GCP/Azure: unsupported.** An on-prem
   customer cannot conveniently point BioMate at an existing HPC/Slurm/K8s cluster.
2. **No central compute sizing on local.** The per-job CPU/mem/GPU tiers (`resource_resolver.py` `RESOURCE_TIERS`:
   process_single 1c/6G … process_high_memory 12c/200G; GPU via a GPU queue) are injected **only in the AWS
   Batch branch** of `nextflow_executor.py`. For **local** (and slurm) they are NOT injected — job sizing comes
   from each workflow's own `.nf` directives, and there is **no BioMate knob** to cap/size jobs or request GPU
   on a local on-prem install. GPU routing is Batch-queue-only.

**Verdict (THIS feature branch):** on-prem is a single-node local-Docker appliance; no cluster executor, no
local resource tiering. **⚠️ But see the next section — this is ALREADY BUILT on `integration/next-phase`.**

### ⚠️ CORRECTION 2026-10-05 — the compute layer is ALREADY BUILT on `integration/next-phase`
The "not built" verdict above is true only for THIS feature branch (`cursor/tutorial-...`), which is behind
next-phase on the executor code. Verified on `origin/integration/next-phase`
(`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`): a colleague has implemented cluster execution
+ resource tiering. Lesson repeated: verify on the authoritative branch before claiming a capability absent.

- **Env-selectable executor** (`:5440-5511`): `NEXTFLOW_EXECUTOR = local | slurm | k8s | awsbatch` (default
  `local` on-prem; `NEXTFLOW_EXECUTOR=local` hard-overrides `NEXTFLOW_USE_AWS` + the frontend default + request
  S3 outdirs; a per-job `compute_config.executor` still wins over the env var).
- **Slurm** (`:3074`): `clusterOptions` from `SLURM_PARTITION`/`SLURM_QOS`/`SLURM_ACCOUNT` (or per-job keys);
  **resource tiers injected** — `withLabel process_low {4c/12G} / process_medium {16c/72G} / process_high
  {32c/200G}` — **plus GPU** (`process_gpu → --partition=gpu --gres=gpu:1`); auto outdir `SLURM_WORK_DIR`
  (default `/scratch/biomate`).
- **Kubernetes** (`:3096`): full `k8s{}` scope — `namespace` (`NXF_K8S_NAMESPACE`), `storageClaimName`
  (`NXF_K8S_STORAGE_CLAIM`, a PVC), `storageMountPath`, `pullPolicy`, `serviceAccount`, the `nf-k8s` plugin;
  resource tiers + GPU (`resourceLabels ['nvidia.com/gpu':'1']`); auto outdir.
- **Config-gen gate** (`:2606`): `if executor not in ("awsbatch","slurm","k8s")` → the three cluster/cloud
  executors all get a generated override; anything else falls back to plain local.

So on next-phase, **pointing on-prem BioMate at an existing Slurm or Kubernetes cluster, with central
CPU/mem/GPU sizing, is supported.** Residual gaps (small): PBS/SGE/LSF are still unsupported (Slurm+K8s cover
most on-prem HPC/cloud-native), and `NEXTFLOW_EXECUTOR`/`SLURM_*`/`NXF_K8S_*` are **not yet documented in
`.env.onprem.example`** — i.e. a docs/exposure gap, not a code gap. Fix: add these to the on-prem env template
and `ONPREM_SETUP.md` so customers can actually find them.

### Scope layer — NOT built anywhere (re-verified on next-phase)
Checked `origin/integration/next-phase`: **no** `build_scoped_catalog`, **no** `deployment_scope.yml`, **no**
domain-scoping env knob (`ENABLED_DOMAINS`/etc.), **no** launch-time enforcement, **no** per-deployment
instrument manifest. The offline manifest generator `export_deployment_manifest.py` exists **only on this
feature branch** (ABSENT on next-phase). The on-prem docs (`ONPREM_SETUP.md`, `ONPREM_IP_PROTECTION.md`) do
not mention domain/task/instrument scoping. So scoped delivery remains the genuinely unbuilt capability — the
recommendation block above still stands as the plan to build it.

### Q1 — Scoped delivery: re-confirmed state
`export_deployment_manifest.py` (offline): `--domains`/`--workflows` → `tool_allowlist` + `container_mirror_resolved`
(mostly empty — `container_info.image` is blank in the DB today) + `license_gated_tools` + workflow list. Verified
there is **no** other subsetting tool, **no** consumer of the manifest, and **no** launch-time enforcement
(the direct-execute path runs any `.nf` on disk). Still missing: scoped DB emission, `.nf`/image bundling,
per-deployment instrument manifest, add-on packs — i.e. the recommendation block above stands unbuilt.
