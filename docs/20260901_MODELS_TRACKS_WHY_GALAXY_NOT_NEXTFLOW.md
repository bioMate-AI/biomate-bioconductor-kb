# Models Tracks: Why the endpoints live in Galaxy, and why they do NOT run on Nextflow

Date: 2026-09-01 (updated 2026-09-07)
Branch: `feat/models-real-tracks` (PR #212)
Author: session note for review
Status: for review

## Purpose

This note answers an architecture question raised in review of the Models
module work (PR #212): **why do the new Models-tracks endpoints live in the
Galaxy backend, and why is the Adapt "retrain" NOT executed on Nextflow / AWS
Batch like the scientific workflows?**

It is a design-rationale document, not a change record. The change record is in
the PR description and commit messages.

## TL;DR

- **Galaxy = BioMate's API / web tier.** Every `/api/*` service endpoint lives
  in the Galaxy FastAPI app and is auto-discovered there. "Galaxy" here names
  the backend web framework BioMate runs on — it is not a bioinformatics-
  workflow concern.
- **Nextflow = BioMate's scientific-pipeline executor.** It runs bio / drug-
  discovery *workflows* (RNA-seq, WGS, ADMET, cryo-EM, PBPK) on AWS Batch,
  driven by `nextflow_executor.py`.
- The Models tracks read and lightly mutate **model-lifecycle state**
  (registered scorers, customer edit-pairs, optimizer proposal rounds) and run a
  **cheap, CPU-only, seconds-long** adaptation compile. That is not a data
  pipeline, so it correctly does **not** touch Nextflow.
- The one genuinely heavy step — **GPU LoRA training** (`post_train_lora`) — is
  deliberately **not** run inline; the existing worker gates it behind a harness
  witness. When it does run, it belongs on a GPU-training path, still not
  Nextflow.

## Where the code lives

| Concern | Location | Why here |
|---|---|---|
| Models track read/mutation endpoints | `backend/lib/galaxy/webapps/galaxy/api/models_inference.py` | The Galaxy FastAPI app is where all `/api/*` endpoints are defined and auto-discovered (`include_all_package_routers()` mounts any module exposing a `router`). |
| Node → Galaxy proxy | `frontend/server/routes.ts` (`_dlProxyHandler`, `/api/model-tracks/*`) | The browser talks to the Node server; Node proxies `/api/*` to Galaxy with the user's decrypted Galaxy API key. Same handler already fronts `/api/models*`. |
| Retrain worker | `backend/lib/galaxy/ai/drug_discovery/regulatory_training_worker.py` | Pre-existing, complete worker that consumes the `regulatory_training_jobs` store. |
| Runs dashboard store | `frontend/server/storage.ts` (`execution_runs` in Postgres + in-memory map) | The dashboard lists Node/Postgres runs only. There is NO shared Galaxy↔Node runs store. |

The Models-tracks routes were added to the **same file** that already holds the
Models registry / detail / inference-dispatch endpoints so they share its
catalog helpers, its honesty contract (labelled-empty, never fabricated), and
the existing Node proxy. "Galaxy" is incidental — it is simply the name of the
web framework the BioMate backend is built on.

## Why NOT Nextflow — the distinction

Nextflow in BioMate orchestrates **scientific data pipelines** on AWS Batch:
multi-phase genomics / chemistry / structural workflows, each a real compute job
with containers, gates, and step outputs. The `nextflow_executor.py` path exists
for exactly that.

What the Models tracks do is different **in kind**, not just in size:

### 1. The reads are state, not compute

- `GET /api/model-tracks/train` — lists registered scorers + adaptation jobs.
- `GET /api/model-tracks/adapt` — lists customer before→after edit pairs.
- `GET /api/model-tracks/optimise` — reads the latest optimizer proposal round.

These are **database / JSONL reads** shaped onto the frontend contract. There is
no pipeline to run. Routing a read through Nextflow would be nonsensical.

### 2. The default retrain is a sub-second CPU compile

`POST /api/model-tracks/adapt/retrain` submits a job and advances it one worker
tick. The default adaptation mode is `prompt_rules`, which — per the worker's own
docstring — "compiles org edit-pair signal into a per-org rule YAML … cheap
(~ms per pair), no GPU." It runs in seconds and produces a rule file that the
serving path (`ind_assembly._build_rag_context`) loads on the next inference call.

Spinning up a Nextflow / AWS Batch job for a sub-second rule compile would be
wrong on three axes:

- **Cost** — a Batch job has real per-invocation overhead (~$ and provisioning
  time) for what is a millisecond CPU task.
- **Latency** — the user toggled a control; they should see the retrain complete,
  not wait on Batch scheduling.
- **Domain fit** — Nextflow orchestrates bio-workflows, not model adaptation /
  rule compilation. This is a lifecycle operation on model state, not a genomics
  or chemistry pipeline.

The in-process worker tick is the correct execution model for the cheap path.

### 3. The heavy path is gated, and still not Nextflow

The worker has a third mode, `post_train_lora` — a full GPU SFT/DPO LoRA on the
open base. It is **not** started by the retrain endpoint, and the worker itself
**refuses to run it** without `models/regulatory_llm_eval_witness.json` showing
local > frontier with non-overlap CI on the org's task mix. This is the CLAUDE.md
"Review Code Before Testing — No Speculative Deploys" discipline applied to GPU
spend.

When that mode does run for real, it belongs on a **GPU-training** path
(dedicated GPU worker / Batch GPU queue for model training), which is still
distinct from Nextflow: Nextflow runs bio-workflow DAGs, not model SFT/DPO
training loops.

## "Training should feel like running a workflow" — the dashboard integration

The reference-design Train-track intent is that training reads as a run, not a
separate product. Two facts shaped how that was implemented:

1. There is **no shared Galaxy↔Node runs store.** The Runs dashboard lists
   Node/Postgres `execution_runs` only (via `storage.createExecutionRun`);
   Nextflow runs are retroactively linked by `galaxyInvocationId` /
   `nextflowRunId`, but the canonical record is in Node Postgres. A job that
   never touches Nextflow will not appear unless it is registered there.
2. The retrain job already runs synchronously (seconds, no GPU), so there is a
   real terminal status to report immediately — no long-poll needed.

**Implementation (built):** a dedicated Node handler for
`POST /api/model-tracks/adapt/retrain` proxies to Galaxy (the job runs and
reaches a terminal state), then calls `storage.createExecutionRun` tagged
`workflow_type: "training"` / `executionEngine: "pipeline"` and reflects the
job's terminal status (`succeeded → completed`, `failed → failed`, else running/
queued). The run id is returned so the UI can deep-link. Run registration is
best-effort — a failure only logs and never alters the API response. The
dedicated route is registered before the generic `/api/model-tracks/*` proxy so
reads and the toggle POST fall through unchanged.

This makes a retrain a **first-class run** in the dashboard — honestly tagged as
training, never faked as a Nextflow subprocess.

## What changed in PR #212 (for context)

- Models-tracks read endpoints (Train / Adapt / Optimise) over real existing
  stores, with an honesty contract (labelled-empty, never fabricated).
- Adapt toggle + retrain persisted server-side; retrain advances the job one
  worker tick so it completes end-to-end and writes a real artefact.
- `train_track` lists the real `regulatory_training_jobs` runs (incl. retrains)
  with live status.
- Retrain now **registers a first-class run** in the Runs dashboard (this doc's
  §"dashboard integration").
- **No new worker was written.** The complete `regulatory_training_worker`
  already existed; the change wires the Models-track flow to it.

## Remaining follow-up (not in scope)

- **GPU training on a Batch GPU path.** When `post_train_lora` is enabled (after
  a harness witness), dispatch it onto a GPU-training queue and register it as a
  run the same way. Still not Nextflow (which runs bio-workflow DAGs, not model
  training). Flag if you want this built.
