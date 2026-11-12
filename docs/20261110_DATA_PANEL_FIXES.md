# 2026-11-10 — Data panel fixes (Track B)

Branch: `track/b-data` → PR into `integration/unmerged-20261110`.
Source analysis: `docs/20261110_EPAR_DATASET_CHAT_UX_REVIEW.md` §4 (D1–D6).
Already shipped before this work and not redone: JSONL profiling, the 100-row preview
sample with sticky header, the upload content type taken from the extension, and the
contradictory "no constant-column issues" note.

## Language rule

The UI shows one language at a time. Every string on the Data surfaces goes through
i18n and has an entry in both `locales/en/common.json` and `locales/zh/common.json`.
New keys live under `perception.*`, `dataset_obj.*` and `data_hub.*`. The unused keys
`data_hub.intro`, `dataset_obj.preview_rows`, `dataset_obj.rows_of` and
`dataset_obj.columns_sample_note` were removed. Dates on these surfaces use the app
locale, not the browser default: previously a zh UI showed "Nov 10".

The profiler used to produce only English sentences. Each note, signal, leakage line and
plan line is now emitted twice:
- as the existing free text, kept for chat context and logs;
- as a structured finding `{section, code, level, params}`.

The QC card renders the findings through `perception.msg.<code>`. It falls back to the
free text only for a profile from an older backend that has no `findings` field.

The test `client/src/components/datasets/data-panel-language.test.tsx` renders the
data-hub header, the file tree (including an upload-failure report), the dataset preview
table, the stat grid and the QC card under both languages:
- **en:** asserts there are no CJK characters in the text, `title`, `placeholder` or `aria-label`.
- **zh:** asserts there are no English words left once data values and proper nouns are removed.

## What changed

### D5 — Folder upload and drag-drop in the project file tree
- **Add menu.** "添加 ▾ → 文件 / 文件夹" (Add ▾ → Files / Folder). The second hidden input has
  `webkitdirectory`, the same attribute set as the chat composer and upload panel.
- **Drop.** Drops go through the shared `lib/folder-drop.ts` (`filesFromDataTransfer`),
  which walks folders recursively with `webkitGetAsEntry`.
- **Root cause of the raw error.** After walking, the helper fell back to
  `dataTransfer.files`. For an empty folder, or one whose reads failed, that fallback
  re-introduced the folder's directory pseudo-file, which surfaced as
  "TypeError: Failed to fetch". It now returns only the walked files. Browsers without the
  entry API go through `readableFiles()`, which drops unreadable untyped pseudo-files.
  This also fixes the same latent bug in the chat composer and the upload panel.
- **One request per file.** Each request carries a `relativePath` field. A failed file does
  not abort the batch.
- **Progress and failures.** The tree shows "Uploading n / N", then a summary. Failures are
  listed per file with a localized reason (413 / no permission / server status / network /
  unreadable), never raw server text. Content dedup is reported.
- **Server** (`server/project-file-paths.ts`, used by the upload and edit routes):
  - The sanitized relative path becomes the stored name and the S3 key under `inputs/`.
    `..`, `.` and control characters are dropped.
  - **Collision fix.** A key segment that loses characters when sanitized gets an 8-hex
    digest. Before this, `数据.csv` and `样本.csv` both became `__.csv`, so the second upload
    overwrote the first file's bytes.
  - multer decodes filenames as latin1, so Chinese names were garbled. Names are now
    re-decoded as UTF-8, and the client also sends the name in the UTF-8 `relativePath` field.
- **Nested tree.** `buildTree` shows nested folders, folders first. Uploaded folders open
  automatically.

### D2 — Full rows, not a sample
- **Backend reader.** `data_perception.read_rows()` is new and uses the same CSV and JSONL
  iterators as the profiler: `_iter_table` and `_iter_jsonl`. `_read_table` and
  `_read_jsonl` were refactored onto these iterators.
- **True row counts.** The profiler's `shape.rows` is now the true total even above
  `MAX_TABLE_ROWS`. `profiledRows` says when statistics cover fewer rows than that.
- **Galaxy endpoint.** `POST /api/perception/rows`.
  - S3 objects are cached on disk, keyed by bucket, key and ETag, with a size/count limit.
    All workers share the cache.
  - A sidecar file stores `{columns, totalRows}`, so later pages stop reading early.
- **Node endpoint.** `GET /api/projects/:id/files/:fileId/rows?offset=&limit=`.
  - Access is owner/member only, the same check as `/url`.
  - The S3 key never reaches the client.
  - Errors map to: 415 not tabular, 422 parse failed, 404 unreadable, 502 backend failure.
- **Shared helper.** `fetchGalaxyAsUser` moved to `server/galaxy-user-fetch.ts`, shared by
  `routes.ts` and `project-routes.ts`.
- **Preview table** (`DatasetRowsTable` and `useDatasetRows`):
  - Rows are windowed and the next page loads on scroll.
  - The footer shows the true total.
  - Sort and filter run on the loaded rows. A label says they cover only the loaded rows
    until every row is loaded. "Load all rows" (up to 100k) makes them apply to the whole file.
- **Columns and Plot views** use the loaded full rows. The note says which rows the stats
  cover: "all N rows" or "the n loaded rows of N".
- **Parquet** is not supported. The profiler cannot read it either, so adding it means a
  pyarrow dependency in both places. Left as a follow-up.

### D3 — QC card
- **i18n.** All strings are localized.
- **Footer.** "Perception is computed by the backend profiler…" is removed.
- **Effective-N reason.** The backend sends `effectiveNReason` and `duplicateRows`. The hint
  states the real reason, for example "1 duplicate rows are counted once". The profiler never
  computes a correlation-based effective N, so it never emits `"correlation"`; the UI string
  exists only for forward compatibility.
- **Hint layout.** The hint wraps over two columns instead of being cropped.
- **Why Watch / Blocked.** A new block lists the findings that set the verdict, with column
  names (for example "near-constant: source").

### D4 — QC placement
The QC block moved from the 溯源 (provenance) tab to the 预览 (preview) tab, directly under
the table. The provenance tab keeps origin and consumers.

### D6 — Data page header
- **Title.** One clean title: a small "数据" crumb over the project name, plus the domain
  badge, translated.
- **Removed.** The duplicate `<h1>数据</h1>`, the lifecycle badge and the intro paragraph.
- **Empty pane.** The empty detail pane is as tall as the file list.
- **Breadcrumb.** The dataset breadcrumb truncates correctly (`min-w-0`, `flex-1`). Its
  tooltip shows the full name instead of the file id.

## Tests

| Command | Result |
|---|---|
| `npx tsc --noEmit -p .` | clean |
| `npx vitest run` | 2673 passed, 3 failed |
| `PYTHONPATH=backend/lib python3.9 backend/lib/galaxy/ai/tests/test_data_perception.py` | 22/22 passed |
| `py_compile` on `data_perception.py` and `perception.py` | OK |

The 3 vitest failures are in `server/adhoc-analysis-routing.test.ts` and
`server/doc-code-drift.test.ts`. Both read files that are not in this sparse checkout
(`evaluation/…`, `backend/database/galaxy_ai_tools.db`). They are unrelated to this change.

The full Galaxy module import could not run locally because `beaker` is missing from the
local environment. Instead, `perception.py` was exercised with a stubbed `Router`:
`perception_rows` returned 2,281 rows × 5 columns for the EPAR JSONL file.

New and updated tests:
- `server/project-file-rows-upload.test.ts`
- `client/src/components/project-file-tree.folders.test.tsx`
- `client/src/components/datasets/dataset-rows.test.tsx`
- `client/src/components/datasets/data-panel-language.test.tsx`
- `client/src/components/data-perception.test.tsx`
- `dataset-object.provenance.test.tsx`
- `pages/__tests__/data-hub.test.tsx`
- `project-routes.test.ts` (endpoint count 33)
- 8 new Python tests

## Verify on dev after deploy (needs both the backend and the frontend)
1. **EPAR file.** Upload `epar_study_tables.jsonl`. Expect:
   - the table shows "200 / 2,281" and loads more on scroll;
   - the QC card sits under the table and reads "需关注" (Watch) because `source` is near-constant;
   - the Effective-N hint names 1 duplicate row.
2. **Folder pick and drop.** Pick and drop a nested folder. The tree shows the folders, and no
   "Failed to fetch" appears. Upload an empty folder: nothing happens.
3. **Chinese file names.** Upload `数据.csv` and `样本.csv`: both keep their names and their own bytes.
4. **Language switch.** Switch the language between zh and en and check the Data page for
   mixed text.
5. **Rows cache.** Confirm `/tmp/perception_rows_cache` stays within its limit on
   `biomate-galaxy-dev`.

## Open items
- Parquet rows, which needs pyarrow in both the profiler and the reader.
- `import-url` still keys its S3 object by the lossy basename. The collision-safe key builder
  is not applied there yet.
- D7 (sidebar "新对话" / Notes card) is outside Track B.
