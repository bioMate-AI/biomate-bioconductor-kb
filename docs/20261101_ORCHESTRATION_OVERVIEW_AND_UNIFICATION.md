# BioMate orchestration: overview of what exists, and one layer for search, analysis, target-ID and execution

Date: 2026-11-01. Code-read audit (file references below); extends `20261005_AGENT_ORCHESTRATION_AND_PARALLELISM.md` and
`20261008_AGENT_PATTERNS_RESEARCH_AND_BIOMATE_INTEGRATION.md`. Problem statement (from the user): search must not be separated from the
other task orchestration. Today it is.

## 1. What exists: seven separate control loops
| # | Loop | Where | Chooses between | Live? |
|---|---|---|---|---|
| 1 | Chat tool loop | `frontend/server/galaxy-assistant.ts` (tools: run_code, read_file, query_domain_knowledge, list_history, search_literature, search_my_data, list_data_sources, search_workflows, request_new_tool, identify_targets, write_review) | The LLM picks one tool per turn; no plan, no parallel tools, no reviewer | Live |
| 2 | Workflow generation | `ai/ai_assistant.py` `generate_workflow_unified`, `UnifiedIntentRouter` | Catalogue search then assemble one workflow | Live |
| 3 | Pattern router | `ai/pattern_router.py`, hook at `ai/ai_assistant.py:~575` | SINGLE / MULTI_SPECIALIST / PIPELINE / PARALLEL_FANOUT, but only for workflow generation | Off (`BIOMATE_PATTERN_ROUTER_ENABLED`) |
| 4 | Multi-specialist orchestrator | `ai/agents/agent_orchestrator.py` | 1-3 domain specialists then assemble | Dormant (no caller) |
| 5 | Evidence search | `federated_query.py`, `research_agent.py`, `target_id/orchestrator.py` | Parallel I/O fan-out over sources / channels, arbiter | Live, but each has its own fan-out and its own provenance |
| 6 | Run-level loop | `nextflow_executor.py` autoloop, RunStateStore/CompletionPoller | Retry or remediate one run | Live |
| 7 | Campaign loop | `drug_discovery/bayesian_optimizer.py`, DBTL, portfolio scheduler spec | Next candidates per round | Live (one campaign, sequential) |

Consequences: a question that needs "search 100 trials, read each, rank targets, then propose a workflow" cannot be expressed. Search results never
feed a plan; fan-out exists three times with three behaviours; no loop has a reviewer gate; grounding checks exist only inside some of them.

## 2. Design: one task layer with shared primitives
**Capability registry.** Every ability is registered once with: name, input and output schema, cost class (cheap I/O / LLM / compute), whether it can
run per item in parallel, and its grounding guarantee. Initial members, all of which already exist as code:
search_literature, search_corpus (corpus_fs: ls/cat/grep/find), corpus_map (per-document LLM reading, this session), identify_targets,
search_workflows, generate_workflow, run_workflow, analyze_results, run_code, review (reviewer gate).

**One planner.** The pattern router becomes task-level, not workflow-generation-level. Input: the user request plus the capability registry.
Output: a plan made of SINGLE, PIPELINE (dependent stages), PARALLEL_FANOUT (independent items) and MULTI_SPECIALIST nodes. The NMI rule stays:
default to SINGLE when the measured single-agent baseline for that task type is already high; fan out only for independent items or low-baseline domains.
Example plan: search_corpus (find trials) -> corpus_map (read each) -> reviewer gate -> identify_targets (consume the extracted rows) -> generate_workflow.

**Shared primitives (already built, to be reused by every capability):**
- `map_reduce.py` is the only fan-out (bounded, ordered, fault-isolating).
- `RunStateStore` is the only place long-running state lives (cross-worker, survives restarts).
- Grounding: every capability returns items that carry provenance, and a verifier checks claims against stored text (`corpus_fs/llm_map.verify_evidence`,
  `citation_check`, target-ID `evidence_links`). A claim without verified evidence is returned as `unsupported`, never as an answer.
- Reviewer gate: an independent second call that sees only verified evidence (`llm_map.make_llm_reviewer`); required on fan-out outputs.
- Provenance and honest status: ok / partial / unverified / refused, in one envelope.

**Chat integration.** Keep the LLM tool loop (loop 1) but add one tool, `orchestrate(task)`, that runs the planner and returns the envelope; the individual
tools stay for simple turns. Planner off means today's behaviour.

## 3. Build order (each slice testable and flag-gated)
1. Capability registry + envelope, registering the existing abilities (no behaviour change). 
2. Make `pattern_router` accept a capability plan, not only a workflow query; reuse `map_reduce`.
3. Corpus capability end to end: ClinicalTrials.gov into corpus_fs, `corpus_map` with the LLM worker, quote check and reviewer (code written; tests next), then
   PubMed Central open-access papers.
4. `orchestrate` chat tool, off by default; evaluate against the single-agent path on a fixed task set (switch-like prior is one; trial-outcome extraction is another).
5. Retire duplicates: federated_query and target-ID fan-outs call `map_reduce`.

## 4. What this session already added toward it
`paperclip_client` (optional hosted source), `corpus_fs/ingest_ctgov.py`, `corpus_fs/llm_map.py` (worker, quote verification, reviewer, reduce, synthesis
with unknown-id removal), the full ClinicalTrials.gov mirror (609,551 studies), and the switch-like prior test as the first scoreable task.
None of the planner work (slices 1, 2, 4) is built yet.
