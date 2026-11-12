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
