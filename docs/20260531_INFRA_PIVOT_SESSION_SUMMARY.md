# Infrastructure Pivot Session — 2026-05-29 → 2026-05-31

**Session arc:** moved from publication finalization into an infrastructure pivot at the user's request. The pivot exposed a chain of real product defects that the E2E tests had been silently working around. By the end, 9 real BioMate fixes had landed plus 1 design doc for a Defect 2 follow-up.

User challenge that reframed the session: **"are you improving your test code or improving biomate?"** — forced an honest audit of test-workaround vs root-cause fix on every change.

## Real product fixes (9)

| # | Fix | File | How surfaced |
|---|---|---|---|
| 1 | CryoSPARC SSE port hard-coded → env-driven `FRONTEND_URL` | `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:5430` | Plan-agent triage; CryoSPARC progress events silently dropped in prod (port 3000 vs Node 5000) |
| 2 | Router rule disambiguates HTS plate-QC from `HTSFilter` (RNA-seq) + `sights` (Bioconductor lib) | `frontend/server/galaxy-assistant.ts:3765` | HT-1..5 routing failures; original test patch was a workaround chat-query hint, removed in favor of router rule |
| 3 | ADMET QC profiles (`admet_standard`, `admet_cns`, `admet_oncology`) registered in central catalog | `backend/lib/galaxy/jobs/qc_trace_monitor.py` +75 lines | AD-0 caught: `/api/qc/profiles` returned 44 non-ADMET profiles; the autoloop's own `qc_evaluator.py` profile dict was never surfaced to the API |
| 4 | `ConversationState` persisted on `chat_sessions` (TEXT PK) instead of LTM `sessions` (UUID PK) | `frontend/server/conversation-state.ts` + `frontend/migrations/0011_chat_sessions_conversation_state.sql` | Node log filled with `invalid input syntax for type uuid: "chat-<ts>-<rand>"` every chat turn; cross-turn context silently lost |
| 5 | Chat-stream content persisted server-side via UPSERT-by-message_id | `frontend/server/routes.ts` `/api/chat/stream` + new SQL helper | HT-1 audit showed assistant message persisted with `content:""` permanently when client disconnected mid-stream; spawned via Option A in design doc |
| 6 | `ResearchApp` default export added | `frontend/client/src/v2/ResearchApp.tsx` | App white-screened: "The requested module '/src/v2/ResearchApp.tsx' does not provide an export named 'default'" |
| 7 | `import React from 'react'` added to 7 v2 files | `frontend/client/src/v2/{ResearchApp,ChatCards,ChatStream,Modals,PlanChecklist,Tour,WorkflowPanel}.tsx` | "React is not defined" after #6 was fixed; v2 files used `React.useState`/`React.useEffect` without the import |
| 8 | `useUiFlavor` hook moved above early return in `RootRoute` | `frontend/client/src/App.tsx:106-116` | "Rendered more hooks than during the previous render" when `isLoading` flipped true→false; classic rules-of-hooks violation |
| 9 | Citation corrections (12 total: 9 substantive + 3 DOI typos) verified via `verify_citations.py` | `backend/config/qc_evidence.yaml`, `frontend/client/src/data/qc-evidence.ts`, `backend/experiments/admet_autoloop/knowledge_base.py`, 4 manuscripts | Carryover from publication audit (Aronov 2008, Schilter→Sutter, Overgaard journal, etc.) |

## Test infrastructure (5)

| Fix | File |
|---|---|
| HTS fixture-login port (replaces broken UI-form auth path) | `frontend/e2e/hts-workflows-ux-e2e.e2e.ts` |
| Cryo fixture-login port | `frontend/e2e/cryoem-workflows-ux-e2e.e2e.ts` |
| HT-1..5 explicit workflow hints — added then REVERTED in favor of router rule | `frontend/e2e/hts-workflows-ux-e2e.e2e.ts` |
| `chat-disconnect-persistence.e2e.ts` regression test | `frontend/e2e/chat-disconnect-persistence.e2e.ts` (new, 149 lines) |
| AD-0 verified 4/4 PASS live (`total=47, admet=admet_standard,admet_cns,admet_oncology`) | live curl + Playwright |

## Documents (2)

| Doc | Purpose |
|---|---|
| `docs/20260529_CHAT_STREAM_PERSISTENCE_GAP.md` | Design analysis for Defect 2 (server-side accumulation Option A); implemented in fix #5 with one deviation: client POST was preserved (would have broken sidebar history) and idempotency enforced via `message_id` instead |
| `docs/20260531_INFRA_PIVOT_SESSION_SUMMARY.md` (this file) | Session summary |

## Verified live

- `/api/qc/profiles`: 44 → 47 profiles, all 3 ADMET names present (HUP-reloaded gunicorn)
- `/internal/sse-inject` smoke: POST → `{"ok":true}` HTTP 200
- Migration 0011 applied to `biomate_dev`: `\d chat_sessions` shows `conversation_state jsonb` column
- Server-side chat-stream persistence: 2 smoke tests pass (normal completion: `partial=false, len=433`; abort 1.5 s after first delta: `partial=true, len=283`); empty-stream guard fires (no junk row when abort precedes first delta)
- App.tsx hooks fix: probe page shows real DOM body text after fixes (sign-in form, not blank screen)

## Pattern observations

- **Test failures were the symptom, not the bug.** Every test failure investigated this session traced to a real product defect: missing default export, wrong PG column type, hard-coded localhost port, hooks-order violation, missing profile registration. The CLAUDE.md "no workaround" rule was the right north star — applying it converted ~6 test "failures" into actionable product fixes.
- **Parallel-session sync commits absorb staged edits.** Several of my changes got bundled into `ae5df68ce`, `9a74068c5`, `a69bde529`, etc. when the parallel session's pre-commit hook swept the working tree. Result is the same (changes land), but `git show --stat HEAD` from my commit may not list a file I edited. Trust `git blame` on the affected line.
- **The v2 phase-0 ship in `a5de1dcb2` was incomplete.** Three independent breakages (missing default export, missing React imports across 7 files, hooks-order violation) all came from that one commit. Whoever wrote it never opened the app after committing — every render path crashed. Worth a code-review reminder for v2 future commits.

## Still open (next session)

- HT-1 still fails on `locator('textarea')` after the v2 fixes — App renders sign-in page on probe; auth-cookie injection lands somewhere that still hides textarea. Needs a follow-up probe with the JWT cookie active to see the post-auth state.
- Local Galaxy 8081 stderr noise from billing-Redis ConnectionRefused — cosmetic; production AWS Redis stack works
- Cryo E2E re-runs ($7.50, ~3.75 hr) held for budget approval
- Defect 2 known limitation: partial-disconnect messages persist `content + workflowMetadata.workflow` but not `metadata.steps`/`inlineParameters`/`suggestions` (reconstructed client-side from `final` event). Acceptable for recover-after-disconnect UX.

## Commit chain (this session, on `integration/next-phase`)

Most commits absorbed into parallel-session sync commits; the ones authored under my session header:

- `9df4274f7` infra: port ADMET fixture login + env-driven SSE FRONTEND_URL
- `f0703f50a` infra: HT-1..5 explicit workflow hints (later reverted)
- `2bad2ac2c` fix(router): disambiguate HTS plate QC
- `a7001feaf` fix(qc): register admet_standard/admet_cns/admet_oncology
- `5d200e411` fix(chat): persist conversation_state on chat_sessions
- `d3910af49` test(chat): regression test for server-side persistence
- `b84fb74f8` fix(v2): React import + default export + hooks-order fixes

Pushed to origin at 2026-05-31 02:50 UTC.
