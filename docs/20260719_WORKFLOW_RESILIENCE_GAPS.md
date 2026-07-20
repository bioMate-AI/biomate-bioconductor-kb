# Workflow Resilience Gaps

**Date:** 2026-07-19  
**Status:** Documented, not yet fixed  
**Branch:** integration/next-phase

---

## Summary

Workflow execution (AWS Batch via Galaxy) is durable — the job continues regardless of what happens to the BioMate server or browser session. The UI is not. Workflow state lives in React state and SSE events, not in durable DB storage, so any session break severs the connection to an in-flight or completed run.

---

## Scenario 1: System goes down while a workflow is running

**What happens today:**
- AWS Batch job continues unaffected (it runs independently of the BioMate/Galaxy process).
- Frontend loses SSE connection and its polling loop.
- Workflow panel freezes at "running" state indefinitely.
- When the server comes back up, nothing triggers a re-poll. The panel stays stale until the user manually refreshes.
- Even after refresh, recovery only works if the conversation rehydrates the Galaxy invocation ID from the DB and the panel mounts a status check.

**Gap:** No reconnect/recovery path on server restart. The UI has no mechanism to ask Galaxy "what is the current state of invocation X?" on session restore.

---

## Scenario 2: New session (new tab or new chat) opened while a workflow is running

**What happens today:**
- Workflow continues on Batch.
- The new session has no reference to the running workflow.
- No sidebar indicator, no notification, no way to find the in-progress run without manually navigating back to the original conversation.
- If the user navigates away and the original conversation is not rehydrated, the completed results are unreachable from the UI.

**Gap:** The `workflowInvocationId` is not persisted per-message in the DB. The panel's running state is ephemeral React state. There is no cross-session visibility of active workflows.

---

## Scenario 3: User logs out while a workflow is running

**What happens today:**
- Workflow continues on Batch (the job has no dependency on the user session).
- SSE auth token is invalidated on logout, so no further progress events will be delivered.
- On next login, the conversation exists in the DB, but the panel does not know there is a completed workflow.
- The panel shows its pre-run idle state — as if the run never happened — unless something explicitly queries Galaxy on mount.

**Gap:** Same root cause as Scenarios 1 and 2. No durable link between a chat message and its Galaxy invocation ID, and no on-mount recovery query.

---

## Root Cause

All three scenarios share the same underlying gap:

1. **No durable invocation record.** The Galaxy `workflowInvocationId` returned when a workflow is submitted is not written to the DB alongside the message. It only lives in React state for the duration of the session.

2. **No recovery query on mount.** The workflow panel does not check Galaxy for terminal state on open. It relies entirely on SSE events and an in-memory polling loop — both of which are lost on session break.

3. **No cross-tab or cross-session visibility.** There is no mechanism to surface "you have a running workflow in another conversation" anywhere in the UI.

---

## Fix Required

### Step 1: Persist the invocation ID

When a workflow is submitted, write the Galaxy `workflowInvocationId` to the `messages` table (or a new `workflow_invocations` table) alongside the `conversationId` and `messageId`. This makes the invocation retrievable after any session break.

### Step 2: Recovery query on panel mount

When the workflow panel opens for a message that has a persisted `workflowInvocationId`, query Galaxy for the current status immediately — regardless of SSE state. If the status is already terminal, render the completed state directly.

### Step 3: Sidebar "running" indicator (optional, UX)

Query for any conversation with an active (non-terminal) invocation on load and show a pulse indicator in the sidebar. Lets users find in-progress runs without remembering which conversation they started from.

### Step 4: Post-login recovery sweep (optional)

On login, query Galaxy for all invocations belonging to the user that are in a non-terminal state. If any are now complete, mark them and surface a notification.

---

## Affected Files (when fix is implemented)

- `frontend/server/` — new API endpoint: `GET /api/workflow-invocations/:messageId/status`
- `frontend/migrations/` — add `workflowInvocationId` column to messages (or new table)
- `frontend/client/src/components/nextflow-workflow-viewer.tsx` — on-mount recovery query
- `frontend/client/src/components/chat-with-artifacts.tsx` — write invocation ID on submit
- `frontend/client/src/components/chat-sidebar.tsx` — optional: running indicator
