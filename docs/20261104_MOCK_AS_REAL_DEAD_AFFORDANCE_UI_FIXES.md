# 2026-11-04 — Mock-as-real / dead-affordance UI fixes

## Goal

Stop presenting fabricated/demo data as the user's real data, and stop showing
controls that silently do nothing. Prefer an honest empty-state over fake data;
wire a no-op control to its real action if a target exists, else remove it.

Worked in an isolated git worktree. No deploy/sync. No edits to CLAUDE.md/config.

## What was changed

### 1) Projects page — fabricated demo projects (HIGH)

- `frontend/client/src/lib/projects.ts`
  - `getLocalProjects()` now returns `[]` when nothing is stored (was seeding
    `getDefaultProjects()`).
  - Deleted `getDefaultProjects()` (the fabricated "biomate AI" / "LIS" rows).
    This was the root source feeding every caller, including
    `project-detail.tsx`'s `projectService.getProject()` fallback — which could
    open a demo project as a real detail page. With the source gone, a missing
    project now hits the existing "Project not found" state honestly.
- `frontend/client/src/pages/projects.tsx`
  - Refactored the loader into `loadProjects()` with a `loadError` state.
  - Empty successful response → real **empty state** ("No projects yet").
  - API error / exception → **error + Retry** state (`projects-load-error`,
    `button-retry-projects`), NOT demo data.
  - `handleProjectCreated` catch no longer substitutes demo data.
  - Removed the now-unused `projectService` import.

**Decision:** removed the demo seed entirely rather than gating it behind an
"example" flag — nothing in the app surfaced it as clearly-labeled example data,
so the honest default is an empty account.

### 2) Starred Workflows dialog (HIGH)

- `frontend/client/src/lib/starred-workflows.ts`: `getAllStarred()` returns `[]`
  when unseeded; deleted `getDefaultStarred()` (3 fabricated demo stars).
- `frontend/client/src/components/starred-workflows-dialog.tsx`: removed the dead
  "View" button (empty `onClick`, no target). Kept the working control (card
  click + the primary button) which routes through the real `onWorkflowSelect`
  prop; relabeled the primary button "Run" → "Open" to match what it actually
  does (select/open, not execute). Removed the now-unused `ExternalLink` import.

### 3) Recent Tools dialog (HIGH)

- `frontend/client/src/lib/recent-tools.ts`: `getAllRecent()` returns `[]` when
  unseeded; deleted `getDefaultRecent()` (5 fabricated demo tools).
- `frontend/client/src/components/recent-tools-dialog.tsx`: removed the dead
  "Star" and "View documentation" buttons (both empty `onClick`). Kept the
  working Remove button and card click (→ real `onToolSelect`). Removed the
  now-unused `Star` / `ExternalLink` imports.
- `frontend/client/src/App.tsx`: `handleStartChat` and `handleAddToWorkflow` were
  `console.log` stubs that only closed the dialog. Wired both to BioMate's real
  chat entry point via `window.location.assign('/?draft=…')` — the exact
  mechanism the project "Analyze with BioMate" flow uses (pre-fills the chat
  input for review, not auto-submitted).
- `frontend/client/src/components/tool-introduction-dialog.tsx`: changed the
  default `onAddToWorkflow` / `onStartChat` props from `console.log` stubs to
  harmless no-ops (the only mount passes the real handlers above).

## Tests added

- `frontend/client/src/lib/starred-recent-projects-empty-state.test.ts` — all
  three services return `[]` when unseeded (no fabricated defaults) and still
  persist genuinely added rows.
- `frontend/client/src/components/starred-recent-dialogs-honest.test.tsx` —
  honest empty state renders; removed dead buttons are absent; the working
  controls route to `onWorkflowSelect` / `onToolSelect`.
- `frontend/client/src/pages/projects-honest-states.test.tsx` — empty success →
  empty state (no demo); API error → error/retry state (no demo); Retry re-fetches.

## Gate results

- `npx tsc --noEmit -p .` — clean (ran via a temporary symlink to installed
  node_modules; the worktree has none of its own. Symlink removed afterwards.)
- `vitest run starred recent projects wiring` — 26 passed (includes the existing
  `server/project-framework-wiring.test.ts`, 16 tests).
- Full `vitest run` — 1050 passed, 7 skipped, 78 files passed / 1 skipped. No regressions.

## Product decisions flagged for the human

1. **No way to star a workflow anywhere in the app.** `starWorkflow()` is never
   called from any UI. The Starred Workflows dialog is now honest (empty-state +
   working Unstar/Open) but will stay empty until a "star this workflow"
   affordance is added. **Build decision needed:** where should the star action
   live (workflow panel? run card?).
2. **"Recent tools" is never populated by real usage.** `addRecentTool()` is only
   called from inside the Recent Tools dialog itself (on click). Real tool usage
   elsewhere does not record into this list, so it will stay empty. **Build
   decision needed:** hook `addRecentTool()` into the real tool-invocation path
   (e.g. where `onToolSelect` / tool execution fires) if this feature is wanted.
3. **Both dialogs' entry points are currently commented out.** In
   `app-sidebar.tsx` the "Actions" panel (Starred Workflows, Recent Tools,
   Billing) is a disabled JSX comment block: "dialogs not yet wired to backend.
   Re-enable once each action lands a real implementation." `StarredWorkflowsDialog`
   is not mounted anywhere; `RecentToolsDialog` is mounted but its only trigger is
   inside that comment. I did **not** re-enable them (out of scope and intentional
   by the team) — these fixes make the components honest *if/when* re-enabled.
   `ToolIntroductionDialog` is reachable only via `onToolSelect`, which today only
   fires from the (gated) Recent Tools dialog, so it is also effectively
   unreachable in the live app.
4. **Starred "Open" / tool CTAs route through chat.** The honest real target for
   "open workflow" / "start chat about tool" / "add tool to workflow" in BioMate
   is the chat entry point (`?draft=`), since that is how workflows are actually
   assembled/run. If the team wants a direct workflow-panel open instead, wire a
   real `onWorkflowSelect` at the (future) mount site.
