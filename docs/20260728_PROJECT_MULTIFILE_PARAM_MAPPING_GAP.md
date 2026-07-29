# Fix: project-uploaded file params resolved to bare filenames, not S3 URIs

**Date:** 2026-07-28
**Status:** ✅ Fixed + VERIFIED on dev (2026-07-29). Capstone e2e now **passes**: run `9a92d0e4`
completed in 2m24s with 10 real DE genes (complement-cascade signature — correct for AChR+ MG).
galaxy.log confirms Nextflow received `--matrix/--samplesheet/--contrasts
s3://biomate-nextflow-work/uploads/project-<id>/…` (the exact scheme `_stageProjectFileToNextflow`
produces). Committed `9ea65fe7a`.
**Severity:** P2 — running a multi-file workflow (differentialabundance, etc.) from project-uploaded
files fails at launch
**Found by:** `frontend/e2e/project-real-run-capstone.e2e.ts` (real GSE227835 counts through a project)

> **Correction:** an earlier version of this doc claimed the run launched with *empty params* and
> the files were "never mapped." **That was wrong.** Completed differentialabundance runs also have
> empty `toolParameters` — inputs live in `inline_parameters`. The files ARE mapped to their param
> roles. The real defect is below.

---

## Root cause (verified by comparing a completed run vs. the failed one)

The file→param **role mapping works** (matrix/samplesheet/contrasts are all set). The difference is
the **value**:

| Param | Completed demo run (`a61e8bfa`) | Failed project run (`99b1e660`) |
|---|---|---|
| `matrix` | `s3://biomate-nextflow-work/demo/mg_demo/counts_matrix.csv` | `counts_matrix.csv` |
| `samplesheet` | `s3://…/sample_metadata.csv` | `sample_metadata.csv` |
| `contrasts` | `s3://…/contrasts.csv` | `contrasts.csv` |

The project run passed **bare filenames**; AWS Batch cannot open `counts_matrix.csv`, so Nextflow
fails at launch (~4 s wall time, "0 significant genes").

**Why the bare filenames:**
- The **demo chip** (`chat-interface.tsx`) actually *uploads* the files (`addFiles()` → S3) and emits
  an `[Uploaded datasets: … s3_uri=…]` block, so the extractor fills params with **S3 URIs**.
- The **project "Analyze with BioMate"** flow (`project-detail.tsx:handleAnalyzeClick`) only builds a
  **text list of filenames** — no upload, no `s3_uri`. So the params get **bare filenames**.
- Project files ARE in S3, but in the **app bucket `S3_BUCKET_NAME`**, which **AWS Batch workers
  cannot read** — the Batch-readable bucket is `biomate-nextflow-work`. Even the full app-bucket URI
  wouldn't be enough; the file must be staged into the Nextflow bucket.

## Fix (implemented — `frontend/server/routes.ts`)

In the `/api/workflows/execute` handler, right after `rawParams` is built, when the request carries a
`projectId`, resolve bare-filename params against the project's files and stage them:

- `resolveProjectFileParams(rawParams, projectId)` — for each param whose value looks like a bare
  filename (no `s3://`, no `/`, not a UUID, has an extension), look it up in `project_files` by name.
- `_stageProjectFileToNextflow(srcBucket, srcKey, projectId, name)` — server-side **cross-bucket
  `CopyObject`** from `S3_BUCKET_NAME/<s3_key>` → `biomate-nextflow-work/uploads/project-<id>/<name>`,
  returning the resolvable `s3://` URI, which replaces the bare filename in `rawParams`.

Non-fatal: if resolution/copy fails, the param is left unchanged (existing behavior), logged as a
warning. Staging is cached per filename within a run.

## Verification

- `tsc --noEmit` clean.
- Deploy from the main-repo next-phase checkout, then re-run
  `frontend/e2e/project-real-run-capstone.e2e.ts` (the `fixme` is lifted once green): the run should
  reach **completed** and the report should contain real DE results.

## Follow-ups (smaller, separate)

1. **Guard:** block launching a workflow whose required *file* params still hold an unresolvable value
   (surface the missing-input blocker the panel already has for other cases) instead of a 4 s Batch
   failure. Needs the workflow schema's required-file-param list.
2. **Stale `galaxyApiKey` → 500 on execute:** re-provisioning works, but the key should be refreshed
   before the execute call, not after a 500 (seen once during this investigation).

## Not affected

Routing, project CRUD, collaboration/RBAC, context injection, single-file rnaseq linkage, and the
billing/Lago work are all verified green. This was specific to multi-file inputs from project storage.
