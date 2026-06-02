# Async Job Queue — Design Document

**Date:** 2026-06-02
**Owner:** yzhang
**Status:** Draft (pre-sign-off)
**Scope:** A shared subsystem for long-running artifact-producing tasks (multi-GB output bundles, AI-generated reports, document exports). Replaces the current pattern of synchronous-HTTP + per-feature ad-hoc state.
**Triggering context:** After-run panel PM review (`docs/20260601_AFTERRUN_PANEL_DESIGN_REVIEW.md`) flagged that the proposed "Download all as ZIP" and "Methods report" UX both depend on operations that can take minutes; sync streaming + per-feature polling don't compose.

---

## 1. Problem

Today BioMate has at least four long-running operations that produce a single artifact for the user to consume:

| Operation | Where | Pattern today | Pain |
|---|---|---|---|
| Download-all-as-ZIP | `routes.ts:7452` `/api/invocations/:id/download-all` | Sync stream — Express + `archiver` pipes for the duration | Multi-GB ZIPs hold HTTP connection 5-30 min; nginx/ALB drops it; no resume; no progress |
| Methods report generation | `routes.ts:4257` `/api/invocations/:id/methods-report` | Sync — first request triggers a 20s Claude call; subsequent requests re-do it | Frontend `fetch()` times out; tab silently hides; double-click → double Claude call |
| Reproducibility bundle | `nextflow_executor.py:6681` `/api/nextflow/runs/:id/reproducibility` | Sync — globs work-dir, packs, returns | Same scale problem as ZIP, smaller bundles today |
| Findings analysis | `routes.ts:10480` `/api/workflows/runs/:id/findings` | Async-ish — backend kicks off Claude in background, frontend polls every 5s indefinitely | No proper job tracking; no give-up; can't cancel; no shared infra for the next async feature |

Future (already in flight or sketched):
- Server-side DOCX/PDF export of the comprehensive after-run report
- Long-running benchmark / sweep runs that produce summary artifacts
- IND-report generation (existing module already does similar work inside its own surface)

### What's wrong with the status quo

1. **Connection-bound long requests** — when `archiver` is streaming a 100 GB ZIP and nginx drops the connection at 40 GB, the user starts over from zero.
2. **No progress** — for the user there's no feedback during preparation; for support there's no observability into what's running.
3. **Double-click hazard** — clicking "Download all" twice queues two archive jobs because there's nothing tracking "this user already asked".
4. **Per-feature retry/polling reinventions** — FindingsCard has a 5s polling loop; nothing else does; if we add three more async features we get three incompatible mini-systems.
5. **No artifact retention** — each request regenerates the artifact. For methods report this is one Claude call per visit (~$0.02 + 20s); for ZIPs this is gigabytes of pointless re-globbing.

## 2. Goals

**G1.** Shared subsystem that any feature can use: "start a job, get a `jobId`, poll status, download the artifact when ready."
**G2.** Survives connection drops — the artifact is generated server-side and persisted; the client just downloads the finished file.
**G3.** Dedup: clicking "Download all" twice does not queue two archive jobs.
**G4.** Progress + ETA exposed to the UI so we can show meaningful feedback.
**G5.** Reuses existing BioMate infrastructure (Postgres job table + existing background worker pattern). **No new Redis, no BullMQ.**
**G6.** Migrates the four call sites in a defined order: download-all → methods → reproducibility → findings.

## 3. Non-goals

- **No general-purpose work queue** — not a replacement for the Nextflow run registry or Galaxy's job system. We're specifically for "artifact-producing tasks the user is going to wait on."
- **No multi-tenant priority lanes.** First-come-first-served plus a per-user concurrency cap.
- **No worker auto-scaling.** Single-process workers tied to the existing Node + Python backends. If we outgrow it later, swap the executor.
- **No SSE / WebSocket push.** Polling is fine for our scale (~10² jobs/day peak).
- **No retry-with-backoff for failures.** A failed job stays failed; user can re-trigger. Avoids silent doubled work.
- **No cross-region replication.** Single-region storage.
- **Findings is migrated last** — it's the only one that currently sort-of-works, so the lowest risk to move.

## 4. Existing infrastructure audit

Before adding anything, what BioMate already has:

| Component | Where | Suitable for jobs? |
|---|---|---|
| Postgres (Drizzle) | `frontend/server/storage.ts` | ✅ Yes — add `download_jobs` table |
| Galaxy job tables | `backend/lib/galaxy/model/__init__.py` (Postgres via SQLAlchemy) | ⚠️ Tightly coupled to Galaxy semantics (tool_id, history_id). Not a clean fit; would conflate concerns. |
| Nextflow run registry | `nextflow_executor.py:60` `_runs` dict + disk persistence at `/tmp/nextflow_runs/<run_id>/` | ✅ Pattern reuse — same mtime-based lifecycle, same crash-recovery on disk |
| In-memory findings cache | `routes.ts:10477` `_findingsCache` Map | ⚠️ Process-local, lost on restart. Acceptable for findings (cheap to regenerate); not acceptable for ZIPs (expensive). |
| Background workers | gunicorn workers (Python) + Node Express (Node) — both already long-running | ✅ Workers exist; we add background tasks to them, not new processes. |
| Redis | `biomate-billing-redis` ElastiCache (used only for billing real-time counters per `CLAUDE.md`) | ❌ Not for jobs. Adds infra dependency we don't want. |
| AWS S3 | `s3://biomate-nextflow-work/` for Nextflow outputs | ✅ Suitable for artifact storage (cloud deploys) |
| Local disk | `/tmp/...` on Node/Python pods | ✅ Suitable for artifact storage (local/dev) |

**Conclusion:** Postgres for state + filesystem (or S3) for artifacts + Node/Python background tasks for execution. Zero new infra dependencies.

## 5. Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │              Frontend                       │
                    │  useJob(jobId) → polls every 2s             │
                    │  <JobButton kind="download-all" runId=…/>   │
                    └─────────────────────────────────────────────┘
                              │  POST /api/jobs (create)
                              │  GET  /api/jobs/:id (poll)
                              │  GET  /api/jobs/:id/artifact (download)
                              │  DELETE /api/jobs/:id (cancel)
                              ▼
                ┌─────────────────────────────────────────┐
                │    Node Express (routes.ts)             │
                │  ────────────────────────────────────   │
                │  jobsRouter — thin CRUD + dedup         │
                │  postgres                               │
                │  ─ download_jobs table                  │
                └─────────────────────────────────────────┘
                              │
                              │  (a) artifact already on disk/S3 → serve
                              │  (b) job already running for same dedup key → 200 with existing jobId
                              │  (c) otherwise → INSERT row + spawn worker
                              ▼
              ┌──────────────────────────────────────────────────┐
              │                Executor                          │
              │  Node setImmediate or Python asyncio task        │
              │  ─ download-all → archiver pipe → /tmp/...zip   │
              │  ─ methods     → Claude stream → /tmp/...md     │
              │  ─ reproducib. → glob+tar     → /tmp/...tgz     │
              │  Writes artifact then UPDATEs job row to 'ready' │
              └──────────────────────────────────────────────────┘
                              │
                              ▼
              ┌──────────────────────────────────────────────────┐
              │              Artifact store                      │
              │  Local: /tmp/biomate_artifacts/<jobId>           │
              │  Cloud: s3://biomate-artifacts/<jobId>           │
              │  GC after 24h or 10GB-per-user (LRU)             │
              └──────────────────────────────────────────────────┘
```

### Why this shape

- **Single Postgres table** is the source of truth for job state. Frontend never trusts in-process state.
- **Executor runs in the same process** as the API for v0. No worker dyno, no IPC. We accept that a Node restart kills in-flight jobs (they get marked `failed` on restart-recovery scan).
- **Artifact store is "local disk OR S3"** — environment chooses; same API. Cloud deploys use S3 (so artifacts survive pod recycles); dev uses local disk.
- **No queue middleware** — Postgres `INSERT … RETURNING` + setImmediate is good enough at our scale.

## 6. Data model

Single Postgres table:

```sql
CREATE TABLE download_jobs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         TEXT NOT NULL,
  kind            TEXT NOT NULL,          -- 'download_all_zip' | 'methods_report' | 'reproducibility_bundle' | 'findings_analysis' | 'docx_export'
  payload         JSONB NOT NULL,         -- kind-specific input (e.g. { invocationId, includeWorkDir: false })
  dedup_key       TEXT NOT NULL,          -- 'download_all_zip:<invocationId>' so we coalesce repeat clicks
  state           TEXT NOT NULL,          -- 'queued' | 'running' | 'ready' | 'failed' | 'cancelled' | 'expired'
  progress        INT  DEFAULT 0,         -- 0..100
  eta_seconds     INT,                    -- nullable; executor updates as it learns
  artifact_uri    TEXT,                   -- 'file:///tmp/biomate_artifacts/<id>.zip' | 's3://biomate-artifacts/<id>.zip'
  artifact_bytes  BIGINT,
  error           TEXT,                   -- if state = 'failed'
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at      TIMESTAMPTZ,
  ready_at        TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ,            -- ready_at + 24h
  cancelled_at    TIMESTAMPTZ
);

CREATE INDEX download_jobs_dedup_lookup ON download_jobs (dedup_key, state) WHERE state IN ('queued', 'running', 'ready');
CREATE INDEX download_jobs_user_active  ON download_jobs (user_id, state)   WHERE state IN ('queued', 'running');
CREATE INDEX download_jobs_gc           ON download_jobs (expires_at)        WHERE state = 'ready';
```

### Dedup rule

`dedup_key = '<kind>:<primary_resource_id>'`. Example:
- `download_all_zip:<invocationId>`
- `methods_report:<invocationId>`
- `reproducibility_bundle:<runId>`

When a `POST /api/jobs` arrives:
1. Look up a row with same `dedup_key` AND state in `('queued', 'running', 'ready')` AND not expired
2. If found: return that job's `id` and current state. No new row inserted.
3. If not found: INSERT new row, spawn executor task, return new `id`.

The dedup window expires when the row hits `expired`, `failed`, or `cancelled`.

### Per-user concurrency cap

Before insert, count rows for the same `user_id` in state `('queued', 'running')`. If ≥ N (initial N = 3), reject with 429 + `Retry-After: 60`. Prevents one user accidentally locking up workers.

## 7. API surface

Four endpoints. All under `/api/jobs/`.

### POST `/api/jobs`
Create or coalesce a job.

Request:
```json
{
  "kind": "download_all_zip",
  "payload": { "invocationId": "abc-123", "includeWorkDir": false }
}
```

Response (201 new job or 200 existing):
```json
{
  "jobId": "uuid",
  "state": "queued",
  "kind": "download_all_zip",
  "statusUrl": "/api/jobs/uuid",
  "artifactUrl": "/api/jobs/uuid/artifact"
}
```

Error responses:
- `400` invalid kind or payload
- `403` user can't access the underlying resource (e.g. invocation belongs to another user)
- `429` per-user concurrency cap reached

### GET `/api/jobs/:id`
Poll status.

Response:
```json
{
  "jobId": "uuid",
  "kind": "download_all_zip",
  "state": "running",          // queued|running|ready|failed|cancelled|expired
  "progress": 47,              // 0..100, may be omitted when unknown
  "etaSeconds": 38,            // optional
  "artifactBytes": null,       // populated when ready
  "createdAt": "...",
  "readyAt": null,
  "expiresAt": null,
  "error": null,               // populated when failed
  "artifactUrl": "/api/jobs/uuid/artifact"
}
```

### GET `/api/jobs/:id/artifact`
Stream the produced artifact when state = `ready`. Otherwise 409 with current state. For S3-backed artifacts, returns 302 → presigned URL (15 min TTL).

### DELETE `/api/jobs/:id`
Cancel an in-flight job. Sets state to `cancelled`, signals the executor to abort, garbage-collects partial artifact. Already-`ready` jobs accept DELETE → marks `expired` and deletes artifact.

## 8. Executor

Per-kind handler registered at server startup:

```ts
// frontend/server/jobs/registry.ts
registerJobKind('download_all_zip', {
  estimateSize: async (payload) => /* return bytes estimate for ETA */,
  execute: async (job, ctx) => {
    // ctx provides: setProgress(0..100), checkCancelled(), writeArtifact(stream, contentType)
    const outputs = await listOutputs(job.payload.invocationId);
    const archive = archiver('zip', { zlib: { level: 9 } });
    const sink = ctx.openArtifact(`${job.id}.zip`, 'application/zip');
    archive.pipe(sink);
    let done = 0;
    for (const o of outputs) {
      if (ctx.checkCancelled()) { archive.destroy(); break; }
      archive.append(await fetchOutput(o), { name: o.path });
      done++;
      await ctx.setProgress(Math.round(100 * done / outputs.length));
    }
    await archive.finalize();
    await ctx.closeArtifact();
  },
});
```

Executor runs in-process via `setImmediate` (Node) or `asyncio.create_task` (Python). On every progress update the row's `progress` + `eta_seconds` columns update; transaction batched every 2s to avoid hammering Postgres.

### Crash recovery

On server startup:
1. SELECT all jobs in state `running` from before the boot timestamp
2. Mark them `failed` with `error = 'Server restarted during execution'`
3. Garbage-collect any half-written artifacts

Cheap and predictable. We don't try to resume mid-flight.

## 9. Artifact storage

Two backends sharing the same interface:

```ts
interface ArtifactStore {
  open(jobId: string, contentType: string): WriteStream;
  read(jobId: string): { stream: ReadStream; bytes: number; contentType: string } | { redirect: string };
  delete(jobId: string): void;
}
```

- **`LocalArtifactStore`** writes to `process.env.BIOMATE_ARTIFACT_DIR || '/tmp/biomate_artifacts/'`. Used for dev + on-prem deploys.
- **`S3ArtifactStore`** writes to `s3://biomate-artifacts/<jobId>` (uses the same AWS creds as Nextflow output bucket). `read()` returns a redirect to a presigned URL.

Garbage collection: a cron job (or just a setInterval on the API process) every hour:
- `SELECT id FROM download_jobs WHERE expires_at < now() AND artifact_uri IS NOT NULL`
- For each, delete artifact via store, NULL out `artifact_uri`, set state to `expired`

Per-user storage cap (LRU): if a new job would push user's total artifact bytes over 10 GB, GC their oldest `ready` artifacts first.

## 10. Frontend

### `useJob(jobId)` hook

```ts
function useJob(jobId: string | null): JobState {
  const [state, setState] = useState<JobState>({ state: 'unknown' });
  useEffect(() => {
    if (!jobId) return;
    let cancelled = false;
    const tick = async () => {
      const r = await fetch(`/api/jobs/${jobId}`);
      if (!r.ok || cancelled) return;
      const j = await r.json();
      setState(j);
      if (cancelled) return;
      if (j.state === 'queued' || j.state === 'running') {
        setTimeout(tick, 2000);
      }
    };
    tick();
    return () => { cancelled = true; };
  }, [jobId]);
  return state;
}
```

### `<JobButton />` component

Generic UI for starting + tracking a job:

```tsx
<JobButton
  kind="download_all_zip"
  payload={{ invocationId }}
  label="↓ Download all as ZIP"
  onReady={(artifactUrl) => triggerDownload(artifactUrl)}
/>
```

Internal states:
- idle → click → POST /api/jobs → set jobId
- waiting (queued | running) → spinner + progress bar + "Cancel" link
- ready → fires `onReady(artifactUrl)` → button returns to idle with "Download started" toast
- failed → red message + "Retry" button
- cancelled → idle

## 11. Migration plan

| Phase | Migrates | Risk | Notes |
|---|---|---|---|
| 0 | Subsystem + tests | low | Postgres migration; jobs router + executor scaffold + LocalArtifactStore + JobButton component. No call sites changed. Internal-only. |
| 1 | `download-all-zip` | medium | Most-clicked button. Add new endpoint alongside old; flip AfterRunReport's button; deprecate old. Keep old endpoint working for one release as fallback. |
| 2 | `methods_report` | medium | Closes the 20s sync-Claude pain. The AfterRunReport's MethodsTab uses `useJob`. Backend keeps an inline cache for the report text so `useJob` returning `ready` always finds the artifact. |
| 3 | `reproducibility_bundle` | low | Smaller bundles; same shape as download-all. |
| 4 | `findings_analysis` | low | Replaces FindingsCard's bespoke 5s polling with `useJob`. Bonus: explicit "cancel" + visible give-up. |
| 5 | New: `docx_export` | new | Server-side comprehensive DOCX of the after-run report. Stretch goal once subsystem proven. |

Each phase ships its own PR. Old endpoints stay alive until the next phase ships and telemetry shows nobody calls them.

## 12. Failure modes

| Failure | What happens | Mitigation |
|---|---|---|
| Executor throws | Row → `failed` with `error` string; artifact (if partial) deleted | User sees error message; can retry (deletes old failed row, inserts new) |
| Disk full | Local store `open()` rejects; job goes `failed` | GC runs first; if still full, surface "out of artifact storage" error |
| Postgres connection lost | API returns 503 to clients; jobs in flight continue but can't update progress | When connection restored, executor flushes pending updates; partial progress lost is OK |
| Node restart mid-job | Recovery scan marks `running` → `failed`; user retries | See §8 |
| Cancel mid-stream | `checkCancelled()` returns true at next progress update; executor aborts; partial artifact deleted | Cancel may take up to 2s to take effect (next progress tick); acceptable |
| User refreshes browser mid-download | jobId is in URL state or localStorage; `useJob(jobId)` resumes polling | Need to persist `jobId` per click → use `useLocalStorageState` for in-flight jobs |
| Dedup race (two POSTs in same ms) | `UNIQUE` constraint on `(dedup_key, active states)` blocks second insert; second POST sees the row and returns coalesced jobId | Postgres handles the race atomically |
| Per-user cap reached | 429 + `Retry-After: 60` | UI shows "Too many active jobs — wait a minute" |
| Artifact > S3 multipart limit (5 GB) | Use S3 multipart uploads when bytes exceed 100 MB; transparent to caller | Standard `@aws-sdk/lib-storage` Upload class |
| Cross-AZ outage during S3 write | Stream fails; job → `failed` | User retries; AWS infra problem, not ours to solve |

## 13. Cost

- **Postgres**: ~500 bytes per job row; 1000 jobs/day = 200 KB/day = nothing.
- **Artifact storage**:
  - Median ZIP: ~500 MB. With 24h retention and 200 ZIPs/day, peak storage ≈ 100 GB on disk. Cloud: S3 standard cost ≈ $2.30/month.
  - Methods reports: <100 KB each. Negligible.
- **Worker time**: same as before (Claude calls / archive globs still happen); we're not adding work, just moving it off the request path.
- **Engineering**: ~3-4 days to implement subsystem + first call site. ~½ day per subsequent call site.

## 14. Rollout / success criteria

### Subsystem (Phase 0)
- All four endpoints implemented + Postgres migration applied on dev
- Tests for: dedup, concurrency cap, executor failure path, recovery scan, artifact GC
- No customer-facing change yet — internal validation only

### First call site (Phase 1, download-all)
- Telemetry: `job.created` / `job.transitioned` / `job.completed` / `job.failed` / `job.cancelled` events shipped first
- Dogfood for 5 days with internal team using `?download_v2=1` query param
- Promote to default when:
  - Zero P0 bugs
  - 95p latency from POST → ready ≤ existing sync-stream latency for same archive size
  - At least 10 real user-triggered downloads in v2 path

### Kill criteria (any phase)
- Job completion rate < 95%
- Sustained queue depth > 5 per user
- Artifact storage exceeds 500 GB peak

## 15. Open questions

### 15.1 Should `findings_analysis` keep its in-process cache?
Findings is unique: cheap to regenerate (~10s Claude call), small artifact (~5 KB JSON), but very frequently re-requested as the user revisits a run. **Recommendation:** keep findings's in-process cache as a fast path; the job-queue migration is for the cold path (cache miss) and consistency, not throughput.

### 15.2 Where does the artifact bucket live for BYO-S3 customers?
For customers who configure their own S3 output bucket (see `docs/2026XXXX_OUTPUT_DESTINATION.md` — pending), should download artifacts go into their bucket or stay in BioMate's `biomate-artifacts` bucket? **Recommendation:** stay in BioMate's bucket. The artifact is a derivative product (a ZIP of their files), not a workflow output; it's BioMate UX, not customer data.

### 15.3 Should we surface jobs in a global "Downloads" UI?
A persistent global tab/sidebar item showing all in-flight jobs across runs. Useful for power users. **Recommendation:** defer to v1. Single-job UI in `<JobButton />` is enough for v0.

### 15.4 Auth for `/api/jobs/:id`
Job rows are scoped to `user_id`. GET checks `req.user.id === job.user_id` (admin bypass). For shared/team runs (future), this becomes a permission check against the underlying resource. **Recommendation:** scope to creating user for v0; permission model later.

### 15.5 Streaming progress vs final-artifact-only
For methods report (Claude streaming): should we expose the partial text as it's generated, or only when `ready`? Streaming would let the user start reading earlier. **Recommendation:** only when `ready` in v0. Avoids exposing half-written reports + adds complexity. Phase 2 enhancement.

## 16. Out of scope

- Per-job priority lanes
- Cross-region / multi-AZ replication
- Worker auto-scaling
- Push notifications (SSE/WebSocket) — polling is fine
- Email-when-ready — defer to v1
- Job sharing between users — defer to permissions work
- Retry-with-backoff — fail fast, let the user retry
- A general "Tasks" UI — single-button v0 is enough

## 17. Effort estimate

| Item | Effort |
|---|---|
| Postgres migration | 1 hr |
| Jobs router (CRUD + dedup) | 4 hr |
| Executor scaffold + LocalArtifactStore + S3ArtifactStore | 6 hr |
| `useJob` hook + `<JobButton />` component | 3 hr |
| Recovery scan + GC cron | 2 hr |
| Tests | 6 hr |
| Phase 1 migration (`download_all_zip`) | 4 hr |
| Phase 2 migration (`methods_report`) | 4 hr |
| Phase 3 migration (`reproducibility_bundle`) | 2 hr |
| Phase 4 migration (`findings_analysis`) | 4 hr |
| **Total** | **~36 hr ≈ 1 dev-week** |

Plus 1 week of dogfood / telemetry before default flip per call site. Total calendar time: ~4 weeks from sign-off to all four migrated.

## 18. Decision log (to fill in during review)

| Decision | Verdict |
|---|---|
| Postgres vs Redis/BullMQ for state? | Postgres (no new infra) |
| Local disk vs S3 for artifacts? | Both — environment chooses |
| Polling vs SSE for status? | Polling (2s interval) |
| Single-process executor vs dedicated worker dyno? | Single-process for v0; can swap later |
| Migrate findings to jobs? | Yes, last (lowest risk) |
| Per-user concurrency cap? | 3 in v0 |
| Artifact retention? | 24h + 10 GB-per-user LRU |
| Cancellation? | Yes — 2s effective latency acceptable |

---

## Appendix A — Reference: existing endpoints being replaced

| Existing endpoint | Replaced by | Phase |
|---|---|---|
| `GET /api/invocations/:id/download-all` (sync stream) | `POST /api/jobs` (kind: `download_all_zip`) | 1 |
| `GET /api/invocations/:id/methods-report` (sync Claude) | `POST /api/jobs` (kind: `methods_report`) | 2 |
| `GET /api/nextflow/runs/:id/reproducibility` (sync glob) | `POST /api/jobs` (kind: `reproducibility_bundle`) | 3 |
| `GET /api/workflows/runs/:id/findings` (async-ish) | `POST /api/jobs` (kind: `findings_analysis`) | 4 |

Old endpoints kept alive for one release after migration as feature-flagged fallback, then deleted.
