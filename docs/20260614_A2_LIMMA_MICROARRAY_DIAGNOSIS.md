# A2 e2e — microarray + limma returns `workflow_failed`

**Status:** Deterministic (3/3 retries on dev), not a flake.
**Detected by:** `scripts/e2e_use_cases.sh` Flow A scenario A2.
**Date:** 2026-06-14

## Symptom

Sending `"Run DEG on the gse22055 microarray with limma, tumor vs normal"` to `/api/chat/stream` returns:

- `state="workflow_failed"`
- Response body contains the substring "limma" twice (so the LLM did identify the tool)
- ~2516 bytes total — no `workflow_ready` event

## Root cause (most likely)

`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/limma/single_channel_microarray_analysis.nf` declares **no `params.*` block** and ships **no `nextflow_schema.json`**.

When the router picks this workflow for a microarray + limma query, `_get_workflow_params()` (`backend/lib/galaxy/ai/ai_assistant.py:2429`) returns `{"required": [], "optional": []}`. The R script inside the .nf file then reads `targets.txt` and `.CEL` files at runtime (line 70: `targets <- readTargets("targets.txt")`), which don't exist for an LLM-only context. The validation gate downstream of `_return_nextflow_match` sees no declared inputs but the workflow object fails a structural / readiness check, and emits `workflow_failed` instead of `workflow_ready`.

(The Explore agent traced this through `_return_nextflow_match` at line 3110-3145 and the `runnableWorkflow` check at `frontend/server/routes.ts:5446-5453`. Both gates check `success / error / nextflow_path` — neither checks parameter fulfilment at definition time, so the failure must come from an exception in the param-inference path raising the outer try-catch at `ai_assistant.py:4090`.)

## Fix direction (not yet applied)

Two options, in increasing order of work:

1. **Add a minimal `nextflow_schema.json`** next to the limma `.nf` declaring `targets_file` (file, required) and `cel_dir` (file, required). The runnable-workflow gate will then correctly route to `needs_input` instead of `workflow_failed`, and the user gets a "drag-drop targets.txt + CEL files" prompt rather than a silent failure.

2. **Long-term:** the routing layer for microarray DEG should prefer the Bioconductor chain (`bioc/limma/microarray_DEG`) which has a proper params schema, over the bare nf-core stub. Add a routing rule in `frontend/server/galaxy-assistant.ts` for `microarray + limma` → bioconductor chain.

Option 1 is the surgical fix (≤30 lines, no routing churn) and is the right next step.

## Test impact

Once fixed, A2 in `scripts/e2e_use_cases.sh` will pass with the existing assertion (`workflow_ready|needs_input|workflow_generation`). No harness change required.
