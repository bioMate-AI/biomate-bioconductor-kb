# Memory Injection Plan — P1 & P2
## Date: 2026-04-14 | Branch: integration/next-phase

---

## Problem Statement

BioMate stores rich episodic and correction memory to PostgreSQL — but 90% of it never reaches the LLM.

| Table | Written by | Read back? |
|---|---|---|
| `project_episodes` | `memoryService.episodes.recordEpisode()` | ❌ Never injected into system prompt |
| `correction_log` | `POST /api/memory/user/corrections` | ❌ Never read back |
| `user_preferences` | `memoryService.users.recordPreference()` | ✅ Partial (domain profile 1-line only) |
| `sessions` | `memoryService.sessions.createSession()` | ✅ `_buildCrossSessionContextBlock()` — but only uses `summary` text |
| `project_procedures` | Manual only | ❌ Never injected |

**Impact**: The system has no long-term learning. Every session starts from scratch. A user who ran CryoSPARC 10 times gets no benefit from their own history.

---

## P1 — Episode Memory Injection

### What it does
On the first message of each session, fetch the user's top-10 most relevant past episodes from `project_episodes`, score them by keyword overlap with the current message, and inject the top-5 into the system prompt before `analyzeIntent()`.

### Test use cases

**UC-P1-1 — Cryo-EM repeat user**
```
Setup: User has a recorded episode for CryoSPARC SPA with pixel_size=0.83, outcome=success,
       whatWorked=["binning_factor=2 gave best CTF"], lessonsLearned=["Use B-factor ≥ 200 for refinement"]
Query: "I want to run SPA on my new GPCR dataset, Titan Krios, 300 kV"
Expected: LLM system prompt contains the past episode. Response should reference past parameters
          or lessons without the user asking.
```

**UC-P1-2 — Drug discovery follow-up**
```
Setup: User has a failed ADMET episode: whatFailed=["logP filter was too strict, filtered all compounds"]
Query: "Run ADMET screening on my compound library"
Expected: Episode injected; LLM can proactively mention the logP filter issue from past experience.
```

**UC-P1-3 — No episodes — no pollution**
```
Setup: New user with 0 episodes
Query: Any query
Expected: No episode block in system prompt, normal routing proceeds
```

### API endpoint
`GET /api/memory/user/episodes?limit=10` — user-scoped, auth required.
Returns: `ProjectEpisode[]` ordered by `importanceScore DESC, createdAt DESC`.

### System prompt format
```
[Past research episodes — use to inform context-aware responses]
  ✓ 2026-04-10 — "CryoSPARC SPA for GPCR complex, 250 kDa"
    Lessons: Use B-factor ≥ 200 for refinement; binning_factor=2 gave best CTF
    Worked: Full dataset processed at 0.143 FSC
  ✗ 2026-04-08 — "ADMET screening on compound library"
    Lessons: logP filter was too strict — filtered all compounds
```

---

## P2 — Correction-Log Routing Injection

### What it does
On the first message of each session, fetch the user's correction history from `correction_log`,
format as routing constraints, and inject before `analyzeIntent()`. This prevents the LLM from
repeating routing mistakes the user has already corrected.

### Test use cases

**UC-P2-1 — Routing correction remembered**
```
Setup: User corrected: suggestedApproach={"workflow": "rnaseq_salmon"},
       correctedApproach={"workflow": "rnaseq_star_rsem"},
       userExplanation="We always use STAR+RSEM for this project"
Query: "Analyze my RNA-seq data" (same type of query)
Expected: Correction block injected. LLM should route to STAR+RSEM, not Salmon.
```

**UC-P2-2 — Multiple corrections — top-5 injected**
```
Setup: User has 12 correction entries
Expected: Only the 5 most recent are injected (to avoid prompt bloat)
```

**UC-P2-3 — Correction with context filter**
```
Setup: Correction has workflowContext={"domain": "proteomics"}
Query: "Run RNA-seq analysis" (different domain)
Expected: Proteomics-specific corrections may be de-prioritized (future: domain filtering)
```

### API endpoint
`GET /api/memory/user/corrections?limit=10` — user-scoped, auth required.
Returns: `CorrectionLogEntry[]` ordered by `createdAt DESC`.

### System prompt format
```
[User routing corrections — apply these preferences when selecting workflows]
  • "When I say 'RNA-seq analysis', route to rnaseq_star_rsem (not rnaseq_salmon)" — "We always use STAR+RSEM for this project"
  • "For GPCR cryo-EM, always use C1 symmetry as default"
```

---

## Implementation Plan

### Files modified
1. `frontend/server/memory-repository.ts` — add `EpisodicMemoryRepository.getRecentUserEpisodes(userId, limit)`
2. `frontend/server/routes.ts` — add `GET /api/memory/user/corrections`, `GET /api/memory/user/episodes`
3. `frontend/server/galaxy-assistant.ts` — add `_buildEpisodeMemoryBlock()`, `_buildCorrectionContextBlock()`, wire in `isFirstMessage` block

### Injection order in system prompt
```
[session_memory block]          ← already exists (working memory)
[cross-session context]         ← already exists (session summaries)
[episode memory — NEW P1]       ← structured episodes with lessons/outcomes
[correction constraints — NEW P2] ← routing preferences inferred from corrections
[domain profile]                ← already exists (1-line profile)
```

P2 injection happens before `analyzeIntent()` — corrections affect routing.
P1 injection happens in the `ltmContextBlock` — episodes inform response generation.

---

## E2E Test Plan

File: `frontend/e2e/session8-memory-injection.e2e.ts`

| Test | ID | What it validates |
|---|---|---|
| Episode endpoint returns 200 | MI-1 | API contract works, auth enforced |
| Corrections endpoint returns 200 | MI-2 | API contract works, auth enforced |
| Normal cryo-EM session unaffected | MI-3 | Memory injection is a non-breaking addition |
| Drug-gen session unaffected | MI-4 | Regression: Track 7D tests still pass |

Full memory-shapes-routing tests (UC-P1-1, UC-P2-1) require seeded episode data in the DB.
These are tracked as Phase 2 E2E tests once the production Postgres has real episode data.

---

*Related: `20260414_SESSION7_PLAN_AI_SCIENTIST_ROADMAP.md` · `20260414_KNOWLEDGE_FLOW_AUDIT_AND_PROPOSAL.md`*
