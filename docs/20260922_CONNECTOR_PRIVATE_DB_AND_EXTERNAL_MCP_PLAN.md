# Connector Build Plan — Private DB Connect + External MCP Connect

**Date:** 2026-09-22
**Status:** Design / scoping (no code written)
**Author:** investigation session

## 0. TL;DR

BioMate's Connectors panel implies two capabilities it does **not** actually have:

1. **Private DB connect** — no code path takes a user's host/port/creds and connects to
   *their* database. Every "database" in the connector list is a **public-catalog REST
   query** (`query_database` → UniProt/PDB/ChEMBL/etc. in
   `backend/lib/galaxy/ai/ai_assistant.py:6335`). There is no `pg`/`mysql` client that
   ever opens a socket to a user-supplied host.
2. **External MCP connect** — BioMate can *expose* an MCP server
   (`backend/lib/mcp/biomate_mcp_server.py`, consumed by Claude/ChatGPT) but cannot
   *consume* a user's own MCP server. The only client code is dead:
   `backend/tools/biomate_ai_tools/mcp_client.py` is hard-wired to two servers
   (AlphaFold/Chai-1) and is never imported anywhere in the running app.

Both are high value for on-prem/hospital customers. This doc scopes what it takes to build
each, grounded in the **existing** architecture so they fit in, not a greenfield.

The good news: **most of the plumbing already exists.**
- A per-user encrypted credential store is already built and wired
  (`backend/lib/galaxy/webapps/galaxy/api/credentials_api.py`, backed by Galaxy Vault /
  Fernet-AES, plus a Node AES-256-GCM field encryptor `frontend/server/field-encrypt.ts`).
- A residency/scope model (`cloud` / `on-prem` / `mounted` / `local`, Account/Project/Request)
  is already a first-class UI property (`frontend/client/src/components/connector-residency.tsx`).
- A tool-dispatch spine (`query_database` case at `frontend/server/routes.ts:884`, Galaxy
  `/api/databases/query` at `backend/.../ai_assistant.py:3016`, MCP enum in
  `backend/lib/mcp/tools_manifest.py`) is where a new read-only query surface slots in.

---

## 1. How the existing "database" surface is wired (grounding)

Trace of a public DB query today, end to end:

| Layer | File:line | Role |
|---|---|---|
| Registry (source of truth) | `backend/lib/galaxy/ai/data_sources.py:59-161` | Declares every source once + which surfaces reach it (`federation`/`single_source`/`mcp`/`galaxy_tool`). |
| Chat tool-dispatch (Node) | `frontend/server/routes.ts:884` | `case "query_database": post("/api/databases/query", …)` — the LLM tool the agent calls. |
| Node proxy | `frontend/server/routes.ts:8442` | `POST /api/databases/query` → forwards to Galaxy `${GALAXY_URL}/api/databases/query`. |
| Node data-source catalog proxy | `frontend/server/routes.ts:8425` | `GET /api/data_sources` → Galaxy registry (self-awareness catalog). |
| Galaxy route | `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:3016` | `query_biological_database()` — federated fan-out or single-source. |
| Single-source dispatcher | `backend/lib/galaxy/ai/ai_assistant.py:6335` | `query_database(database, query, operation)` → `handlers = {…}` dict of `_query_*` REST methods (`_query_uniprot` etc., lines 5828-6334). |
| MCP enum (external clients) | `backend/lib/mcp/tools_manifest.py` (`query_database` schema) + `backend/lib/mcp/biomate_mcp_server.py:965` | The enum ChatGPT/Claude connectors see. Kept "in lock-step with `ai_assistant.query_database` handlers." |

**Key insight:** every "database" here is a hardcoded public REST endpoint. There is no
per-user connection object, no driver, no socket to a user host. The new private-DB
capability is a **new database backend behind the same `query_database` dispatch spine**,
plus a per-user connection record it resolves against.

### Credential storage that already exists (do NOT invent plaintext)

Two proven patterns are already in the codebase — reuse one, don't build a third:

- **Galaxy Vault store (backend, preferred for backend-executed queries)** —
  `backend/lib/galaxy/webapps/galaxy/api/credentials_api.py`:
  - `POST /api/users/credentials` `{tool, data}` → `_store_credential()` writes to
    `UserVaultWrapper` at `biomate/credentials/<tool_id>` (`credentials_api.py:49-65`).
  - Vault is Fernet-AES at rest (`backend/lib/galaxy/security/vault.py:136-171`,
    `DatabaseVault` uses `MultiFernet`); falls back to `user.preferences` JSON only if vault
    is unconfigured.
  - `get_effective_credential(trans, tool_id)` (`credentials_api.py:112-160`) returns
    `(data, source)` with `source ∈ {user, biomate, none}` — the exact resolution hook a
    query executor calls.
  - Gated by `LICENSE_REGISTRY` (`backend/lib/galaxy/webapps/galaxy/api/license_registry.py:17`)
    — `store_credential` rejects unknown tool ids (`credentials_api.py:250`). A private-DB
    connection is NOT a license tool, so it needs its **own** record type (see §2.3), not a
    `LICENSE_REGISTRY` entry.
- **Node AES-256-GCM field encryptor (frontend, used for LLM keys)** —
  `frontend/server/field-encrypt.ts:43` `encryptField()` / `:61` `decryptField()`, format
  `<iv>:<tag>:<ciphertext>`, key from `FIELD_ENCRYPTION_SECRET` (SHA-256 → 32 bytes).
  Precedent: `users.llmApiKeys` JSONB column (`frontend/shared/schema.ts:62`,
  migration `frontend/migrations/0019_user_llm_api_keys.sql`), GET returns only booleans
  (`routes.ts:7150`), PATCH encrypts before write (`routes.ts:7168-7203`), decrypt in-memory
  per request (`routes.ts:6132-6149`).

**Known deficit to NOT copy:** instrument credentials are stored **plaintext**
(`frontend/shared/schema.ts:1544-1546` `api_key`/`oauth_token` TEXT; written raw at
`routes.ts:16054`). Private-DB creds must not follow the instrument pattern.

### Residency/scope UI that already exists

- `frontend/client/src/components/connector-residency.tsx` — `Residency` type
  (`cloud|onprem|mount|local|prompt`), `ResidencyBadge`, `ScopeSelector`
  (Account/Project/Request), `DeclaredFacts`. §0.9 "no blank residency" honesty rule.
- `frontend/client/src/components/connectors-dialog.tsx` — the Connectors modal
  (Databases tab `DB_RAW`:62, AI & Platforms tab:165; all public rows stamped
  `residency: 'cloud'` at :141). Opened from `app-sidebar.tsx:173`.
- Writable config today lives in `frontend/client/src/components/settings-dialog.tsx`
  — the S3-credentials form (`useS3Credentials` hook :257-344, form :685-807, "Test
  Connection" verify at :315) is the **exact template** for a DB-connection form.

---

## 2. Capability A — Private DB Connect

**Goal:** a user (esp. on-prem/hospital) registers a connection to *their* Postgres/MySQL,
and BioMate's chat/agent can run **read-only** queries against it, with the DB staying inside
the customer network (residency = `onprem`).

### 2.1 Flow (target)

```
Settings → "Private Databases" tab
  → user enters host/port/db/user/password (or a connection URI) + a friendly name
  → "Test Connection" (backend opens a short-lived read-only conn, runs `SELECT 1`, lists schemas)
  → Save → creds encrypted at rest, connection record created (per-user, optional per-project scope)

Chat: "how many patients in my clinical DB have EGFR mutations?"
  → LLM calls query_database(database="userdb:<conn_id>", query="<intent or SQL>", operation="read")
  → backend resolves conn_id → decrypts creds → opens pooled read-only conn
  → executes (guarded: read-only role, statement timeout, row cap) → returns rows/summary
```

### 2.2 Where it plugs into existing code

- **New DB backend behind the same dispatch spine.** Add a `userdb` prefix branch to the
  `query_database` dispatcher:
  - Galaxy route `backend/.../ai_assistant.py:3016` `query_biological_database()` — before the
    public-source path, detect `database.startswith("userdb:")` and route to a new
    `private_db.execute(trans, conn_id, query, operation)`.
  - Node proxy already forwards `database` verbatim (`routes.ts:8442`), and the chat tool case
    (`routes.ts:884`) already passes `database`/`query`/`operation` — **no change needed**
    there beyond documenting the `userdb:<id>` convention in the tool description.
  - MCP enum: `query_database`'s `database` field is a fixed enum today
    (`tools_manifest.py`). For MVP, do **not** expose user DBs to external MCP clients
    (ChatGPT/Claude) — keep private DBs to the authenticated first-party chat only. (Revisit
    in full scope with per-connection ACL.)
- **Connection registry + creds:** reuse `credentials_api.py`'s Vault store, but as a new
  record type. Two options:
  - **(chosen)** New backend module `backend/lib/galaxy/ai/private_db.py` +
    `POST/GET/DELETE /api/users/db-connections` in a new
    `backend/lib/galaxy/webapps/galaxy/api/private_db_api.py`. Store the **connection
    metadata** (name, host, port, db, user, driver, scope) as one Vault secret per connection
    at `biomate/db-connections/<conn_id>`, with the password inside the same encrypted blob.
    This mirrors `_store_credential`/`_get_credential` exactly (`credentials_api.py:49-87`) but
    is not `LICENSE_REGISTRY`-gated.
  - (alt) Node-side table `user_db_connections` with `encryptField()` on the password
    (mirrors the LLM-keys pattern). Rejected for MVP because the **query executor runs in the
    Galaxy backend** (where the driver + pooling live), so keeping creds in the Galaxy Vault
    avoids a second decrypt hop across the Node↔Galaxy boundary.
- **UI:** new "Private Databases" tab in `settings-dialog.tsx`, cloning `useS3Credentials`
  (:257-344) → `useDbConnections`, and the S3 card/verify form (:685-807) → host/port/db/
  user/password fields + "Test Connection" (`POST /api/users/db-connections/verify`). Stamp
  residency `onprem` (default) on the connector row via the existing `ResidencyBadge`.

### 2.3 Concrete build items

**Drivers / deps (already present — no new heavy deps for MVP):**
- Backend already has `psycopg2-binary` and `sqlalchemy`
  (`backend/lib/galaxy/dependencies/conditional-requirements.txt:2`,
  `pinned-requirements.txt:190,232`). Postgres MVP needs **zero** new deps.
- MySQL (full scope) adds `PyMySQL` or `mysqlclient`.
- Use SQLAlchemy `create_engine` with `pool_size`/`max_overflow`/`pool_pre_ping` and
  `pool_recycle` — one engine cached per `conn_id`, lazily created, TTL-evicted.

**Security (the hard part — these handle live PHI/clinical DBs):**
1. **Read-only enforcement, defense in depth:**
   - Instruct users to supply a **read-only DB role** (documented in the UI form).
   - Server-side: open the connection with `default_transaction_read_only=on` (Postgres
     `options='-c default_transaction_read_only=on'`) / `SET SESSION TRANSACTION READ ONLY`.
   - Statement allow-list: reject anything that isn't a single `SELECT`/`WITH…SELECT` via a
     SQL parser (`sqlglot` — small dep — or `sqlparse`); block multiple statements, DML/DDL,
     `COPY`, `pg_read_file`, `dblink`, `\!`, comments-with-semicolon smuggling.
   - Wrap in an aborting transaction (`BEGIN READ ONLY … ROLLBACK`) so even a bypass can't
     persist.
2. **Injection safety:** when the LLM produces SQL, treat it as untrusted — parse + validate
   (above), never string-concatenate identifiers; if the flow is NL→SQL, generate parameterized
   SQL and bind values.
3. **Resource caps:** `statement_timeout` (e.g. 15s), hard `LIMIT` injection / row cap
   (e.g. 10k rows), max result bytes; kill the connection on breach.
4. **Encryption at rest:** creds only in Galaxy Vault (Fernet-AES) — never logged, never in
   error strings, never returned by GET (return masked host + booleans, like the S3 GET at
   `routes.ts:7271`).
5. **Least privilege / residency:** for true on-prem, the *Galaxy worker that opens the socket*
   must run inside the customer network (the DB "stays in the hospital network"). MVP works for
   a cloud-reachable DB; on-prem residency requires the query executor to run on a customer-side
   agent — call this out as the on-prem deployment story, not a code change (see §4).
6. **Scoping/permissions:** connection record carries `owner_user_id` and optional
   `project_id`; resolver refuses a `conn_id` not owned by / shared to the requesting user
   (mirror the ownership 404-not-403 pattern already enforced elsewhere). Reuse the
   Account/Project/Request scope model from `connector-residency.tsx`.

**Read-only query surface exposed to chat/MCP:**
- New `private_db.execute(trans, conn_id, query, operation)` returning
  `{success, columns, rows, row_count, truncated}` — the same envelope shape `_query_*`
  handlers return so the chat renderer needs no special-casing.
- Register `userdb:<id>` as a recognized `database` value; extend the `query_database` tool
  **description** (not enum) so the LLM knows to pass a user connection id. Expose the user's
  connections to the LLM via a small context block (like the data-source catalog block at
  `galaxy-assistant.ts:9403`) listing `{conn_id, name, driver, tables?}`.

**Tests:**
- Backend unit: `backend/tests/test_private_db.py` — SQL validator (accepts `SELECT`, rejects
  `DROP`/`; DELETE`/multi-statement/`COPY`), creds round-trip through Vault, resolver ownership
  check, row-cap + timeout enforcement (mock engine).
- Integration: spin a throwaway Postgres (docker `postgres:16`, seed 1 table), register a
  connection via the API, run a `SELECT`, assert rows; assert a `DROP TABLE` is rejected and
  the table still exists; assert cross-user `conn_id` → 404.
- E2E (dev, live, fixture `lifeifei163361@163.com`): Settings → add a throwaway Postgres →
  Test Connection green → chat "count rows in table X" → assert an answer with the count.
  Follow the E2E discipline in CLAUDE.md (one login, one project, 90s LLM timeout).

### 2.4 MVP vs full

| | MVP (first slice) | Full |
|---|---|---|
| Drivers | Postgres only | + MySQL, SQL Server, Snowflake, BigQuery |
| Query mode | user/LLM supplies read-only SQL | NL→SQL with schema introspection + few-shot |
| Residency | cloud-reachable DB | on-prem query agent (DB never leaves network) |
| Scope | per-user | per-project sharing, RBAC |
| MCP exposure | first-party chat only | per-connection ACL for external MCP |

**Smallest valuable slice:** one Postgres connection, user supplies a read-only SQL string,
backend validates (single SELECT) + caps rows + returns a table into chat. This alone unblocks
"let BioMate read my results DB."

### 2.5 Effort / risk

- **Effort:** MVP ~4–6 dev-days (connection API + Vault record + SQLAlchemy executor + SQL
  validator + Settings tab + tests). Full (MySQL, NL→SQL, on-prem agent) multi-week.
- **Risk (high — security):** an under-guarded executor on a clinical DB is a data-exfil /
  destructive-query hazard. The read-only enforcement (role + `READ ONLY` txn + SELECT-only
  parser + rollback) must all land in MVP; do not ship "we'll add the parser later."
- **Risk (medium):** connection pooling leaks / long-lived sockets to customer DBs — use
  `pool_pre_ping`, short `pool_recycle`, TTL-evict idle engines.

---

## 3. Capability B — External MCP Connect

**Goal:** a user registers *their own* MCP server (SSE/HTTP URL, or a local stdio command),
BioMate lists its tools and lets the agent call them, so a customer's proprietary tools show up
inside BioMate chat.

### 3.1 Dead code + SDK decision

- Existing `backend/tools/biomate_ai_tools/mcp_client.py` is a hand-rolled JSON-RPC-over-stdio
  caller hard-wired to `alphafold`/`chai1` (:13-23) and **never imported** by the app. Do
  **not** build on it — it has no protocol handshake, no tool discovery, no SSE/HTTP transport,
  no session lifecycle.
- **Use the official MCP Python SDK** (`mcp` package: `ClientSession`, `stdio_client`,
  `sse_client`/`streamablehttp_client`). It is **not currently installed** (verified: no `mcp`
  in `backend/lib/galaxy/dependencies/*.txt`; the `from mcp import tools_manifest` in tests
  refers to the **local** `backend/lib/mcp` package, not the SDK). Adding the SDK is a new dep
  — pin it, and confirm Python-3.9 compat on dev (the SDK targets 3.10+; if 3.9 is a blocker,
  implement a thin HTTP/SSE JSON-RPC client for the **remote** transport MVP and defer stdio).

### 3.2 Where it plugs in

BioMate's chat agent already has a tool-dispatch loop (Node `routes.ts` `case "…"` spine,
33 cases; tool set assembled around `galaxy-assistant.ts`). Registering a user MCP means:
its tools become **additional dynamic tools** the LLM can call, dispatched by proxying to the
user's MCP session.

- **Registration + storage:** new `POST/GET/DELETE /api/users/mcp-servers`
  (Node route + Galaxy Vault record `biomate/mcp-servers/<server_id>`, same pattern as
  §2.2). Record: `{name, transport: 'sse'|'http'|'stdio', url?, command?, args?, headers/auth?,
  scope}`. Auth token encrypted at rest.
- **Client + discovery:** new `backend/lib/galaxy/ai/user_mcp.py`:
  `list_tools(server_id)` opens an SDK `ClientSession`, does `initialize` + `tools/list`,
  caches the tool schemas (name/description/inputSchema). `call_tool(server_id, tool, args)`
  opens a session and dispatches `tools/call`.
- **Exposure to the LLM:** at chat-tool-assembly time, append the user's registered MCP tools
  (namespaced, e.g. `mcp__<server>__<tool>`) to the tool list handed to the model — the same
  place the static tool set is built for `galaxy-assistant.ts`. Dispatch: a new
  `case` (or a prefix match on `mcp__`) in the `routes.ts` dispatch spine → proxy to
  `user_mcp.call_tool`. This mirrors how *this very harness* surfaces MCP tools via
  namespaced `mcp__server__tool` names.
- **Routing/tool-search:** MVP = expose the user's MCP tools directly to the model (small N).
  Full = index their descriptions into the existing tool search
  (`UnifiedToolSearch`/`VectorToolSearch`, `backend/lib/galaxy/ai/unified_tool_search.py`) so
  they compete with the 12k built-in tools by relevance.

### 3.3 Security (arbitrary user server/command)

- **Remote (SSE/HTTP) first — lower risk:** it's an outbound HTTPS call to a URL the user owns.
  Guard with: URL allow-scheme (https only in prod), **SSRF protection** (block
  RFC-1918/link-local/metadata `169.254.169.254` unless the deployment is on-prem and explicitly
  allows private ranges), per-call timeout, response-size cap, and store auth headers encrypted.
- **stdio (local command) — high risk, defer / sandbox:** launching an arbitrary user-supplied
  command on the BioMate host is RCE-by-design. Only allow in **on-prem/self-hosted**
  deployments where the operator owns the box; in multi-tenant cloud, **disable stdio** (feature
  flag, like `BIOMATE_ENABLE_IT`). When allowed, run under a restricted user, no network unless
  needed, resource limits (cgroup/ulimit), and never interpolate user text into the command.
- **Tool-call safety:** treat user-MCP tool outputs as untrusted content in the LLM context
  (prompt-injection surface). Do not auto-execute side-effectful MCP tools without the same
  confirm-gate the workflow runner uses.
- **Per-user isolation:** a `server_id` resolves only for its owner/shared-project;
  sessions are per-request, not shared across users.

### 3.4 Build items + tests

- Deps: `mcp` (SDK) pinned; verify 3.9 or gate stdio behind 3.10+.
- Backend: `user_mcp.py` (list/call), `private... ` — sorry, `user_mcp_api.py` routes,
  Vault record, dynamic-tool injection into the chat tool set.
- UI: "MCP Servers" tab in `settings-dialog.tsx` (URL + auth token + "List tools" verify that
  shows discovered tool names), residency `cloud` (remote) or `local` (stdio) via
  `ResidencyBadge`.
- Tests:
  - Unit: registration round-trip (Vault), SSRF blocklist, tool-name namespacing, dispatch
    routing for `mcp__*`.
  - Integration: run a **throwaway reference MCP server** (the SDK ships an `everything`/echo
    server, or reuse the in-repo `biomate_mcp_server.py` against a mock backend as the
    sandbox tests already do — `backend/tests/test_connector_sandbox.py:407-465` spawns a real
    MCP subprocess over stdio and drives `initialize`/`tools/list`/`tools/call`; that harness is
    a ready template for the *client* side too). Assert list+call round-trips.
  - E2E: register an HTTP/SSE echo MCP → chat asks to use it → assert the tool is invoked.

### 3.5 MVP vs full / effort / risk

| | MVP (first slice) | Full |
|---|---|---|
| Transport | remote SSE/HTTP only | + stdio (on-prem, sandboxed) |
| Discovery | list tools, expose all to LLM | index into vector tool-search, relevance-ranked |
| Auth | static bearer/header | OAuth flows per MCP spec |
| Exposure | first-party chat | also surface in the biomate MCP server we expose (chaining) |

**Smallest valuable slice:** register one **remote SSE/HTTP** MCP server, list its tools, let
the agent call them in chat. Skips the RCE surface of stdio entirely.

- **Effort:** MVP ~4–5 dev-days (SDK client + registration API + Vault record + dynamic tool
  injection + Settings tab + tests). Full (stdio sandbox, OAuth, vector indexing) multi-week.
- **Risk (high):** stdio = arbitrary code execution — keep it out of MVP / multi-tenant.
  SSRF on remote MCP registration — must land the private-range blocklist in MVP.
- **Risk (medium):** a slow/hostile MCP server stalling the chat loop — per-call timeouts and a
  circuit breaker.

---

## 4. On-prem residency note (applies to both)

For a genuine "data stays in the hospital network" story, the component that opens the socket
(the DB connection in §2, the stdio MCP in §3) must run **on a customer-side agent**, not on
BioMate cloud. That is a **deployment** capability (a BioMate worker / connector agent deployed
inside the customer VPC that the cloud control plane dispatches queries to), not just the code
above. The code above delivers the capability for a **cloud-reachable** DB / **remote** MCP
today; the on-prem agent is the follow-on that makes residency `onprem` literally true. The
residency model (`connector-residency.tsx`) and scope model already exist to represent it in the
UI honestly — do not stamp `onprem` on a row whose query actually runs in the cloud.

---

## 5. Recommended sequencing

1. **Private DB MVP (Postgres, read-only SQL, cloud-reachable)** — highest customer pull,
   zero new heavy deps, reuses Vault + Settings-S3-form template + `query_database` spine.
2. **External MCP MVP (remote SSE/HTTP only)** — reuses the same Vault registration pattern;
   adds the `mcp` SDK; sandbox-free because stdio is deferred.
3. **On-prem query agent** — the deployment piece that makes residency real for both.
4. **Full scope** — MySQL/NL→SQL, stdio-sandboxed MCP + OAuth + vector-indexed tool routing.

## 6. File-touch summary (for the executing session)

**Private DB:**
- `backend/lib/galaxy/ai/private_db.py` (new) — SQLAlchemy engine cache, SQL validator, executor.
- `backend/lib/galaxy/webapps/galaxy/api/private_db_api.py` (new) — register/verify/list/delete,
  Vault record (pattern from `credentials_api.py`).
- `backend/.../api/ai_assistant.py:3016` — route `userdb:<id>` in `query_biological_database()`.
- `frontend/server/routes.ts` — proxy `/api/users/db-connections*` (pattern from `:7215-7279`);
  `case "query_database"` (`:884`) description note re `userdb:`.
- `frontend/client/src/components/settings-dialog.tsx` — "Private Databases" tab (clone
  `useS3Credentials` :257-344 + form :685-807).
- `backend/tests/test_private_db.py` (new) + integration + e2e.

**External MCP:**
- `backend/lib/galaxy/ai/user_mcp.py` (new) — SDK `ClientSession` list/call.
- `backend/lib/galaxy/webapps/galaxy/api/user_mcp_api.py` (new) — register/verify/list/delete + Vault.
- chat tool-set assembly (around `frontend/server/galaxy-assistant.ts` + `routes.ts` dispatch
  spine) — inject `mcp__<server>__<tool>` dynamic tools + dispatch.
- `frontend/client/src/components/settings-dialog.tsx` — "MCP Servers" tab.
- `backend/lib/galaxy/dependencies/*.txt` — add pinned `mcp` SDK.
- `backend/tests/test_user_mcp.py` (new) — reuse the subprocess-MCP harness from
  `backend/tests/test_connector_sandbox.py:407-465` for the client round-trip.
