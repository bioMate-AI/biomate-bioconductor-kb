# Reuse strategy for BioMate's local agent harness

Date: 2026-10-09. Official upstream documentation inspected; no dependency installed, code vendored or upstream harness benchmarked in this assessment.

## Recommendation

Follow-up: [pinned source review and adapter boundary](20261009_HARNESS_ADAPTER_SOURCE_REVIEW.md) records exact upstream revisions, the Hermes/Python compatibility constraint, existing BioMate transport tests and the proposed tool interface.

Adopt a reuse-first implementation gate before expanding custom orchestration. Evaluate an existing agent runtime and portable skills against BioMate's current execution APIs. Preserve BioMate's scientific tool catalog, Nextflow execution, run ownership, artifacts and report interfaces. Choose one runtime owner for the agent loop; avoid layering several competing planners and session stores.

The previous plan emphasized repairs to BioMate's contracts. Those repairs remain necessary, but it should not imply that we must build all agent infrastructure ourselves. External harnesses can supply substantial generic machinery; the product integration and scientific correctness still require measured acceptance.

## Verified upstream candidates

| Source | Documented reusable pieces | Proposed BioMate use |
|---|---|---|
| [Hermes Agent](https://github.com/NousResearch/hermes-agent) and [architecture](https://hermes-agent.nousresearch.com/docs/developer-guide/architecture/) | Configurable model endpoints; prompt assembly, tool registry, context compression, session persistence, skills and training trajectories | First candidate for a bounded local-model integration experiment. Reuse relevant runtime facilities behind BioMate adapters; compare integration effort before adopting. |
| [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) and [architecture](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/architecture.md) | Separate session, system-prompt, tool, agent and model-adapter modules; event-based tool execution and cancellation | Alternative runtime candidate, especially relevant to the TypeScript server. Inspect package dependencies and integration boundaries before extraction or embedding. Upstream labels it developer preview with breaking changes. |
| [Anthropic workflow patterns](https://www.anthropic.com/engineering/building-effective-agents) | Chaining, routing, parallelization, orchestrator-workers and evaluator-optimizer patterns | Reuse the decision rules as BioMate planning guidance, with executable validators at step boundaries. These are design patterns, not evidence that our workflow scheduler supports them. |
| [Anthropic long-running harness guidance](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) | Initialization, incremental work and explicit handoff artifacts across sessions | Adapt to versioned request plans, completion criteria and durable execution/evidence summaries. Conversation compaction must not become the authoritative job ledger. |
| [Agent Skills specification](https://agentskills.io/specification) and [Anthropic public skills](https://github.com/anthropics/skills) | Portable instruction packages with scripts/references; task-specific procedural guidance | Adopt the format for BioMate procedures, retrieval rules and report requirements. Load only relevant material for each stage. |

Hermes and DeepSeek repositories identify their main licenses as MIT. Anthropic's skills repository distinguishes many Apache-2.0 examples from source-available document skills. Record the exact upstream revision, file license and dependencies before copying any implementation. Do not assume all public Claude materials or the Claude Code runtime are open-source or interchangeable with a local-model runtime.

## What to reuse versus retain

**Reuse candidates:** model/tool loop, provider adapters, skill discovery/loading, prompt composition, context management, structured error handling, event hooks and trajectory export. Upstream documentation establishes availability, not compatibility with our particular local model or deployment.

**Retain and connect:** BioMate catalog/search, workflow schemas, Nextflow submission/status/reconciliation, run/artifact ownership, scientific parsers, existing findings/report/export facilities. A generic agent's session persistence does not establish idempotent recovery of scientific jobs; test that through the existing executor.

**BioMate-specific additions:** exact case coverage, biological identity and typed inputs, scientific comparability, ranking eligibility, partial-result semantics, evidence-backed recommendations and the user-endorsed response structure. Prompts guide these behaviors; code must enforce checkable invariants.

## Initial BioMate skill pack to develop

These are proposed application skills, not installed skills in this coding session:

| Skill | Required procedure and output |
|---|---|
| Interpret and scope | Recover context, distinguish review from execution, resolve entities, identify only material missing information |
| Recover prior artifacts | Resolve authorized run references; preserve identities, original scores and provenance |
| Expand applicable tools | Exhaust declared catalog scope, check compatibility, record exclusions and aliases |
| Plan scientific execution | Select supported sequence/fan-out/join patterns; produce stable cases, nodes and typed bindings |
| Compare and prioritize | Apply declared deterministic metrics, missingness and ranking policy; never invent numerical results |
| Report scientific results | Input summary, tools/coverage table, integrated results, recommendations with reasons, full artifacts and limitations |
| Recover failed work | Inspect actual errors, classify recoverable failures, preserve successful work and avoid duplicate submissions |

Each skill should carry applicability, prerequisites, expected artifacts, completion checks and concise examples. Link scripts for deterministic operations instead of asking the LLM to calculate rankings or validate graph completeness in prose. Reuse existing BioMate pattern-library content and corrected execution logs when authoring the procedures.

For the peptide example, the relevant skills compose into prior-input recovery → tool expansion → preparation → independent predictions → validated join/rank → shortlist/report. This provides reusable guidance for a common task without hard-coding the screenshot's tool names or winners.

## Bounded adoption experiment

1. **Inventory existing integration points first.** Identify the actual model-call interface, catalog API, execution receipts, status/artifact APIs and report input. Include the separate BioMate orchestration branch in the comparison so existing work is not duplicated.
2. **Inspect and pin candidate source.** Start with Hermes; inspect DeepSeek as the alternative. Record revision/license, dependency/runtime requirements, local endpoint support, cancellation behavior and observable events. This assessment has not yet selected exact versions or verified package-level reuse.
3. **Expose a small typed BioMate tool surface.** Catalog search/list, prior-artifact lookup, plan validation, existing workflow submission/status/artifact retrieval and validated reduction. All calls retain user, request, case and run identity. Avoid routing scientific execution through untracked shell commands.
4. **Exercise one candidate through the same interface.** Use the local model and frozen catalog/evidence fixtures. First test interpretation and plan/tool calls offline; then the existing small CPU comparison through the real application path. Do not replace the product before the adapter passes.
5. **Compare against the existing runtime.** Measure complete-task success, case/edge loss, invalid calls, recovery, grounded report quality, latency and model calls. Require the three user cases and failure fixtures. Mocks validate contracts only; real execution is a separate gate.
6. **Adopt only demonstrated improvements.** If one full runtime integrates cleanly, use it behind the adapter. If integration cost is higher than reusing individual modules/patterns, retain the existing loop and selectively port proven pieces. Do not adopt Hermes and DeepSeek as nested runtime owners.

The existing nine failing production-boundary probes remain mandatory repair gates regardless of runtime choice. An imported harness cannot restore metadata after our browser serializer discards it.

## Consequences for local-model training

Measure harness and model improvements separately with a controlled matrix:

| Arm | Model | Runtime/procedures | Question |
|---|---|---|---|
| A | Current local model | Existing BioMate baseline | What works today? |
| B | Same local model | Candidate runtime, corrected adapters and skills | How much does the integration package improve results? |
| C | Same local model | Same corrected runtime with skills ablated | What improvement is attributable to procedures? |
| D | Fine-tuned candidate | Same corrected runtime and skills | What extra improvement comes from training? |

Keep catalog, evidence, tool versions and budgets fixed. Where practical, ablate adapter repairs separately from runtime replacement; arm B otherwise measures their combined effect, not pure framework benefit. A stronger reference model can diagnose residual reasoning gaps on authorized development data, but local acceptance must execute entirely on the on-premise model path.

Skills improve instructions and context without changing weights. Fine-tuning should target remaining measured weaknesses: selecting applicable skills, constructing valid plans, interpreting scientific evidence, recovering errors and writing the expected report. Export verified trajectories for this purpose. Repeated failure corrections can become candidate skill updates; promote them only after regression evaluation, with versions and rollback. Do not let an agent's own success claim serve as its training label.

## Plan update

Insert this reuse experiment into Stages 0–1 of the [capability and implementation plan](20261009_ORCHESTRATION_CAPABILITY_AUDIT_AND_PLAN.md), before committing to new custom agent-loop infrastructure. Continue correcting product boundaries and collecting data in parallel. The decision criterion is working BioMate request-to-report behavior with the local model, not framework popularity or an upstream coding benchmark.
