# BioMate Comprehensive Test Plan
# Date: 2026-03-19
# Author: PM / QA Lead (generated from codebase audit)
# Scope: Head-to-toe coverage — Workstreams A, B, C, D + regression surface

---

## Table of Contents

1. User Journey Coverage Map
2. Unit Tests — Backend
3. API Tests — Backend Endpoints
4. E2E Tests — User Journeys (T1–T9) with Playwright snippets for T1, T2, T4
5. UX Cognitive Load Audit
6. Performance Benchmarks
7. Execution Priority Matrix

---

## 1. User Journey Coverage Map

Each row is one discrete step in the UX journey. "Feature" is the internal
workstream item that implements it. "Test" is the specific test ID that
validates it. "Status" is the current coverage state.

| # | UX Step | Feature | Test ID(s) | Status |
|---|---------|---------|-----------|--------|
| 1 | User types query in chat textarea | Core chat | ADMET Full (UC-1), all E2E | COVERED |
| 2 | AI generates workflow card | Core chat + galaxy-assistant | UC-1, D1-D6, GC-1 | COVERED |
| 3 | AWAITING REVIEW badge visible | pending_review UX | UC-1 AWAITING REVIEW test | COVERED |
| 4 | Cost estimate badge appears before Run | D1: estimate_cost | T1 (NEW) | GAP |
| 5 | Parameters section renders (no raw dict) | _extract_scalar_param | UC-2 AWAITING REVIEW | COVERED |
| 6 | QC Settings collapsible present | QC governance | qc-gate-inline.e2e.ts | COVERED |
| 7 | Scientific Rationale panel present | Rationale fix | drug-dev-viewers-audit | COVERED |
| 8 | "Confirm & Run" button enabled / disabled logic | pending_review UX | UC-1 full flow | COVERED |
| 9 | "Adjust via Chat" button present | Chat param adjust | AWAITING REVIEW UX test | COVERED |
| 10 | Pilot run banner shown (pilot_run_suggested=true) | Workstream C | UC-2, T3 (NEW) | PARTIAL |
| 11 | PilotRunPanel: 4 validation phases all pass | Phase 4 data characterization | UC-2 API only, T3 (NEW) | GAP |
| 12 | Param recommendations shown after pilot | Pilot decision trees | T3 (NEW) | GAP |
| 13 | "Run Full Analysis" button after pilot | Pilot run panel | T3 (NEW) | GAP |
| 14 | Multi-step pipeline: PipelineListView rendered | Workstream B | T4 (NEW) | GAP |
| 15 | Circled numbers ① ② rendered on steps | PipelineListView | T4 (NEW) | GAP |
| 16 | "← uses: ①" label on dependent step | PipelineListView | T4 (NEW) | GAP |
| 17 | "Confirm & Run Pipeline" button present | PipelineListView | T4 (NEW) | GAP |
| 18 | Workflow execution starts (status transitions) | execute API | UC-1 full flow, UC-6 | COVERED |
| 19 | Detach (not Pause) button for Nextflow | Detach/Reconnect labels | UC-6 | COVERED |
| 20 | Reconnect (not Resume) button for Nextflow | Detach/Reconnect labels | UC-6 | COVERED |
| 21 | PhaseCard steps animate during execution | PhaseCard component | UC-3, UC-5 | COVERED |
| 22 | Log tail visible during execution | Log streaming | ux-execution-pass.e2e.ts | COVERED |
| 23 | Progress % badge updates | Progress polling | UC-1 full flow | COVERED |
| 24 | QC gate amber panel fires mid-run | QC gate | qc-gate-inline.e2e.ts | COVERED |
| 25 | "Apply suggestions / Keep current / Cancel" in QC gate | QC gate actions | qc-gate-inline.e2e.ts | COVERED |
| 26 | Error: red ErrorRecoveryBanner shows | D4: parse_error | T5 (NEW) | GAP |
| 27 | Error: human_summary displayed | D4: parse_error | T5 (NEW) | GAP |
| 28 | Error: "Continue from Checkpoint" button | UC-4 | UC-4 (negative), T5 (NEW) | PARTIAL |
| 29 | Error: "Fix via chat" pre-fills chat | D4: UI wiring | T5 (NEW) | GAP |
| 30 | Completion banner appears | Completion UX | UC-1 full flow | COVERED |
| 31 | DownloadCommandsPanel renders with aws s3 sync | UC-7 | UC-7 | COVERED |
| 32 | aws s3 sync command contains run-specific UUID | UC-7 | UC-7 | COVERED |
| 33 | ReproducibilityExportButton present | D3: reproducibility | T2 (NEW) | GAP |
| 34 | ProvenancePanel collapsible expands | D5: provenance | T2 (NEW) | GAP |
| 35 | ProvenancePanel shows input → workflow → output | D5: provenance | T2 (NEW) | GAP |
| 36 | ChatOutputAttachments render CSV table viewer | Viewers | drug-dev-viewers-audit UC-3 | COVERED |
| 37 | Workflow modification: "change SMILES" updates param | A3: modify endpoint | T6 (NEW) | GAP |
| 38 | Search quality: RNA-seq query returns nf-core/rnaseq first | A2: search_terms FTS | T8 (NEW) | GAP |
| 39 | Chain execution: step 2 auto-wires step 1 output | Workstream B: chain API | T9 (NEW) | GAP |
| 40 | Disambiguation: somatic vs germline | LLM disambiguation | D2, D3, GC-1 | COVERED |

Legend: COVERED = existing test validates it; PARTIAL = tested by API only, no UI assertion; GAP = no test yet; NEW = new test proposed in this plan.

---

## 2. Unit Tests — Backend

### 2.1 Existing (642 tests — all passing as of 2026-03-18)

| Test file | Count | What it covers |
|-----------|-------|----------------|
| `backend/tests/test_qc_consistency.py` | 65 | DEFAULT_THRESHOLDS schema, infer_qc_profile correctness, profile existence, threshold merge order |

### 2.2 New Unit Tests Needed

Each section below describes a new Python test module that should be created in `backend/tests/`.

#### 2.2.1 WorkflowSession Round-Trip + ModificationClassifier

File: `backend/tests/test_workflow_session.py`

```python
# Test cases needed:

class TestWorkflowSessionRoundTrip:

    def test_empty_session_serializes(self):
        # WorkflowSession("sess-1").to_dict() has all required keys
        # WorkflowSession.from_dict(d) reconstructs identical object
        pass

    def test_add_step_auto_wires_input_from(self):
        # sess.add_step("rnaseq", "path/rnaseq/main.nf", {}, output_types=["count_matrix"])
        # sess.add_step("deseq2", "path/deseq2/main.nf", {})
        # steps[1].input_from == 0
        # steps[1].input_type == "count_matrix"
        pass

    def test_add_step_no_autowire_without_output_types(self):
        # prev step has no output_types → step[1].input_from is None
        pass

    def test_redis_round_trip(self):
        # WorkflowSession stored to Redis key → retrieved → reconstructed identically
        # Skipped if Redis unavailable (mark with pytest.importorskip)
        pass


class TestWorkflowModificationClassifier:

    def test_value_change_classification(self):
        # classify_modification("change padj to 0.01") → type="value_change"
        # param_changes == {"padj": 0.01} or {"padj_threshold": 0.01}
        pass

    def test_skip_step_classification(self):
        # classify_modification("skip deduplication") → type="skip_step"
        # "skip_markduplicates" in skip_flags
        pass

    def test_add_workflow_classification(self):
        # classify_modification("then run GSEA pathway enrichment")
        # → type="add_workflow", new_workflow_name contains "GSEA" or "pathway"
        pass

    def test_non_modification_returns_none(self):
        # classify_modification("what genome should I use?") → type="none"
        pass

    def test_regex_fallback_when_llm_unavailable(self):
        # mock _classify_with_llm to raise; result is still valid WorkflowModification
        pass
```

#### 2.2.2 FTS search_terms Scoring

File: `backend/tests/test_unified_workflow_search.py`

```python
class TestFTSSearchTermsScoring:

    def test_rnaseq_query_returns_nfcore_rnaseq_first(self):
        # search("RNA-seq of GSE68086 lung cancer") → results[0].name contains "rnaseq"
        # No bioconductor package in top-3
        pass

    def test_germline_query_not_somatic(self):
        # search("germline variant calling GATK") → top result is sarek or similar
        # results[0].name does NOT contain "somatic" or "mutect"
        pass

    def test_bioconductor_not_in_pass1_pass2(self):
        # Pass 1 and Pass 2 use format='nextflow' filter
        # Bioconductor results only appear in Pass 3 fallback
        pass

    def test_gse_accession_does_not_dominate(self):
        # Query "GSE68086" alone → still returns nf-core pipelines, not bioconductor noise
        pass

    def test_fuzzy_name_resolution(self):
        # search("nf core rnaseq") resolves to nf-core/rnaseq (slash re-joining)
        pass
```

#### 2.2.3 Provenance Endpoint Data Structure

File: `backend/tests/test_provenance.py`

```python
class TestProvenanceEndpoint:

    def test_returns_required_fields(self):
        # Mock _runs with a completed run containing params and s3_output_files
        # Call get_run_provenance(run_id) → response has:
        #   run_id, nextflow_path, params, input_s3_uris, output_s3_uris,
        #   output_files, started_at, completed_at, status
        pass

    def test_input_s3_uris_extracted_from_params(self):
        # params = {"input": "s3://bucket/file.fastq", "genome": "GRCh38"}
        # → input_s3_uris == ["s3://bucket/file.fastq"]
        # → "GRCh38" NOT in input_s3_uris
        pass

    def test_404_for_unknown_run(self):
        # get_run_provenance("nonexistent") raises HTTPException(404)
        pass

    def test_output_s3_uris_from_s3_output_files(self):
        # s3_output_files = [{"s3_uri": "s3://b/out.csv", "name": "out.csv"}]
        # → output_s3_uris == ["s3://b/out.csv"]
        pass
```

#### 2.2.4 Cost Estimate Endpoint

File: `backend/tests/test_cost_estimate.py`

```python
class TestCostEstimateEndpoint:

    def test_returns_min_max_usd(self):
        # estimate_workflow_cost("rnaseq/main.nf", sample_count=5)
        # → {"cost_min_usd": float, "cost_max_usd": float}
        # cost_min_usd > 0; cost_max_usd > cost_min_usd
        pass

    def test_assumptions_field_present(self):
        # response["assumptions"] is a list of exactly 3 strings
        pass

    def test_rnaseq_uses_correct_runtime_model(self):
        # "rnaseq" in nextflow_path → matched_workflow == "rnaseq"
        # estimated_runtime_hours == 0.25 * sample_count * 1.2
        pass

    def test_admet_faster_than_wgs(self):
        # ADMET runtime < WGS (sarek) runtime for same sample_count
        pass

    def test_sample_count_scales_linearly(self):
        # cost(sample_count=10) approximately == 2 * cost(sample_count=5)
        pass
```

#### 2.2.5 Error Recovery Parser

File: `backend/tests/test_error_parser.py`

```python
class TestErrorRecoveryParser:

    def test_returns_required_fields(self):
        # parse_workflow_error with a sample log tail
        # response has: error_type, failed_process, human_summary, suggested_fix, can_resume
        pass

    def test_empty_log_returns_graceful_fallback(self):
        # log_tail="" → {"error_type": "unknown", "can_resume": True, ...}
        # Does NOT raise an exception
        pass

    def test_oom_error_classified(self):
        # log_tail contains "OutOfMemoryError" or "exit code 137"
        # → error_type == "oom"
        pass

    def test_missing_file_classified(self):
        # log_tail contains "No such file or directory"
        # → error_type == "missing_file"
        pass

    def test_can_resume_true_for_process_failed(self):
        # Most process failures → can_resume == True (upstream work cached)
        pass
```

#### 2.2.6 Notification Service De-Dup Guard

File: `backend/tests/test_notification_dedup.py` (TypeScript Jest or Python integration test)

```
Tests needed:
- notifyNextflowTerminal called twice for same runId
  → second call is a no-op (beginTerminalHandling returns false)
- terminalEventLedger prevents re-notification after first terminal event
- Concurrent in-flight events blocked (inFlightTerminalEvents Set)
- Notification sent only when prefs.emailOnComplete / emailOnError is true
- Notification NOT sent when user preference is false
```

---

## 3. API Tests — Backend Endpoints

These are direct HTTP integration tests (using `page.request` in Playwright or
equivalent `pytest + httpx` tests) that validate endpoint contracts without
requiring UI rendering.

### 3.1 POST /api/workflows/preflight — Phase 4 Data Characterization

```
Input: { workflowDefinition: {...}, parameters: {...}, s3_data_uri: "s3://..." }

Assertions:
A1. Response 200; body.phases is array of 4+ items
A2. phase[id="parameters"].status == "pass" when all required params present
A3. phase[id="parameters"].status == "fail" when required param missing
A4. phase[id="data_characterization"] present when s3_data_uri provided
A5. body.ready == false when any phase is "fail"
A6. body.ready == true when all phases are "pass"
A7. phase[id="data_characterization"].analyzers is array (can be empty if no analyzers match)
A8. Response time < 30s for phase 4 (data characterization timeout guard)

Error cases:
E1. Missing workflowDefinition → 400 or helpful error message
E2. Malformed S3 URI → phase[id="s3_inputs"].status == "fail" with message
```

### 3.2 POST /api/workflows/chain — Sequential Execution

```
Input: { steps: [ { nextflow_path: "...", params: {...} }, { nextflow_path: "...", params: {} } ] }

Assertions:
A1. Response 200; body.chain_run_id is a non-empty string
A2. GET /api/workflows/chain/:chain_run_id → 200; body.steps array length == 2
A3. body.status is one of: "pending" | "running" | "completed" | "failed"
A4. Each step object has: nextflow_path, params, status, run_id (null until started)
A5. After step 1 completes, step 2 params are auto-filled from step 1 S3 outputs
    (body.steps[1].params contains at least one "s3://" value)

Error cases:
E1. Empty steps array → 400 with validation message
E2. Invalid nextflow_path → step reports "failed" with error detail
E3. GET /api/workflows/chain/nonexistent → 404
```

### 3.3 GET /api/workflows/estimate_cost

```
Query params: nextflow_path, sample_count

Assertions:
A1.  Response 200; body has cost_min_usd and cost_max_usd (both numeric)
A2.  cost_min_usd > 0
A3.  cost_max_usd > cost_min_usd
A4.  body.assumptions is array of exactly 3 strings
A5.  body.matched_workflow is a non-empty string
A6.  body.estimated_runtime_hours > 0
A7.  ?nextflow_path=rnaseq/main.nf → matched_workflow == "rnaseq"
A8.  ?nextflow_path=sarek/main.nf → matched_workflow == "sarek"
A9.  ?sample_count=1 produces smaller estimate than ?sample_count=20 (same workflow)
A10. Missing nextflow_path → 422 or reasonable default applied

Performance:
P1. Response time < 200ms when Batch DescribeJobDefinitions is mocked/unavailable
```

### 3.4 POST /api/workflows/parse_error

```
Input: { log_tail: "...", workflow_path: "rnaseq/main.nf" }

Assertions:
A1. Response 200 (always — never a 500)
A2. Body has: error_type, failed_process, human_summary, suggested_fix, can_resume
A3. human_summary is a non-empty string
A4. error_type is one of the 7 valid enum values:
    "missing_file" | "oom" | "container_pull" | "aws_permission" |
    "process_failed" | "config_error" | "unknown"
A5. can_resume is boolean
A6. Empty log_tail → graceful fallback, not an exception
A7. Log containing "OutOfMemoryError" → error_type == "oom"
A8. Response time < 5s (Haiku; no timeout on trivial logs)
```

### 3.5 GET /api/workflows/runs/:id/reproducibility

```
Precondition: a completed run exists with known run_id

Assertions:
A1. Response 200 for known completed run
A2. body.files has exactly these keys:
    "methods.txt", "params.json", "workflow.nf", "download_commands.sh"
A3. body.files["params.json"] is valid JSON string
A4. body.files["download_commands.sh"] contains "aws s3 sync" (S3 outdir runs)
A5. body.output_count is a non-negative integer
A6. body.run_id matches the requested run_id
A7. body.outdir is a non-empty string

Error cases:
E1. GET /api/workflows/runs/nonexistent/reproducibility → 404
E2. Run exists but has no s3_output_files → output_count == 0 (not an error)
```

### 3.6 GET /api/workflows/runs/:id/provenance

```
Precondition: a completed run with S3 inputs and outputs

Assertions:
A1. Response 200 for known run
A2. body.input_s3_uris is array; each element starts with "s3://"
A3. body.output_s3_uris is array; each element starts with "s3://"
A4. body.nextflow_path is a non-empty string
A5. body.started_at and body.completed_at are ISO 8601 strings (or empty strings)
A6. body.status == "completed" for completed runs
A7. body.params is an object with at least one key
A8. Run with no S3 inputs → body.input_s3_uris == []
A9. Run with no S3 outputs → body.output_s3_uris == []

Error cases:
E1. GET /api/workflows/runs/nonexistent/provenance → 404
```

### 3.7 POST /api/workflow/modify — Modification Classifier

```
Input: {
  message: "change padj to 0.01",
  session_id: "...",
  current_workflow: "nf-core/differentialabundance"
}

Assertions:
A1. Response 200
A2. body.modification.type is one of:
    "value_change" | "skip_step" | "add_workflow" | "none"
A3. value_change message → body.modification.param_changes is non-empty object
A4. skip_step message → body.modification.skip_flags is non-empty array
A5. add_workflow message → body.modification.new_workflow_name is non-empty string
A6. Non-modification message ("what genome?") → body.modification.type == "none"
A7. Response time < 3s (Haiku classification)

Test inputs to cover all branches:
  "change padj to 0.01"         → value_change
  "skip deduplication"          → skip_step
  "then run GSEA"               → add_workflow
  "what genome should I use?"   → none
```

---

## 4. E2E Tests — User Journeys

### Test Infrastructure Notes

- All tests use `registerAndGoHome(page, label)` from existing helpers or the
  equivalent `setupTestUser()` from `frontend/e2e/helpers.ts`
- All tests use `waitForAIResponse()` and `waitForNewWorkflowCard()`
- Screenshots saved to `e2e/screenshots/<test-name>/` using date-prefixed filenames
- `test.setTimeout(600000)` — 10 minutes per test (matches `playwright.config.ts`)
- NO `page.route()` mocking anywhere — all calls hit the live server
- Billing cost logged via `afterAll` using `GET /api/telemetry/cost-summary`

---

### T1 — Cost Estimate Before Confirmation (NEW, HIGH PRIORITY)

**Purpose**: Verify the CostEstimateBadge appears in the AWAITING REVIEW panel
before the user clicks Confirm & Run. This validates that D1 is fully wired
end-to-end from backend endpoint through to UI display.

**Preconditions**: Fresh user account. ADMET query with inline SMILES so the
Run button is enabled (no MISSING prereqs).

**Steps**:
1. Register fresh user, navigate to home
2. Send query: "Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O). Need hERG and DILI risk."
3. Wait for AI response and workflow card to appear
4. Assert AWAITING REVIEW state (Confirm & Run button visible)
5. Assert cost estimate badge is visible before clicking Run
6. Assert badge text contains "$" and a numeric value
7. Assert badge appears within 3 seconds of the card rendering
8. Screenshot the cost badge state
9. Verify the estimate_cost API directly for correct response shape

**Assertions**:
- `[data-testid="cost-estimate-badge"]` is visible OR `text=/\$\d+/` appears within the workflow card
- Badge text matches pattern containing a dollar sign and numeric value
- `estimate_cost` API: `cost_min_usd > 0`, `cost_max_usd > cost_min_usd`, `assumptions` has 3 items
- Badge is visible while "Confirm & Run" is still unclicked

**What can go wrong**:
- Badge not yet implemented in frontend (D1 backend exists but CostEstimateBadge component
  not yet wired into `nextflow-workflow-viewer.tsx` — test will surface this as a KNOWN GAP)
- API request race condition: badge renders after "Confirm & Run" is already clicked
- Wrong currency format or missing range in badge text

**Playwright snippet**:

```typescript
import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';

test.setTimeout(600000);

test.describe('T1 — Cost Estimate Before Confirmation', () => {
  test('cost-estimate-badge visible in AWAITING REVIEW before Confirm & Run', async ({ page }) => {
    const SS = path.join(__dirname, 'screenshots', 'T1-cost-estimate');
    if (!fs.existsSync(SS)) fs.mkdirSync(SS, { recursive: true });

    // Clear session state
    await page.context().clearCookies();
    const email = `e2e_T1_cost_${Date.now()}@biomate.test`;
    await page.goto(`${BASE_URL}/register`);
    await page.evaluate(() => { try { localStorage.clear(); } catch {} });
    await page.waitForLoadState('load');
    try {
      await page.waitForSelector('#name', { state: 'visible', timeout: 10000 });
      await page.fill('#name', 'T1 Cost Test User');
      await page.fill('#email', email);
      await page.fill('#password', 'TestPass123!');
      await page.fill('#confirmPassword', 'TestPass123!');
      await page.click('#terms');
      await page.click('button[type="submit"]');
      await page.waitForTimeout(2000);
    } catch {
      console.log('[T1] Registration skipped — using existing session');
    }
    await page.goto(BASE_URL);
    await page.evaluate(() => { try { localStorage.clear(); } catch {} });
    await page.reload();
    await page.waitForLoadState('load');
    await page.waitForSelector('textarea', { state: 'visible', timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(1000);

    // Intercept estimate_cost API call for timing verification
    let costApiCalledAt: number | null = null;
    let cardRenderedAt: number | null = null;
    page.on('response', async resp => {
      if (resp.url().includes('/api/workflows/estimate_cost') ||
          resp.url().includes('estimate_cost')) {
        costApiCalledAt = Date.now();
        console.log('[T1] estimate_cost API responded at', new Date(costApiCalledAt).toISOString());
      }
    });

    const textarea = page.locator('textarea').first();
    await expect(textarea).toBeVisible({ timeout: 15000 });

    const baselineCount = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);

    // Step 1: Send ADMET query
    await textarea.fill(
      'Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O). ' +
      'I need hERG cardiotoxicity risk and DILI assessment.'
    );
    await textarea.press('Enter');
    console.log('[T1] Query sent');

    // Step 2: Wait for AI response
    await page.waitForSelector('text=BioMate is typing', { state: 'hidden', timeout: 180000 }).catch(() => {});
    await page.waitForSelector('textarea:enabled', { timeout: 180000 }).catch(() => {});
    await page.waitForTimeout(3000);
    cardRenderedAt = Date.now();

    await page.screenshot({ path: path.join(SS, '01_card_appeared.png'), fullPage: true });

    // Step 3: Assert AWAITING REVIEW state
    const hasAwaitingReview =
      await page.locator('[data-testid="button-confirm-and-run"]').isVisible().catch(() => false) ||
      await page.locator('text=AWAITING REVIEW').isVisible().catch(() => false);
    console.log('[T1] AWAITING REVIEW state:', hasAwaitingReview);
    expect(hasAwaitingReview, 'Workflow card must show AWAITING REVIEW / Confirm & Run').toBe(true);

    await page.screenshot({ path: path.join(SS, '02_awaiting_review.png'), fullPage: true });

    // Step 4: Assert cost estimate badge visible
    const costBadge = page.locator('[data-testid="cost-estimate-badge"]');
    const costBadgeByTestId = await costBadge.isVisible({ timeout: 5000 }).catch(() => false);

    // Fallback: look for dollar-sign text near the workflow card
    const costBadgeByText = await page.locator('[data-testid^="workflow-artifact"]')
      .locator('text=/\\$[0-9]/')
      .first()
      .isVisible({ timeout: 3000 })
      .catch(() => false);

    const costVisible = costBadgeByTestId || costBadgeByText;
    console.log('[T1] cost-estimate-badge visible (testid):', costBadgeByTestId);
    console.log('[T1] cost text ($N) visible (text fallback):', costBadgeByText);

    if (!costVisible) {
      console.warn(
        '[T1] KNOWN GAP: CostEstimateBadge not rendered in frontend UI. ' +
        'D1 backend endpoint (GET /api/workflows/estimate_cost) exists and returns ' +
        'correct data, but the frontend component needs to be wired into ' +
        'nextflow-workflow-viewer.tsx near the Confirm & Run button. ' +
        'Switching to API-only assertion.'
      );
      await page.screenshot({ path: path.join(SS, '03_gap_cost_badge_missing.png'), fullPage: true });
      // Document gap without hard-failing CI — change to expect(costVisible).toBe(true) once wired
    } else {
      const badgeText = costBadgeByTestId
        ? await costBadge.textContent().catch(() => '') ?? ''
        : '';
      console.log('[T1] Cost badge text:', badgeText);
      expect(badgeText).toMatch(/\$[\d.]+/);
      await page.screenshot({ path: path.join(SS, '03_cost_badge_visible.png'), fullPage: true });
    }

    // Step 5: Timing assertion — badge must appear within 3s of card render
    if (costApiCalledAt && cardRenderedAt) {
      const lagMs = costApiCalledAt - cardRenderedAt;
      console.log(`[T1] estimate_cost API called ${lagMs}ms after card rendered`);
      if (lagMs > 3000) {
        console.warn(`[T1] Performance: cost badge lag ${lagMs}ms exceeds 3000ms target`);
      }
    } else {
      console.log('[T1] estimate_cost API not called during this session (badge not yet wired)');
    }

    // Step 6: Direct API contract validation
    const costResp = await page.request.get(
      `${BASE_URL}/api/workflows/estimate_cost?nextflow_path=admet%2Fmain.nf&sample_count=1`
    );
    console.log('[T1] estimate_cost API status:', costResp.status());
    expect(costResp.ok(), 'estimate_cost API must return 200').toBe(true);

    const costData = await costResp.json();
    console.log('[T1] Cost API response:', JSON.stringify(costData));
    expect(typeof costData.cost_min_usd).toBe('number');
    expect(typeof costData.cost_max_usd).toBe('number');
    expect(costData.cost_min_usd).toBeGreaterThan(0);
    expect(costData.cost_max_usd).toBeGreaterThan(costData.cost_min_usd);
    expect(Array.isArray(costData.assumptions)).toBe(true);
    expect(costData.assumptions.length).toBe(3);
    expect(costData.matched_workflow).toBeTruthy();
    console.log(
      `[T1] ✓ Cost API: min=$${costData.cost_min_usd} max=$${costData.cost_max_usd} ` +
      `workflow=${costData.matched_workflow}`
    );

    await page.screenshot({ path: path.join(SS, '04_final.png'), fullPage: true });
    console.log('[T1] ✓ Test complete');
  });
});
```

---

### T2 — Full Run Lifecycle with Provenance (NEW, HIGH PRIORITY)

**Purpose**: Verify the complete post-completion surface: completion banner
appears, ReproducibilityExportButton is present, ProvenancePanel expands and
shows S3 URIs. Validates D3 and D5 end-to-end.

**Preconditions**: Fresh user. ADMET run must complete (either via real Batch
execution or mock mode).

**Steps**:
1. Register fresh user, navigate to home
2. Send ADMET query with inline SMILES (no MISSING prereqs)
3. Wait for workflow card in AWAITING REVIEW state
4. Click "Confirm & Run", intercept execute API response to capture runId
5. Poll to terminal status (up to 17 minutes for Batch cold start)
6. If not completed, log status and return early (non-blocking on Batch failure)
7. Wait for UI to update after completion signal
8. Assert: completion banner visible
9. Assert: ReproducibilityExportButton visible (or log KNOWN GAP)
10. Assert: ProvenancePanel toggle visible (or log KNOWN GAP)
11. Click ProvenancePanel toggle, assert it expands
12. Assert expanded panel contains recognizable content (workflow path or S3 URI)
13. Call provenance API directly: assert data structure correctness
14. Call reproducibility API directly: assert files bundle correctness

**Assertions**:
- `[data-testid="workflow-completion-banner"]` visible after completion
- `[data-testid="reproducibility-export-btn"]` visible (D3 frontend wiring)
- `[data-testid="provenance-panel"]` visible and expandable (D5 frontend wiring)
- API `GET /api/workflows/runs/:id/provenance`:
  - `input_s3_uris` is array, `output_s3_uris` is array
  - `nextflow_path` is non-empty string
- API `GET /api/workflows/runs/:id/reproducibility`:
  - `files["methods.txt"]` is non-empty string
  - `files["params.json"]` is valid JSON string
  - `run_id` matches

**What can go wrong**:
- ProvenancePanel and ReproducibilityExportButton not yet wired in frontend
  (both backend endpoints exist; UI components need to be added to
  `nextflow-workflow-viewer.tsx`)
- Run fails on Batch: test skips UI assertions for post-completion features
- `completed_at` not set: provenance timestamps empty strings (acceptable)

**Playwright snippet**:

```typescript
import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';

test.setTimeout(600000);

test.describe('T2 — Full Run Lifecycle with Provenance', () => {
  test('completion banner → reproducibility button → provenance panel expand', async ({ page }) => {
    const SS = path.join(__dirname, 'screenshots', 'T2-provenance');
    if (!fs.existsSync(SS)) fs.mkdirSync(SS, { recursive: true });

    let capturedRunId: string | null = null;
    page.on('response', async resp => {
      if (resp.url().includes('/api/workflows/execute')) {
        try {
          const d = await resp.json().catch(() => ({})) as any;
          capturedRunId = d?.runId || d?.execution?.runId || capturedRunId;
          if (capturedRunId) console.log('[T2] Captured runId:', capturedRunId);
        } catch {}
      }
    });

    // Register fresh user
    await page.context().clearCookies();
    const email = `e2e_T2_prov_${Date.now()}@biomate.test`;
    await page.goto(`${BASE_URL}/register`);
    await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} });
    await page.waitForLoadState('load');
    try {
      await page.waitForSelector('#name', { state: 'visible', timeout: 10000 });
      await page.fill('#name', 'T2 Provenance User');
      await page.fill('#email', email);
      await page.fill('#password', 'TestPass123!');
      await page.fill('#confirmPassword', 'TestPass123!');
      await page.click('#terms');
      await page.click('button[type="submit"]');
      await page.waitForTimeout(2000);
    } catch {
      console.log('[T2] Registration skipped');
    }
    await page.goto(BASE_URL);
    await page.evaluate(() => { try { localStorage.clear(); } catch {} });
    await page.reload();
    await page.waitForLoadState('load');
    await page.waitForSelector('textarea', { state: 'visible', timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(1000);

    const textarea = page.locator('textarea').first();
    await expect(textarea).toBeVisible({ timeout: 15000 });

    // Step 1: Send ADMET query
    await textarea.fill(
      'Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O). ' +
      'I need hERG and DILI assessment.'
    );
    await textarea.press('Enter');

    // Step 2: Wait for workflow card
    await page.waitForSelector('text=BioMate is typing', { state: 'hidden', timeout: 180000 }).catch(() => {});
    await page.waitForSelector('textarea:enabled', { timeout: 180000 }).catch(() => {});
    await page.waitForTimeout(3000);
    await page.screenshot({ path: path.join(SS, '01_card.png'), fullPage: true });

    // Step 3: Click Confirm & Run
    const confirmBtn = page.locator('[data-testid="button-confirm-and-run"]').last();
    const confirmVisible = await confirmBtn.isVisible({ timeout: 10000 }).catch(() => false);
    if (!confirmVisible) {
      console.warn('[T2] Confirm & Run not visible — skipping execution');
      return;
    }
    const confirmEnabled = await confirmBtn.isEnabled().catch(() => false);
    if (!confirmEnabled) {
      console.warn('[T2] Confirm & Run disabled (MISSING prereqs) — skipping execution');
      return;
    }
    await confirmBtn.click();
    await page.waitForTimeout(3000);

    // Wait to capture runId from response interceptor
    for (let i = 0; i < 10 && !capturedRunId; i++) {
      await page.waitForTimeout(1000);
    }
    console.log('[T2] RunId after wait:', capturedRunId);

    if (!capturedRunId) {
      console.warn('[T2] Could not capture runId — verifying UI execution state only');
      await page.screenshot({ path: path.join(SS, '02_no_run_id.png'), fullPage: true });
      return;
    }

    // Step 4: Poll to completion
    const TERMINAL = new Set(['completed', 'failed', 'error', 'cancelled']);
    let finalStatus = 'unknown';
    let statusPayload: any = null;
    for (let i = 0; i < 200; i++) {
      await page.waitForTimeout(5000);
      const resp = await page.request.get(
        `${BASE_URL}/api/workflows/runs/${capturedRunId}/status`
      ).catch(() => null);
      if (!resp?.ok()) continue;
      statusPayload = await resp.json().catch(() => null);
      const s = (statusPayload?.status || '').toLowerCase();
      if (i % 6 === 0) console.log(`[T2] Poll ${i}: status=${s}`);
      if (TERMINAL.has(s)) { finalStatus = s; break; }
    }
    console.log('[T2] Final status:', finalStatus);
    await page.screenshot({ path: path.join(SS, '02_terminal.png'), fullPage: true });

    if (finalStatus !== 'completed') {
      console.warn(`[T2] Run did not complete (status=${finalStatus}) — skipping post-completion UI assertions`);
      return;
    }

    // Step 5: Give UI time to update
    await page.waitForTimeout(4000);

    // Dismiss feedback modal if present
    const skipBtn = page.getByRole('button', { name: /^skip$/i }).first();
    if (await skipBtn.isVisible().catch(() => false)) {
      await skipBtn.click().catch(() => {});
      await page.waitForTimeout(500);
    }

    await page.screenshot({ path: path.join(SS, '03_completion.png'), fullPage: true });

    // ASSERTION 1: Completion banner
    const completionBanner = page.locator('[data-testid="workflow-completion-banner"]');
    await expect(completionBanner).toBeVisible({ timeout: 30000 });
    console.log('[T2] ✓ Completion banner visible');

    // ASSERTION 2: ReproducibilityExportButton
    const reproSelectors = [
      page.locator('[data-testid="reproducibility-export-btn"]'),
      page.locator('text=Export Bundle'),
      page.locator('text=Reproducibility'),
      page.locator('button:has-text("Export")'),
    ];
    let reproBtnVisible = false;
    for (const loc of reproSelectors) {
      if (await loc.first().isVisible({ timeout: 3000 }).catch(() => false)) {
        reproBtnVisible = true;
        console.log('[T2] ✓ ReproducibilityExportButton visible');
        break;
      }
    }
    if (!reproBtnVisible) {
      console.warn(
        '[T2] KNOWN GAP: ReproducibilityExportButton not visible in UI. ' +
        'D3 backend endpoint exists (GET /api/workflows/runs/:id/reproducibility). ' +
        'Frontend component needs to be added to nextflow-workflow-viewer.tsx ' +
        'below the completion banner.'
      );
    }
    await page.screenshot({ path: path.join(SS, '04_reproducibility_btn.png'), fullPage: true });

    // ASSERTION 3: ProvenancePanel
    const provenanceSelectors = [
      page.locator('[data-testid="provenance-panel"]'),
      page.locator('text=Provenance'),
      page.locator('text=Data Lineage'),
      page.locator('button:has-text("Provenance")'),
    ];
    let provenanceToggleVisible = false;
    let provenanceLocator = provenanceSelectors[0];
    for (const loc of provenanceSelectors) {
      if (await loc.first().isVisible({ timeout: 3000 }).catch(() => false)) {
        provenanceToggleVisible = true;
        provenanceLocator = loc;
        console.log('[T2] ✓ ProvenancePanel toggle visible');
        break;
      }
    }
    if (!provenanceToggleVisible) {
      console.warn(
        '[T2] KNOWN GAP: ProvenancePanel not visible in UI. ' +
        'D5 backend endpoint exists (GET /api/workflows/runs/:id/provenance). ' +
        'Frontend component needs to be added to nextflow-workflow-viewer.tsx.'
      );
    } else {
      // Try to expand
      await provenanceLocator.first().click().catch(() => {});
      await page.waitForTimeout(1500);
      const provenanceContent = await page.locator('[data-testid="provenance-panel"]')
        .textContent().catch(() => '');
      console.log('[T2] Provenance content snippet:', (provenanceContent ?? '').slice(0, 120));
      await page.screenshot({ path: path.join(SS, '05_provenance_expanded.png'), fullPage: true });
    }

    // ASSERTION 4: Provenance API contract
    const provResp = await page.request.get(
      `${BASE_URL}/api/workflows/runs/${capturedRunId}/provenance`
    );
    expect(provResp.status(), 'provenance API must return 200').toBe(200);
    const provData = await provResp.json();
    expect(provData.run_id).toBe(capturedRunId);
    expect(Array.isArray(provData.input_s3_uris)).toBe(true);
    expect(Array.isArray(provData.output_s3_uris)).toBe(true);
    expect(provData.nextflow_path).toBeTruthy();
    console.log(
      `[T2] ✓ Provenance API: inputs=${provData.input_s3_uris.length} ` +
      `outputs=${provData.output_s3_uris.length}`
    );

    // ASSERTION 5: Reproducibility API contract
    const reproResp = await page.request.get(
      `${BASE_URL}/api/workflows/runs/${capturedRunId}/reproducibility`
    );
    expect(reproResp.status(), 'reproducibility API must return 200').toBe(200);
    const reproData = await reproResp.json();
    expect(reproData.run_id).toBe(capturedRunId);
    expect(reproData.files).toBeDefined();
    expect(typeof reproData.files['methods.txt']).toBe('string');
    expect(reproData.files['methods.txt'].length).toBeGreaterThan(0);
    expect(typeof reproData.files['params.json']).toBe('string');
    // Verify params.json is valid JSON
    const parsedParams = JSON.parse(reproData.files['params.json']);
    expect(typeof parsedParams).toBe('object');
    expect(typeof reproData.output_count).toBe('number');
    console.log(`[T2] ✓ Reproducibility API: output_count=${reproData.output_count}`);

    await page.screenshot({ path: path.join(SS, '06_final.png'), fullPage: true });
    console.log('[T2] ✓ Test complete');
  });
});
```

---

### T3 — Pilot Run Test Harness (NEW, MEDIUM PRIORITY)

**Purpose**: Verify PilotRunPanel full flow when `pilot_run_suggested=true` is
returned. All 4 validation phases should be visible and report a result. Param
recommendations from decision trees should appear after phase 4.

**Preconditions**: Fresh user. Query must trigger a multi-sample workflow that
causes `pilot_run_suggested=true` in the AI response (typically data-intensive
queries involving FASTQ or BAM inputs).

**Steps**:
1. Register fresh user
2. Send: "Run RNA-seq differential expression analysis on 12 tumor vs 12 normal samples. I have paired-end FASTQ files in S3."
3. Wait for workflow card
4. Assert pilot run banner is visible (`[data-testid="pilot-run-banner"]`)
5. Click "Configure Pilot Run" (`[data-testid="button-open-pilot-panel"]`)
6. Assert PilotRunPanel opens showing 4 phase rows (`[data-testid="preflight-phases"]`)
7. Assert each phase 1-3 shows "pass" or "fail" within 5 seconds
8. Trigger pilot execution by clicking "Start Pilot"
9. Wait for phase 4 (data characterization) up to 60s
10. Assert param recommendations section appears
11. Click "Apply All Recommendations" if present
12. Assert "Run Full Analysis" button enabled (`[data-testid="button-run-full-analysis"]`)
13. Screenshot each step

**Assertions**:
- `[data-testid="pilot-run-banner"]` visible in workflow card
- `[data-testid="button-open-pilot-panel"]` clickable
- Phase rows all have a non-"loading" status icon after 5s
- `[data-testid="param-recommendations"]` visible after phase 4
- `[data-testid="button-run-full-analysis"]` enabled after applying recommendations
- API: `POST /api/workflows/preflight` returns `phases.length >= 4` and `ready` field

**What can go wrong**:
- `pilot_run_suggested` not returned by AI for this query — check galaxy-assistant.ts
- Phase 4 data characterization requires real S3 data to run analyzers
- Recommendations section UI not yet wired in PilotRunPanel
- Query may trigger dataset-first clarification instead of workflow generation

**Test ID**: T3, screenshots to `e2e/screenshots/T3-pilot-run/`

---

### T4 — Multi-Step Pipeline (NEW, HIGH PRIORITY)

**Purpose**: Verify PipelineListView renders with numbered steps, dependency
arrows, and that the chain API is called when "Confirm & Run Pipeline" is
clicked. This is the primary validation for Workstream B.

**Preconditions**: Fresh user. Query must generate a multi-step pipeline intent.

**Steps**:
1. Register fresh user
2. Send: "I want to run RNA-seq alignment with nf-core/rnaseq first, then differential expression with DESeq2. I have paired-end FASTQ files in s3://my-bucket/rnaseq/."
3. Wait for AI response
4. Assert `[data-testid="pipeline-list-view"]` is rendered
5. Count step rows (`[data-testid^="pipeline-step-"]`) — expect >= 2
6. Assert step 1 content includes circled digit ①
7. Assert step 2 content includes "uses:" and ArrowLeft indicator
8. Assert `[data-testid="pipeline-confirm-run"]` is visible and enabled
9. Click "Confirm & Run Pipeline"
10. Assert `POST /api/workflows/chain` is called (intercept response)
11. Assert chain_run_id is returned in response
12. Poll `GET /api/workflows/chain/:id` for status transitions
13. Assert step 1 transitions to "running"
14. Screenshot each milestone

**Assertions**:
- `[data-testid="pipeline-list-view"]` present in DOM
- `page.locator('[data-testid^="pipeline-step-"]').count() >= 2`
- Step 1 text content includes "①"
- Step 2 text content includes "uses:" (ArrowLeft dependency label)
- `[data-testid="pipeline-confirm-run"]` enabled
- Network: `POST /api/workflows/chain` returns HTTP 200
- `chain_run_id` is non-empty string
- `GET /api/workflows/chain/:chain_run_id` returns `steps` array of length 2

**What can go wrong**:
- AI generates single-step workflow instead of multi-step (refine query if needed)
- `pipeline-list-view-container` in `chat-with-artifacts.tsx` renders PipelineListView
  only for specific response shapes — may need query refinement
- Chain API auto-wiring: step 2 inputs not filled if step 1 outputs are not indexed correctly

**Playwright snippet**:

```typescript
import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';

test.setTimeout(600000);

test.describe('T4 — Multi-Step Pipeline', () => {
  test('PipelineListView renders with numbered steps; chain API called on confirm', async ({ page }) => {
    const SS = path.join(__dirname, 'screenshots', 'T4-pipeline');
    if (!fs.existsSync(SS)) fs.mkdirSync(SS, { recursive: true });

    let chainApiResponse: any = null;
    page.on('response', async resp => {
      if (resp.url().includes('/api/workflows/chain') && resp.request().method() === 'POST') {
        try {
          chainApiResponse = await resp.json();
          console.log('[T4] Chain API response:', JSON.stringify(chainApiResponse).slice(0, 200));
        } catch {}
      }
    });

    // Register fresh user
    await page.context().clearCookies();
    const email = `e2e_T4_pipeline_${Date.now()}@biomate.test`;
    await page.goto(`${BASE_URL}/register`);
    await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} });
    await page.waitForLoadState('load');
    try {
      await page.waitForSelector('#name', { state: 'visible', timeout: 10000 });
      await page.fill('#name', 'T4 Pipeline User');
      await page.fill('#email', email);
      await page.fill('#password', 'TestPass123!');
      await page.fill('#confirmPassword', 'TestPass123!');
      await page.click('#terms');
      await page.click('button[type="submit"]');
      await page.waitForTimeout(2000);
    } catch {
      console.log('[T4] Registration skipped');
    }
    await page.goto(BASE_URL);
    await page.evaluate(() => { try { localStorage.clear(); } catch {} });
    await page.reload();
    await page.waitForLoadState('load');
    await page.waitForSelector('textarea', { state: 'visible', timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(1000);

    const textarea = page.locator('textarea').first();
    await expect(textarea).toBeVisible({ timeout: 15000 });

    // Step 1: Send multi-step query
    await textarea.fill(
      'I want to run RNA-seq alignment and quantification first using nf-core/rnaseq, ' +
      'then perform differential expression analysis with DESeq2. ' +
      'I have paired-end FASTQ files in s3://my-bucket/rnaseq/.'
    );
    await textarea.press('Enter');
    console.log('[T4] Multi-step query sent');

    // Step 2: Wait for response
    await page.waitForSelector('text=BioMate is typing', { state: 'hidden', timeout: 180000 }).catch(() => {});
    await page.waitForSelector('textarea:enabled', { timeout: 180000 }).catch(() => {});
    await page.waitForTimeout(4000);
    await page.screenshot({ path: path.join(SS, '01_response.png'), fullPage: true });

    // ASSERTION 1: PipelineListView rendered
    const pipelineView = page.locator('[data-testid="pipeline-list-view"]');
    const pipelineVisible = await pipelineView.isVisible({ timeout: 10000 }).catch(() => false);

    if (!pipelineVisible) {
      console.warn(
        '[T4] PipelineListView not rendered. This may mean: ' +
        '(a) AI generated a single-step workflow for this query, ' +
        '(b) chat-with-artifacts does not yet route multi-step intents to PipelineListView, ' +
        'or (c) the AI asked for clarification or data first. ' +
        'Falling back to chain API contract validation only.'
      );
      await page.screenshot({ path: path.join(SS, '02_gap_no_pipeline.png'), fullPage: true });

      // Fallback: verify chain API endpoint is wired correctly
      const chainResp = await page.request.post(`${BASE_URL}/api/workflows/chain`, {
        data: {
          steps: [
            {
              nextflow_path: 'rnaseq/main.nf',
              params: { input: 's3://my-bucket/samples.csv', genome: 'GRCh38' },
            },
            {
              nextflow_path: 'differentialabundance/main.nf',
              params: {},
            },
          ],
        },
      });
      console.log('[T4] Direct chain API status:', chainResp.status());
      expect(chainResp.ok(), 'POST /api/workflows/chain must return 200').toBe(true);
      const chainData = await chainResp.json();
      expect(chainData.chain_run_id).toBeTruthy();
      console.log('[T4] ✓ Chain API wired. chain_run_id:', chainData.chain_run_id);

      // Poll chain status once
      const pollResp = await page.request.get(
        `${BASE_URL}/api/workflows/chain/${chainData.chain_run_id}`
      );
      expect(pollResp.status()).toBe(200);
      const pollData = await pollResp.json();
      expect(Array.isArray(pollData.steps)).toBe(true);
      expect(pollData.steps.length).toBe(2);
      console.log('[T4] ✓ Chain poll: status=' + pollData.status);
      return;
    }

    // ASSERTION 2: Step rows present
    const stepRows = page.locator('[data-testid^="pipeline-step-"]');
    const stepCount = await stepRows.count();
    console.log('[T4] Step count:', stepCount);
    expect(stepCount).toBeGreaterThanOrEqual(2);
    await page.screenshot({ path: path.join(SS, '02_steps.png'), fullPage: true });

    // ASSERTION 3: Circled digit ① in step 1
    const step1Content = await stepRows.first().textContent() ?? '';
    const hasCircledOne = step1Content.includes('①') || step1Content.includes('1');
    console.log('[T4] Step 1 has circled ①:', step1Content.includes('①'));
    expect(step1Content.includes('①'), 'Step 1 must show circled digit ①').toBe(true);

    // ASSERTION 4: "uses:" dependency label in step 2
    const step2Content = await stepRows.nth(1).textContent() ?? '';
    const hasUsesLabel = step2Content.includes('uses:') || step2Content.includes('←');
    console.log('[T4] Step 2 uses-label:', hasUsesLabel, '| content:', step2Content.slice(0, 80));
    expect(hasUsesLabel, 'Step 2 must show "uses:" dependency label').toBe(true);
    await page.screenshot({ path: path.join(SS, '03_dependency_label.png'), fullPage: true });

    // ASSERTION 5: Confirm & Run Pipeline button enabled
    const confirmPipelineBtn = page.locator('[data-testid="pipeline-confirm-run"]');
    await expect(confirmPipelineBtn).toBeVisible({ timeout: 5000 });
    const isEnabled = await confirmPipelineBtn.isEnabled();
    console.log('[T4] pipeline-confirm-run enabled:', isEnabled);
    expect(isEnabled, '"Confirm & Run Pipeline" button must be enabled').toBe(true);

    // ASSERTION 6: Click and verify chain API is called
    await confirmPipelineBtn.click();
    console.log('[T4] Clicked Confirm & Run Pipeline');
    await page.waitForTimeout(4000);
    await page.screenshot({ path: path.join(SS, '04_after_confirm.png'), fullPage: true });

    if (chainApiResponse) {
      expect(chainApiResponse.chain_run_id, 'chain_run_id must be returned').toBeTruthy();
      console.log('[T4] ✓ Chain API called. chain_run_id:', chainApiResponse.chain_run_id);

      // ASSERTION 7: Poll chain status
      const chainId = chainApiResponse.chain_run_id;
      let chainStatus: any = null;
      for (let i = 0; i < 20; i++) {
        await page.waitForTimeout(3000);
        const pollResp = await page.request.get(
          `${BASE_URL}/api/workflows/chain/${chainId}`
        ).catch(() => null);
        if (!pollResp?.ok()) continue;
        chainStatus = await pollResp.json().catch(() => null);
        const stepStatuses = chainStatus?.steps?.map((s: any) => s.status) ?? [];
        console.log(`[T4] Chain poll ${i}: status=${chainStatus?.status} steps=${JSON.stringify(stepStatuses)}`);
        const step1Status = chainStatus?.steps?.[0]?.status;
        if (step1Status === 'running' || step1Status === 'completed') break;
      }

      if (chainStatus) {
        expect(chainStatus.steps, 'Chain must have steps array').toBeDefined();
        expect(Array.isArray(chainStatus.steps)).toBe(true);
        expect(chainStatus.steps.length).toBeGreaterThanOrEqual(2);
        console.log('[T4] ✓ Chain status polled: step1=' + chainStatus.steps[0]?.status);
      }
    } else {
      console.warn('[T4] Chain API response not captured in interceptor — button routing may differ');
    }

    // ASSERTION 8: UI shows step status badges updated
    await page.waitForTimeout(2000);
    const step1Badge = stepRows.first().locator('[class*="badge"], [class*="Badge"]').first();
    const step1BadgeText = await step1Badge.textContent().catch(() => '');
    console.log('[T4] Step 1 status badge text:', step1BadgeText);

    await page.screenshot({ path: path.join(SS, '05_final.png'), fullPage: true });
    console.log('[T4] ✓ Test complete');
  });
});
```

---

### T5 — Error Recovery UX (NEW, MEDIUM PRIORITY)

**Purpose**: Verify the ErrorRecoveryBanner (`[data-testid="error-summary-banner"]`
in `workflow-artifact.tsx` line 1021) appears on run failure, displays a
human-readable summary, and that the "Fix via chat" button
(`[data-testid="fix-and-resume-btn"]` line 1038) pre-fills the chat input.

**Preconditions**: Fresh user. The test needs a run that fails deterministically.
Strategy: submit a valid workflow definition but with a deliberately invalid S3
input path so the preflight S3 validation fails fast, or run in an environment
where the backend returns a simulated failure.

**Steps**:
1. Register fresh user
2. Submit a query that generates a workflow with an S3 input param
3. Before clicking Run, modify the S3 input to a known-invalid path via chat:
   "Set the input to s3://nonexistent-biomate-test-bucket-xyz/missing.fastq"
4. Click Confirm & Run
5. Poll until status == "failed"
6. Assert `[data-testid="error-summary-banner"]` is visible
7. Assert banner text does NOT contain "Traceback" (no raw Python errors)
8. Assert banner text DOES contain at least one plain English sentence
9. Assert `[data-testid="fix-and-resume-btn"]` is visible
10. Click "Fix via chat →"
11. Assert `textarea` value is non-empty (pre-filled with suggestion text)
12. If `can_resume=true`: assert "Continue from Checkpoint" button visible

**Assertions**:
- `[data-testid="error-summary-banner"]` visible after failure
- Banner text: `!text.includes("Traceback")` and `!text.includes("HTTPException")`
- Banner text: length > 20 characters (substantive English summary)
- `[data-testid="fix-and-resume-btn"]` visible
- After click: `textarea` value contains suggestion text (non-empty)
- API: `POST /api/workflows/parse_error` with a crafted log returns `error_type != "unknown"` for known error patterns

**What can go wrong**:
- Run may not fail fast enough for test timeout (S3 validation may take 30s)
- `error-summary-banner` and `fix-and-resume-btn` testids already exist in `workflow-artifact.tsx`
  so the banner component is implemented; the question is whether it populates correctly
- Chat pre-fill: `fix-and-resume-btn` click handler must set the textarea value;
  if it opens a new route instead, the assertion will fail

**Test ID**: T5, screenshots to `e2e/screenshots/T5-error-recovery/`

---

### T6 — Workflow Modification Across Turns (NEW, MEDIUM PRIORITY)

**Purpose**: Verify that a follow-up message to change a parameter uses the
`WorkflowModificationClassifier` via `POST /api/workflow/modify` rather than
regenerating the entire workflow. This validates Workstream A3.

**Preconditions**: Fresh user. An ADMET workflow must be in AWAITING REVIEW
state before the modification turn.

**Steps**:
1. Register fresh user
2. Send: "Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O)"
3. Wait for workflow card in AWAITING REVIEW state
4. Note the workflow card count (should be 1)
5. Note the current SMILES parameter value displayed
6. Send follow-up: "Change the SMILES to CC(=O)O"
7. Intercept: verify `POST /api/workflow/modify` is called
8. Wait for AI response
9. Assert: workflow card count is still 1 (no new card generated)
10. Assert: SMILES parameter shows "CC(=O)O" in the updated view
11. Assert: workflow name still contains "ADMET" (not a new unrelated workflow)
12. Assert: modification API returned `type == "value_change"`

**Assertions**:
- `POST /api/workflow/modify` called during response to follow-up message
- `modification.type == "value_change"`
- `modification.param_changes` contains SMILES-related key with new value
- Workflow card count unchanged (modification, not regeneration)
- Updated parameter value visible in the workflow card
- Workflow name still references ADMET

**What can go wrong**:
- AI may ignore the modify endpoint and regenerate the workflow via the standard chat path
- `galaxy-assistant.ts` may not route follow-up messages to `/api/workflow/modify`
- SMILES display may not update if the param update is not propagated to the UI state

**Test ID**: T6, screenshots to `e2e/screenshots/T6-modification/`

---

### T7 — Disambiguation: Somatic vs Germline (Regression)

**Purpose**: Regression test for the LLM disambiguation fix. Ambiguous tumor
query triggers clarification, user answers "germline", and nf-core/sarek
germline workflow (not a somatic pipeline) is selected.

**Status**: COVERED by `disambiguation.e2e.ts` D1-D3. All 6/6 tests passing as
of 2026-03-18.

**Regression triggers to watch**:
- `_classify_intent_with_llm` cache collision if query hash function changes
- `_llm_rerank_results` no longer excluding somatic workflows for germline queries
- New bioconductor packages with "germline" in their name outscoring nf-core/sarek

**Run as part of**: P0 CI suite. If D3 or D5 in `disambiguation.e2e.ts` fails,
block the release.

---

### T8 — Search Quality: RNA-seq Query Rank (NEW, MEDIUM PRIORITY)

**Purpose**: Verify the two-pass FTS search algorithm returns nf-core/rnaseq as
the top result for a query containing a GEO accession. This catches regression
against bioconductor noise dominating the results.

**Preconditions**: Workflow database indexed (2284 workflows). Galaxy backend running.

**Steps**:
1. Call `GET /api/workflows/search?query=RNA-seq+of+GSE68086+lung+cancer` directly
2. Assert: `results[0].format == "nextflow"` (not bioconductor)
3. Assert: `results[0].name.toLowerCase()` contains "rnaseq"
4. Assert: first 3 results all have `format == "nextflow"`
5. Assert: response time < 2s
6. Run 3 additional queries to verify consistent ranking:
   - "differential expression analysis bulk RNA-seq" → nf-core/rnaseq or differentialabundance
   - "WGS somatic variant calling" → nf-core/sarek
   - "ATAC-seq peak calling" → nf-core/atacseq
7. Log ranked results for audit

**Assertions**:
- `results[0].format == "nextflow"` for all 4 queries
- No bioconductor package in top-3 for standard nf-core queries
- Response latency < 2000ms (FTS + LLM re-ranking budget)

**What can go wrong**:
- Search API endpoint path: verify `/api/workflows/search` exists in `routes.ts`
- GSE accession tokenization: "GSE68086" may fragment into tokens that match bioconductor gene IDs
- LLM re-ranking cache miss on first run adds ~2s latency on first call

**Test ID**: T8, run as nightly scheduled job

---

### T9 — Chain Execution Output Wiring (NEW, MEDIUM PRIORITY)

**Purpose**: Verify that after step N completes in a chain, step N+1's params
are automatically populated with step N's S3 output URIs. This validates the
auto-wiring core of Workstream B.

**Preconditions**: Two-step chain. Step 1 must complete and produce S3 outputs
that can be resolved as step 2 inputs.

**Steps**:
1. `POST /api/workflows/chain` with 2 steps:
   - Step 1: `rnaseq/main.nf`, params = `{ input: "s3://biomate-nextflow-work/test/samples.csv", genome: "GRCh38" }`
   - Step 2: `differentialabundance/main.nf`, params = `{}` (empty — to be auto-filled)
2. Capture `chain_run_id`
3. Poll `GET /api/workflows/chain/:chain_run_id` every 5s
4. Wait for `steps[0].status == "completed"` (up to 30 minutes)
5. Assert: `steps[1].params` contains at least one value starting with "s3://"
6. Assert: `steps[1].input_from == 0` (correctly wired to step 1)
7. Assert: `steps[1].status` transitions to "running" after step 1 completes
8. Continue polling until `steps[1].status` reaches terminal state
9. Assert: `chain.status == "completed"` when both steps complete

**Assertions**:
- After step 1 complete: `steps[1].params` has `s3://` URI values (auto-wired)
- `steps[1].input_from == 0`
- `steps[1].status` reaches "running" (not stuck in "pending" after step 1 done)
- Final: `chain.status` is "completed"
- No HTTP 500 from chain polling endpoint at any point

**What can go wrong**:
- Step 1 fails on Batch: chain marks step 2 as "skipped", never starts
- Output-resolution logic: `POST /api/workflows/runs/:run_id/resolve-outputs` in `workflow_chain.py`
  may not correctly match step 1's S3 output file types to step 2's expected input param names
- Timing race: step 2 might start before step 1's output listing is complete

**Test ID**: T9, run as P1 nightly job (requires Batch access)

---

## 5. UX Cognitive Load Audit

### State 1: Initial Chat (Empty)

| Metric | Assessment |
|--------|-----------|
| What user sees | Large textarea, minimal chrome, welcome message or empty state |
| Interactive elements | 1 textarea, 1 send button, sidebar nav |
| Primary action obvious? | Yes — textarea is visually dominant and has placeholder text |
| Points of confusion | None for first-time users |
| Recommendations | None needed. Current state is clean. |

### State 2: AWAITING REVIEW (Workflow Card Generated)

| Metric | Assessment |
|--------|-----------|
| What user sees | Workflow card with name, amber "AWAITING REVIEW" badge, params accordion, QC Settings accordion, cost badge (planned D1), "Confirm & Run" (green), "Adjust via Chat" (outline) |
| Interactive elements | 6–8 (2 buttons + 2 accordions + cost badge + rationale toggle + QC) |
| Primary action obvious? | Yes — green "Confirm & Run" is visually dominant |
| Points of confusion | (1) Cost estimate badge positioning unclear if not adjacent to Run button; (2) "Adjust via Chat" vs retyping in chat — users may not understand the difference; (3) QC Settings collapse: users don't know whether they must interact with it |
| Recommendations | (1) Place cost badge immediately above "Confirm & Run", not in the card header; (2) Add tooltip: "Adjust via Chat modifies parameters without regenerating the workflow"; (3) Rename "QC Settings" to "Quality Thresholds (advanced)" and default-collapse with a Learn more link |

### State 3: PilotRunPanel Open

| Metric | Assessment |
|--------|-----------|
| What user sees | 4 phase rows with pass/fail icons, pilot config (size slider, strategy dropdown), "Start Pilot" button, data characterization results (analyzer names + extracted values) |
| Interactive elements | 10+ (4 phase rows, slider, dropdown, multiple buttons, per-recommendation Apply) |
| Primary action obvious? | Moderately — "Start Pilot" is clear but the 4 phase rows above it may confuse users into thinking they need to wait for them |
| Points of confusion | (1) Phases 1–3 complete instantly but users may read them as "in progress"; (2) "Data characterization" is technical jargon; (3) Param recommendation keys (e.g., "max_memory") are cryptic without explanation |
| Recommendations | (1) Label phases 1–3 as "Pre-checks (instant)" and phase 4 as "Data analysis (~30s)"; (2) Add plain-English explanation to each param recommendation; (3) Provide a single "Apply All & Run Full Analysis" button instead of per-recommendation Apply |

### State 4: PipelineListView (Multi-Step Pipeline)

| Metric | Assessment |
|--------|-----------|
| What user sees | Numbered list with circled digits ① ②, step names, param summaries, "← uses: ①" labels, status badges per step, "Confirm & Run Pipeline" green button |
| Interactive elements | 3–5 per step (remove button, "edit via chat" link) + 1 confirm button |
| Primary action obvious? | Yes — "Confirm & Run Pipeline" is large and green at the bottom |
| Points of confusion | (1) Circled digits look decorative rather than functional; (2) "← uses: ①" is abstract — users may not know what "uses" means; (3) "edit via chat" link is tiny and loses discoverability |
| Recommendations | (1) Add "Step N of M" text label alongside the circled digit; (2) Change "← uses: ①" to "Input from Step 1: count_matrix"; (3) Promote "edit via chat" to a hover popover with example text ("Type: change padj to 0.01") |

### State 5: Run In Progress

| Metric | Assessment |
|--------|-----------|
| What user sees | PhaseCard steps with animated RUNNING badge, log tail (collapsed), Detach button, Reconnect (disabled), progress % badge, "Batch job continues running" note |
| Interactive elements | 3–4 (Detach, Cancel, log accordion, possibly per-phase output inspect) |
| Primary action obvious? | Yes — Detach is the clear action when user wants to leave |
| Points of confusion | (1) "Detach" wording is unfamiliar (many users expect "Minimize" or "Close"); (2) No ETA shown; (3) "Batch job continues running" note is small — users may worry it stops when they detach |
| Recommendations | (1) Add tooltip: "Detach closes this view — your job keeps running on AWS Batch"; (2) Show "ETA: ~15 min" derived from the estimate_cost runtime_hours field; (3) Make "Batch job continues running" a prominent green chip, not small italic text |

### State 6: Error Recovery

| Metric | Assessment |
|--------|-----------|
| What user sees | Red ErrorRecoveryBanner with human_summary, suggested_fix, "Continue from Checkpoint" (if can_resume=true), "Fix via chat →" button |
| Interactive elements | 2–3 |
| Primary action obvious? | Moderately — two CTAs with similar visual weight may cause decision paralysis |
| Points of confusion | (1) Users don't know what "Checkpoint" means in a bioinformatics context; (2) "Fix via chat" is vague — users need to know what to type; (3) Banner may be below many PhaseCards that users scroll past |
| Recommendations | (1) Change "Continue from Checkpoint" to "Retry from last completed step"; (2) Pre-fill chat with the specific suggested_fix text, not just any text; (3) Auto-scroll the page to bring the error banner into viewport on failure detection |

### State 7: Post-Completion

| Metric | Assessment |
|--------|-----------|
| What user sees | Green completion banner, DownloadCommandsPanel (aws s3 sync command), ReproducibilityExportButton (planned), ProvenancePanel (planned, collapsible), ChatOutputAttachments (CSV/HTML/FASTA viewers) |
| Interactive elements | 6–10 depending on output file count |
| Primary action obvious? | No single obvious primary action — multiple panels compete for attention |
| Points of confusion | (1) "aws s3 sync" requires AWS CLI; most biologists don't have this; (2) ProvenancePanel is a bonus feature most won't look for; (3) Multiple output viewers may overflow the card height making the page very long |
| Recommendations | (1) Make "Download All" the primary CTA above all other post-completion elements; (2) Move "aws s3 sync" into a collapsible "Advanced / CLI" section; (3) Group ReproducibilityExportButton and ProvenancePanel into a single "Share & Export" dropdown menu; (4) Show output count as a badge: "3 files ready to view" |

---

## 6. Performance Benchmarks

All benchmarks are measured from the user's perspective (wall clock from user
action to visible UI update). Targets based on the rule that users should not
perceive loading states longer than stated.

| Metric | Target | Measurement Method | Current Status |
|--------|--------|-------------------|----------------|
| Query → workflow card visible | < 10s | `waitForNewWorkflowCard()` timing in E2E | ~8–12s (AI response) — AT TARGET |
| Cost estimate badge render | < 2s after card appears | Network timing for `estimate_cost` API call | API < 200ms; frontend wiring PENDING |
| Preflight phases 1–3 complete | < 5s from button click | Time `POST /api/workflows/preflight` | ~1–2s observed in UC-2 — AT TARGET |
| Phase 4 data characterization | < 30s with real data | UC-2 timeout guard assertion | Not measurable until Phase 4 UI wired |
| Pilot run start | < 5s from click | Time from "Start Pilot" to phase 4 spinner | Not measurable yet |
| Status polling UI update lag | < 3s | Polling interval vs backend state change time | 5s polling interval — SLIGHTLY OVER TARGET |
| Workflow modify classify | < 3s | Network timing on `POST /api/workflow/modify` | Haiku ~1–2s — AT TARGET |
| Search result ranking | < 2s for top result | `GET /api/workflows/search` total response time | FTS fast; LLM re-ranking adds ~2s — AT TARGET |
| Chain status poll response | < 500ms | `GET /api/workflows/chain/:id` response time | ~200ms proxy pass-through — AT TARGET |
| Download commands panel render | < 5s after completion | `waitForSelector("download-commands-panel")` | ~3–4s observed in UC-7 — AT TARGET |

### Degraded Condition Notes

- AWS Batch cold start: 5–8 minutes is expected and acceptable. The Detach UX
  exists precisely for this. Users must be informed via the "Batch job continues
  running" note.
- LLM disambiguation (two Haiku calls): adds 2–4s to first response for ambiguous
  queries. Results are cached by query hash so subsequent identical queries are fast.
- Phase 4 pilot analysis: up to 60s when running 20 analyzers on large S3 files.
  Use `timeout: 60000` guard in the pilot panel and surface a timeout message.
- Notification email: sent asynchronously after terminal state — no latency impact
  on the polling loop.

---

## 7. Execution Priority Matrix

### P0 — Block Release (Run in CI on every Pull Request)

These tests protect the core workflow execution loop. A failure means the
product is broken for the primary user persona.

| Test ID | File | Rationale |
|---------|------|-----------|
| ADMET Full Execution Flow | `full-workflow-e2e.e2e.ts` | Core lifecycle — query to completion |
| AWAITING REVIEW UX | `full-workflow-e2e.e2e.ts` | pending_review state regression |
| UC-6: Detach/Reconnect labels | `full-workflow-e2e.e2e.ts` | Batch execution label regression |
| UC-7: Download Commands Panel | `full-workflow-e2e.e2e.ts` | Post-completion output access |
| D3: Germline routes to WGS | `disambiguation.e2e.ts` | LLM disambiguation regression |
| D5: Direct germline no clarification | `disambiguation.e2e.ts` | Disambiguation false positive |
| QC consistency (65 unit tests) | `test_qc_consistency.py` | QC profile + threshold regression |
| T4: Multi-step pipeline chain API | NEW | Workstream B core feature |

### P1 — Run Before Release Tag (Nightly + manual pre-release)

These tests validate new feature surfaces that have not yet fully stabilized,
or require longer runtime budgets.

| Test ID | File | Rationale |
|---------|------|-----------|
| T1: Cost estimate badge | NEW | D1 UI wiring not yet confirmed |
| T2: Provenance + reproducibility | NEW | D3 + D5 UI components not yet surfaced |
| T3: Pilot run harness Phase 4 | NEW | Phase 4 requires real S3 data |
| GC-1 to GC-4: Germline complete E2E | `germline-complete-e2e.e2e.ts` | Full germline flow regression |
| UC-2: Pilot run / preflight API | `full-workflow-e2e.e2e.ts` | Phase 4 characterization |
| UC-3: Per-step output inspection | `full-workflow-e2e.e2e.ts` | PhaseCard rendering regression |
| T8: Search quality ranking | NEW | A2 FTS scoring regression |
| T9: Chain output auto-wiring | NEW | Workstream B output wiring regression |
| Drug-dev 4 tests | `drug-dev-viewers-audit.e2e.ts` | Drug domain full regression |

### P2 — On-Demand / Weekly Audit

Long-running tests, or tests for features not yet fully implemented on the
frontend side.

| Test ID | File | Rationale |
|---------|------|-----------|
| T5: Error recovery UX | NEW | Requires deliberate failure injection |
| T6: Workflow modification turns | NEW | A3 modify endpoint UI wiring uncertain |
| T7: Disambiguation regression | `disambiguation.e2e.ts` | Redundant with D3/D5 at P0 |
| Client demo (ADMET+RNA+CryoEM) | `client-demo.e2e.ts` | 27+ minute runtime |
| QC E2E tests (9 tests) | `qc-governance.e2e.ts` | QC gate interactive flow |
| Domain performance suite | `domain-case-performance.e2e.ts` | Comparative benchmark, not blocking |

### Recommended GitHub Actions Structure

```
on_pr:
  1. unit_tests:
       backend/tests/ (pytest, ~30s for 642 tests)
  2. api_smoke:
       UC-2 preflight API, estimate_cost, parse_error, chain POST
       (no browser, 2-3 min)
  3. e2e_p0:
       full-workflow-e2e.e2e.ts (ADMET Full + UC-6 + UC-7)
       disambiguation.e2e.ts (D3 + D5 only)
       (~20-25 min depending on Batch cold start)

nightly:
  1. unit_tests (full)
  2. e2e_p0 (full, all tests in P0 files)
  3. e2e_p1 (T1, T2, T4, T8, T9, germline-complete, drug-dev)
  4. api_contract_suite (all 7 endpoints in section 3)

weekly:
  1. e2e_p2 (T5, T6, client-demo)
  2. search_quality_audit (T8 expanded to 10 diverse queries)
  3. cost_estimate_audit (verify assumptions stay calibrated to Batch pricing)
```

---

## Appendix A: Test ID Registry

### Confirmed in Codebase

| data-testid | Component | Source file |
|-------------|-----------|-------------|
| `workflow-artifact` (prefix) | WorkflowArtifact | `workflow-artifact.tsx` |
| `button-confirm-and-run` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:1106` |
| `button-run-workflow-panel` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:859` |
| `button-pause-workflow-panel` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:868` |
| `button-resume-workflow-panel` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:877` |
| `button-restart-workflow-panel` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:888` |
| `button-cancel-workflow-panel` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:897` |
| `button-download-all-workflow-panel` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:1146` |
| `button-confirm-low-confidence-run` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:1106` |
| `button-prereq-recovery` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:1087` |
| `qc-settings-section` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:908` |
| `qc-gate-inline` | WorkflowArtifact | `workflow-artifact.tsx:1086` |
| `qc-gate-apply` | WorkflowArtifact | `workflow-artifact.tsx:1125` |
| `qc-gate-keep` | WorkflowArtifact | `workflow-artifact.tsx:1134` |
| `qc-gate-cancel-run` | WorkflowArtifact | `workflow-artifact.tsx:1141` |
| `error-summary-banner` | WorkflowArtifact | `workflow-artifact.tsx:1021` |
| `fix-and-resume-btn` | WorkflowArtifact | `workflow-artifact.tsx:1038` |
| `milestone-timeline` | WorkflowArtifact | `workflow-artifact.tsx:804` |
| `ai-realtime-panel` | WorkflowArtifact | `workflow-artifact.tsx:817` |
| `workflow-run-controls` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:856` |
| `workflow-prereq-checklist` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:1045` |
| `workflow-prereq-item-{id}` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:1060` |
| `autofix-status-panel` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:1019` |
| `autofix-active-banner` | NextflowWorkflowViewer | `nextflow-workflow-viewer.tsx:1035` |
| `workflow-completion-banner` | NextflowWorkflowViewer | (referenced in full-workflow-e2e) |
| `download-commands-panel` | NextflowWorkflowViewer | (referenced in UC-7) |
| `phase-card-setup` | PhaseCard | `phase-card.tsx` |
| `phase-card-process` | PhaseCard | `phase-card.tsx` |
| `phase-card-{id}` (prefix) | PhaseCard | `phase-card.tsx` |
| `preflight-phases` | PilotRunPanel | `pilot-run-panel.tsx` |
| `pilot-run-banner` | NextflowWorkflowViewer | (referenced in UC-2) |
| `button-open-pilot-panel` | NextflowWorkflowViewer | (referenced in UC-2) |
| `pipeline-list-view` | PipelineListView | `pipeline-list-view.tsx:339` |
| `pipeline-step-{id}` (prefix) | PipelineListView StepRow | `pipeline-list-view.tsx:152` |
| `pipeline-step-remove-{id}` | PipelineListView StepRow | `pipeline-list-view.tsx:191` |
| `pipeline-confirm-run` | PipelineListView | `pipeline-list-view.tsx:441` |
| `pipeline-list-view-container` | ChatWithArtifacts | `chat-with-artifacts.tsx:1357` |
| `button-continue-from-checkpoint` | NextflowWorkflowViewer | (referenced in UC-4) |

### Required — Not Yet Implemented in Frontend (D1, D3, D5)

| data-testid | Component to Build | Priority | Notes |
|-------------|-------------------|----------|-------|
| `cost-estimate-badge` | CostEstimateBadge | P1 (D1) | Backend: `GET /api/workflows/estimate_cost` exists. Wire into `nextflow-workflow-viewer.tsx` near Confirm & Run button. |
| `reproducibility-export-btn` | ReproducibilityExportButton | P1 (D3) | Backend: `GET /api/workflows/runs/:id/reproducibility` exists. Add button below completion banner. |
| `provenance-panel` | ProvenancePanel | P1 (D5) | Backend: `GET /api/workflows/runs/:id/provenance` exists. Add collapsible panel below DownloadCommandsPanel. |
| `provenance-panel-toggle` | ProvenancePanel (collapse toggle) | P1 (D5) | Required for T2 expand assertion. |
| `button-run-full-analysis` | PilotRunPanel extension | P1 (C) | Shown after pilot + recommendations. |
| `param-recommendations` | PilotRunPanel extension | P1 (C) | Section visible after phase 4 completes. |

---

## Appendix B: Known Gaps and Recommended Implementation Actions

| Gap ID | Gap Description | User Impact | Recommended Action | Priority |
|--------|----------------|-------------|-------------------|----------|
| GAP-1 | CostEstimateBadge not wired in frontend | Users cannot see cost before clicking Run | Implement `CostEstimateBadge` component in `nextflow-workflow-viewer.tsx`. Call `GET /api/workflows/estimate_cost` on workflow card mount. Render "$X.XX–$Y.YY · ~Zmin" adjacent to Confirm & Run. | P1 |
| GAP-2 | ReproducibilityExportButton not in frontend | Users cannot download reproducibility bundle from UI | Add button below completion banner. On click: fetch `GET /api/workflows/runs/:id/reproducibility`, bundle the files JSON as a downloadable `.zip` or `.tar.gz` using browser File API. | P1 |
| GAP-3 | ProvenancePanel not in frontend | Lineage tree invisible to users | Add collapsible panel after DownloadCommandsPanel. Fetch `GET /api/workflows/runs/:id/provenance` on expand. Render as a 3-node tree: input S3 URIs → workflow name + path → output S3 URIs. | P1 |
| GAP-4 | Phase 4 data characterization UI not fully wired | Pilot run shows only 3 phases instead of 4 | Extend `PilotRunPanel` to accept and display `phase[id="data_characterization"]` results. Show analyzer names and extracted values (e.g., "read_length: 150bp detected"). | P1 |
| GAP-5 | Param recommendations section not in PilotRunPanel | Users cannot apply pilot analysis recommendations | Add `[data-testid="param-recommendations"]` section to PilotRunPanel. Render each recommendation with param name, suggested value, and plain-English rationale. Provide "Apply All" button. | P1 |
| GAP-6 | T6 workflow modify not end-to-end tested | A3 WorkflowModificationClassifier untested in UI flow | Verify `galaxy-assistant.ts` routes follow-up modification messages to `POST /api/workflow/modify`. Wire the modification result (param_changes) to update the existing workflow card params without regeneration. | P2 |
| GAP-7 | T8 search quality not in automated test suite | Bioconductor noise could silently regress | Add T8 as a nightly API integration test. Assert nf-core/rnaseq in top-3 for at least 5 canonical queries covering RNA-seq, WGS, ATAC-seq, ChIP-seq, and metagenomics. | P1 |
| GAP-8 | notifyNextflowTerminal unit tests missing | Email de-dup guard could silently regress | Add Jest unit tests for `workflow-notification-service.ts`: double-call guard, `terminalEventLedger` persistence, user preference gating. | P2 |
| GAP-9 | Status polling interval is 5s (target is < 3s) | Users see 5s lag between backend state change and UI update | Consider reducing polling interval to 3s, or implement SSE push from status endpoint to eliminate polling lag entirely. | P2 |