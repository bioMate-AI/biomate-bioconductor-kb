# BioMate UI Leaking, Routing Bugs & Workflow Panel Fixes
**Date:** 2026-07-02  
**Branch:** integration/next-phase

---

## Overview

This session addressed three categories of bugs found during manual testing:

1. **Internal detail leaking** — S3 paths, Nextflow branding, Invocation IDs, confidence scores, stack traces shown to users
2. **Workflow panel UX failures** — duplicate buttons, download buttons on failed runs, misleading empty-state messages, useless "Fix & Retry" button
3. **Intent routing bug** — "tell me what this paper is about" + PDF incorrectly routed to `workflow_generation` instead of `research_question`

---

## Category 1: Internal Detail Leaking

### 1.1 S3 paths in user messages

**File:** `frontend/client/src/components/chat-message.tsx`

**Problem:** User messages displayed raw `[BioMate dataset: name (id: s3://biomate-nextflow-work/...)]` annotations in the chat bubble. The strip regex didn't include the `BioMate dataset` label variant.

**Fix:** Extended the strip regex to cover all variants:
```javascript
.replace(/\n?\[(?:BioMate dataset|Galaxy dataset|Dataset|Attached files|Uploaded datasets?)[^\]]*\]/gi, '')
```

### 1.2 S3 paths in error messages

**File:** `frontend/client/src/components/nextflow-workflow-viewer.tsx`

**Problem:** Raw error text from the backend included S3 paths (`s3://biomate-nextflow-work/...`), Nextflow groovy stack traces (`Launcher.groovy:123`), and the word "Nextflow" throughout.

**Fix:** Added `sanitizeErrorText()` helper applied to all user-facing error text:
```typescript
function sanitizeErrorText(msg: string): string {
  const withoutStack = msg
    .split('\n')
    .filter(l => !/^\s*at\s+[\w.$]+\(/.test(l))
    .join('\n').trim();
  return withoutStack
    .replace(/\bnextflow\b/gi, 'the pipeline')
    .replace(/s3:\/\/[^\s'"]+/gi, 'the storage bucket')
    .replace(/biomate-nextflow-work/gi, 'storage')
    .replace(/Launcher\.groovy:\d+/gi, '')
    .trim();
}
```
Applied to: `errorExplanation.human_summary`, `errorExplanation.suggested_fix`, raw `errorMessage`.

### 1.3 "Nextflow" branding in reports and API

**File:** `frontend/server/routes.ts`

**Problems found and fixed:**
- `"Nextflow workflow queued (run_id: ...)"` → `"Workflow queued (run_id: ...)"`
- `error_code: 'nextflow_execution_failed'` → `'workflow_execution_failed'`
- Report header line `ORCHESTRATION: Nextflow DSL2 + AWS Batch` → `ORCHESTRATION: BioMate pipeline on AWS Batch`
- Removed `INVOCATION ID` and `NEXTFLOW RUN ID` lines from both fallback and LLM-generated report headers
- Removed `s3_output_path` from CryoEM LLM metrics block and prompt
- Removed `outdir` and `download_commands` from `/api/workflows/runs/:id/output_files` response
- Rewrote `/api/workflows/runs/:id/download_commands` endpoint: removed all S3 paths; now returns `{ workflow_id, files, download_commands: {} }`
- Changed fallback report "DATA LOCATION" section to "NEXT STEPS / Download via BioMate run panel"

### 1.4 S3 labels in AfterRunReport

**File:** `frontend/client/src/v2/AfterRunReport.tsx`

**Problem:** Dataset table showed `"S3 reference"` and `"URL reference"` as note labels.

**Fix:** Changed to `"Cloud storage"` and `"Remote file"` respectively.

### 1.5 Duplicate references in literature responses

**File:** `frontend/client/src/components/chat-message.tsx`

**Problem:** The AI LLM response text included a `## References` section at the bottom AND `ResearchResponseDisplay` rendered structured citations — users saw references twice.

**Fix:** When `message.metadata.type === 'research_response'` and structured citations exist, strip the trailing `## References` block from the raw message content before rendering:
```javascript
(message.metadata?.type === 'research_response' &&
  (message.metadata?.research_response as any)?.citations?.length > 0)
  ? (message.content || '').replace(/\n+(?:#{1,3}\s+|\*{1,2})?references?\**\s*\n[\s\S]*$/i, '').trim()
  : (message.content || '')
```

### 1.6 Confidence scores and internal method metadata

**File:** `frontend/client/src/components/benchmark-evidence.tsx`  
**File:** `frontend/client/src/components/pilot-run-panel.tsx`

**Problem:** "Confidence: X%" and "Methods: ..." labels visible to end users.

**Fix:**
- Removed the entire Confidence/Methods display block from `benchmark-evidence.tsx` (lines 506–520)
- Removed `Estimated accuracy: High/Moderate/Rough` label from `pilot-run-panel.tsx` entirely

---

## Category 2: Workflow Panel UX Failures

### 2.1 Three overlapping button areas (duplicate Restart/Run buttons)

**File:** `frontend/client/src/components/nextflow-workflow-viewer.tsx`

**Problem:** Three separate locations rendered run/stop action buttons simultaneously:
1. Header icon (RotateCcw restart button, always visible)
2. Action bar (Pause/Stop when running; Restart/Run-again when terminal)
3. Footer (always-visible Run/Restart button)

This created 2–3 duplicate buttons visible at the same time, causing confusion.

**Fix:**
- Removed header icon restart button (RotateCcw) entirely
- Removed the `isTerminal` block from the action bar (Restart/Run-again were redundant with the footer)
- Hid the footer run button when `status === 'running'` or `status === 'paused'` (action bar Pause/Stop handles those states):
```jsx
{!executionBlockedReason && status !== 'running' && status !== 'paused' && (
  <button className="btn primary" data-testid="button-run-workflow-panel" ...>
```

Result: exactly one button visible per state — Run (idle), Pause+Stop (running), Run again (completed), Restart (failed).

### 2.2 Download buttons active on failed runs

**File:** `frontend/client/src/v2/AfterRunReport.tsx`

**Problem:** "Download All" and per-file download buttons were active even when the run failed and no outputs existed.

**Fix:** Added `executionStatus` prop to `OutputsTab`. When `totalCount === 0` and `executionStatus === 'failed'`, show a plain message instead of any download UI:
```jsx
if (totalCount === 0) {
  return (
    <div style={styles.tabContent}>
      <p style={styles.empty}>
        {executionStatus === 'failed'
          ? 'No outputs — run did not complete successfully.'
          : 'No output files registered yet.'}
      </p>
    </div>
  );
}
```

### 2.3 "Run again with edits" on empty-parameter workflows

**File:** `frontend/client/src/v2/AfterRunReport.tsx`

**Problem:** "Run again with edits" button in the Parameters tab rendered even when the workflow had no parameters, leading to an empty modal opening.

**Fix:** Wrapped the button render in a guard:
```jsx
{entries.length > 0 && (
  <button ...>Run again with edits</button>
)}
```

### 2.4 Results links (View results / Download all) on failed runs

**File:** `frontend/client/src/components/nextflow-workflow-viewer.tsx`

**Problem:** "View results · Download all · AI analysis · Report · QC audit log" links were visible below the workflow settings panel even after a failed run.

**Fix:** Changed outer condition from `(invocationId || status === 'completed')` to `status === 'completed'` — links only appear on successfully completed runs.

### 2.5 "Fix & Retry via Chat" button

**File:** `frontend/client/src/components/nextflow-workflow-viewer.tsx`

**Problem:** A "Fix & Retry via Chat" button appeared in the workflow panel after failure. It sent a generic chat message but didn't actually fix anything — pure UI noise.

**Fix:** Removed the entire button block.

### 2.6 AI-analyzed / error_type metadata leak

**File:** `frontend/client/src/components/nextflow-workflow-viewer.tsx`

**Problem:** `"AI-analyzed"` badge and `errorExplanation.error_type` raw value were displayed in the failure UI, leaking internal classification labels.

**Fix:** Removed the `error_type` + "AI-analyzed" metadata line from the failure display block.

### 2.7 Empty Phases tab with "Run failed before any phases started"

**File:** `frontend/client/src/components/nextflow-workflow-viewer.tsx`

**Problem:** When a run failed before any phases started (e.g., pipeline crashed at launch, no input file found), the Phases tab showed `"Steps will appear here once the workflow runs."` — misleading because the run was already over.

**Fix:** Differentiated the empty-state message by status:
```jsx
{status === 'failed'
  ? 'Run failed before any phases started. Check the error details above.'
  : 'Phases will appear here once the workflow starts.'}
```

### 2.8 wf-chip status badge in chat

**File:** `frontend/client/src/components/chat-message.tsx`  
**File:** `frontend/client/src/styles/reference-design.css`

**Problem:** The wf-chip (compact workflow card in chat messages) always showed "In panel" with a neutral/green style regardless of run state.

**Fix:** Made the chip status-aware using `currentExecutionRun?.execution?.status`:
- `chip-ok` (green) — completed
- `chip-run` (blue, pulsing) — running
- `chip-fail` (red) — failed

Added `chip-run` and `chip-fail` CSS classes to `reference-design.css` (only `chip-ok` existed before).

---

## Category 3: Intent Routing Bug (PDF Paper → Wrong Workflow)

### Root Cause Analysis

**User action:** "tell me what this paper is about" + PDF attachment

**What happened:**
1. User uploads a PDF → BioMate converts it to `[BioMate dataset: paper.pdf (id: s3://...)]`
2. The message with that annotation is sent to Gemini Flash (intent classifier)
3. The classifier sees "user provided a file" → applies HIGHEST PRIORITY RULE → classifies as `workflow_generation`
4. The system prompt does say "document reading without execution intent → research_question" but the LLM ignores it when a file annotation is present
5. A literature/paper-analysis workflow gets matched from the DB
6. That workflow receives the PDF's S3 path as `input_data`
7. Nextflow fails immediately (can't process a PDF)
8. Phases tab shows empty (no SSE step events before crash)

### Fix 1: Paper-question guard

**File:** `frontend/server/galaxy-assistant.ts`  
**Location:** ~line 3204 (FINAL gate, after all other `needsWorkflowGeneration` overrides)

Added a programmatic guard that fires after the intent classifier result is processed:
```typescript
if (paperContentResult && actions.needsWorkflowGeneration) {
  const _isPaperQuestion = 
    /\b(what\s+(is|does|are|do)|tell\s+me|summarize|summary|explain|describe|findings?|abstract|key\s+points?|main\s+(finding|result|point|conclusion)|overview|about\s+this|this\s+paper|the\s+paper)\b/i
      .test(originalUserQuery)
    && !/\b(run|execute|process|align|map|call|quantify|trim|filter|differential\s+expression|variant|genotype|assemble|pipeline|workflow)\b/i
      .test(originalUserQuery);
  if (_isPaperQuestion) {
    log('Paper-question guard: PDF attached + question about paper — routing to research_response, not workflow');
    actions.needsWorkflowGeneration = false;
    intent.type = 'research_question';
  }
}
```

### Fix 2: Guard tests original user query, not injected message

**Critical bug in the first implementation:** The guard originally tested `message` — but by line 3010, `message` has already been modified to inject thousands of words of paper content:
```typescript
message = `${message}\n\n[Paper content: ${paperContentResult.ref}]\n${paperContentResult.content}`;
```

A bioinformatics paper will contain words like `"pipeline"`, `"run"`, `"workflow"`, `"execute"` in its body — causing the negative condition to suppress the guard even for simple "tell me about this paper" queries.

**Fix:** Saved the original user query before injection:
```typescript
const originalUserQuery = message; // saved BEFORE paper content injection
```

And the guard now tests `originalUserQuery` (what the user actually typed).

### Fix 3: LLM rationale logging

**File:** `frontend/server/galaxy-assistant.ts`

Added visibility into why the classifier picks each intent type:

1. Added `"rationale"` field to the JSON output schema in the system prompt:
```json
{
  "type": "workflow_generation",
  ...
  "rationale": "User pasted a raw nucleotide sequence inline — this is a direct computation request, not a pipeline execution."
}
```

2. Logged the raw LLM response before parsing (so rationale is always visible even if JSON parse fails):
```typescript
console.log('[Intent Classifier RAW]', resultText.slice(0, 1500));
```

3. Extracted and logged the rationale prominently after parsing:
```typescript
console.log(
  `[Intent Classifier] type=${intentType} confidence=${result.confidence ?? '?'}` +
  (intentRationale ? `\n  rationale: ${intentRationale}` : '')
);
```

---

## Files Changed

| File | Changes |
|------|---------|
| `frontend/client/src/components/chat-message.tsx` | BioMate dataset strip regex, references dedup, wf-chip status |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | `sanitizeErrorText()`, removed header restart, results-links guard, removed Fix&Retry, single footer button, empty phases message |
| `frontend/client/src/components/benchmark-evidence.tsx` | Removed confidence/methods display |
| `frontend/client/src/components/pilot-run-panel.tsx` | Removed estimated accuracy label |
| `frontend/client/src/v2/AfterRunReport.tsx` | S3→Cloud labels, failed-run no-downloads, empty-params guard |
| `frontend/client/src/styles/reference-design.css` | Added `chip-run` and `chip-fail` CSS classes |
| `frontend/server/routes.ts` | Removed Nextflow/S3/InvocationID from reports and API responses |
| `frontend/server/galaxy-assistant.ts` | Paper-question guard, `originalUserQuery`, LLM rationale logging |

---

## Known Open Issues

- **Phases tab badge "1" on failed fast run:** When `workflowDefinition.steps` has entries with `phase_group` set, the badge shows the phase count even though the run failed before those phases ran. No SSE events update the step status, so all steps remain in "pending" state. Cosmetically misleading but not harmful — would need backend to emit a `run_aborted` event clearing phase state.

- **Paper-question guard scope:** The guard only fires on paper-question keywords. A more adversarial prompt like "run analysis on what this paper describes" with a PDF attached will still route to `workflow_generation` correctly. The guard is conservative by design.

- **Workflow DB match for paper uploads:** If a workflow exists in the DB that matches keywords in the paper title (e.g., "RNA-seq analysis paper" matching the RNA-seq workflow), it can still be selected as the candidate workflow BEFORE the guard fires. The guard prevents execution but the workflow card may still briefly appear in the UI during the generation step if the routing happens asynchronously.
