# Background Assist Parallel Actions and Run Manager Completion

Timestamp: 2026-03-01 13:15

## Objective

Continue from run-manager/session wiring and implement Claude-like “while running, what can I do meanwhile?” behavior in BioMate UI with real action execution.

## What was missing before this step

1. Run Manager and session-scoped run switching were implemented, but no proactive parallel task affordance existed during active workflow execution.
2. User could continue chatting manually, but no guided, one-click “background assistance” path was surfaced.

## Implementation delivered

### 1) External prompt handoff contract in chat interface

File:
- `frontend/client/src/components/chat-interface.tsx`

Added props:
- `externalPromptRequest?: { id: number; prompt: string } | null`
- `onExternalPromptConsumed?: (id: number) => void`

Behavior:
- New effect listens for external prompt requests.
- When chat is not currently typing, it dispatches the prompt through existing `handleSendMessage(...)` pipeline.
- After dispatch, marks request as consumed via callback.

Result:
- Upstream UI controls can trigger real chat tasks without duplicating API logic.

### 2) Proactive background assist panel during active run

File:
- `frontend/client/src/components/chat-with-artifacts.tsx`

Added state:
- `externalPromptRequest` + request ID counter.

Added helper:
- `submitBackgroundPrompt(prompt, actionId)`:
  - emits telemetry `workflow.background_action_selected`
  - dispatches prompt via external prompt handoff.

Added UI panel inside active execution status bar:
- `data-testid="background-assist-panel"`
- copy: “Workflow is running. I can help in parallel:”
- actions:
  - `button-background-action-review-params`
  - `button-background-action-prepare-next`
  - `button-background-action-draft-report`

Each button sends a concrete prompt into chat automatically.

### 3) Wired handoff into chat interface

File:
- `frontend/client/src/components/chat-with-artifacts.tsx`

`ChatInterface` now receives:
- `externalPromptRequest={externalPromptRequest}`
- `onExternalPromptConsumed={...}`

So parallel action clicks become real assistant tasks in same session context.

## New E2E coverage

Added:
- `frontend/e2e/ux-background-assist-panel.e2e.ts`

Test validates:
1. workflow enters running state,
2. background assist panel appears,
3. clicking “Draft report outline” triggers a real `/api/chat` request with corresponding prompt intent,
4. assistant response appears from that background action.

## Regression and validation results

### Lint
- No linter issues on modified files.

### Build
- `npm run build` succeeded.

### E2E
- `ux-background-assist-panel.e2e.ts` PASS
- `ux-run-manager-panel.e2e.ts` PASS
- release matrix strict gate PASS:
  - `feedback-real-ui-strict.e2e.ts` PASS
  - `pm-user-stories-comprehensive.e2e.ts` PASS

Artifact:
- `frontend/e2e/matrix-runs/feedback-matrix-run-20260301_130934.txt`

## Current status vs your ask

You asked for multitask convenience similar to background assistance:

- Run Manager: implemented and wired.
- Session-scoped run list/switch: implemented and wired.
- Proactive “meanwhile” guided actions: now implemented and actionable.

## Remaining optional enhancements

1. Add “suggest once per run milestone” throttling (e.g., show at 10% and then hide unless user reopens).
2. Add a mini outcome tracker showing which background actions were requested during each run.
3. Expand quick actions to include “monitor logs and alert me only on failures”.

