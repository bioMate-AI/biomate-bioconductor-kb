# Cross-workflow QC gate audit

Date: 2026-10-24. Scope: source audit followed by local implementation and regression checks; no deployment or live scientific runs.

## Implemented corrections

The findings below describe the audited behavior before these changes.

- Shared trace-based QC events are explicitly assessments, not permission to pause or rerun. Both Nextflow workflow viewer and older workflow card require a confirmed orchestration hold with actual pending steps before showing execution/remediation controls. Completed-run observations remain findings; Summary includes recorded failed/advisory checks.
- NCA process names dispatch to NCA parsing and criteria rather than PBPK.
- Live, stored and flat QC records normalize to explicit pass/fail/advisory/not-evaluated/unavailable outcomes. Missing data does not imply a pass. Failed checks do not imply an executed retry. Reports, exports and the older workflow card consume the same outcomes.
- Local assessments persist to `qc_events.json`. Reopened runs prefer recorded local/S3 assessments before reconstruction. Standard QC/report outputs can be reconstructed for additional domains, including NCA and OpenFE, with source references and retrospective context. Ambiguous/unrecognized sources remain not evaluated. Broad `drug_discovery` labels no longer force unrelated outputs through ADMET parsing.
- Completion-time ADMET evaluation no longer dispatches auto-loop events. Stored profiles/overrides are reused when available; reconstruction identifies when original criteria are unavailable.
- Pause endpoints reject terminal/no-controller cases before writing paused state. Failed controller termination restores prior state. The frontend proxy records a pause only after the backend confirms it.
- CryoSPARC model validation emits a not-evaluated record with null measurements instead of fabricated scores. Genuine CryoSPARC `QCHaltException` boundaries and chain approval behavior remain in place.

Validation: **139 backend tests passed**, including 22 new assessment regressions, 70 gate-reader tests and 47 existing CryoSPARC tests. **42 frontend tests passed**, covering completed findings, normalization, missing outcomes, explicit actions and late-event behavior. TypeScript checking, Python compilation and diff whitespace checks passed. The broader legacy consistency suite still requires the unavailable `pulsar` dependency; no pass is claimed for it.

Limits: no live Nextflow/CryoSPARC/AWS jobs were rerun, and stored reports were not bulk-rewritten. Unsupported historical output formats remain explicitly unavailable/not evaluated. A trace observer is not a scheduling barrier; any new intermediate Nextflow hold must be enforced by the orchestrator and name its actual pending consumers, rather than relying on a browser callback.

## Product rule

A finished scientific analysis reports its quality checks as findings. A negative scientific result is not an execution failure or a reason to manufacture a pending decision. Stop execution only where an actual remaining operation depends on an explicitly enforced precondition. Name that operation and the affected sample/compound/model. Report generation and access to partial results should remain possible.

## Coverage and limits

Inspected the shared Nextflow QC handler's 37 process-name rule branches, its event/report paths, the five-domain auto-loop bridge, the 13-domain gate-only emitter, the shared workflow UI and reproducibility report, the CryoSPARC halt path and workflow-chain approval boundary. Examined ten representative standalone graphs: QSAR RF, Vina docking, OpenFE RBFE, accelerated stability, polymorph stability, NCA, PBPK, novelty scoring, REINVENT lead design and Boltz structure prediction; also inspected the drug-discovery parent workflow and RNA-seq DE dependencies.

There are 2,239 `subworkflows/**/main.nf` files in this checkout. This audit covers shared mechanisms and representative graphs; it does not certify every tool, deployment, threshold's scientific validity or live run. Existing working-tree changes were left intact.

## Findings requiring correction

### 1. A blocking event does not establish that work remains

`backend/lib/galaxy/jobs/qc_trace_monitor.py:1312` checks completed processes and emits `qc_gate_triggered` based on threshold failures. Neither that decision nor its payload checks pending dependent work or records which next operation is held. The live monitor polls completed trace entries after scheduling may have advanced (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:3914`). It is an observer, not a synchronous DAG barrier.

`frontend/client/src/components/nextflow-workflow-viewer.tsx:2220` reacts by requesting a whole-run pause for a non-advisory failure. It does not establish whether this was the final scientific process or whether any particular consumer remains. Its auto-loop branches can instead rerun with suggested parameters, or report “No auto-fix available — workflow continued.” Neither behavior is equivalent to a reliable scientific gate before dependent work.

The pause route (`frontend/server/routes.ts:13710`) records paused state even if its backend pause request fails. The executor pause (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:7247`) stops the controller; already-running remote tasks may finish. UI-only gating cannot promise that bad inputs never reached downstream computation.

Correction: separate assessment result from execution disposition. Terminal result checks become findings. Genuine preconditions require an enforced orchestration boundary, confirmed pause status and named pending consumers.

### 2. NCA rules are shadowed by the PBPK branch

The PBPK branch at `qc_trace_monitor.py:5562` includes the substring `NCA_ANALYSIS`. This matches both `NCA_ANALYSIS` and the actual `NCA_PKNCA_ANALYSIS` process before the NCA branch at line 5642 can run. The intended extrapolated-AUC and missing-terminal-slope checks are skipped for those names.

Local execution of the extracted, unchanged rule function confirmed that NCA input with 50% extrapolated AUC and 5/10 subjects missing a terminal slope returned only the PBPK missing-half-life advisory. Providing `t_half_h` to `NCA_ANALYSIS` returned no warning at all. These probes use default threshold helpers, not a full Galaxy runtime.

Correction: make dispatch unambiguous, then verify the actual NCA process name. NCA analysis is followed by an HTML report; poor estimates belong in that report rather than preventing it from being produced.

### 3. Missing QC can be presented as passed; failed QC as an executed retry

`qc_trace_monitor.py:6355` records failures/warnings, but does not keep a complete per-check pass/not-evaluated ledger. With no gate events, its methods text says all processes passed. The rule function itself returns `(True, [])` for recognized processes with missing metrics and for unmatched process names.

`frontend/client/src/v2/AfterRunReport.tsx:1942` treats a missing status as passed. The empty-event UI says “All quality gates passed.” `isAutoCorrectedStatus` treats any status containing `fail` as auto-corrected, `deriveAction` claims a rerun, and the row renderer labels every non-pass as “FAIL → loop” without requiring evidence of a retry.

Correction: distinguish pass, fail, advisory, not evaluated and unavailable. Record actual actions; never infer a retry from a failed check. Missing evidence is not a pass.

### 4. Live event and report row schemas differ

Live events are nested `{type, process_name, timestamp, metrics, failures, suggestions}` in `qc_trace_monitor.py:6218`. `useFetchQcEvents` (`AfterRunReport.tsx:788`) passes `data.events` through unchanged. The report/table expects flat `{ts, gate, status, measured, threshold, message}` rows; its Markdown export also reads only those fields (`AfterRunReport.tsx:2515`). The Node proxy forwards the report without normalizing its rows.

The S3 ADMET fallback explicitly constructs flat rows, so reopened ADMET runs can look different from live or other-workflow records. Nested live failures risk blank report columns and false pass classification because `status` is absent.

Correction: normalize one durable per-check contract for chat, Summary, QC audit and export. Carry sample/compound identity, metric, units, comparison, effective criterion, result, source and actual action; preserve the original evaluation time and context.

### 5. Completion-time evaluation is domain-limited and can emit action-like feedback

`_evaluate_qc_from_s3` (`nextflow_executor.py:3382`) is explicitly called after completion and early-returns outside ADMET, CryoEM and preprocessing/cleaning signatures. Other workflow families do not get equivalent fallback coverage through this function. Its ADMET path invokes the auto-loop bridge, including on-demand historical evaluation.

Correction: historical/completion checks should produce durable findings without suggesting that an active run is being halted or automatically repaired. Represent unsupported/reconstruction-unavailable QC honestly. Do not apply today's default criteria to an old run without recording that this is a retrospective evaluation.

### 6. CryoSPARC emits placeholder model-quality measurements

`backend/lib/galaxy/webapps/galaxy/api/cryosparc_executor.py:1115` explicitly states PHENIX/MolProbity is not automatically run, but supplies placeholder scores (2.5, 0.95, 0.03) to its model-quality gate and emits the advisory. A log identifies the placeholder, but the resulting structured measurement can still resemble real QC.

Correction: report model validation as not performed, with an optional follow-up. Do not emit placeholder scientific scores as measured results.

## Workflow treatment

| Workflow/context | Observed structure | Correct interpretation |
| --- | --- | --- |
| Standalone ADMET | Inference shards → final prediction/aggregation → outputs | Completed with named-compound findings. No pause/remediation prompt after completion. |
| Standalone Vina docking | One docking process, poses/results/QC outputs | Weak scores and pose-quality issues are findings. A probe confirmed weak score currently yields a blocking event. |
| Standalone QSAR RF | One training/evaluation process, model report/results | Completed evaluation can fail validation. Preserve/report the model's limitations; block later registration or predictive use only at an explicit boundary, not a fictional unfinished training step. |
| Standalone PBPK | One simulation process with results/QC files | Invalid profile/clearance is a completed result-validity finding; do not claim a valid result. Further simulation is a follow-up, not automatic continuation. |
| NCA | Input validation → NCA analysis → HTML report | Invalid input can stop analysis. Extrapolation/terminal-slope findings belong in the final report; do not stop report creation. Fix the shadowed dispatch first. |
| OpenFE RBFE | PREP feeds both SETUP and ANALYSIS; terminal ANALYSIS emits summary/QC | Final uncertainty/convergence/cycle checks are findings. SETUP is not a sequential gate before ANALYSIS in the inspected graph: both consume PREP outputs. No synchronous check barrier was found there. |
| Boltz structure prediction | Input preparation → prediction → summary/QC | Final confidence is a finding attached to the structure, not a paused finished prediction. |
| Accelerated/polymorph stability | Standalone result-producing process | Report the stability/form-conversion result and limitations. Do not assume every emitted metric has a shared-handler rule. |
| Novelty scoring | Parallel per-query scoring → emitted results | Per-query findings; the inspected graph has no subsequent scientific consumer to hold. |
| REINVENT lead design | Validate → generate → filter/rank → report | Input errors can stop generation. Candidate rejection is a recorded filter outcome; generating the report should continue. |
| Sequencing/omics pipelines | Some QC steps precede alignment/inference; final aggregators can also match QC names | Decide by graph position and consumer, not tool name. `MULTIQC` shares the `FASTQC` blocking branch, so an end-of-run aggregation risks the same false-pause semantics. |
| CryoSPARC staged execution | QC functions can raise `QCHaltException` between stages | Preserve true intermediate stops where later stages remain. Review terminal validation separately; remove placeholder measurements. |
| Workflow-chain approval | `end_at_step` checks for pending steps before setting `awaiting_approval` | Preserve: this is an actual orchestration boundary. With no remaining steps it marks the chain succeeded. |
| Drug-discovery parent | Most branches read the same input and run independently | Source order is not sequential execution. Do not claim a docking branch waits for ADMET merely because it appears later in the file. |

## Verification

- `python3 -m pytest backend/tests/test_qc_gate_reader.py -q --disable-warnings --maxfail=2`: **70 passed**.
- Combined run with `test_qc_consistency.py`: collection blocked by missing `pulsar` dependency. No consistency-suite pass is claimed.
- Ten direct probes of the unchanged `_check_qc_thresholds` function, extracted with Python AST and default threshold stubs, demonstrated docking/QSAR/PBPK blocking classifications, NCA shadowing, FastQC/MultiQC classification, and empty/unmatched inputs returning pass. Probe results: `20261024_QC_GATE_AUDIT_PROBES.json`. The polymorph probe establishes only that the supplied field did not produce a failure, not whether all valid polymorph metrics are covered.
- Static workflow/event/report inspection only. No tools installed, production thresholds changed, live workflows rerun, or gates disabled.

## Recommended implementation sequence

1. Correct completed-run state handling and keep result findings visible; preserve actual intermediate gates.
2. Fix NCA dispatch and missing/unrecognized evaluation status.
3. Normalize QC records and remove invented pass/retry claims from reports and exports.
4. Remove placeholder measurements; retain explicit not-performed status.
5. Add remaining-consumer identity and enforced boundaries where a workflow actually needs a gate; verify real pause success and concurrency behavior.
6. Expand historical QC coverage and verify named-entity/source propagation against actual output fixtures, workflow by workflow.
