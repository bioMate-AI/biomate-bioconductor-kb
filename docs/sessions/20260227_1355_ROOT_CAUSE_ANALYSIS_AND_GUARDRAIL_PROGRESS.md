# Root Cause Analysis and Guardrail Progress (2026-02-27 13:55)

## User request interpreted

- Clarify why the current approach can still produce incorrect workflows.
- Dig to root cause using real evidence.
- Document findings in detail.
- Continue implementation work to improve BioMate behavior.

## Evidence-led diagnosis

### 1) Current pipeline prioritizes "generate runnable workflow" over "domain-correct workflow"

- In `frontend/server/galaxy-assistant.ts`, workflow generation is intentionally attempted whenever workflow intent is detected.
- It does not require strong domain-fit certainty before generation.

Observed code behavior:
- `shouldGenerate` is effectively true for workflow intent.
- Confidence remains high even when tool match is weak.

### 2) Tool retrieval/ranking can produce semantically nearby but domain-wrong matches

- Tool search strategy uses short keyword queries and then LLM ranking on returned candidates.
- If returned candidate pool is skewed (e.g., QC terms matching microbiome tools), ranking can still choose non-WES tools.

### 3) Assistant text can acknowledge mismatch while still returning executable workflow

- In observed UI evidence, assistant warns that found tools are not ideal for WES, but still presents a runnable workflow card.
- This creates a high-trust UX hazard: user may execute a scientifically misaligned pipeline.

### 4) Existing validator checks execution readiness, not scientific appropriateness

- `workflow-prerequisites-validator.ts` verifies inputs/parameters and compatibility, intentionally domain-agnostic.
- This is valuable but insufficient to stop domain-mismatched workflows.

### 5) Execution API gate is structural only

- `/api/workflows/execute` enforces presence of required inputs.
- It does not enforce domain-to-tool consistency.

## Why additional guardrail is needed

The system currently has:
- **Technical validity checks** (inputs/params/execution),
- but no **scientific domain-fit gate** before execution.

Therefore, wrong-domain workflows can still pass and run.

## Improvements implemented in this cycle

### A) Backend: domain-fit guard metadata added to chat response

File:
- `frontend/server/routes.ts`

What was added:
- A domain-guard computation before sending chat response.
- Guard triggers when either:
  - WES-like request + microbiome/QIIME-style tool signals + no strong WES-tool signals, or
  - assistant self-reports mismatch phrases like "not ideal match".
- Returns:
  - `metadata.domainGuard.blocked`
  - `metadata.domainGuard.reason`
  - `metadata.domainGuard.detectedDomain`

Purpose:
- Expose explicit blocking signal to UI when generated workflow is likely off-domain.

### B) Frontend: pass domain guard to workflow message metadata

File:
- `frontend/client/src/components/chat-interface.tsx`

What was added:
- Persist `data.metadata?.domainGuard` into message metadata so render components can act on it.

### C) Frontend: block Run button when domain guard blocks execution

Files:
- `frontend/client/src/components/chat-message.tsx`
- `frontend/client/src/components/nextflow-workflow-viewer.tsx`

What was added:
- `executionBlockedReason` prop to `NextflowWorkflowViewer`.
- `Run Workflow` button is disabled when block reason exists.
- Alert banner shown in viewer with human-readable blocking reason.

Purpose:
- Convert silent mismatch into explicit "cannot run yet" behavior.

## Expected product impact

- Users no longer get a simple green path to execute a workflow when the system itself detects likely domain mismatch.
- Reduces risk of invalid scientific runs from misleadingly runnable UI.
- Creates a clear correction loop: regenerate/refine prompt with domain constraints first.

## Remaining gaps (next improvements)

1. Expand domain-fit beyond WES/microbiome heuristics into a reusable domain ontology.
2. Add server-side hard-stop in `/api/workflows/execute` using persisted guard status (defense in depth).
3. Add deterministic and real-UI tests for blocked-run state and successful unblocked rerun after regeneration.
4. Replace keyword heuristics with richer signal from workflow/tool metadata and task taxonomy.

