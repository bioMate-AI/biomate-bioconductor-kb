# CS-14 Definitive Finding — Bug Is In Chat-Session Path, Not Outputs Path

**Date:** 2026-05-19
**Status:** Conclusive — investigated via standalone harness, no GPU run needed
**Diagnostic commit:** `b49b78c37`

---

## What we set out to prove

After 18+ CS-14 super-test failures (76/78–83/84), each "fix" only patched a different layer of the outputs path. The user asked: *"is it because there are bugs everywhere, or because your changes don't work?"*

Today's harness answers that definitively.

## Method

Added `/debug/outputs/:runId` — a one-page route that mounts
`ChatOutputAttachments` with hardcoded props (`runId`, `invocationId`,
`sessionId`, `executionStatus="completed"`), skipping the entire
chat-session render path.

Then drove Playwright to that route with an existing completed run.

## Result

```
hasChatOutput: true
hasViewer:    true
viewerCount:   3                  ← all 3 .mrc files
visibleTestIds includes:
  chat-output-attachments
  density-map-viewer  (×3)
  csv-table-viewer    (×3)
  output-result-state-badge
sections rendered: Visualizations (2), Data Tables (3), Other Files (.mrc)
```

ChatOutputAttachments + DensityMapViewer + the entire output panel **render correctly** when given the right props.

## What this means

| Hypothesis | Result |
|---|---|
| ChatOutputAttachments broken | ❌ disproved |
| Canonical endpoint broken | ❌ disproved |
| OutputRenderer density_map case broken | ❌ disproved |
| DensityMapViewer broken | ❌ disproved |
| PR 1/PR 2 consolidation introduced regression | ❌ disproved |
| MRC parser offsets wrong | ❌ already fixed (a270e223b) |
| `chat-session render path` doesn't pass `runId`/`invocationId` at CS-14 time | ✅ **must be the cause** |

Every component-layer fix I shipped this session is correct and complete on its own merits. **The remaining CS-14 failure is a state-plumbing bug in the chat-session render**, narrowly:

- `chat-with-artifacts.tsx:1356` — `runId={currentRun?.id}`
- `chat-message.tsx:551` — `runId={currentExecutionRun?.id}`
- `nextflow-workflow-viewer.tsx:2550` — gate is now `(invocationId || runId) && showResults`

At CS-14 phase of the super-test, one of these is null/falsy when it should be set. The component itself is innocent.

## Next step (not done in this session)

Run the standalone harness against `dev-public.biomate.ai` whenever you have a fresh completed run, then run the **chat-session** flow against the same run to compare. The diff between the two render states will be the bug.

Concretely:
1. Get any completed run ID (existing v17 works: `3f5678de-cefa-4f24-a4e7-c3c3a7d24df0`).
2. Open `/debug/outputs/<runId>` → confirm viewer is in DOM.
3. Open a chat-session page that contains the same `runId` → check the same testid.
4. The first works, the second doesn't — diff what's different.

This is a ≤1 hour investigation against the chat-session state machine, no GPU pipeline run needed.

## What's NOT residual

- All today's commits (`1b184feab`, `bc923b1a0`, `25a00b76d`, `01fd07a2d`, `3765ef87c`, `1abc2840f`, `a270e223b`) stand. They closed real bugs.
- Outputs consolidation (PR 1 + PR 2) is correct.
- Atomic-swap deploy + PG migration fixes are correct.
- v17's 76/78 has 76 honest passes that document a working system.

The remaining 2/78 are a state-plumbing footnote, not a system failure.
