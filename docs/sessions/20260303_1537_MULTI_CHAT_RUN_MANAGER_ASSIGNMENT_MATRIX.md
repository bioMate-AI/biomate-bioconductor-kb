# Multi-Chat Run Manager Assignment Matrix (2026-03-03 15:37)

## Use this file
- Assign directly by lane (A/B/C) for parallel execution.
- Keep dependencies strict where marked.
- All items reference:
  - `20260303_1532_MULTI_CHAT_RUN_MANAGER_EXECUTION_HANDOFF.md`
  - `20260303_1408_LEVERAGE_FIRST_MULTI_CHAT_RUN_MANAGER_PLAN.md`

---

## Team mapping template
- **BE-1**: backend API/contract owner
- **FE-1**: run manager UI/state owner
- **FE-2**: chat anchoring/traceability owner
- **UX-1**: UX instrumentation and confusion telemetry owner
- **QA-1**: E2E + UAT owner
- **PM-1**: requirement arbitration + sign-off

---

## Assignment matrix

| Ticket | Lane | Suggested Owner | Estimate | Depends On | Parallel With | Deliverable |
|---|---|---|---:|---|---|---|
| WS1-T1 Run overview adapter endpoint | A | BE-1 | 1.5 d | none | WS2-T1, WS3-T1 | `/api/workflows/runs/overview` + tests |
| WS1-T2 Run summary consistency tests | A | BE-1 | 0.5 d | WS1-T1 | WS2-T1 | API parity test coverage |
| WS2-T1 Scope toggle (`current chat`/`all chats`) | B | FE-1 | 1.0 d | none | WS1-T1, WS3-T1 | run manager scope controls |
| WS2-T2 Search/filter/sort | B | FE-1 | 1.5 d | WS1-T1 preferred | WS3-T2 | advanced run discovery UX |
| WS2-T3 Run card metadata hardening | B | FE-1 | 0.75 d | WS2-T1 | WS3-T1 | IDs/readiness/freshness on cards |
| WS3-T1 Focused run context chip | C | FE-2 | 0.75 d | none | WS2-T1 | run context chip in artifacts |
| WS3-T2 Run switch anchoring | C | FE-2 | 1.5 d | WS2-T1 | WS2-T2 | scroll+highlight correct artifact |
| WS3-T3 Message/run mismatch guard | C | FE-2 | 1.0 d | WS3-T2 | WS4-T1 | reduced stale-context leakage |
| WS4-T1 Confusion index telemetry | D | UX-1 | 1.0 d | WS2/WS3 baseline | WS5-T1 | confusion heuristics + events |
| WS4-T2 Triage hierarchy consistency | D | UX-1 + FE-2 | 0.75 d | WS3-T1 | WS5-T1 | standardized status->guidance order |
| WS5-T1 UAT script + product checks | E | PM-1 + QA-1 | 0.75 d | none | all lanes | signed UAT checklist |
| WS5-T2 E2E suites for multi-chat/run manager | E | QA-1 | 2.0 d | WS2+WS3 merged | WS4-T1 | new E2E files + CI green |

Total estimated effort (parallelized): ~5-7 working days.

---

## Recommended sprint sequencing

## Day 1-2 (foundation)
- BE-1: WS1-T1
- FE-1: WS2-T1
- FE-2: WS3-T1
- PM/QA: WS5-T1 draft starts

## Day 3-4 (core UX behavior)
- FE-1: WS2-T2 + WS2-T3
- FE-2: WS3-T2
- BE-1: WS1-T2

## Day 4-5 (correctness hardening)
- FE-2: WS3-T3
- UX-1: WS4-T1 + WS4-T2

## Day 5-7 (validation)
- QA-1: WS5-T2
- PM-1: sign-off gate

---

## Blocking dependency graph
- WS1-T1 -> WS2-T2 (server-side filters/sort preferred)
- WS2-T1 -> WS3-T2
- WS3-T2 -> WS3-T3
- WS2+WS3 merged -> WS5-T2
- WS2/WS3 baseline -> WS4-T1

---

## PR slicing guidance (to reduce merge conflicts)
- **PR-1 (backend contract)**: WS1-T1 + WS1-T2
- **PR-2 (run manager controls)**: WS2-T1
- **PR-3 (run manager discovery)**: WS2-T2 + WS2-T3
- **PR-4 (run focus + traceability)**: WS3-T1 + WS3-T2
- **PR-5 (mismatch guard)**: WS3-T3
- **PR-6 (ux telemetry/triage)**: WS4-T1 + WS4-T2
- **PR-7 (e2e + uat)**: WS5-T2 + docs updates

---

## Definition of done per owner

## BE-1 done when
- `/api/workflows/runs/overview` supports scope and key filters.
- Contract tests pass.
- No regressions in existing run endpoints.

## FE-1 done when
- Scope toggle works and persists.
- Search/filter/sort works on 20+ runs.
- Run cards show context-rich metadata.

## FE-2 done when
- Focus chip always shows run identity.
- Switch-to-run anchors correct artifact.
- No reproducible run/message mismatch in scripted test.

## UX-1 done when
- Confusion signals emitted and observable.
- Triage hierarchy is consistent across running/completed/failed.

## QA-1 done when
- New run-manager/multi-chat E2Es pass.
- Existing strict complete-workflow E2E remains green.
- UAT checklist signed by PM-1.

---

## Required non-regression gates
- Existing strict gate:
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/complete-workflow.e2e.ts --project chromium --retries=1`
- New suites:
  - `npx playwright test e2e/run-manager-multi-chat-scope.e2e.ts`
  - `npx playwright test e2e/run-manager-switch-anchoring.e2e.ts`
  - `npx playwright test e2e/run-manager-search-filter-sort.e2e.ts`
  - `npx playwright test e2e/run-context-traceability.e2e.ts`

---

## Escalation rules
- If WS1 slips: FE uses client-side filter/sort fallback temporarily.
- If WS3 anchoring is unstable: block release, keep feature flag off.
- If telemetry is noisy: ship with logging-only mode and tune thresholds in next patch.

---

## Assignment checklist for you
- [ ] Name owners for BE-1, FE-1, FE-2, UX-1, QA-1, PM-1
- [ ] Confirm sprint window (5-7 days recommended)
- [ ] Confirm feature flags enabled in dev only
- [ ] Confirm CI includes both old strict E2E and new run-manager suites

