# Session: Prereq Recovery Removal + Information Flow Fixes
**Date**: 2026-04-06
**Branch**: `integration/next-phase`

---

## Summary

Removed the prereq recovery panel (dead UX path introduced in March), fixed the resulting information flow gap, confirmed D4 LLM error analysis is complete, and cleaned all "Nextflow"/"Galaxy" product-internal branding from user-facing text.

---

## 1. Prereq Recovery Panel — Removed

### What it was
When the Run button was blocked by missing prereqs, the viewer showed a button:
> "Ask BioMate to prepare runnable demo inputs"

Clicking it sent a hidden chat message to the backend. The backend detected the phrase, set `prereqRecovery.approved=true` in metadata, and the frontend carried forward the previous workflow + bypassed confidence gates.

### Why it was removed
- The information flow was opaque: user clicks a button but doesn't know what message was sent or why
- The agent architecture (added 2026-04-06) broke it: the recovery turn's agent loop generates a **new Galaxy workflow** from the recovery message text, overwriting `workflowData` with something that has no `workflow_type`/`format`/`nextflow_path` → `isNextflow=false` → silent early return, no execution
- Three root causes were fixed to get GC-2 passing, but the underlying design was fragile
- "Prepare runnable demo inputs" is meaningless to a real user who just wants to run a real workflow

### Files changed
| File | Change |
|------|--------|
| `nextflow-workflow-viewer.tsx` | Removed recovery button JSX and `onRequestPrereqRecovery` prop |
| `chat-message.tsx` | Removed `onRequestPrereqRecovery` prop, `prereqRecoveryApproved` logic, override bypasses |
| `chat-interface.tsx` | Removed prop, recovery carry-forward block, recovery workflowInfo append, `prereqRecovery` metadata field |
| `chat-with-artifacts.tsx` | Removed `handlePrereqRecoveryRequest` function |
| `routes.ts` | Removed `prereqRecovery` block from both `/api/chat` and `/api/chat/stream` endpoints |
| `prereq-normalizer.ts` | Removed `allowPrereqRecovery`, `toolInstallationSuccess` options; removed `tool_runtime` item |
| `germline-complete-e2e.e2e.ts` | GC-2: removed recovery button path; direct fail if run button disabled |

---

## 2. Information Flow Fix — Blocked Prereqs

### Problem after removal
When prereqs block the run button, the checklist showed `actionHint` as passive text with no way to get help. User sees a greyed Run button and a text hint — dead end.

### Fix: `chatPrompt` on PrereqItem
Added `chatPrompt?: string` to `PrereqItem`. When set, the viewer renders a "Continue in chat →" link that calls `onAdjustViaChat(item.chatPrompt)`, pre-filling the chat input without auto-sending.

**Which items get `chatPrompt`:**
- `input_data` with `status: "warning"` or `"missing"` → chat is the resolution (user needs to describe/upload data)
- `confidence_gate` with no override allowed → chat to refine the request

**Which items do NOT get `chatPrompt`:**
- `required_parameters` with `status: "missing"` → params are editable directly in the form above the button; chat is the wrong resolution
- `input_data` with `status: "ok"` → no action needed
- `confidence_gate` with `overrideAllowed=true` → "Confirm and Run Anyway" button already handles this

### Files changed
| File | Change |
|------|--------|
| `prereq-normalizer.ts` | Added `chatPrompt` field to `PrereqItem`; set on `input_data` and `confidence_gate` (no-override) items |
| `nextflow-workflow-viewer.tsx` | Checklist renders "Continue in chat →" button when `item.chatPrompt && onAdjustViaChat` |

---

## 3. Branding Cleanup — "Nextflow" / "Galaxy" Removed from UX

| Location | Before | After |
|----------|--------|-------|
| Workflow card title | `"Nextflow Workflow: {name}"` | `"{name}"` |
| Output panel text | `"Galaxy output hydration may still be in progress"` | `"output processing may still be in progress"` |
| `ai_assistant.py` feedback_prompt | `"I found a Nextflow workflow that partially matches..."` | `"I found a workflow that partially matches..."` |
| `ai_assistant.py` message field | `"Reused/Best available Nextflow workflow: {name}"` | `"Found/Best available workflow: {name}"` |
| `ai_assistant.py` note field | `"Found Nextflow workflow with N step(s)"` | `"Found workflow with N step(s)"` |

Internal fields (e.g. `tool_installation.message: 'Nextflow workflow'`) are not user-facing; left as-is.

---

## 4. Dead Code Removal — `tool_runtime` Prereq Item

The normalizer previously had a `tool_runtime` item that always showed `status: "ok"` for Nextflow. This was because `ai_assistant.py` hardcodes `tool_installation: {success: True}` for all Nextflow workflows (correct — Nextflow containers are pulled at runtime, there is no install step). The item was a permanently-green row that added noise. Removed from normalizer entirely.

The `toolInstallationSuccess` field is still passed in `__generationAssessment` to the execute endpoint, where `routes.ts:5917` checks `toolInstallationReady = generationAssessment?.toolInstallationSuccess !== false`. That server-side gate is still active and correct.

---

## 5. D4 LLM Error Analysis — Status: COMPLETE

The 2026-03-30 audit noted "Regex fallback only" for D4. This was a configuration gap, not a missing feature.

**Current state:**
- `routes.ts:6755` — `POST /api/workflows/explain_error` endpoint
- When `ANTHROPIC_API_KEY` is set: calls `claude-haiku-4-5-20251001`, max 500 tokens, JSON output
- Fallback: regex pattern matching on error log text (8 patterns: missing_file, docker_pull, resource_limit, etc.)
- Viewer: auto-triggered when `status === 'failed'`; shows `· AI-analyzed` or `· pattern-matched` badge
- `.command.err` content from failed Nextflow work dirs is appended to the log before analysis

**The 2026-03-30 note** referred to `ANTHROPIC_API_KEY` not being set in the Galaxy process environment. The LLM call runs in the Node.js layer (not Galaxy), so it needs the key in the Node.js environment — which is set via `frontend/.env`. D4 is complete.

---

## Current Prereq Checklist Behavior (After All Changes)

```
User sends message → AI generates workflow
  ↓
backend returns prerequisitesValidation + domainGuard

prereq-normalizer produces PrereqChecklist:
  input_data:
    ok       → "N dataset mapping(s) detected"
    warning  → "No input data detected yet" + chatPrompt → Continue in chat
    missing  → (not currently reachable — missingInputs always empty for Nextflow)
  required_parameters:
    ok       → "Required parameters are satisfied"
    warning  → "N required parameter(s) will use defaults / N optional"  [no chat]
    missing  → "N required parameter(s) missing, no defaults"  [fill form]
  confidence_gate:
    blocked + override → "Use Confirm and Run Anyway" button + [no chat]
    blocked, no override → actionHint + "Continue in chat →"

canRun = false when any item is "missing" or "blocked"
Run button disabled ← canRun=false OR hasUnfilledRequired (form-level check)
```

---

## GC-2 E2E — Updated Assertion

GC-2 now expects the run button to be **directly enabled** after the workflow card appears (SRR accession present in query → prereq validator maps it → no missing inputs). If the button is disabled, the test fails immediately — no recovery path fallback. This is the correct behavior: if an SRR accession in the query doesn't enable the run button, that's a real bug to fix.
