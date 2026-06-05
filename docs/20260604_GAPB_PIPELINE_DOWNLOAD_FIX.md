# Gap B fix — pipeline-run download via async job system (2026-06-04)

Closes Gap B from `docs/20260603_PHASE1_GAPS_NEXTFLOW_DOWNLOAD_AND_MIGRATION_RUNNER.md`.

## Why this matters

Phase 1 shipped the new `download_all_zip` job kind + JobButton wiring, but
the resolution chain inherited the legacy endpoint's Galaxy-only blind
spot: both endpoints walked `workflow_invocations` and returned 404 for
every run that didn't have a Galaxy invocation row — i.e. every pipeline
run. The most-recent 5 succeeded `execution_runs` on dev all 404'd, meaning
the JobButton on the AfterRunReport's OutputsTab was effectively broken for
~100% of real users.

## The fix

`frontend/server/jobs/handlers/download-all-zip.ts:resolveInvocation()`
now appends a final fallback:

```ts
const s3Uri = executionRun?.execution?.nextflowOutputDir;
if (s3Uri?.startsWith("s3://")) {
  return { _pipelineSource: true, id, workflowName, s3Uri };
}
```

`execute()` branches on `_pipelineSource` and dispatches to a new
`executePipelineSource()` which:

1. Lists every object under the S3 prefix via `ListObjectsV2Command`
   (handles pagination).
2. Streams each `GetObjectCommand` body into the archiver with
   run-relative paths (strips the `s3://bucket/nextflow/outputs/<id>/`
   prefix so the ZIP looks like a run output directory).
3. Updates progress every 5 files.
4. Cancellation-safe via the same `checkCancelled` + `sink.stream.end()`
   pattern as the Galaxy path.

`estimateSize()` also gained a pipeline branch — uses S3 list `Size`
field, no extra API calls.

Side effect: the user-facing error string "Invocation not found" became
"Run not found" (the legacy word leaked through).

## End-to-end validation on dev

Synthetic `execution_run` row pointing at a real 121-file cryo-EM S3
prefix from a 2026-04-26 run. Cleaned up after testing.

### Behavior parity vs legacy

| Endpoint | Result |
|---|---|
| Legacy `GET /api/invocations/:id/download-all` | 404 (pre-existing — unchanged) |
| New `POST /api/jobs (download_all_zip)` | 201 → 23s → ready → 57 MB ZIP |

### Performance

| Path | Time | Bytes |
|---|---|---|
| Cold (S3 list + 81 GetObjects + archive) | 23s | 57.5 MB |
| Warm (dedup hit → cached artifact) | **256ms** | 57.5 MB |

### Integrity

- **ZIP magic**: `504b0304` ✓
- **File-count parity vs S3**: 81 / 81 (non-zero size) ✓
- **Byte-identical sample**: `picking_report_batch_0000.json` MD5
  `20d0981497a4305bc5b4bffa84728991` matches between ZIP entry and the S3
  source. ✓
- **Archive paths are run-relative**: `00_batch_split/batch_manifest.csv`,
  `02_motion_correction/batch_0000/motion_report_batch_0000.json`, etc.
  — no leading `nextflow/outputs/<uuid>/` cruft. ✓
- **Filename**: `Content-Disposition: filename="CryoSPARC SPA (Test)_outputs_test-gap.zip"`
  — proper name (Phase 2 filename plumbing carried through).

### Cache + dedup

Second POST with the same `(kind, invocationId)` returned the same
`jobId` with `state=ready` in 256ms. Cached artifact served from local
disk without re-listing S3 or re-fetching any object. 90× speedup over
cold path.

### Compatibility

- The Galaxy path in `execute()` is untouched — runs with a real
  `workflow_invocations` row still work identically.
- Per-file fetch errors are caught and logged; the archive continues
  (partial bundles preferred over zero output). Mirrors legacy behavior.
- Existing handler unit tests still pass (4/4).

## What this unblocks

- AfterRunReport OutputsTab's "Download all" button on every pipeline
  run (drug discovery, cryo-EM, RNA-seq, variant calling, etc.) — i.e.
  the dominant case.
- Phase 1 (`download_all_zip`) was technically "shipped" yesterday but
  was 404'd by default; today it actually does the thing.

## What this does NOT do

- The legacy `GET /api/invocations/:id/download-all` is unchanged. It
  continues to 404 for pipeline runs. Once telemetry shows nobody hits
  it (per design §11), the legacy endpoint can be retired.
- No memory backpressure on huge bundles: each S3 `GetObject` body is
  streamed directly into the archiver (one file in memory at a time),
  but 50 GB of small files would still take 30+ minutes serially. If
  it becomes a real problem, parallelize 4-wide.

## Commits

| SHA | What |
|---|---|
| `fb166639e` | `fix(jobs): download_all_zip supports pipeline-native runs (Gap B)` |
