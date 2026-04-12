# 2026-04-12 — S5/S6 Multi-line Params Fix: All 6 E2E Sessions Passing

## Result
**6/6 drug discovery pilot E2E sessions passing** — all with `exec=completed` (not fallback).

| Session | Status | Time |
|---------|--------|------|
| S1 ADMET | ✅ exec=completed | 344s |
| S2 IVIVE | ✅ exec=skipped | 110s |
| S3 Pocket | ✅ exec=completed | 338s |
| S4 Pharma | ✅ exec=completed | 208s |
| S5 Ranking | ✅ exec=completed | 404s |
| S6 CRO | ✅ exec=completed | 379s |

Total suite time: 29.8 minutes.

---

## Root Causes Fixed

### 1. Nextflow 25.x `--params-file` silently drops multi-line strings (S5, S6)

**Symptom**: `params.assay_csv is required` error immediately at workflow startup, even though the param was set in `nf-params.json`.

**Root cause**: Nextflow 25.10.0 silently converts multi-line string values in `--params-file` JSON to `null` inside `params`. The JSON file was written correctly, but Nextflow discarded the value.

**Fix in `nextflow_executor.py`**: When any param value contains `\n`, write all multi-line params as Groovy triple-quoted strings in a separate `biomate_inline_params.config` file and pass it via `-c`. Scalar params still go to `nf-params.json` via `--params-file` for audit trail.

```python
if _has_multiline:
    _inline_cfg_lines = ["params {"]
    for key, value in params.items():
        if isinstance(value, str) and "\n" in value:
            _safe_val = value.replace('"""', '\\"\\"\\"')
            _inline_cfg_lines.append(f'    {key} = """{_safe_val}"""')
        else:
            _scalar_params[key] = value
    _inline_cfg_path = log_dir / "biomate_inline_params.config"
    _inline_cfg_path.write_text("\n".join(_inline_cfg_lines) + "\n")
    cmd += ["-c", str(_inline_cfg_path)]
```

Verified with local test: `nextflow run .../main.nf -c inline_params.config` → `assay_csv length: 81` ✓

### 2. Groovy `\n` escape in triple-quoted template blocks (S5, S6)

**Symptom**: `SyntaxError: unterminated string literal (detected at line 37)` in the Python script running on AWS Batch.

**Root cause**: In Nextflow `.nf` script blocks using Groovy `"""..."""` templates, `\n` is interpreted as a literal newline character. So `if raw and '\n' not in raw` becomes `if raw and '` + newline + `' not in raw` = unterminated string literal in Python.

Discovered by downloading `.command.sh` from S3 and inspecting the actual shell script sent to Batch.

**Fix in both `.nf` files**: Change `'\n'` → `'\\n'` in the inline-vs-filepath detection block. Groovy `\\n` → `\n` in Python output.

```python
# Before (broken):
if raw and '\n' not in raw and os.path.exists(raw):
# After (fixed):
if raw and '\\n' not in raw and os.path.exists(raw):
```

Files fixed:
- `assay_ingestion_and_ranking/main.nf` line 68
- `cro_submission_export/main.nf` line 66

### 3. Python f-string vs Nextflow interpolation confusion in RANK_AND_REPORT (S5)

**Symptom**: `NameError: name 'params' is not defined` at line 49 in the RANK_AND_REPORT process.

**Root cause**: The HTML report template had `{params.herg_safe_threshold}` — a Python f-string expression referencing `params`, which doesn't exist in Python scope. Nextflow-interpolated expressions use `${...}`, which Groovy substitutes before the script runs. Python f-strings use `{...}` which is evaluated at runtime.

The working pattern nearby — `{float("${params.potency_weight}")*100:.0f}%` — works because `${params.potency_weight}` is Nextflow-interpolated first (e.g. → `0.6`), giving Python valid `{float("0.6")*100:.0f}`.

**Fix in `assay_ingestion_and_ranking/main.nf`** line 310:
```python
# Before (broken):
| hERG threshold: {params.herg_safe_threshold} uM
# After (fixed):
| hERG threshold: ${params.herg_safe_threshold} uM
```

### 4. Playwright test timeout on S5 (S5)

**Symptom**: S5 test hitting Playwright's 10-minute global timeout because the assay ranking workflow has 3 sequential Batch steps (PARSE → SCORE → RANK) totaling 8-10 minutes.

**Fix in `drug-discovery-pilot-e2e.e2e.ts`**: Added `test.setTimeout(900000)` (15 min) inside the S5 test, same approach as S2 (IVIVE).

---

## Files Changed

| File | Change |
|------|--------|
| `nextflow_executor.py` | Multi-line params → Groovy config file approach (already committed) |
| `assay_ingestion_and_ranking/main.nf` | `\\n` escape fix + `${params.herg_safe_threshold}` fix |
| `cro_submission_export/main.nf` | `\\n` escape fix |
| `drug-discovery-pilot-e2e.e2e.ts` | S5 `test.setTimeout(900000)` |

---

## Debugging Method: `.command.sh` Download

The key diagnostic tool was downloading the actual `.command.sh` from S3 to see what Python code Nextflow actually generated (after Groovy template interpolation):

```bash
aws s3 cp s3://biomate-nextflow-work/nextflow/work/<hash>/.command.sh /tmp/cmd.sh
```

This revealed:
- The literal newline inside `'\n'` (unterminated string bug)
- The `{params.herg_safe_threshold}` not being interpolated (NameError bug)

Always use this approach when debugging Nextflow script process failures on Batch.
