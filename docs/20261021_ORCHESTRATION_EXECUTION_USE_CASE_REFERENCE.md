# 2026-10-21 — BioMate Orchestration & Execution: Authoritative Use-Case Reference

**Purpose.** The single reference for *how BioMate turns one chat request into one or
more workflow executions* — decomposition, the two multi-workflow paths, how step-to-step
handoff actually works, and what is proven vs unproven. Written from a direct code audit
(file:line citations verified against the tree on this date), not from memory or demos.

**Honesty contract.** Every capability below is tagged with how strongly it is evidenced:
- **[code]** — the implementation exists and was read directly.
- **[unit-mock]** — covered by a test, but with mocked submit/poll (no real Nextflow run).
- **[E2E-card]** — an end-to-end test exercises routing/card rendering, not execution.
- **[UNPROVEN-E2E]** — **no test executes this end-to-end against real compute.**

> Bottom line, stated once up front: the **sequential/chain executor is real and
> non-trivial [code]**, but **no test — unit or E2E — runs more than one real workflow
> to completion from a chat request [UNPROVEN-E2E]**. **Parallel multi-intent is not
> orchestrated at all** — it emits independent cards the user runs one at a time. A live
> end-to-end validation run is tracked in §7.

---

## 1. Routing: how one request becomes a plan

The intent classifier (`galaxy-assistant.ts::analyzeIntent`) labels each request as
single / multi-intent / sequential, and `_processMessageInner` dispatches:

| Shape | Trigger | Handler | Result object |
|---|---|---|---|
| **Single** | one task | single-intent path (`galaxy-assistant.ts:4029+`) | one workflow card |
| **Parallel multi-intent** | `isMultiIntent` (e.g. "RNA-seq **and** ATAC-seq") | `processMultiIntent` (`:5478`) | primary card + `additionalWorkflows[]` |
| **Sequential pipeline** | `isSequential` (output of N feeds N+1) | `processSequentialPipeline` (`:5064`) | `workflow_type:'pipeline'`, `pipeline_steps[]` |
| **Named chain** | query maps to a curated chain | TIER 1/2/3 chain resolution | `workflow_type:'chain'` |

The classifier now also emits a plain-language **`rationale`** for every request, shown in
the progress box as the "why this routing" line (`galaxy-assistant.ts:3982`, prompt
`:6447/6479/6527/6605`). For a multi-intent request the rationale is a single prose
sentence naming the split (not a per-intent list) — the per-intent breakdown appears as
the workflow **cards**, not in the progress box.

---

## 2. Path A — Parallel multi-intent (NOT orchestrated)

**What happens [code]:** `processMultiIntent` (`galaxy-assistant.ts:5478`) unions all
intents' keywords into one tool/dataset search, runs `Promise.all(processSubIntent)` over
each intent (`:5541-5546`) — so *search and workflow generation* happen in parallel — then
picks one **primary** runnable workflow (`:5558-5560`) and keeps the rest as
`additionalWorkflows` (`:5566`). `processSubIntent` **generates/searches; it does not launch
runs.**

**What executes:** nothing automatically. The frontend renders each of `additionalWorkflows`
as its **own** `NextflowWorkflowViewer` card (`chat-message.tsx:1028-1066`), each with its
own run button. **There is no "run all / run together" affordance — the user runs each card
one at a time.**

**So "parallel" today = the user launches N independent cards.** BioMate does not fan out,
batch, or aggregate multiple workflows from one multi-intent request.
Tests: decomposition/card-list only (`multi-intent-workflows.test.ts`, 3 pure-function
cases) — **[UNPROVEN-E2E]** for any multi-run.

---

## 3. Path B — Sequential pipeline / chain (REAL executor, user-gated)

### 3.1 The plan (chat side) [code]
`processSequentialPipeline` (`galaxy-assistant.ts:5064`) builds a `pipeline_steps[]` plan
(`:5353-5373`): each step carries `nextflow_path`, `params`, `input_from` (prior step id),
and a **prose** `uses_description` ("Output from step N: …"). At this layer the data flow is
**described, not yet physically wired**. A "single-workflow collapse" (`:5385-5399`) folds a
plan whose steps all resolve to the same `.nf` back into one card.

### 3.2 The executor (backend) [code] — verified directly
A pipeline/chain card submits to **`POST /api/workflows/chain`** (proxied
`routes.ts:12388` → backend), handled by **`backend/.../workflow_chain.py`** (~1700 lines).
`_run_chain` (`:473`) is a genuine sequential engine — verified line-by-line:
- Loops steps from `start_from_step`, marks each `running`, writes a heartbeat (`:489-503`).
- **Auto-wires outputs → inputs**: `_apply_connection_handoffs` for explicit connections
  (`:518-519`) and `_resolve_outputs_for_run(prev_run_id, …)` to pull the previous run's
  output files into the next step's params (`:572-577`).
- **Context-param propagation** across steps, e.g. genome → organism for DESeq2/
  clusterProfiler (`resolve_context_params`, `:535`).
- **Type-compatibility check** between prev output types and next input types
  (`check_step_compatibility`, `:558`) with warnings/suggestions surfaced.
- Launches each step via the **real** single-run executor (`execute_nextflow`, `:592-597`)
  and polls to completion before the next step.
- `_run_dag_chain` (`:680`) runs explicit dependency graphs topologically (fan-out / join /
  blocked-on-failure); resume via `start_from_step`; cancel handling (`:494`).

The ordinary `nextflow_executor.py` is strictly **one workflow per run**; its only chain
awareness is reading a `chain_meta.json` sidecar for the "why?" anchor and firing downstream
chain **suggestions** via SSE after success — suggestions, not execution.

### 3.3 The approval gate [code] — important UX nuance
From `chain-execution.ts::pipelineApprovalOptions` (`:64-68`):
- A **legacy linear pipeline** submits with `endAtStep:0` → **runs step 1 only**, then each
  user approval resumes the next step (`resumeWorkflowChain`). So a sequential pipeline from
  chat is **per-step user-gated by default, not one-click full-auto.**
- An **explicit DAG plan** submits the whole plan on one confirm.

---

## 4. Worked use-case examples

**UC-1 — Sequential: "Quantify my RNA-seq FASTQs then run DESeq2 differential expression."**
→ classifier: `isSequential` → `pipeline_steps` = [nf-core/rnaseq quant, DESeq2 DE] →
`workflow_type:'pipeline'` card → `POST /api/workflows/chain` → `_run_chain` runs step 1,
resolves its count-matrix output into step 2's input, propagates genome→organism, runs
step 2. **Default: you approve step 2 after step 1 finishes.** Status: executor **[code]**,
end-to-end **[UNPROVEN-E2E]** — this is the case §7 will validate live.

**UC-2 — Parallel: "Run RNA-seq DE and ATAC-seq peak calling on these samples."**
→ `isMultiIntent` → primary card (one) + `additionalWorkflows` (the other) → two cards.
**You run each card yourself; BioMate does not run them together.** Status: decomposition
**[code]**, multi-run **not implemented**.

**UC-3 — Named chain (curated):** a query matching a known multi-step chain resolves via
TIER 1/2/3 to `workflow_type:'chain'` → `WorkflowChainPlan` card → `onRunChain` →
`/api/workflows/chain` (DAG or sequential). Same executor as UC-1.

---

## 5. Capability × evidence matrix (honest)

| Capability | Evidence |
|---|---|
| Classify single / multi / sequential | [code] + routing unit tests |
| Parallel search + per-intent generation | [code] (`Promise.all(processSubIntent)`) |
| **Automatic parallel multi-workflow execution** | **not implemented** (cards only) |
| Sequential step execution, output→input handoff | [code], verified (`_run_chain`, `_resolve_outputs_for_run`) |
| Type-compatibility check between steps | [code] (`check_step_compatibility`) |
| DAG fan-out/join, blocked-on-failure | [code] (`_run_dag_chain`) + [unit-mock] (`test_chain_dag.py`) |
| Resume / per-step approval | [code] + [unit-mock] |
| Chain request-body contract | [unit-mock] (`chain-submission-contract.test.ts`) |
| Chain card renders + "Run" button visible | [E2E-card] (`chain-system-comprehensive.e2e.ts`) |
| **≥2 real workflows run to completion from one chat request** | **[UNPROVEN-E2E] — no such test** |
| Chain works against real Nextflow/AWS Batch in prod | **unverified — no live-execution test found** |

---

## 6. Known gaps
1. **No end-to-end multi-run proof.** Engine tests mock submit/poll; the one multi-step E2E
   (`composer-dag-draft.e2e.ts:143-157`) explicitly asserts the draft is **not** dispatched.
2. **Parallel multi-intent is presentation-only** — no batched execution.
3. **Docs were fragmented** before this file: ~15 audit/design docs, several marked
   "built but dormant/unwired" (`20261019`, `20261008`, `20261005`, `20261009`), some
   correcting each other. This doc supersedes them as the execution reference.

---

## 7. Live end-to-end validation — UC-1 (RNA-seq quant → DESeq2 DE)

**Status: PENDING — run on dev, results to be folded in below.**
Plan: drive UC-1 on `dev-public.biomate.ai` through `/api/workflows/chain` with the fixture,
observe (a) step 1 launches and completes, (b) step 1 output auto-resolves into step 2
params, (c) step 2 launches and completes. Record run ids, the handoff params, and whether
it ran smoothly or exposed a bug. This is the first evidence that moves the UNPROVEN-E2E
rows above to proven (or finds the defect).

### 7.1 — Live run 2026-10-24: cheapest-chain handoff proof (admet_to_cipa_cardiac)

Per the approved plan, the first live proof used the **cheapest** valid 2-step chain
(ADMET → CiPA; tiny SMILES input, no alignment) rather than the heavy RNA-seq→DESeq2, to
prove the step1→step2 mechanism at minimal Batch cost. Fixture login on
`dev-public.biomate.ai`; `POST /api/workflows/chain` (body = 2 steps + a
`herg_ic50_nM` connection).

**Result — control plane PROVEN, handoff pending (defect found):**
- Submit accepted → `chain_run_id=chain_1792887838_8c3e36`, status `running`, both steps
  registered. [proven]
- Step 1 (ADMET) **launched** on the real backend: `run_id=ae8dc627-…`, S3 `outdir`,
  `started_at`/`completed_at` timestamps. [proven]
- Step 1 **failed in ~11 s**; the chain then **halted with step 2 blocked-on-failure
  (stayed `pending`)** — the sequential executor's launch → fail-detect →
  blocked-on-failure flow works end-to-end. [proven]
- **Handoff NOT exercised** — step 1 produced no output, so no step1→step2 param
  resolution occurred. [still UNPROVEN]
- **Defect surfaced:** the ADMET step failed at/near launch — `run_id` is absent from
  `execution_runs` (`/api/workflows/runs/<id>` → "not found"), `outdir` domain segment is
  `unknown`, `artifacts: {}`. The chain executor resolves `nextflow_path` relative to a
  workflows root (`workflow_chain.py:431-437`: tries `backend/<path>` …); the DB
  `filename` path `nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf`
  likely does not resolve to the actual file (found earlier at
  `backend/biomni_workflows/nextflow/subworkflows/pharmacology/predict_admet_properties.nf`).
  Needs the dev backend error log for run `ae8dc627` (SSM) to confirm path-resolution vs.
  `smiles_list` format.

**Net:** the orchestration *control plane* is now evidenced end-to-end against real dev
(submit → launch → blocked-on-failure), moving those rows from UNPROVEN toward proven;
the *output→input handoff* remains unproven pending a step-1 success. Next: get the
run-`ae8dc627` backend error (path resolution is the leading hypothesis), fix the step
path, re-run the cheap chain to show the handoff, then the RNA-seq→DESeq2 UC-1.

_(UC-1 RNA-seq→DESeq2 still pending — to run after the cheap-chain handoff is green.)_

---

## 8. Key file map
| What | Where |
|---|---|
| Intent classification + routing | `frontend/server/galaxy-assistant.ts::analyzeIntent`, `_processMessageInner` |
| Parallel multi-intent | `galaxy-assistant.ts::processMultiIntent` (:5478), `processSubIntent` (:5697) |
| Sequential plan build | `galaxy-assistant.ts::processSequentialPipeline` (:5064) |
| Chain submit contract (frontend) | `frontend/client/src/lib/chain-execution.ts` |
| Card rendering | `chat-message.tsx` (:1028 parallel, :889 pipeline, :928 chain) |
| Run handlers | `chat-with-artifacts.tsx::handleRunPipeline` (:1390), `handleRunChain` (:1303) |
| Chain API proxy | `frontend/server/routes.ts` (:12388) |
| **Chain executor (real)** | `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py::_run_chain` (:473), `_run_dag_chain` (:680) |
| Single-run executor | `backend/.../nextflow_executor.py` (one workflow per run) |
| Engine tests (mocked) | `backend/tests/test_chain_dag.py`, `test_chain_dag_api.py` |
