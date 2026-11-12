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

## Rounds 4–6 (2026-11-12) — live walkthroughs on dev, fixes

Rounds 4 and 5 were live walkthroughs of the deployed panel (EN, ZH, 390 px). Round 6 closes the
round-5 leftovers. Each backend fix landed with a test that fails on the commit before it.

**Round 4 (deployed `4ea6bb7f`; format matrix 34/34 on dev):**
- 3D structure fills the frame (`1ee55bf46d`): a principal-axis fit after the canvas has its final
  size. 3Dmol's bounding-sphere `zoomTo` had shown the 5e5z peptide end-on, as a speck.
- Profiler (`262204b088`): the folder kind comes from the roll-up; one note per fact; near-constant
  columns get a neutral note with the reason and are never flagged; column roles.
- Client (`62f2b736e3`, N3–N12):
  - `fake.png` no longer flips from image to text;
  - each fact appears once (kind summaries, AnnData, QC card);
  - the plot defaults to a measurement column;
  - header-only tables show no Run QC and no Edit;
  - the narrow layout wraps and scrolls;
  - kind icons in the tree;
  - the Run full QC tooltip.
- Copy (`f838b9a329`, `1b98e211d8`): group/label findings in experimental-design words, not ML
  jargon; the backend-ahead-of-locale allow-list is empty.

**Round 5 (deployed `64433d94`):**
- Profiler (`80d7235769`):
  - a grouping column nested within the groups (every donor in one condition) is a confounded
    design (`group_nested`), not leakage, and gets no "drop the column" plan;
  - wide count matrices (featureCounts, MAGeCK, Salmon, RSEM) no longer say "no group column" and
    read groups from sample names (`sample_groups_from_names`);
  - VCF, AnnData, Loom and xlsx state each fact once;
  - `columnStats` for BED/GTF and one-row tables.
- Client (`abe5aff115`, `d37e160aea`):
  - "How it shaped the plan" appears only in planning contexts;
  - findings that restate the stat grid are suppressed (code + matching values);
  - the cartoon is fitted to the CA/P trace (5e5z 58% → ≥80% of the limiting axis);
  - plot columns are grouped by role;
  - a "More tabs" chevron when the tab list overflows;
  - zh spacing around interpolated labels;
  - a "No data rows yet" state;
  - JSONL/JSON quick look in the Files tab;
  - a chat started in a project is filed under it at once.
- Copy (`f801ac3688`): plan advice for group-revealing columns ("leave it out of any model that
  predicts the group") and batch columns ("include it in the design as a covariate").

**Round 6 leftovers (`c3c33a8c9d`, merged into devline after the `64433d94` deploy):**
1. FASTQ said the single/paired-end decision in both the note and the plan. The note now states
   the observation (mate present / missing / not checked) and the plan the decision.
2. `leaked_id` could never fire. Under leave-one-out, a value seen once carries no evidence, so a
   unique-per-row column never reached the 0.98 threshold. Near-unique columns are now scored by
   their letter stems (`ctrl_017` → `ctrl`), only when ≥ 2 distinct stems exist. Running IDs
   (`S0001`), hex codes and numbers stay silent (tested). Consequence: a condition-named sample ID
   now raises a watch finding and a "leave it out of the model" plan.
3. The "order-dependent r2 test" was a real profiler bug. The undecodable-byte counter was a codec
   error handler registered under one process-global name, so a second copy of the module took over
   counting, and the copy reading the file saw 0 replaced bytes (a damaged file rated Good). The
   handler name is now unique per module object; all profiler suites pass in one pytest session.
4. Plate well positions (`A01`, `sample_B3`, `plate1_H12`) are no longer read as sample groups;
   `KO1`, `WT1`, `C1/T1` and `ctrl_1` still group.

5. A WT/KO `genotype` column (or a `treatment` column) was not recognised as the group, so the
   table said "no group column was found" (`00377fa3ed`).

**Results on dev `64433d94` (computed by the harnesses):** format matrix **PASS 34 / PARTIAL 0 /
FAIL 0**; `dataset-edit-safety`, `project-file-rename`, `jsonl-nested-tables`, `run-code-outputs`
(1 pass, 1 skip by design), `dataset-panel-full`: pass. The round-6 fixes are not yet deployed.

## Rounds 6–7 (2026-11-12) — live audit fixes, deployed `72e21ca3`

**Round 6 live audit (on `64433d94`)** found 8 items. Two were already fixed in round-6 leftovers
(plate wells; `leaked_id`). Fixed in `2aa0348e3f` (backend), `ec46f77709` + `3b0f4bebeb` (client):
- the small-table note said the group was not checked even when the design check on it ran; it now
  names exactly what was skipped (group balance, the per-column screen);
- PDB lists chain IDs, not a count the stat grid already shows;
- a column with one value in every row is `constant_columns`, not "near-constant (over 99%)", with
  the column badge and the "expected with this few rows" note;
- chat titles are the first sentence (cut at a word boundary with "…"); the Run QC chat is titled
  "QC report: <file>";
- file-row actions are visible on touch devices (`@media (hover:none)`).

Not changed: the zh "： B" spacing was the full-width colon's own width (no space in the text);
nested JSON Lines fields in the Plot need a flattening rule in the rows reader first (open).

**Round 7 live audit (on `72e21ca3`)** confirmed all nine round-6 fixes on dev. Dev e2e: all specs
pass; format matrix 33/34 — `pod5` failed on a transient 502 from the profile proxy, not a profiler
regression (the same file profiles correctly in dev's Galaxy). Dev logs: 2 of 127 profile requests
in 24 h returned 502 within ~20 ms with nothing logged by Galaxy (connection-level failure before the
request reached it; cause not yet confirmed — the logger truncated the detail).

Fixed in round 7 (`bf6e400c63` + follow-up):
- the profile proxy now reports and logs the transport cause of a 502 (`[passthrough] …` lines), so
  the next one is diagnosable;
- a failed profile REQUEST is no longer reported as an unreadable FILE: connection failures and
  502/503 are retried twice (never 4xx, never a backend timeout), then "Couldn't reach the profiler"
  with Try again; 403 says no access;
- zh: no space after "。" before the "expected" qualifier; `constant_columns` / `near_constant` zh
  text no longer carries a count the en text lacks; `label_few_rows` reworded.

## Round 8 (2026-11-12) — deployed `2554e05c`

**Live audit on `0fead9b9`:** all round-7 fixes confirmed. 28 of 28 profile requests returned 200,
so the new "Couldn't reach the profiler" state was not exercised. The zh joins and copy are correct.
These also passed: phone folder and Versions views, a Chinese file name, an empty file (Blocked), a
BOM file. Defects found and fixed:
- **Chinese column headers were never read** (`cada21734f`). `_name_tokens` only tokenised ASCII, so
  `分组` (对照/处理) gave "No group column was found". Each CJK run now maps to the English token of
  the word it ends with: Chinese compounds are head-final, so `实验分组` → group, `样本编号` → id, and
  `处理时间` → nothing. 组 alone is excluded so that `参考基因组` is not read as a group. Tests in
  `test_dataset_audit_r8_20261112.py` (4/4; each failed before the fix).
- **The open object kept its name after a rename or move** (`2a5d0fd918`). The tree now reports its
  file list and folder renames. The data hub follows the open file by id (new name), closes it when
  the file is deleted ("“name” was deleted."), and follows a renamed folder. The profile query key
  includes the name, since the profiler detects the format from the name. The `s3_key` did not go
  stale: a rename keeps id and key.
- **Compare on a phone stuck at "Comparing…"**: not a bug. The compare path does not depend on width;
  the audit captured the screen before the diff response arrived.

**Integration:** dev had meanwhile deployed `ab11d0adca` (chat outputs in per-chat folders,
resizable Data file list, HTML reports, CJK plot fonts, run_code docx/pptx). The sync's ancestry
check refused to drop it. Merging conflicted in `project-file-tree.tsx` (props) and `data-hub.tsx`
(imports); both sides were kept, and tsc plus the data-hub, file-tree and datasets suites passed
(318 passed) before re-gating.
