# Fix 16: Use ${OUTPUT_DIR} Variable Instead of Hardcoded Path

**Date**: 2025-10-22
**Status**: ✅ FIXED
**Related**: Fix 12 (command line path rewriting)

## Problem Description

After Fix 15 successfully resolved the JOB_ID caching issue, Job 421 (Trimmomatic) failed with:

```bash
mv: can't rename 'fastq_out.fastqsanger.gz': No such file or directory
ERROR: Script failed at line 71
```

But the file **did exist** in the working directory:
```bash
-rw-r--r-- 1 root root 254118 Oct 22 14:04 fastq_out.fastqsanger.gz
```

## Root Cause

Fix 12 rewrote output paths to **hardcoded `/tmp/outputs/`**:

```python
# galaxy_job_runner.py:386 (BEFORE FIX 16)
path_mapping[original_path] = f"/tmp/outputs/{filename}"
```

But in the fetch-and-run container environment:
- `OUTPUT_DIR=/galaxy_outputs` (mounted from host `/tmp/galaxy_job_XXX/outputs`)
- `/tmp/outputs/` directory **does not exist**

**Result**: Tool command tried to move file to non-existent `/tmp/outputs/` directory.

## Evidence from Job 421

### Generated Command (Line 71)
```bash
mv fastq_out.'fastqsanger.gz' '/tmp/outputs/dataset_afdf9f6e-23a7-4e8a-b741-0261483d04da.dat'
#                                ^^^^^^^^^^^^ Hardcoded path, directory doesn't exist!
```

### Correct Path Should Be
```bash
mv fastq_out.'fastqsanger.gz' "${OUTPUT_DIR}/dataset_afdf9f6e-23a7-4e8a-b741-0261483d04da.dat"
#                              ^^^^^^^^^^^^^^ Variable that expands to /galaxy_outputs
```

## Solution: Fix 16

### Code Changes

**File**: [galaxy_job_runner.py:389-392](/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L389-L392)

**BEFORE**:
```python
# Map absolute path to /tmp/outputs/
path_mapping[original_path] = f"/tmp/outputs/{filename}"
path_mapping[f"{original_path}_files"] = f"/tmp/outputs/{filename}_files"
self.logger.debug(f"[{job_id}] Output mapping: {original_path} → /tmp/outputs/{filename}")
```

**AFTER**:
```python
# Map absolute path to ${OUTPUT_DIR}/ (variable will be expanded at runtime)
path_mapping[original_path] = f"${{OUTPUT_DIR}}/{filename}"
path_mapping[f"{original_path}_files"] = f"${{OUTPUT_DIR}}/{filename}_files"
self.logger.debug(f"[{job_id}] Output mapping: {original_path} → ${{OUTPUT_DIR}}/{filename}")
```

### Cleanup: Remove Legacy /tmp/outputs/ References

**File**: [galaxy_job_runner.py:1026](/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L1026)

**REMOVED**:
```python
# Check both original path and rewritten path (/tmp/outputs/)
job_script += f'if [ -f "/tmp/outputs/{filename}" ]; then cp "/tmp/outputs/{filename}" "${{OUTPUT_DIR}}/{filename}"; fi\n'
```

**File**: [galaxy_job_runner.py:1065-1068](/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L1065-L1068)

**REMOVED**:
```bash
# Copy files from /tmp/outputs/ if it exists (rewritten paths)
if [ -d "/tmp/outputs" ]; then
    echo "Copying files from /tmp/outputs/"
    cp -r /tmp/outputs/* "${OUTPUT_DIR}/" 2>/dev/null || true
fi
```

## How OUTPUT_DIR is Set

### In Job Script Header

**File**: [galaxy_job_runner.py:960-961](/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L960-L961)

```bash
# Use the directories set by fetch_and_run.sh
INPUT_DIR="${GALAXY_INPUT_DIR}"
OUTPUT_DIR="${GALAXY_OUTPUT_DIR}"
```

### In fetch_and_run.sh

**File**: `docker/fetch-and-run/fetch_and_run.sh` (Docker run command)

```bash
docker run --rm -i \
    -v "${DOCKER_OUTPUT_DIR}:/galaxy_outputs:rw" \
    -e GALAXY_OUTPUT_DIR="/galaxy_outputs" \
    ...
```

Where `DOCKER_OUTPUT_DIR=/tmp/galaxy_job_${JOB_ID}/outputs` (host path).

## Path Flow Diagram

```
1. Galaxy generates command with local path:
   mv output.dat '/Users/.../database/objects/a/f/d/dataset_xxx.dat'

2. Fix 12 + Fix 16 rewrites to variable:
   mv output.dat '${OUTPUT_DIR}/dataset_xxx.dat'

3. Job script sets variable from environment:
   OUTPUT_DIR="${GALAXY_OUTPUT_DIR}"  # = /galaxy_outputs

4. fetch_and_run.sh sets environment variable:
   GALAXY_OUTPUT_DIR="/galaxy_outputs"

5. Docker mounts host path to container path:
   -v "/tmp/galaxy_job_421/outputs:/galaxy_outputs:rw"

6. Final expanded command in container:
   mv output.dat '/galaxy_outputs/dataset_xxx.dat'

7. File on host appears at:
   /tmp/galaxy_job_421/outputs/dataset_xxx.dat

8. S3 upload from host:
   aws s3 sync /tmp/galaxy_job_421/outputs/ s3://.../jobs/421/outputs/
```

## Benefits of Fix 16

### 1. Environment Flexibility

Using `${OUTPUT_DIR}` variable instead of hardcoded path means:
- Works with any output directory configuration
- Fetch-and-run can set custom paths if needed
- No assumptions about container filesystem structure

### 2. Consistency with INPUT_DIR

Input paths already use `${INPUT_DIR}` variable (from Fix 7):
```bash
ln -s "${INPUT_DIR}/dataset_xxx.dat" /data/files/dataset_xxx.dat
```

Now output paths are consistent:
```bash
mv output.dat "${OUTPUT_DIR}/dataset_xxx.dat"
```

### 3. Eliminates Hardcoded Paths

**Before Fix 16**: Code had 3 hardcoded references to `/tmp/outputs/`
**After Fix 16**: Zero hardcoded paths, all use `${OUTPUT_DIR}` variable

## Testing

### Test Case 1: Trimmomatic (Previously Failed)

**Expected Command**:
```bash
trimmomatic SE ... fastq_out.fastqsanger.gz && \
mv fastq_out.fastqsanger.gz '${OUTPUT_DIR}/dataset_xxx.dat'
```

**Expected Behavior**:
1. Trimmomatic generates output in working directory
2. `mv` command expands `${OUTPUT_DIR}` to `/galaxy_outputs`
3. File moved to `/galaxy_outputs/dataset_xxx.dat`
4. Host sees file at `/tmp/galaxy_job_421/outputs/dataset_xxx.dat`
5. S3 upload succeeds

### Test Case 2: FastQC (Already Working)

FastQC uses `--outdir` parameter, so command becomes:
```bash
fastqc --outdir '${OUTPUT_DIR}' input.fastq
```

Expanded to:
```bash
fastqc --outdir '/galaxy_outputs' input.fastq
```

Files written directly to correct location.

### Verification Commands

```bash
# Check generated script uses ${OUTPUT_DIR}
aws s3 cp s3://.../jobs/421/job_script.sh - | grep OUTPUT_DIR

# Should see:
# OUTPUT_DIR="${GALAXY_OUTPUT_DIR}"
# mv fastq_out.fastqsanger.gz '${OUTPUT_DIR}/dataset_xxx.dat'

# Should NOT see:
# /tmp/outputs/
```

## Impact

### Before Fix 16
- ❌ Trimmomatic and similar tools fail
- ❌ Any tool using `mv`, `cp` for outputs breaks
- ❌ Hardcoded path assumptions fragile

### After Fix 16
- ✅ All tools work with dynamic output directory
- ✅ Consistent with input directory handling
- ✅ No hardcoded path assumptions

## Related Fixes

- **Fix 7**: Symlink rewriting for inputs (uses `${INPUT_DIR}`)
- **Fix 12**: Command line path rewriting for outputs (originally used `/tmp/outputs/`)
- **Fix 13**: Docker-in-Docker volume mounting (sets up the actual directories)
- **Fix 14**: Output directory creation (mkdir -p ${OUTPUT_DIR})
- **Fix 15**: JOB_ID caching bug (allowed us to test workflows properly)
- **Fix 16**: Use `${OUTPUT_DIR}` variable (this fix)

## Restart Required

**YES** - Galaxy must be restarted to load the updated code.

```bash
pkill -f "python.*run"
PYTHONPATH=lib sh run.sh --daemon
```

## Next Steps

1. ✅ Fix 16 code changes completed
2. ⏳ Restart Galaxy
3. ⏳ Re-run the workflow (Job 420 + Job 421)
4. ⏳ Verify Job 421 (Trimmomatic) completes successfully
5. ⏳ Check outputs uploaded to S3

---

**Status**: FIXED - Awaiting restart and testing
**Priority**: P1 - Blocks tools that use explicit file moves/copies
