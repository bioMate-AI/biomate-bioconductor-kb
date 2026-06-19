# Phase B + C Spec — Output Endpoint Lockdown + User-Assigned Output Location

**Date:** 2026-06-19
**Status:** awaiting approval before implementation (touches backend, AWS, audit)
**Parent:** `docs/20260619_NEXT_PHASE_OUTPUT_PROJECT_COLLAB_PLAN.md`
**Phase A shipped:** commit `15193afb9` — report content rewrite (frontend only)

## Why this needs explicit approval

Phase B touches:
- New backend endpoint that proxies S3 reads
- New audit-log table + migration
- (Optional in Phase B) AWS S3 bucket policy change to revoke direct user IAM access

Phase C touches:
- Workflow-settings UI (new picker field)
- Backend request schema (NextflowExecuteRequest gains `outputLocation`)
- Nextflow dispatch (`publishDir` directive becomes dynamic)

Both are reversible but Phase B's bucket policy change is operational and needs ops/security buy-in. Spec'd here as a discrete patch you can review + greenlight.

## Phase B — Counted output endpoint

### B.1 — `/api/runs/:id/output/:filename` route

**New endpoint:** `GET /api/runs/:runId/output/:filename`

**Behavior:**
1. Resolve run by id (existing `storage.getExecutionRun(...)` path)
2. Authorize (user must own the run OR be project member of the run's project)
3. Look up file in `output_files` list (already populated by `/api/workflows/runs/:id/output_files`)
4. Generate **single-shot presigned URL** (60-second TTL) for the S3 object
5. Write audit log row (see B.2)
6. **302 redirect** to the presigned URL (browser fetches directly from S3 with the short-lived URL)
7. If file not found in registry → 404
8. If user not authorized → 403

**Why 302 (not stream-through):** streaming through Node would saturate Node memory on multi-GB files (AML BAM is ~30 GB). 60-second presigned URLs are standard practice and audit-trackable.

**Effort:** ~3 hours

### B.2 — Audit log

**New table:** `output_access_log`
```sql
CREATE TABLE output_access_log (
  id BIGSERIAL PRIMARY KEY,
  run_id TEXT NOT NULL,
  filename TEXT NOT NULL,
  user_id TEXT NOT NULL,
  user_email TEXT,
  project_id TEXT,                    -- nullable for runs not in a project
  ip_address INET,
  user_agent TEXT,
  http_status INTEGER,                -- 200 / 403 / 404
  file_size_bytes BIGINT,
  accessed_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_output_access_log_run ON output_access_log(run_id, accessed_at DESC);
CREATE INDEX idx_output_access_log_user ON output_access_log(user_id, accessed_at DESC);
CREATE INDEX idx_output_access_log_project ON output_access_log(project_id, accessed_at DESC) WHERE project_id IS NOT NULL;
```

**Query patterns supported:**
- "All downloads of run X" → for chain-of-custody in the Download Report
- "All downloads by user Y in last 7 days" → for billing + abuse
- "All downloads in project Z" → for project audit

**Migration:** `frontend/server/migrations/0007_output_access_log.sql` (new). Drizzle schema entry mirrored in `frontend/shared/schema.ts`.

**Effort:** ~1 hour (table + migration + schema)

### B.3 — Update existing callers

These code paths currently expect to embed S3 URIs or to call `aws s3 cp`:

| Caller | Change |
|---|---|
| `frontend/client/src/v2/AfterRunReport.tsx` — Outputs tab Download links | Already shipped (Phase A) — links go to `/api/runs/<id>/output/<filename>` |
| `frontend/server/routes.ts` per-file response shape | Strip `s3_uri` from the user-facing response. Keep internally; never serialize to client. |
| `step-output-preview.tsx` inline preview (image, table, etc.) | Fetch via new endpoint instead of presigned URL it currently builds client-side |
| Download-all ZIP at `routes.ts:7460` | Continues to use BioMate's own S3 reads (server-side); just adds an audit-log row per file in the zip |
| Galaxy interactive tools (RStudio, JupyterLab) | Already access files via Galaxy History (server-side); unaffected |

**Effort:** ~half day to update + test

### B.4 — Bucket policy change (optional, recommended)

Once B.1-B.3 ship, the only legitimate read path for `s3://biomate-nextflow-work/*` becomes the BioMate IAM role. Lock down:

```json
// biomate-nextflow-work bucket policy addition
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::biomate-nextflow-work/*",
  "Condition": {
    "StringNotEquals": {
      "aws:PrincipalArn": "arn:aws:iam::399683337364:role/biomate-service-role"
    }
  }
}
```

**Operational note:** this breaks anyone today who is using `aws s3 cp` directly. Two-week deprecation notice recommended; email power users; switch policy after.

**Effort:** ~30 min (policy change) + 2 weeks deprecation window

## Phase C — User-assigned output location

### C.1 — UI picker

In `frontend/client/src/components/nextflow-workflow-viewer.tsx`, workflow settings tab — add a new section:

```
Output Location
  ○ Default (BioMate-managed, kept 90 days)
  ○ My project folder  ← only shown if chat is in a project
  ○ My S3 bucket (paste URI)  → text input for s3:// path
  ○ My Galaxy History  ← only shown if user has Galaxy account configured
```

Stored in a new param `__outputLocation` (mirrors existing `__qcConfig` pattern at `nextflow-workflow-viewer.tsx:1431`):

```ts
{
  __outputLocation: {
    type: 'default' | 'project' | 'user_s3' | 'galaxy_history',
    userS3Uri?: string,      // when type === 'user_s3'
    projectId?: string,      // when type === 'project'
  }
}
```

**Effort:** ~half day UI

### C.2 — Backend wiring

`NextflowExecuteRequest` already has a `compute_config` field. Extend with `outputLocation`:

```python
class NextflowExecuteRequest(BaseModel):
    # ... existing fields ...
    output_location: Optional[Dict[str, Any]] = None  # {type, userS3Uri?, projectId?}
```

In `execute_nextflow`, before computing `outdir`:

```python
if request.output_location:
    loc = request.output_location
    if loc.get("type") == "user_s3":
        # Validate the user has bucket-write IAM grant; assume role if needed
        outdir = loc["userS3Uri"].rstrip("/") + f"/{run_id}/output"
    elif loc.get("type") == "project":
        outdir = f"s3://biomate-projects/{loc['projectId']}/runs/{run_id}/output"
    elif loc.get("type") == "galaxy_history":
        # Use Galaxy's native history dataset publish (no S3 layer)
        outdir = f"galaxy://histories/{history_id}/datasets/{run_id}"
    # else: fall through to default behavior (current)
```

Then `publishDir` directive in the dispatched Nextflow uses that `outdir`. For non-default options, also write a small `metadata.json` next to outputs so the per-project file browser can reconstruct.

**Effort:** ~1 day backend + ~half day testing each of 4 options

### C.3 — Per-project S3 layout (when "My project folder" selected)

Outputs land at:
```
biomate-projects/
└── <project_id>/
    └── runs/
        └── <run_id>/
            ├── metadata.json    # workflow_name, params, timestamp, chain_id
            ├── output/          # Nextflow publishDir target
            ├── logs/
            └── report.md        # downloaded report goes here too (snapshot)
```

Same `/api/runs/:id/output/:filename` endpoint (B.1) works against this bucket; it picks the right bucket based on the run's `outputLocation` metadata.

**Effort:** ~half day (bucket creation, IAM, file-path resolver)

## Total Phase B+C effort

| Sub-item | Effort |
|---|---|
| B.1 endpoint | 3 hours |
| B.2 audit log | 1 hour |
| B.3 caller updates | half day |
| B.4 bucket policy | 30 min + deprecation window |
| C.1 UI picker | half day |
| C.2 backend wiring | 1 day + half day testing |
| C.3 per-project layout | half day |
| **Total dev time** | **~3 days** |
| **Calendar time** (incl. ops sign-off + 2-week deprecation) | **~3 weeks** |

## What I need from you to start

1. **Greenlight for the audit-log table migration** (Drizzle migration `0007_output_access_log.sql`)
2. **Greenlight for the new S3 bucket `biomate-projects`** (or use a prefix in the existing bucket — slightly cheaper, less clean)
3. **Confirmation on the 4 output-location options** (default / project / user-S3 / galaxy-history). Any I should drop or add?
4. **Decision on B.4 timing**: ship B.1-B.3 first (so users have the endpoint), then revoke direct S3 with 2-week deprecation, OR ship everything atomically (riskier)?
5. **For Galaxy History option (C.1 #4)** — do we have current users with active Galaxy accounts who'd benefit, or is it OK to defer this option to v2?

Once approved I'll ship in this order:
1. B.2 migration + B.1 endpoint (lowest risk)
2. B.3 caller updates
3. C.1 UI picker
4. C.2 backend wiring
5. C.3 per-project layout
6. B.4 bucket policy (after notice)

All test-driven, all behind the existing fixture-login pattern, all evidence-backed.
