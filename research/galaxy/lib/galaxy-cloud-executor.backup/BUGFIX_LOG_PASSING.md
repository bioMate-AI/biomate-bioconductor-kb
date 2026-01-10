# Bug Fix: Pass Tool Output Logs to Galaxy

## Problem

**File**: `galaxy_cloud/galaxy_workflow/galaxy_job_runner.py:359`

When a cloud job completes successfully, the logs (stdout/stderr) are retrieved from CloudWatch but NOT passed to Galaxy. This means users cannot see tool output in the Galaxy UI.

**Current code (line 359)**:
```python
job_wrapper.finish("", "")  # ← Empty strings!
```

## Root Cause

The code retrieves logs from CloudWatch successfully:
- `AWSBatchExecutor.get_job_result()` calls `_get_job_logs()`
- Logs are stored in `result.stdout` and `result.stderr`
- But line 359 passes empty strings instead of using these values

## Solution

Change line 359 to pass the actual logs:

```python
# Before (INCORRECT):
job_wrapper.finish("", "")

# After (CORRECT):
job_wrapper.finish(result.stdout or "", result.stderr or "")
```

## Verification

After the fix:
1. Tool stdout/stderr will be visible in Galaxy WebUI
2. Users can download log files
3. User experience will be identical to local execution

## Test Cases

1. **Successful job with output**:
   - Run FastQC tool
   - Expected: See "Started analysis of sample.fastq..." in Galaxy UI

2. **Failed job with error**:
   - Run tool with missing input
   - Expected: See error message in Galaxy UI

3. **Empty output**:
   - Run tool that produces no output
   - Expected: Empty log display (no errors)
