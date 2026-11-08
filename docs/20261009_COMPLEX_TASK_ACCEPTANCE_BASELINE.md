# Complex-task acceptance baseline and first integration changes

Date: 2026-10-09. This continues the capability audit with executable production-boundary probes and a common acceptance specification. No runtime code was changed or deployed.

## Acceptance suite

[Shared suite specification](../evaluation/local_trial/cases/complex_task_acceptance_suite.json) covers:

1. Compare all applicable tools for a task and dataset.
2. Evaluate two inhibitors against three targets, preserving all six cases.
3. Recover prior peptide designs, run applicable property tools, and recommend five candidates.

The third case uses the other platform's example as the user-endorsed standard for response content and presentation. The expected output is an understandable report: recovered-input summary, tools/coverage table, integrated comparison, recommendations with reasons, complete results and material limitations. This is a product requirement, not an optional narrative after execution.

Each case requires evidence from interpretation, input recovery, planning, execution and final reporting. Unexecuted stages remain `not_evaluated`. Offline helper results cannot pass the overall product acceptance gate.

## Executable baseline

[Production-boundary probe runner](../evaluation/local_trial/probe_complex_task_boundaries.ts) imports actual frontend submission/status helpers and the benchmark scorer. Inputs are synthetic; it makes no network requests and launches no jobs.

Run from `frontend/`:

```sh
node --import tsx ../evaluation/local_trial/probe_complex_task_boundaries.ts
```

Exit code 1 means the checked contract is not satisfied. Failures are recorded as failures, not marked expected-pass. Missing fields are encoded as `{"missing": true}` in the output, rather than disappearing during JSON serialization.

[Captured baseline](20261009_COMPLEX_TASK_BOUNDARY_BASELINE.json): **12 checks, 3 passed, 9 failed**.

| Check | Result | Implication |
|---|---|---|
| Six same-workflow cases retain different parameters | Pass | Serializer preserves these values; earlier planner collapse remains a separate concern |
| Six cases retain supplied step keys | Pass | Reuse existing `step_key` instead of inventing another unrelated identity |
| Six cases retain dimension labels | Fail | Scientific case coverage metadata is lost |
| Diamond graph retains dependency arrays | Fail | Explicit branching cannot survive this boundary |
| Connection retains context transformation rules | Fail | Existing backend context inheritance cannot receive these rules through this helper |
| Blocked status remains distinguishable | Fail | Becomes pending |
| Submitting status remains distinguishable | Fail | Becomes pending |
| Partial parent remains distinguishable | Fail | Becomes running |
| Invalid ground-truth metrics produce no winner | Fail | One-sample case still has a winner |
| A single method without pairwise evidence produces no winner | Fail | No-comparison case still has a winner |
| Nonoverlapping methods produce no winner | Fail | No shared samples still produce a winner |
| Valid ground-truth comparison selects the matching method | Pass | Preserve the working scorer behavior while fixing eligibility |

The probes establish boundary behavior, not an empirical failure rate across user requests. Some required states are proposed integration semantics, so failure means an unsupported contract, not necessarily a regression of a previously supported feature.

## Traced product call sites

- `frontend/client/src/components/chat-with-artifacts.tsx` imports submission helpers at line 18; calls `submitWorkflowFromArtifact` around 1282 and 1367; synchronizes chain statuses around 1334 and 1484.
- `frontend/client/src/lib/chain-execution.ts` `submitWorkflowFromArtifact` around 196 obtains structured steps/connections and calls `submitWorkflowChain`. Parent coverage and concurrency are not copied. The step and connection builders discard the fields identified above.
- The chat component's per-step resume path around 1423 uses an array-derived index and the legacy resume interface. Do not apply it to an arbitrary graph without explicitly supporting that operation.
- `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py` `resolve_context_params` expects rule objects such as `organism: {from_run_param: genome, transform: genome_to_organism}`. The probe now uses that real rule shape.
- `frontend/server/jobs/handlers/findings-analysis.ts` accepts one `runId`; `methods-report.ts` accepts one `invocationId`. These are reusable child-report mechanisms. A parent comparison needs a versioned collection of expected cases, child evidence and reducer results, not concatenated child prose alone.

## First integration changes, in dependency order

### 1. Freeze compatibility rules before expanding the runtime

Use existing `step_key` as the adapter's stable node identity. Preserve legacy sequential payloads; explicit graphs must be validated and must not silently become legacy sequences. Specify how one-based dependency indices in the provisional backend map to stable IDs, and forbid ambiguous mixed conventions. Keep scientific case IDs distinct from execution nodes because preparation may be shared and a batch node may cover many cases.

Define the terminal/partial/blocked/submitting status semantics jointly across backend, polling and UI. A serializer-only fix would still leave misleading status and unsupported resume behavior.

### 2. Repair transport and rendering as one bounded change

Carry explicit dependencies, dimensions, context rules and parent coverage/concurrency through the artifact adapter, browser submission, server proxy and backend validation. Update status rendering and polling together. Preserve stable IDs across responses and match by ID, with a documented legacy fallback only for old records. Run the same fixtures through actual browser/API requests after unit checks pass.

Exit gate: the diamond graph and six-case plan survive a complete round trip without loss; blocked/partial results render correctly; legacy sequential execution and its resume remain valid.

### 3. Fix metric eligibility independently of narrative generation

Require valid comparable evidence before assigning rank/winner. Make missingness and comparability explicit in scorer output and parent completion. Preserve valid existing metrics and avoid turning insufficient evidence into a zero-quality result. Define ties and the shared-cohort policy before changing sorting.

Exit gate: the three invalid-winner probes pass alongside the valid comparison control; additional ties, partial tools and cohort fixtures pass. Audit consumers of the scorer's return schema before modifying it.

### 4. Add parent report input using existing report jobs

Give the parent report immutable plan/case coverage, validated metric rows, evidence/artifact references and a declared reducer policy. Reuse child findings and export/version facilities. Produce the expected report sections from the positive example. Human review evaluates readability and whether the recommendation follows from results; structural checks alone cannot establish that.

Exit gate: one real comparison reaches the report through normal BioMate interaction, with every tool/case visible and every numeric claim traceable. Then apply the same integration to the inhibitor–target and peptide cases.

## Outstanding execution evidence

No complete scientific fixture, live product session or deployed configuration was exercised in this baseline. Real tool availability, authenticated prior-input recovery, artifact ownership, durable scheduling and restart/cancellation still need the acceptance runs described in the [detailed plan](20261009_ORCHESTRATION_CAPABILITY_AUDIT_AND_PLAN.md). The current baseline is suitable for debugging and regression tracking, not client sign-off or a model-quality score.
