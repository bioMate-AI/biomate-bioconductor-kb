# BioMate Bug Fixes — 2026-04-20

## Summary

5 product bugs found and fixed during demo run analysis.

---

## Fix 1: ANSI Escape Codes in Execution Logs (Critical UX)

**Symptom**: Execution log panels in the workflow viewer showed raw terminal escape
sequences (`[2A`, `[33m200[39m`, `[K`, etc.) making logs unreadable.

**Root cause**: Nextflow, AutoDock Vina, and tqdm emit ANSI color/cursor codes
designed for real TTYs. Log lines were passed through to HTML `<pre>` elements
without stripping.

**Fix**:
- Backend `nextflow_executor.py`: Added `_strip_ansi()` helper, applied at all
  3 `log_tail` read sites.
- Frontend `src/lib/utils.ts`: Added exported `stripAnsi()` utility.
- Frontend `nextflow-workflow-viewer.tsx`: Strip in main log panel + validation log.
- Frontend `step-output-preview.tsx`: Strip in `InlineTextViewer` + structure viewer.
- Frontend `job-log-viewer.tsx`: Strip in `parseLogEntry`.

**Files**: `nextflow_executor.py`, `utils.ts`, `nextflow-workflow-viewer.tsx`,
`step-output-preview.tsx`, `job-log-viewer.tsx`

---

## Fix 2: "Confidence: 0%" Always Showing on Research Responses

**Symptom**: Every AI research response (scientific Q&A) showed "Confidence: 0%"
in the footer, even when no confidence was computed.

**Root cause**: `ResearchResponseDisplay` in `benchmark-evidence.tsx` always
rendered the confidence indicator div regardless of whether `response.confidence > 0`.

**Fix**: Wrapped the confidence + methods footer in a conditional that only renders
when `confidence > 0` OR `methods_used` is non-empty.

**File**: `frontend/client/src/components/benchmark-evidence.tsx`

---

## Fix 3: Post-Run Survey Flash (UX — Demo Suppression)

**Symptom**: Quick Feedback survey briefly appeared over workflow results even
when localStorage suppression was set, because the suppression check fired in a
React `useEffect` (asynchronous, one render after opening).

**Root cause**: `chat-with-artifacts.tsx` set `showPostRunSurvey = true` without
checking suppression. The survey component's own effect dismissed it one cycle
later, but the screenshot captured the flash.

**Fix**: Check `biomate_survey_suppressed_until` in localStorage **before** calling
`setShowPostRunSurvey(true)` — skip the state update entirely if suppressed.

**File**: `frontend/client/src/components/chat-with-artifacts.tsx`

---

## Fix 4: Workflow User Edits Lost on "Confirm & Run" (Critical Data)

**Symptom**: Parameters edited by the user in the workflow panel (e.g., `reads`,
`max_spots`, `pdb_id`, `exhaustiveness`) were silently discarded when the user
clicked "Confirm & Run". The workflow ran with default/empty parameters instead.

**Root cause**: `chat-with-artifacts.tsx` built the execute request with:
```javascript
parameters: workflow.parameters || {},
```
But user edits from the viewer panel flow back via `inline_parameters`, not
`parameters`. The execute handler didn't merge `inline_parameters` into the
final parameter set.

**Fix**:
```javascript
const mergedParams = {
  ...(workflow.parameters || {}),
  ...(workflow.inline_parameters || {}),
};
workflowDefinition = { ...workflow, parameters: mergedParams };
```

**Impact**: Affected every workflow where the user edited any parameter before
running — the edit was visible in the panel but not sent to the backend.

**Evidence**: WGS Germline GATK run `b2f66418` failed immediately with
`params.reads is required` despite user providing `SRR1518169` in the panel.
The Nextflow command only had `--outdir`, no `--reads`.

**File**: `frontend/client/src/components/chat-with-artifacts.tsx`

---

## Fix 5: LLM Parameter Extraction Ignores Explicit User Values

**Symptom**: When a user explicitly provides parameter values in their query
(e.g., `PDB: 1M17`, erlotinib SMILES), the workflow panel shows the schema
default values (7RFS, nirmatrelvir SMILES) instead of the user-specified ones.

**Root cause**: `ai_assistant.py` LLM param fill logic:
```python
if p['name'] in _llm_extracted and not p.get('default')
```
The `not p.get('default')` guard prevented overriding existing schema defaults
even when the LLM extracted an explicit user-specified value. So `pdb_id` with
default `7RFS` was never updated to the user-provided `1M17`.

**Fix**: Remove the `not p.get('default')` guard. LLM-extracted values (from
explicit user mentions) should always override schema defaults.

```python
if p['name'] in _llm_extracted:
    result.append({**p, 'default': str(_llm_extracted[p['name']]), 'llm_extracted': True})
```

**File**: `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

---

---

## Fix 6: Nextflow Startup Noise in Execution Logs (UX)

**Symptom**: Even after ANSI stripping (Fix 1), execution log panels showed
Nextflow startup banners (`N E X T F L O W`, version update notices, dependency
download messages) that add noise without value.

**Root cause**: Nextflow emits startup banners unconditionally on every run.
These lines were included in the 20-line log tail alongside actual process output.

**Fix**: Added `_NF_NOISE_RE` regex pattern and `_clean_log_line()` helper to
`nextflow_executor.py` that both strips ANSI and filters startup noise. All three
`log_tail` construction sites updated to use the new helper. The log window is
also expanded from `lines[-20:]` to `lines[-40:]` before filtering so the 20
remaining lines show actual content.

**Patterns filtered**:
- `N E X T F L O W  ~  version X.Y.Z` (ASCII banner)
- `Nextflow X.Y.Z is available - Please consider updating...`
- `Downloading nextflow dependencies...`
- `nf-core/tools version...`

**File**: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

---

## Fix 7: LLM Param Extraction Skipped for Docking Workflows (Critical UX)

**Symptom**: For workflows where ALL parameters have schema defaults (e.g.
`p0_docking_validation` with `pdb_id=7RFS`, `ligand_smiles=nirmatrelvir`,
`box_center=[-10.2, 17.5, 50.1]`, `exhaustiveness=16`), the LLM param extractor
returned `{}` immediately because the `extractable` filter excluded every param.

**Root cause**: `_infer_params_from_intent_llm` had a `not p.get("default")`
guard that was the same bug as Fix 5 but at the EXTRACTION PHASE, not just the
APPLY phase. Fix 5 fixed the apply phase; this fixes the extraction phase.

**Fix**:
- Removed `not p.get("default")` from the extractable filter in `_infer_params_from_intent_llm`
- Added `_SKIP_NAMES` set for purely technical params (`outdir`, `publish_dir_mode`, etc.)
- Updated LLM prompt to show current defaults and instruct extraction only when user provides a different value
- Updated return value handling to serialize JSON arrays correctly (`json.dumps([22, 2.5, 17])` → `"[22.0, 2.5, 17.0]"`)
- Added `autoFilled: True` to extracted params in `_apply_llm_fill` (mirror of `llm_extracted: True`)

**Impact**: The docking workflow now correctly extracts `pdb_id`, `ligand_smiles`,
`box_center`, `box_size`, and `exhaustiveness` from the user query. The panel will
show the correct extracted values with the blue "AI-recommended" highlight instead
of the wrong schema defaults.

**File**: `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

---

## Fix 8: Demo 5 Query Missing Explicit Box Center for EGFR (Demo)

**Symptom**: Demo 5 query used "centred on the ATP binding site" without
explicit coordinates. With Fix 7, `pdb_id=1M17` is correctly extracted, but
`box_center` would fall back to the Mpro default `[-10.2, 17.5, 50.1]` — wrong
coordinates for EGFR, causing the docking to fail or give nonsensical results.

**Fix**: Updated `DOCKING_QUERY_1` in `demo-05-autoloop-qc.demo.ts` to include
explicit EGFR ATP site coordinates: `box center: [22.0, 2.5, 17.0], box size: 20 Å`.
With Fix 7, these are now extracted by the LLM and override the defaults.

**File**: `frontend/e2e/demo-05-autoloop-qc.demo.ts`

---

## Fix 9: Duplicate `sendAdminAlert` Method (Code Quality)

**Symptom**: TypeScript build warning `duplicate-class-member` in `email-service.ts`.

**Root cause**: Two definitions of `sendAdminAlert` — old `opts: {subject, body}`
form (line 578) and new `(subject, details)` form (line 606). JavaScript uses
the last definition. The first form was dead code; no callers used it.

**Fix**: Removed the dead first definition.

**File**: `frontend/server/email-service.ts`

---

## Fix 10: Demo 1 Docking Query — Single Compound with Explicit Coordinates (Demo)

**Symptom**: Demo 1 docking query said "dock all 5 compounds against BCR-ABL1" but:
1. The docking workflow (`p0_docking_validation`) takes a single `ligand_smiles` parameter — multi-compound requests can't be handled in one run
2. The box center was specified as "residues Thr315, Glu286" (descriptive text), not numeric coordinates — LLM can't extract coordinates from residue names

**Fix**: Updated `DOCKING_QUERY` in `demo-01-drug-discovery.demo.ts` to dock imatinib
(CPD-001) specifically with:
- Explicit imatinib SMILES in the query
- Explicit BCR-ABL1 ATP binding site box center: `[15.0, 34.0, 46.0]`, box size: 25 Å
- These coordinates are now extracted by the LLM (Fix 7) and override schema defaults

**File**: `frontend/e2e/demo-01-drug-discovery.demo.ts`

---

## Deployment

- Frontend: `npm run build` → `dist/` updated (clean, no warnings)
- Backend: `kill -HUP 3038571` → workers reloaded (multiple times during session)
- Demo runner: `frontend/e2e/run-demos.sh` — runs demos 01, 02, 04, 05 with 1920×1080 video
- All changes on branch `integration/next-phase`
