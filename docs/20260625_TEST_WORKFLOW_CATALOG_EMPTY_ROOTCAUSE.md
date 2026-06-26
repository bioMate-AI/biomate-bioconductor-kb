# Test workflow catalog empty → "workflow-engine" error (2026-06-25)

## Symptom (reported via connector on test.stage-public.biomate.ai)

Connector → `POST /api/chat/stream` authenticates 200 (per-user API key works),
Claude correctly routes intent to workflow id `cyp_ddi_panel`, then **stalls
"fetching the catalog"** and the user sees a generic "workflow-engine" error.

## Reporter's fact that is a RED HERRING

> "Postgres `workflows` table exists but is 0 rows on test and prod."

The workflow **catalog** is **NOT** Postgres. Postgres only backs
`workflow_runs` / run-state (which is why `/api/workflows/runs` works). The
catalog/search reads a **SQLite** file.

## Actual data source (code evidence)

- `backend/lib/galaxy/ai/unified_workflow_search.py:113`
  `DB_PATH = Path(__file__).parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"`
  → in-container `/app/database/galaxy_ai_tools.db`. Tables: `workflows`,
  `workflows_fts`, `workflow_chains`.
- `_get_connection()` (`unified_workflow_search.py:538`) opens a fresh
  `sqlite3.connect()` per query — so replacing the file is picked up with **no
  restart**.

## Root cause

The test container's `/app/database/galaxy_ai_tools.db` was the **20 KB stub**
baked into the image (only `workflows_fts*` shadow tables, **no `workflows`
table**). Galaxy log:

```
[Pass-0] FTS broad fetch failed: no such table: workflows
FTS search failed: no such table: workflows, falling back to LIKE search
[UnifiedWorkflowGeneration] Chain lookup failed: no such table: workflows
[UnifiedWorkflowGeneration] Error: no such table: workflows
```

→ search returns 0 / raises → frontend marks `workflow_failed`
(`frontend/server/routes.ts` ~5821) → user-facing "workflow-engine" error.

**Why it broke now:** the populated catalog (~2632 workflows, 279 MB) is **not
in the image** and **not in a persistent volume** — it is shipped out-of-band
(`scripts/sync_to_dev.sh` step 3 scp's `backend/database/galaxy_ai_tools.db`
→ host → `docker cp` into the container). **Any container recreate reverts to
the stub.** The 2026-06-25 API-key deploys ran `deploy.sh test` twice, which
recreated the Galaxy container and wiped the previously docker-cp'd catalog.
(dev-public's `/app/database/galaxy_ai_tools.db` is ALSO a 20 KB stub as of
2026-06-24 — same drift; it is not a reliable source.)

## Immediate remediation applied (2026-06-25) — test only

Restored the populated catalog from the S3 sync artifact (NOT from dev-public):

1. Source: `s3://biomate-nextflow-work/dev-sync/galaxy_ai_tools.db`
   (279 MB / 292,659,200 bytes, 2026-06-22).
2. Presigned GET (bucket is us-east-1; test instance role can't read it →
   presign bypasses IAM) → `curl` on the test host → verify (`workflows`=2632,
   `workflows_fts`=2632, `cyp_ddi_panel` id 12831 present) → `docker cp` into
   `biomate-galaxy-deploy:/app/database/galaxy_ai_tools.db` →
   `chown galaxy:galaxy` + `chmod 664`.

Verified: search now resolves `cyp_ddi_panel`; `no such table` errors gone.
**This is treating the symptom — it is lost again on the next `deploy.sh`.**

## UPDATE 2026-06-26 — durable fix shipped (single-file bind-mount)

Implemented option-2-style persistence, but learned an important lesson:

- **First attempt (WRONG): named volume over the whole `/app/database`.** It
  persisted the catalog AND Galaxy's `gravity/` process-manager runtime state
  (supervisor sockets/pids). The first recreate worked (fresh volume), but the
  next `deploy.sh` down/up reused the volume with **stale gravity state** →
  Galaxy went **unhealthy** → frontend (depends_on healthy) never started →
  **test outage**. (PR #51 shipped this; corrected by the follow-up.)
- **Correct fix: single-file bind-mount** of just the catalog:
  `/opt/biomate/data/galaxy_ai_tools.db:/app/database/galaxy_ai_tools.db`.
  `/app/database` (gravity, cache, tmp) stays ephemeral image content → clean
  boots; only the catalog persists on the host. Verified: full down/up cycle →
  Galaxy healthy in ~120s, catalog persists (2632 rows).

Seed the host file once per host:
`mkdir -p /opt/biomate/data && curl <presigned s3://biomate-nextflow-work/dev-sync/galaxy_ai_tools.db> -o /opt/biomate/data/galaxy_ai_tools.db && chmod 644`.
If the host file is absent, Docker creates an empty dir at the mount target →
sqlite can't open it → search degrades to no-results, **but Galaxy still boots
healthy** (safe). deploy.sh `down` (no -v) doesn't touch the host file.

## Root-cause fix — for backend (pick one)

1. **Bake `galaxy_ai_tools.db` into the backend image (recommended).** The
   image build pulls the catalog artifact from
   `s3://biomate-nextflow-work/dev-sync/galaxy_ai_tools.db` and `COPY`s it to
   `/app/database/`. Catalog becomes part of the immutable artifact; deploys are
   reproducible; docker-cp drift is eliminated. Cost: ~279 MB image size; the
   reindex pipeline must publish a new artifact + trigger a rebuild on catalog
   change.
2. **Persistent volume / host bind-mount** for `/app/database/galaxy_ai_tools.db`
   that `deploy.sh` does not recreate. Restore once into the volume; container
   mounts it. Survives recreate.
3. **Restore-on-boot** entrypoint that fetches the catalog from S3 if the local
   file is missing/stub. Needs the instance role to have S3 read on the bucket
   (currently 403) — add a bucket policy or use a dedicated artifacts bucket.

## Secondary bug found (same logs) — please also fix

```
[UnifiedWorkflowGeneration] LTM correction fetch failed:
  (psycopg2.OperationalError) invalid sslmode value: "no-verify"
```

A Postgres connection string on test uses `sslmode=no-verify`, which is **not a
valid libpq value** (valid: disable/allow/prefer/require/verify-ca/verify-full).
The LTM (long-term-memory) correction path is broken until this env/DSN is
corrected (likely intended `require` or `prefer`). Non-fatal for routing but
silently disables LTM corrections.
