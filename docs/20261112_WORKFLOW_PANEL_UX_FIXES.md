# Workflow Panel UX Fixes — 2026-11-12

Deployed to dev as `484efdda98` (build-info verified live, `result=healthy`, all
smoke tests passed). Branch: `deploy/panelfix-20261112` (pushed to origin).

## What changed

Three founder-flagged UI issues in the chat + workflow panel, each committed on
top of the live dev commit `6474f200d1`, gate-green, then merged with f9's
deployed line (`48baba4653`) before deploy.

### 1. Chat + workflow panel share the window ~half-and-half (`c86f4036a3`)
`frontend/client/src/components/chat-with-artifacts.tsx`

- The panel was capped at a fixed `860px`, leaving it narrow on wide screens
  (founder: "can the chat and the workflow panel share the window half half?").
- Now caps at **~60% of the window** (`Math.min(round(splitWidth*0.6), splitWidth-340)`),
  reserving ≥340px for chat, and **defaults to a ~48% even split** until the user
  drags the splitter — after a drag, their width wins (`userResizedPanel` ref).
- Overlay mode (mobile / <880px) is unchanged.

### 2. Step-detail pre-run view simplified (`6d49c03a73`)
`frontend/client/src/components/steps/step-detail.tsx` + en/zh locales

- A not-run step showed a full provenance chain of n/a placeholders ("tool not
  reported / version n/a / 0 outputs / duration n/a") plus the long origin-badge
  caption (founder: "too much placeholder info in the step detail panel when it
  is not run yet").
- A step with **no run-evidence** now shows a single "Not run yet" line,
  suppresses the redundant outputs-empty text, labels params neutrally
  ("Parameters" / "no configurable parameters"), and hides the origin-badge
  caption until real badged params exist.
- Critically, the pending test gates on **run-evidence** (`tool || toolVersion ||
  duration || outputs.length || workDir || jobId || errorMessage`), NOT the status
  string — a recorded step with no explicit status still shows its full chain.
- New i18n keys: `not_run_yet`, `params_planned`, `no_params_planned` (en + zh).

### 3. Step task description shown in the detail panel (`191571c151`)
`frontend/client/src/components/steps/step-detail.tsx`,
`frontend/client/src/components/nextflow-workflow-viewer.tsx`

- The pre-run detail panel showed parameters but never explained what the step
  does (founder: "the step task can have more details here").
- The viewer's step objects already carried an annotation
  (`step.annotation/description/summary` from the workflow definition), but
  `buildStepDetailStep` dropped it. Now threaded through to
  `StepDetailStep.description` and rendered as a brief line under the step name.
- Real data, shown **only when the definition supplies it** — honest-empty
  otherwise (no new placeholder). Verified wired end-to-end: `PhaseGroupStep`
  carries `description`, `groupStepsIntoPhases` preserves whole step objects, and
  a trim-guard turns empty `""` into undefined.

## Testing

- `tsc --noEmit`: 0 errors on each commit and on the merged line.
- Targeted suites: `step-detail` (18 tests), `nextflow-workflow-viewer` (53),
  plus f9's merged suites (code-execution-block, hint-tip, tool-turn-truncation,
  user-facing-error) — all green.
- Full `vitest run`: 3285 passed. The single failure is the known flaky
  `pdf-canvas-viewer.test.tsx` (pdfjs canvas render `waitFor` timeout under
  full-suite parallel load; passes 3/3 in isolation — not touched by this work).
- New guard tests: pending-collapse + evidence-kept (step-detail), description
  thread-through + summary fallback + blank→undefined (viewer).

## Cross-session coordination

Deployed through the shared dev sync lane. Order tonight: 72 (source-query,
`b88dda44e3`) → f9 (coldstart hints/tool-cards/leak-sweep, `48baba4653`) → this
session (`484efdda98`). I yielded the lane to f9 (their leak-sweep was
user-requested), then merged their deployed commit before syncing. Clean merge,
both sides preserved (my step-description/isPending + f9's `userFacingErrorText`
error wrapper). 74 (datasets, PR #390) is 1–2h out; my changes don't touch the
dataset edit flow, so no rebase onto their branch was needed.

## Known open / deferred

- **Phase-merge redesign (lost-phases-on-stop)** — DEFERRED. The planned-vs-runtime
  phase matching for nf-core fully-qualified process names was reverted after
  multi-LLM review found HIGH bugs (dedup drops phases, overlay drops failure
  data). Needs real nf-core matching tests before re-attempting. The current
  behavior keeps the full phase list on stop/pause (resume-safe).
- **Logo square icon** — DEFERRED. No square icon asset exists; both logos are
  horizontal wordmarks (345×99, 1126×312). Needs an asset from the founder.
- **addBriefInfoForStepTask on the phase-card step row** — the step-detail
  description (item 3 above) covers the "more details" ask in the detail panel;
  adding a description inline on the cramped phase-card row is a separate
  design-judgment call, not done.

## Next steps

- Visual E2E audit of the three states on live dev once f9's next deploy settles
  (the founder's standing "end-to-end, every element correct" bar).
- Consolidate the diverged lines: `fix/images-and-reroute-20261111` (review
  worktree) is a stale subset of the deployed superset and carries unrelated
  uncommitted OpenRouter work — needs the founder to reconcile.
