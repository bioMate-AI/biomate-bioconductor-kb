# 07a · Memory & Learning

**Verified 2026-08-29.** Source: `backend/lib/galaxy/ai/memory/agentic_memory.py`, `frontend/server/memory-*.ts`, `frontend/shared/ltm-schema.ts`.

---

## 1. The 4-layer hierarchy — design vs. code

The 4-tier model is documented in `docs/architecture/19_hierarchical_memory_architecture.drawio.xml` and the spring-2026 docs, but **only L3 is a real memory store**:

| Layer | Design role | Code reality |
|-------|-------------|--------------|
| **L1 Volatile** | in-memory hot cache, 5-min TTL | **Design-only** — no dedicated cache class in `memory/` |
| **L2 Transient** | Redis session store, 24h TTL | Redis exists but is used for run-state + billing, **not** a memory session store |
| **L3 Persistent** | PostgreSQL LTM | **Fully implemented** (§2) — the real, load-bearing layer |
| **L4 Searchable** | SQLite FTS5 + 384-dim vectors | Implemented as the **workflow/tool** search (`vector_search.py`, BGE-small), not per-user memory |

The shipped Python (`agentic_memory.py`) is a pure SQLAlchemy→Postgres service with no Redis/in-memory tier; the frontend runtime path is `memory-repository.ts` (1,280 lines) + `memory-integration.ts` (473 lines).

## 2. LTM tables (L3, Postgres)

Dual-defined and kept in sync: SQLAlchemy (`agentic_memory.py`) + Drizzle (`ltm-schema.ts`), migrated via `0012_ltm_schema.sql`. Nine tables with `agentic_memory.py` line refs: `ltm_users` (L48), `projects` (L73), `sessions` (L106), `user_preferences` (L152), `correction_log` (L172), `project_knowledge` (L191), `workflows` (L211), `project_episodes` (L244), `project_procedures` (L278). Service classes `UserMemoryService` / `EpisodicMemoryService` / `ProceduralMemoryService`, unified by `AgenticMemoryService` (L739); session bootstrap `initialize_session_context` (L754). Column-level detail: [DATABASES §2](../05-data/DATABASES.md).

## 3. The three learning mechanisms

1. **Explicit corrections** — `record_correction` inserts into `correction_log` (`agentic_memory.py:412`; frontend `recordCorrection` L157). Stored as suggested→corrected pairs with an `applied_to_future` flag.
2. **Implicit preference reinforcement** — `record_preference` (L389): on an existing key it bumps `usage_count += 1` and **`confidence = min(1.0, confidence + 0.1)`**. Frontend identical (`recordPreference` L124, bump L139). **Fully implemented on both sides.**
3. **Emergent procedures from 3+ episodes** — `consolidateEpisodes` (`memory-repository.ts:741–771`) groups successful episodes by `userIntent` into a `Map` and flags patterns where **`group.length >= 3`** (L760). Procedure reliability tracking is real (`record_usage` recomputes `success_rate`; `get_reliable_procedures` filters `>= 0.7`).

> **Gap:** the ≥3-episode → procedure *distillation* is **detected but not written**. `consolidateEpisodes` only counts/logs the pattern (L762 "Could create/update procedures here"); the write path (`createProcedure`, L790+) exists but is never called. Wiring this closes the learning loop — an upgrade item.

## 4. Chat integration

`memory-integration.ts` records episodes after interactions (L350), retrieves matching procedures (L274) and similar episodes (L288), and injects lessons from successful episodes into the prompt context (L307–313). LTM corrections are also prepended to the intent at the top of `generate_workflow_unified` (see [AI_ASSISTANT §1.1](../03-backend-ai/AI_ASSISTANT.md)).

## Key files

| Path | Purpose |
|------|---------|
| `backend/lib/galaxy/ai/memory/agentic_memory.py` | 9 LTM tables + 3 services (the real memory layer) |
| `frontend/server/memory-repository.ts` (1280) | runtime repository; preference reinforcement L139; episode consolidation L741 |
| `frontend/server/memory-integration.ts` (473) | records/retrieves/injects memory in chat |
| `frontend/shared/ltm-schema.ts` (646) | Drizzle schema mirror |
| `backend/lib/galaxy/ai/vector_search.py` | L4 vectors (workflow/tool search) |
