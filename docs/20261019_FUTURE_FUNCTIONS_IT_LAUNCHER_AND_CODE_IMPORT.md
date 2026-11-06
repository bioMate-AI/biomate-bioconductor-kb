# Future functions — standalone Interactive-Tool launcher & runnable code import (2026-10-19)

Two capability gaps found while auditing BioMate against the t0 tutorial claims.
Both are **verified in code** (current state is accurate, not speculative) and
documented here as future work with a concrete, ready-to-build path. Neither is
implemented yet.

---

## 1. Standalone "open Jupyter / RStudio / CellxGene on a dataset or project"

### Current state (verified live)
- Three Galaxy Interactive Tools are **really integrated and live on dev**:
  `GET /api/interactive/available` → `{jupyter:true, rstudio:true, cellxgene:true}`.
  Real containers, launched via `/api/interactive/launch` (`routes.ts:15478`), entry
  URL proxied back (`rewriteInteractiveToolUrl`). Availability-gated so no dead buttons
  (`use-interactive-tools.ts`).
- They surface **only on result surfaces** — the after-run Outputs tab, step-output
  previews, workflow artifacts, chat attachments (`InteractiveLauncher`,
  `interactive-launcher.tsx`; `AfterRunReport.tsx`). That's why the user "only sees the
  previous three in the output tab."
- The other viewer names (iSEE, vcf.iobio, bam.iobio, HiGlass, Pavian, IGV, JBrowse) are
  **inline file viewers**, not launchable compute environments.

### The gap
There is **no entry point to open Jupyter/RStudio/CellxGene on a dataset or project**
directly (e.g. from the data hub). Reason: data-hub datasets are **S3 files** (`DatasetRef.ref`
is an S3 key — no `galaxyDatasetId`), but Interactive Tools launch into a **Galaxy history**
and need an HDA (CellxGene needs an `infile` HDA; Jupyter/RStudio mount the history). So
"open on a dataset" requires **staging the S3 file into the history first**.

### Ready-to-build path
The pieces all exist:
1. Presign the dataset's S3 ref — `s3Service.generatePresignedDownloadUrl(key)`
   (`routes.ts:2968`, `POST /api/s3/download`).
2. Stage into the session Galaxy history — `galaxyAPIProxy.uploadFromUrl(presignedUrl,
   historyId, fileName)` (`galaxy-api-proxy.ts:577`) → returns an HDA id.
3. Launch — `launchInteractiveTool(tool_id, historyId, {dataset_ids:[hda]}` (+ `infile`
   for CellxGene) — reuse the launch+entry-point poll from `/api/interactive/launch`.
- **New endpoint:** `POST /api/interactive/launch-on-dataset {tool_id, s3_ref, file_name}`
  doing steps 1–3 atomically.
- **UI:** reuse `InteractiveLauncher` (already availability-gated + format-aware + ready-poll)
  from `dataset-object.tsx` (and a project-level "Open Jupyter/RStudio" that launches into the
  history with no dataset — the launcher's existing "manual launch, no format" mode).
- **Verify:** launch Jupyter on a staged dataset on dev; confirm it serves and the data is
  present.
- Notes: counts against compute/billing; stage is async (uploadFromUrl + container boot
  ~10–30 s — the launcher already polls readiness).

---

## 2. Make imported Python / R code actually runnable (auto-wrap)

### Current state (verified live on dev, 2026-10-19)
- Import: `POST /api/workflows/upload-file` (`routes.ts:8510`) stores the file in the
  `personal_workflows` Postgres table. **The multer `fileFilter` (`routes.ts:8496-8503`)
  allows only `.nf`, `.ga`, `.yml`, `.yaml`** — `.py`/`.R` are rejected. Listed via
  `GET /api/workflows/personal`.
- Execute: the frontend fetches `file_content`, passes it to Galaxy
  (`routes.ts:11087-11106`); the backend writes it to `/tmp/biomate_user_nf/<user>/<name>`
  and runs it with **`nextflow run`, `executor=local`** (NOT Batch — personal workflows run
  in the Galaxy container, `nextflow_executor.py:5720-5727`), with an optional sandbox pre-check.

### What works vs. the gaps (empirically verified)
- **Nextflow `.nf` imports genuinely function.** Imported a minimal one-process `.nf` on dev,
  executed it, and it **completed in ~5 s** (`status: completed`). Confirmed end-to-end.
- **Python/R are rejected at import** — so there is NO "stored-but-unrunnable" problem (my
  earlier claim that it accepts any type was wrong). BUT the rejection surfaces as a bare
  **`500 Internal server error`**, not the intended clean message ("Only .nf, .ga, .yml, and
  .yaml workflow files are supported") — the multer `Error` isn't mapped to a 400. **UX bug.**
- **`.ga` (Galaxy workflow) is allowed at import but CANNOT run** (confirmed from code): the
  upload stores it to Postgres with no Galaxy call, so it is never registered as a Galaxy
  workflow, and the execute path routes everything through `nextflow run`
  (`nextflow_path:'personal_workflow/main.nf'`) — there is no routing of an uploaded `.ga` to
  Galaxy's native `invokeWorkflow`. A `.ga` JSON can't be parsed by Nextflow → fails. `.yml`
  is likely the same. So `.ga`/`.yml` look supported (pass the filter) but are not executable —
  worse than `.py`/`.R`, which are at least rejected. Fix: route `.ga` to Galaxy's native
  workflow invocation (register on import), or drop `.ga`/`.yml` from the allowlist.

### Ready-to-build (two pieces)
1. **UX fix (small):** catch the multer `fileFilter` error in the upload handler and return
   `400` with the "Only .nf/.ga/.yml/.yaml…" message instead of a 500.
2. **Python/R support (the feature):** add `.py`/`.R` to the allowlist AND auto-wrap them at
   import into a minimal Nextflow process (below), so "import your Python/R and run it" works.

### Ready-to-build path (recommended: auto-wrap)
At import (or just before execution), detect `file_type in {py, r, R}` and generate a minimal
Nextflow wrapper that runs the script in the right container:
```
process USER_SCRIPT {
  container '<python|r-base image>'        // py → python:3.x, R → rocker/r-ver
  input:  path script_file                 // + path(s) for declared inputs
  output: path 'outputs/*'
  script: """ mkdir -p outputs; python ${script_file} """   // or: Rscript ${script_file}
}
workflow { USER_SCRIPT(file('<staged script>')) }
```
- Store/emit the wrapper as the `main.nf`, with the user's script staged as an input file.
- Interpreter + container chosen by `file_type`; inputs bound the same way the bioc entry
  wrapper does (`_build_bioc_entry_wrapper`, `nextflow_executor.py:1757`).
- **Alternative (smaller):** reject non-`.nf` at import with a clear message pointing to
  `run_code` / the wrap option — honest, no silent "stored but unrunnable".
- **Verify:** import a `.py` and a `.R`, run each, confirm outputs.

---

## Status
Documented as future functions per user direction (not implemented this session). The
Interactive-Tools launcher staging path and the code-import wrap are both fully scoped
above with exact file/endpoint anchors.
