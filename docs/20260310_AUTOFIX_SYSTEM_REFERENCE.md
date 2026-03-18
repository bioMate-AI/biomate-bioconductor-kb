# BioMate AutoFix System — Reference Document

**Date:** 2026-03-10  
**Source:** `galaxy_nextflow/lib/galaxy/ai/workflow_ops/autofix/`  
**Status:** Core functions complete and tested

---

## Overview

The AutoFix system provides fully automated failure detection, diagnosis, and self-healing for Nextflow workflows running in BioMate. When a workflow fails or produces out-of-spec QC metrics, AutoFix:

1. **Detects** the root cause from Nextflow trace files, Galaxy DB state, and CloudWatch logs
2. **Classifies** the fix risk (LOW / MEDIUM / HIGH / CRITICAL)
3. **Applies** low-risk fixes automatically; queues medium/high-risk for user approval
4. **Restarts** the workflow with corrected parameters via Galaxy's invocation API

---

## Architecture

```
Workflow fails
     │
     ▼
NextflowMonitor._analyze_logs_with_ai()   ← parses nextflow.out, workflow-trace.txt
     │                                       CloudWatch logs, Galaxy invocation state
     ▼
_attempt_auto_fix(issues, logs)
     │
     ├─► ContainerErrorFixer.detect_issues()
     ├─► (other fixers can be added)
     │
     ▼
AutoFixOrchestrator.run_all_fixers()
     │
     ├─► Risk gate: LOW → auto-approve
     │              MEDIUM / HIGH → user approval required (API call)
     │
     ├─► StateSnapshot (rollback point)
     │
     ├─► apply_fix() → updates context.metadata['updated_parameters']
     │
     ▼
WorkflowRestarter.restart_workflow()
     │
     ├─► LLMParameterMapper: maps generic fix params → pipeline-specific params
     │   (cached after first LLM call; subsequent hits <10 ms, $0)
     │
     ├─► build_workflow_run_configs()   ← Galaxy core API
     ├─► queue_invoke()                  ← Galaxy scheduler
     │
     └─► returns new invocation_id
```

---

## Framework Primitives (`base.py`)

### Key Types

| Type | Values | Description |
|------|--------|-------------|
| `RiskLevel` | `LOW \| MEDIUM \| HIGH \| CRITICAL` | Controls auto-approve gate |
| `FixStatus` | `SUCCESS \| FAILED \| PENDING \| SKIPPED \| PARTIAL` | Result of apply_fix |
| `FixContext` | dataclass | Carries invocation_id, work_dir, error_logs, current_params, user_id, metadata |
| `StateSnapshot` | frozen dict | Pre-fix state for rollback |
| `FixPlan` | dataclass | List of `FixAction` objects describing what to change |
| `AutoFixResult` | dataclass | Final outcome with status, message, suggested_params, can_rollback |

### `BaseAutoFixer` (abstract)

All fixers implement three methods:

```python
class BaseAutoFixer:
    def detect_issues(self, context: FixContext) -> List[Dict]: ...
    def generate_fix_plan(self, context: FixContext, issues: List[Dict]) -> Optional[FixPlan]: ...
    def apply_fix(self, context: FixContext, fix_plan: FixPlan, sa_session) -> AutoFixResult: ...
```

The base class enforces before `apply_fix` is called:
- Permission check (user_id scoping)
- Risk and cost gate
- State snapshot
- Audit log write (`AIFixAuditLog` DB table)
- Rollback on failure

---

## Orchestrator (`orchestrator.py`) — `AutoFixOrchestrator`

Central coordinator. Executes the full lifecycle:

1. Build `FixContext` from `invocation_id`
2. Check user permissions
3. Call `detect_issues` → `generate_fix_plan` per fixer
4. Evaluate `RiskLevel` and estimated cost
5. Auto-approve LOW-risk or wait for user approval (Medium/High)
6. Take `StateSnapshot`
7. Call `apply_fix`; roll back on failure
8. Write to `AIFixAuditLog`

Phase 3.3 additions:
- `FixValidator`: post-fix validation (confirms fix worked)
- `FixSuccessTracker`: tracks historical fix outcomes per fixer type
- `FixSimulator`: dry-run mode (returns plan without applying)

---

## Fix Applier (`fix_applier.py`) — `WorkflowFixApplier`

Low-level DB and infrastructure mutations used by fixers:

- `apply_parameter_fix`: updates `WorkflowRequestInputParameter` rows in DB
- `apply_resource_scaling_fix`: modifies Nextflow config files and AWS Batch job definitions (via boto3)
- `apply_retry_fix`: writes retry metadata into `invocation.input_parameters`
- Checks user quotas (`UserCloudPreferences`, `UserResourceUsage`) before changes

---

## Auto Healer (`auto_healer.py`) — `WorkflowAutoHealer`

Strategy dispatcher. Maintains a registry of `FixStrategy` implementations:

| Strategy | Handles |
|----------|---------|
| `ParameterFixStrategy` | Invalid/missing parameter values |
| `DataConversionFixStrategy` | File format mismatches |
| `ResourceScalingFixStrategy` | OOM, CPU throttle, disk exhaustion |
| `SimpleRetryStrategy` | Transient network/Spot errors |
| `GTFFormatFixStrategy` | GTF chromosome naming mismatches |

For issues no strategy handles, calls `UnifiedLLMClient` for enhanced analysis.

---

## Fixer Modules

### 1. `NextflowParameterFixer`

| Aspect | Detail |
|--------|--------|
| **Detects** | Missing required parameters (vs `WorkflowParameterTemplate` and `CRITICAL_PARAMS` per pipeline), invalid values, type mismatches |
| **Infers fix from** | Historical successful runs (`_infer_from_history`), pipeline-specific defaults (`_get_pipeline_default`), template defaults |
| **Applies** | Directly updates `WorkflowRequestInputParameter` DB rows and commits |
| **Risk level** | LOW (parameter correction), MEDIUM (value changes that alter biology) |

---

### 2. `ReferenceGenomeFixer`

| Aspect | Detail |
|--------|--------|
| **Detects** | "genome not found" error patterns in `nextflow.out`; GTF/FASTA chromosome naming mismatches (via `nextflow.config` parsing) |
| **Genome IDs recognised** | GRCh38, GRCh37, GRCm39, GRCm38, BDGP6, WBcel235, EB2, UMD3.1, +others |
| **Fixes** | Missing genome → proposes DOWNLOAD_REFERENCE_GENOME + BUILD_GENOME_INDEX actions; GTF/FASTA mismatch → suggests correct FASTA param + disable iGenomes; unknown genome → USER_ACTION_REQUIRED |
| **Applies** | Returns `FixStatus.PENDING` — downloads/index builds are long-running and require user confirmation. Helper methods `list_available_genomes()` and `get_genome_sources()` available for external API interaction |
| **Risk level** | MEDIUM–HIGH (depends on whether a download is required) |

---

### 3. `ContainerErrorFixer` ← Primary fixer called from `NextflowMonitor`

| Aspect | Detail |
|--------|--------|
| **Detects** | Parses `workflow-trace.txt` + AWS CloudWatch logs. Error categories: GTF format issues, STAR index errors, Bowtie alignment failures, OOM (exit codes 137/143), network timeouts, permission denied, disk space |
| **Unknown errors** | Passed to `DeepAnalysisAgent` (LLM) via `_analyze_unknown_error_with_llm` |
| **Fixes** | Fixable errors → proposes updated Nextflow params (e.g., `star_index`, `aligner`, `max_memory`). Non-fixable (disk space, permissions) → generates `user_guidance` text |
| **Applies** | Adds/updates entries in `context.metadata['updated_parameters']` for `WorkflowRestarter`. Does NOT touch the DB directly |
| **Risk level** | LOW (parameter changes), MEDIUM (memory increases), HIGH (aligner substitution) |

**Recognised error patterns:**

| Pattern | Category | Auto-fixable |
|---------|----------|--------------|
| GTF format errors | `GTF_FORMAT` | Yes — update GTF param |
| STAR index missing/wrong | `STAR_INDEX` | Yes — rebuild index |
| Bowtie alignment failure | `BOWTIE_ALIGN` | Yes — adjust Bowtie params |
| OOM, exit 137/143 | `OOM` | Yes — increase `max_memory` |
| Network timeout | `NETWORK` | Yes — retry with backoff |
| Permission denied | `PERMISSION` | No — user_guidance |
| Disk space | `DISK` | No — user_guidance |
| Unknown (LLM analysed) | `UNKNOWN` | Depends on LLM assessment |

---

### 4. `AWSResourceFixer`

| Aspect | Detail |
|--------|--------|
| **Detects** | OOM, CPU throttling, disk exhaustion, Spot interruptions, S3 transfer errors, container image pull errors — via log parsing with CloudWatch/local sources |
| **Fixes** | Recommends increased memory/CPU/disk (with safety overhead headroom), retry mechanisms for Spot interruptions, S3 timeouts, container pull failures. Respects `UserCloudPreferences` limits |
| **Applies** | Directly updates `invocation.input_parameters['resource_overrides']` in DB and commits — picked up by job scheduler on next run |
| **Risk level** | LOW (retry), MEDIUM (resource increase), HIGH (exceeds user quota) |

---

### 5. `DataFileFixer`

| Aspect | Detail |
|--------|--------|
| **Detects** | Missing files, inaccessible files, format mismatches (`.fastq` vs `.fasta`, compression), paired-end read pairing errors — via `HistoryDatasetAssociation` queries + fuzzy matching (`SequenceMatcher`) |
| **Fixes** | Updates workflow parameters to use a similar dataset (`_find_similar_dataset`), or performs format conversions (e.g., decompress `fastq.gz`). Identifies incorrect paired-end pairings |
| **Applies** | File replacement → updates `invocation.input_datasets_metadata` to new dataset IDs. Format conversions → `FixStatus.PENDING` requiring user confirmation for API-driven file transforms |
| **Risk level** | LOW (format fix), MEDIUM (dataset substitution) |

---

### 6. `FileFormatFixer`

| Aspect | Detail |
|--------|--------|
| **Detects** | FASTQ quality encoding (Phred33/64), line endings (CRLF/LF), file encoding (Latin1/UTF-8), BOM presence — via error log keyword matching + direct file content analysis |
| **Fixes** | Proposes `CONVERT_FILE_FORMAT` action for each issue type |
| **Applies** | `FixStatus.PENDING` for user confirmation. Internal helpers (`_detect_line_ending`, `_detect_bom`, `_detect_fastq_encoding`, `convert_file_format`) perform transformations locally with backup |
| **Risk level** | LOW |

---

### 7. `RetryStrategyFixer`

| Aspect | Detail |
|--------|--------|
| **Detects** | Transient failures: network timeouts, API throttling, resource unavailability, random crashes, minor OOM, Spot interruptions, S3 transfer errors, container pull timeouts. Tracks `retry_count` for circuit breaker |
| **Fixes** | Schedules `RETRY_TASK` with exponential backoff. For `minor_oom`, incremental memory increase |
| **Retry strategies** | Predefined `RETRY_STRATEGIES` dict per error type with delay formula and resource adjustment |
| **Applies** | Updates `invocation.input_parameters['retry_metadata']` in DB with next retry details, backoff delay, and resource adjustments |
| **Risk level** | LOW |

---

### 8. `SamplesheetFixer`

| Aspect | Detail |
|--------|--------|
| **Detects** | Missing required columns, duplicate sample names, `clipseq`-specific rule violations (same group with multiple `input_name` values) — downloads and parses the samplesheet |
| **Fixes** | Proposes `UPDATE_FILE` actions: unify `input_name` within groups, add missing columns with defaults, remove duplicates |
| **Applies** | Downloads original, applies fixes in memory, uploads `_fixed` version to S3/local path, returns `recommended_params` (e.g., `input: fixed_path`) for workflow restart |
| **Risk level** | LOW–MEDIUM |

---

### 9. `LLMFirstFixer`

| Aspect | Detail |
|--------|--------|
| **Detects** | All error types. Uses Claude Sonnet 4 with an "Error Classification Decision Tree" prompt, few-shot examples. Reads `nextflow.out` + `workflow-trace.txt` + invocation params. Falls back to rule-based detection if LLM quality insufficient |
| **Fixes** | Generates `FixPlan` with `FixAction`s from LLM analysis. For `fixable: false` issues (data quality, corrupted files, permissions), generates detailed `user_guidance` with tool/command examples |
| **Applies** | Returns plan to `AutoFixOrchestrator` → `WorkflowFixApplier`. Dynamically generates user guidance for non-fixable issues via `_generate_dynamic_guidance` |
| **Cost** | ~$0.005–0.01 per analysis; cached after first invocation |
| **Risk level** | Determined by LLM assessment |

---

## Workflow Restarter (`workflow_restarter.py`) — `WorkflowRestarter`

```python
result = restarter.restart_workflow(
    original_invocation_id=738,
    updated_parameters={'max_memory': '32 GB', 'aligner': 'star'},
    auto_start=True,
)
# Returns: {'success': True, 'new_invocation_id': 746}
```

Internally:
1. Reads original invocation's full configuration (100+ parameters)
2. Maps AutoFix generic params → pipeline-specific params via `LLMParameterMapper`:
   - Cache hit: <10 ms, $0
   - First-time LLM mapping: ~3 s, ~$0.005
3. Copies all input dataset associations
4. Calls Galaxy's `build_workflow_run_configs` + `queue_invoke`
5. Returns new invocation ID

---

## Audit Trail

Every fix operation writes to `AIFixAuditLog`:

| Field | Description |
|-------|-------------|
| `invocation_id` | Original workflow invocation |
| `fix_type` | `parameter / data / resource / retry / container` |
| `risk_level` | `LOW / MEDIUM / HIGH` |
| `auto_approved` | Whether auto-approval triggered |
| `user_approved` | Whether user manually approved |
| `success` | Whether fix succeeded |
| `applied_changes` | JSON — before/after values |
| `error_details` | JSON — error if fix failed |
| `create_time` | Timestamp |

---

## API Endpoints

### Trigger AutoFix
```
POST /api/workflows/{invocation_id}/autofix/run
```
Parameters: `auto_approve_low_risk` (default: true), `force_apply` (default: false), `restart_workflow` (default: true)

### Extract Suggested Parameters
```
GET /api/workflows/{invocation_id}/autofix/parameters
```
Returns fix-suggested params converted to a flat key-value dict ready for the Workflow Run Form.

### Real-time Status (for frontend polling)
```
GET /api/workflows/{invocation_id}/realtime/status
```
Returns `RealtimeWorkflowData`: workflow state, detected issues, autofix status, recommendations, restart info, cost estimate.
Recommended frontend polling interval: 5 seconds.

---

## Risk Gate Summary

| Risk Level | Behaviour | Examples |
|------------|-----------|---------|
| `LOW` | Auto-applied immediately | Data format conversion, parameter correction, exponential backoff retry |
| `MEDIUM` | Detected + flagged for user approval | Parameter value changes, resource increases, dataset substitution |
| `HIGH` | Detected + must be explicitly approved + warning shown | Aligner substitution, genome download, exceeding user resource quota |
| `CRITICAL` | Detected + blocked | Would delete data, skip required QC steps |

---

## Performance Benchmarks (from testing)

| Operation | Time |
|-----------|------|
| AutoFix detection (5 fixers, parallel) | 0.03 s |
| LLM parameter mapping (cache hit) | <10 ms |
| LLM parameter mapping (first-time) | ~3 s |
| Workflow restart (Galaxy queue) | ~0.2 s |
| End-to-end (detect + fix + restart) | ~10 s |

---

## Extending AutoFix

To add a new fixer:

```python
# 1. Create your fixer
class MyFixer(BaseAutoFixer):
    def detect_issues(self, context: FixContext) -> List[Dict]:
        # Parse context.error_logs, context.current_params, etc.
        return [{'type': 'my_issue', 'severity': 'error', 'message': '...'}]

    def generate_fix_plan(self, context, issues) -> Optional[FixPlan]:
        actions = [FixAction(action='set_param', param='foo', value='bar', risk=RiskLevel.LOW)]
        return FixPlan(actions=actions, fixable=True, estimated_cost=0.0)

    def apply_fix(self, context, fix_plan, sa_session) -> AutoFixResult:
        context.metadata['updated_parameters']['foo'] = 'bar'
        return AutoFixResult(status=FixStatus.SUCCESS, message='Fixed foo')

# 2. Register in autofix/fixers/__init__.py
from .my_fixer import MyFixer

# 3. Add to the orchestrator's fixer list in nextflow_monitor.py
```
