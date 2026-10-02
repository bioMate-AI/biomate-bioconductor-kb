# Task Flows: What Knowledge/DB Supports, What It Can't

**Date:** 2026-10-01
**Purpose:** for each BioMate task, a clear definition + information flow, marking exactly what is
supplied by existing **knowledge/DB/resolvers (the harness)** vs the **residual LLM judgment**.
**Thesis (confirmed):** most tasks are DB/knowledge-supported; the LLM's irreducible share is small.
Companion: [[20261001_LLM_HARNESS_TASK_SPLIT]], [[20261001_EXECUTION_GRADER_PLAN]].

---

## The supply side — what the harness already has

| Asset | Contents | Serves |
|-------|----------|--------|
| **Workflow DB** (`galaxy_ai_tools.db`, 4,200 wf) | name, description, domain, `tools_used`, `input_types`, `output_types`, `params_schema` (+`allowed_values`), `step_metadata`, `scientific_rationale` (when_to_use / do_not_use / **param_hints** / common_pitfalls), `hardware_requirements` | routing, tool-rec, prereq, params, decomposition, model/design choice |
| **Dense retrieval** | `UnifiedWorkflowSearch` / `VectorToolSearch` (BGE/MiniLM cosine ≥0.55) | routing & tool candidate generation |
| **Resolvers** | PubChem/ChEMBL/ChEBI/KEGG (`federated_query`, name→SMILES/props), `resolve_accession` (GEO/SRA→modality+metadata), gene/protein/pathway | turning names/accessions into facts |
| **Literature/RAG** | `search_literature` (PubMed/Semantic Scholar) + corpus | knowledge_recall, scientific_qa |
| **Rules engine** | unit conversion (ns→n_steps), boolean flags (single-end→true), alias norm (human→GRCh38, dUTP→reverse) | deterministic param fill |
| **Schema guardrail** | `params_schema.allowed_values` | param validation |
| **Execution + verifiers** | AWS Batch run, QC gates (`qc_metrics.json`), programmatic output checks, autofix rerun | workflow_generation/autofix verification, the execution grader |
| **Failure knowledge** | error categories + suggested_action (`failure.category`/`fix_strategy`) | log_diagnosis, autofix |

**Verdict legend:** 🟢 DB/knowledge-supported (LLM residual none/thin) · 🟡 thin judgment over
retrieved context · 🔴 irreducible LLM judgment (no DB answer).

---

## The 17 tasks

### 🟢 1. workflow_routing
- **Def:** NL request → the right workflow.
- **Flow:** request → **[DB: dense retrieval → short candidate list]** → [LLM: re-rank near-ties only] → **[harness: grounded_pick → catalog id]** → id.
- **DB supports:** candidate generation + the answer is always a real catalog id. (Base model 0.94.)
- **Can't:** nothing material — LLM only breaks near-ties.

### 🟢 2. tool_recommendation
- **Def:** task → appropriate tools/methods.
- **Flow:** task → **[DB: `tools_used` of the matched workflow(s) + VectorToolSearch]** → [LLM: phrase] → list.
- **DB supports:** the tools are a stored field. **Can't:** nothing material.

### 🟢 3. dataset_prerequisite_check
- **Def:** what input data a workflow needs.
- **Flow:** workflow → **[DB: `input_types`]** → list.
- **DB supports:** it's a stored field. **Can't:** nothing (pure lookup).

### 🟢 4. parameter_extraction
- **Def:** context → concrete parameter values.
- **Flow:** request + **[DB: `params_schema` + `param_hints`]** → **[rules: unit/flag/alias conversion]** → [LLM: only free-text/ambiguous residue] → **[harness: validate vs `allowed_values`]** → params.
- **DB supports:** schema, defaults, hints, validation; rules do conversions. **Resolvers** supply fact-values (name→SMILES, accession→genome). **Can't (thin 🟡):** inferring an unstated value from prose (e.g. "mouse, paired, dUTP" → strandedness=reverse) when not rule-coverable.

### 🟢 5. knowledge_recall
- **Def:** biomedical fact question.
- **Flow:** question → **[RAG: literature/corpus retrieval]** → [LLM: read + answer, cite-or-abstain] → answer.
- **DB supports:** the fact comes from retrieval (never weights — CPT no-op confirmed). **Can't:** only reasoning over the retrieved passage.

### 🟢 6. scientific_qa
- Same as knowledge_recall: **[RAG]** → [LLM read] → answer. DB/literature-supported.

### 🟢 7. model_selection
- **Def:** pick the method/model for a task (e.g. DESeq2 vs edgeR).
- **Flow:** task + sample traits → **[DB: `scientific_rationale.when_to_use` / `do_not_use_when`]** → [LLM: match traits to the stored guidance] → choice.
- **DB supports:** the selection rules are stored per workflow (verified: "use edgeR for n<3", etc.). **Can't (thin 🟡):** mapping an unusual design to the stored rules.

### 🟢 8. design_constraint
- **Def:** respect constraints (allowed values, licences, hardware).
- **Flow:** request → **[DB: `allowed_values`, `hardware_requirements`, licence tags, common_pitfalls]** → [LLM: apply] → constrained config.
- **DB supports:** constraints are stored + validated. **Can't:** little.

### 🟢 9. dataset/accession prerequisite (resolve) & 10. log_diagnosis
- **log_diagnosis flow:** failure → **[DB: error-category map + `failure.category`/`suggested_action`]** (verified: runs carry `fix_strategy`) → [LLM: match novel logs] → diagnosis.
- **DB supports:** known-error patterns + suggested actions. **Can't (thin 🟡):** genuinely novel errors.

### 🟢 11. autofix_repair
- **Def:** fix a failed step and re-run.
- **Flow:** failure → **[DB: error patterns]** → [LLM: propose fix] → **[harness VERIFIER: rerun the step → pass? (pass@k)]** → fixed or escalate.
- **DB/verifier supports:** the pipeline *is* the verifier (cheap pass@k). **Can't:** nothing material — a wrong fix is caught by rerun.

### 🔴 12. task_decomposition  (CORRECTED — intent interpretation, not step lookup)
- **Def (correct):** the user writes a **long free-text message containing several distinct tasks** →
  **segment it into discrete, individually-executable tasks** (then each is routed/executed normally).
- **Flow:** long user text → [**LLM: parse intent, find task boundaries, split into N asks (judgment)**]
  → per-task **[harness: route → execute]** → ordered task list.
- **DB supports:** the capability catalog helps *map* each segment to a known task type; but the core —
  segmenting the user's prose into intents — has **no DB answer** (the DB can't tell you how a user's
  sentence splits). It is upstream **intent interpretation**, sibling to clarification_request.
- **Prior error:** I had defined this as "enumerate workflow steps" with gold = `step_metadata`. That is
  a DIFFERENT (DB-supported) capability — *workflow_step_enumeration* (🟢 below) — NOT task_decomposition.
  The db_grounded decomposition seeds (gold=`step_metadata`) are therefore mislabeled.

### 🟢 12b. workflow_step_enumeration (the thing I mislabeled as decomposition)
- **Def:** given a *chosen workflow*, list its ordered steps. **Flow:** workflow → **[DB: `step_metadata`]** → steps.
- **DB supports:** stored field (pure lookup). This is real and DB-supported — just not "task_decomposition".

### 🟡 13. multi_workflow_chaining
- **Def:** chain workflows so outputs feed inputs.
- **Flow:** goal → **[DB: per-workflow `output_types`/`input_types` → type-match the handoff]** → [LLM: order the chain, resolve mismatches] → **[harness: validate wiring]** → chain.
- **DB supports:** the I/O types that make wiring checkable. **Can't (🟡):** choosing the chain shape for a novel multi-step goal.

### 🟡 14. lane_arbitration
- **Def:** resolve disagreement among the 3 routing classifiers.
- **Flow:** 3 votes + scores → **[rules: confidence thresholds/priors]** → [LLM: tie-break the genuinely ambiguous] → lane.
- **DB/rules support:** most cases resolve by threshold. **Can't (🟡):** the genuinely ambiguous residue.

### 🔴 15. workflow_generation
- **Def:** compose a *new* runnable workflow from steps.
- **Flow:** goal → **[DB: candidate steps/tools + I/O types]** → [**LLM: compose + wire (judgment)**] → **[harness VERIFIER: does it run / output passes?]** → workflow.
- **DB supports:** the building blocks + a verifier. **Can't (🔴):** the composition itself is LLM judgment (floor is LLM-bound; verifier only rejects).

### 🔴 16. out_of_catalog_composition
- **Def:** nothing in the catalog fits → compose a plan from primitives or **abstain**.
- **Flow:** request → **[DB: retrieval returns NO adequate match]** → [**LLM: compose-or-abstain (judgment)**] → plan/abstain.
- **DB supports:** only confirms "no match." **Can't (🔴):** by definition there is nothing to retrieve; pure judgment. (Lowest score, 0.10.)

### 🔴 17. findings_interpretation / conclusion_drawing
- **Def:** turn result numbers into biological meaning.
- **Flow:** results (in context) + **[DB/RAG: domain priors, pathway DBs]** → [**LLM: interpret (judgment)**] → findings.
- **DB supports:** priors/pathways for grounding. **Can't (🔴):** the interpretation is novel to *this* result — no stored answer, **no cheap verifier** (so also not cheaply gradeable).

### 🔴 (adjacent) clarification_request
- **Def:** decide when the request is too ambiguous to proceed and what to ask.
- **Flow:** request → [**LLM: calibration judgment**] → ask or proceed.
- **Can't (🔴):** a calibration decision — no DB answer, no verifier.

---

## Tally

| Verdict | Count | Tasks |
|---------|------:|-------|
| 🟢 DB/knowledge-supported (residual none/thin) | **~11** | routing, tool_rec, dataset_prereq, parameter_extraction, knowledge_recall, scientific_qa, model_selection, design_constraint, log_diagnosis, autofix_repair, **workflow_step_enumeration** |
| 🟡 thin judgment over retrieved context | **~2** | multi_workflow_chaining, lane_arbitration |
| 🔴 irreducible LLM judgment (no DB answer, no cheap grader) | **~5** | **task_decomposition (intent-split)**, workflow_generation, out_of_catalog_composition, findings_interpretation, clarification_request |

**The 🔴 set clusters into two jobs, both genuinely the LLM's:**
- **Intent interpretation (upstream):** `task_decomposition` (split long user prose → discrete tasks),
  `clarification_request` (is it too ambiguous to proceed?), and the ambiguous slice of
  `lane_arbitration`. No DB answer — the model reads the *user*, not the catalog.
- **Generation/judgment (mid/down-stream):** `workflow_generation`, `out_of_catalog_composition`,
  `findings_interpretation`. The harness supplies building blocks/results; the LLM composes/interprets.
This two-cluster view is the real scope of the LLM: **read the user's intent, and reason/compose where
the catalog has no answer.** Everything else is harness-carried.

**So the user's thesis holds:** ~13 of 17 tasks are supported by existing knowledge/DB/resolvers +
rules + verifiers — the LLM's job there is phrasing or thin tie-breaking, model-invariant (cheapest/
on-prem model suffices). Only ~4 are irreducibly LLM-judgment, and those are exactly the ones with no
cheap execution grader. **Design implication:** push every fact/selection/validation into the
harness (retrieval, resolvers, rules, schema, verifiers); reserve the LLM for the 4 judgment tasks,
where — for on-prem — our own model carries them, and in cloud mode frontier can be escalated.

## Where today's harness has gaps to CLOSE (so "most" becomes "nearly all")
- **parameter_extraction (🟡→🟢):** widen the rules table + always run resolvers (name→SMILES,
  accession→genome/strandedness) before the LLM, so the LLM never guesses a fact-value.
- **model_selection/design_constraint (🟡→🟢):** ensure every workflow has populated
  `scientific_rationale.when_to_use/do_not_use_when` (tool enrichment gap, [[project_tool_enrichment_gap]]).
- **log_diagnosis (🟡→🟢):** grow the error-category → fix map from accumulated run failures.
- **multi_workflow_chaining (🟡):** a type-matcher over `input_types`/`output_types` can auto-wire
  most chains, leaving the LLM only the order.
