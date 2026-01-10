# Fix 15: Critical Job ID Caching Bug

**Date**: 2025-10-22
**Severity**: 🔴 **CRITICAL**
**Impact**: All workflow jobs were executing with incorrect JOB_ID, causing data corruption and upload failures

## Problem Description

User discovered that multiple jobs in a workflow (Jobs 417, 418, 419) all executed with **JOB_ID=416**, causing:

1. ❌ All jobs downloaded the wrong job script (`jobs/416/job_script.sh`)
2. ❌ All jobs attempted to upload to the same S3 path (`jobs/416/outputs/`)
3. ❌ First job failed (output directory not found)
4. ⚠️ Subsequent jobs succeeded by overwriting previous outputs
5. ❌ **Complete data loss** for jobs 417, 418, 419

## Root Cause

### AWS Batch Job Definition Caching

File: [executor.py:232-246](/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/providers/aws/executor.py#L232-L246)

```python
def _generate_job_def_key(self, job_spec: JobSpec) -> str:
    """Generate a stable key for job definition caching."""
    # Create hash from job requirements
    key_data = {
        'image': job_spec.container.image,
        'cpus': job_spec.resources.cpus,
        'memory': job_spec.resources.memory_mb,
        'gpu': job_spec.resources.gpu,
        'privileged': job_spec.container.privileged,
    }
    key_str = json.dumps(key_data, sort_keys=True)
    return hashlib.md5(key_str.encode()).hexdigest()[:8]
```

**Issue**: Job definition is cached based on image + resources, **not including environment variables**.

### Environment Variables in Job Definition

File: [executor.py:266-269](/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/providers/aws/executor.py#L266-L269)

```python
# Environment variables
if job_spec.container.env:
    container_props['environment'] = [
        {'name': k, 'value': v} for k, v in job_spec.container.env.items()
    ]
```

**Issue**: Environment variables including `JOB_ID` were baked into job definition, then cached.

### Conditional Override Logic

File: [executor.py:422-436](/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/providers/aws/executor.py#L422-L436) (BEFORE FIX)

```python
# Job parameters
if job_spec.container.command or job_spec.container.args:
    container_overrides = {}

    if job_spec.container.command:
        container_overrides['command'] = job_spec.container.command
    elif job_spec.container.args:
        container_overrides['command'] = job_spec.container.args

    if job_spec.container.env:
        container_overrides['environment'] = [
            {'name': k, 'value': v} for k, v in job_spec.container.env.items()
        ]

    submit_request['containerOverrides'] = container_overrides
```

**Issue**: Environment overrides only set **if command or args exist**. Fetch-and-run container uses ENTRYPOINT (no command), so env vars were never overridden!

## Execution Timeline (Job 417, 418, 419)

### Job 416 (First job, created job definition)

```
17:24:09 - Galaxy submits Job 416
17:24:20 - AWS Batch job submitted (f78ef50a)
AWS creates job definition with:
  - Image: fetch-and-run:latest
  - Environment: JOB_ID=416, JOB_SCRIPT_S3_URL=s3://.../jobs/416/job_script.sh
Job definition cached with key: hash(image+cpu+mem)
```

### Job 417 (Reuses cached job definition)

```
17:35:42 - Galaxy submits Job 417 with JOB_ID=417
17:35:52 - AWS Batch job submitted (4f6e3cb1)
AWS reuses cached job definition from Job 416!
  - Image: fetch-and-run:latest (match!)
  - CPU/Memory: same (match!)
  - containerOverrides: EMPTY (no command, so env not overridden)
Result: Job 417 executes with JOB_ID=416 ❌
```

### Job 418 (Same issue)

```
17:35:42 - Galaxy submits Job 418 with JOB_ID=418
17:35:52 - AWS Batch job submitted (c7f28eed)
Result: Job 418 executes with JOB_ID=416 ❌
```

### Job 419 (Same issue)

```
17:38:56 - Galaxy submits Job 419 with JOB_ID=419
17:39:01 - AWS Batch job submitted (a8fc6259)
Result: Job 419 executes with JOB_ID=416 ❌
```

## Evidence

### AWS Batch Job Inspection

```bash
$ aws batch describe-jobs --jobs 4f6e3cb1-14b4-43d2-9165-ce766cb8fc9f \
    | jq '.jobs[0].container.environment[] | select(.name == "JOB_ID")'
{
  "name": "JOB_ID",
  "value": "416"  ← Should be 417!
}
```

### S3 Job Script Paths

```bash
$ aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive | grep job_script.sh
jobs/416/job_script.sh  ← Created by Job 416
jobs/417/job_script.sh  ← Created by Job 417 (but never used!)
jobs/418/job_script.sh  ← Created by Job 418 (but never used!)
jobs/419/job_script.sh  ← Created by Job 419 (but never used!)
```

### CloudWatch Logs (All 3 jobs)

```
Job ID: 416  ← Wrong!
Script URL: s3://galaxy-cloud-data-1760241377/jobs/416/job_script.sh  ← Wrong!
```

## Solution: Fix 15

### Code Changes

File: [executor.py:421-443](/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/providers/aws/executor.py#L421-L443)

**BEFORE**:
```python
# Job parameters
if job_spec.container.command or job_spec.container.args:
    container_overrides = {}
    # ... set command ...
    if job_spec.container.env:
        container_overrides['environment'] = [...]
    submit_request['containerOverrides'] = container_overrides
```

**AFTER**:
```python
# Job parameters
# CRITICAL FIX 15: Always use containerOverrides for environment variables
# Even if there's no command/args, we need to override env vars per job
container_overrides = {}

if job_spec.container.command:
    container_overrides['command'] = job_spec.container.command
elif job_spec.container.args:
    container_overrides['command'] = job_spec.container.args

# ALWAYS set environment variables as override (Fix 15)
# This ensures each job gets its unique JOB_ID, not cached values
if job_spec.container.env:
    container_overrides['environment'] = [
        {'name': k, 'value': str(v)} for k, v in job_spec.container.env.items()
    ]
    logger.debug(f"Setting {len(job_spec.container.env)} environment variable(s) for job {job_spec.job_id}")

# Only add containerOverrides if there's something to override
if container_overrides:
    submit_request['containerOverrides'] = container_overrides
```

### Key Changes

1. ✅ **Unconditionally create `container_overrides`** dict
2. ✅ **Always set environment variables** as overrides (moved outside command/args condition)
3. ✅ **Added debug logging** to track env var setting
4. ✅ **Convert values to string** (`str(v)`) to handle numeric job IDs

## Expected Behavior After Fix

### Job Definition Creation (Job 416)

```
AWS Batch Job Definition: galaxy-cloud-executor-abc123
  - Image: fetch-and-run:latest
  - CPU: 2, Memory: 4096
  - Environment: (empty or defaults only)
```

### Job Submission (Job 417)

```
AWS Batch submit_job:
  - jobDefinition: galaxy-cloud-executor-abc123 (reused)
  - containerOverrides:
      environment:
        - JOB_ID: "417"  ← Correct!
        - JOB_SCRIPT_S3_URL: "s3://.../jobs/417/job_script.sh"  ← Correct!
        - S3_BUCKET: "galaxy-cloud-data-1760241377"
        - AWS_REGION: "us-west-2"
```

### Execution Result

```
Container logs:
Job ID: 417  ← Correct!
Script URL: s3://.../jobs/417/job_script.sh  ← Correct!
Output path: /host-tmp/galaxy_job_417/outputs/  ← Correct!
```

## Testing Plan

### Test 1: Simple Sequential Workflow

Run a 3-step workflow:
1. FastQC (Job N)
2. Trimmomatic (Job N+1)
3. FastQC (Job N+2)

**Expected**:
- Each job uses its own JOB_ID
- Each job downloads its own job_script.sh
- Each job uploads to its own S3 output path

**Verification**:
```bash
# Check AWS Batch environment variables
for job_id in $(aws batch list-jobs --job-queue galaxy-cloud-queue --max-items 3 --query 'jobSummaryList[*].jobId' --output text); do
  echo "=== Job $job_id ==="
  aws batch describe-jobs --jobs $job_id | jq '.jobs[0].container.environment[] | select(.name == "JOB_ID")'
done

# Check S3 outputs
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive | grep outputs
```

### Test 2: Parallel Jobs

Run 3 FastQC jobs in parallel (same tool, same resources).

**Expected**:
- All 3 jobs share the same job definition (cached)
- But each has unique JOB_ID via containerOverrides

### Test 3: Verify CloudWatch Logs

Each job's log should show:
```
Job ID: <correct_job_id>
Script URL: s3://.../jobs/<correct_job_id>/job_script.sh
```

## Impact Assessment

### Before Fix 15

- ❌ Workflow execution completely broken
- ❌ Data loss (outputs overwrite each other)
- ❌ Impossible to debug (logs show wrong job IDs)
- ❌ Cannot run multi-step workflows

### After Fix 15

- ✅ Each job executes with correct JOB_ID
- ✅ Each job uses its own script and data paths
- ✅ Workflow dependencies work correctly
- ✅ Logs are accurate and debuggable

## Related Issues

- **Fix 13**: Docker-in-Docker volume mounting (solved file visibility)
- **Fix 14**: Output directory creation (attempted to fix upload failures)
- **Fix 15**: JOB_ID caching (root cause of all these issues!)

Fix 15 reveals that Fix 14 was addressing a **symptom**, not the root cause. The output upload failures happened because multiple jobs were trying to use the same output path due to incorrect JOB_ID.

## Restart Required

**YES** - Galaxy must be restarted to load the updated executor code.

```bash
sh run.sh --stop
PYTHONPATH=lib sh run.sh --daemon
```

## Next Steps

1. ✅ Fix 15 code changes completed
2. ⏳ Restart Galaxy
3. ⏳ Run test workflow (3 steps minimum)
4. ⏳ Verify each job has correct JOB_ID
5. ⏳ Verify outputs uploaded to correct S3 paths
6. ⏳ Confirm workflow completes successfully end-to-end

---

**Status**: FIXED - Awaiting restart and testing
**Priority**: P0 - Blocks all workflow execution
**Credit**: User discovered the issue by observing CloudWatch logs showing duplicate Job IDs
