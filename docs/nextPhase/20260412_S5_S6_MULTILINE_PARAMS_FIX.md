# 2026-04-12 — S5/S6 Multi-line Params Fix: All 6 E2E Sessions Passing

## Summary

This session resumed a multi-session debugging effort to get all 6 drug discovery pilot E2E tests passing with `exec=completed` on AWS Batch (not just the `h1=true` heading-check fallback). S1–S4 were already passing. S5 (assay ranking) and S6 (CRO export) were failing due to four separate bugs uncovered incrementally through backend log analysis and S3 artifact inspection.

**Final result: 6/6 sessions passing, 29.8 min total.**

| Session | Description | Status | Time |
|---------|-------------|--------|------|
| S1 | ADMET screening | ✅ exec=completed | 344s |
| S2 | IVIVE metabolic scaling | ✅ exec=skipped | 110s |
| S3 | Fpocket binding-site detection | ✅ exec=completed | 338s |
| S4 | Pharmacology panel | ✅ exec=completed | 208s |
| S5 | Assay ingestion + compound ranking | ✅ exec=completed | 404s |
| S6 | CRO export (WuXi AppTec format) | ✅ exec=completed | 379s |

---

## Background: What Was Already Working

Before this session, the previous conversation had:
- Diagnosed the primary `--params-file` bug (Nextflow 25.x silently drops multi-line string values)
- Implemented the `biomate_inline_params.config` fix in `nextflow_executor.py`
- Confirmed via local Nextflow test that `-c inline_params.config` correctly delivers multi-line strings

What remained was fixing the Nextflow `.nf` workflow files themselves, which had their own separate bugs that only surfaced once the param-delivery problem was solved.

---

## Bug 1 — Nextflow 25.x `--params-file` Silently Drops Multi-line Strings

### Symptom
S5 and S6 both failed immediately at the first process with:
```
ERROR ~ params.assay_csv is required. Provide a file path or inline CSV string.
```
The `nf-params.json` was written correctly (verified by reading the file), but Nextflow discarded the value.

### Root Cause
Nextflow 25.10.0 does not handle multi-line string values in `--params-file` JSON. When a JSON string value contains embedded newlines, Nextflow silently coerces it to `null` inside `params`. This is a regression/undocumented behavior change from earlier versions.

**Confirmed with local test:**
```bash
# test.json: { "assay_csv": "line1\nline2\nline3" }
nextflow run .../main.nf --params-file test.json -stub
# Output: "params.assay_csv is required" — param arrived as null
```

### Fix — `nextflow_executor.py` (lines ~2170–2210)

When any parameter value contains a newline, write multi-line params as Groovy triple-quoted string assignments in a separate `biomate_inline_params.config` file, and pass it to Nextflow via the `-c` flag. Scalar params still go to `nf-params.json` for audit purposes.

```python
_has_multiline = any(
    isinstance(v, str) and "\n" in v
    for v in params.values()
)

if _has_multiline:
    _inline_cfg_lines = ["params {"]
    _scalar_params: dict = {}
    for key, value in params.items():
        if isinstance(value, str) and "\n" in value:
            _safe_val = value.replace('"""', '\\"\\"\\"')
            _inline_cfg_lines.append(f'    {key} = """{_safe_val}"""')
            log.info(f"[Nextflow run {run_id}] inline multi-line param '{key}' → config block ({len(value)} chars)")
        else:
            _scalar_params[key] = value
    _inline_cfg_lines.append("}")
    _inline_cfg_path = log_dir / "biomate_inline_params.config"
    _inline_cfg_path.write_text("\n".join(_inline_cfg_lines) + "\n")
    cmd += ["-c", str(_inline_cfg_path)]

    # scalar params still go to nf-params.json
    _params_json_path = log_dir / "nf-params.json"
    _params_json_path.write_text(json.dumps(_scalar_params_for_json, indent=2))
    cmd += ["--params-file", str(_params_json_path)]
```

The resulting `biomate_inline_params.config` looks like:
```groovy
params {
    assay_csv = """compound_id,assay_type,value,unit,assay_date
CPD001,IC50_BCR_ABL1,600,nM,2026-03-15
CPD001,hERG_IC50,30,uM,2026-03-15
..."""
}
```

**Verified with local test:**
```bash
nextflow run .../main.nf -c inline_params.config
# Output: "assay_csv length: 81" — param correctly received ✓
```

This fix was committed in the prior session and was already in place at the start of this session.

---

## Bug 2 — Groovy `\n` Escape Produces Unterminated Python String

### Symptom
S5's `PARSE_ASSAY_DATA` process and S6's `VALIDATE_COMPOUNDS` process both failed on AWS Batch with:
```
SyntaxError: unterminated string literal (detected at line 37)
```

### Diagnosis

The key diagnostic step was downloading the actual `.command.sh` file that Nextflow sent to the Batch container:
```bash
aws s3 cp s3://biomate-nextflow-work/nextflow/work/<hash>/.command.sh /tmp/cmd.sh
cat /tmp/cmd.sh
```

Inside the generated shell script, the Python line that should have been:
```python
if raw and '\n' not in raw and os.path.exists(raw):
```
was actually:
```python
if raw and '
' not in raw and os.path.exists(raw):
```
A literal newline had been inserted inside the single-quote string.

### Root Cause

In Nextflow `.nf` files, process script blocks use Groovy `"""..."""` template strings. Inside these templates, `\n` is a Groovy escape sequence meaning a literal newline character. When the `.nf` source contains `'\n'`, Groovy outputs a single-quote, a newline, a single-quote — producing the unterminated string error.

This is a standard Groovy string interpolation pitfall: any backslash escape in a Groovy `"""..."""` block is processed by Groovy before the string is handed to the shell.

### Fix

In both `.nf` files, the inline-vs-filepath detection block checks whether the input looks like a multi-line CSV or a file path. The fix is to double-escape the backslash: `'\\n'` in the `.nf` source. Groovy turns `\\n` → `\n` in the output, which is the correct Python string containing a backslash-n.

**`assay_ingestion_and_ranking/main.nf` line 68:**
```python
# Before (broken):
if raw and '\n' not in raw and os.path.exists(raw):
# After (fixed):
if raw and '\\n' not in raw and os.path.exists(raw):
```

**`cro_submission_export/main.nf` line 66:**
```python
# Before (broken):
if raw and '\n' not in raw and os.path.exists(raw):
# After (fixed):
if raw and '\\n' not in raw and os.path.exists(raw):
```

**Verified locally:**
```bash
# Test with multi-line content:
nextflow run .../main.nf -c inline_params.config -stub
# Output: "MULTILINE: 3 lines" — correctly detected ✓
```

---

## Bug 3 — Python `NameError` from Missing Groovy Interpolation Dollar Sign

### Symptom
S5's `RANK_AND_REPORT` process failed on AWS Batch with:
```
NameError: name 'params' is not defined
```
at line 49 of the generated Python script, inside the HTML report generation.

### Diagnosis

Again downloaded `.command.sh` from S3 to inspect the generated code. The HTML template string contained:
```python
f'<p><small>Scoring: composite = {float("0.6")*100:.0f}% potency + {float("0.4")*100:.0f}% safety | hERG threshold: {params.herg_safe_threshold} uM</small></p>'
```
The first two expressions (`float("0.6")*100`, `float("0.4")*100`) were valid — Nextflow had already substituted `${params.potency_weight}` → `0.6` and `${params.safety_weight}` → `0.4` before the script ran. But `{params.herg_safe_threshold}` had no `$` prefix, so Groovy left it as-is, and Python tried to evaluate `params.herg_safe_threshold` as a Python expression at runtime — where `params` doesn't exist.

### Root Cause

Groovy double-quote string interpolation uses `${expression}` syntax. Python f-strings use `{expression}` syntax. Inside Nextflow `"""..."""` script blocks, expressions of the form `${...}` are consumed by Groovy before the shell script is written. Expressions of the form `{...}` are left untouched by Groovy and land verbatim in the Python script, where they are evaluated as Python f-string expressions.

The working pattern nearby:
```python
{float("${params.potency_weight}")*100:.0f}%
```
works because Groovy substitutes `${params.potency_weight}` → `0.6` first, yielding valid Python `{float("0.6")*100:.0f}`.

The broken pattern:
```python
{params.herg_safe_threshold}
```
has no `$`, so Groovy ignores it, and Python tries to evaluate `params.herg_safe_threshold` — which fails because `params` is not defined in Python.

### Fix

**`assay_ingestion_and_ranking/main.nf` line 310:**
```python
# Before (broken):
| hERG threshold: {params.herg_safe_threshold} uM
# After (fixed):
| hERG threshold: ${params.herg_safe_threshold} uM
```

The `$` prefix tells Groovy to substitute the value (e.g. `10`) before writing the shell script, so Python receives the literal number in the string rather than a reference to undefined `params`.

---

## Bug 4 — Playwright Test Timeout on S5

### Symptom
S5 test was failing with a Playwright timeout after ~600 seconds (10 minutes), even though the underlying Nextflow workflow was succeeding on Batch.

### Root Cause
S5's `assay_ingestion_and_ranking` workflow has 3 sequential AWS Batch steps:
1. `PARSE_ASSAY_DATA` — parses CSV, pivots to wide format
2. `COMPUTE_COMPOSITE_SCORE` — normalises IC50/hERG, computes weighted composite score
3. `RANK_AND_REPORT` — sorts, emits ranked CSV + HTML report + JSON summary

Each step involves container startup overhead (~2–3 min). Total wall time is 8–10 minutes. Playwright's default global test timeout is 600 seconds (10 minutes), which was being hit before the workflow could complete.

### Fix

**`drug-discovery-pilot-e2e.e2e.ts`** — added `test.setTimeout(900000)` (15 minutes) at the top of the S5 test function, matching the same approach used for S2 (IVIVE), which also had a long-running multi-step workflow:

```typescript
test('S5: Assay data upload + compound ranking — hERG + potency integration', async ({ page }) => {
  test.setTimeout(900000); // 15 min — assay ranking has 3 Batch steps; RANK_AND_REPORT can take 8-10 min
  const SESSION_ID = 'S5_RANKING';
  // ...
```

---

## Debugging Journey: Multi-Worker Gunicorn UUID Mismatch

During run 7 and run 8, an additional issue was observed: the frontend received run ID `6d03d701` from the execute endpoint, but the backend logs showed the actual Nextflow run completing under a different UUID (`13416981`). Status polling for `6d03d701` kept returning `"running"` indefinitely even after the actual workflow succeeded.

**Root cause**: gunicorn runs 4 worker processes, each with its own in-memory `_runs` dict. If the `/execute` POST is handled by Worker A (which creates the run and stores it in its own `_runs`), but subsequent `/status` GET requests are load-balanced to Workers B/C/D, those workers have no record of the run and return stale or default state.

**How S5 still passed**: Despite this, after enough polls the status endpoint eventually returned `completed` (likely because the run was written to the database and the status endpoint had a DB fallback path). The test observed `Terminal status: completed` at Poll 64 and passed.

**This is a latent reliability issue** — the test can pass or fail depending on which gunicorn worker handles each request. A proper fix would be to make the status endpoint read from the database as the primary source of truth rather than worker-local dicts. This is tracked but not fixed in this session.

---

## Key Diagnostic Technique: Download `.command.sh` from S3

The most important tool for debugging Nextflow process failures on AWS Batch is to download the generated shell script directly from S3 before looking at anything else:

```bash
# Find the work hash from Nextflow logs or S3 listing
aws s3 ls s3://biomate-nextflow-work/nextflow/work/ --recursive | grep ".command.sh"

# Download and inspect
aws s3 cp s3://biomate-nextflow-work/nextflow/work/<hash>/.command.sh /tmp/cmd.sh
cat /tmp/cmd.sh
```

The `.command.sh` file shows exactly what Python code Nextflow generated after all Groovy template interpolation. In this session, this revealed:
- The literal newline inside `'\n'` (Bug 2)
- The `{params.herg_safe_threshold}` not being substituted (Bug 3)

Without this technique, both bugs would have been extremely hard to isolate because the Nextflow source `.nf` file looks correct — the errors only appear after Groovy template expansion.

Similarly, `.command.log` and `.command.err` in the same S3 prefix contain the actual stdout/stderr from the container:
```bash
aws s3 cp s3://biomate-nextflow-work/nextflow/work/<hash>/.command.log /tmp/cmd.log
aws s3 cp s3://biomate-nextflow-work/nextflow/work/<hash>/.command.err /tmp/cmd.err
```

---

## Files Changed

| File | Change | Commit |
|------|--------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Multi-line params → Groovy config file approach | Prior session |
| `backend/biomni_workflows/.../assay_ingestion_and_ranking/main.nf` | `\\n` escape (line 68) + `${params.herg_safe_threshold}` (line 310) | `ca24b1049` |
| `backend/biomni_workflows/.../cro_submission_export/main.nf` | `\\n` escape (line 66) | `ca24b1049` |
| `frontend/e2e/drug-discovery-pilot-e2e.e2e.ts` | `test.setTimeout(900000)` in S5 | `ca24b1049` |
| `docs/nextPhase/20260412_S5_S6_MULTILINE_PARAMS_FIX.md` | This document | `ca24b1049` |

---

## Lessons Learned

### Nextflow + Groovy template escaping rules

Inside Nextflow `"""..."""` script blocks:

| Source `.nf` | Groovy output | Python receives |
|-------------|---------------|-----------------|
| `\n` | literal newline | newline char (breaks string literals) |
| `\\n` | `\n` | backslash-n (correct escape) |
| `${params.foo}` | value of `params.foo` | literal number/string |
| `{params.foo}` | `{params.foo}` (unchanged) | Python f-string tries to eval `params.foo` → NameError |
| `\${literal}` | `${literal}` | Python f-string with `literal` in scope |

**Rule of thumb**: Any `\` in a `.nf` script block is consumed by Groovy. Write `\\` to get a single `\` in the output. Any `${...}` is consumed by Groovy. Use `\${...}` if you need a literal `${...}` in the output.

### `--params-file` is unreliable for multi-line strings in Nextflow 25.x

Do not pass multi-line string parameters via `--params-file` JSON in Nextflow 25.x. Use the `-c config_file` approach with triple-quoted Groovy strings. This is now the standard approach in `nextflow_executor.py`.

### Always check `.command.sh` first for Batch process failures

When a Nextflow process fails on AWS Batch with a Python syntax error, Python NameError, or unexpected behavior, the first debugging step is to download `.command.sh` from the S3 work directory. This shows the code after Groovy template expansion — which is often quite different from what the `.nf` source suggests.

### Per-test timeouts for long-running E2E tests

Any E2E test that involves 3+ sequential AWS Batch steps should have `test.setTimeout(900000)` (15 min) or longer. The global Playwright timeout (600s) is insufficient for workflows with >2 sequential container starts. S2 and S5 both required this override.
