# 2026-11-15 — Flow cytometry container exit (`analysis-try-sample-data-3`)

**Case:** `analysis-try-sample-data-3` · remasure tip `25a03a72c7` · `runId` `e7aa117b-…`  
**Fail:** `ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING` → Essential container exited

## Root causes (both required)

1. **Unstaged FCS path** — process took `val(meta)` and exported a Galaxy host `projectDir` string. That path is not mounted in the Batch container.
2. **Missing `flowio`** — `workflow-tools` image did not install `flowio`; script imports it for real FCS parsing.

Batch D only closed the prior `PRODUCTION_MD` selector abort; remasure then hit this class.

## Fix (in tree)

| Piece | Change |
|-------|--------|
| `…/analyze_flow_cytometry_immunophenotyping/main.nf` | `path(fcs_file, stageAs: 'input.fcs')`; entry `file(fcs_src, checkIfExists: true)`; stderr on fail; compensation description ignore; `.pydeps` bootstrap if image lacks flowio |
| `backend/docker/workflow-tools/Dockerfile` (+ onprem, `smoke.py`) | bake `flowio` |
| `backend/tests/test_coldstart_batch_d_fixes.py` | stageAs + Dockerfile guards |

## Still needs

- Sync Galaxy / workflows to DEV
- Remasure `BIOMATE_DEEP_FILTER='^analysis-try-sample-data-3$'`
- Optional: rebuild/push `workflow-tools:x86` (bootstrap covers until then)

**Not closed** until remasure rewrites the execshot off container-exit.
