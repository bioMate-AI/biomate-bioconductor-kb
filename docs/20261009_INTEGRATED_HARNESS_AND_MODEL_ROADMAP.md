# Integrated roadmap: BioMate harness, skills and local-model adaptation

Date: 2026-10-09. This is the consolidated implementation and evaluation direction after the source audit and hosted 9B fixture experiments. Proposed architecture and training stages below are not claims of shipped capability.

## Objective and current evidence

Deliver common scientific requests through interpretation, real execution and a useful evidence-backed report on a model no larger than 32B. Retain existing BioMate capabilities and reuse upstream agent infrastructure where integration improves measured outcomes.

Initial evidence: nine of twelve product-boundary probes failed (the implementation update below records subsequent fixes); the Hermes registry adapter passes 30 component checks; actual hosted Qwen3.5-9B fixture conversations improve with explicit schemas and task-specific report context. This supports harness/procedure improvements before broad new training. It does not establish full Hermes runtime integration, trained-checkpoint quality, scientific correctness or on-premise acceptance.

The three worked examples are now **development/regression cases**, because prompts and schemas were modified after seeing their failures. They cannot serve as untouched evidence of generalization. Freeze separate unseen task instances and families before evaluating release readiness.

## Platform architecture to implement

Use a model-facing orchestration layer above BioMate's execution system:

```text
request and prior artifacts
  → intent/context resolution + relevant skill retrieval
  → structured logical plan
  → deterministic catalog expansion / case expansion / validation
  → existing durable workflow execution and artifact tracking
  → deterministic result parsing / scientific reduction
  → task-specific report synthesis
  → coverage, provenance and report-quality checks
```

This is a flexible sequence of responsibilities, not one fixed scientific pipeline. The logical plan can contain supported sequential prerequisites, independent branches, joins and reducers. Add conditions and bounded iteration only with explicit runtime semantics and tests. Distinguish workflow parallelism from parallel LLM agents.

Have the LLM express “evaluate these candidates with these methods,” then let code expand the exact case set. Do not require it to repeatedly serialize a large Cartesian product. The harness must preserve stable biological case identities independently of workflow/node IDs.

One component owns each responsibility: one agent loop, one authoritative request plan, and the existing executor owns scientific jobs. A conversation/session log must not replace durable run receipts or artifact ownership. Keep calculations and coverage checks outside narrative generation.

## Track A — harness and platform

| Priority | Work | Evidence required |
|---|---|---|
| P0 | Repair browser/API preservation of dependencies, dimensions, context rules and parent metadata; stable-ID status mapping and terminal/partial states | Existing failing transport/status probes become passing; real browser/API round trip preserves the plan |
| P0 | Fix invalid benchmark ranking and completion semantics | No winner with invalid/incomparable evidence; failed tools remain in denominator; valid comparisons remain correct |
| P0 | Implement logical-plan-to-executable-plan adapter over current catalog and executor | Dynamic tool set and candidate matrix expand exactly once, validate before dispatch and retain case identity |
| P0 | Parent evidence/report contract | Expected cases, run states, validated metric rows, policy and sources reach one report; no unrelated task policy leaks |
| P1 | Durable fan-out/join integration, retries and recovery | Restart/cancellation/partial-submission tests; no duplicate jobs; clear blocked/partial outcomes |
| P1 | Isolated reusable agent-runtime trial | Full initialization/provider/tool audit and actual three-case conversations through the chosen runtime; local-only route verified |
| P1 | Case-specific report renderer and grounded synthesis | Complete tables and artifacts, correct comparisons, actionable recommendations; model prose cannot override validated numbers/status |
| P2 | Conditional workflows, bounded scientific iteration and selective specialist agents | Explicit measurable benefit on tasks needing them, with budget and stopping limits |

Hermes remains a candidate for a separate worker, not an in-process Galaxy dependency; pinned source requires a newer Python runtime than Galaxy's 3.9 target. DeepSeek remains an alternative with modular interfaces. Do not install both as nested runtime owners. Source review and registry compatibility alone do not decide which full runtime is best.

## Track B — procedural skills

Adopt the portable skill-package approach and adapt existing BioMate pattern knowledge. Each skill needs a trigger/applicability description, prerequisites, tool schemas/references, procedure, output contract, failure rules, examples and tests. Load only relevant procedures and evidence; do not dump the knowledge base or every skill into the prompt.

Initial skills:

1. Interpret a scientific request and recover context.
2. Recover candidates/datasets from prior runs and artifacts.
3. Resolve all applicable tools with availability and compatibility checks.
4. Compose supported sequential, parallel and join patterns.
5. Compare methods/results under explicit scientific criteria.
6. Prioritize a candidate set under a declared selection policy.
7. Explain results in the expected report format with provenance.
8. Diagnose failures and recover without duplicating successful work.

Keep three levels separate: generic control-flow procedures, domain-specific scientific requirements, and tool-specific input/output knowledge. For example, a general candidate-selection procedure should not inject peptide-specific scoring into an inhibitor–target comparison.

Use skills first at inference time. Once they are correct and stable, collect successful skill-conditioned trajectories for training. Automatically proposed skill updates remain candidates until regression tests and review pass; version them and allow rollback. Do not let self-generated success assertions certify improvements.

## Track C — local model adaptation

### C0. Serving and protocol qualification

Verify the actual local checkpoint, tokenizer/chat template, structured output/tool-call behavior, truncation handling, context length, quantization, memory and latency on client-relevant hardware. Test every model role, including recovery and reporting, with no hidden remote fallback. Hosted 9B latency and behavior do not establish local checkpoint behavior.

### C1. Prompt, schema, retrieval and skills adaptation

Start with the current instruct-capable local candidate. Provide precise tools, relevant retrieved knowledge, applicable skills and separate planning/report contexts. Use deterministic validators and structured feedback. Compare against the same model without each addition. Do not change prompts, model, catalog and tool behavior together and attribute the combined gain to training.

### C2. Targeted supervised fine-tuning

Train only after stable contracts and measured residual failures exist. Initial targets: clarification decisions, correct tool/skill choice, logical plans, parameter grounding, interpreting validation errors, recovery and faithful reporting. Prefer complete multi-turn episodes with actual tool observations and corrections over isolated idealized decomposition answers.

Data lanes:

- **Execution trajectories:** request/context → skills/evidence → plan → calls/results → corrections → report.
- **Failure/correction pairs:** preserve the original failure, the verified fix and outcome; distinguish runtime defects from model mistakes.
- **Knowledge grounding:** tool/workflow inputs, outputs, applicability, examples and scientific constraints with provenance and version.
- **Preference examples:** expert- or validator-supported comparisons between candidate plans/reports, with specific reasons.

Teacher models may draft examples and alternatives on authorized development data. Validators, real tool outcomes and domain review certify labels. Teacher prose alone is not ground truth. Preserve the external example's response standard without copying its particular winners as scientific labels.

Split by source/project/task family and workflow ancestry before augmentation; keep linked retries and near-duplicates together. Keep test cases out of retrieval examples, skill examples, SFT and preference data used during evaluation.

### C3. Preference tuning and continual learning

Consider preference tuning after SFT only if remaining weaknesses are measurable and there are reliable comparative labels—for example unsupported claims, unnecessary calls, incomplete coverage or poor recommendations. Consider execution-feedback optimization only after the reward cannot be satisfied by plausible text or skipped cases. Do not start with unrestricted self-training or a broad RL program for the urgent trial.

Continue domain pretraining only if controlled evaluations reveal a knowledge/representation deficit not adequately addressed by retrieval and targeted adaptation. A large knowledge corpus is not by itself a reason for another pretraining run. Audit existing CPT/SFT artifacts rather than discarding or automatically extending them.

## Paired evaluation and release gates

| Comparison | Hold fixed | Measures |
|---|---|---|
| Current model, current vs repaired harness | Weights, data, catalog and intended task | Integration benefit |
| Current model, skills off vs on | Correct runtime, tools, evidence, budgets | Procedural guidance benefit |
| Base/instruct candidate vs adapted checkpoint | Harness, skills, evidence, budget and serving configuration where compatible | Training benefit |
| Hosted development route vs local deployment | Task/evidence/tool contracts | Deployment compatibility; hardware differences reported separately |

Record interpretation, plan validity, complete coverage, execution success, recovery, metric correctness, report grounding, readability, latency and cost separately. Require full request-to-report success as well. A model that passes MCQA but loses a branch or fabricates a completed run is not ready.

Mechanical gates are strict: no silently lost cases, no invalid winner, no duplicate submissions in recovery tests, and every metric linked to artifacts. Scientific quality thresholds require task-specific definitions and review before scoring. Do not invent a global acceptance percentage from three examples.

## Delivery sequence

**First:** fix reproducible platform errors; freeze the plan/tool/evidence contracts; build the initial skills and reserve unseen evaluation data. Data curation can proceed while runtime work continues.

**Then:** complete one normal BioMate request-to-report path with real applicable tools and a small known dataset. Repeat the three development scenarios, including partial failure and recovery. Evaluate the reusable runtime as an adapter over this system, not a replacement for scientific execution.

**Then:** measure the actual local checkpoint. Run targeted SFT only against demonstrated residual gaps, export/pin the serving artifact, and repeat the frozen evaluations. Select a larger candidate within 32B only if its measured accuracy/latency/memory tradeoff is preferable to further adaptation of the smaller model.

Client-trial readiness requires verified local execution and reporting; neither an upstream harness install nor a finished training job alone meets that gate.

Related evidence: [platform audit](20261009_ORCHESTRATION_CAPABILITY_AUDIT_AND_PLAN.md), [reuse strategy](20261009_HARNESS_REUSE_STRATEGY.md), [real-model fixture evaluation](20261009_OPENROUTER_HARNESS_EVALUATION.md).

## Implementation queue and delivery gates

Work proceeds through these gates without requiring approval at each checkpoint. A passing component test is not a deployed end-to-end acceptance result.

| Order | Concrete deliverable | Completion gate |
|---|---|---|
| 1 | Benchmark scorer and status fixes in `frontend/server/benchmark-orchestrator.ts` | Shared sample cohort, explicit insufficient evidence and ties, missing-method coverage, no silent label fallback; regression and route tests |
| 2 | Preserve the complete plan through browser submission and API; reconcile by stable step identity | Six inhibitor–target cases survive round trip; diamond dependencies and context transforms remain intact; blocked/partial states reach both panels |
| 3 | Versioned logical plan and parent evidence contracts | Deterministic case expansion, catalog snapshot, expected coverage, input bindings, reducer policy and artifact provenance validated before dispatch/reporting |
| 4 | First complete scientific comparison through the normal application | Real tools, visible child states, complete result table, traceable metrics, meaningful recommendation; repeat with a failed child and restart |
| 5 | Versioned application skills and one selected runtime integration | Relevant skills load selectively; bounded tool loop; same contracts; no duplicate executor or hidden remote fallback |
| 6 | Local model qualification and targeted adaptation | Evaluate pinned original and adapted checkpoints on frozen evidence, including tool calls and complete reports; export reproducible serving configuration |

### Data preparation that can proceed immediately

Create a manifest before converting logs into training text. Each episode should record its source and revision, project/task-family group, workflow ancestry, original request, permitted input/artifact references, catalog and skill versions, model/prompt versions, observed tool calls and results, correction, verifier, and outcome. Preserve failure causes as separate labels: model interpretation, schema/protocol, runtime, tool/scientific validity, or report grounding. Platform defects must not become examples teaching the model to work around lost fields or incorrect status.

Group linked retries, commits and derived documents before assigning train/development/test splits. Reserve unseen projects and task variants; perform near-duplicate checks before teacher augmentation. Keep the already debugged three examples in development. Record data permissions and remove credentials and unrelated client identifiers before any authorized teacher use.

Build four datasets against the same contracts: interpretation/logical plans; tool-call and recovery episodes; evidence-to-report examples; and expert-reviewed preference pairs. For each sample, retain the validator result and actual execution evidence where execution is claimed. Documents and knowledge-base entries primarily feed versioned retrieval; only verified examples enter supervised training. Capture counts by task family and failure class before setting sampling weights or training volume.

Freeze the evaluation manifest, serving configuration and budgets before training. Record a no-training baseline with skills/retrieval enabled, then test targeted SFT using the same evidence. Expand training only where measured model failures persist after platform fixes. Archive dataset hashes, split manifests, checkpoint/optimizer state and evaluation outputs with each run; Spot interruption recovery must verify optimizer restoration, not merely model-file existence.

### Implemented locally in this continuation

The benchmark scorer now uses the same sample cohort across methods, returns null metrics/ranks for insufficient comparisons, and avoids arbitrary winners for ties. Identical degenerate partitions score correctly. The status handler marks missing-method coverage as partial, recognizes cancellation/blocked/skipped terminal states, and fails explicitly when requested labels cannot be read. This is a local implementation; deployment and full scientific acceptance remain pending.

Validation: 16 focused scorer/registered-handler tests pass, and `npx tsc --noEmit -p .` passes. The original twelve production-helper probes improve from **3 passing / 9 failing** to **6 passing / 6 failing**; the remaining six concern plan transport and status mapping. Preserve the original baseline and the new [after-scoring evidence](20261009_COMPLEX_TASK_BOUNDARY_AFTER_SCORING.json) separately. Benchmark parent durability, partial submission recovery, robust CSV validation and consumer presentation remain open.


### Double check and transport continuation

The follow-up review added rejection of duplicate benchmark methods before dispatch and explicit failure/zero coverage when every cluster output is empty. Plan submission now preserves dependencies, biological dimensions, connection context rules, coverage axes and concurrency limits. Backend DAG persistence retains explicit step keys; frontend synchronization matches keyed branches by identity while retaining positional compatibility for legacy unkeyed artifacts. Blocked/submitting states are preserved and rendered; the standalone polling helper recognizes partial completion.

The twelve original helper probes now all pass: [transport evidence](20261009_COMPLEX_TASK_BOUNDARY_AFTER_TRANSPORT.json). There are 39 passing focused TypeScript contract/scorer tests, 10 passing pipeline component tests and 16 passing Python 3.9 DAG/API tests. The API tests isolate Galaxy Router initialization and inject job I/O; they are not deployed execution. Full Galaxy module import remains blocked locally by the missing `beaker` dependency; Python 3.14 also lacks FastAPI, so backend validation used the existing Python 3.9 environment.

Critical remaining integration work: the normal pipeline UI still uses linear step approval. Explicit DAGs now fail clearly before dispatch when that unsupported range is requested, instead of losing dependencies. Whole-plan approval and recovery need deliberate UI integration. The chat polling effect still has its own terminal-state list and can miss parent-only status changes; its integration with Run Manager and both panels must be tested. The component badges prevent unsupported-state rendering failures, but browser visual and real scientific execution acceptance have not run. Thus 12/12 helper probes does not mean the platform is end-to-end ready.

### Whole plan approval and chat status integration

Explicit dependency plans now use whole-plan approval in the normal pipeline chat card and submission callback. The card displays prerequisite step numbers, biological dimensions and the scope of confirmation. Legacy pipelines retain step-by-step approval. Once a dependency plan has a run ID, its card does not offer another submission of that same plan; recovery remains a separate pending feature.

Chat polling now persists parent-only status changes, stops polling terminal/partial parents across chat rerenders, ignores responses after effect cancellation, and clears stale terminal status when a sequential run is resumed. A parent status label exposes partial outcomes alongside child badges. These changes replace the previous documented UI blocker but do not establish live execution acceptance.

Validation in this increment: 25 focused approval/status/component tests and 17 existing chat regression tests pass; TypeScript checking passes. The right-hand Run Manager still uses a separate status conversion in `frontend/server/routes.ts` that does not include partial completion in its terminal set. Reconcile that mapping and its downstream consumers before claiming both-panel consistency. Real browser screenshots, job execution, restart/cancellation recovery and evidence-backed scientific reporting remain required gates.

### Run Manager status reconciliation

The Run Manager chain polling branch now classifies partial and blocked outcomes as terminal and unsuccessful. Its existing persisted status schema has no `partial` member, so the canonical status is `failed`, with an explicit partial-completion explanation; the original `partial` chain state and child details remain in `nextflowStatus`. This prevents success notifications and promotion while retaining successful child evidence. Cancellation aliases terminate, and resumed active/paused runs clear stale terminal timestamps and errors.

The status endpoint now returns the fetched chain details to the client instead of returning the unrelated, unset Nextflow variable. Successful chain recording remains conditional on a transition to successful completion. Ten classification tests and TypeScript checking pass. These tests validate the mapping contract, not the complete HTTP/storage/panel flow.

Live validation attempt: authorized read-only requests to local ports 5000 and 8081 both returned connection refused. Neither local frontend nor Galaxy was available for browser/scientific execution verification. The previously identified Galaxy import dependency gap remains. Next steps are a reproducible runnable integration environment, both-panel browser verification, and a real comparison with complete and partial outcomes before client-trial acceptance.

### Spark endpoint qualification

Spark access is working through `yzhang@spark-d816.local`, using the key and pinned host identity in the user-provided Downloads access package. The package's recorded IPv4 address timed out; mDNS works. No private key was copied into the repository.

The existing Ollama 0.21.2 could not pull the current Qwen3.5-27B package (HTTP 412, newer runtime required). A separate GPU container, `biomate-qwen27`, now runs Ollama 0.40.2 on Spark loopback port 11435, with a dedicated model volume. The image digest and model digest are recorded in [endpoint manifest](../evaluation/local_trial/harness_reuse/results/spark_qwen35_27b/endpoint_manifest.json). The original Ollama service remains unchanged. Model: Qwen3.5-27B, registry reports 26.9B, GGUF Q4_K_M; configured context 16,384 and one parallel request. This is the downloaded upstream model, not BioMate's trained checkpoint.

The current SSH tunnel exposes `http://127.0.0.1:18001/v1` on the Mac. [Environment template](../evaluation/local_trial/harness_reuse/spark-endpoint.env.example) records the BioMate local-only configuration; it has not been installed into a running application service. The tunnel is required and must be recreated after it stops. Container lifecycle is manual; no production service deployment is claimed.

Endpoint qualification passed: exact native structured tool call (42.96 seconds including cold startup), and BioMate's actual `localCompletion` JSON request (1.954 seconds warm). GPU residency was confirmed through `/api/ps`. The smoke explicitly requests `reasoning_effort=none`; automatic reasoning-mode compatibility across all application callers remains to be qualified. Results are in [protocol evidence](../evaluation/local_trial/harness_reuse/results/spark_qwen35_27b/protocol_smoke.json) and [transport evidence](../evaluation/local_trial/harness_reuse/results/spark_qwen35_27b/biomate_transport.json).

References: [official model package](https://ollama.com/library/qwen3.5:27b), [Ollama compatibility and reasoning controls](https://docs.ollama.com/api/openai-compatibility). Local fixture evaluation has no hosted fallback and uses synthetic data only. Endpoint success does not establish full scientific execution or client acceptance.

Spark fixture results: all three development cases completed in five turns each with every mechanical gate passing—tool comparison 74.24 seconds, inhibitor/target comparison 115.30 seconds, peptide shortlist 143.93 seconds. Scores and case coverage match the frozen fixtures. The comparison and inhibitor reports include irrelevant top-five instruction discussion; the inhibitor report uses six rows rather than a literal 2-by-3 matrix; the peptide report gives an artifact-reference pattern rather than enumerating all twelve references. Fixture-supplied recommended IDs mean peptide shortlisting is not an independent scientific-selection test. These results do not isolate model-size benefit from runtime/hardware differences versus the hosted 9B experiments.

Evidence: [Spark summary](../evaluation/local_trial/harness_reuse/results/spark_qwen35_27b/summary.json), with saved conversations, reports and manual reviews under the same directory. All 30 registry checks, 16 local transport tests and TypeScript checking pass. BioMate now accepts an optional `BIOMATE_LOCAL_LLM_REASONING_EFFORT`; the Spark environment template sets `none` so normal callers can use the tested reasoning configuration. The [reconnection script](../evaluation/local_trial/harness_reuse/connect_spark_endpoint.sh) restores the local SSH tunnel without installing or copying private keys. No application service has been switched globally to this endpoint.

### Real CLL comparison preparation and blocker

The next execution case is a deliberately bounded two-method comparison: SNF and MFA, the same CLL mRNA/methylation inputs, two clusters each, IGHV labels used for evaluation only. This tests the existing multi-method execution route; it must not be described as exhaustive tool discovery. Local source review confirms both workflows consume the same universal matrix interface and publish cluster assignments. MFA uses base R; SNF may install its CRAN dependencies at runtime. Expected outcome is two independent child runs, two cluster CSVs, metrics on the same shared labeled cohort and an evidence-backed report. Failure, missing output or incompatible coverage must prevent a full-success claim.

[Input manifest](../evaluation/local_trial/real_comparison/input_manifest.json): mRNA 5,000 features × 200 samples; methylation 4,248 × 200; 188 common labeled samples, class counts 84/104. Input hashes are frozen, sample IDs are unique and rows have consistent widths. Raw downloaded matrices are excluded from Git. [Execution request](../evaluation/local_trial/real_comparison/request.json) records the proposed destination and scope.

The existing development service responds to health requests. The saved E2E login had expired; the existing fixture account was authenticated again without registering another account. A historical run from a different owner correctly returned 403 with authentication and 401 without it; this is not proof of a new scientific workflow failure. Source inspection found the benchmark output collector did not pass the requesting session to the protected output endpoint. The local fix forwards the request credentials through the dependency and HTTP adapter; 19 benchmark tests pass, including the requesting-session handoff regression. No deployment or new scientific job has occurred.

The initial automatic approval review required explicit destination/payload approval. The user approved on October 10, 2026; the assistant request and two-method benchmark have now been submitted to the approved development service. No additional approval is pending for this case.


### October 10 real execution: planning failure and independent executor check

The real assistant request completed in 97.82 seconds. Its final event is `state=chat_only`, `intentType=research_question`, `workflow=null`, `workflowGenerated=false`. It calls its prose an executable plan but provides no runnable artifact. It also suggests unverified preprocessing and fitting only the labeled cohort. These are not the submitted scientific protocol. Full response and the failure assessment are saved in [planning review](../evaluation/local_trial/real_comparison/planning_review.json) and sibling evidence files.

Local source identifies a relevant architectural conflation: `execution-intent-guard.ts` recognizes “do not launch jobs yet”; `galaxy-assistant.ts` uses that prohibition to disable workflow *generation*. The live response is consistent with this path, but server decision logs are not available to distinguish the initial classifier from this override. Planning, approval, and job submission need separate contracts. Fixing the classifier prompt alone cannot correct the final guard. A draft must remain possible without authorizing launch, and prohibiting plan generation must remain respected.

To independently test execution, the approved benchmark API was called directly. This is an explicitly recorded **manual bridge**, not automatic end-to-end success. Benchmark `bm_mv2la6qj_0` returned SNF `cab2c69d-fc91-4861-b7e0-4ac265847b59` and MFA `e9acdf33-6575-44cb-82e5-725130386d7f`. Both entered AWS Batch execution. Inputs to each contain only the two omics matrices and n_clusters=2; labels stay at the evaluation stage. Submission and timestamped status snapshots are under `evaluation/local_trial/real_comparison/`. No metrics or winner are claimed before actual cluster artifacts are verified.

#### Implementation order after this live case

1. **Separate draft intent from execution permission.** Represent requested artifact (`explanation`, `draft_plan`, `results`) independently of permitted actions (`read`, `plan`, `execute`). Preserve explicit execution prohibitions through every model backend and tool dispatcher. A request for a draft must produce a reviewable plan without starting jobs; a request to interpret existing results must remain interpretation-only. Cover both cases and an explicit prohibition on generating a plan in integration tests.
2. **Bind comparison plans to executable catalog entries.** Capture method IDs, exact inputs, each method's parameter schema, independent branches, and a reducer contract. Preserve the difference between workflow-specific preprocessing and shared evaluation. Reject an incomplete comparison artifact rather than silently selecting one method. Connect the existing benchmark executor to the ordinary review/approval flow; do not introduce another executor.
3. **Make reports consume verified evidence.** Resolve authenticated output manifests, require actual cluster files, score one shared labeled cohort, preserve failed/missing methods, and expose versions, run IDs and output references. A descriptive response must never count as an executable artifact or completed report. The current local collector/scorer fixes still require controlled deployment validation.
4. **Test recovery and presentation.** After the complete two-method case, test one failed branch, restart during execution, and missing output. Verify chat and Run Manager agree, successful work is not duplicated, and the comparison remains partial until its required evidence exists.
5. **Create adaptation data from validated transitions.** Keep this observed request/response as a negative planning example with platform-confound labels. Pair it with a corrected, catalog-bound plan only after validation. Include draft-vs-execute pairs, parallel/sequence/matrix plans, failed-branch reports and evidence-grounded conclusions. Group retries and related source material before splitting; this case is development data. Test frozen unseen cases with the same harness on original versus adapted models before claiming a training gain.

The live request used the development service's configured hosted model path (response metadata reports `gpt-5.6-luna`), not the Spark 27B or a trained BioMate checkpoint. Consequently this case diagnoses current platform behavior; it cannot measure a local-model deficit or adaptation benefit. The existing 34 scorer/intent-guard tests passed on October 10, but do not cover draft/launch separation end to end.
