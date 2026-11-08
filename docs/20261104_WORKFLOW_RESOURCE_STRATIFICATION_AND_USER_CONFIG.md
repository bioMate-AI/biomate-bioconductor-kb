# Workflow resource stratification + where user-configurable compute belongs

Date: 2026-11-04. Question (user): resources should be configurable per the user's own compute; can we stratify workflows by resource; where do we put the config; does Galaxy already have this?

## 1. Current state — stratification is nearly FLAT (the real problem)
Resource per process is set by a Nextflow `label`. Across all `biomni_workflows/nextflow_nfcore/subworkflows/**/main.nf`:

| label | process count | tier (cpus / mem) |
|---|---|---|
| `process_medium` | 3,664 (~96%) | 6 vCPU / 36 GB |
| `process_low` | 99 | 2 / 12 |
| `process_high` | 9 | 12 / 72 |
| `process_gpu*` | 34 | GPU node |
| `process_single` | 5 | 1 / 6 |
| `process_high_memory` | 1 | 12 / 200 |

Plus **422 `.nf` files hardcode `cpus=`/`memory=` directly** (bypassing the tier labels entirely). So in practice almost everything asks for **6 vCPU / 36 GB regardless of the actual work** — a 1-ligand docking shard and a whole-genome alignment step request the same. This is wasteful on cost and, more importantly, it is exactly what throttled the EGFR docking run: 29 shards × 6 vCPU against a 48-vCPU compute-environment cap ⇒ only ~8 shards ran at once.

## 2. Three (really four) competing sources of truth — fragmented
1. `backend/lib/galaxy/ai/resource_resolver.py` → `RESOURCE_TIERS` + `TASK_RESOURCE_MAP` (domain→tier). A clean map, but **not the one that actually applies to Batch runs.**
2. `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:3441-3444` → a hardcoded `withLabel` block injected into every run's `nextflow.config`. **This is the authoritative one at runtime**; it merely says its values "mirror" `RESOURCE_TIERS` (drift risk — they are duplicated by hand).
3. The 422 hardcoded `.nf` directives.
4. The **AWS Batch compute-environment max vCPUs** (`biomate-nextflow-ce-v2` = 48) — the actual throughput ceiling, independent of any of the above. Account EC2 quota is 1,200, so 48 is our own setting.

## 3. Does Galaxy already have this ability? Yes — but this path bypasses it
Galaxy has a mature job-resource system: `job_resource_params_conf` + a `<resources>` group in `job_conf`, which renders a **user-facing resource selector** (cpus/mem/time) at tool-run time and maps the choice to a destination. It is present in this tree (`lib/galaxy/config/sample/job_conf.sample.yml`, `lib/galaxy/tools/execute.py`).
**But BioMate's Nextflow workflows do NOT go through Galaxy's job runner.** `config/job_conf.yml` has only `local` + `nextflow` runners; the real dispatch is the custom `nextflow_executor.py` → AWS Batch. So Galaxy's native resource UI governs only native Galaxy XML tools (Interactive Tools etc.), not the 4,000 Nextflow workflows. We can't get this "for free" from Galaxy for the workflows users actually run; we'd reuse the *idea*, not the plumbing.

## 4. The plumbing to carry a user choice ALREADY EXISTS (unused)
`NextflowExecuteRequest.compute_config` (Pydantic) ← `executionConfig.computeConfig` (routes.ts:11482 `buildNextflowComputeConfig`) ← per-run request. It already flows end-to-end; today it carries queue/container/profile but **not CPU/memory tiers**, and nothing in the UI sets them. The injected tier block at 3441 ignores `compute_config`.

## 5. Recommendation — two distinct levels, don't conflate them
**(A) Per-run resource choice (the user's request).** Add an optional `resources` object to `compute_config` (e.g. `{ "shard_size": N, "tier_overrides": { "process_medium": {"cpus":4,"memory_gb":16} } }`). Make the injected block at `nextflow_executor.py:3441` read it instead of hardcoding, falling back to `RESOURCE_TIERS`. Surface it in the **workflow panel's param strip** — the same place params are already edited and already posts `executionConfig` — as a small "Compute" control (a tier preset: Economy / Balanced / Fast, plus shard size for the dockable steps). This is the right home because it is per-run and per-user, needs no infra change, and reuses an existing request field.

**(B) Throughput ceiling (max parallelism).** The CE `maxvCpus` (48) is **deployment/org scope, not per-user** — it governs the shared fleet and the bill, and one user shouldn't set it per run. It belongs in deployment config (an env var / IaC value the sync reads) and, for a multi-tenant SaaS, behind the plan/quota layer. For on-prem it is simply the customer's cluster size. Raising dev's 48→256 is a one-line CE change (no idle cost; peak only) and is the single biggest speed lever, but it is an infra decision for you, separate from (A).

**Also fix the drift:** make `RESOURCE_TIERS` the single source and have `nextflow_executor.py` render the `withLabel` block from it (import, don't re-type), so (2) can't silently diverge from (1).

## 6. Not done here
This is a design note — no code changed. The stratification counts are from a static scan; the 422 hardcoded files were counted, not individually re-tiered. A real re-stratification (assigning sensible tiers per process instead of a blanket `process_medium`) is a larger follow-up that (A) makes safe to expose.

## 7. Built (2026-11-03): dispatch-time per-group right-sizing — option (b), flag-gated OFF

Section 6 said "no code changed." That is now superseded for the server-side classification piece. We did NOT put anything in the UI (the on-prem environment is still unknown, per the user's call — "we don't know the on premise env, yet"). Instead we built the **server-side classification table** that is the prerequisite for any later UI, and left it gated OFF so dev behaviour is byte-identical until someone opts in.

### What was added
- **`backend/lib/galaxy/ai/resource_classification.py`** (new). Groups each process by what its *name* says it does and maps the group to a tier:
  - `light` 2 vCPU / 8 GB — QC, plotting, reporting, trimming, filtering, format/sort/index
  - `standard` 4 / 16 — DE, enrichment, annotation, normalisation, single-cell stats
  - `heavy` 12 / 64 — alignment, assembly, variant calling, taxonomic classification
  - `shardable` 4 / 16 — ADMET / docking shards (throughput from fan-out, each shard small)
  - `gpu` deliberately **omitted** — GPU processes already carry `process_gpu` and are sized + queue-routed by the executor's existing block; reclassifying here would fight that.
  - Patterns are an ordered first-match list; **specific/heavy before generic** so `VARIANT_ANNOTATION`→`heavy` (variant) not `standard` (annot), and ADMET predictors→`shardable` not `standard` (predict).
- **`nextflow_executor.py`** (after the `withLabel` block, ~3447, inside `if not _is_personal_wf:`): when `BIOMATE_RESOURCE_CLASSIFICATION` is on and we have the dispatched `main.nf`, emit a `withName:` selector for **only the processes that actually exist in that file**. `withName` overrides `withLabel`, so a `FASTQC` labelled `process_medium` drops to the `light` tier; anything unmatched keeps its label tier. Emitting selectors only for present processes avoids Nextflow 24+ strict-mode exit-1 on a selector that matches nothing.

### Why gated OFF (`BIOMATE_RESOURCE_CLASSIFICATION`, default off)
When off, the executor injects nothing new → behaviour identical to today. Turn it on per-deployment once the tiers are validated against that deployment's fleet. A deployment overrides the group→tier numbers with `BIOMATE_RESOURCE_TIERS_JSON` (e.g. `{"light":{"cpus":1,"memory_gb":4},"heavy":{"cpus":32}}`) — merged over the defaults, so partial overrides keep the untouched keys. **This JSON is the seam on-prem needs**: the same classification, re-sized to the customer's hardware, with no code change.

### How this relates to §5
- It is the server half of **(A)** — the group→tier table a later per-run "Compute" preset would select from. The per-run `compute_config.resources` wiring and the UI control in the param strip are still TODO (and still correct to defer).
- It does **not** change the throughput ceiling **(B)** — the CE `maxvCpus` (48) is unchanged. Right-sizing the light/standard majority *down* does, however, free vCPU for the heavy/shardable steps under the same cap, so it helps the EGFR-style throttle indirectly.

### Tests
`backend/lib/galaxy/ai/test_resource_classification.py` (9 cases, all green via `python3.9 .../test_resource_classification.py` — run directly, not via pytest, because the repo's pytest collection pulls heavy ML deps):
group representatives, specific-beats-generic, unmatched→None, `classify_nf_text` only declared+matched processes, disabled-renders-nothing, enabled-emits-only-present-matched, enabled-no-matches→nothing, env-JSON tier override (incl. partial), malformed override ignored.

### On-prem configuration (operator guide — self-contained)

**Where to set.** Both variables are read by the **Galaxy backend process** (the container/service that runs gunicorn on port 8081 and dispatches Nextflow — `biomate-galaxy-dev` on dev; the equivalent Galaxy container/service on-prem). They are read at dispatch time, so a process restart is required after changing them. Set them wherever you set that process's environment — Docker `-e` / compose `environment:`, a k8s Deployment `env:`, or a systemd `Environment=` line. The Node/frontend container does not need them.

**Two variables:**

| Variable | Values | Effect |
|---|---|---|
| `BIOMATE_RESOURCE_CLASSIFICATION` | `1`/`true`/`yes`/`on` to enable; anything else (or unset) = OFF | Master switch. OFF ⇒ the executor injects nothing new; identical to pre-feature behaviour. |
| `BIOMATE_RESOURCE_TIERS_JSON` | a JSON object (see below); unset = built-in defaults | Resizes the group→tier numbers for this deployment's hardware. |

**`BIOMATE_RESOURCE_TIERS_JSON` schema.** A JSON object whose keys are group names and whose values are `{"cpus": <int>, "memory_gb": <int>}`. It is **merged over** the built-in defaults, so you only list the groups/keys you want to change; everything omitted keeps its default. The complete set of overridable groups and their built-in defaults (the baseline you are editing):

| group | default cpus | default memory_gb | covers |
|---|---|---|---|
| `light` | 2 | 8 | QC, plotting, reporting, trimming, filtering, format/sort/index |
| `standard` | 4 | 16 | DE, enrichment, annotation, normalisation, single-cell stats |
| `heavy` | 12 | 64 | alignment, assembly, variant calling, taxonomic classification |
| `shardable` | 4 | 16 | ADMET / docking shards (throughput comes from fan-out) |

Rules the parser enforces (so a bad value degrades safely, never crashes a run):
- Only `cpus` and `memory_gb` are read; any other inner key is ignored.
- A group name not in the table above (e.g. `"gpu"`, a typo) is **silently ignored** — GPU steps are sized by the executor's existing `process_gpu` block, not here, so there is no `gpu` key to set.
- Malformed JSON is logged and ignored (defaults stand) — it will **not** block dispatch.
- `cpus`/`memory_gb` are the only knobs here. **`queue` and `time` are NOT settable via this JSON** — they stay with the existing `withLabel` block. If your scheduler needs a different queue, that is a separate executor/`job_conf` change.

Example (a bigger on-prem node pool — give heavy steps 32 cores, shrink the light tier):
```
BIOMATE_RESOURCE_CLASSIFICATION=1
BIOMATE_RESOURCE_TIERS_JSON={"light":{"cpus":1,"memory_gb":4},"heavy":{"cpus":32,"memory_gb":128}}
```
(`standard` and `shardable` here keep their 4/16 defaults.)

**Capacity caveat.** Each number is a per-process request. `cpus`/`memory_gb` for any group must fit inside a **single scheduler node** — a `heavy` tier of 32/128 requires nodes with ≥32 cores and ≥128 GB, or those processes will never be schedulable. Size the tiers to your smallest node that must run that class of step, not your largest.

**Interaction with the 422 hardcoded-`cpus=` `.nf` files.** `withName` overrides a hardcoded `cpus =`/`memory =` inside a process body too, not just a `withLabel`. So enabling the flag **will** re-size those processes if their name matches a pattern. That is usually what you want (it fixes over/under-provisioned hardcodes), but it means the flag is not purely additive for that subset — audit them if a specific hardcoded value was load-bearing.

**Validate it took effect (no Batch run needed).** Run this against your Galaxy container — it confirms the module imports in your environment, that OFF is a no-op, and that ON renders a valid block for your actual workflow files:
```bash
# inside the Galaxy container (adjust PYTHONPATH to your lib path, /app/lib on the dev image):
PYTHONPATH=/app/lib BIOMATE_RESOURCE_CLASSIFICATION=1 python3 -c '
from galaxy.ai import resource_classification as rc
nf = open("/app/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/docking_autodock_vina/main.nf").read()
print("declared -> group:", rc.classify_nf_text(nf))
print("\n".join(rc.render_withname_lines(nf)))'
```
Expected: a `process { withName: ... }` block listing only the processes declared in that file, each with your tier numbers. With the flag unset it prints nothing. To audit the whole catalog's classification, loop `classify_nf_text` over every `subworkflows/**/main.nf` and eyeball the group assignments before enabling in production. *(This is the exact check run against dev on 2026-11-03; it passed — import OK, OFF renders `[]`, ON tagged `DOCKING_AUTODOCK_VINA`/`DOCKING_MERGE` → shardable.)*

### Still not done
No re-tiering of the 422 hardcoded-`cpus=` `.nf` files (they bypass labels *and* `withName` can still override them — but they were not audited individually). No UI. The flag stays OFF on dev until a run-level validation confirms the `withName` block is accepted by the executor's Nextflow version in a live Batch run.
