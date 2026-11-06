# BioMate live-chat flexibility: audit + design to make reason-with-tools first-class

Date: 2026-10-21
Premise (user): "BioMate has the full set of evidence resources; given a novel need it should know what
to do. We can't predefine every need. Is it really so inflexible?" — Answer: it has the resources and the
agent loop, but the live chat is architected as a **workflow ROUTER that strips its own tools when it emits
a card**, with ~15 regex patches hand-routing specific phrasings, the rich evidence tools locked out of the
loop, and all the real agentic machinery flag-dark. The inflexibility is architectural, and the fix is small.

## Diagnosis (live path = `frontend/server/galaxy-assistant.ts`; backend reached only via the single
`/api/ai_assistant/generate_workflow` endpoint → `nextflow_composer`)

1. **Intent is a router, not a tool-chooser.** `analyzeIntent()` (:5851) = one Gemini-Flash LLM call →
   open-vocab `type` → `inferActionsFromType()` (:1454) → static flag table; `workflow_generation` is a
   DEFAULT DESTINATION that sets `needsWorkflowGeneration:true` (:1457). run_code-vs-pipeline is a boolean
   the router pre-decides, not a choice the agent makes.
2. **THE GATE ties tool availability to workflow production** — `:8760`
   `toolsEnabledThisTurn = (!useThinking && onToolEvent && !hasRunnableWorkflow)` (+ `:8766`, Gemini `:9156`).
   **Emitting a workflow card deletes ALL tools for the turn.**
3. **Fabrication is the structural failure mode of 1+2** (`:3514-3527`, `:8749`): a direct-compute need
   mis-classified as `workflow_generation` → card → gate strips `run_code` → the model, still told to
   compute, PRINTS a `<run_code>` block as prose and claims "executed in the sandbox" while nothing runs.
4. **~15 hardcoded named-workflow overrides** (`:4096-4400`, `:3639`, `:5716`, `:5742`) each force one card
   for one phrasing (`_isClusterProfilerQuery`, ADMET, codon, epitope, pocket, GWAS→eQTL, …) — the literal
   "predefine every need" surface; the counter-patch `_isDirectCodeExecutionQuery` (:3529) only rescues
   explicit "use run_code" asks.
5. **The rich evidence/exec tools are NOT in the loop.** Live `BIOMATE_TOOLS` (:84-240) = 7 thin tools
   (run_code, read_file, query_domain_knowledge, list_history, search_literature, search_my_data,
   list_data_sources[catalog-only]). `query_database`, `identify_targets`, `fetch_public_data`,
   `run_workflow`, `search_workflow`, OpenTargets live ONLY in the MCP server / REST — the in-loop model
   cannot compose them into a novel analysis.
6. **All real agentic machinery is flag-dark / zero live callers:** `pattern_router.py` (INERT by its own
   docstring), the multi-agent orchestrator (`generateWorkflowMultiAgent` has zero callers),
   `chain_composer`/`chain_planner` (shadow-telemetry only, `BIOMATE_COMPOSER_SHADOW`), `decomposed_dag`
   (flag-gated). Live path is hardwired single-pass `generate_workflow_unified → nextflow_composer`.

Net: center of gravity is "classify → emit a card"; the tool-using reason path is a fallback that has to be
specially protected (the Gemini→Claude reroutes `:2681`,`:8824` exist solely to keep a tool loop alive).

## Design — make reason-with-tools the DEFAULT; workflows a tool the agent chooses

The minimal change set (surgical, not a rewrite):

**P1 — Kill fabrication (highest value, lowest risk).** A tool is either really callable or clearly
unavailable — never "stripped while the prompt still asks the model to compute."
- Drop the `!hasRunnableWorkflow` term at `:8760` / `:9156` so a turn that also shows a workflow card keeps
  its tools (a card and a computation are not mutually exclusive).
- Add a hard integrity guard: if the model emits a `<run_code>` (or any tool) block and the tool is not
  actually executed, the response must surface "not executed" — it must be IMPOSSIBLE to render fabricated
  "executed in the sandbox" prose. (Guard alluded to at `:8823`; make it authoritative.)
- Keep the thinking-mode exclusion (`!useThinking`) — tool_use ∥ extended thinking is a real constraint.

**P2 — Put the evidence/exec tools IN the loop.** Register `query_database`, `identify_targets`,
`fetch_public_data`, `search_workflow`, `run_workflow` (already defined in `backend/lib/mcp/tools_manifest.json`)
into `BIOMATE_TOOLS` (:84) with real dispatch (proxy to the MCP/REST handlers, like `userMcpTools` at :8765).
Now the agent can compose OpenTargets + DB + run_code + a workflow launch in ONE reasoning loop — i.e. answer
a novel need (e.g. "assess ICB-response evidence") without a predefined module.

**P3 — Demote the router to a hint; workflows become `search_workflow`/`run_workflow` tool calls.** Turn
`analyzeIntent`/`inferActionsFromType` + the `:4096-4400` override block into an optional BIAS (a suggested
tool), not a gate that sets `needsWorkflowGeneration`. The agent decides compute-vs-pipeline by calling the
right tool. The ~15 regex patches then delete themselves (the agent routes by reasoning, not by phrasing).

Risk/test: this touches the live chat. Stage P1→P2→P3; each gated by the pre-sync checklist (tsc + vitest)
+ the `scripts/e2e_use_cases.sh` flow (ensure genuine pipeline requests STILL land a workflow card, and a
direct-compute request actually runs run_code and never fabricates). P3 is the biggest regression surface
(workflow-card routing is load-bearing for the UX) → behind a flag first, A/B on the e2e suite.

## Why this is also the publishable innovation
The defensible contribution was never "a single-cell LLM that beats PCA" (3 rigorous negatives this session).
It is the **flexible agentic multi-omic reasoning system**: given an arbitrary biomedical need it plans which
evidence resources + tools to call (literature, OpenTargets, DisGeNET, DB, run_code, workflows), runs them,
and reasons with provenance — predefined workflows demoted to one tool-choice, no fabrication. That is a real
systems contribution (agentic biomedical reasoning + honest execution), and it is what lets BioMate answer
needs nobody predefined. See [[project_composer_execution_bottleneck]], [[project_agent_patterns_research]],
[[project_agentic_tools_gemini]], [[project_data_source_fragmentation]].
