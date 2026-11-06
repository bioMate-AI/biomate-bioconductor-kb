# BioMate task interpretation, orchestration, execution and reporting

**Audit: 2026-10-09. Status: investigation and proposed implementation plan, not a release claim.**

## Decision

BioMate already contains many of the required components: intent splitting, pattern retrieval, a composer with explicit edges, sequential chain execution and recovery, asynchronous Nextflow execution, a narrow multi-method benchmark endpoint, per-run findings and reports, and a separate orchestration/retrieval branch. The immediate problem is inconsistent contracts and incomplete integration across those components. Another model-training run cannot repair dropped dependencies, lost task identities, or invalid rankings.

Use the existing components to deliver one continuous product path:

**Request → scoped scientific question → validated execution plan → durable child execution → validated evidence/metrics → coverage-aware report.**

Workflow patterns are relevant at interpretation time. They describe the dependency and aggregation structure of the requested work. Choosing how many LLM agents reason about that work is a separate decision. A single LLM can plan parallel scientific jobs; several specialist agents can collaborate on one sequential workflow.

The first client-trial scope should support sequential prerequisites, independent branches, joins, and explicit comparison/reduction. Conditional branches and bounded iteration need their own acceptance tests before being advertised. Do not silently flatten unsupported patterns.

## Evidence boundaries and corrections

The reviewed checkout is `/Users/kky/biomate-review`, branch `cursor/tutorial-live-recording-and-report-editing-4ea7`, HEAD `53d09e07c`. The separate orchestration worktree is `/Users/kky/biomate-orch`, branch `feat/orch-retrieval-s2-20261008`, HEAD `6f4da7a04`. Both contain shared work; this audit does not merge or reset either.

Distinguish five levels of evidence: **source exists; caller is connected; component executes; normal product flow executes; deployed product is verified**. This audit establishes the first three for selected components. It does not establish the final two for the complete complex-task path.

Corrections to earlier assessments:

- “BioMate has no fan-out” is too broad. A registered benchmark endpoint can submit several asynchronous child workflows. General arbitrary-tool fan-out through chat is not demonstrated.
- “The composer is linear only” is inaccurate at the schema level. Its output has explicit edges. Several consumers nevertheless assume an array or immediate predecessor, and first-class map/condition/reduce semantics are incomplete.
- “BioMate has no reporting” is incorrect. Per-run findings and methods-report jobs already exist. Request-wide, scientifically valid comparison reporting is the missing demonstrated integration.
- Passing the orchestration branch's isolated tests is not equivalent to successful live dispatch. The hook/result-type mismatch remains visible in source.
- Local commit `53d09e07c` is my earlier, premature DAG increment. It is **not preexisting BioMate capability, not pushed/deployed, and not an accepted implementation of this plan**. Its tests are useful evidence, but the design must be reconciled with the existing systems before adoption.

Earlier documents remain useful historical inputs: [execution substrate requirements](20261008_REQUIREMENT_COMPOSER_EXECUTION_SUBSTRATE.md), [flexibility audit](20261008_DECOMPOSITION_EXECUTION_FLEXIBILITY_AUDIT.md), [orchestration analysis](20261005_AGENT_ORCHESTRATION_AND_PARALLELISM.md), [S1/S2 validation](20261008_ORCHESTRATION_RETRIEVAL_S1_S2_VALIDATION.md), and [my provisional increment](20261009_COMPLEX_TASK_EXECUTION_TAKEOVER.md). This audit qualifies their broad capability claims; it does not claim to have revalidated every older failure count.

## Capability inventory

Paths below are relative to the review checkout unless explicitly marked **orch branch**. Line numbers describe the inspected snapshot and may move.

| Area | Existing capability and source | Verified limit / reuse decision |
|---|---|---|
| Frontend intent interpretation | `frontend/server/galaxy-assistant.ts`: intent dependency fields around 1479; request dispatch around 3839–3974; `processSequentialPipeline` 4997; `processMultiIntent` 5411 | Multiple intents and sequential routing exist. Parallel sub-intent planning is not proof of parallel scientific execution. Retain intent extraction, require a validated common plan. |
| Sequential planning | Same file: predecessor binding around 5301; same-path collapse 5318–5320 | A fallback constructs dependencies from array order. A same-path plan can collapse to one workflow with merged parameters. Require semantic coverage proof before collapsing tasks. |
| Chain composer | `backend/lib/galaxy/ai/chain_composer/composer.py`, prompt around 571 and parser around 610; `types.py` | Emits steps **and edges**, uses retrieved patterns and examples, and constrains generated plans to 2–5 steps. Reuse planning knowledge; the limit and graph semantics do not cover every request. |
| Pattern library | `chain_composer/pattern_loader.py`; `docs/20260608_CHAIN_PATTERN_LIBRARY_DRAFT.md` | Includes sequential, integration, consensus, iteration, QC branching and other patterns. Deprecated patterns are filtered by default. Comparative benchmarking was explicitly deprecated in June; the current user request requires reconsidering that product decision. |
| Composer integration | `backend/lib/galaxy/ai/ai_assistant.py` around 504 | Composer shadow mode is flag controlled, default off/log-only. Presence does not establish the live frontend path uses its graph. |
| Backend decomposer | `backend/lib/galaxy/ai/task_decomposer.py` 223–250, 306–312; `_handle_multi_task_generation` in `ai_assistant.py` | Prompt asks for dependencies and `parallel_with`; parsing retains dependencies but not `parallel_with`. Index validation lacks complete lower-bound/self/cycle checks. The multi-task handler can fall back to single-workflow generation. |
| Browser chain submission | `frontend/client/src/lib/chain-execution.ts`: types 12; builders 61 and 91; submit 104 | Current serializer drops DAG dependencies/dimensions and connection `context_params`. Parent coverage/concurrency is not carried. Directly reproduced. |
| Browser status / cards | `chain-pipeline-sync.ts` 5–43; `components/chat-message.tsx` around 962 | Status sync uses array position; blocked/submitting map to pending, parent partial maps to running. Additional workflows are independent review cards, not a demonstrated parent execution graph. |
| Nextflow and legacy chains | `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`; `workflow_chain.py` | Asynchronous execution, concurrency controls, output collection and recovery are real assets. Nextflow process parallelism is distinct from request-level branching. Reuse run tracking and reconciliation. |
| Narrow benchmark | `frontend/server/benchmark-orchestrator.ts`; registration `frontend/server/routes.ts` 12824–12883 | Registered multi-method clustering benchmark; explicit fixed method set. Child executions can overlap even though submission calls are awaited in a loop. No general category resolver or normal chat caller was found in the inspected client paths. |
| Pattern router (**orch branch**) | `backend/lib/galaxy/ai/pattern_router.py`, context 301, entry 318, dispatch 524 | Selects single, multi-specialist, pipeline, fan-out. Live dispatch only implements multi-specialist; other decisions fall through. Query text is not itself analyzed into shape by `_task_from_context`. |
| Agent hook (**orch branch**) | `ai_assistant.py` 557–591; `agents/agent_orchestrator.py` `OrchestrationResult` and `generate_workflow` | Hook consumes a dictionary; real orchestrator returns a dataclass. Context influences routing but is not forwarded by that hook into generation kwargs. Integrate actual types and dataset context before enabling. |
| Map/reduce (**orch branch**) | `backend/lib/galaxy/ai/map_reduce.py` | Bounded in-process workers, ordered successes, separately recorded failures. Useful for retrieval/evidence extraction. It is not a durable long-running workflow scheduler. Reducer receives successes, so expected coverage/errors must be supplied explicitly. |
| Evidence retrieval (**orch branch**) | `backend/lib/galaxy/ai/corpus_fs/map.py` 118–154 | Per-document evidence retains source/path/line provenance. Default reduction assembles extracts; `synthesis` remains `None`. Reuse as evidence substrate. |
| Existing reporting | `frontend/server/jobs/handlers/findings-analysis.ts`, `methods-report.ts`, `frontend/server/report-version.ts` | Asynchronous per-run findings and methods reports, caching/version support. Extend with a parent report tied to the complete plan and child artifacts. |

## Current gaps, ordered by impact

### G1. Task identity and meaning can be lost before execution — critical

The frontend, backend decomposer, composer, router, chain API and browser do not share one versioned plan contract. They use different dependency conventions and different assumptions about sequence. A valid graph at one boundary can become an array at another.

Same workflow path is not a task identity. Two compounds using one docking workflow are two scientific cases. The sequential same-path collapse must distinguish a workflow that genuinely covers all requested work from a merge that overwrites parameters. My earlier non-sequential dedup change does not fix that separate path.

Consequences: omitted cases, incorrect input reuse, fabricated sequencing, or a result that answers only part of the question while appearing complete.

### G2. Pattern selection does not consistently reach a runnable plan — critical

The orchestration branch's router defaults shape to `single` unless context supplies it. It can choose `PIPELINE` or `PARALLEL_FANOUT`, but its live dispatch only acts on `MULTI_SPECIALIST`. The latter's result then encounters a dataclass/dictionary mismatch in the assistant hook. Dataset context is not forwarded through that dispatch seam.

The default capability baseline is a static table; a benchmark-backed adapter exists but is not the default. Do not interpret its thresholds as measured proof that adding agents improves BioMate outcomes. Evaluate single versus multi-specialist with identical evidence after wiring correctness is established.

Failure fallback must preserve the scientific request. Falling back to a single generator is acceptable only if it can satisfy the same plan contract; otherwise surface unsupported work or clarification, not apparent success.

### G3. Browser/API/status contracts do not preserve the new execution semantics — critical

Controlled execution of production browser helper functions confirmed:

- `buildChainSubmitSteps` removes `depends_on` and `dimensions`.
- `buildChainConnections` removes `context_params`.
- `mapChainStepStatus('blocked')` and `('submitting')` return `pending`.
- `mapChainRunStatus('partial')` returns `running`.

Consequently, the provisional backend DAG patch alone cannot solve the normal UI flow. Stable node IDs must survive serialization, persistence, polling and report links; array position is insufficient for evolving or branched plans.

### G4. Existing benchmarking can overstate completion and validity — critical

The registered benchmark is a valuable reuse candidate, but it currently has these limits:

1. Six hard-coded multi-omics methods, explicit method selection; no arbitrary “all applicable tools” resolver.
2. Parent grouping is in memory. Child runs are stored separately; GET supports reconstruction from supplied child IDs, but that is not durable parent ownership, plan or lifecycle storage.
3. Parent group creation follows submissions. A failure partway through submission can leave already-started children without a successful parent response.
4. GET scores successful, readable outputs; it can return `completed` while other requested methods failed or have missing outputs. Child details remain available, but parent completion is misleading.
5. Ground-truth metrics use each method's overlapping samples, potentially different cohorts. Comparability needs a declared cohort/missingness policy.
6. **Direct reproduction:** one shared sample produces invalid ARI/NMI (`NaN`, JSON `null`) but the method receives rank 1 and is returned as winner. In the no-label path, zero comparable pairs also deserve an explicit insufficient-evidence state rather than a default winning rank.
7. Inter-method agreement is not accuracy. Selecting the most agreeing method does not establish biological correctness.

Also review parent/child ownership and artifact authorization before broader exposure. The module's injected status lookup has no request context, its GET accepts supplied run IDs and a labels URI, and its output-list adapter does not forward the same authentication context as submission. These are source-level concerns, **not a demonstrated deployed access-control exploit**; inspect upstream middleware and storage authorization before assigning a final security conclusion.

### G5. Durable execution and scientific reduction are separate unfinished integrations — high

Reuse the existing Nextflow executor and run reconciler. Neither in-process retrieval map/reduce nor a new polling loop alone solves durable parent execution. Required properties include submission receipts, idempotency, scheduler ownership, restart recovery, cancellation, dependency joins and explicit partial completion.

Existing output collection and connection fallback are useful for established sequential chains. General fan-in additionally needs typed artifacts, biological identity, units, reference/build, sample set and provenance. A filename match cannot prove scientific compatibility.

Reducers must receive expected cases plus successes/failures, not just successful results. They must distinguish comparison, consensus, selection, and narrative synthesis. No reducer may convert “missing result” to “negative result.”

### G6. Request-level reporting and model evaluation are not yet acceptance-tested — high

Per-run reporting exists. The missing proof is one report answering the original request with every expected tool or compound–target pair accounted for, linked to the actual execution and evidence. A coverage table alone is not a scientific interpretation; an eloquent narrative without complete evidence is not a valid report.

No live full-product run of either user example was performed in this audit. No conclusions here establish that a local model, trained checkpoint, or particular model size meets client acceptance.

## Intended behavior for the two requests

An additional user-supplied example is now specified in [prior peptide designs → property tools → shortlist five](20261009_PEPTIDE_SHORTLIST_EVALUATION_CASE.md), with a machine-readable evaluation case. It adds prior-artifact recovery, chemical identity validation, mixed batch/per-candidate execution and an explicit selection policy. Screenshot claims are not verified scientific labels.

### “Compare all tools for XXX”

First resolve comparison mode: capability/literature review, execution benchmark, or both. Recover task, dataset and criteria from conversation and artifacts. Ask only for missing information that changes the scientific plan.

Resolve “all” against a versioned catalog scope: task-compatible, available tools and versions, licensing/deployment constraints, required inputs. Exhaust catalog pagination; do not substitute retrieval top-k. Record included, excluded and unavailable tools with reasons. Knowledge-only tools can appear in a capability comparison even when they cannot be executed locally; report that distinction explicitly.

Build shared preparation where scientifically valid, then method-specific branches with explicit adapters. Shared inputs must preserve sample identity, reference, contrasts and preprocessing assumptions. Join at validated metric extraction. Compare on declared compatible cohorts/endpoints; if no ground truth exists, report agreement, disagreement, runtime and resource use without claiming accuracy.

Report every scoped tool, run status, parameters/version, valid metrics, excluded metrics and reasons, uncertainties, artifacts and evidence. A winner requires a declared criterion and valid comparable evidence; “no defensible winner” is a valid result.

### “For inhibitor A and inhibitor B, how do targets A, B, C fit?”

Resolve compound structures/identifiers and target species/isoforms. Interpret “fit” using context; measured activity/selectivity, structural docking, and other evidence are different questions. Do not default every such request to docking.

Freeze the six requested compound–target cases. Retrieve measured evidence with endpoint, units, assay conditions and provenance. If computational evaluation is requested and inputs are available, prepare each unique compound and target once where valid, then fan out across the six pair evaluations. There can be more than six execution nodes; the **scientific coverage denominator remains six cases**.

Report a 2 × 3 matrix and explanatory comparisons, including missing evidence, failed computations, conflicting assays and uncertainty. Keep measured activity and computational predictions separate. Docking scores alone do not establish measured affinity, selectivity, efficacy or clinical suitability. “Unknown” must never become “inactive.”

Actual compounds, targets and dataset were not supplied for this audit. Named placeholders define acceptance structure, not scientific results.

## Target contracts and boundaries

Keep one versioned `RequestPlan` as the boundary between interpretation and execution. Use existing structures where compatible, with explicit adapters rather than another disconnected planner.

| Contract | Minimum content |
|---|---|
| Request scope | Original request, recovered context references, resolved entities, comparison mode, constraints, catalog/evidence snapshot, unresolved questions |
| Cases | Stable case IDs and requested dimensions; exact expected set; inclusion/exclusion reasons; mapping from each case to nodes and outputs |
| Nodes | Stable node ID, operation kind, workflow/tool/version, parameters, case membership, input artifact references, expected output schema |
| Edges | Explicit upstream/downstream IDs, typed output→input bindings, context propagation and compatibility checks |
| Execution policy | Max concurrency, budgets/time limits, retry/idempotency policy, failure/join behavior, cancellation semantics; bounded iteration only when supported |
| Reduction | Reducer kind/version, metric definitions, units, cohort/normalization policy, expected coverage, evidence validity rules, ranking eligibility |
| Run/evidence record | Parent/child IDs, plan version/hash, attempt IDs, receipts, statuses, artifacts/checksums, tool versions, source citations and timestamps |
| Report | Original question, scope, case coverage, validated facts/metrics, interpretation, limitations, links to artifacts and failed/missing cases |

Validate graph structure, capability availability, required inputs, complete case coverage and artifact compatibility before launching children. Unknown conditions must remain unknown; unsupported operations must be explicit. A changed plan after new user information gets a new version.

Use pattern retrieval to propose structure, deterministic validation to check it, existing durable execution to run it, deterministic parsers/reducers to establish metrics, and the LLM to explain evidence. Domain patterns (e.g. RNA-seq phases), control-flow patterns (e.g. parallel branches), and reasoning strategies (single/multiple specialists) must remain distinct fields.

## Detailed implementation plan

**Reuse-first update:** Before extending custom agent-loop infrastructure, perform the bounded [Hermes / DeepSeek / Agent Skills reuse experiment](20261009_HARNESS_REUSE_STRATEGY.md) within Stages 0–1. Keep BioMate's scientific execution and acceptance contracts; evaluate upstream runtime components and procedures against them.

Effort ranges below are engineering estimates for focused work after dependencies are available, not a same-day completion promise. Stages can overlap only where contracts are already settled. Do not wait for model training to fix runtime correctness.

| Stage | Concrete work and reuse | Deliverable / exit gate | Dependency; estimated effort |
|---|---|---|---|
| 0. Establish product baseline | Confirm deployed branch/flags, trace browser→assistant→planner→executor→report with correlation IDs; capture both example shapes using existing supported fixtures; inventory branch changes without merging unrelated work | Trace showing exactly where each case/edge/status is retained or lost; reproducible baseline and deployment manifest | First; 0.5–1 day |
| 1. Agree the plan boundary | Define versioned scope/cases/nodes/edges/reducers/status contract; adapters for existing frontend, composer, backend and chain API; document supported patterns and compatibility behavior | Round-trip contract tests; invalid cycles/IDs/bindings/incomplete cases fail before submission | Stage 0; 0.5–1 day |
| 2. Repair interpretation and pattern wiring | Reuse intent/NER/context recovery and pattern retrieval; category→catalog scope resolution; preserve same-workflow/different-case identity; fix real router result type and generation context; separate shape from agent strategy | Real class integration tests plus golden plans for both examples; no semantic collapse or silent single-task fallback | Stage 1; 1–2 days |
| 3. Preserve plans through the product | Browser/API serializer and status schema; stable-ID polling; visible dependencies/partial states; review summary states scope and missing inputs; expose one parent action | Browser submits the same validated plan; returned child IDs/statuses attach to correct cases; legacy sequential path remains valid | Stages 1–2; 0.5–1.5 days |
| 4. Integrate durable execution | Reuse Nextflow submission/status/reconciler; decide which provisional DAG pieces to retain; persist parent before first launch; idempotent receipts, leases, cancellation, bounded concurrency and fan-in; typed artifact adapters | Restart, partial submission, failure and cancel tests; live small CPU graph executes with verified artifacts and no duplicate children | Stages 1,3; 1–3 days |
| 5. Correct reducers and reporting | Fix invalid benchmark winner/partial status; freeze comparable cohorts; parent reduction receives full expected set; reuse findings/report jobs and version store; evidence-linked matrix plus explanation/export | Every case accounted for; no invalid winner; each metric reproducible from artifacts; exported report agrees with UI | Stages 1,4; 1–2 days |
| 6. Run full acceptance | Normal UI and supported API, actual tools and data, both user examples, local-model routing/no remote fallback; rerun after failures and review screenshots/reports | Acceptance evidence bundle with request, plan, run receipts, outputs, metrics, report and explicit omissions | Stages 2–5; runtime/data dependent, budget 1–2 days after readiness |
| 7. Train and evaluate against the repaired system | Curate validated trajectories and failures in parallel; freeze held-out tasks; compare base/instruct/fine-tuned candidate with identical tools/evidence/budgets | Measured end-to-end improvement, no coverage/reporting regression, reproducible local artifact and checkpoint manifest | Data preparation can start now; training follows schema freeze and verified trajectories |

Fastest credible sequence: baseline → one complete existing multi-method comparison → generalized case matrix → additional control-flow patterns. Do not begin with a broad orchestration rewrite or another synthetic decomposition training round.

For the first vertical slice, use the existing benchmark methods and a small known fixture to verify the complete product path. This validates integration, not arbitrary-domain generalization. Then use a supported compound–target workflow/evidence fixture; do not invent a scientific adapter merely to pass the example.

## Acceptance matrix

| Test | Required observation |
|---|---|
| Interpretation ambiguity | Review versus execution and meaning of “fit” resolved from context or one targeted clarification; missing inputs stop affected work honestly |
| Complete catalog scope | Multiple catalog pages included; unavailable/incompatible tools listed with reasons; no unannounced top-k truncation |
| Same workflow, different cases | Different compound/tool parameters retain separate case identities and correct artifacts; no path-only collapse |
| Sequential A→B | B receives the verified output of A with compatible metadata; no premature execution |
| Diamond A→{B,C}→D | B/C may overlap within concurrency limits; D obeys explicit join policy and receives both named outputs |
| Six-pair coverage | Two inhibitors × three targets produce six case records; five results cannot be reported as complete; prerequisites are not counted as extra scientific cases |
| Partial failure | Independent work completes; dependent work is blocked; report includes failures and keeps original denominator |
| Invalid metrics | One shared sample, empty output, incompatible units/cohorts and no comparable pairs produce an insufficient-evidence result, never a spurious winner |
| Ground truth absent | Agreement reported as agreement, not accuracy; ranking criterion and eligibility visible |
| Scientific uncertainty | Unknown activity remains unknown; predictions separated from measured evidence; conflicting assays retained |
| Crash/restart | Restart before/after submission and after receipt persistence does not create duplicate runs; uncertain submission requires reconciliation |
| Cancellation | Cancelling parent prevents new children and propagates to cancellable active work; final report/status does not remain falsely running |
| Conditional/iteration, when enabled | Unknown condition is not false; iteration has explicit maximum/budget and termination reason |
| Ownership | Another user's parent, child run, labels or artifact cannot be read by supplying its identifier; report inherits authorization |
| Product round trip | Browser/API preserve plan IDs/edges/cases/context; polling and export show the same terminal state and facts |
| Local client environment | All required LLM calls use the configured ≤32B local endpoint; no silent remote fallback; latency/resources measured on the actual trial machine |

Operational gates should be exact: zero lost cases/edges in fixtures; zero duplicate submissions in recovery tests; every terminal case has a result or explicit reason; every reported metric resolves to source artifacts. Scientific/model quality thresholds should be defined per task before running the held-out evaluation, not chosen after seeing scores.

## Data collection and training preparation in parallel

Start with the existing logs, corrections, commits, documents and tool/workflow knowledge. Their volume alone does not establish quality or the meaning of “300+ M”; inventory actual formats, counts, provenance, licenses and usable records first.

1. **Create a trajectory schema now:** user request and context, resolved scope, candidate/revised plans, selected pattern, validation errors, tool calls/results, failures/recovery, final artifacts, report and reviewer corrections. Record model/prompt/tool versions and evidence snapshot IDs.
2. **Mine genuine failures:** omitted branch, overwritten parameters, wrong dependency, missing input, format mismatch, invalid metric, unsupported comparison, partial result disguised as complete. Link corrections to executed outcomes; a commit alone is not a successful training label.
3. **Deduplicate and split by task family/project/workflow ancestry:** keep variants and retries from one scientific task in one split. Hold out realistic ambiguous requests, unfamiliar tools and combinations. Keep retrieval documents and evaluation questions traceable to detect leakage.
4. **Use teachers to draft, not certify:** teacher-generated plans/reports must pass structural validators, real tools where applicable, evidence checks and review. Preserve hard failures and negative examples. Do not train truncated or overly complete synthetic prompts as if they were real user traffic.
5. **Separate targets:** interpretation/clarification, graph construction, tool/parameter selection, evidence extraction, error recovery and report grounding. Record both component scores and complete-task outcomes; do not let good decomposition scores hide execution failures.
6. **Freeze paired evaluation:** identical evidence snapshot, catalog, executors and budgets for original/instruct/fine-tuned candidates. Measure completion, coverage, valid bindings, supported claims, recovery, latency and cost. MCQA alone cannot establish BioMate client readiness.
7. **Train after verified labels exist:** prioritize a small clean supervised set from complete trajectories. More advanced preference/self-improvement loops must use frozen external checks and held-out evaluation; the model must not grade its own unsupported success into new training truth.

Existing cost constraints still apply to any later authorized compute: Spot GPU or CPU, checkpoint/resume and S3 backup, ≤32B model, existing GPU ceiling and bounded run lifetime. The expired October 3 deadline is not a new launch window. No cloud compute or training was launched for this audit.

## Validation performed and remaining evidence

Follow-up: [shared acceptance suite and executable baseline](20261009_COMPLEX_TASK_ACCEPTANCE_BASELINE.md) now covers all three user examples. Twelve production-helper probes produced three passes and nine contract failures; the follow-up specifies the first integration changes and their exit gates.

- Existing browser serializer/status test files: **11 tests passed** (8 + 3). These tests do not currently catch the reproduced metadata/status gaps.
- Direct execution of actual production helpers reproduced metadata loss, status misclassification and invalid benchmark winner. Outputs are recorded in [audit evidence JSON](20261009_ORCHESTRATION_CAPABILITY_EVIDENCE.json). JSON `null` values in the scorer reproduction represent JavaScript `NaN`.
- Separate orchestration branch: **63 tests passed through its standalone runners** (router 12, S2 hook 15, map/reduce 11, corpus filesystem 14, corpus map 11). This is component evidence. Full pytest/package loading encountered local dependency-stack issues; it is not a full Galaxy integration pass.
- The earlier provisional increment passed 16 isolated Python tests, 5 frontend tests and TypeScript checking. Full Galaxy import remained blocked by missing `beaker`; isolated router fixtures do not replace that check.
- No live LLM call, scientific job, production deployment, cloud launch or end-to-end client acceptance run was performed in this audit. Deployed flags, real compound/target fixtures, scientific adapters and authenticated artifact behavior remain to be verified.

Reproduce the existing browser suites from `frontend/`:

```sh
./node_modules/.bin/vitest run client/src/lib/chain-execution.test.ts client/src/lib/chain-pipeline-sync.test.ts
```

For controlled reproductions, import production functions with `node --import tsx --input-type=module` from `frontend/`; use the inputs and observed outputs in the evidence JSON. No cloud service is required.

## Disposition and next action

Keep `53d09e07c` provisional. Review its graph validation, exact bindings and failure tests for reuse; reconcile its persistence, ownership, cancellation and API design with the existing executor and orchestration branch. Do not merge it wholesale as the solution. Preserve unrelated checkout changes.

The next implementation action is Stage 0/1: capture the actual product route and freeze the common plan/status contract, then repair the smallest complete benchmark slice. The acceptance artifact is one traceable request-to-report run, not a collection of independently green helper tests.
