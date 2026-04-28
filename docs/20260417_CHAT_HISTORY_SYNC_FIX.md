# Chat History Cross-Machine Sync Fix

**Date:** 2026-04-17  
**Branch:** integration/next-phase  
**Commit:** 56260fd67  
**Tests:** 4/4 E2E smoke tests passing

---

## Problem

Two bugs reported:

1. **Sidebar only showed 4 sessions** — regardless of how many chats existed
2. **Different machines kept different history** — sessions were not synced across devices for the same account

---

## Root Causes

### Bug 1 — Hardcoded slice

`frontend/client/src/components/app-sidebar.tsx` line 332:

```typescript
// Before
const recentChats = chatSessions.slice(0, 4).map(...)
// After
const recentChats = chatSessions.slice(0, 20).map(...)
```

### Bug 2 — Galaxy proxy with no backing table

`/api/sessions` was forwarded to the Galaxy Python backend (port 8081) by the Node.js BFF. Galaxy has no `chat_sessions` table — it returned 500 / auth errors for all session operations, silently disabling sync.

Additionally, `chat-history.ts` was sending `x-api-key: <Galaxy API key>` to the Node.js server, but Node.js routes use JWT Bearer tokens (`authenticateToken` middleware). This meant all sync calls were rejected as 401 even after the proxy was fixed.

### Why the migration was missing

`frontend/shared/ltm-schema.ts` defines `sessions` and `conversation_messages` tables (the hierarchical memory system), but these were never migrated to the actual PostgreSQL DB. A separate `chat_sessions` table was needed for the chat sidebar — simpler structure (JSONB blobs) rather than the fully normalized LTM schema.

---

## Fix

### 1. Migration — `frontend/migrations/0006_chat_sessions.sql`

```sql
CREATE TABLE IF NOT EXISTS chat_sessions (
  session_id    TEXT        PRIMARY KEY,
  user_id       TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title         TEXT        NOT NULL DEFAULT 'New Chat',
  status        TEXT        NOT NULL DEFAULT 'active',
  messages      JSONB       NOT NULL DEFAULT '[]',
  workflows     JSONB       NOT NULL DEFAULT '[]',
  datasets      JSONB       NOT NULL DEFAULT '[]',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_activity TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS chat_sessions_user_id_idx ON chat_sessions (user_id);
CREATE INDEX IF NOT EXISTS chat_sessions_last_activity_idx ON chat_sessions (user_id, last_activity DESC);
```

Applied locally:
```bash
PGPASSWORD=biomate_dev_password psql -h localhost -U biomate -d biomate_dev \
  -f frontend/migrations/0006_chat_sessions.sql
```

### 2. Server endpoints — `frontend/server/routes.ts` (lines ~9630–9720)

Replaced the Galaxy proxy with direct PostgreSQL CRUD. All routes use `authenticateToken` middleware and scope queries to `req.user.id`:

| Method | Route | Action |
|--------|-------|--------|
| GET | `/api/sessions?limit=N` | List sessions (max 100), ordered by `last_activity DESC` |
| GET | `/api/sessions/:sessionId` | Get full session with messages/workflows/datasets |
| POST | `/api/sessions` | Create session (UPSERT on conflict) |
| PUT | `/api/sessions/:sessionId` | Update title/status/messages/workflows/datasets |
| DELETE | `/api/sessions/:sessionId` | Delete session |

`frontend/server/db.ts` — exported `pool` for raw SQL:
```typescript
export { schema, ltmSchema, pool };
```

### 3. Client auth — `frontend/client/src/lib/chat-history.ts`

Replaced Galaxy API key auth with JWT Bearer token:

```typescript
private getAuthToken(): string | null {
  for (const key of ['biomate_token', 'biomate-auth-token', 'token']) {
    const v = localStorage.getItem(key);
    if (v && v.startsWith('eyJ')) return v;
  }
  for (const key of ['biomate_token', 'biomate-auth-token', 'token']) {
    const v = sessionStorage.getItem(key);
    if (v && v.startsWith('eyJ')) return v;
  }
  return null;
}
private authHeaders(): Record<string, string> {
  const token = this.getAuthToken();
  return {
    'Content-Type': 'application/json',
    ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
  };
}
```

All 4 fetch sites in `chat-history.ts` (fetchSessionDetail, deleteSession, syncSessionToBackend ×2) updated from `'x-api-key': API_KEY` to `...this.authHeaders()`.

Added `fetchSessionDetail(id)` — hydrates full messages from backend when a session in localStorage has empty messages (cross-machine restore scenario).

### 4. App-level restore — `frontend/client/src/App.tsx`

`handleChatSelect` made async to fetch full session detail when needed:

```typescript
const handleChatSelect = async (chatId: string) => {
  const local = chatHistoryService.getSession(chatId)
  const session = (!local || local.messages.length === 0)
    ? await chatHistoryService.fetchSessionDetail(chatId)
    : local
  if (session) {
    setCurrentChatSession(session)
    setLocation('/')
  }
}
```

---

## Test Results

`frontend/e2e/chat-history-smoke.e2e.ts` — 4/4 passing (26s):

| Test | Result |
|------|--------|
| sessions API returns 200 for authenticated user | PASS |
| session detail endpoint returns messages | PASS |
| cross-machine: clearing localStorage restores sessions from backend | PASS |
| new message is synced to backend and retrievable | PASS |

Run with:
```bash
npx playwright test e2e/chat-history-smoke.e2e.ts --reporter=line
```

---

## Deployment Note

The migration `0006_chat_sessions.sql` must be applied to the production PostgreSQL database before deploying. The Node.js server will 500 on `/api/sessions` if the table doesn't exist.

```bash
psql "$DATABASE_URL" -f frontend/migrations/0006_chat_sessions.sql
```

---

## Architecture Note — LTM Schema vs Chat Sessions

`frontend/shared/ltm-schema.ts` defines a fully normalized `sessions` + `conversation_messages` schema (part of the P2/P3 long-term memory system). Those tables have **not** been migrated and are separate from this fix. The `chat_sessions` table added here is a simpler JSONB-based store specifically for sidebar history sync. If LTM is activated in future, a migration plan will be needed to reconcile the two schemas.
