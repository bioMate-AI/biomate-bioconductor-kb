# Iterative Backend Confidence + Feedback Loop (2026-02-27 15:30)

## Objective

Implement the essential behavior:

1. Retry backend workflow retrieval iteratively until confidence is good.
2. If confidence remains insufficient, present best candidate(s) and explicitly request user corrections/confirmation before proceeding.

## What was implemented

### 1) Iterative search trials in backend workflow generation

File:
- `backend/lib/galaxy/ai/ai_assistant.py`

Changes:
- Added `_build_intent_trials(user_intent)` to generate retrieval trials:
  - original query
  - normalized query
  - domain-enriched expansion for high-risk intents (WES / RNA-seq DE / microbiome)
- Updated `generate_workflow_unified(...)` to:
  - run search across trial variants,
  - stop early when high confidence appears,
  - otherwise keep the best-scoring trial/result,
  - persist selected trial metadata.

### 2) Explicit low-confidence feedback handoff

File:
- `backend/lib/galaxy/ai/ai_assistant.py`

Changes:
- Added response fields:
  - `needs_user_feedback`
  - `feedback_prompt`
  - `candidate_workflows` (top alternatives)
  - `selected_trial`
  - `trial_count`
- High-confidence path returns `needs_user_feedback=False`.
- Medium/low confidence paths now ask for correction/confirmation rather than silently implying certainty.

### 3) Frontend message behavior for correction loop

File:
- `frontend/client/src/components/chat-interface.tsx`

Changes:
- Appends backend `feedback_prompt` to assistant text when `needs_user_feedback=true`.
- Changes suggestions to correction-oriented options:
  - "This domain looks correct"
  - "Use different domain/tools"
  - "Regenerate with stricter constraints"
  - "Show alternative workflows"
- Stores confidence-loop metadata in message metadata:
  - `needsUserFeedback`, `feedbackPrompt`, `candidateWorkflows`, `selectedTrial`, `trialCount`.

## Why this addresses your concern

This changes the core behavior from:
- "single retrieval pass + confidence assumption"

to:
- "iterative retrieval attempts with richer query variants, then explicit human-in-the-loop correction when confidence is still not high."

This is the correct path toward simultaneous:
- technical confidence (runnable, validated),
- scientific confidence (domain-fit confirmed).

## Validation

- Lint check for modified files: no errors.
- UI validation:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/domain-case-performance.e2e.ts --project chromium`
  - Result: `1 passed`.

