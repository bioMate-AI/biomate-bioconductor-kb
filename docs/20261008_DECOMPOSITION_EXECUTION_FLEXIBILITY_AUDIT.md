# Decomposition & Execution Flexibility Audit — Can BioMate Handle "Easy but Needs Mature Task Decomposition"?

**Date:** 2026-10-08
**Mode:** Read-only code investigation. No files changed.
**Question asked:** Is BioMate's interpretation + execution *too literal* to flexibly handle tasks that are not hard but need mature task decomposition — the canonical example being *"take the cyclic peptides from this prior run, run ALL peptide-property prediction tools on them, and shortlist 5 for validation"* (recover inputs → fan out to a **dynamic SET** of tools in parallel → aggregate/rank → select)?

**Ground truth of the target behavior** (`/Users/kky/Desktop/business/bioconductor_screenshot/task_decomposition_example.jpg`): a one-sentence request with a `scminer.tech/share?id=…` link to previously-designed KRAS-G12D 8-mer cyclic peptides. The platform (a) parsed the share link back to 16 unique sequences, (b) ran **PepFuNN** (Peptide Descriptors) + **Peptide-Tools** + **CPMP** (MAT permeability model) **in parallel** on the same input, and (c) produced a **rank-sum** top-5 (CyclicMPNN score + mean permeability + developability-penalty rank-sum).

**Verdict (one line):** BioMate is at **(b) on the spectrum — single-workflow routing plus *pre-authored, hand-wired, strictly-sequential* chains — not (c) genuine dynamic decomposition+aggregation.** The screenshot behavior is **not a general production capability**: none of its three tools exist in the catalog or codebase, and the parallel-fan-out + rank-sum + select primitives it shows are **absent from the live composer and executor**. That run was assembled from the **bespoke peptide research track**, not the chat composer. The honest grade is "literal + fragile-sequential," and the fix is **primarily in the harness/composer, not the LLM.**

---

## 1. Interpretation / routing — maps to ONE workflow, or a pre-authored chain; no dynamic SET

**Routing resolves a single best match.** The live generation path (`backend/lib/galaxy/ai/ai_assistant.py:4940, 4997`) selects `best_match` at high/medium/low confidence — one workflow. When nothing matches, the fallback is `NextflowComposer`, which **generates a single new `.nf` pipeline** from tool search (`backend/lib/galaxy/ai/nextflow_composer.py:1-20` — *"LLM-driven Nextflow DSL2 workflow generator … Used as the fallback when no high/medium confidence workflow match is found … single LLM call in the hot path"*). It emits one DSL2 file, not a fan-out over an open set of independent tools.

**There is no "category → tool SET" resolver.** Nothing in the routing path expands a phrase like *"all peptide-property tools"* into a concrete, dynamically-sized set of tools to run. I searched routing/composer for category-expansion / "run all tools" semantics and found only (a) per-domain routing prose and (b) **multi-intent fan-out**, which is a different thing.

**Multi-intent fan-out ≠ dynamic set expansion.** `frontend/server/galaxy-assistant.ts:3790-3795, 3971` splits a message that contains *multiple distinct user intents* ("do DE **and** run ADMET on this SMILES") into independent sub-intents, each processed on its own (`processMultiIntent` → `Promise.all(processSubIntent)`). It keys off **separate asks the user typed**, never off expanding one ask ("all peptide tools") into N tool runs. So "run all property tools" is seen as a *single* intent and routed to a single workflow.

**Input recovery is accession-only; the share-link recovery in the screenshot is not in the reviewed code.** BioMate can recover inputs from GEO/SRA/PDB accessions (`galaxy-assistant.ts:2390-2452`, `geo_data_connector`, `geo_scrna_pseudobulk`). But there is **no `scminer.tech/share?id=…` → prior-run-outputs resolver** in the reviewed tree — the only `share` handling in `backend/lib/galaxy/**` is Galaxy's native history/page/workflow UI sharing (`pages.py:299`, `visualizations.py:211`, Selenium `navigates_galaxy.py`), not "parse a share link back into the designed sequences of a prior run." The input-recovery half of the example is therefore **not evidenced as a general capability** either.

**The one engine that *could* compose novel multi-step plans is a prototype wired only to tests.** `backend/lib/galaxy/ai/chain_composer/composer.py` (`compose_chain`, retrieval → curated-chain exemplars → LLM compose) is the real "compositional" module, but its only callers in the whole repo are `backend/tests/test_chain_composer.py` — **no `webapps` route, no `frontend/server` caller**. Its output schema (`composer.py:571-588`) is a **linear** chain: `steps[]` + `edges[{from_step,to_step,via}]`, with hard constraints *"workflow_name MUST be from the CANDIDATE list … Keep chains short (2-5 steps)."* There is **no parallel branch, no aggregation node, no selection node** in the schema.

---

## 2. Execution / composition — strictly sequential; no fan-out, no aggregate, no select

**The chain executor runs one step at a time.** `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py:465-466` — `def _run_chain(...): """Execute chain steps sequentially in a background thread."""` — is a plain `for idx in range(start_from_step, len(steps))` loop (`:479`). No two steps in a chain ever run concurrently.

**No "parallel" concept exists anywhere in the composition/execution data model.** `grep -niE "parallel"` across `chain_composer/`, `nextflow_composer.py`, `chain_planner.py`, and `workflow_chain.py` returns **zero hits**. The only parallelism in the product is **"parallel-independent"** — launching N *separate* runs in N browser contexts (`docs/20260723_FLEXIBLE_CHAIN_EXECUTION_DESIGN.md` §2, the `test_mg_demo_parallel.mjs` harness) — which is not a fan-out→join inside one plan. That same design doc states arbitrary DAG branching is **explicitly out of scope**: *"Explicitly out of scope … arbitrary DAG branching (parallel forks/joins beyond the existing parallel-independent harness)"* (`20260723_FLEXIBLE_CHAIN_EXECUTION_DESIGN.md:832-834`).

**Connections are single-predecessor param handoffs, not a compute join.** `_apply_connection_handoffs` (`workflow_chain.py:251-299`) wires `from_step.from_output → to_step.to_input` by **filename-substring matching**. Multiple connections *can* target one `to_step` (merging several predecessors' params), but that is a param merge, not concurrent execution and not a reduction/aggregation computation.

**The "aggregate" endpoint is a file collector, not a rank-sum.** `GET /api/workflows/chain/{id}/outputs` (`workflow_chain.py:1341`, *"Aggregate outputs across chain steps"*) just gathers each step's output files into one list. There is **no node type that computes a rank-sum / Pareto / top-k selection** across sibling outputs. The rank-sum + shortlist-5 in the screenshot has no corresponding executor primitive.

**The task decomposer exists but its multi-step output is discarded before execution — the single most damning finding.** `TaskDecomposer` (`backend/lib/galaxy/ai/task_decomposer.py`) is live-referenced (`ai_assistant.py:259-263, 687-699`) and can even emit `parallel_with` hints (`task_decomposer.py:224, 250`). But after it decomposes a request into N tasks, the live path throws the graph away:

```
# ai_assistant.py:724-728
# No missing context — fall back to single-task generation for now.
# Full parallel dispatch (LangGraph + Celery) is Phase 1 of the main plan.
log.info(f"[MultiTask] {len(tasks)} tasks detected, generating sequentially for now")
return await self._handle_workflow_generation(query, context)
```

So multi-task decomposition in production collapses to **single-workflow generation**, and the comment names the missing piece outright: **"Full parallel dispatch (LangGraph + Celery) is Phase 1 of the main plan"** — i.e. not built. Templates in `task_decomposer.py` are also hard-coded (`rna_seq_analysis`, `genome_assembly`, `variant_calling`) — a fixed template bank, not dynamic composition.

---

## 3. Reliability — even the pre-authored sequential chains are 41% broken

The chain catalog is **hand-authored** (scripts `backend/scripts/add_*_chain.py`, `add_tier0_drug_design_chains.py`, `add_zhao_lab_chains.py`, …), stored as 69 rows in `workflow_chains`. The step-to-step connection audit (`docs/20261005_CHAIN_CONNECTION_AUDIT.md`, read-only, static+resolver-accurate) quantifies how robust the multi-step machinery actually is:

| Verdict | Count of 137 connections | Meaning |
|---|---:|---|
| **OK** | 23 | resolves cleanly |
| **FALLBACK** | 12 | resolves only by brittle extension-in-name heuristic |
| **BROKEN** | 56 | `from_output` matches no real filename → **handoff silently dropped** |
| **UNCERTAIN** | 46 | `.nf` missing / stub / scalar-JSON field the resolver can't address |

- **33 of 69 chains have ≥1 BROKEN connection.** Only **5** chains are fully OK; only **9** are fully clean (OK/FALLBACK).
- **Root cause (systemic, not incidental):** chain `connections` were authored with *semantic* labels (`de_results`, `normalized_sce`, `cluster_assignments`), but the runtime resolver only does **filename substring / extension matching**, and — critically — the `_EXT_TO_PARAM` fallback is gated to the `elif idx>0` branch and **does not run for any chain that declares connections** (58 of 69). When the semantic label ≠ the real filename, the handoff is dropped with only a `handoff_warning` (`20261005_CHAIN_CONNECTION_AUDIT.md:63-65, 533-542`).

So the machinery that *does* exist — pre-defined sequential chaining — is itself fragile: nearly half the declared data handoffs don't resolve. This is the honest reliability floor for "chain pre-defined pipelines."

---

## 4. The peptide example specifically — bespoke research code, not a catalog composition

**None of the three tools in the screenshot exist in the product.** Searching `backend/database/galaxy_ai_tools.db` and the entire backend/frontend tree for `PepFuNN`, `CPMP`, `Peptide-Tools`, `peptide descriptor`, `permeability` returns: **no code hits at all**, and only **3** workflows with "peptide" in the name (`msnid_peptide_modification_mapping`, `daglogo_fasta_peptide_analysis`, `cyclic_peptide_design`) plus **2** "permeability" workflows. The named property-prediction toolset (PepFuNN / Peptide-Tools / CPMP-MAT) is simply **not in the catalog the chat composer routes over**.

**The multi-tool-run-plus-rank capability lives in a separate, bespoke research track.** The "run property tools → multi-objective select → shortlist" pattern is implemented as standalone scripts under `research/guangzhou_all_atom/` + `drug_discovery/`, described in `docs/20260925_PEPTIDE_EXECUTION_PLAN.md`:
- **Track A1** "verify layer": `permeability_predictor.py` (EnsembleCycPerm ΔPSA3D), `physics_verify.sh`, MM-GBSA scripts, `score_generation.py` — wrap these into one `verify(peptide) → {affinity, ΔG, permeability, SA, safety}`.
- **Track A2** "Multi-objective selection (MPO/EHVI)": `multi_property_selection.py`, `perm3_select.sh`, `drug_discovery/bayesian_optimizer.py` (GP-Pareto EHVI) — *"given a generated pool, returns a Pareto-optimal shortlist."*

That is exactly the fan-out→rank→shortlist shape of the screenshot — but it is **hand-built research tooling**, run outside the chat composer/chain executor. The **rank-sum aggregation is bespoke** (a research selection script), **not a general chain capability** any user request would compose automatically. The architectural worry is therefore well-founded: the demo was **special-cased**, not produced by a general decomposition engine.

---

## 5. Where BioMate actually sits, and what's missing

**Spectrum placement: (b), reaching toward (c) only in prototype/eval form.**
- **(a) literal single-workflow routing** — this is the *default* live behavior (§1): one request → one `best_match` workflow, or one newly-generated `.nf`.
- **(b) chain pre-defined pipelines, not compose dynamically** — this is the *ceiling* of what ships: 69 hand-authored sequential chains, **41% of whose connections are broken** (§3). Strictly sequential; no fan-out, no aggregate, no select (§2).
- **(c) genuine dynamic decomposition + aggregation** — exists **only** as (i) the `chain_composer` prototype wired to tests, outputting linear 2-5-step chains with no parallel/aggregate nodes, and (ii) the v3 removal/reconstruction **eval** (`docs/20260919_V3_PLAN_OUT_OF_CATALOG_COMPOSITION.md`). It is not on the live path and cannot express the example's shape.

**What specifically is missing for the "easy but needs mature decomposition" class:**
1. **A category→tool-set expansion primitive** — resolve "all peptide-property tools" into a concrete, validated set. Does not exist.
2. **A parallel fan-out executor** — run a set of tools concurrently on one input inside a single plan. The executor is sequential-only; `_run_chain` is a `for` loop; "Full parallel dispatch (LangGraph + Celery)" is named as unbuilt Phase 1 (`ai_assistant.py:726`).
3. **A general aggregation/reduce + ranking + selection node type** (rank-sum / Pareto / top-k). Only a file-collector endpoint exists.
4. **A reliable handoff contract** — the current substring resolver drops 41% of declared connections; even sequential composition isn't trustworthy (`20261005_CHAIN_CONNECTION_AUDIT.md`).
5. **Wiring the compositional engine to the live path** — `chain_composer.compose_chain` is test-only.
6. **Prior-run/share-link input recovery** — recover the outputs of a named prior run as inputs; only accession resolution exists today.

**Is the fix in the LLM, the harness/composer, or both? → Primarily the HARNESS/COMPOSER.** The evidence says the LLM is *not* the binding constraint: on the v3 removal eval a frontier model already decomposes correctly — **`composed_rate 1.00`** (always builds a multi-step plan instead of forcing one workflow) and **`validity_rate 1.00`** (names only real, available blocks, no hallucination); its only weakness is **reconstruction fidelity `mean_step_coverage 0.54`**, which v3 training targets (`20260919_V3_PLAN_OUT_OF_CATALOG_COMPOSITION.md:592-612`). The model can already *plan* the fan-out→rank→select; what's absent is the **substrate to execute it**: the set-expansion primitive, the parallel executor, the aggregate/select node, and a non-fragile handoff contract. So the LLM piece (plan-fidelity training) is a secondary, already-in-progress improvement, while the **harness/composer/executor is the primary, load-bearing gap**.

---

## Appendix — evidence index (file:line)

- Routing picks one `best_match`: `backend/lib/galaxy/ai/ai_assistant.py:4940, 4997`
- Single-workflow generative fallback: `backend/lib/galaxy/ai/nextflow_composer.py:1-20`
- Multi-intent = split distinct asks, not set-expansion: `frontend/server/galaxy-assistant.ts:3790-3795, 3971`
- Compositional engine is test-only; linear schema, 2-5 steps, no parallel/aggregate: `backend/lib/galaxy/ai/chain_composer/composer.py:571-588`; callers only in `backend/tests/test_chain_composer.py`
- Sequential chain executor: `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py:465-479`
- Connection handoff = single-predecessor substring match: `workflow_chain.py:251-299`
- "Aggregate outputs" is a file collector: `workflow_chain.py:1341`
- **Task graph discarded; parallel dispatch unbuilt:** `backend/lib/galaxy/ai/task_decomposer.py:23-134, 206-266` (templates + LLM decompose) → `backend/lib/galaxy/ai/ai_assistant.py:724-728` (fallback to single-task)
- No "parallel" anywhere in composer/planner/executor: `grep -niE parallel` → 0 hits across those files
- DAG fork/join explicitly out of scope: `docs/20260723_FLEXIBLE_CHAIN_EXECUTION_DESIGN.md:832-834`
- Chain reliability 56/137 BROKEN, 33/69 chains affected: `docs/20261005_CHAIN_CONNECTION_AUDIT.md:76-88, 533-542`
- Peptide tools absent from catalog (DB query): only `cyclic_peptide_design`, `daglogo_fasta_peptide_analysis`, `msnid_peptide_modification_mapping` + 2 permeability; zero PepFuNN/CPMP/Peptide-Tools code hits
- Bespoke multi-property selection + rank lives in research track: `docs/20260925_PEPTIDE_EXECUTION_PLAN.md` Track A1/A2 (`multi_property_selection.py`, `bayesian_optimizer.py`, `permeability_predictor.py`)
- LLM already decomposes (not the bottleneck): `docs/20260919_V3_PLAN_OUT_OF_CATALOG_COMPOSITION.md:592-612`
