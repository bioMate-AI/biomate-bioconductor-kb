# Fix 14: Output File Copy Issue in Tool Container

**Date**: 2025-10-22
**Status**: 🔧 IN PROGRESS
**Previous Fix**: Fix 13 (Docker-in-Docker volume mounting) ✅ WORKING

## Problem Description

After Fix 13 successfully solved the Docker-in-Docker file mounting issue, a new problem was discovered: **output files are not being uploaded to S3** even though the tool executes successfully and generates outputs.

### Symptoms

From AWS Batch Job 416 CloudWatch logs:

```bash
# Tool execution successful
Tool execution completed successfully

# Output files detected in working directory
Found output file in working directory: FastQC on data 201_ RawData
Found output file in working directory: output.html
Found output file in working directory: output.txt

# But upload to S3 fails
[4/4] Uploading output files to S3...
Source: /host-tmp/galaxy_job_416/outputs/
[WARN] No output files found in /host-tmp/galaxy_job_416/outputs
find: '/host-tmp/galaxy_job_416/outputs': No such file or directory
```

### Root Cause Analysis

The problem occurs in the **output file collection phase** within the tool container:

1. **Tool generates files** in `/tmp/work/` (working directory):
   - `output.html`
   - `output.txt`
   - `FastQC on data 201_ RawData/` (directory)

2. **Job script tries to copy** files to `${OUTPUT_DIR}` which is `/galaxy_outputs` in the container:
   ```bash
   cp "$file" "${OUTPUT_DIR}/" 2>/dev/null || true
   ```

3. **Silent failure**: The `2>/dev/null || true` suppresses all errors, so if the copy fails, it continues silently.

4. **Result**: No files in `/galaxy_outputs/` means no files in host's `/tmp/galaxy_job_416/outputs/`, which means no files to upload to S3.

## Investigation

### Step 1: Check if OUTPUT_DIR exists

The job script should be copying files to `${OUTPUT_DIR}`, but we need to verify:
- Does `/galaxy_outputs/` directory exist in the tool container?
- Does the container have write permissions to `/galaxy_outputs/`?

### Step 2: Silent failure in copy commands

Current code in `galaxy_job_runner.py` (line 1034):
```bash
cp "$file" "${OUTPUT_DIR}/" 2>/dev/null || true
```

The `2>/dev/null || true` means:
- Redirect stderr to /dev/null (hide errors)
- `|| true` ensures the script continues even if cp fails

**This is dangerous** because we never know if the copy succeeded!

## Solution: Fix 14

### Changes Made

Modified `/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`:

1. **Add debugging output** to see what's happening:
   ```bash
   echo "DEBUG: OUTPUT_DIR=${OUTPUT_DIR}"
   echo "DEBUG: Checking if OUTPUT_DIR exists:"
   ls -la "${OUTPUT_DIR}" || echo "OUTPUT_DIR does not exist or is not accessible"
   ```

2. **Create OUTPUT_DIR explicitly** before copying:
   ```bash
   mkdir -p "${OUTPUT_DIR}" 2>/dev/null || true
   ```

3. **Show copy results** (success or failure):
   ```bash
   if cp "$file" "${OUTPUT_DIR}/" 2>&1; then
       echo "  [OK] Copied $file to OUTPUT_DIR"
   else
       echo "  [ERROR] Failed to copy $file: $?"
   fi
   ```

### Expected Behavior

After this fix, the logs should show:

```bash
DEBUG: OUTPUT_DIR=/galaxy_outputs
DEBUG: Checking if OUTPUT_DIR exists:
drwxr-xr-x 2 root root 40 Oct 22 10:00 /galaxy_outputs

Found output file in working directory: output.html
  [OK] Copied output.html to OUTPUT_DIR
Found output file in working directory: output.txt
  [OK] Copied output.txt to OUTPUT_DIR
Found output directory: FastQC on data 201_ RawData/
  [OK] Copied directory FastQC on data 201_ RawData/ to OUTPUT_DIR

[4/4] Uploading output files to S3...
[OK] Uploaded 3 output file(s)
```

## Docker Volume Mount Verification

The Docker mount configuration from Fix 13:

```bash
# In fetch_and_run.sh
DOCKER_OUTPUT_DIR="/tmp/galaxy_job_416/outputs"  # Host path
docker run --rm -i \
    -v "${DOCKER_OUTPUT_DIR}:/galaxy_outputs:rw" \
    ...
```

**Important**: The `/galaxy_outputs` directory inside the container is mounted from host's `/tmp/galaxy_job_416/outputs`, which should be created by fetch-and-run container at `/host-tmp/galaxy_job_416/outputs/` (line 71: `mkdir -p "${OUTPUT_DIR}"`).

**Hypothesis**: The Docker mount might create an empty directory `/galaxy_outputs` with restricted permissions, or the directory is bind-mounted AFTER the container starts but BEFORE files are copied.

## Testing Plan

1. **Restart Galaxy** to load the updated `galaxy_job_runner.py`
2. **Run the same workflow** (FastQC on single dataset)
3. **Check AWS CloudWatch logs** for:
   - Debug output showing OUTPUT_DIR path and existence
   - Success/failure messages for each file copy
   - Number of files uploaded to S3

## Alternative Solutions (if Fix 14 doesn't work)

### Option A: Copy to working directory, then move to OUTPUT_DIR
```bash
# Don't rely on OUTPUT_DIR being writable
# Instead, collect outputs in working directory first
mkdir -p /tmp/collected_outputs
for file in *; do
    if [ -f "$file" ]; then
        cp "$file" /tmp/collected_outputs/
    fi
done
# Then move all at once
mv /tmp/collected_outputs/* "${OUTPUT_DIR}/" 2>&1
```

### Option B: Use fetch-and-run to collect outputs
Instead of relying on the tool container to copy files, have fetch-and-run extract files from the container after it completes:

```bash
# After docker run completes
# Fetch-and-run collects outputs from the host path
# (Since /galaxy_outputs is mounted from host /tmp/galaxy_job_416/outputs)
# Files should already be there if the tool wrote to /galaxy_outputs
```

### Option C: Change OUTPUT_DIR to be in working directory
```bash
# In job script header
OUTPUT_DIR="/tmp/work/outputs"
mkdir -p "${OUTPUT_DIR}"

# After tool execution, copy from /tmp/work/outputs to /galaxy_outputs
cp -r "${OUTPUT_DIR}"/* /galaxy_outputs/ 2>&1
```

## Related Files

- [galaxy_job_runner.py:1028-1060](/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L1028-L1060) - Output copy logic
- [fetch_and_run.sh:71](/Users/renyuankai/work/biometa/galaxy/docker/fetch-and-run/fetch_and_run.sh#L71) - Create work directories
- [fetch_and_run.sh:159-167](/Users/renyuankai/work/biometa/galaxy/docker/fetch-and-run/fetch_and_run.sh#L159-L167) - Docker volume mounting

## Next Steps

1. ✅ Code changes completed
2. 🔄 Galaxy restart in progress
3. ⏳ Run test workflow
4. ⏳ Analyze CloudWatch logs
5. ⏳ Verify files uploaded to S3

---

**Last Updated**: 2025-10-22 17:45
**Status**: Waiting for Galaxy restart to test Fix 14
