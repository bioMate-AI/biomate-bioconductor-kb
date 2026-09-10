# BioMate Data-Centric Upgrade — Master Test-Plan Index

**Date:** 2026-09-09 · Branch: integration/dev-test

Detailed use-case specs (preconditions → input → action flow → expected output →
information flow → pass criteria → edge/error) for every page / module / sidebar /
panel / tab. All testids/routes/endpoints extracted from real source; items not
determinable from code are flagged in each plan.

## The four plans — 190 use cases

| Plan | File | UCs |
|---|---|---|
| Cold-start / Composer / Chat | `20260909_TESTPLAN_COLDSTART_COMPOSER_CHAT.md` | 68 |
| Run-surface / Step / AfterRun | `20260909_TESTPLAN_RUNSURFACE_STEP_AFTERRUN.md` | 41 |
| DataHub / Dataset / Models | `20260909_TESTPLAN_DATAHUB_DATASET_MODELS.md` | 40 |
| Design / Search / Sidebar | `20260909_TESTPLAN_DESIGN_SEARCH_SIDEBAR.md` | 41 |

## Execution notes (per CLAUDE.md)

- No mocked API in E2E; live dev with shared fixture `lifeifei163361@163.com`
  (bypass `x-e2e-test-token: biomate-e2e-bypass-token-dev-only`); login once,
  one project per harness, 90 s LLM timeouts.
- Live SSE use cases require a REAL run (header badge is parent-`status`-driven).
- Pure helpers (`reRank`, `classifyRejection`, `isContradiction`, `laneForText`,
  `readIntent`, `groupProgressMessages`) are unit-testable directly.

## Spec-drift & non-wired controls found while reading (product decisions to confirm — do NOT file as test bugs)

1. **Sidebar** diverges from the CLAUDE.md checklist: no "Runs→/dashboard"
   (route commented App.tsx:608), no "CRO Library", no "Billing", "Workflows"
   opens **WorkflowHistoryDialog** (not StarredWorkflowsDialog); real entries:
   New Chat, Workflows, Connectors, IND Report, Data, Models, Design&Generate,
   Projects tree, chat dots, Settings, collapse, logout.
2. **"Make a project instruction"** permanently disabled — no write endpoint.
3. **ModelsPanel**: only `onOpenModel` wired; other open/compare/supersede links no-op.
4. **Auto-loop hard-locked** (`autoloopLocked=true`); **skip-toggle display-only**;
   StepDetail **"Re-run from here" never wired** by the viewer; `eSignature` never forwarded.
5. `/trajectory` endpoint doesn't exist (404); `/api/qc/profiles` unconfirmed.
6. Composer `disabled` prop doesn't gate textarea/send; `pendingCount` unused.
7. **RecentToolsDialog** mounted with no opener.
8. Two preview paths per file (DatasetObject structured `/api/perception/profile`
   vs FileTree raw `/url` client-parse) — test separately.
