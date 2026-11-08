# Private-DB + External-MCP: FULLY FIXED & verified end-to-end (2026-09-23)

> **STATUS: RESOLVED.** Full CRUD round-trips for a real user on dev:
> MCP register→list (`owner=1`) ✅, DB create→list ✅, SSRF→400, db verify→200,
> unauthenticated→401. The four-layer fix chain below is complete and verified.
>
> **Fix chain (all committed + synced):**
> 1. **Route collision** — moved `/api/users/{db-connections,mcp-servers,mcp-tools}` → `/api/biomate/*` (collided with Galaxy `/api/users/{user_id}`). `eacb3f36`.
> 2. **Proxy status mapping** — Node read `error.response?.status`; proxy throws `.status_code`. `bb0ae978`.
> 3. **Master-key poison (the deep one)** — provisioning reuse query could hand a user Galaxy's `master_api_key` → auth as `BootstrapAdminUser` (id 0) → no per-user store. Excluded the master key from reuse (`9dd7143e`) + re-provisioned the fixture to its real key (WHOAMI → 200 real user).
> 4. **Vault not configured on dev** — `private_db.create_connection` called Vault directly (`NullVault` → `InvalidVaultConfigException` → 500) while MCP already fell back to preferences. Added the same Vault→preferences fallback to private_db (`6728256a`).
>
> Also hit + worked around a **deploy race**: a concurrent session's sync overwrote the dev frontend without these routes; forced a frontend rebuild (`335425a2`).

---

## (historical) Private-DB + External-MCP: authed-500 FIXED; persistence layer still open

**Date:** 2026-09-23
**Context:** #1 from the "what's left" list — the private-DB/MCP connectors were deployed but returned 500 for logged-in users.

## FIXED (committed + synced + verified on dev)

### 1. Route collision → authed 500 (`bb0ae978`/`eacb3f36`)
The 2-segment routes `GET/POST /api/users/db-connections`, `/api/users/mcp-servers`, `/api/users/mcp-tools` collided with Galaxy's `GET/PUT/DELETE /api/users/{user_id}` (`users.py:651`). FastAPI decodes `user_id` as a `DecodedDatabaseIdField`; `"db-connections"` / `"mcp-servers"` fail to decode → **400** (surfaced by the Node proxy as 500). `walk_controller_modules` registers via **unsorted `os.listdir`**, so `credentials_api` won the race while these lost — a real, non-deterministic latent bug.
**Fix:** moved the resource group to the collision-free `/api/biomate/{db-connections,mcp-servers,mcp-tools}` prefix (no top-level `/api/{param}` route exists). Frontend client paths (`/api/mcp/servers`, `/api/databases/connections`) are the Node routes — unchanged.

### 2. Proxy dropped Galaxy 4xx status (`bb0ae978`)
`GalaxyAPIProxy`'s interceptor throws `galaxyError` with `.status_code`/`.detail`, but 15 Node routes read `error.response?.status` → every Galaxy 4xx became a 500. Fixed all 15 to read `error.status_code ?? error.response?.status ?? 500`.

### Verified live on dev after the fixes
- `GET /api/mcp/servers` authed → **200** `{"servers":[]}` (was 500)
- `GET /api/databases/connections` authed → **200** (was 500)
- `POST /api/mcp/servers` register → **200** (full record)
- `POST /api/databases/connections/verify` → **200** `{ok:false, psycopg2 connection refused}` (real executor runs)
- SSRF `http://169.254.169.254/` → **400** (was 500; still blocked either way)
- unauthenticated → **401**

## STILL OPEN — persistence layer (needs the Galaxy traceback to root-cause)

Two symptoms found by end-to-end testing after the routing fix:

1. **`POST /api/databases/connections` (create) → 500** "Internal Server Error".
   - `private_db.create_connection` (`private_db.py:280`) calls `vault.write_secret(...)` with **no try/except** (its read path `_load_index:209` *does* catch). `registry._write_secret` and `credentials_api._store_credential` both wrap the vault write. So a Vault write error propagates → 500.
2. **`POST /api/mcp/servers` returns 200 but the server never appears in the subsequent `GET` list** (`{"servers":[]}`, both immediately and on repeat).
   - Register writes record + index via `registry._write_secret`; `list()` reads an empty index in the next request. The vault-success path does **not** commit (only the preferences fallback commits, `registry.py:98`); dev runs gunicorn with 4 workers, so an uncommitted write in the POST worker isn't visible to the GET worker.
3. **`owner_user_id: 0`** on the registered record — `getattr(trans.user, "id", None)` resolved to **0** for the userProxy-mapped fixture user. Unresolved; may indicate the userProxy→Galaxy user context is a synthetic/id-0 user whose Vault/preferences don't persist normally. NOTE: `credentials_api` uses the same `trans.user` and its GET returns 200, but a credentials store→read round-trip was **never actually verified** — it may share this latent non-persistence.

### ROOT CAUSE CONFIRMED (2026-09-23, via SSH-over-SSM Galaxy traceback)
`trans.user` for these userProxy calls is a **`BootstrapAdminUser` (id 0)**, NOT the real user. The Galaxy log on a create shows:
```
File "/app/lib/galaxy/webapps/galaxy/api/users.py", line 662, in show
  ...serialize... BootstrapAdminUser...
AttributeError: 'BootstrapAdminUser' object has no attribute 'preferred_object_store_id'
```
plus the earlier `credential_map from vault: {...real values...}` proves **Vault is healthy**. So the persistence failure is NOT Vault and NOT a commit gap — it is that `userProxy(req)` calls Galaxy with the **master/bootstrap key** because the fixture user has **no provisioned per-user `galaxyApiKey`** (`req.user.galaxyApiKey` is null → `forUser(undefined)` → Galaxy resolves the master key → `BootstrapAdminUser`). Every write is therefore scoped to the synthetic bootstrap admin (id 0), which has no persistent per-user Vault/preferences store → writes "succeed" but never round-trip, and `owner_user_id=0`.

This is the CLAUDE.md credential-architecture case: *"If a feature fails because a user lacks a Galaxy account → fix the provisioning flow, don't skip Galaxy account operations."* It affects `credentials_api` identically (its store→read round-trip was never actually verified — it likely also writes to the bootstrap admin). Related prior incident: the "provision master-key poison" note in the Input-HDA pipeline work.

**Proper fix (architectural, not a patch):** ensure the user has a provisioned real Galaxy user + `galaxyApiKey` so `userProxy` authenticates as that user (not the master key). Then per-user Vault/preferences persist and `owner_user_id` is the real id. This is the same provisioning path the HDA-input work fixed; verify it runs for this user/flow. Only after provisioning is correct do the (secondary) create-path error-handling + commit hardening matter.

Also surfaced: a **pre-existing Galaxy bug** — serializing a `BootstrapAdminUser` via `GET /api/users/{user_id}` throws `AttributeError: preferred_object_store_id` (500). Independent of our feature but worth noting.

### Why not patched yet (discipline)
CLAUDE.md: "no fix without an identified cause." The clean fix for #1 (wrap the vault write) and #2 (commit after vault write) is understood, BUT #3 (`owner_user_id: 0`) suggests the deeper cause may be the user context itself — in which case commit/fallback patches would produce a false "no crash" without real persistence. Confirming needs the Galaxy backend traceback for the create-500 + a check of what `trans.user` resolves to for a userProxy call.

### Blocker on getting the traceback
`aws ssm send-command` with `AWS-RunShellCommand` returns `InvalidDocument` for this identity; the sync path uses **SSH-over-SSM sessions** (`AWS-StartSSHSession`), not RunCommand. Next step: SSH over SSM into `i-06696b0d91f4346e0` and `docker logs biomate-galaxy-dev` around a create-500, plus log `trans.user.id` / vault availability, then apply the correct fix (resilient write + commit, and/or the user-context fix) and re-run the end-to-end lifecycle.

## Net
The **reported #1 bug (authed-500) is fixed and verified** — the feature is reachable with correct auth/routing/status. Full **CRUD persistence** is a distinct, deeper bug (Vault write commit + create-path error handling + the `owner_user_id:0` user-context question) that needs the backend traceback before a root-cause fix.
