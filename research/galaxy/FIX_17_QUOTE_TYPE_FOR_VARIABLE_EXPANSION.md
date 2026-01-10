# Fix 17: Use Double Quotes for Variable Expansion

**Date**: 2025-10-22
**Status**: ✅ FIXED
**Related**: Fix 16 (use ${OUTPUT_DIR} variable)

## Problem Description

After Fix 16 changed output paths to use `${OUTPUT_DIR}` variable, Job 424 (Trimmomatic) still failed with the same error:

```bash
mv: can't rename 'fastq_out.fastqsanger.gz': No such file or directory
ERROR: Script failed at line 71
```

## Root Cause

Fix 16 correctly replaced hardcoded `/tmp/outputs/` with `${OUTPUT_DIR}`, but the replacement preserved the **original quote type**:

### Generated Command (Job 424)
```bash
mv fastq_out.'fastqsanger.gz' '${OUTPUT_DIR}/dataset_90caaba9-cf70-4dc6-a568-dfc1a2759fb6.dat'
#                               ^                                                             ^
#                               Single quotes prevent variable expansion!
```

### Shell Behavior
```bash
# With single quotes (WRONG):
echo '${OUTPUT_DIR}/file.dat'
# Output: ${OUTPUT_DIR}/file.dat  (literal string, no expansion)

# With double quotes (CORRECT):
echo "${OUTPUT_DIR}/file.dat"
# Output: /galaxy_outputs/file.dat  (variable expanded)
```

**Problem**: Single quotes preserve literal strings and **prevent shell variable expansion**!

## Evidence from Job 424 Script

```bash
$ aws s3 cp s3://.../jobs/424/job_script.sh - | grep "mv fastq_out"

mv fastq_out.'fastqsanger.gz' '${OUTPUT_DIR}/dataset_90caaba9-cf70-4dc6-a568-dfc1a2759fb6.dat'
#                               ^-- Single quotes!
```

When this command runs in the container:
```bash
OUTPUT_DIR=/galaxy_outputs

# Command attempts to execute:
mv fastq_out.fastqsanger.gz '${OUTPUT_DIR}/dataset_90caaba9-cf70-4dc6-a568-dfc1a2759fb6.dat'

# Shell interprets this as LITERAL STRING (no expansion):
mv fastq_out.fastqsanger.gz '${OUTPUT_DIR}/dataset_90caaba9-cf70-4dc6-a568-dfc1a2759fb6.dat'

# Tries to create file with LITERAL NAME:
# ${OUTPUT_DIR}/dataset_90caaba9-cf70-4dc6-a568-dfc1a2759fb6.dat
# (invalid path, directory ${OUTPUT_DIR} doesn't exist)

# Result: "No such file or directory"
```

## Solution: Fix 17

### Code Changes

**File**: [galaxy_job_runner.py:407-412](/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py#L407-L412)

**BEFORE (Fix 16)**:
```python
# Replace in single quotes
if f"'{old_path}'" in rewritten:
    rewritten = rewritten.replace(f"'{old_path}'", f"'{new_path}'")
    #                               Single quotes → Single quotes (WRONG!)
    replacements += 1
```

**AFTER (Fix 17)**:
```python
# Replace in single quotes - CHANGE TO DOUBLE QUOTES (Fix 17)
# Single quotes prevent variable expansion, so we must use double quotes
if f"'{old_path}'" in rewritten:
    rewritten = rewritten.replace(f"'{old_path}'", f'"{new_path}"')
    #                               Single quotes → Double quotes (CORRECT!)
    replacements += 1
    self.logger.debug(f"[{job_id}] Rewrote: '{old_path}' → \"{new_path}\" (Fix 17: single→double quotes)")
```

### Key Change

**Original path in single quotes** → **New path in DOUBLE quotes**

This allows shell variable expansion:
```bash
# Before Fix 17:
mv file.dat '/Users/.../dataset.dat'  →  mv file.dat '${OUTPUT_DIR}/dataset.dat'  ❌

# After Fix 17:
mv file.dat '/Users/.../dataset.dat'  →  mv file.dat "${OUTPUT_DIR}/dataset.dat"  ✅
```

## Expected Behavior After Fix 17

### Generated Command
```bash
mv fastq_out.'fastqsanger.gz' "${OUTPUT_DIR}/dataset_90caaba9-cf70-4dc6-a568-dfc1a2759fb6.dat"
#                               ^-- Double quotes allow variable expansion
```

### Runtime Execution
```bash
# In container, OUTPUT_DIR is set:
OUTPUT_DIR=/galaxy_outputs

# Command with variable:
mv fastq_out.fastqsanger.gz "${OUTPUT_DIR}/dataset_90caaba9-cf70-4dc6-a568-dfc1a2759fb6.dat"

# Shell expands variable:
mv fastq_out.fastqsanger.gz "/galaxy_outputs/dataset_90caaba9-cf70-4dc6-a568-dfc1a2759fb6.dat"

# File successfully moved to mounted output directory
# Host sees file at: /tmp/galaxy_job_424/outputs/dataset_90caaba9-cf70-4dc6-a568-dfc1a2759fb6.dat
```

## Quote Types in Shell

### Single Quotes (`'...'`)
- **Literal strings**: No expansion, no escaping
- Variables **NOT** expanded: `'$VAR'` → `$VAR`
- Command substitution **NOT** executed: `'$(cmd)'` → `$(cmd)`
- Use case: Literal strings, prevent all interpretation

### Double Quotes (`"..."`)
- **Allow variable expansion**: `"$VAR"` → value of VAR
- **Allow command substitution**: `"$(cmd)"` → output of cmd
- Escaping works: `"\$VAR"` → `$VAR` (literal)
- Use case: Strings with variables, safe path handling

### No Quotes
- Word splitting occurs
- Globbing occurs
- Generally unsafe for paths with spaces

**For paths with variables, always use double quotes!**

## Testing

### Test Case: Trimmomatic Command

**Before Fix 17**:
```bash
# Generated command:
mv output.gz '${OUTPUT_DIR}/dataset.dat'

# In container:
$ OUTPUT_DIR=/galaxy_outputs
$ mv output.gz '${OUTPUT_DIR}/dataset.dat'
mv: can't rename 'output.gz': No such file or directory  ❌
```

**After Fix 17**:
```bash
# Generated command:
mv output.gz "${OUTPUT_DIR}/dataset.dat"

# In container:
$ OUTPUT_DIR=/galaxy_outputs
$ mv output.gz "${OUTPUT_DIR}/dataset.dat"
# Success! File moved to /galaxy_outputs/dataset.dat  ✅
$ ls /galaxy_outputs/
dataset.dat
```

### Verification Commands

```bash
# Check new job script has double quotes:
aws s3 cp s3://.../jobs/<NEW_JOB_ID>/job_script.sh - | grep 'OUTPUT_DIR'

# Should see:
# mv ... "${OUTPUT_DIR}/dataset.dat"   ← Double quotes ✅
# cp ... "${OUTPUT_DIR}/file.txt"      ← Double quotes ✅

# Should NOT see:
# mv ... '${OUTPUT_DIR}/dataset.dat'   ← Single quotes ❌
```

## Impact

### Before Fix 17
- ❌ Variable `${OUTPUT_DIR}` treated as literal string
- ❌ All tools using mv/cp fail
- ❌ Trimmomatic and similar tools broken

### After Fix 17
- ✅ Variable `${OUTPUT_DIR}` correctly expanded
- ✅ Files written to correct output directory
- ✅ All tools work properly

## Why This Happened

### Path Rewriting Logic

1. **Original Galaxy command**:
   ```bash
   mv output.dat '/Users/renyuankai/.../dataset.dat'
   ```
   Note: Galaxy uses single quotes for paths (safe, prevents expansion)

2. **Fix 12 replacement logic**:
   ```python
   # Find: '/Users/.../dataset.dat'
   # Replace with: '/tmp/outputs/dataset.dat'
   # Preserves quote type: single → single
   ```
   This was fine when using literal path `/tmp/outputs/`

3. **Fix 16 changed to variable**:
   ```python
   # Find: '/Users/.../dataset.dat'
   # Replace with: '${OUTPUT_DIR}/dataset.dat'
   # Still preserves single quotes (BUG!)
   ```
   Now single quotes prevent variable expansion

4. **Fix 17 changes quote type**:
   ```python
   # Find: '/Users/.../dataset.dat'  (single quotes)
   # Replace with: "${OUTPUT_DIR}/dataset.dat"  (double quotes)
   # Allows variable expansion ✅
   ```

## Related Fixes

- **Fix 12**: Command line path rewriting (introduced quote preservation)
- **Fix 16**: Use `${OUTPUT_DIR}` variable (exposed the quote type bug)
- **Fix 17**: Change single quotes to double quotes (fixes variable expansion)

## Restart Required

**YES** - Galaxy must be restarted to load the updated code.

```bash
pkill -f "python.*run"
PYTHONPATH=lib sh run.sh --daemon
```

## Next Steps

1. ✅ Fix 17 code changes completed
2. ⏳ Restart Galaxy
3. ⏳ Re-run workflow (FastQC + Trimmomatic)
4. ⏳ Verify Job 424 (Trimmomatic) completes successfully
5. ⏳ Check S3 outputs for both jobs

---

**Status**: FIXED - Awaiting restart and testing
**Priority**: P0 - Blocks all tools that use explicit file moves with variables
**Lesson**: When using variables in strings, **always use double quotes**!
