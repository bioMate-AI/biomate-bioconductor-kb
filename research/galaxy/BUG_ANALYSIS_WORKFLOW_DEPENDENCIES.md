# Bug Analysis: Workflow Intermediate Dependencies Not Being Uploaded

## Date
2025-10-30

## Problem Summary
When running a multi-step workflow in AWS cloud execution mode, jobs fail with errors like:
```
sed: can't read /galaxy_execution/datasets/objects/5/b/8/dataset_5b8e2a2f-33a8-4d1a-8dec-5f2287e63e38.dat: No such file or directory
```

## Root Cause

There are **TWO separate bugs** causing this failure:

### Bug #1: NoneType Error in Dataset Download
**Location:** `galaxy_job_runner.py:1474`

**Problem:**
```python
s3_bucket = self.app.config.object_store_config.get('config', {}).get('s3_bucket')
```
When `object_store_config` is `None`, calling `.get('config', {})` on `None` raises:
```
TypeError: 'NoneType' object has no attribute 'get'
```

**Impact:**
- Job completes successfully in AWS Batch
- But Galaxy fails to download the output datasets from S3
- Output files remain 0 bytes locally
- Downstream jobs see empty input files

**Logs:**
```
[866] Failed to download datasets from S3: 'NoneType' object has no attribute 'get'
```

### Bug #2: Workflow Step Dependencies Not Enforced
**Problem:**
- Job 866 (Create text file) starts at 13:06:58
- Job 867 (Text transformation/sed) starts at 13:10:15
- Job 867's input file (dataset_5b8e2a2f...) is **0 bytes**
- This is Job 866's output, but Job 866 hasn't finished downloading results from S3 yet

**Timeline:**
```
13:06:58 - Job 866 queued (Create text file)
13:07:10 - Job 866 submitted to AWS Batch
13:10:15 - Job 867 queued (Text transformation) - INPUT FILE IS 0 BYTES!
13:10:17 - Job 867 submitted with empty input file
13:10:14 - Job 866 download fails with NoneType error
```

**Why This Happens:**
1. Galaxy's job handler checks that input datasets are in "ok" state before queueing
2. Dataset 1198 (Job 866's output) was marked as "ok" because Job 866 submitted successfully
3. But the **actual file content** (0 bytes) wasn't checked
4. Job 867 gets queued with a valid dataset ID but an empty file

## The Fix

### Fix #1: Robust S3 Configuration Handling
**File:** `galaxy_job_runner.py` lines 1470-1510

**Changes:**
```python
# Get S3 configuration - try multiple sources
s3_bucket = None
aws_region = 'us-west-2'

# Try 1: object_store_config (if using S3 object store)
if hasattr(self.app.config, 'object_store_config') and self.app.config.object_store_config:
    object_store_cfg = self.app.config.object_store_config
    if isinstance(object_store_cfg, dict):
        config_section = object_store_cfg.get('config', {})
        s3_bucket = config_section.get('s3_bucket')
        aws_region = config_section.get('s3_region', aws_region)

# Try 2: job destination params (fallback)
if not s3_bucket:
    job_dest = job_wrapper.job_destination
    s3_bucket = job_dest.params.get('s3_bucket') or job_dest.params.get('aws_s3_bucket')
    aws_region = job_dest.params.get('aws_region', aws_region)

# Try 3: Use the stored bucket from job submission
if not s3_bucket and hasattr(job_wrapper, '_fetch_and_run_s3_bucket'):
    s3_bucket = job_wrapper._fetch_and_run_s3_bucket
    aws_region = job_wrapper._fetch_and_run_aws_region

if s3_bucket:
    # Download datasets from S3
    ...
else:
    self.logger.warning(f"[{job_id}] No S3 bucket configured - cannot download datasets from cloud")
```

**Benefits:**
1. Gracefully handles missing `object_store_config`
2. Falls back to job destination parameters
3. Uses stored S3 bucket from job submission
4. Clear logging when S3 is not configured

### Fix #2: Wait for Previous Job Outputs
**Status:** This is a Galaxy workflow scheduling issue, not our code bug

**Current Behavior:**
- Galaxy only checks dataset **state** (ok/error/paused)
- It doesn't check if file **content** exists

**Potential Solutions:**
1. **Option A:** Add file size check in Galaxy's job handler
   - Before queueing, verify input files are not empty
   - Pro: Prevents wasted cloud resources
   - Con: Requires Galaxy core modification

2. **Option B:** Implement retry logic in cloud executor
   - If input file is 0 bytes, wait and retry
   - Pro: No Galaxy core changes needed
   - Con: Wastes cloud resources on failed attempts

3. **Option C (RECOMMENDED):** Sequential workflow execution
   - Don't run workflow steps in parallel
   - Wait for each step to fully complete (including download) before starting next
   - Pro: Guaranteed correctness
   - Con: Slower workflow execution

## Testing Results

### Before Fix:
```
Job 866: FAILED - NoneType error during dataset download
Job 867: FAILED - Input file is 0 bytes (sed can't read file)
```

### After Fix:
Job 866 should now:
1. ✅ Complete successfully in AWS Batch
2. ✅ Download output datasets from S3 without errors
3. ✅ Output files have correct content (not 0 bytes)

Job 867 should:
- Wait for Job 866 to fully complete before starting
- Have valid input files with actual content

## Recommendation

**Immediate Action:**
- ✅ Fix #1 is implemented and deployed

**Future Improvement:**
Implement workflow step synchronization:
```python
# In queue_job(), before submitting cloud job:
for input_assoc in job.input_datasets:
    if input_assoc.dataset and input_assoc.dataset.dataset:
        file_path = input_assoc.dataset.dataset.get_file_name()
        if Path(file_path).stat().st_size == 0:
            # File is empty - previous job hasn't finished downloading
            self.logger.warning(f"Input file {file_path} is empty, job may be premature")
            # Option: delay submission, or mark as waiting
```

## Impact
- **Severity:** High - Blocks all multi-step workflows
- **Affected Users:** All workflows with 2+ steps using cloud execution
- **Workaround:** Run workflow steps one at a time manually
- **Fix Complexity:** Low (Fix #1), Medium (Fix #2)

## Related Files
- `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py` (lines 1470-1520)
- `docker/fetch-and-run/fetch_and_run.sh` (dataset download logic)
