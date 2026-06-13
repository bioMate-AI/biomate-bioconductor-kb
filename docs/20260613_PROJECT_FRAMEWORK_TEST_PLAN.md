# Project framework — PM-level test plan (2026-06-13)

## Purpose

The project framework is the spine for memory scoping, cross-session
dataset isolation, team collaboration, and per-project billing. Eight
backend endpoints, two new client modules, one UI page, a localStorage
contract, and a database schema with three CASCADE rules. **It deserves
to be tested like the load-bearing module it is.**

This plan is written from a product perspective — what the user
expects to work — and translated into test cases. Source-level vitest
already covers the wiring. This document defines the additional
runtime / E2E / DB-integrity tests that prove the *product* works.

## User stories the framework must satisfy

### As a researcher running multiple lines of work
1. *Create a workspace* with a meaningful name + domain → it appears in my list.
2. *Switch active workspace* → my next chat is scoped to it without me having to remember.
3. *Clear active workspace* → I can ask BioMate a quick question without polluting any project.
4. *Refresh the page* → my active workspace selection persists.
5. *Archive an old workspace* → it disappears from active lists but the data is preserved.
6. *Delete a workspace* → it's gone, including episodes + procedures + knowledge; my chat sessions survive but unlink.

### As a researcher with multiple parallel projects
7. *Talk about project A in one session*, *project B in another* → context doesn't bleed; the bot only sees data from the active workspace.
8. *Attach a dataset in project A* → it's reachable from new sessions within project A, never from project B.

### As a team admin
9. *Another user creates a workspace* → I cannot see it, list it, fetch it, or mutate it. Cross-user access returns a 404 (does not leak existence).

### As BioMate the system
10. *Project memory* (procedures / episodes / knowledge) only loads when an active project is set.
11. *User-scoped memory* (preferences / corrections) loads always, even in project-less mode.
12. *DB constraints* — soft-delete keeps the row; hard-delete CASCADEs to episodes / procedures / knowledge; chat_sessions.project_id → NULL on hard-delete.
13. *Server invariant* — server-resolved projectId always beats client-sent value (in case the client is buggy or malicious).

## Acceptance criteria → test matrix

| # | Story | Test type | Where |
|---|---|---|---|
| 1 | Create workspace | API E2E | `POST /api/projects` returns 201 + row appears in `projects` table |
| 1 | Create workspace — validation | API E2E | empty name → 400; >255 chars → 400 |
| 2 | Switch active | UI/contract | localStorage `biomate-active-project-id` updates |
| 3 | Clear active | UI/contract | localStorage key removed; chat-stream context omits projectId |
| 4 | Refresh persistence | UI/contract | Reload preserves active id |
| 5 | Archive | API E2E + DB | `POST /api/projects/:id/archive` → status='archived' in DB; row absent from `?status=active` list |
| 6 | Delete | API E2E + DB | `DELETE /api/projects/:id` → row gone; chat_sessions.project_id NULLed |
| 7 | Cross-project isolation | API E2E + DB | Chat with project A's id → row gets project A id; chat with project B's id → project B id; never crosses |
| 8 | Cross-session within project | DB query | (deferred — needs cold-refresh recovery code, future PR) |
| 9 | Cross-user access | API E2E | User B's project id from User A's auth → 404 on GET/PATCH/archive/DELETE |
| 10 | Project memory loads on active | Manual + log probe | (deferred — memory-integration is a separate audit) |
| 11 | User-scoped memory always | API E2E | ltm_users row exists after first chat regardless of project |
| 12 | DB constraints | DB query | Manual cascade test |
| 13 | Server invariant | API E2E | Client sends `projectId='foo'` → server overrides to resolved one |

## Test scenarios — runtime steps

### S1: Lifecycle round-trip (happy path)
```
1. Login fixture user
2. POST /api/projects {name:"Test S1", primaryDomain:"transcriptomics"}
3. GET /api/projects → expect Test S1 in list
4. GET /api/projects/:id → expect 200, includes project + context blocks
5. PATCH /api/projects/:id {description:"updated"} → expect 200, description echoed
6. POST /api/projects/:id/archive → expect 200, project.status='archived'
7. GET /api/projects?status=active → expect Test S1 absent
8. GET /api/projects?status=archived → expect Test S1 present
9. DELETE /api/projects/:id → expect 200 {ok:true}
10. GET /api/projects → expect Test S1 absent
11. Direct DB: SELECT FROM projects WHERE id=:id → 0 rows
```

### S2: Validation errors
```
1. POST /api/projects {name:""} → 400 "name is required"
2. POST /api/projects {} → 400 "name is required"
3. POST /api/projects {name:"x".repeat(256)} → 400 "name too long"
4. PATCH /api/projects/:id {status:"garbage"} → 400 "invalid status"
```

### S3: Cross-user isolation (single user simulation)
```
1. Login user A; create project Pa
2. Note Pa.id
3. Login user B (different fixture)
4. GET /api/projects → expect Pa NOT in list (different user)
5. GET /api/projects/Pa.id → expect 404 (do NOT leak existence)
6. PATCH /api/projects/Pa.id → expect 404
7. POST /api/projects/Pa.id/archive → expect 404
8. DELETE /api/projects/Pa.id → expect 404
```

### S4: Chat-stream wiring
```
1. Login fixture user; ensure no active project
2. Send chat (context.projectId omitted) → chat_sessions.project_id IS NULL
3. Create project P
4. Send chat (context.projectId = P.id) → chat_sessions.project_id = P.id
5. Send another chat to the SAME sessionId (context.projectId = P.id) →
   project_id stays P.id (COALESCE protects)
6. Send chat to the SAME sessionId (context.projectId omitted) →
   project_id STAYS P.id (COALESCE prevents accidental clobber)
7. Send chat to a NEW sessionId (context.projectId omitted) →
   that session's project_id is NULL (correctly project-less)
```

### S5: Authorization gates
```
1. GET /api/projects without auth → 401
2. POST /api/projects without auth → 401
3. GET /api/projects/<random uuid> without auth → 401
4. With auth, GET /api/projects/<fake uuid> → 404
```

### S6: Delete cascade behavior
```
1. Create project P
2. Insert a fake project_knowledge row referencing P.id (DB direct)
3. Send a chat with context.projectId = P.id → chat_sessions.project_id = P.id
4. DELETE /api/projects/P.id → 200
5. DB query: project_knowledge for P.id → 0 rows (CASCADE worked)
6. DB query: chat_sessions WHERE session_id = the test session → row still exists
7. DB query: that row's project_id → NULL (ON DELETE SET NULL worked)
```

### S7: Active project clears if archived/deleted elsewhere
```
1. Set active project = P (localStorage)
2. Archive P via API
3. Reload page (refresh active-project-context)
4. provider.activeProjectId → null (not P)
5. localStorage 'biomate-active-project-id' → absent or null
```

## Out of scope (tracked, not tested in this round)

- **S8** cross-session dataset recovery within a project — needs the cold-refresh fetch implementation (separate PR).
- **S9** memory-integration project-scoped path activation — requires generating real episodes/procedures/knowledge to load. Tracked for the memory audit, not this framework test.
- **S10** UI Playwright e2e — covered in source-level wiring tests; deferred to e2e-runner expansion.

## Pass criteria

- All scenarios S1–S7 must pass live on dev.
- Zero log spam during runs (no "relation does not exist", no "ensureDefaultProject failed").
- DB invariants hold after each scenario.
