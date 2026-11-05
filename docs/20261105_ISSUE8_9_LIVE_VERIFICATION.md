# #8 / #9 live verification on dev — results + #8 output-attribution completion

Date: 2026-11-05. After A–E (#5a) synced to dev, verified the earlier-shipped #8 and #9 against
live dev data (fixture login; read-only API + container logs). Findings below, with one gap found
and fixed.

## #9 (failed-run UX) — VERIFIED ✓
Failed ADMET run `d72b67af`:
- `GET /output_files` → **3/3 files are Nextflow metadata** (`dag.html`, `report.html`,
  `timeline.html`), **0 scientific**. So `isRunMetadataFile` splits them correctly → the Outputs
  tab shows the "No scientific outputs — only Nextflow run metadata" state + the collapsed
  `run-metadata-section`, and "Download all (N)" counts scientific only.
- `GET /findings` → `status: "error"`, summary "The workflow run failed before producing output
  files…" → the no-report / "Analysis not available" path.
The data layer the #9 fix handles is confirmed live; the visual rendering (metadata section,
"No report" note, HTML-in-new-tab) is covered by the passing RTL tests in `AfterRunReport.test.tsx`
and `step-output-preview.test.tsx`.

## #8 (per-step finalization) — status VERIFIED ✓; outputs were a GAP, now fixed
Completed ADMET run `82c1245a`, `GET /api/workflows/runs/82c1245a`:
- **Step status: finalized ✓** — both steps `completed` (the stale creation-time `pending` is
  gone). This is the core #8 fix working.
- **Step outputs: were still 0 ✗** — because `GET /output_files` returns files with
  `step_name`/`process_name` = **null** (only `s3_uri, name, size, extension, download_url`).
  `finalizeRunSteps` honestly left them unattributed rather than guessing.

### Fix (this commit) — attribute outputs via the S3 key path
The S3 key DOES encode the producing process:
`…/80e1a0b5/02_predict_admet_properties/toxicity_report.json`. Nextflow publishes each process's
files under a `NN_<process>/` dir. Added `stepKeyFromUri()` in `run-record-metrics.ts`: when a
file has no `step_name`/`process_name`, derive the step key from the directory above the filename
(drop the `NN_` phase prefix, normalize), and match it to the step as before. The aggregate
`output/` dir (findings_data, qc_events) yields no key → correctly unattributed. No hardcoding —
pure path structure; the explicit `step_name`/`process_name` tag still wins when present.
Unit test added (`run-record-metrics-20261104.test.ts`): outputs attach via the
`NN_<process>/` path when the tags are null, and the `output/` aggregate file stays unattributed.

Gate: `tsc` clean; full `vitest run` 2178 passed / 42 skipped / 0 failed.

### Needs live re-check after sync
Re-`GET /api/workflows/runs/82c1245a` on dev after this deploys — the two steps should now carry
their `02_predict_admet_properties` / `01_*` outputs (not 0). NOTE: the read-time backfill in
`GET /:id` only re-attaches when a terminal step still has no outputs while output files exist, so
the first GET after deploy triggers it.

## Honest status
- #9: verified (data + unit tests).
- #8: status-finalization verified live; output-attribution gap found live and fixed here (pending
  a post-sync re-check). This is the same "run record starved of data the backend doesn't surface"
  pattern as the original #8 — here the data (producing step) was present in the S3 path all along,
  just not in the listing's fields.
