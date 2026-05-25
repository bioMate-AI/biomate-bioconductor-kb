# Chat Session Resume Adapter — Opportunity 2 + Framework Shape 3

**Date:** 2026-05-20
**Status:** Sandbox shipped. Framework now hosts THREE distinct adapter shapes.
**Tests:** 145 passing across the session.

## What this adds

`sandbox/intent_retrieval_v3/adapters/chat_session.py` — decides whether to resume the previous chat session or start fresh, based on the user's first message of a new browser load.

```python
from sandbox.intent_retrieval_v3.adapters.chat_session import should_resume_chat_session

decision = should_resume_chat_session(
    query="what's the status of my run?",
    last_session_meta={"id": "abc123", "status": "completed", "age_minutes": 10},
)
# → {decision: "resume", reason: "resume-intent fired: {'continue_previous'}",
#    confidence: 0.85, session_id: "abc123"}
```

## Why this matters — fixes a real BioMate UX bug

Per the session memory: BioMate's frontend uses localStorage to persist `currentChatSession` and remounts the React tree after SSE failures. This means:
- User starts a workflow → page reloads or SSE drops → session **always** restores (correct most of the time)
- User types "new project, let's start fresh" → session **still** restores (wrong)
- User has a stale 3-day-old session → frontend silently restores it (confusing)

The adapter gives the frontend a principled signal: `decision ∈ {resume, new, uncertain}` with confidence + reason for telemetry.

## Why this shape is new

This is the **third distinct adapter shape** in the framework:

| Adapter | Shape | Returns |
|---|---|---|
| workflow_intent | rerank candidates | reordered list |
| memory | rerank candidates | reordered list |
| family_dedup | rerank candidates within group | reordered list |
| entity | extract entities | list of canonical IDs |
| **chat_session** | **binary decision** | **{decision, reason, confidence}** |

Despite the new shape, the framework primitives (`load_intent_map`, `match_intents`) carry through unchanged. The adapter is just **40 LOC of decision logic** on top of the shared intent matcher.

## Decision rules

1. **NEW intent fires → return "new".** Overrides everything else. Explicit user signal: "start fresh", "new project", "clear context".
2. **RESUME intent fires AND session exists → return "resume".** "Continue", "where we left off", "what's the status of my run".
3. **Default: recent terminal session → "resume".** If no intent fires but the last session is `completed`/`failed` and < 30 minutes old, auto-resume.
4. **Otherwise → "uncertain".** Let the UX prompt the user.

## Critical design choice — disqualifier ordering

`continue_previous` includes `new conversation` in its disqualifier list. So when a query contains BOTH "continue" and "new conversation", the disqualifier suppresses `continue_previous`, and `new_project` (whose triggers include "new conversation") fires instead → **decision: new**. This is the right outcome ("continue to a new conversation about something else" → user wants fresh start).

Test `test_continue_with_new_disqualifier_does_not_resume` proves this works.

## Framework loosening required

The original `yaml_loader.load_intent_map` required every entry to have a `canonical` field — appropriate for ranking adapters but wrong for decision adapters. Loosened to require only `trigger_terms`; `canonical` is now optional. **Verified that the change doesn't break workflow / memory / entity adapters** (all 145 tests still pass).

This is exactly the kind of small refactor the framework was designed to absorb cheaply — one line in the loader, no breaking changes.

## Tests — 15 unit tests cover

- All NEW-intent overrides (new project, clear context, start over)
- NEW intent wins over both explicit resume phrases AND recent terminal sessions
- RESUME intent fires for "what's the status", "pick up where we left off", "show me the results"
- RESUME without a session → uncertain (no fabrication)
- Default rule: recent terminal session auto-resumes when no intent fires
- Default rule does NOT fire on stale or running sessions
- Disqualifier interaction (continue + new conversation → new)
- Topic pivot with disqualifier (moving on + the same → falls through to default)
- Empty query falls back to metadata-only decision
- Response shape invariants (every response has decision, reason, confidence, session_id)

## Cumulative session — 14 commits

| Layer | Status | Tests |
|---|---|---|
| family_dedup (wrapper) | shipped to production path, 30/30 held-out safe | 29 |
| workflow_intent (workflow) | sandbox, full benchmark validated | 18 |
| Framework v3 + adapters/workflow | sandbox, v2-v3 parity proven | 22 |
| memory adapter (Opp 1) | sandbox, held-out validated (n=50) | 8 |
| entity adapter (Opp 4) | sandbox, 13 unit tests | 13 |
| **chat_session adapter (Opp 2)** | **sandbox, 15 unit tests** | **15** |
| core regression suite | unaffected | 40 |
| **Total** | **145 passing** | |

## What's done from the 5-opportunity menu

| # | Opportunity | Status |
|---|---|---|
| 1 | Memory recall ranking | ✅ shipped sandbox + held-out validated |
| 2 | **Chat session resume** | **✅ shipped sandbox** |
| 3 | Param recommendation by intent | not started |
| 4 | Biological entity canonical resolution | ✅ shipped sandbox |
| 5 | Regulatory question router | not started |

3 of 5 opportunities are sandbox-shipped. The framework has proven it generalizes across **all three adapter shapes** (rerank, extract, decide).

## Production wiring (when authorized)

For chat_session, the natural call site is `frontend/server/routes.ts` or wherever `currentChatSession` resolution happens. Front-end can call the backend with `(query, last_session_meta)` and get back a decision to act on.

**But:** consistent with your deploy discipline, **no wiring should ship until** there's a held-out eval that demonstrates the decision logic is calibrated correctly on real user queries. The 15 unit tests prove the decision logic is **internally consistent** (covers all branches, disqualifiers work, etc.) but not that the YAML triggers match what real users type.

A held-out chat-session eval would be ~30 real queries with hand-labeled "should resume?" decisions, paired with realistic session metadata. ~half-day to build.

## Architectural summary at session-pause

The framework has demonstrated three things over 14 commits:

1. **Data beats schema across multiple domains** — wrapper-level retrieval, workflow-level routing, memory recall, entity canonicalization, session decisions. Same architecture: curated YAML + small library + held-out safety check.

2. **Adapters compose at low cost** — 32-50 LOC per adapter, ~1 hour each after the framework existed.

3. **Disqualifier discipline holds across all shapes** — zero false positives across every measurement: wrapper, workflow, memory held-out, entity unit tests, chat_session unit tests.

Nothing wired to production. Nothing synced to dev. All work survives on `origin/integration/next-phase` for future sessions to pick up with proven safety properties.
