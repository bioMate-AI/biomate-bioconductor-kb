# Chat-context fix-set — use-case audit (2026-06-11)

User request: *"test again, this is not trivial. Audit your work, logs,
outputs. Use cases based e2e tests."*

This document captures the real-world audit results — what works on
`https://dev-public.biomate.ai` after the seven chat-context commits,
where reality deviated from the unit-test claim, and what is being
walked back as a result.

## Methodology

For each fix I ran a use case (UC) against the live dev SSE chat-stream
with the `lifeifei163361@163.com` fixture, then inspected Postgres and
container logs on dev. Unit tests alone are not evidence; the harness
runs against an in-process module graph that does not catch missing
DB tables, missing migrations, or LLM behaviour.

## UC-A — wjunlin "warm" path (datasets in chat window)

**Goal**: bot attached two datasets, then asked DEG after a few turns
of distractor chatter, must produce a workflow card naming both
datasets and NOT ask for re-uploads.

**Setup**: SSE chat-stream, 5-turn conversation (attach + 4 distractors
+ "run DEG tumor vs normal").

**Result**: ✅ **PASS**

- `event: workflow_ready` emitted (not chat_only)
- Bot named both files in the response:
  *"Input: `gse22055_expression.csv` (expression matrix),
  `clinical_gse22055.csv` (metadata)…"*
- Routed to `limma_differential_expression` (microarray-aware) — not
  `nf-core/differentialabundance` (DESeq2)
- Zero forbidden patterns (`please upload`, `share metadata`, etc.)

This is the original wjunlin@HKU bug; it is fixed.

## UC-B — cold-refresh path (no `previousMessages`)

**Goal**: after attaching datasets, simulate a page refresh by sending
`previousMessages: []` on the next turn. Server must rehydrate dataset
state from somewhere durable.

**Result**: ⚠️ **PARTIAL** — emits `workflow_ready` and no forbidden
patterns, but the bot does NOT name the previously-attached files and
the microarray rule does NOT fire (routes to generic DESeq2 instead of
limma).

**Root cause uncovered by the audit**:

1. `chat_sessions.messages` JSONB **only stores assistant replies**
   (`routes.ts:5048`). User messages — which carry the
   `[Galaxy dataset: …]` blocks — are persisted by the client into
   localStorage and (separately) by the `/api/sessions/*` REST surface,
   not by the chat-stream path. My server-side `SELECT messages, datasets
   FROM chat_sessions` rehydration therefore finds an assistant-only
   message history and no dataset context to reinject.
2. The authoritative source of attached datasets is **Galaxy history**,
   not `chat_sessions.datasets`. Pulling from Galaxy history at chat
   time would close this gap properly.

**Status**: tracked as a follow-up. The hot path (UC-A) is fixed; cold
refresh needs a Galaxy-history-fetch path that is bigger than this
fix-set.

## UC-C — Q1 compression dataset preservation

**Goal**: hit `/api/compress-session` with a 30-message conversation
that contains a single `[Galaxy dataset: pinned.csv (id:
deadbeef-1234-cafe-babe-0000-uuid)]` block in turn 1. The LLM
summarizer must not paraphrase the UUID away.

**Result**: ✅ **STRONG PASS**

Server log + response payload from dev:
```
messages_before: 30  →  messages_after : 4
tokens_before  : 3513  →  tokens_after  : 679  (ratio 19%)

**[Preserved dataset attachments across compression — verbatim]**
- [Galaxy dataset: pinned.csv (id: deadbeef-1234-cafe-babe-0000-uuid)]

UUID preserved in summary?  True
Preserved header present?   True
```

The UUID survives verbatim above the LLM-generated prose summary. This
is the canonical case the fix was designed for.

## UC-D — Q2 "Start a new chat" CTA

**Status**: ⏸ not exercised via SSE — this is a UI-only path that fires
at ≥85% of the 200 K-token budget. A Playwright smoke test that drives
the dialog into the high-percentage state and asserts the button is
rendered is the right test; deferred to the next e2e pass.

The source-level assertions in `chat-audit-followups.test.ts` lock in
the prop, percentage gate, testid, and chat-interface wiring — i.e.
the button cannot silently disappear in a refactor.

## UC-E — Q4 project framework

**Goal**: every chat-stream request resolves a `projectId` via
`MemoryService.ensureDefaultProject(userId)`, so memory-integration's
project-scoped procedures / episodes / knowledge paths come online.

**Result**: ❌ **DOES NOT DELIVER ON DEV (HONEST AUDIT FINDING)**

Dev Postgres has **none of the LTM tables**:
```
public | _migrations         public | audit_logs
public | chat_sessions       public | download_jobs
public | execution_runs      public | feature_flags
public | instrument_events   public | instruments
public | invite_code_uses    public | invite_codes
public | mfa_challenge_jtis  public | telemetry_events
public | users               public | ux_feedback
```

`ltm_projects`, `ltm_episodes`, `ltm_procedures`, `ltm_knowledge`,
`ltm_conversation_messages`, `ltm_sessions` — **all missing**. The
schema is defined in `shared/ltm-schema.ts` as drizzle pgTable
declarations, but no SQL migration creates them. So every call to
`ensureDefaultProject` on every chat-stream request was producing:

```
[MemoryService] ensureDefaultProject failed: relation "projects" does not exist
```

…in the frontend container logs, with zero functional benefit because
the table doesn't exist.

This is also why memory-integration's project-memory paths have been
silently no-op'ing in production all along — not a regression from
my fix, but uncovered by it.

**Walked back**: the chat-stream call to `ensureDefaultProject` is
removed. The `MemoryService.ensureDefaultProject` helper stays in
place so the activation is one line of code once a migration
`0012_ltm_schema.sql` ships. `enrichedContext.projectId` continues to
honour whatever the client sends (currently nothing).

## Summary scorecard

| # | Fix | Audit verdict | Evidence |
|---|---|---|---|
| #4 | Pharma boilerplate gate | ✅ Pass | UC-A, no leakage in 4 turns with `clinical_gse22055.csv` |
| #5 | Chain step resolution | ✅ Pass | UC-A, all chain candidates resolved (BP4RNAseq, consensus DE) |
| #6 | SECOND-TURN OVERRIDE leak | ✅ Pass | UC-A response text — no markers |
| #7 | Microarray → limma | ✅ Pass | UC-A routed to limma; **conditional on dataset awareness** (UC-B regressed to DESeq2) |
| Q1 | Compression dataset preservation | ✅ Pass | UC-C, UUID round-trip on dev |
| Q2 | Start-new-chat CTA | 🟡 Source-locked, no UI test yet | Tests; UI smoke deferred |
| Q3 | Token-budget history selector | ✅ Pass | UC-A, byte cap held |
| Q3 | sessionDatasetsBlock | ✅ Hot path; ⚠ cold refresh | UC-A pass, UC-B reveals chat_sessions.messages user-message gap |
| Q4 | Project framework | ❌ **Walked back** — no LTM schema on dev | UC-E, schema audit |

## Decisions made by this audit

1. **Q4 chat-stream call removed.** Helper stays. Re-enable in the PR
   that lands `0012_ltm_schema.sql`. Same PR should ship a runtime
   gate so a missing migration produces a single startup warning,
   not log spam on every chat-stream request.
2. **Cold-refresh path needs Galaxy-history fetch.** Not in this
   fix-set. Tracked: `_resolvedDatasets = await fetchGalaxyHistory(userId, recent=20)`.
3. **chat_sessions.messages persistence is asymmetric** — only
   assistant replies. Document this. Either fix it (persist user
   messages too at chat-stream time) or stop relying on it.
