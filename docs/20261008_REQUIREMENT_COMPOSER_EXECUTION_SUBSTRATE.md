# REQUIREMENT — Dynamic Composer / Execution Substrate (for another session)

**Date:** 2026-10-08
**Status:** Engineering requirement / handoff spec. To be OWNED and executed by a separate session.
**Source of truth:** `docs/20261008_DECOMPOSITION_EXECUTION_FLEXIBILITY_AUDIT.md` (the code-grounded audit this plan implements), `docs/20261005_CHAIN_CONNECTION_AUDIT.md` (the 56/137-broken data), `docs/20260723_FLEXIBLE_CHAIN_EXECUTION_DESIGN.md` (prior design; fork/join was out-of-scope there).

## 1. Why (the problem, proven in code)

BioMate today does **literal single-workflow routing + fragile, hand-authored, strictly-sequential chains.** It **cannot**, in production, dynamically resolve a tool *set*, run tools in **parallel** on one input, or **aggregate/rank/select**. Evidence:
- Routing picks one `best_match` (`ai_assistant.py:4940,4997`); composer emits one `.nf` (`nextflow_composer.py`). No category→tool-set resolver.
- Chain execution is a sequential `for`-loop (`workflow_chain.py:465-479`); `grep parallel` across the chain layer = 0 hits. "Aggregate outputs" (`workflow_chain.py:1341`) is a **file collector** — no rank/top-k node. DAG fork/join explicitly out of scope (`20260723_...:832-834`).
- **The plan is discarded:** `TaskDecomposer` emits `parallel_with` hints, but `ai_assistant.py:724-728` throws them away ("full parallel dispatch (LangGraph + Celery) is **Phase 1**") → collapses to single-workflow generation.
- `chain_composer/composer.py` (the real compositional engine) is **test-only**, linear 2–5 steps, no parallel/aggregate/select nodes, no live caller.
- **41% of hand-authored chain connections are broken** (56/137; only 5/69 chains fully OK) — even sequential chaining is unreliable.
- The SciMiner peptide screenshot (fan-out→rank-sum→top-5) is **bespoke** research scripts (`research/...`, `drug_discovery/multi_property_selection.py`, `bayesian_optimizer.py`, `permeability_predictor.py`; `20260925_PEPTIDE_EXECUTION_PLAN.md`) run OUTSIDE the chat composer — not a general capability.

**Key reframe:** the **LLM is not the bottleneck** — a frontier LLM already plans fan-out→rank→select correctly (`composed_rate 1.00`, `validity 1.00`). The missing piece is the **substrate to execute the plan.** Build that.

## 2. Goal + end-to-end acceptance scenario

Make the "easy but needs mature decomposition" class work **generally**. Canonical acceptance scenario (the peptide example, generalized):

> User (one sentence): *"Here are some peptide sequences I designed — run all the peptide-property prediction tools and shortlist 5 for validation."*
> BioMate must: recover the input set → **resolve the tool category** (all peptide-property tools) → **run them in parallel** on the same input → **aggregate/rank** (e.g. rank-sum) → **select** top-5 → report.

Plus ≥2 more fan-out/aggregate scenarios from different domains (e.g. *"run DESeq2 and edgeR and give the consensus DE genes"*; *"predict ADMET across these SMILES and rank by developability"*) to prove it's general, not re-special-cased.

## 3. The six primitives (what to build), prioritized

### Phase 0 — Make existing composition reliable (prerequisite, also a quick win)
**P4. Robust handoff contract.** Fix the 41%-broken connection resolver (root cause: semantic connection labels vs a filename-substring resolver with no fallback). Replace with a typed I/O handoff contract (output-type → input-type match + explicit fallback + validation at compose time, failing loudly). Acceptance: re-run `scripts/`/`20261005_CHAIN_CONNECTION_AUDIT` → broken rate ≪ 41% (target <5%), all 69 chains resolve or error explicitly. *Do this first — nothing reliable composes on a 41%-broken substrate.*

### Phase 1 — The core missing capability: parallel execution of the plan
**P2. Parallel fan-out executor.** Replace the sequential `for`-loop (`workflow_chain.py:465-479`) with a **DAG executor** that honors `depends_on` / `parallel_with`: nodes with no mutual dependency run concurrently (on AWS Batch — BioMate's executor already does per-job Batch). **Stop discarding the plan:** remove the `ai_assistant.py:724-728` fallback so the `TaskDecomposer` DAG is actually dispatched. Acceptance: a plan with 3 independent tools on one input launches 3 Batch jobs concurrently and joins; a sequential plan still runs in order.

### Phase 2 — Complete the pattern: aggregate + category
**P3. General aggregate/rank/select node.** A first-class node type (not a file collector) that takes N upstream outputs + a spec (rank-sum / Pareto/EHVI / top-k / consensus / compare) → ranked table + selected subset. Reuse the real bespoke logic (`drug_discovery/multi_property_selection.py`, `bayesian_optimizer.py` EHVI) as the engine, exposed generically. Acceptance: the peptide rank-sum + a consensus-DE case both produce correct ranked tables + top-k.
**P1. Category → tool-set expansion.** A resolver that maps "all peptide-property tools" / "all ADMET predictors" to the concrete catalog tool set (via the catalog categories / `UnifiedWorkflowSearch` + the capability lexicon in `evaluation/datasets/reverse_decomp/accept_sets.json` / `capability_lexicon.py`). Acceptance: "all peptide-property tools" → {the real galaxyp peptide toolset}; "all DE methods" → {DESeq2, edgeR, limma, …}.

### Phase 3 — Inputs + consolidation
**P6. Input recovery.** Resolve prior-run / share-link / accession inputs (today only GEO/SRA accession recovery exists). Add a share-link/prior-run-ID resolver so "the peptides I designed before" works. Acceptance: a prior-run reference recovers its output set as the new input.
**P5. Wire the real composer live.** Connect `chain_composer/composer.py` (or the new DAG executor) to the live path (`galaxy-assistant.ts` / `ai_assistant.py`), replacing the single-`.nf` hot path for multi-tool intents; keep single-workflow routing untouched for single-intent requests. Acceptance: a multi-tool chat request flows through the composer end-to-end in the product.

## 4. Hard constraints
- **Do NOT break single-workflow routing** — the literal one-workflow path is the proven strength (+0.69 harness dividend); multi-tool composition is an *additional* path, gated on detecting a multi-tool/aggregate intent.
- **Root cause, not workaround** (CLAUDE.md): no special-casing per domain; the peptide example must work *because* the general primitives work, not via a peptide branch.
- **Reliability first:** P4 before P2 — don't build parallel dispatch on a 41%-broken handoff.
- **The LLM already plans** — do NOT rebuild planning; consume the `TaskDecomposer`/LLM DAG. (Plan *fidelity* improvements are a separate LLM track.)
- **Execution-graded acceptance** (`project_execution_grader`): each primitive's acceptance test is a real run that produces the expected output, not a unit mock.
- Honesty: until this ships, "mature decomposition + execution" stays labeled **Aspirational** in external material.

## 5. Suggested effort / sequence
P4 (reliability fix) → P2 (parallel DAG executor + un-discard the plan) → P3 (aggregate/select) + P1 (category expansion) → P6 (input recovery) + P5 (live wiring). P4+P2 are the load-bearing majority of the value (they make the screenshot class *possible*); P1/P3 make it *clean*; P5/P6 make it *seamless*.

## 6. Key files
- Routing/interp: `backend/lib/galaxy/ai/ai_assistant.py` (4940, 4997, 724-728), `frontend/server/galaxy-assistant.ts` (3790-3795, 3971), `backend/lib/galaxy/ai/nextflow_composer.py`, `chain_composer/composer.py` (571-588).
- Execution: `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py` (465-479 exec loop, 1341 aggregate), `nextflow_executor.py` (Batch dispatch).
- Capability lexicon / tool-set data: `evaluation/datasets/reverse_decomp/{capability_lexicon.py, accept_sets.json}`.
- Aggregate engine to reuse: `drug_discovery/multi_property_selection.py`, `bayesian_optimizer.py`.
- Audits: `docs/20261008_DECOMPOSITION_EXECUTION_FLEXIBILITY_AUDIT.md`, `docs/20261005_CHAIN_CONNECTION_AUDIT.md`.

## 7. Done =
The acceptance scenario (§2) + the 2 cross-domain scenarios run end-to-end in the product through the general primitives (no per-task special-casing), single-workflow routing is unregressed, and the chain-connection broken-rate is <5%. Then flip "decomposition + execution" from Aspirational to Evidenced in the capability docs.
