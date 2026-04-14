# 2026-04-10 Session: Workflow Routing Fix + Processing Step Indicator

## Summary

Two bug fixes and one UX enhancement shipped in this session:
1. Processing step progress indicator during AI thinking
2. `get_workflow_by_name` path-matching bug that caused wrong workflow routing
3. 3D Variability Pipeline tag corruption that amplified the routing bug

---

## 1. Processing Step Progress Indicator

### Problem
The typing indicator showed only "BioMate is thinking..." for the entire duration of multi-step AI processing (which can take 10–30+ seconds). Users had no visibility into what was happening.

### Root Cause
The SSE stream already emits `tool_event` messages with `type: 'tool_call'` and `type: 'tool_result'` when the backend invokes a tool. These events were consumed but not surfaced in the UI.

### Fix

**`frontend/client/src/components/typing-indicator.tsx`**
- Added optional `stepLabel?: string` prop
- Displays `stepLabel` when provided; falls back to `'BioMate is thinking...'`
- Label text uses `transition-all duration-300` for smooth updates between steps

**`frontend/client/src/components/chat-interface.tsx`**
- Added `processingStepLabel` state (`useState<string | undefined>`)
- In SSE `tool_event` handler:
  - On `type === 'tool_call'`: map tool name → human-readable label, set state
  - On `type === 'tool_result'`: clear label (back to default "thinking...")
- On `delta` text arrival: clear label (streaming response has started)
- On all 3 `setIsTypingLocal(false)` call sites: also clear `processingStepLabel`
- `TypingIndicator` rendered with `stepLabel={processingStepLabel}`

**Tool name → label mapping:**
```
search_nextflow_workflow  → "Searching available workflows..."
search_galaxy_workflow    → "Searching available workflows..."
search_workflow           → "Searching available workflows..."
generate_workflow         → "Generating workflow..."
validate_prerequisites    → "Validating prerequisites..."
search_datasets           → "Looking up datasets..."
retrieve_knowledge        → "Retrieving domain knowledge..."
search_tools              → "Identifying best tools..."
build_parameters          → "Configuring parameters..."
check_credentials         → "Checking credentials..."
analyze_intent            → "Analyzing your request..."
(any other tool)          → "Processing: <tool name with underscores→spaces>..."
```

---

## 2. `get_workflow_by_name` Path-Matching Bug

### Problem
The query "I want to run single-particle analysis on EMPIAR-10028 (apoferritin). Process the cryo-EM movies through CryoSPARC..." routed to "3D Variability Pipeline" instead of "CryoSPARC Standard Single-Particle Analysis", causing a timeout error.

### Root Cause (traced from backend logs)
`_try_direct_workflow_lookup` in `ai_assistant.py` scans the user query for snake_case/kebab-case identifiers and calls `get_workflow_by_name()` for each match. The query contained "cryo-EM" which was extracted and normalized to "cryo_em".

In `get_workflow_by_name()` the old LIKE pattern was:
```python
filename_pattern_slash = f"%/{normalised}/%"  # matches ANY file under /cryo_em/ directory
```

This pattern `%/cryo_em/%` matches:
- `.../cryo_em/cryosparc_standard_spa/main.nf` ✓ (correct)
- `.../cryo_em/3d_variability_pipeline/main.nf` ✓ (wrong — domain dir, not workflow name)
- `.../cryo_em/helical_spa_pipeline/main.nf` ✓ (wrong)
- etc.

SQLite `LIMIT 1` returned whichever row happened to be first — the 3D Variability Pipeline.

### Fix — `backend/lib/galaxy/ai/unified_workflow_search.py`

Changed the LIKE pattern to anchor to the workflow's own directory:
```python
# Before (WRONG — matches domain directory):
filename_pattern_slash = f"%/{normalised}/%"

# After (CORRECT — matches workflow's own main.nf):
filename_pattern_main = f"%/{normalised}/main.nf"
filename_pattern_end  = f"%/{normalised}.nf"

cursor.execute("""
    SELECT id, name, description, domain, source, format,
           step_count, tools_used, tags, filename, workflow_json,
           0.0 as fts_score, input_types, output_types
    FROM workflows
    WHERE REPLACE(LOWER(name), '-', '_') = ?
       OR REPLACE(LOWER(filename), '-', '_') LIKE ?
       OR REPLACE(LOWER(filename), '-', '_') LIKE ?
    LIMIT 1
""", (normalised, filename_pattern_main, filename_pattern_end))
```

Now `cryo_em` only matches if a workflow's `main.nf` lives at `.../cryo_em/main.nf`, which doesn't exist (the actual SPA workflow is at `.../cryosparc_standard_spa/main.nf`). The lookup correctly returns no match for "cryo-EM", allowing semantic search to find the right workflow by name/description.

---

## 3. 3D Variability Pipeline Tag Fix

### Problem
Even after fixing the path bug, the 3D Variability Pipeline ranked highly for SPA queries because it had `"spa"` in its tags — a tag that was incorrectly added.

### Fix — `backend/database/galaxy_ai_tools.db`

**Before:**
```json
tags: ["cryo_em", "cryosparc", "spa", "3d_variability", "conformational_heterogeneity", "heterogeneity"]
```

**After:**
```json
tags: ["cryo_em", "cryosparc", "3d_variability", "conformational_heterogeneity", "heterogeneity", "multi_state", "continuous_motion", "3dva"]
```

Changes:
- Removed `"spa"` (incorrect — 3DVA is not SPA)
- Added `"multi_state"`, `"continuous_motion"`, `"3dva"` (accurate descriptors)

Since `workflows_fts` only has an INSERT trigger (no UPDATE trigger), manually synced the FTS index:
```sql
DELETE FROM workflows_fts WHERE rowid = 12836;
INSERT INTO workflows_fts(rowid, name, description, domain, tags, tools_used, input_types, output_types)
VALUES (12836, <name>, <description>, <domain>, <new_tags>, <tools_used>, <input_types>, <output_types>);
```

---

## 4. Post-Fix Routing Verification

After all fixes, the EMPIAR-10028 SPA query correctly:
1. `_try_direct_workflow_lookup` finds no exact match for "cryo-em" (correct — no workflow named "cryo_em")
2. Semantic search finds "CryoSPARC Standard Single-Particle Analysis" with score=84.10
3. `_check_and_reroute_for_credentials` detects no CryoSPARC license configured → reroutes to RELION (expected behavior on dev environment without CryoSPARC credentials)

---

## 5. Sync to EC2 Dev

All changes synced via `scripts/sync_to_dev.sh`:
- Frontend Docker image rebuilt and pushed to EC2 (`biomate-dev-frontend` container)
- Backend Python files synced (including `ai_assistant.py`, `unified_workflow_search.py`)
- `galaxy_ai_tools.db` uploaded to S3 → pulled down on EC2

**Note:** Galaxy container on EC2 requires 30+ minutes to initialize (tool loading). During this window the container reports "unhealthy" but the frontend is operational. Galaxy will become healthy once tool loading completes.

---

## Files Changed

| File | Change |
|------|--------|
| `frontend/client/src/components/typing-indicator.tsx` | Added `stepLabel` prop |
| `frontend/client/src/components/chat-interface.tsx` | `processingStepLabel` state + tool event handler |
| `backend/lib/galaxy/ai/unified_workflow_search.py` | Fixed `get_workflow_by_name` LIKE pattern |
| `backend/database/galaxy_ai_tools.db` | Fixed 3DVA pipeline tags + FTS sync |
