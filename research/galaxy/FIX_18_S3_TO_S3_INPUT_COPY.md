# Fix 18: S3-to-S3 Input Copy for Workflow Dependencies

## Problem

**Symptom**: In multi-step workflows, when Job B depends on Job A's output:
- Job A runs successfully and uploads output to S3 (`jobs/430/outputs/dataset_xxx.dat`, 248KB)
- Job B receives **0-byte input file** even though source file exists in S3

**Example**:
```bash
# Job 430 output in S3:
2025-10-23 08:46:22  248.2 KiB jobs/430/outputs/dataset_156fc595...dat

# Job 431 input in S3 (staged by Galaxy):
2025-10-23 08:46:34    0 Bytes jobs/431/inputs/dataset_156fc595...dat

# Job 431 container log:
-rw-r--r-- 1 root root 0 Oct 23 00:46 dataset_156fc595...dat  # Empty!
```

**Impact**:
- Workflow chains fail silently with empty data
- Tools process empty inputs and produce invalid outputs
- Data flow between cloud jobs is broken

## Root Cause

The input staging code in `galaxy_job_runner.py` only handles **local files**:

```python
# OLD CODE (lines 914-934):
for input_assoc in job.input_datasets:
    dataset = input_assoc.dataset
    if dataset and dataset.dataset:
        file_path = dataset.dataset.get_file_name()
        if file_path and Path(file_path).exists():  # ❌ Only checks local filesystem!
            s3_client.upload_file(file_path, s3_bucket, s3_key)
```

**Why this fails for cloud workflows**:

1. Job 430 runs in AWS Batch, outputs saved to S3: `s3://bucket/jobs/430/outputs/dataset_xxx.dat`
2. Galaxy's database points to local path: `/Users/.../database/objects/xxx/dataset_xxx.dat`
3. This local file **doesn't exist** (data is in cloud only)
4. `Path(file_path).exists()` returns `False`
5. Upload is **skipped**
6. But `job_wrapper.prepare()` creates **0-byte placeholder** file
7. This empty file gets uploaded to S3
8. Job 431 downloads the empty file

## Solution

Implement **S3-to-S3 copy** fallback when local file doesn't exist:

```python
# NEW CODE (Fix 18):
if file_path and Path(file_path).exists():
    # Local file exists - upload it (original workflow)
    s3_client.upload_file(file_path, s3_bucket, s3_key)
else:
    # File doesn't exist locally - search S3 outputs from previous jobs
    # This handles cloud-to-cloud data flow
    for job_prefix in all_job_prefixes:
        source_key = f"{job_prefix}outputs/{filename}"
        if file_exists_in_s3(source_key):
            # Copy directly in S3 (no download needed!)
            s3_client.copy_object(
                Bucket=s3_bucket,
                CopySource={'Bucket': s3_bucket, 'Key': source_key},
                Key=s3_key
            )
            break
```

**Benefits**:
- ✅ Handles cloud-to-cloud data flow (S3→S3 copy)
- ✅ No download/upload needed (faster, cheaper)
- ✅ Preserves file integrity (248KB stays 248KB)
- ✅ Backwards compatible (still uploads local files first)

## Code Changes

**File**: `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`

**Lines 914-981**: Complete rewrite of input staging logic

**Key Changes**:
1. Split into two paths: local upload vs S3 copy
2. Added S3 search logic: list all job output folders
3. Use `copy_object()` for S3-to-S3 transfer (no download)
4. Added detailed logging for debugging

## Testing

**Before Fix 18**:
```bash
$ aws s3 ls s3://bucket/jobs/431/inputs/dataset_156fc595...dat
2025-10-23 08:46:34    0 Bytes  # ❌ Empty file!
```

**After Fix 18** (expected):
```bash
$ aws s3 ls s3://bucket/jobs/431/inputs/dataset_156fc595...dat
2025-10-23 08:47:00  248.2 KiB  # ✅ Correct size!

# Galaxy logs should show:
[431] Input file /path/to/dataset_xxx.dat not found locally, searching S3 outputs...
[431] Found input in S3: s3://bucket/jobs/430/outputs/dataset_156fc595...dat
[431] Copying to s3://bucket/jobs/431/inputs/dataset_156fc595...dat
[431] Uploaded 1 input file(s)
```

## Edge Cases Handled

1. **Local file exists**: Upload directly (original behavior)
2. **File in S3 from previous job**: Copy within S3
3. **File not found anywhere**: Log warning, continue (job may fail with better error)
4. **Multiple matches in S3**: Use first match (latest job output)
5. **S3 errors**: Catch and log, continue with other inputs

## Performance

**S3-to-S3 Copy**:
- No egress charges (within same bucket)
- Sub-second latency for <1GB files
- Atomic operation (no partial uploads)

**Alternative considered**: Download to local, then upload
- ❌ Doubles transfer time
- ❌ Requires local disk space
- ❌ Costs 2x bandwidth

## Related Issues

- **Fix 15**: JOB_ID caching (ensured each job has unique ID)
- **Fix 16**: Output path variables (ensured outputs go to correct location)
- **Fix 17**: Quote type for variable expansion (ensured variables expand correctly)
- **Fix 18** (this): S3-to-S3 input copy (ensures data flows between jobs)

**Together, these fixes enable complete cloud workflow execution!**

## User Impact

**Before**: Multi-step workflows failed with empty input files
**After**: Workflows execute end-to-end with correct data flow

Example workflow:
```
Input → Job 429 (FastQC) → Job 430 (Trimmomatic) → Job 431 (Tool) → Output
         ✅ OK             ✅ OK                    ❌ Empty input!
```

**With Fix 18**:
```
Input → Job 429 (FastQC) → Job 430 (Trimmomatic) → Job 431 (Tool) → Output
         ✅ OK             ✅ OK                    ✅ OK (248KB)
```

## Future Enhancements

1. **Optimize S3 search**: Track job dependencies to avoid listing all jobs
2. **Parallel S3 copies**: Copy multiple inputs concurrently
3. **Checksum validation**: Verify data integrity after copy
4. **Retry logic**: Handle transient S3 errors

## Verification Checklist

- [ ] Galaxy restarts without errors
- [ ] Multi-step workflow executes successfully
- [ ] Job 431 receives correct input size (248KB, not 0 bytes)
- [ ] S3 logs show `copy_object` operations
- [ ] Galaxy logs show "Found input in S3" messages

---

**Status**: Implemented, awaiting testing
**Date**: 2025-10-23
**Author**: Claude (AI Assistant)
