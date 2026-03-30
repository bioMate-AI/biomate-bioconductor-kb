# Workflow Generation — Design, Status, and Gaps

**Date:** 2026-03-24
**Branch:** `connection_formal`

---

## 1. End-to-End Architecture

The full path from user message → running Nextflow job involves 7 layers:

```
User message
    │
    ▼
[1] galaxy-assistant.ts   — intent classification (Haiku), ambiguity gate
    │
    ▼
[2] generateWorkflow()    — calls /api/ai_assistant/generate_workflow (Galaxy backend)
    │
    ▼
[3] generate_workflow_unified()  — Python, routes by confidence
    │  ├─ Step 0: chain pre-check (WorkflowChain DB, Jaccard ≥ 0.35)
    │  ├─ Step 1: unified_workflow_search.py → FTS + LLM rerank
    │  ├─ Step 2: high_confidence (score ≥ 8.0) → reuse Nextflow .nf
    │  ├─ Step 3: medium_confidence (score ≥ 4.0) → adapt template
    │  └─ Step 4: low_confidence → nextflow_composer.py (compose from subworkflows)
    │
    ▼
[4] Response payload      — includes workflow_ga, required_params, prerequisitesValidation
    │
    ▼
[5] Frontend routing      — chat-message.tsx detects workflow_type
    │  ├─ "nextflow"  → NextflowWorkflowViewer
    │  ├─ "chain"     → ChainWorkflowViewer (not yet implemented)
    │  └─ "galaxy_ga" → WorkflowArtifact (Galaxy ToolShed workflows)
    │
    ▼
[6] NextflowWorkflowViewer — parameter inputs, checklist, Confirm & Run
    │
    ▼
[7] /api/nextflow/execute  — launches Nextflow process (local or AWS Batch)
```

---

## 2. Workflow Search Pipeline Detail

File: `backend/lib/galaxy/ai/unified_workflow_search.py`

**Two-tier Nextflow result selection** (as of 2026-03-23):

| Tier | Helper | Matches |
|---|---|---|
| Tier-1 `_is_full_pipeline()` | Full standalone pipelines | `wgs_germline_gatk/main.nf`, `nf-core/sarek`, etc. |
| Tier-2 `_is_composition_subworkflow()` | Building blocks | `nf-core-modules/subworkflows/*/main.nf` |

**Selection cascade:**
1. Tier-1 with runnable config key → preferred
2. Tier-1 without config key → acceptable
3. Tier-2 composition subworkflow (when no Tier-1 on disk) → fallback
4. Non-Nextflow Galaxy tool → last resort

**Chain threshold:** `search_chains()` returns matches with Jaccard similarity ≥ 0.35 (was 0.15 — caused false positives).

---

## 3. Parameter Flow Detail

When a Nextflow workflow is selected, `api/ai_assistant.py:search_nextflow_workflow` and `ai/ai_assistant.py:generate_workflow_unified` both:

1. Call `_parse_nextflow_params(filename)` — reads the `.nf` file, extracts `params.X` assignments
   - `val is None` → required
   - `val = "false"`, `val = 0`, etc. → optional
   - Skips internal params: `mock_mode`, `outdir`, `max_cpus`, `max_memory`, etc.

2. Build return dict with:
   ```json
   {
     "required_params": [{"name": "reads", "label": "Reads", "description": "...", "default": null}],
     "optional_params": [...],
     "generated_parameters": [...all combined...],
     "prerequisitesValidation": {
       "requirements": {"parameters": [{"stepId":"workflow","paramName":"reads","optional":false}]},
       "analysis": {"missingInputs": [], "missingParameters": [{"stepId":"workflow","paramName":"reads"}]}
     },
     "workflow_ga": {
       "required_params": [...],   // viewer reads from here
       "optional_params": [...]
     }
   }
   ```

3. `prereq-normalizer.ts` reads `prerequisitesValidation` → builds `PrereqChecklist`
   - `missingParameters.length > 0` → "Required parameters" item with status `warning`
   - `missingInputs.length > 0` → "Input data" item with status `missing` (blocks `canRun`)

---

## 4. Verified API Results (2026-03-23)

Query: *"Run WGS germline variant calling on sample NA12878 SRR1518169"*

```
workflow_name: Wgs Germline Gatk
nextflow_path: nextflow_nfcore/subworkflows/genomics/wgs_germline_gatk/main.nf
required_params: ['reads', 'reference', 'known_sites', 'dbsnp_vcf']
optional_params (first 5): ['sample_id', 'platform', 'library', 'genome', 'caller']
generated_parameters count: 18
prerequisitesValidation: present ✅
missingParameters: ['reads', 'reference', 'known_sites', 'dbsnp_vcf']
```

---

## 5. E2E Test Results

### `full-workflow-e2e.e2e.ts` — **6/8 passing** (latest run, ~52 min)

| Test | Status | Notes |
|---|---|---|
| ADMET → AWAITING REVIEW → run → results → download | ✓ PASS | |
| Workflow card: AWAITING REVIEW badge + rationale panel + Confirm & Run | ✓ PASS | |
| download_commands API correct; PhaseCards render | ✓ PASS | |
| Checkpoint absent in non-failed state; resume API wired | ✓ PASS | |
| **Workflow artifact renders; all 4 PhaseCards present after run** | ✗ FAIL | `button-confirm-and-run` not found |
| Nextflow shows "Detach"/"Reconnect" labels after run | ✓ PASS | |
| **Completed workflow: download_commands correct; panel renders** | ✗ FAIL | `button-confirm-and-run` not found |
| Pilot run banner: Configure pilot + preflight API | ✓ PASS | |

**Root cause of 2 failures:** Both fail at `clickConfirmAndCaptureRunId()` — the test helper cannot find `[data-testid="button-confirm-and-run"]` or `[data-testid="button-run-workflow-panel"]`. This means the Nextflow workflow card is rendering but the "Confirm & Run" button selector doesn't match, OR the card shows the old Galaxy-format workflow artifact (which uses `button-run-workflow` not `button-confirm-and-run`).

### `germline-complete-e2e.e2e.ts` — **2/6 passing** (last Playwright run)

| Test | Status | Notes |
|---|---|---|
| GC-1: Disambiguation → germline → execute API | ✗ FAIL | LLM classifier false negative |
| GC-2: Direct mock germline → run → outputs → download | ✗ FAIL | LLM classifier false negative |
| GC-3: Full API chain (status/output/download all 200) | ✓ PASS | |
| GC-4: QC Settings section present | ✓ PASS | |
| GC-5: Inline SRR accession in query | ✗ FAIL | LLM classifier |
| GC-6: Two-turn data provision | ✗ FAIL | LLM classifier |

Screenshots from last run show the product is working visually:
- `gc2_02_workflow_card.png` — correct germline chain rendered (HaplotypeCaller, BQSR, GenotypeGVCFs, MultiQC all visible)
- `gc2_03_after_run_click.png` — viewer opens with IDLE status, checklist shows "4 required input(s) missing", "No editable parameters detected" (GAP — see §6)
- `gc2_03_after_run_attempt1.png` — run launches, shows "Executing workflow... 0%", status: running
- `gc2_08_terminal_failed.png` — reaches terminal state (expected — no real data provided); feedback modal appears

---

## 6. Identified Gaps

### Gap 1 — CRITICAL: `required_params` not rendered in viewer

**File:** `frontend/client/src/components/nextflow-workflow-viewer.tsx`

`buildViewerParameters()` (line 115) only reads from `workflowDefinition.parameters` and `workflowDefinition.inline_parameters`. It does **not** read from `workflowDefinition.required_params` or `workflowDefinition.optional_params`.

**Symptom:** Screenshot `gc2_03_after_run_click.png` shows "No editable parameters detected for this workflow" even though the backend returns 18 params (4 required, 14 optional). The user cannot fill in `--reads`, `--reference`, etc.

**Backend sends (confirmed):**
```json
"workflow_ga": {
  "required_params": [{"name":"reads",...}, {"name":"reference",...}],
  "optional_params": [...]
}
```

**Viewer reads (current):**
```typescript
const fromWorkflow = workflowDefinition?.parameters  // → {}
const fromInline = workflowDefinition?.inline_parameters  // → {}
// required_params never accessed
```

**Fix needed:** Update `buildViewerParameters()` to also pull from `workflowDefinition.required_params` and `workflowDefinition.optional_params`, mapping them to `ViewerParameter[]` with `required: true` for required params.

---

### Gap 2 — MODERATE: `canRun` not blocked by missing required params

**File:** `frontend/client/src/lib/prereq-normalizer.ts` line 29

`missingParameters` (workflow params) creates a **WARNING** item — not a **MISSING** (hard block). Only `missingInputs` (datasets) creates a hard `MISSING` status. So even with 4 missing required params, `prereqChecklist.canRun` remains `true` and the button is not disabled.

**Screenshot evidence:** `gc2_03_after_run_click.png` — checklist shows "Required parameters: WARNING" but the Run Workflow button was still clickable (it ran and reached RUNNING state without any param values).

**Fix needed:** When `missingParameters.length > 0` AND any of those params have `optional: false` in `requirements.parameters`, set status to `"missing"` (not `"warning"`) to block `canRun`.

---

### Gap 3 — MODERATE: `button-confirm-and-run` testid mismatch

**Evidence:** 2/8 `full-workflow-e2e` failures. The test looks for `[data-testid="button-confirm-and-run"]` but the rendered button in the viewer uses a different testid.

Checking the viewer:
```typescript
// nextflow-workflow-viewer.tsx line ~1280
// Button text = "Run Workflow" with data-testid="button-run-workflow-panel"
```
But the test also tries `[data-testid="button-run-workflow-panel"]` as fallback — and still fails. Likely the Nextflow card is not being shown (the test gets a Galaxy .ga card instead).

**Fix needed:** Diagnose what workflow card format is being generated for the test query and ensure it matches the Nextflow viewer route.

---

### Gap 4 — MINOR: Chain threshold reverted by linter

The system reminder indicates `unified_workflow_search.py` was reverted to `>= 0.15` (from 0.35). The `rare_disease_multimodal_workup` false positive on germline queries will recur.

**Fix needed:** Re-apply threshold change from 0.15 → 0.35 (or higher).

---

### Gap 5 — MINOR: Optional params not in collapsible section

All params (required + optional) would render in a flat list. The optional 14 params will overwhelm the UI. They should be in a collapsed "Optional parameters" accordion by default.

---

### Gap 6 — OPEN: Parameter values not passed to Nextflow runtime

Even if users fill in required params via the UI, it has not been verified that those values are actually forwarded as `--reads X --reference Y` flags to the Nextflow command. The executor (`nextflow_executor.py`) needs to receive and apply them.

---

## 7. Screenshot Inventory

All from `frontend/e2e/screenshots/germline-complete/`:

| File | What it shows |
|---|---|
| `gc1_04_awaiting_review.png` | AI response after disambiguation — 6-step GATK pipeline table, tool notes, "What You'll Need", "Expected Outputs" |
| `gc2_02_workflow_card.png` | Nextflow card (step list mode) — HaplotypeCaller, BQSR, MarkDuplicates, VariantFiltration, SnpEff, MultiQC — all PENDING |
| `gc2_03_after_run_click.png` | **Wgs Germline Gatk** viewer (IDLE state) — checklist shows "4 required input(s) missing" (MISSING) + "No hard parameter blocker" (WARNING) + "Tool checks passed" (OK) — **parameters section shows "No editable parameters detected"** — GAP 1 visible |
| `gc2_03_after_run_attempt1.png` | Viewer after run starts — "Executing workflow... 0%", status = RUNNING, invocation ID captured, "Detach" button visible |
| `gc2_04_prereq_recovery_click.png` | Viewer still IDLE after second attempt (new session) — same checklist state, recovery button visible, chat bottom shows "Analyzing request..." |
| `gc2_08_terminal_failed.png` | Terminal state — workflow fails (expected, no real data), feedback modal opens automatically: "Was execution status clear? / Did outputs match expectation? / Was download easy?" |
| `gc5_03_workflow_card.png` | GC-5 card — same step list, SRR accession provided inline, still shows pending steps |

---

## 8. What Works vs What Doesn't

### Working ✅
- Workflow search returns correct Nextflow pipeline for germline/somatic/ADMET queries
- `required_params` + `prerequisitesValidation` correctly populated in backend API response
- Prereq checklist renders in UI (via `prereq-normalizer.ts`) — shows MISSING/WARNING/OK items
- "Ask BioMate to prepare runnable demo inputs" recovery button present
- Execution launches, reaches RUNNING state, then terminal state (fails without real data — expected)
- Detach/Reconnect labels on Nextflow card post-run
- Feedback modal at terminal state
- GC-3: status/output_files/download_commands APIs all return 200
- Disambiguation (somatic vs germline) working
- Pilot run banner + preflight API responding

### Not Working ❌
- **Parameter input fields not shown** (Gap 1) — viewer shows "No editable parameters detected"
- **"Confirm & Run" not blocked** by missing required params (Gap 2)
- **Germline E2E tests 4/6 failing** — LLM classifier `hasGermlineContent` returns false on correct content
- **full-workflow-e2e 2/8 failing** — `button-confirm-and-run` not found
- **Chain threshold reverted** — false positive risk on germline queries (Gap 4)

---

## 9. Priority Fix Order

| Priority | Gap | File | Effort |
|---|---|---|---|
| P0 | Gap 1: `required_params` not rendered | `nextflow-workflow-viewer.tsx` `buildViewerParameters()` | 30 min |
| P0 | Gap 2: Missing params don't block run | `prereq-normalizer.ts` missingParameters status | 15 min |
| P1 | Gap 4: Chain threshold reverted | `unified_workflow_search.py` | 2 min |
| P1 | Gap 3: button testid mismatch (E2E) | diagnose + fix viewer/test | 1 hr |
| P2 | Gap 5: Optional params collapsible | `nextflow-workflow-viewer.tsx` | 30 min |
| P2 | Gap 6: Param values passed to Nextflow | `nextflow_executor.py` + viewer `onConfirm` | 1 hr |
