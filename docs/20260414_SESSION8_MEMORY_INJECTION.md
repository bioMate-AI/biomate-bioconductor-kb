# Session 8 — Memory Injection: P1 Episodes + P2 Corrections
## Date: 2026-04-14 | Branch: integration/next-phase

---

## What Was Built

Two new memory injection paths that surface stored episodic and correction data into
the LLM system prompt on the first message of each session.

### P1 — Episode Memory Injection

**Problem**: `project_episodes` table stores past workflows with outcomes, `whatWorked`,
`whatFailed`, and `lessonsLearned` arrays — but none of this ever reached the LLM.

**Fix**:
- `memory-repository.ts`: New `EpisodicMemoryRepository.getRecentUserEpisodes(userId, limit)` —
  joins through `projects` to retrieve user-scoped episodes (not project-scoped), ordered by
  `importanceScore DESC, createdAt DESC`.
- `routes.ts`: New `GET /api/memory/user/episodes?limit=N` endpoint (auth required).
- `galaxy-assistant.ts`: New `_buildEpisodeMemoryBlock(message, userId)` — keyword-scores top-10
  episodes against the current query, injects top-5 as structured block with date, outcome,
  lessons, what_worked, what_failed.

**System prompt format**:
```
[Past research episodes — use to inform context-aware responses]
  ✓ 2026-04-10 — "CryoSPARC SPA for GPCR complex, 250 kDa"
    Lessons: Use B-factor ≥ 200 for refinement; binning_factor=2 gave best CTF
    Worked: Full dataset processed at 0.143 FSC
  ✗ 2026-04-08 — "ADMET screening on compound library"
    Lessons: logP filter was too strict — filtered all compounds
```

### P2 — Correction-Log Routing Injection

**Problem**: `correction_log` stores user-corrected routing decisions (suggestedApproach →
correctedApproach with userExplanation) — but the LLM never saw them, so it kept making
the same routing mistakes.

**Fix**:
- `routes.ts`: New `GET /api/memory/user/corrections?limit=N` endpoint (auth required).
  `getUserCorrections()` already existed in `UserMemoryRepository` — just needed an HTTP surface.
- `galaxy-assistant.ts`: New `_buildCorrectionContextBlock(userId)` — formats top-5 corrections
  as routing constraints injected before `analyzeIntent()`.

**System prompt format**:
```
[User routing corrections — apply these preferences when selecting workflows]
  • Prefer rnaseq_star_rsem over rnaseq_salmon — "We always use STAR+RSEM for this project"
  • Prefer C1 symmetry for GPCR cryo-EM
```

### Injection order

All three blocks are now fetched in parallel on `isFirstMessage`:

```
correctionBlock   (P2) — routing constraints, inject first so they reach analyzeIntent()
+ episodeBlock    (P1) — past outcomes with lessons
+ crossSessionBlock    — existing session summary bullets
```

The merged prefix is prepended to `context.ltmContextBlock`.

---

## Files Modified

| File | Change |
|---|---|
| `frontend/server/memory-repository.ts` | Added `getRecentUserEpisodes(userId, limit)` to `EpisodicMemoryRepository` |
| `frontend/server/routes.ts` | Added `GET /api/memory/user/episodes` + `GET /api/memory/user/corrections` |
| `frontend/server/galaxy-assistant.ts` | Added `_buildEpisodeMemoryBlock()` + `_buildCorrectionContextBlock()`, wired in `isFirstMessage` block |
| `frontend/e2e/session8-memory-injection.e2e.ts` | 4 new E2E tests |
| `docs/20260414_MEMORY_INJECTION_PLAN.md` | Planning doc with test use cases |

---

## E2E Results — 4/4 PASS (2.1 min)

| Test | ID | Result | Key finding |
|---|---|---|---|
| Episode endpoint returns 200 / 401 | MI-1 | ✅ PASS | 401 — endpoint exists, auth enforced, not 404 |
| Corrections endpoint returns 200 / 401 | MI-2 | ✅ PASS | 401 — endpoint exists, auth enforced, not 404 |
| Cryo-EM session unaffected by injection | MI-3 | ✅ PASS | "cryosparc" + "pixel size" still in response |
| Drug-gen session unaffected by injection | MI-4 | ✅ PASS | "reinvent" still in response |

MI-3 and MI-4 are regression tests: memory injection must not break existing routing.
Both pass — the three injection paths are fully non-blocking (try/catch, never throws).

---

## What the Memory Injection Changes

| Before | After |
|---|---|
| LLM sees: session memory + 1-line domain profile + 5 session summary bullets | LLM sees: correction constraints + episode outcomes/lessons + session summaries + 1-line domain profile |
| Routing: no learning from past corrections | Routing: correction log shapes workflow selection |
| Response: no awareness of past failures/successes | Response: can reference past lessons without user asking |

---

## What Remains (Phase 2 E2E)

Full memory-shapes-routing E2E tests (UC-P1-1, UC-P2-1 from the plan) require real episode and
correction data seeded in the DB. These will be testable once:
1. The `recordInteraction()` path auto-creates episodes after workflow execution
2. The correction path fires automatically when the user redirects the system
3. Prod Postgres has several weeks of real user history

Current gap: episodes are written only via the explicit `POST /api/memory/projects/:projectId/episodes`
endpoint (manual). Auto-recording on workflow execution is P3 scope.

---

*Related: `20260414_MEMORY_INJECTION_PLAN.md` · `20260414_SESSION7_PLAN_AI_SCIENTIST_ROADMAP.md`*
