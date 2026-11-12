# Dataset panel — committee audit of the 2026-11-11 work (PR #387 @ 521ee24b)

Five independent read-only reviewers (backend profiler, server routes, live dev UI EN+ZH, test
quality, EN/ZH copy) plus 8 founder screenshots. Every item below was reproduced unless marked
(S) = suspected. Evidence/scripts: scratchpad `audit-{backend,server,ui,tests,copy}/`.

**Corrections to earlier claims.** (1) "~22/30 formats PASS, 0 FAIL" was wrong by the matrix doc's own
rubric: 9 formats (bam, cram, h5ad, loom, xlsx, mtx, sdf, pod5, 10x matrix) still show "no content
preview" = FAIL, and the matrix e2e asserted nothing per format. (2) "stale edit → 409" holds only when
the cell value differs: with repeated values a stale/mis-numbered edit lands on the wrong row.

## P0 — data loss / security
| ID | Finding | Where |
|---|---|---|
| S1 | Two concurrent edits on one version: one edit lost, history lists v1 twice, no v2 (dev) | project-routes.ts edit/restore: no version precondition |
| S2 | Two concurrent uploads of a new name: DB row describes bytes S3 no longer holds (dev) | `_allocateObjectKey` check-then-put without lock |
| S3 | Stale/mis-numbered edit with repeated values edits the wrong row, no 409 | edit contract lacks base version |
| S4 | Parallel run_code calls in one chat run each other's script (fixed `/work/script.py`) | code-runner.ts shared workspace |
| S5 | `/api/perception/folder_profile` reads any `files[].datasetRef` (any path / s3 key) | routes.ts gate checks only `datasetRef`; perception.py `_resolve_path` |
| S6 (S) | Persistent workspace: a run can plant symlinks under input/ that the next staging follows | code-runner.ts; workspace key not bound to user |
| P1 | Novogene names `WT_1_1/WT_1_2/WT_2_*` paired across replicates (Galaxy auto_pair raises; fallback substitutes `_1` anywhere) | folder_profile.py |
| P2 | Corrupt gzip → profile_dataset raises → HTTP 500 | data_perception `_raw_head` |
| P3 | JSONL lines dropped silently (BOM loses record 1) | data_perception jsonl |

## P1 — wrong results
| ID | Finding |
|---|---|
| R1 | CSVs 1–10 MiB cannot be edited; error says "not UTF-8" (`readTextPrefix` clamps to 1 MiB) |
| R2 | featureCounts / `#`-comment-first tables read as 1-column text "Good"; delimiter sniffed on line 1 only; `.log` parsed as CSV |
| R3 | Header inference: numeric/year headers read as data; same-case single-column header (SYMBOL, Gene) read as data; UTF-8 BOM in first column name; blank first line |
| R4 | Header-only / 1-line / 1-byte files rated Good |
| R5 | Label detection by substring (`y` in assay/gene_symbol/feature_type; `id` in width); continuous column taken as classes; first match wins |
| R6 | Contradictions: `table_clean` "no leakage/imbalance" beside leakage/confound/imbalance findings or when checks never ran; effective-N "strong imbalance" on 65/35 |
| R7 | read_rows vs profile disagree (SAM, PDB, FASTQ-as-.txt): table paged for non-tables |
| R8 | No content validation for files named .fastq/.vcf (prose → "Good, 1 read") |
| R9 | Format chip trusts the extension (20-byte ".png" → "PNG"; one NUL in a CSV → whole file non-tabular) |
| R10 | Ragged rows silently truncated; h5ad shape −1; FASTA cap ignored for one huge record; IUPAC → protein; BED header row counted; semicolon CSV |
| R11 | Lanes not merged (S1_L001/L002 = 2 samples); I1/I2 index reads become single-end samples |
| R12 | Wide matrices: memory ~21× file size (S: OOM on TCGA-size) |
| R13 | Versions tab: timestamps on the wrong versions; author shown as UUID; diff row numbers 0-based |
| R14 | Downloads named after the S3 key (`small-2.csv.v2`); header Download navigates the tab to the raw S3 URL for text/image files |
| R15 | Upload accepts names rename refuses (file + folder both "data"); non-uuid ids → 500/502 instead of 404; delete leaves version objects |
| R16 | X-ray PDB shown with a pLDDT chart (B-factors misread as confidence) |

## P2 — panel shape (founder screenshots)
| ID | Finding |
|---|---|
| U1 | Table/Columns/Plot always drawn (PNG, TIFF, PDF, PDB, FASTA, FASTQ, BAM, h5ad, xlsx, MD, JSON) — controls not chosen per data kind |
| U2 | QC card always shows ROWS/COLUMNS (PNG 0/0, h5ad 1/1, VCF "columns 1"); stat cards wrong for non-tables |
| U3 | Columns view says "not a table" for header-only TSV, JSON array/object, VCF, xlsx shown as tables |
| U4 | "Watch" used for "not analysed" (images, PDF, BAM, h5ad, xlsx, JSON) → orange dots everywhere |
| U5 | h5ad: no AnnData summary preview (cells × genes, obs/var, embeddings) |
| U6 | Invalid image: broken icon, no error |
| U7 | Histogram ticks 1.84e+3; mixed precision |
| U8 | Columns view flags healthy columns "watch" when their name appears in any note |
| U9 | JSONL nested chips not clickable/keyboard; record view opens below the table off-screen |
| U10 | File tree: names in nested folders shrink to 0–19 px; hover eye renders file contents inside the tree; title hides the full name |
| U11 | FASTQ shown with FASTA ">" headers; Markdown unrendered; tab carries over between files; raw MIME; "Run full QC"/Edit offered where meaningless |

## P2 — copy (EN/ZH)
"≥Reads scanned"; Watch wording for not-analysed; raw exception text with temp paths; "Galaxy" in
tooltips; raw ext labels (mothur.axes); English-only format labels in zh; rename errors (every 400 =
"name not allowed", 403 says "upload"); remaining "(s)" plurals; zh terminology (R1/R2, 注释, 布局);
glosses for Phred, N50, effective N, leakage; "inputs" root untranslated; viewer/pLDDT strings
untranslated.

## Test quality
Safety checks guarded only by regex on source (mutations disabling 409, UTF-8 refusal, tabular gate
all survive); `splitRecords` mid-field quote mutation survives; no committed Python-csv differential
test; FASTQ viewer test can't detect its regression; 3D test mocks the selector under test; Galaxy seam
tested only with hand stubs; matrix e2e records instead of asserting and its JSON predates its
assertions; EPAR e2e pinned to the extraction bug (69%/7); swallowed cleanup errors; harness strips
auth headers with `page.route` because `loginAsFixture` sets a Bearer header on every request
(root cause: use the cookie session, CLAUDE.md's canonical pattern).

## Fix plan (parallel streams, one owner per file set)
A. Server integrity (project-routes.ts, delimited-text.ts, s3-client.ts, content-disposition, data-hub
download): version precondition + row lock for edit/restore/upload-versioning; key reservation under the
project lock; full-size reads up to the cap; download names; name rules shared by upload and rename;
404s; version timestamps/author; behavioural route tests (fake pool/S3) replacing source regexes.
B. run_code workspace (code-runner.ts): per-call script/input paths, symlink-safe staging, workspace
bound to user+chat.
C. Profiler (data_perception.py, folder_profile.py, galaxy_formats.py, perception.py): P1–P3, R2–R12,
"not assessed" verdict, content-first format, backend copy; folder_profile accepts only server-resolved
refs.
D. Panel (dataset-object, data-perception card, columns view, plot, previews, file tree, JSONL record,
viewers, locales): per-kind view model, QC shape per kind, AnnData/image/markdown views, tree layout,
copy fixes.
E. Tests/harness (frontend/e2e): cookie-based fixture login (no page.route), matrix asserts expected
verdicts per format, cleanup failures fail loudly, no tests pinned to known data defects.
Every fix ships with a behavioural test that fails without it.

## Follow-up: TIFF / OME-TIFF preview (branch fix/ds-tiff-preview-20261112)
The panel showed "TIFF can't be displayed in the browser" (`data-preview-kind=none`); the format
matrix expects `image`. Browsers cannot decode TIFF, so the server renders one plane to PNG:
- `backend/lib/galaxy/ai/tiff_preview.py` — first (or `series`/`page`-selected) plane → 8-bit PNG,
  ≤1024 px. uint8 as stored (a 0–15 mask is min–max stretched); bool black/white; other dtypes
  0.5–99.5 percentile stretch (reported); ≤3 channels → RGB, more → channel 1 + note; pyramidal
  OME-TIFF read at the smallest level covering 1024 px; otherwise a plane over 256 MiB decoded is
  refused (`too_large`). Compressions tifffile cannot decode without the optional `imagecodecs`
  (LZW, JPEG; CCITT fax always) are decoded by Pillow's libtiff for the selected pages only — the dev
  Galaxy container has no imagecodecs, and Galaxy's own `1.tiff` fixture is CCITT G4.
  numpy/tifffile/Pillow are imported lazily: without them the endpoint answers 503 `preview_unavailable`.
- `POST /api/perception/preview_image {projectId, datasetRef, series, page}` (perception.py) reads only
  `projects/<projectId>/…` objects of the uploads bucket (S5 `folder_object_ref`), ≤256 MiB stored,
  two renders at a time per worker; `X-Preview-Info` = JSON of what was drawn. Not reachable through the
  generic `/api/perception/*` proxy (gate allowlist → 404).
- `GET /api/projects/:id/files/:fileId/preview.png` (project-routes.ts) — owner/member, key from
  project_files, ETag from content_hash + selection (304 on revalidation), 256 MiB cap, keys outside the
  project prefix (run outputs under `nextflow/…`) → 422 `not_previewable`.
- Panel: a TIFF-family format (or `.tif/.tiff/.btf/.tf8` name without a format) fetches the PNG, shows it
  with a caption ("first of 3 pages · 16-bit, contrast stretched · 56 × 49 px"); any refusal / decode
  failure → the honest download state with the localized reason.
Open: run-output TIFFs stored outside `projects/<id>/` are not previewable until the backend can
verify a server-attested ref for them; only plane 0 / series 0 is reachable from the panel (no page
picker yet); the format-matrix e2e on dev needs this branch deployed.

## Rounds 2–3 (2026-11-12) — verification, new findings, results on dev

**Process.** Round 2 = a read-only verifier re-checked every ID above against the integrated branch
with the round-1 probes plus mutation tests (revert a guard → its test must fail). Round 3 = a live
walkthrough of dev in EN/ZH/390 px. Each round's findings were fixed in parallel streams (one owner
per file set), integrated on `devline/ds-audit-20261112` (draft PR #390, deploy vehicle; review in
#387), gated (backend pytest, 7 profiler suites on py3.9, module load inside dev's Galaxy container,
tsc ×2, full vitest) and deployed through the guarded sync (merges any newer dev deploy, re-gates).

**Round 2 new findings (fixed):** path traversal through the backend passthrough
(`/api/generate/../perception/*`, shared helper `proxy-path.ts`); text with no newline in 8 KB read as
binary; edit route vs reader delimiter mismatch (rows carry `delimiter`, edit uses it); missing
rows→edit round-trip test (recorded real reader fixtures); small X-ray PDBs as documents (`structure`
evidence: method/predicted); JSONL with a bad first line read as CSV; empty-file / latin-1 / duplicate
column handling; diff row numbers by the reader's layout; untested 404/tabular guards; specific
upload-conflict and edit-error messages; zh format labels; density viewer by kind not extension.

**Round 3 new findings (fixed):** Versions tab showed another file's diff; QC card 403 after every
edit (gate accepted only the current key — now current + archived version keys for members); PDF
rated Watch ("PDF named PDF", gb18030); tree dots from a stale extension list (now the stored
profiler verdict; auto-profile only ≤ 50 MB); xlsx slow (bounded reader 4.6 s → 0.03 s) and no
contents (first-sheet preview); restore UX; decimal-comma typing (`columnStats`); featureCounts false
alarms (layouts recognised); JSONL cut-off false positive + median; AnnData layers vs groups;
effective N / groups only with a confident label column; 10x root folder; folder roll-up = file
panel decision; "Run full QC" sends; rename hint; header/breadcrumb; duplicate stats; Plot only when
numeric; multi-line cell editor; provenance wording; image fit/zoom; PDB fit; TIFF/OME-TIFF preview
(server PNG render); paired vs single-end samplesheets; zh/en wording. Also found by e2e on dev:
header version chip read "v1" until the Versions tab was opened.

**Integration catches (before deploy):** a removed TIFF constant still referenced by another branch
(runtime ReferenceError in the preview); backend/locale wording drift (parity tests now have no
exemptions); locale three-way JSON merge with another session's leak sweep.

**Results on dev `aefa6221` (computed by the harnesses, not judged):**
- `dataset-format-matrix.e2e.ts`: **PASS 34 / PARTIAL 0 / FAIL 0** (baseline `eeb1219c`: 3/13/14 by
  hand; the asserting harness computed 0/0/34 before the fixes deployed).
- `dataset-edit-safety` (byte-exact, header-less, stale repeated-value → 409, mis-numbered row →
  409), `project-file-rename`, `jsonl-nested-tables`, `run-code-outputs`, `dataset-panel-full`: pass.

**Open (owner decisions / later):** fixture password is committed in ~61 tracked files (incl. LLM
training data) — rotate + scrub; dev's Galaxy container is paused during deploys (`docker commit`),
stalling users; PR #387's squash onto next-phase lost the run_code persistence wiring (see the PR
comment); run-output TIFF preview; TIFF page picker; profile verdicts do not refresh after a profiler
upgrade until re-profiled.
