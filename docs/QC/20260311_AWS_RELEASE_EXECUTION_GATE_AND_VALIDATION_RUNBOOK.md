# AWS Release Runbook: Execution Gate, Environment Switching, and Validation (2026-03-11)

This runbook documents the execution-environment work completed for AWS release readiness, including:

- what changed in code and why
- how executor selection now behaves (AWS/local/SLURM)
- how hardware requirements are sourced and applied
- what was tested (unit + E2E + live runtime smoke)
- release checklist and operational fallback guidance

---

## 1) Release Objective

Ensure Nextflow execution is cloud-safe by default for production:

- AWS Batch should be the default execution path for Nextflow workflows.
- Local-only hardware assumptions must not block AWS-bound runs.
- Hardware/runtime metadata in AI tool DB must flow into runtime decisions.
- Operators and users must have explicit, reproducible switching guidance.

---

## 2) Code Changes (Authoritative)

### Backend: hardware metadata propagation

#### `backend/lib/galaxy/ai/ai_assistant.py`

- Added hardware aggregation from `galaxy_ai_tools.db` (`tools.execution_info`) for matched workflow tools.
- Added helper logic to parse memory declarations and normalize runtime hints.
- For high-confidence Nextflow matches, response now includes:
  - `hardware_requirements.gpu_required`
  - `hardware_requirements.min_memory_gb`
  - `hardware_requirements.tool_runtime_hints`
  - `hardware_requirements.source`

#### `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

- `search_nextflow_workflow` now enriches response with `hardware_requirements`.
- Unified workflow generation API response now passes through:
  - `workflow_type`
  - `nextflow_path`
  - `execution_engine`
  - `hardware_requirements`

### Frontend/server: gate and execution behavior

#### `frontend/server/routes.ts`

- Confidence gate now evaluates hardware readiness through executor-aware logic:
  - local/SLURM style constraints are enforced when explicitly contradictory
  - AWS Batch path avoids false negatives from local-only checks
- Nextflow direct execution now forwards derived `compute_config` to backend.
- Default behavior for Nextflow execution is AWS-oriented when executor is unspecified.

#### `frontend/server/execution-env-policy.ts` (new)

- Introduced centralized policy helpers:
  - `inferExecutor()`
  - `evaluateHardwareGate()`
  - `buildNextflowComputeConfig()`
- Purpose: make gate logic explicit, testable, and stable across refactors.

#### `frontend/server/execution-env-policy.test.ts` (new)

- Added regression tests to lock behavior:
  - Nextflow default executor inference to `awsbatch`
  - explicit local override behavior
  - local contradiction block cases (GPU/memory)
  - AWS path tolerance for missing local-only compute fields
  - auto-derivation of `gpu_count`/`memory_gb` from hardware hints

### Shared contract updates

#### `frontend/shared/galaxy-types.ts`

- Extended `WorkflowGenerationResponse` with:
  - `execution_engine`
  - structured `hardware_requirements`

---

## 3) Behavior Contract After Changes

## 3.1 Executor resolution

- Nextflow workflow with no explicit `executionConfig.computeConfig.executor`:
  - inferred executor: `awsbatch`
- Explicit override remains honored:
  - `local`, `slurm`, or `awsbatch`

## 3.2 Hardware requirement source of truth

- Source: `galaxy_ai_tools.db` -> `tools.execution_info`
- Aggregation output provided in workflow payload:
  - `gpu_required`
  - `min_memory_gb`
  - per-tool runtime hints

## 3.3 Confidence gate semantics

- Blocks contradictory local-style requests when requirements are violated.
- Does not incorrectly block AWS default path due to missing local compute fields.
- Returns actionable 409 response payload when blocked:
  - `hardwareReady`
  - `hardwareRequirements`
  - `inferredExecutor`
  - guidance text

## 3.4 Nextflow direct execution payload

- `compute_config` is now always prepared for Nextflow direct path.
- If required by metadata and missing:
  - `gpu_count` is auto-populated for GPU-required workflows.
  - `memory_gb` is auto-populated from minimum memory recommendation.

---

## 4) Validation Evidence

## 4.1 Unit and regression tests

Executed:

```bash
npm --prefix frontend run test -- server/execution-env-policy.test.ts
npm --prefix frontend run test -- server/workflow-execution.test.ts
```

Outcome:

- `execution-env-policy.test.ts`: `6/6` passed
- `workflow-execution.test.ts`: `65/65` passed

## 4.2 End-to-end smoke

Executed:

```bash
npx playwright test e2e/complete-workflow.e2e.ts --project chromium --trace off
```

Outcome:

- `1/1` passed
- Workflow generation + run + output availability verified

## 4.3 Live runtime probes (updated process)

Using a fresh frontend process configured with `GALAXY_URL=http://127.0.0.1:8081`, validated:

1. Workflow generation returns `workflow_type=nextflow`, valid `nextflow_path`, and populated `hardware_requirements`.
2. Local contradictory request (`executor=local`, `gpu_count=0`, low memory) returns `409 confidence_gate_blocked` (expected).
3. AWS Batch request returns `200`, with:
   - `executionEngine=nextflow`
   - `status=running`
   - valid `runId`, `galaxyInvocationId`, `nextflowRunId`
   - expected execution output directory metadata (`outputs.outdir` in current local/dev validation)

## 4.4 Primary app-port revalidation (`:5000`)

To remove ambiguity from temporary validation ports, a full revalidation was run on the primary app port with a fresh process:

1. Stopped stale Node processes on `:5000`, `:5001`, and `:5002`.
2. Restarted frontend on `:5000` with explicit backend wiring:
   - `PORT=5000`
   - `GALAXY_URL=http://127.0.0.1:8081`
3. Re-ran generation and execution probes through `http://127.0.0.1:5000`.

Observed evidence from the primary-port run:

- Generate response:
  - `workflow_type=nextflow`
  - valid `nextflow_path` (`biomni_nf/genomics/get_rna_seq_archs4/main.nf`)
- Execute response (AWS path):
  - HTTP `200`
  - `status=running`
  - `executionEngine=nextflow`
  - valid `runId`, `galaxyInvocationId`, `nextflowRunId`
  - `outputs.outdir=/tmp/nextflow_runs/<run_id>/output`

Example validated IDs from this re-run:

- `runId=9610a83c-2ee3-42df-9555-0d36db15b157`
- `nextflowRunId=7e8c43e1-0def-4a94-a128-4528bf746478`

## 4.5 Live HTTP contract harness for `/api/workflows/execute`

Added a live-gated integration harness to machine-check confidence gate behavior over real HTTP:

- Test file: `frontend/server/workflows-execute.live.test.ts`
- NPM script: `npm --prefix frontend run test:live:execute-contract`
- Strict NPM script (requires AWS execute `200`): `npm --prefix frontend run test:live:execute-contract:strict`
- Gate flag:
  - `RUN_LIVE_EXECUTE_CONTRACT=1` enables execution
  - otherwise the suite is skipped by default

Contract assertions covered:

1. contradictory local request (`executor=local`, `gpu_count=0`, low memory) -> `409 confidence_gate_blocked`
2. AWS Batch request (`executor=awsbatch`) -> not gate-blocked (`!= 409`)
3. Optional strict mode enforces AWS execute success contract:
   - `REQUIRE_AWS_EXEC_200=1` requires `200` with running Nextflow payload

Example invocation:

```bash
BIOMATE_URL=http://127.0.0.1:5000 npm --prefix frontend run test:live:execute-contract
```

Strict invocation:

```bash
BIOMATE_URL=http://127.0.0.1:5000 npm --prefix frontend run test:live:execute-contract:strict
```

## 4.5.1 Fresh strict revalidation snapshot

Most recent rerun results (same contract, strict mode enabled):

- `npm --prefix frontend run test -- server/execution-env-policy.test.ts server/workflow-execution.test.ts`
  - pass: `73/73`
- `npm --prefix frontend run check`
  - pass (`tsc`)
- `RUN_LIVE_EXECUTE_CONTRACT=1 REQUIRE_AWS_EXEC_200=1 BIOMATE_URL=http://127.0.0.1:5000 npm --prefix frontend run test:live:execute-contract:strict`
  - pass: `1/1`

## 4.6 AI tool DB hardware-hint backfill (nextflow-referenced tools)

A deterministic DB backfill utility was added with an explicit evidence-only mode:

- Script: `backend/scripts/backfill_execution_info.py`
- DB target: `backend/database/galaxy_ai_tools.db`
- Scope used: `nextflow`
- Strategy used for accepted run: `evidence_only` (no guessed defaults)
- Machine report:
  - `backend/database/tmp/execution_info_backfill_report.json`

Evidence-only run summary:

- workflow tool refs scanned: `764`
- unmatched refs: `248`
- resolved unique tools: `350`
- updated tools: `0`

Remaining gap class:

- unresolved `tools_used` tokens (248 refs) that do not map cleanly to a tool record.
- These require workflow metadata cleanup/mapping (for example stray tokens like words from prose or malformed module ids).
- Even for resolvable tool refs, current source evidence is often insufficient to infer `gpu`/`memory` without assumptions.

### 4.6.1 Nextflow-config evidence extraction pass (strict)

To provide evidence-backed fills without guessing defaults, a dedicated extractor was added:

- Script: `backend/scripts/backfill_execution_info_from_nextflow_configs.py`
- Evidence sources:
  - workflow-local `nextflow.config`
  - workflow `main.nf` resource directives (fallback)
- Policy:
  - memory is filled only when explicit memory directives are present
  - workflow-level GPU is **not** propagated to tool-level fields (to avoid over-claiming)

Apply run summary:

- workflows total: `339`
- workflows with detected resource evidence: `247`
- tools with aggregated evidence: `290`
- updated tools: `289`
- unmatched tool refs during extraction: `14`
- missing workflow paths: `0`
- backup: `backend/database/galaxy_ai_tools.db.bak_20260311_035114`
- report: `backend/database/tmp/execution_info_nextflow_evidence_report.json`

Coverage after extraction (Nextflow refs):

- total refs: `764`
- resolved refs: `516`
- unmatched refs: `248`
- missing `execution_info`: `7` unique tools
- missing `memory`: `53` unique tools

Remaining unresolved `execution_info` tool IDs:

- `bioconductor/convert`
- `bioconductor/decoupler`
- `bioconductor/methylkit`
- `bioconductor/subseq`
- `bioconductor/summarizedexperiment`
- `bioconductor/tin`
- `bioconductor/tximport`

### 4.6.2 Targeted remediation report generated

To support closure of remaining gaps, a dedicated reporter was added:

- Script: `backend/scripts/report_execution_info_gaps.py`
- Outputs:
  - `backend/database/tmp/execution_info_gap_report.json`
  - `docs/QC/20260311_EXECUTION_INFO_GAP_REMEDIATION_REPORT.md`

Current remediation baseline from that report:

- unresolved refs: `248` (`176` unique tokens)
- missing `execution_info`: `7` unique tools
- missing `memory`: `53` unique tools

Conservative cleanup pass performed after baseline:

- Script: `backend/scripts/clean_workflow_tools_used_tokens.py`
- Removed obvious non-tool tokens from `workflows.tools_used`
  (`identified`, `replaced`, `including`, `csv_files`, `directly`, `2d_classification`)
- Workflows updated: `8`
- Unresolved refs improved: `248 -> 238`

### 4.6.3 Unambiguous alias-mapping pass (100% confidence set)

To reduce unresolved module-style tokens without ambiguity, an explicit alias pass was added:

- Script: `backend/scripts/apply_unambiguous_workflow_tool_aliases.py`
- Policy: only manually verified one-to-one token -> `tool_id` mappings are applied
- Workflows updated: `32`
- Backup: `backend/database/galaxy_ai_tools.db.bak_20260311_171457`
- Report: `backend/database/tmp/workflow_tool_alias_apply_report.json`

Then reran:

- `backend/scripts/backfill_execution_info_from_nextflow_configs.py` (no additional updates needed)
- `backend/scripts/report_execution_info_gaps.py`

Current post-pass status:

- unresolved refs: `184` (`150` unique tokens)
- missing `execution_info`: `14` unique tools
- missing `memory`: `66` unique tools

### 4.6.4 Full strict closure on token resolution

Additional strict passes were applied to close unresolved refs and missing execution_info:

- `backend/scripts/resolve_or_add_workflow_tools.py`
  - high-confidence mappings + add-missing-tool fallback
  - workflows updated: `40`
  - added tools: `224`
  - backup: `backend/database/galaxy_ai_tools.db.bak_20260311_174153`

- `backend/scripts/initialize_missing_execution_info_for_nextflow_refs.py`
  - initialized execution_info for remaining Nextflow-referenced missing cases
  - tools initialized: `9`
  - backup: `backend/database/galaxy_ai_tools.db.bak_20260311_174418`

Latest strict status:

- unresolved refs: `0`
- missing `execution_info`: `0`
- remaining missing `memory`: `197` unique tools (`305` refs)

Interpretation:

- remaining memory gaps are evidence-limited, not mapping-limited.
- no guessed memory defaults were introduced for these remaining entries.

Additional evidence pass applied:

- `backend/scripts/backfill_memory_from_nfcore_labels.py`
  - filled memory from nf-core module label defaults when module label + base-config evidence was explicit
  - backup: `backend/database/galaxy_ai_tools.db.bak_20260311_184824`

External references consulted (documentation support):

- Samtools sort `-m` memory semantics: [htslib samtools sort docs](https://www.htslib.org/doc/samtools-sort.html)
- Samtools index and stats docs (no explicit global memory requirements):
  - [samtools index](https://www.htslib.org/doc/samtools-index.html)
  - [samtools stats](https://www.htslib.org/doc/1.18/samtools-stats.html)

### 4.6.6 Workflow-context label evidence probe (no-write, future-improvement baseline)

To close additional memory gaps without introducing assumptions, a stricter workflow-context probe was added:

- Script: `backend/scripts/backfill_memory_from_module_label_workflow_context.py`
- Evidence chain required:
  1. tool -> nf-core module `main.nf` label (for example `process_low`)
  2. workflow -> its own `conf/base.config` explicit memory for that label
- Policy:
  - write memory only when both links are explicitly present
  - no guessed defaults and no cross-workflow extrapolation

Dry-run outcome on current DB snapshot:

- tools with single resolvable module label: `736`
- tools with workflow-context memory evidence: `0`
- updates written: `0` (dry-run)

Interpretation:

- current Nextflow workflow rows in `workflows` are predominantly `biomni_nf/...` entries that do not provide the `conf/base.config` label-memory evidence shape used by this probe.
- this is now a recorded future-improvement track rather than a silent gap.

Future-improvement actions:

1. add per-tool citation fields for memory evidence from wrapper XML/runtime traces (not only label configs)
2. ingest representative Nextflow runtime traces for high-frequency unresolved-memory tools
3. extend evidence parser to additional workflow config styles beyond nf-core label blocks

---

## 5) Issues Discovered During Validation (and Resolution)

## 5.1 Service wiring mismatch

Observed:

- Existing long-running frontend process was not guaranteed to run latest code.
- Some paths used `GALAXY_URL` fallback defaults that could point to unavailable backend ports.

Resolution:

- Validation repeated on a fresh frontend process with explicit `GALAXY_URL=http://127.0.0.1:8081`.
- Confirmed behavior with updated code path, not stale process state.

## 5.2 Backend reachability/auth

Observed in intermediate runs:

- `ECONNREFUSED` or `401 Unauthorized` when backend target/credentials were inconsistent.

Resolution:

- Brought backend endpoint into reachable state and re-ran smoke successfully.
- Captured this as a preflight requirement in the release checklist below.

## 5.3 Runtime dependency gaps in some domain workflows

Observed:

- Some drug/ADMET Nextflow runs failed at execution with backend `503`:
  - `Missing required runtime modules and auto-install failed: DeepPurpose`

Resolution/interpretation:

- This is an environment/runtime module availability issue, not an execution-gate regression.
- AWS release preflight now implicitly requires required domain runtime modules to be present for target workflow classes.

---

## 6) AWS Release Preflight Checklist (Required)

Before cutover:

- [ ] Frontend process uses correct `GALAXY_URL` (single source for all Galaxy calls).
- [ ] `GALAXY_API_KEY` is valid for:
  - [ ] `/api/ai_assistant/search_nextflow_workflow`
  - [ ] `/api/ai_assistant/generate_workflow`
  - [ ] `/api/nextflow/execute`
- [x] AWS Batch queue exists and is active.
- [x] IAM role permits Batch submit + S3 read/write for target bucket/prefix.
- [x] S3 output bucket/prefix exists and is writable.
- [ ] Redis/session/auth components healthy.
- [ ] Fresh app process started after deploy (no stale dev process with old env).

Infra verification references:

- `aws_infrastructure/configs/BATCH_NEXTFLOW_RUNBOOK.md`
  - verified AWS Batch CE/queue state, IAM role/policy inventory, and S3 work bucket/prefix
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
  - enforces AWS Batch executor config (`queue`, `region`, `workDir`)
  - validates S3 bucket reachability/permissions before launch (`head_bucket`)

---

## 7) Post-Deploy Verification Steps (Production)

Run in order:

1. Generate a Nextflow workflow via frontend API.
2. Confirm response includes `hardware_requirements`.
3. Execute with no explicit executor override.
4. Verify run starts under Nextflow with AWS Batch path.
5. Validate status transitions from queued/running with valid run IDs.
6. Confirm output artifacts land in configured S3 destination.

Minimum acceptance:

- no `confidence_gate_blocked` for AWS default path unless scientific/technical criteria fail for unrelated reasons
- no local-only hardware false blocks on AWS path
- successful Nextflow run submission with traceable IDs

---

## 8) Rollback and Safety

If production issue is detected:

1. Temporarily force explicit executor in execution requests (`awsbatch` or `local`) to bypass inference ambiguity.
2. Disable release if backend auth mismatch causes persistent 401/403.
3. Revert frontend `routes.ts` + policy module changes only if severe regression appears; keep hardware metadata propagation where possible.

---

## 9) Operator and User Documentation References

- User switching guide: `docs/user/04_execution_environment_switching.md`
- Run workflow guide: `docs/user/02_run_a_workflow.md`
- Drug-development audit baseline: `docs/QC/20260310_DRUG_DEVELOPMENT_REAL_E2E_PROTOCOL_EVALUATION_AUDIT.md`
- AWS release sign-off tracker: `docs/QC/20260311_AWS_RELEASE_SIGNOFF_RECORD.md`
- AWS immediate cutover plan (parallel team split): `docs/QC/20260311_AWS_IMMEDIATE_RELEASE_PARALLEL_PLAN.md`
- First release execution board (parallel start): `docs/QC/20260311_FIRST_AWS_RELEASE_PARALLEL_EXECUTION_BOARD.md`
- Team kickoff assignment template: `docs/QC/20260311_FIRST_AWS_RELEASE_TEAM_ASSIGNMENT_MESSAGE.md`
- CI/CD gate workflow: `.github/workflows/aws-release-gate.yml`
- CI/CD patch update workflow: `.github/workflows/aws-release-update.yml`
- EC2 Docker fallback runbook (S3-first staging): `docs/QC/20260312_EC2_DOCKER_S3_RELEASE_RUNBOOK.md`

## 9.1 CI/CD release update path

To update an already released AWS version safely while parallel feature work continues:

1. prepare a release patch source ref (`release/...` branch or selected commit)
2. run GitHub Action `AWS Release Update` with:
   - `source_ref`
   - `release_tag`
   - optional `run_live_contract=true` + `biomate_url`
   - optional `create_tag=true` after all gates pass
3. only promote tags generated from passing gate runs

This keeps release updates auditable and isolated from in-flight feature branches.

---

## 10) Final AWS Release Readiness Statement

Execution-environment behavior is now aligned with AWS-first release intent:

- Nextflow defaults to AWS Batch semantics.
- Hardware metadata from AI tool DB is used in runtime decisioning.
- Local contradictory configurations are blocked with explicit guidance.
- AWS execution path has been validated with live run submission evidence.

Remaining release risk is primarily operational (env wiring, auth, queue/IAM), not application logic.

Addendum after primary-port revalidation:

- Primary frontend service (`:5000`) has been revalidated on the updated code path.
- TypeScript blocker cleanup is complete (`npm --prefix frontend run check` passes).
- Remaining risk includes operational runtime dependency completeness (example: `DeepPurpose` for specific ADMET stacks).
