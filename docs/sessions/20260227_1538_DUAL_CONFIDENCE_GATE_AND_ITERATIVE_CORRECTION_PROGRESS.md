# Dual Confidence Gate and Iterative Correction Progress (2026-02-27 15:38)

## Objective

Continue from iterative backend trials and add enforcement so execution proceeds only when both:

1. **Technical confidence** is acceptable.
2. **Scientific confidence** is acceptable.

If not acceptable, system should request correction/confirmation before run.

## Implemented changes

### 1) Propagate generation assessment from UI workflow card into execution API request

Files:
- `frontend/client/src/components/chat-message.tsx`
- `frontend/client/src/components/chat-with-artifacts.tsx`
- `frontend/client/src/hooks/useUnifiedExecution.ts`

Details:
- `ChatMessage` now enriches workflow object passed to run handler with:
  - scientific confidence signal from generation stage
  - `needsUserFeedback`
  - domain guard status/reason
  - candidate workflow alternatives
  - tool installation success signal
- `ChatWithArtifacts` forwards this as `generationAssessment` in `/api/workflows/execute` request.
- Hook type updated to include optional `generationAssessment`.

### 2) Backend execution gate: require both scientific + technical readiness

File:
- `frontend/server/routes.ts` (`POST /api/workflows/execute`)

Added gate logic:
- Technical checks:
  - required inputs present
  - no known tool-install blocker from generation stage
- Scientific checks:
  - generation did not indicate `needsUserFeedback`
  - domain guard did not mark mismatch
- If blocked and no explicit override:
  - return `409 confidence_gate_blocked`
  - include guidance and next actions.

Override path:
- `request.executionConfig.allowLowConfidence === true` allows explicit operator override.

Payload hygiene:
- strips internal `__generationAssessment` key before sending workflow definition deeper into execution path.

## Why this is important

This moves system behavior from "best effort run" to "controlled run":

- not only technically runnable,
- but also scientifically acceptable or explicitly user-confirmed.

## Validation

- Lints:
  - edited files clean.
- Playwright:
  - `e2e/domain-case-performance.e2e.ts` passed.
  - `e2e/feedback-regression.e2e.ts` passed.

## Current status

The system now supports:
- iterative retrieval and confidence raising,
- best-candidate exposure for user correction when confidence is insufficient,
- backend run-time enforcement of dual confidence policy (with explicit override).

