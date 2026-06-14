# Project framework build-out — session summary (2026-06-12 → 2026-06-13)

Tracks the work from "Q4 chat-stream wiring failed because the LTM
schema didn't exist" (2026-06-11 audit) to "memory subsystem actually
captures user activity and recovers datasets across sessions inside
the same project, with cross-project isolation guaranteed and
verified live on dev."

Branch: `bioc/v2-qc-audit-panel`.

---

## Commits, in order

| Commit | Title |
|---|---|
| `cd08a6554` | fix(auth): registration email-verify link 404 + expired-trial 404; ship LTM schema |
| `fbb864d0d` | feat(chat): re-enable Q4 project-framework wiring (LTM schema now exists) |
| `b9ef8a984` | feat(chat): persist chat_sessions.project_id for cross-session isolation |
| `11b443619` | docs(chat): dataset storage boundaries + cross-session isolation policy |
| `0991abf2f` | feat(projects): full LTM project framework — server CRUD + client UI |
| `bb7e1f8c3` | fix(build): stub regulatory-training-routes so dev build can ship |
| `ad06fbccc` | docs+test(projects): PM-level test plan + live audit on dev (31/31 pass) |
| `476d413d5` | fix(memory): bridge chat-stream sessionId ↔ LTM sessions.id uuid |
| `e2869deac` | feat(chat): cold-refresh dataset recovery within project (UC-B closer) |

---

## What landed, layer by layer

### Database schema

Three migrations applied cleanly on dev:

| Migration | Adds |
|---|---|
| `0012_ltm_schema.sql` | 12 LTM tables — `ltm_users`, `projects`, `sessions`, `conversation_messages`, `user_preferences`, `correction_log`, `project_knowledge`, `workflows`, `project_episodes`, `project_procedures`, `conversation_state_facts`, `pending_tasks`. Fully idempotent. |
| `0015_chat_sessions_project_id.sql` | `chat_sessions.project_id uuid` FK to `projects(id)` `ON DELETE SET NULL` + scoping indexes. |
| `0016_ltm_sessions_chat_link.sql` | `sessions.chat_session_id text UNIQUE` — the bridge column that maps chat-stream's text sessionId to LTM's uuid sessions.id. |

`shared/ltm-schema.ts` mirrors these via drizzle declarations.

### Server-side core (`memory-repository.ts`)

New + updated methods on `MemoryService`:

- `ensureLtmUser(userId, email?, name?)` — idempotent upsert, called on every chat-stream + every `/api/projects` request.
- `resolveProjectForChat(clientProjectId?)` — returns the client's value or null; **does NOT auto-create** (the policy correction).
- `ensureChatLtmSession(userId, chatSessionId, projectId?)` — finds-or-creates the LTM sessions row keyed by `chat_session_id`, returns its uuid for chat-stream to pass through as `memorySessionId`. Closes the silent-write bug that was dropping every episode.
- `recoverProjectDatasets(projectId, currentChatSessionId)` — project-scoped SQL pulling distinct dataset references from other sessions' `chat_sessions.datasets` jsonb, last 14 days, LIMIT 20. Returns entries marked `recovered: true`.
- `ensureDefaultProject` — kept as `@deprecated` with the auto-create branch removed; legacy callers still resolve to null.

On `ProjectMemoryRepository`:

- `archiveProject(id)` — soft-delete via `status='archived'`.
- `deleteProject(id)` — hard-delete; CASCADEs to episodes/procedures/knowledge; chat_sessions.project_id → NULL.

### Server-side API (`project-routes.ts`)

Six endpoints, every one ownership-checked at row-fetch time (404 on cross-user, never 403):

```
GET    /api/projects?status=          list user's projects
POST   /api/projects                  create
GET    /api/projects/:id              fetch + loadProjectContext
PATCH  /api/projects/:id              update mutable fields
POST   /api/projects/:id/archive      soft-delete shortcut
DELETE /api/projects/:id              hard-delete (CASCADEs)
```

`ensureLtmUser` is called at the entry of `GET` and `POST` so a
brand-new user can hit the API before they've ever chatted.

### Server-side chat-stream wiring (`routes.ts`)

Inside the `/api/chat/stream` handler, after history rehydration:

```ts
let _ltmSessionUuid: string | null = null;
let _recoveredDatasets = [];

if (req.user) {
  try {
    await memoryService.ensureLtmUser(uid, email, name);
    _resolvedProjectId = await memoryService.resolveProjectForChat(context?.projectId) ?? undefined;
    if (_resolvedSessionId) {
      _ltmSessionUuid = await memoryService.ensureChatLtmSession(uid, _resolvedSessionId, _resolvedProjectId);
      if (_resolvedProjectId) {
        _recoveredDatasets = await memoryService.recoverProjectDatasets(_resolvedProjectId, _resolvedSessionId);
      }
    }
  } catch (e) { /* defensive — never break chat */ }
}
```

`enrichedContext`:

- `projectId: _resolvedProjectId` (undefined when project-less)
- `memorySessionId: _ltmSessionUuid ?? undefined` (LTM uuid, not text)
- `sessionDatasets`: direct + dedup'd recovered, dropping recovered if id already present in direct

The persist closure (declared earlier in the handler) writes `chat_sessions.project_id` via COALESCE so a previously-set value is never clobbered.

### Server-side prompt block (`galaxy-assistant.ts`)

`sessionDatasetsBlock` now splits the `<session_datasets>` bulletin into two labeled sections:

```
<session_datasets>
Datasets attached to this conversation (Galaxy history is the source of truth …):
  - foo.csv | id=… | type=csv

Datasets from earlier sessions in this project (recovered after refresh
— the user did NOT attach them this turn; ask once if you're unsure):
  - bar.csv | id=… | type=csv

… anti-confabulation instruction: confirm intent for *recovered*
   datasets but never claim the user attached them this turn …
</session_datasets>
```

### Client (`frontend/client/src/…`)

- `lib/api.ts` — six new methods mirroring the endpoints.
- `contexts/active-project-context.tsx` — `ActiveProjectProvider` persists the active id to `localStorage('biomate-active-project-id')`. Exposes `createProject / archiveProject / deleteProject / renameProject / setActiveProjectId / refresh`.
- `components/chat-interface.tsx` — reads localStorage and conditionally threads `projectId` into the chat-stream context body. Missing/null → project-less mode.
- `components/app-sidebar.tsx` — "Workspaces" entry (FolderOpen icon already imported) navigates to `/workspaces`.
- `pages/workspaces.tsx` — full management UI. The active card has a first-class **"Clear (chat will be project-less)"** affordance, not just "switch to another."
- `App.tsx` — `ActiveProjectProvider` mounted under `AuthProvider`; `/workspaces` route added; legacy `/projects` route preserved (different concept; do not break).

---

## Policy + isolation guarantees

All from `docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md`, verified live:

1. **Chats can have no project.** Auto-creation was walked back after the parallel session re-introduced it. `chat_sessions.project_id` stays NULL when the client doesn't send `projectId`.
2. **Datasets cross sessions only within the same project.** Recovery query is gated on `_resolvedProjectId` being non-null and SCOPES BY `project_id`, never `user_id`. Verified: session B1 (different project) and session C1 (project-less) get zero recovery while session A2 (same project) gets one.
3. **Cross-user access never leaks existence.** Every per-id endpoint returns 404 on cross-user attempts. Verified: 7/7 secondary-user attacks blocked.
4. **CASCADE + ON DELETE SET NULL.** Hard-deleting a project removes its episodes/procedures/knowledge but keeps the chat session row with `project_id=NULL`. Verified: 0 rows in each cascaded table; chat row survived with `project_id IS NULL = TRUE`.
5. **Server-resolved projectId beats client-sent.** A buggy client can't dissociate a session from its resolved project. Verified by source assertion + persist behaviour.

---

## Live audit results

### S1–S6 against `https://dev-public.biomate.ai`
- **31 / 31 assertions PASS** (`docs/20260613_PROJECT_FRAMEWORK_AUDIT_RESULTS.md`)
- Driver: `scripts/audit_project_framework.sh`

### LTM session bridge

```
Project: 60683890-…
Session: memw-v2-1781317684

LTM sessions row:
  id = 7b4c3b7e-ddee-49d7-b183-fd655823ad09
  chat_session_id = memw-v2-1781317684
  has_project = true

project_episodes row:
  id = 10
  user_query = "Run DESeq2 on the airway dataset, tumor vs normal"
  workflow_generated = true

Log: [MemoryIntegration] Recorded episode 10
```

### Cold-refresh recovery

| Session | Same user, same project as A1? | Expected | Live |
|---|---|---|---|
| A2 | yes, same project, same user | recovers 1 dataset | ✅ `recovered 1 project-scoped dataset(s)` |
| B1 | same user, **different** project | NO recovery | ✅ silent |
| C1 | same user, **project-less** | NO recovery | ✅ silent |

---

## Source-level tests added (locks in every contract)

| File | Purpose | Assertions |
|---|---|---|
| `server/chat-audit-followups.test.ts` (updated) | Q1/Q2/Q4 policy | 15 |
| `server/chat-sessions-project-scoping.test.ts` | project_id persistence + COALESCE | 5 |
| `server/project-routes.test.ts` | 6 endpoints, ownership, validation | 11 |
| `server/project-framework-wiring.test.ts` | client→server full chain | 16 |
| `server/ltm-session-bridge.test.ts` | bridge schema + helper + wiring | 7 |
| `server/cold-refresh-recovery.test.ts` | recovery SQL + wiring + prompt block | 12 |
| **TOTAL** | | **66 new** |

Full suite at session end: **736 passed / 4 skipped / 2 pre-existing DATABASE_URL env failures unrelated.**

---

## What was walked back (parallel-session reverts)

Two of my mid-session commits were reverted by parallel claude
sessions (stashed as `stash-server` / `stash-server2`). Both
recovered + re-applied:

1. The "chats can be project-less" policy walk-back (commit
   eventually landed within `feat(projects): full LTM project
   framework`).
2. The `regulatory-training-routes` import try/catch (since
   stub-routed properly in `bb7e1f8c3`).

---

## Open backlog (small, tracked)

1. **`chat_sessions.datasets` 100-entry cap** with LRU eviction. Defensive only.
2. **`chat_sessions.messages` post-compression eviction** — pre-compression turns dropped once a summary row covers them.
3. **Playwright UX flow** against `/workspaces` — source-level testid contract already locked.
4. **Memory-integration episode-driven prompts** — episodes are now being written; surfacing them as injected context on subsequent turns is the next user-visible feature unlock.

---

## Related documents

- `docs/20260610_REAL_USER_FULL_CHAT_LOGS.md` — wjunlin@HKU root incident.
- `docs/20260610_CHAT_CONTEXT_AUDIT_4_QUESTIONS.md` — Q1/Q2/Q3/Q4 audit.
- `docs/20260611_CHAT_FIXES_USECASE_AUDIT.md` — UC-A/B/C/E live evidence.
- `docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md` — isolation policy.
- `docs/20260613_PROJECT_FRAMEWORK_TEST_PLAN.md` — PM-style test plan.
- `docs/20260613_PROJECT_FRAMEWORK_AUDIT_RESULTS.md` — 31/31 live evidence.
