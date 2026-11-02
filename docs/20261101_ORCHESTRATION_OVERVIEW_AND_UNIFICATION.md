# BioMate structure: one model for workflows, chains, search and campaigns

Date: 2026-11-01. Code-read audit; extends `20261005_AGENT_ORCHESTRATION_AND_PARALLELISM.md` and `20260601_CHAIN_FRAMEWORK_AUDIT_AND_FIX.md`.
Problem (from the user): search must not be separated from the rest of task orchestration; the structure should be unified.

## 1. What already exists (and is the right skeleton)
| Concept | Code | State |
|---|---|---|
| **Workflow** (the unit of execution; Nextflow on AWS Batch) | catalogue `galaxy_ai_tools.db`, `nextflow_executor.py`, typed ports (input_types / output_types) | Live |
| **Chain** (DAG of workflows; each step's outputs wired into the next; `depends_on`, `max_parallel`, approve-each-step mode) | `POST /api/workflows/chain`, `galaxy.chain.dag.validate_plan`, curated chains in the DB (e.g. `drug_discovery_screening`: ADMET -> docking -> binding_affinity) | Live |
| **Chain planning** | curated lookup, `chain_planner.py` (typed-port BFS, no LLM), `task_decomposer.py` + `decomposed_dag.py` (LLM tasks -> DAG), `chain_composer/` (shadow only) | Partly live |
| **Domain workflow patterns** (phases per domain) | `domain_workflow_patterns.py`, `bioc_chain_templates.py`, `cryoem_chain_templates.py` | Live |
| **Evidence search** | `federated_query.py`, `research_agent.py`, `target_id/orchestrator.py`, `corpus_fs/` | Live, each with its own fan-out and provenance |
| **Pattern router** (SINGLE / PIPELINE / PARALLEL_FANOUT) | `pattern_router.py` | Off; sees only workflow generation |
| **Campaign** (drug-discovery DMTA loop for one compound series) | `drug_discovery/bayesian_optimizer.py`, `/api/drug-discovery/{campaign_id}/...` | Live, standalone |

The pieces are separate because search, target-ID and the campaign are not steps in a chain, and the router cannot plan across them.

## 2. Unified model: three layers
1. **Step.** Two kinds with the same interface (typed inputs and outputs, provenance, honest status):
   - *workflow step*: a Nextflow workflow (exists);
   - *capability step*: an in-process call: `search_literature`, `search_corpus` / `corpus_map` (per-document reading), `identify_targets`, `bo_propose`, `analyze_results`, `review` (reviewer gate).
2. **Plan = a chain DAG.** The existing chain format (`depends_on`, `max_parallel`) is extended so a node may be a capability step. The pattern names are only the *shape* of the DAG, not separate engines:
   - SINGLE: one node; PIPELINE: linear `depends_on`; PARALLEL_FANOUT: a `map` node that expands to N independent items with one `reduce` node after it (`map_reduce.py`); a reviewer node gates fan-out output.
   - Domain workflow patterns and chain templates are plan *templates* that pre-fill the DAG for a domain.
   - Specialists are context profiles attached to a step (domain instructions, tools, rules); they are not a pattern.
3. **Loop.** A controller that re-instantiates a plan template each round with persisted state (`RunStateStore`) and a gate (lab data arrives, human approves). A campaign is exactly this: per round the plan is `bo_propose -> CRO order export -> [wait for assay data] -> ingest assay -> retrain models`, and the earlier screening chain (ADMET -> docking -> ...) is a normal chain feeding the first round. The same wrapper serves any iterative task (e.g. repeated literature mining with a stopping rule).

**Planner.** One planner (extending `chain_planner` + `decomposed_dag`, with the router's single-vs-multi rule: default SINGLE when the measured single-agent baseline is high; fan out only for independent items or low-baseline domains) turns a request into a plan over both step kinds. Example: `search_corpus (find trials) -> corpus_map (read each trial) -> review -> identify_targets -> [workflow chain: ADMET -> docking]`.

**Shared primitives (reuse, no new ones):** `map_reduce` is the only fan-out; `RunStateStore` holds state; every claim carries provenance and is checked against stored text (`corpus_fs/llm_map.verify_evidence`, `citation_check`, target-ID `evidence_links`); a claim without verified evidence is returned `unsupported`, never as an answer.

**Target-ID is not a separate engine.** It is a plan template: parallel channel steps (Open Targets, STRING, pathway, hospital tables, LLM-reasoned; later a trial-corpus reader, the switch-like prior, Paperclip) -> the arbiter as the *reduce* node -> optional `validation_plan` chain. Each channel already has the `Channel.run` contract, so migration = register channels as capability steps and replace its private fan-out with `map_reduce`. The arbiter (harmonic sum, tiers, honest-framing rules) stays as target-ID's domain reduce function. Results feed any later step (e.g. screening, then a campaign).

## Human gates (a property of the step, for every chain and loop)
Each step declares `gate`: `none`, `review` (does not block; edits feed the next step) or `approve` (blocks until the person decides). Defaults by step class:

| Step class | Default | Examples |
|---|---|---|
| Mechanical, reversible, cheap | none | search, read, standard analysis, QC checks |
| Scientific choice | approve | which target, gap or design; accepting assumptions |
| Spend or compute above a threshold | approve, estimate shown first | long Batch runs, large LLM fan-outs |
| Outward-facing or irreversible | approve, always | CRO orders, lab synthesis, sending results to a partner |
| Result that changes the plan | approve | failed QC gate, weak pilot, a model that cannot discriminate |
| Output that leaves as the person's work | review | reports, IND sections, regulatory text |

Every gate shows its evidence (citations, counts, claim status). Loops declare a stopping rule and an approval cadence (e.g. approve every round early, only on a failed gate later).
Drug-development applications: screening chain (ADMET -> docking -> binding): approve target and compound set at the start, review a blocked QC gate, approve the shortlist before it enters a campaign. Campaign round: approve the proposed batch before the CRO order export; approve before anything is synthesized; review returned assay data (outliers) before retraining; approve continue / stop / change objective at round end.
Exists today: chain approve-each-step mode, "Confirm & Run" / "Fix now" parameter gates, QC gates, the campaign's natural handoffs (CRO order, assay ingest, LIMS poll). Missing: one declared `gate` field, the defaults above, review screens, the cost estimate before approval. The `gate` field is added to the step interface in slice S3.

**Out of scope for this layer:** the run-level auto-loop (not offered in the product now); the dormant `agent_orchestrator` (legacy; its specialist advice becomes context profiles).

## 3. Build order (each slice flag-gated and testable)
1. Step interface and registry; register the existing capabilities (no behaviour change).
2. Extend chain DAG validation and execution to accept capability steps; keep `validate_plan` guarantees (acyclic, backward `depends_on`).
3. Corpus capability end to end (code written, tests pending): ClinicalTrials.gov converter, `corpus_map` LLM worker with quote check and reviewer, `search_corpus`; then PubMed Central open-access papers.
4. Planner: let `decomposed_dag`/`chain_planner` emit capability steps; add the single-vs-fan-out rule.
5. Loop wrapper; re-express the campaign on it without changing its APIs.
6. `orchestrate` chat tool (off by default); evaluate against the current single-tool path on a fixed task set.

## 4. Added this session toward it
`paperclip_client` (optional hosted source), `corpus_fs/ingest_ctgov.py`, `corpus_fs/llm_map.py`, the 609,551-study ClinicalTrials.gov mirror, and the switch-like prior test as the first scoreable task. Slices 1, 2 and 4-6 are not built.
