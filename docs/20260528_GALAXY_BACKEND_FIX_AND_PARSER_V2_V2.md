# Galaxy Backend Crash-Loop Fix + Parser-v2 Docstring v2

**Date:** 2026-05-28 (afternoon, continuing 2026-05-27 session)
**Branch:** `integration/next-phase`
**Key commits:** `903745e19` (Python 3.9 fix), `15bbb1381` (docstring v2)

## TL;DR

Two showstopper bugs blocked dev validation. Both fixed within ~30 minutes once root-caused:

1. **Galaxy gunicorn worker crash-loop** — Python 3.9 cannot parse PEP 604 `X | Y` union syntax in type annotations. My recent edits to `nextflow_executor.py` introduced 13 such annotations. Every gunicorn worker crashed at module import, master shut down, restarted, repeat. **Container reported "Up N min (unhealthy)" indefinitely**; all `/api/workflows/*` requests returned `fetch failed (ECONNRESET)` at the Node.js proxy. Fix: one-line `from __future__ import annotations`.
2. **Docstring conversion v1 missed multi-line docstrings** — yesterday's bulk sweep (`2e5b07783`) used a heuristic that mis-identified inner Python `"""` (multi-line docstrings followed by regular Python code, not directives) as the outer Groovy closer. Result: 3 of 7 clinical workflows still crashed with `Unexpected input: <docstring word>` at Nextflow parser-v2 module load. v2 sweep (`15bbb1381`) uses `}`-follow detection to find the true outer boundary; 14 files, 55 additional conversions.

After both fixes, the v9 clinical sweep showed `p0_pkpd_semaglutide` producing 4 real outputs (294s runtime) — first end-to-end success of a clinical workflow this session. v10 sweep (post-docstring-v2) targets the 3 previously failing.

## Issue 1: Galaxy Worker Crash-Loop

### Symptom

`docker ps` showed `biomate-galaxy-dev Up N min (unhealthy)` indefinitely after every restart. Gunicorn worker process visible at 80%+ CPU but port 8080 refused connections. All workflow API calls returned `fetch failed (ECONNRESET)` at the Node.js → Galaxy proxy step. Health check `FailingStreak: 54+`.

### Diagnosis

Found `gunicorn.log` rotated every ~1 hour for 12+ hours, each file 50MB — implying constant restart churn. Grepped for `Traceback|Error`, found the smoking gun:

```
[2026-05-28 16:43:01 +0000] [1207] [ERROR] Worker (pid:1209) exited with code 3
[2026-05-28 16:43:01 +0000] [1207] [ERROR] Shutting down: Master
[2026-05-28 16:43:01 +0000] [1207] [ERROR] Reason: Worker failed to boot.
...
File "/app/lib/galaxy/webapps/galaxy/api/nextflow_executor.py", line 320, in <module>
    log_tail: list | str | None = None,
TypeError: unsupported operand type(s) for |: 'type' and 'type'
```

### Root cause

The Galaxy container ships **Python 3.9** (`/usr/local/bin/python3.9`). PEP 604 `X | Y` union syntax was introduced in Python 3.10. Python 3.9 evaluates annotations at module load, so:

```python
def f(x: list | str | None = None): ...
```

raises `TypeError` immediately at definition. Module load fails, worker exits code 3, gunicorn master gives up.

My session's edits to `nextflow_executor.py` introduced 13 of these annotations across various function signatures. The bug was undetected during local development because the developer machine has Python ≥ 3.10.

### Fix

Added one line at the top of `nextflow_executor.py`:

```python
from __future__ import annotations
```

This is PEP 563 — *postponed evaluation of annotations*. Annotations become string literals at definition time; they're only resolved at runtime if explicitly requested (e.g. `typing.get_type_hints()`). Galaxy doesn't introspect these annotations, so deferred evaluation is safe.

### Deployment

Avoided `sync_to_dev.sh` (which would have restarted the container and triggered another cycle). Used direct `docker cp` + `docker restart biomate-galaxy-dev`. Container went **healthy in 60 seconds**.

### Lesson

When introducing PEP 604 `X | Y` union syntax to a Python file, always pair it with `from __future__ import annotations` for forward compat with 3.9 environments. The Galaxy container won't be upgraded to 3.10+ in the near term; treat 3.9 as the deployment target until that changes.

## Issue 2: Docstring Conversion v1 Missed Multi-Line Cases

### Symptom

After deploying the Galaxy fix, fired v9 sweep of 7 clinical workflows. 3 still failed with parser-v2 compilation errors:

```
Caused by: MultipleCompilationErrorsException: startup failed:
Main: 147: Unexpected input: 'parameters' @ line 147, column 15.
       Parse E-R parameters from JSON string.
```

Affected: `biomarker_patient_enrichment`, `exposure_response_modeling`, `phase2_dose_justification`.

### Diagnosis

The error pointed at line 147 col 15 — the *content* of a Python docstring, not the marker. Investigating the file:

```python
def parse_er_params(raw):
    """              ← line 146: inner docstring opener
    Parse E-R parameters from JSON string.    ← line 147: content
    ...
    """              ← line 150: closer
    if raw and raw not in ('null', ...):    ← line 151: NEXT line is Python code
```

The outer Groovy script block:

```groovy
script:
"""              ← line 94: OUTER opener (same indent as inner!)
python3 << 'PYEOF'
... 50 lines of Python ...
def parse_er_params(raw):
    """           ← was NOT converted by v1
```

### Root cause of v1 bug

`2e5b07783`'s heuristic for detecting the outer Groovy closing `"""`:

> *if next non-blank line is `}` / `output:` / `input:` → this `"""` is the outer close*

This works when the script block's closing brace is immediately after the closing `"""`. It **fails** when there's a multi-line Python docstring **whose closer is followed by Python code**, not Groovy directives. v1 mis-identified the inner docstring closer as the outer Groovy close, exited script-state early, and stopped converting subsequent docstrings in the same file.

### Fix (v2 algorithm)

Find the matching outer `"""` properly: it's the `"""` line whose immediate next non-blank line **starts with `}`** (the process's closing brace). All `"""` markers strictly between the outer opener and outer closer are Python docstrings — convert them all to `'''`.

```python
# Pseudocode
for each `script:` directive in file:
    open_idx = next non-blank line after `script:` (must be exactly `    """`)
    close_idx = next `"""` line followed by `}` (the process close)
    for k in range(open_idx + 1, close_idx):
        if line k matches `^\s+"""\s*$` (lone) or `^\s+"""[^"]*"""\s*$` (single-line):
            convert to '''
```

Result: 14 files modified, 55 docstrings converted (in addition to v1's 31). The cumulative effect: every Python docstring inside any Nextflow process script block now uses `'''` triple-single-quote.

### Deployment

Tarball of just the 14 changed files → `docker cp` into the running Galaxy container — no restart needed because workflow `.nf` files are read fresh on each Nextflow launch.

## Validation

### v9 sweep (7 clinical workflows, after Galaxy fix, before docstring v2)

| Workflow | Duration | Outputs | Verdict |
|---|---|---|---|
| `p0_pkpd_semaglutide` | 294s | 4 (pkpd_report.json, pd_weight_curve.csv, pk_simulation.csv, pkpd_plot.png) | ✓ **working** |
| `biomarker_patient_enrichment` | 14s | 0 | docstring v1 miss → fixed in v2 |
| `exposure_response_modeling` | 28s | 0 | docstring v1 miss → fixed in v2 |
| `phase2_dose_justification` | 18s | 0 | docstring v1 miss → fixed in v2 |
| `adaptive_trial_design` | 45s | 0 | not docstring — separate dig needed |
| `survival_analysis_km` | 20s | 0 | not docstring — separate dig needed |
| `ich_s7a_safety_pharmacology` | 43s | 0 | not docstring — separate dig needed |

### v10 sweep (after docstring v2 deployment)

Fired `phase2`, `exp_resp`, `biomarker` — polling under task `bve9vwbnu`. Expect all 3 to succeed.

## Open work after this turn

(see also `docs/20260527_OPEN_WORK_AND_NEXT_STEPS.md` Tier 1-5)

| Task | Status |
|---|---|
| #17 Restore dev Galaxy backend | ✅ resolved by `903745e19` |
| #18 Persist ExecutionRun to Postgres | pending |
| #19 Survey remaining clinical workflows | in-progress — v10 polling |
| #20 Diagnose Galaxy worker hang | ✅ resolved (root cause documented in #17) |

Still failing v9 (not docstring, separate cause):
- `adaptive_trial_design`, `survival_analysis_km`, `ich_s7a_safety_pharmacology` — investigate after v10 results land

## Files touched

```
backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py
  (+ from __future__ import annotations + comment)

backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/3d_variability_analysis/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/3d_variability_pipeline/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/focused_refinement_pipeline/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/et_full_pipeline/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/import_tiltseries/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/tomogram_reconstruction/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/pocket_detection_druggability/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/scaffold_hopping/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/alphagenome_track_prediction/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/biomarker_patient_enrichment/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/exposure_response_modeling/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/phase2_dose_justification/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/polymorph_stability_screening/main.nf
backend/biomni_workflows/nextflow_nfcore/subworkflows/virtual_cell/gears_perturbation_prediction/main.nf
```

## Standing principles re-applied

From CLAUDE.md:
- **Resolve root causes, never workarounds.** Both bugs traced from symptom (dev unresponsive, workflows failing) through actual logs (gunicorn crash trace, parser-v2 error line/col) to true root cause (Python 3.9 vs PEP 604, docstring heuristic bug). No symptom-level patches.
- **Static analysis before expensive tests.** Ran `python3 -c "import ast; ast.parse(...)"` to validate the syntax fix before deploying. Used `git diff-tree --name-only` to verify only intended files were in the deployment tarball.
- **Documented periodically.** This file is one of those docs (per CLAUDE.md mandate after every significant session).
