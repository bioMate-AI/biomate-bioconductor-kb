# Complex-task execution takeover — 2026-10-09

> Follow-up audit: [capabilities, gaps and detailed integration plan](20261009_ORCHESTRATION_CAPABILITY_AUDIT_AND_PLAN.md).
> That investigation corrects overly broad earlier claims about fan-out, composer edges and reporting,
> and identifies additional browser/router/scoring gaps. The implementation below remains provisional.

## Status

The user's acceptance bar is **request → decomposition → real execution → evidence-backed report**.
This change is a first implementation increment, **not a completed or deployed end-to-end feature**.
Do not substitute a decomposition benchmark, six generated cards, or an execution coverage table for scientific acceptance.
No new training or GPU instance is needed to repair the issues identified here.

## What the two requests mean operationally

### Compare all tools for a scientific task

1. Resolve whether the user wants a literature/capability comparison or an actual benchmark.
2. Recover the dataset, task and success criteria. Resolve the applicable executable catalog set;
   freeze its version and list included/excluded tools with reasons. “All” means that stated scope,
   not an arbitrary retrieval top-k and not every tool on the internet.
3. Validate tool-specific required inputs. Insert explicit format conversions; retain the same
   biological samples, reference, contrasts and preprocessing assumptions across arms.
4. Build one branch per tool, with dependencies for prerequisites and explicit output bindings.
5. Execute, keeping run IDs, parameters, versions, input identities, outputs, runtime and failures.
6. Parse real output metrics into a common schema. Compare only compatible endpoints/units.
   With no ground truth, report agreement/disagreement and resource use; do not invent accuracy.
7. Report the complete tool set, metrics, differences, limitations and links to actual outputs.
   Missing or failed tools stay in the denominator; a partial comparison is labeled partial.

### Two inhibitors against three targets

1. Resolve the two compound identities and three target identities, species and relevant isoforms.
   Clarify “fit”: measured activity/selectivity evidence, structural docking, or both.
2. Declare the complete **2 × 3 = 6-pair matrix** before execution. Keep identity labels through
   every stage; identical workflow paths do not mean identical tasks.
3. Retrieve measured evidence for each pair with provenance, endpoint, units and assay context.
   Unknown evidence is not “inactive.” Resolve structures and required preparation if docking is requested.
4. Run the applicable pairwise workflows and validate their outputs. Keep assay evidence and
   predicted/docking metrics separate; a docking score alone is not measured affinity or efficacy.
5. Produce a six-row matrix (or 2 × 3 view), showing evidence, computational results, missing data,
   failed runs and uncertainty. Any ranking must specify its criterion and comparability limits.

Actual compounds, targets, task/dataset and desired interpretation were requested from the user.
These are needed for meaningful live acceptance, not for the generic scheduler tests.

## Current code findings

- `GalaxyAssistant.processMultiIntent` discarded additional workflow results solely because their
  Nextflow paths matched. This loses same-tool/different-input comparisons.
- `processSubIntent` sent the original entire multi-intent request back to workflow generation,
  instead of the branch's subquery. That can repeatedly route every branch to the primary task.
- The chain request/proxy dropped dependency metadata; the backend executed an array sequentially.
- Existing connections may use fuzzy labels and a single-file fallback. This cannot establish
  unambiguous scientific input identity for general fan-in.
- Existing pipeline manifests and output collection do not normalize metrics or generate the
  scientific comparison requested here. The older Python assistant still falls back from its
  decomposed tasks to single-workflow generation; the frontend planner still needs DAG assembly.

## Implemented in this increment

- Preserve runnable results per intent, including repeated workflow paths, and route branch subqueries.
- Extend the existing chain API/proxy with explicit **one-based** `depends_on`, `dimensions`,
  `coverage_axes` and `max_parallel`. Requests without dependency lists retain sequential behavior.
- Validate cycles, unresolved paths, invalid dependencies, conflicting bindings and case coverage
  before dispatch. A declared 2 × 3 scope with only five cases is rejected.
- Coordinate independent asynchronous Nextflow submissions, honor joins, bound concurrency,
  block descendants of failed steps and finish unrelated branches.
- Reattach to recorded run IDs after recovery. A crash during submission with no receipt is marked
  for reconciliation rather than automatically resubmitted. This is not a distributed exactly-once guarantee.
- Explicit DAG connections require an unambiguous exact published output filename. No fuzzy
  filename guess or demo-input substitution. Inherited context uses the actual source node.
- Persist chain snapshots atomically; DAG persistence errors prevent further dispatch. Preserve
  stable step identities and complete coverage/provenance rows in status/output responses.
- Mark successful executor responses with no published artifacts as failed in the DAG adapter.

Example explicit plan shape (paths and parameters must first be catalog-grounded):

```json
{
  "coverage_axes": {"tool": ["method-one", "method-two"]},
  "max_parallel": 2,
  "steps": [
    {"nextflow_path": "<resolved method-one path>", "depends_on": [],
     "dimensions": {"tool": "method-one"}, "params": {"input": "<validated input>"}},
    {"nextflow_path": "<resolved method-two path>", "depends_on": [],
     "dimensions": {"tool": "method-two"}, "params": {"input": "<validated input>"}}
  ]
}
```

## Verification and limits

- 16 Python 3.9 scheduler/API-contract tests passed: fork/join ordering, failure isolation,
  six-case retention, missing-pair rejection, recovery, uncertain receipts, cycles, ambiguous
  handoffs, preserved request metadata, persistence, and legacy sequential selection.
- 5 frontend tests passed (three new coverage/routing tests plus two existing local-LLM tests).
- Frontend TypeScript checking passed after the dependency and coverage metadata changes.
- Full Galaxy application import was attempted and failed on the local environment's missing
  `beaker` dependency. API tests isolate only the Galaxy Router import, using real FastAPI/Pydantic
  request models and actual API functions. They are **not** a full application/server test.
- No live Batch run, production deployment, biological result or end-to-end UI acceptance is claimed.

## Remaining completion gates

1. Ground category scope and case expansion in the planner; assemble the explicit plan through
   the live chat and UI execution path. Preserve dependencies instead of flattening multi-intent results.
2. Add schema-backed metric extraction, aggregation/comparison and final report generation with
   artifact-level provenance. The new coverage report is operational, not a scientific report.
3. Verify required output semantics, not just file existence; check input contracts and required params.
4. Harden multi-worker submission ownership, cancellation, and interrupted submission reconciliation;
   confirm these in the deployed persistence/runtime configuration before general rollout.
5. Run both user examples through the real product; inspect every pair/tool, actual outputs and final
   report. Include a controlled failure to prove it stays visible. Regress single-workflow behavior.
6. Only then use successful/failed complete trajectories as training data and execution-grounded evals.
   Further synthetic decomposition training is not the prerequisite for this repair.
