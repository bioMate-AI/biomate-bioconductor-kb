# Workflow Execution Order Investigation

**Date**: 2025-10-22
**Issue**: Multiple containers executing with same Job ID, output upload failures

## Problem Statement

User reported running a "complete workflow" and observing 3 container logs all labeled as "Job ID: 416", with inconsistent results:
- Container 1: Failed to upload outputs (directory not found)
- Container 2: Successfully uploaded 3 files
- Container 3: Successfully uploaded 3 files

User suspects: **Jobs may not be executing in the correct workflow order, causing dependency issues.**

## Investigation Findings

### 1. Galaxy Job Submission Timeline

From `logs/galaxy_startup_20251022_172127.log`:

```
17:24:09 - Job 416 submitted (input: dataset 678:ok)
17:35:42 - Job 417 submitted (input: dataset 200:ok)
17:35:42 - Job 418 submitted (input: dataset 200:ok)
17:38:56 - Job 419 submitted (input: dataset 683:ok)
```

**Observation**:
- 4 separate jobs were submitted
- All had input datasets in `ok` state before submission
- Jobs were submitted **sequentially** with delays (11 min, 0 sec, 3 min)

### 2. Container Execution Timeline

From CloudWatch logs provided by user (all show "Job ID: 416"):

```
Container 1: Started 09:38:22 UTC (17:38:22 local) - Upload FAILED
Container 2: Started 09:38:22 UTC (17:38:22 local) - Upload SUCCESS
Container 3: Started 09:39:04 UTC (17:39:04 local) - Upload SUCCESS
```

**Discrepancy**:
- Galaxy submitted Job 416 at **17:24:09**
- Containers started at **17:38:22** (14 minutes later!)
- This timestamp aligns with **Job 419** submission (17:38:56)

### 3. Hypothesis: Log Stream Confusion

**Possibility A**: User provided logs from different jobs (417, 418, 419) but all displayed "Job ID: 416"
- Cause: S3 script reuse - all jobs may download the same `jobs/416/job_script.sh`
- Result: Job script internally references Job ID 416 even when executed by Job 419

**Possibility B**: AWS Batch retry mechanism
- AWS Batch has 1 attempt per job (verified: `attempts: 1`)
- Cannot explain 3 containers for 1 job

**Possibility C**: Multiple compute environments running same job
- Unlikely: Only one job queue configured

## Key Questions

### Q1: Are the 3 containers actually different jobs?

Need to check:
```bash
# Get AWS Batch job IDs for each Galaxy job
grep "Submitted job.*to AWS Batch" logs/galaxy_startup_20251022_172127.log

# Then check CloudWatch log streams for each AWS Batch ID
```

### Q2: Why do all logs show "Job ID: 416"?

Need to examine:
- How JOB_ID environment variable is set in fetch-and-run
- Whether job scripts are cached/reused incorrectly

### Q3: Is there a workflow dependency tracking issue?

Current code in `galaxy_job_runner.py:248-257`:
```python
# Log input dataset states for debugging workflow dependencies
input_info = []
for dataset_assoc in job.input_datasets:
    if dataset_assoc.dataset:
        input_info.append(
            f"{dataset_assoc.dataset.hid}:{dataset_assoc.dataset.state}"
        )
self.logger.info(
    f"Queueing job {job_wrapper.get_id_tag()} with input datasets: {input_info}"
)
```

This shows Galaxy **does** check input dataset states before queueing jobs.

## Root Cause Analysis

### Most Likely Cause: Job Script Caching Issue

**Problem**: Each job downloads its script from S3 path `s3://.../jobs/{JOB_ID}/job_script.sh`

**If Job 417, 418, 419 all reference the wrong script path**, they would:
1. Download `jobs/416/job_script.sh` instead of their own
2. Execute with hardcoded references to Job 416
3. Attempt to upload to `jobs/416/outputs/` instead of their own paths

**Evidence**:
- All 3 containers show identical "Job ID: 416" in logs
- Containers 2 and 3 succeed because they overwrite Container 1's outputs
- First container fails because output directory doesn't exist yet

### Code to Investigate

File: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

Line ~700-800: Where S3 paths are generated for job script upload

```python
# Need to verify this uses correct job_id, not hardcoded value
script_s3_key = f"jobs/{job_id}/job_script.sh"
```

File: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/providers/aws/executor.py`

Line ~200: Where JOB_SCRIPT_S3_URL environment variable is set

```python
# Need to verify this uses correct job_spec.job_id
env_vars = {
    'JOB_SCRIPT_S3_URL': f"s3://{bucket}/jobs/{job_spec.job_id}/job_script.sh",
    'JOB_ID': str(job_spec.job_id),
    ...
}
```

## Testing Plan

### Test 1: Verify Job ID Propagation

Add debug logging to track job IDs through the entire flow:

1. In `galaxy_job_runner.py` before S3 upload:
   ```python
   self.logger.info(f"Uploading job script for Job {job_id} to s3://{bucket}/jobs/{job_id}/job_script.sh")
   ```

2. In `aws/executor.py` when setting env vars:
   ```python
   logger.info(f"Setting JOB_ID={job_spec.job_id} for AWS Batch job")
   ```

3. In `fetch_and_run.sh` at start:
   ```bash
   echo "DEBUG: JOB_ID from environment: ${JOB_ID}"
   echo "DEBUG: JOB_SCRIPT_S3_URL: ${JOB_SCRIPT_S3_URL}"
   ```

### Test 2: Check S3 Upload Paths

Verify each job uploads to its own S3 path:

```bash
aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive | grep "job_script.sh"
# Should see:
# jobs/416/job_script.sh
# jobs/417/job_script.sh
# jobs/418/job_script.sh
# jobs/419/job_script.sh
```

### Test 3: Run Simple Sequential Workflow

Create a 2-step workflow:
1. Tool A: Generate output file
2. Tool B: Read output from Tool A

Expected behavior:
- Job N+1 should only start after Job N completes
- Job N+1 should download input from `jobs/N/outputs/`

## Immediate Action Items

1. Check S3 bucket for job script paths:
   ```bash
   aws s3 ls s3://galaxy-cloud-data-1760241377/jobs/ --recursive | grep -E "jobs/(416|417|418|419)"
   ```

2. Check AWS Batch job names to correlate with Galaxy jobs:
   ```bash
   grep "AWS Batch with ID" logs/galaxy_startup_20251022_172127.log
   ```

3. Verify CloudWatch log streams correspond to correct AWS Batch jobs

4. If scripts are cached incorrectly, add unique identifiers to each script:
   ```bash
   echo "### This script is for Galaxy Job ${JOB_ID} ###" >> job_script.sh
   ```

## Expected Resolution

If the issue is job script path confusion:
- **Fix**: Ensure each job uploads and downloads from its own unique S3 path
- **Verify**: Each job's CloudWatch log shows correct JOB_ID
- **Test**: Run workflow and confirm sequential execution with correct data flow

If the issue is workflow dependency tracking:
- **Fix**: Add explicit job state checking before submission
- **Verify**: Jobs only start after dependencies complete
- **Test**: Run workflow with artificial delays to test dependency enforcement

---

**Next Steps**:
1. User to provide AWS Batch job IDs for jobs 416-419
2. Check S3 bucket structure for job-specific paths
3. Add debugging to job ID propagation
4. Rerun workflow with enhanced logging
