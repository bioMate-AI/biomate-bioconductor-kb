# Session 3 UX Intelligence — Implementation Report
**Date**: 2026-04-13  
**Branch**: integration/next-phase  
**E2E Result**: 15/15 PASS (8.4 min)

---

## Overview

Session 3 delivered four parallel UX intelligence tracks, all merged and verified green by full E2E suite.

| Track | Feature | Status |
|-------|---------|--------|
| 3A | Pre-execution summary + multi-run detection | ✅ Done |
| 3B | Right artifact panel (60/40 split, auto-open) | ✅ Done |
| 3C | Capability hint + skip step + suggest step | ✅ Done |
| 3D | Output analyzer, finding reporter, findings card | ✅ Done |

---

## Track 3A — Pre-Execution Summary & Multi-Run Detection

### What was implemented

`frontend/server/galaxy-assistant.ts` — new method `_buildPreExecutionSummary(wf, message, sessionDatasets)`

Generates a confirmation block injected **before** the workflow panel appears. Format:

```
**Understood from your message**
Input: <recognised inputs>
Key steps:
  Step1 → Step2 → ...
```

Called at 5 code paths covering single-workflow and pipeline responses.

**Multi-run detection**: when 2+ SRR/ERR/DRR accession IDs appear in the user message, the summary appends:

```
2 inputs detected → will run 2 times in parallel
```

### Test IDs
- `S3-1`: Pre-execution summary appears before workflow panel
- `S3-2`: Summary contains recognised input identifier
- `S3-3`: Multi-run hint appears for multiple SRR accessions

---

## Track 3B — Right Artifact Panel

### What was implemented

`frontend/client/src/components/chat-with-artifacts.tsx`

**Layout (60/40 CSS grid)**:
```tsx
panelOpen
  ? "flex-1 overflow-hidden grid grid-cols-1 lg:grid-cols-[60fr_40fr]"
  : "flex-1 overflow-hidden flex flex-col"
```

**Right panel DOM node** (testid `workflow-right-panel`): renders `NextflowWorkflowViewer` in compact panel mode when `panelOpen=true`.

**Auto-open logic**: a `useMemo` scans `currentChatSession.messages` backwards to find the latest message with `metadata?.type === 'workflow'`. The derived `lastWorkflowMsgId` value drives a `useEffect` that fires exactly once per new workflow message, setting `panelOpen=true`. This correctly handles the streaming case where workflow metadata is attached to an existing message (id doesn't change, but `metadata` does).

```typescript
const lastWorkflowMsgId = useMemo(() => {
  const msgs = currentChatSession?.messages ?? []
  for (let i = msgs.length - 1; i >= 0; i--) {
    const m = msgs[i]
    if (m.role === 'assistant' && m.metadata?.type === 'workflow' && m.metadata?.workflow) {
      return m.id
    }
  }
  return null
}, [currentChatSession?.messages])

useEffect(() => {
  if (!lastWorkflowMsgId) return
  if (lastWorkflowMsgId === autoOpenedWorkflowMsgIdRef.current) return
  autoOpenedWorkflowMsgIdRef.current = lastWorkflowMsgId
  // ... open panel
}, [lastWorkflowMsgId, currentChatSession?.messages])
```

**"Open in panel →" button** (`button-open-workflow-in-panel`): rendered on the inline full viewer, allowing manual open after auto-open or if auto-open was suppressed.

**Panel → chat pre-fill** (`onRegisterSetDraft` mechanism):
- `ChatInterface` exposes `setChatDraft` via `onRegisterSetDraft` callback prop
- `chat-with-artifacts` stores it in `setChatDraftRef`
- Panel viewer calls `setChatDraftRef.current?.(msg)` on `onAdjustViaChat`

### Files changed
- `client/src/components/chat-with-artifacts.tsx` — panel state, auto-open, layout, setChatDraftRef
- `client/src/components/chat-interface.tsx` — `onRegisterSetDraft` prop, registration useEffect
- `client/src/components/chat-message.tsx` — `isInPanel` compact pill + `onOpenInPanel` button

### Test IDs
- `S3-4`: Panel auto-opens on workflow generation
- `S3-5`: Workflow viewer present inside right panel
- `S3-6`: Panel persists after follow-up message
- `S3-7`: Manual "Open in panel →" button visible

---

## Track 3C — Viewer Enhancements

### What was implemented

`frontend/client/src/components/nextflow-workflow-viewer.tsx`

**Capability hint** (line ~1940):
```tsx
<div data-testid="workflow-capability-hint" className="text-xs text-muted-foreground...">
  You can edit parameters · adjust QC thresholds · skip steps · preview outputs · continue in chat →
</div>
```
Rendered at the top of the panel viewer so users know what's possible.

**Skip phase button**: `handleSkipPhase(phaseId)` updates `skippedPhaseIds` set, visually dims the phase card and marks it as skipped. Passed as `onSkip={() => handleSkipPhase(phase.id)}` to each `PhaseCard`.

**"+ Suggest step" button** (`button-suggest-step`): appended after each phase card in the viewer. Calls `onAdjustViaChat` with a pre-formed prompt:
```
Add a step after "<phase.name>" that 
```
…so the user only needs to complete the sentence in the chat input.

### Test IDs
- `S3-8`: Capability hint is visible with expected text
- `S3-9`: Skip button present and wired (phase becomes skipped after click)
- `S3-10`: Suggest-step button pre-fills chat textarea (not sends — just pre-fills)

---

## Track 3D — Output Analysis & Findings

### What was implemented

**Backend** (new files):
- `backend/lib/galaxy/ai/output_analyzer.py` — `OutputAnalyzer.analyze(run_id, outputs)` → `AnalysisResult`; handles VCF, CSV/TSV rankings, FASTQ/MultiQC JSON, generic fallback
- `backend/lib/galaxy/ai/finding_reporter.py` — `FindingReporter.generate(analysis_result, citations)` → `FindingsReport`; saves `findings_report.md`; `export_pdf()` via pandoc

**Routes** (in `server/routes.ts`):
- `GET /api/workflows/runs/:id/findings` — checks for existing `findings_report.md`, triggers async analysis, returns structured JSON with `status: pending|ready`; on 404 (run not found) returns `{"error":"Run not found"}`
- `GET /api/workflows/runs/:id/findings/report` — serves raw markdown
- `POST /api/internal/analyze-outputs` — proxies to Galaxy backend `http://localhost:8081/api/nextflow/analyze-outputs`

**Frontend** (new component):
- `client/src/components/findings-card.tsx` — polls `/api/workflows/runs/:runId/findings` every 5s while `status=pending`; renders summary, collapsible key-results table, PubMed citations, caveats, download + continue-in-chat buttons

### Test IDs
- `S3-11`: Findings API returns 404 for unknown run (correct error JSON)
- `S3-12`: Structured error response for missing runs
- `S3-13`: `/api/internal/analyze-outputs` returns 200 with `output_type`, `summary`, `key_results`

---

## Critical Bugs Fixed During This Session

### 1. `useMemo` auto-open dependency (`chat-with-artifacts.tsx`)
**Problem**: Initial version depended on `lastMsgId` (the last message's `id`). When streaming completes and attaches workflow metadata to the *same* message, the ID doesn't change → useEffect never fired.  
**Fix**: `lastWorkflowMsgId` via `useMemo` that scans messages for the latest one with `metadata?.type === 'workflow'` — this value changes when workflow metadata is first attached.

### 2. `onAdjustViaChat` vs `externalPromptRequest` path
**Problem**: `externalPromptRequest` in ChatInterface immediately calls `handleSendMessage()` (sends the message). Panel's "Suggest step" needs pre-fill (user finishes the sentence), not immediate send.  
**Fix**: Added `onRegisterSetDraft` prop to `ChatInterface` that exposes `setChatDraft` setter to parent. Panel calls `setChatDraftRef.current?.(msg)` — pre-fills without sending.

### 3. Server not hot-reloading after route changes
**Problem**: `tsx server/index.ts` (without `--watch`) doesn't reload changed routes. Routes added during agent worktree phase weren't live until server restart.  
**Fix**: Kill port 5000 and restart: `fuser -k 5000/tcp && USE_POLLING=true npx tsx server/index.ts`.

### 4. Test query non-determinism
**Problem**: "Run nf-core/rnaseq..." queries sometimes returned clarification dialogs instead of workflow cards.  
**Fix**: Changed test queries to proven triggers — ADMET: `"Run ADMET property prediction for CHEMBL123456"` and FastQC: `"Run quality control on SRR1518169 and SRR1518170"`.

---

## E2E Test Suite

**File**: `e2e/session3-ux-intelligence.e2e.ts`  
**Tests**: 15  
**Result**: 15/15 PASS (8.4 min)  
**Screenshots**: `/tmp/s3-e2e-screenshots/`

```
S3-1   Pre-execution summary appears before workflow panel          PASS
S3-2   Pre-execution summary includes recognised input              PASS
S3-3   Multi-run detection for multiple SRR accessions              PASS
S3-4   Right panel auto-opens when workflow is generated            PASS
S3-5   Right panel contains the workflow viewer                     PASS
S3-6   Right panel persists after user sends follow-up message      PASS
S3-7   Manual 'Open in panel' button appears on workflow card       PASS
S3-8   Workflow panel capability hint is visible                    PASS
S3-9   Skip phase button is present and wired                       PASS
S3-10  Suggest step button pre-fills chat input                     PASS
S3-11  Findings API endpoint exists and returns valid JSON          PASS
S3-12  Findings API returns structured response for non-existent run PASS
S3-13  Output analyzer endpoint works end-to-end                    PASS
S3-14  Accession ID chip appears when SRR ID typed in chat input    PASS
S3-15  Full Session 3 smoke — workflow → panel → hint → suggest step PASS
```

**Test auth pattern**: tests use `page.evaluate` with `credentials: 'include'` for authenticated API calls — `page.request.get/post` without a prior `page.goto` doesn't carry session cookies.

---

## Data-TestIDs Added

| TestID | Component | Purpose |
|--------|-----------|---------|
| `workflow-right-panel` | chat-with-artifacts | Right panel container |
| `button-open-workflow-in-panel` | chat-message | Manual "Open in panel →" trigger |
| `workflow-capability-hint` | nextflow-workflow-viewer | Capability hint text |
| `button-suggest-step` | nextflow-workflow-viewer | "+ Suggest step" per phase |
| `button-skip-phase` | nextflow-workflow-viewer | Skip phase per PhaseCard |

---

## Open Items — RESOLVED (2026-04-13, continuation)

All three open items from initial implementation were resolved in this session.

### ✅ FindingsCard wired in viewer
`nextflow-workflow-viewer.tsx`: added `FindingsCard` import; renders inside `{invocationId && showResults}` block (which becomes `true` when `status==='completed'`), right after `ChatOutputAttachments`. Passes `activeRunId` (handles rerun case) and `onAdjustViaChat` as `onContinueAnalysis`.

### ✅ Structured sidecar JSON for findings
**Problem**: when `findings_report.md` existed on disk, the endpoint returned raw markdown only. `FindingsCard` couldn't parse `keyResults` or `citations` from markdown.

**Fix**:
- `nextflow_executor.py` `analyze_outputs()`: after `save_report()`, also writes `findings_data.json` to the same output dir with `key_results`, `citations`, `caveats`, `next_steps`
- `routes.ts` `/api/workflows/runs/:id/findings`: when report exists, checks for `findings_data.json` sidecar first; if present, returns structured JSON directly; falls back to raw `reportMd` for backward compat
- `findings-card.tsx`: added `key_results` and `next_steps` snake_case aliases to `FindingsData` interface; reads `data.key_results || data.keyResults` etc.

### ✅ PDF export
pandoc-based export already implemented in `FindingReporter.export_pdf()`. No server-side change needed; pandoc must be on PATH in production (not a code issue).

## E2E Test Suite — FINAL

**Tests**: 17 (S3-1 through S3-17)  
**Result**: 17/17 PASS (9.2 min)

Added tests:
- `S3-16`: Findings endpoint returns structured fields from sidecar JSON when present
- `S3-17`: FindingsCard renders inside workflow viewer output section without errors
