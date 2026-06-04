# Session log — 2026-06-04 — Boot-time DB migration runner shipped

Closes Gap A from yesterday's `docs/20260603_PHASE1_GAPS_NEXTFLOW_DOWNLOAD_AND_MIGRATION_RUNNER.md`.

## What changed

| Commit | What |
|---|---|
| `3ad8d47ed` | `feat(migrations): boot-time runner + ship migrations into container` |
| `573a43e90` | `fix(migrate): recover already-applied migrations instead of crashing Node boot` (parallel session) |
| `a5c6761b1` | `fix(sync): literal single quotes in echo broke heredoc — replaced with brackets` (parallel session — unblocked the sync) |
| `d5eac6c0d` | `fix(sync): make NF version detect robust against remote pipefail` (parallel session) |

## Architecture

Two layers of defense, both idempotent:

1. **Bash layer** (`scripts/sync_to_dev.sh:apply_postgres_migrations`) — runs
   `psql -f` against `biomate-dev-postgres` for every `.sql` file in
   `frontend/migrations/` during sync, in lex order. Pre-existed; this session
   hardened it to fail loudly when the migrations dir is missing (previously
   silently no-op'd).

2. **Node layer** (`frontend/server/migrate.ts`, new) — runs on every container
   boot before `registerRoutes(app)`. Maintains a `_migrations(filename,
   sha256, applied_at)` tracking table; applies each pending file in its own
   transaction; aborts the process on first hard failure.

The Node layer is the **load-bearing** one — it runs unconditionally on every
container restart, regardless of how the deploy reached the box. The bash
layer is belt-and-suspenders for the sync path.

## "Already applied out-of-band" recovery

The `_migrations` table didn't exist on dev when we shipped this — the dev DB
had 14 tables created by the bash runner's `IF NOT EXISTS` pattern, but no
record of which migration files produced them. On first boot:

- The Node runner sees `_migrations` is empty.
- It tries to apply `0000_add_auth_system.sql` → PG returns `42P07: relation
  "users" already exists`.
- Recovery branch detects `42P07` (also `42710` duplicate object, `42P06`
  duplicate schema), logs "already applied out-of-band", and inserts the row
  into `_migrations` with the file's sha256.
- Subsequent files: same story for `0001`. Then 2 through 13 actually apply
  (some did and some didn't — the recovery handles both transparently).
- Result: 15 rows in `_migrations`, matching 15 `.sql` files on disk.

Boot 2 of this container would log `[migrate] no pending migrations`.

## Dev verification

```
$ ssh ... docker logs biomate-dev-frontend 2>&1 | grep migrate
[migrate] applying 0000_add_auth_system.sql…
[migrate] 0000_add_auth_system.sql already applied out-of-band (PG 42P07: relation "users" already exists). Recording as applied.
[migrate] applying 0001_invite_codes.sql…
[migrate] 0001_invite_codes.sql already applied out-of-band (PG 42P07: relation "invite_codes" already exists). Recording as applied.
[migrate] applying 0002_ux_feedback.sql…
...
[migrate] applied 13 migration(s): 0002_ux_feedback.sql, 0003_telemetry_events.sql, ...

$ psql -c 'SELECT count(*), max(applied_at) FROM _migrations'
 count |              max
-------+-------------------------------
    15 | 2026-06-04 20:33:37.278475+00
```

API smoke (auth-gated, no boot regression):

```
$ curl -X POST https://dev-public.biomate.ai/api/jobs -d '{}'
{"error":"Not authenticated"}  HTTP 401
```

## Files touched

| Path | Change |
|---|---|
| `frontend/server/migrate.ts` | New — boot-time runner |
| `frontend/server/index.ts` | Wire `applyPendingMigrations()` before `registerRoutes()` |
| `frontend/Dockerfile` | `COPY migrations ./migrations` into runtime stage |
| `scripts/sync_to_dev.sh` | Hard-fail (not silent skip) when migrations dir is missing; include `frontend/migrations/` in frontend tar |

## Properties

- **Idempotent**: re-applying = no-op (tracked in `_migrations`).
- **Atomic per-file**: each file applies inside `BEGIN`/`COMMIT`; failure
  rolls back that file but does not corrupt others.
- **Fail-loud**: process exits non-zero on unrecoverable failure; container
  health check goes red; deploy is visibly broken instead of silently broken.
- **Recoverable from drift**: hash drift on already-applied files logs a
  WARNING but does not re-apply (re-applying could be destructive — human
  must write a new migration if the change is intentional).
- **Boot-coupled**: runs on every container start; doesn't need an external
  trigger or CI job.

## What this catches (that bash-only wouldn't)

- A future migration shipped via any deploy mechanism — `sync_to_dev.sh`, a
  manual `docker run`, ECS / Kubernetes rolling restart, etc.
- A future engineer who edits an already-applied migration file in-place — the
  hash drift warning surfaces it.
- The class of bug that produced the 2026-06-03 dev outage: bash sync sets
  `REPO_ROOT` to empty, migrations dir lookup silently fails, schema diverges
  from code, first request to the new endpoint takes Node down. Now the bash
  runner fails loudly AND the Node runner picks up the slack on the next
  container boot regardless.

## Open follow-ups

- **Phase 2** of async-job-queue (methods-report caching) — unblocked, can
  start.
- **Gap B** from yesterday — output ZIP for pipeline runs still broken in
  both endpoints (resolveInvocation chain is Galaxy-only). Pre-existing.
- **Branding sweep (Phase 1.6)** — server field rename + URL path rename for
  the rest of the `nextflow`-suffixed user-facing surfaces. Awaiting go-ahead.
