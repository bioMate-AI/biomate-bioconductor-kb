# Test Plan — DataHub / Dataset-Object / Models Surfaces

**Date:** 2026-09-09
**Branch:** `integration/dev-test` (workspace `/Users/kky/biomate-review`)
**Scope:** the data-centric UI surfaces — the `/files` DataHub, the dataset-as-object detail (`DatasetObject`), and the `/models` Models surface (`ModelsPanel`, `ModelObject`, `RunPretrained`, `InferenceResultView` + the four wave-1 viewers).

All `data-testid`s, routes, tab names, endpoints and visible copy in this plan were extracted verbatim from the real components — nothing is invented. Where the code leaves a behaviour undeterminable from source alone, it is flagged in the **Open questions / undeterminable** section at the bottom.

---

## Component / route map (source of truth)

| Surface | Route | Component file |
|---|---|---|
| DataHub page | `/files` (`App.tsx:673`) | `frontend/client/src/pages/data-hub.tsx` |
| Project file tree | (inside DataHub) | `frontend/client/src/components/project-file-tree.tsx` |
| Dataset object | (inside DataHub detail pane) | `frontend/client/src/components/datasets/dataset-object.tsx` + `datasets-api.ts` |
| Quality panel | (Dataset "Quality" tab) | `frontend/client/src/components/data-perception.tsx` |
| Models panel | `/models` (`App.tsx:654`) | `frontend/client/src/components/models/models-panel.tsx` |
| Model object | (inside Models, Registry row click / track links) | `frontend/client/src/components/models/model-object.tsx` |
| Run pre-trained | (Models track 3) | `frontend/client/src/components/models/run-pretrained.tsx` |
| Inference result | (RunPretrained result body) | `frontend/client/src/components/models/inference-result.tsx` |
| Wave-1 viewers | (dispatched by evidence class) | `viewers/plddt-chart.tsx`, `pae-heatmap.tsx`, `seq-tracks.tsx`, `hit-grid.tsx` |

### Endpoints (all credentialed; proxied to Galaxy via `server/routes.ts`)

| Endpoint | Method | Consumer | Notes |
|---|---|---|---|
| `/api/projects` | GET | `useActiveProject()` | project picker cards |
| `/api/projects/:id/files` | GET | `ProjectFileTree.load()` | returns `{ files: ProjectFile[] }` |
| `/api/projects/:id/files/upload` | POST (FormData) | upload | source `upload` |
| `/api/projects/:id/files/:fid` | DELETE | delete row | `source==='upload'` only |
| `/api/projects/:id/files/:fid/url` | GET | download / preview | returns `{ url, name }` |
| `/api/perception/profile` | POST `{ datasetRef, name }` | QualityDot + Preview + Quality | returns `DataProfile` (+ `planImpact`, `columns`, `sampleRows`, `quality`) |
| `/api/datasets/:ref/lineage` | GET | Lineage tab | `{ available, source, producedBy }` |
| `/api/datasets/:ref/consumers` | GET | Consumers tab | `{ consumers: RunLabel[] }` |
| `/api/datasets/:ref/versions` | GET / POST `{ note }` | Versions tab | append-only |
| `/api/datasets/:ref/ro-crate` | GET (blob) | Export RO-Crate | downloads `<name>-ro-crate-metadata.json` |
| `/api/models` | GET | Registry / RunPretrained / count | `ModelSummary[]` |
| `/api/models/:id` | GET | ModelObject | `ModelDetail` |
| `/api/models/:id/infer` | POST `{ inputs }` | RunPretrained | `{ run_id }` |
| `/api/inference/:runId/result` | GET (polled 1500 ms) | RunPretrained | `InferenceResult` (by evidence class; may be `stub`) |
| `/api/model-tracks/train` | GET | Train track | `{ runs: [] }` honest-empty |
| `/api/model-tracks/adapt` | GET | Adapt track | `{ pairs: [], pendingCount }` |
| `/api/model-tracks/adapt/:pairId/toggle` | POST | Adapt toggle | persisted override |
| `/api/model-tracks/adapt/retrain` | POST | Adapt retrain | queues training job |
| `/api/model-tracks/optimise` | GET | Optimise track | `undefined` when `{active:false}` |

---

## Coverage checklist

| # | Surface | Element / state | UC |
|---|---|---|---|
| 1 | DataHub | Project picker loading state | UC-DH-01 |
| 2 | DataHub | Project picker empty (no projects) | UC-DH-02 |
| 3 | DataHub | Project picker grid + card fields | UC-DH-03 |
| 4 | DataHub | Pick project → two-pane hub | UC-DH-04 |
| 5 | DataHub | Change project button | UC-DH-05 |
| 6 | DataHub | Detail-pane empty (no selection) | UC-DH-06 |
| 7 | DataHub | Breadcrumb / header badges | UC-DH-07 |
| 8 | FileTree | Loading / error / empty ("No files yet") | UC-FT-01 |
| 9 | FileTree | inputs/ + outputs/<run> folders + expand/collapse | UC-FT-02 |
| 10 | FileTree | Quality dot: profilable good/watch/blocked/unknown + non-profilable grey | UC-FT-03 |
| 11 | FileTree | Open dataset (file name button) | UC-FT-04 |
| 12 | FileTree | Copy S3 path / Download / Delete (upload only) | UC-FT-05 |
| 13 | FileTree | Inline preview (image / CSV table / text) + input_context | UC-FT-06 |
| 14 | FileTree | Upload (picker + drag-drop) + refresh | UC-FT-07 |
| 15 | Dataset | Header identity + RO-Crate + Download buttons | UC-DS-01 |
| 16 | Dataset | Preview tab: data table + identity rows | UC-DS-02 |
| 17 | Dataset | Quality tab: perception panel good/watch/blocked | UC-DS-03 |
| 18 | Dataset | Quality tab: no-ref / loading / error | UC-DS-04 |
| 19 | Dataset | Lineage tab: produced-by / prop-fallback / uploaded | UC-DS-05 |
| 20 | Dataset | Consumers tab: live / prop / empty | UC-DS-06 |
| 21 | Dataset | Versions tab: list / prop / empty + append note | UC-DS-07 |
| 22 | Dataset | Origin tab | UC-DS-08 |
| 23 | Dataset | Export RO-Crate success + error | UC-DS-09 |
| 24 | Models | Header, count badge, 5 track tabs | UC-MP-01 |
| 25 | Models | Registry: loading / error / empty / table | UC-MP-02 |
| 26 | Models | Registry row → ModelObject takeover | UC-MP-03 |
| 27 | Models | Train track: loop + runs (empty/list) + families | UC-MP-04 |
| 28 | Models | Adapt track: ladder + learned pairs + toggle + retrain | UC-MP-05 |
| 29 | Models | Optimise track: empty vs running (rounds/proposal/verdicts) | UC-MP-06 |
| 30 | ModelObject | Evidence gate: pass / fail / not_evaluated | UC-MO-01 |
| 31 | ModelObject | Lineage / Used-by / Interface / Versions | UC-MO-02 |
| 32 | ModelObject | Loader loading / error | UC-MO-03 |
| 33 | RunPretrained | Domain pick (structure/genomic/chemical) + model resolve | UC-RP-01 |
| 34 | RunPretrained | Submit → poll running → completed | UC-RP-02 |
| 35 | RunPretrained | Failed inference | UC-RP-03 |
| 36 | RunPretrained | Stub result banner | UC-RP-04 |
| 37 | Viewers | Structure: PlddtChart + PaeHeatmap (+ empty) | UC-VW-01 |
| 38 | Viewers | Genomic: SeqTracks (+ flagged) | UC-VW-02 |
| 39 | Viewers | Chemical: HitGrid table/grid + held rows | UC-VW-03 |
| 40 | RunPretrained | No-model-registered honest state | UC-RP-05 |

Preconditions across the whole plan: authenticated fixture `lifeifei163361@163.com` (see project `CLAUDE.md`), routes wrapped in `AuthenticatedPageLayout`. E2E must hit the live backend (no `page.route` mocks per project rule).

---

## `##` DataHub page — `frontend/client/src/pages/data-hub.tsx`

Purpose: two-pane data hub at `/files`. When no project is active it shows a project picker (`data-testid="data-hub-picker"`); once a project is active it shows a persistent file tree (`ProjectFileTree`) beside a detail pane that renders the selected file as a `DatasetObject`. Root container: `data-testid="data-hub"`.

### UC-DH-01 · Project picker — loading
- **Preconditions/state:** `useActiveProject().loading === true`, no `activeProjectId`.
- **Input:** navigate to `/files`; projects fetch in flight.
- **Action flow:**
  1. Load `/files`.
  2. Observe the picker before `/api/projects` resolves.
- **Expected output:** `data-hub-picker` card renders copy `Loading projects…`.
- **Information flow:** `useActiveProject()` GET `/api/projects` (pending) → `ProjectPicker(loading=true)` renders the loading card.
- **Pass criteria:** `data-hub-picker` visible with "Loading projects…"; no project grid, no panes.
- **Edge/error cases:** slow network keeps the loading card; fetch error resolves to `loading=false` (falls through to empty or grid depending on `projects`).

### UC-DH-02 · Project picker — no projects (honest empty)
- **Preconditions/state:** `loading===false`, `projects.length===0`.
- **Input:** authenticated account with zero projects.
- **Action flow:** 1. Load `/files`. 2. Wait for `/api/projects`.
- **Expected output:** `data-hub-picker` shows `No projects yet` heading + copy `A project holds your datasets, runs and models…` with `FolderOpen` icon.
- **Information flow:** `/api/projects` → `[]` → empty branch.
- **Pass criteria:** empty-state copy present; no `data-hub-project-grid`.
- **Edge/error cases:** none beyond empty.

### UC-DH-03 · Project picker — grid + card fields
- **Preconditions/state:** `projects.length>0`, no active project.
- **Input:** account with ≥1 project.
- **Action flow:** 1. Load `/files`. 2. Inspect the grid.
- **Expected output:** header `Choose a project`; grid `data-testid="data-hub-project-grid"`; per project a button `data-testid="data-hub-project-<id>"` with status dot (emerald=active / sky=completed / muted=archived, via `STATUS_DOT`), name, optional description (`line-clamp-2`), status badge (capitalized), optional `primaryDomain` badge, optional created date (`formatDate`).
- **Information flow:** `/api/projects` → `projects.map` → card buttons; `p.status`→dot colour, `p.createdAt`→`formatDate`.
- **Pass criteria:** one card per project; only real fields shown (no fabricated domain/description when absent).
- **Edge/error cases:** invalid `createdAt` → `formatDate` returns null → no date span; unknown status → falls to `STATUS_DOT.archived` (muted dot).

### UC-DH-04 · Pick a project → two-pane hub
- **Preconditions/state:** picker shown.
- **Input:** click a project card.
- **Action flow:** 1. Click `data-hub-project-<id>` → `onPick(id)` → `setActiveProjectId`. 2. Observe panes.
- **Expected output:** `data-testid="data-hub-panes"` grid `[300px_1fr]`; left = `ProjectFileTree` (`project-file-tree`), right = detail-empty (`data-hub-detail-empty`) until a file is picked. Header now shows breadcrumb `Data / <project name>` and status/domain badges.
- **Information flow:** `activeProjectId` set → `useEffect` clears `selected` → `ProjectFileTree` mounts and GETs `/api/projects/:id/files`.
- **Pass criteria:** two panes render; selection cleared on project change.
- **Edge/error cases:** switching projects mid-selection clears `selected` (file id from another project is meaningless).

### UC-DH-05 · Change project
- **Preconditions/state:** active project + panes shown.
- **Input:** click `data-hub-change-project`.
- **Action flow:** 1. Click "Change project". 2. Observe return to picker.
- **Expected output:** `setSelected(null)` + `setActiveProjectId(null)` → `ProjectPicker` returns.
- **Information flow:** state reset → conditional renders `ProjectPicker`.
- **Pass criteria:** picker visible again; no stale detail pane.

### UC-DH-06 · Detail pane — no selection (honest prompt)
- **Preconditions/state:** active project, `selected===null`.
- **Input:** none (default after picking a project).
- **Expected output:** `data-hub-detail-empty` card with `Select a dataset` + copy `Pick a file from the tree to open it as an object…` and `Database` icon.
- **Information flow:** `selected===null` branch renders the empty card (not a blank pane).
- **Pass criteria:** prompt visible; no `dataset-object` in the DOM.

### UC-DH-07 · Header breadcrumb + badges
- **Preconditions/state:** active project.
- **Expected output:** breadcrumb `Data` + `/ <activeProject.name>`; title `Data`; `activeProject.status` badge (capitalized); optional `primaryDomain` badge; description paragraph "Every dataset is an object…".
- **Information flow:** `activeProject` fields → header spans/badges.
- **Pass criteria:** name/status/domain match the active project record.
- **Edge/error cases:** no active project → breadcrumb shows only `Data`, no change-project button.

---

## `##` Project file tree — `frontend/client/src/components/project-file-tree.tsx`

Purpose: VS Code / Jupyter style browser of a project's files (`inputs/` + `outputs/<runId>/`). Root: `data-testid="project-file-tree"`. Each file row carries a lazy per-row ingest-quality dot and Open / Copy / Download / Delete affordances.

### UC-FT-01 · Loading / error / empty
- **Preconditions/state:** file list fetch in flight, then error, then empty.
- **Input:** project with no files (empty case).
- **Action flow:** 1. Mount tree → `load()` GET `/api/projects/:id/files`. 2. Observe states.
- **Expected output:**
  - Loading: refresh button spinner (`project-files-refresh-btn` icon animates); no rows.
  - Error: red `error` div with server message (from `!res.ok` → `res.text()`).
  - Empty (`tree.length===0 && !error`): `Folder` icon + `No files yet` + `Drag & drop or click Upload`.
- **Information flow:** `/api/projects/:id/files` → `data.files` → `buildTree()`; empty array → `[]` → empty branch.
- **Pass criteria:** each state renders honestly; empty state not shown while loading.
- **Edge/error cases:** non-OK response text surfaces as the error string.

### UC-FT-02 · Folders (inputs / outputs) + expand/collapse
- **Preconditions/state:** files with `source==='upload'` and `source==='run_output'` (with `run_id`).
- **Expected output:** `inputs` folder (`folder-inputs`) always expanded by default (`expandedFolders` seeded with `"inputs"`); one folder per run `folder-outputs/<runId>` labelled `"<workflow_name> · <Mon D HH:MM>"` (from first file's `workflow_name` + `created_at`); each `FolderRow` shows child count on the right.
- **Action flow:** 1. Click a `FolderRow` → toggles `expandedFolders`. 2. Observe children mount/unmount.
- **Information flow:** `buildTree()` groups by source/run → `FolderRow` + `FileRow` children.
- **Pass criteria:** run folders labelled with workflow + timestamp; toggle adds/removes the path from the set.
- **Edge/error cases:** run with missing `workflow_name` → label `"Workflow · …"`; missing `created_at` → `runId.slice(0,8)` timestamp fallback; `run_id` null → grouped under `"unknown"`.

### UC-FT-03 · Quality dot (lazy `/api/perception/profile`)
- **Preconditions/state:** file rows of profilable (`csv/tsv/txt/tab/vcf/fastq/fq/gz`, incl. `.fastq.gz` two-token check) and non-profilable types.
- **Action flow:** 1. Render a profilable row → `useEffect` POSTs `/api/perception/profile` `{ datasetRef: s3_key, name }`. 2. Response `{ quality }` sets the dot.
- **Expected output:** `data-testid="file-quality-<id>"` with `data-quality` attribute:
  - `good`→emerald, `watch`→amber, `blocked`→red, `unknown`→muted grey (via `QUALITY_DOT`).
  - Non-profilable rows never fetch → stay `unknown` grey; `title="Ingest quality: not profiled (unsupported file type)"`.
  - Profilable title `Ingest quality: <quality>`.
- **Information flow:** `isProfilable(file)` gate → POST profile → `d.quality` (string) → `setQuality` → dot class + `data-quality`.
- **Pass criteria:** dot colour matches returned verdict; `data-quality` reflects it; unsupported types never call the endpoint.
- **Edge/error cases:** profile fetch fails / non-OK / non-string quality → stays `unknown` (catch keeps grey); component unmount cancels via `cancelled` flag.

### UC-FT-04 · Open dataset (file-name button)
- **Preconditions/state:** DataHub passes `onOpenDataset`; `canEdit` true.
- **Input:** click a file name.
- **Action flow:** 1. Click `data-testid="file-open-<id>"`. 2. `onOpenDataset(file)` → DataHub `setSelected(file)` → `DatasetObject` mounts in the right pane.
- **Expected output:** file name is a button (`hover:underline`, `title="Open dataset"`); detail pane swaps from empty to `dataset-object`.
- **Information flow:** `ProjectFile` → `toDatasetRef()` → `DatasetObject` prop.
- **Pass criteria:** clicking the name opens the object; when `onOpenDataset` is absent the name is a plain non-clickable span.
- **Edge/error cases:** a `step_name` shows a blue mono chip beside the name (`title="Produced by step: <name>"`).

### UC-FT-05 · Copy S3 path / Download / Delete
- **Preconditions/state:** hover a file row (action buttons are `opacity-0 group-hover:opacity-100`).
- **Action flow:**
  1. Click `file-copy-<id>` → clipboard write of `s3_key`; icon flips to green `Check` for 1.5 s; if `onPickFile` set, fires it.
  2. Click `file-download-<id>` → GET `/api/projects/:id/files/:fid/url` → presigned URL → anchor click (or desktop native save).
  3. Click `file-delete-<id>` (only when `source==='upload' && canEdit`) → `confirm()` → DELETE → row removed.
- **Expected output:** copy check icon toggles; download triggers a file save; delete removes the row after confirm.
- **Information flow:** copy → `navigator.clipboard`; download → `/url` endpoint → `{url,name}`; delete → DELETE → `setFiles` filter + `onFilesChanged`.
- **Pass criteria:** delete button absent on `run_output` rows and when `canEdit===false`; download uses the presigned URL.
- **Edge/error cases:** download/delete non-OK → `error` state string set; delete `confirm()` cancel → no request.

### UC-FT-06 · Inline preview + input_context
- **Preconditions/state:** file with previewable ext (`csv/tsv/txt/log/md/png/jpg/jpeg/gif/webp/svg`) AND `size < 1 MB` (`canPreview`).
- **Action flow:** 1. Click the Eye toggle (only shown when `showPreview`). 2. First open fetches `/url`, then `FilePreview` renders.
- **Expected output:**
  - Image ext → `<img>` thumbnail (max 200px).
  - CSV/TSV → HTML table of first 6 lines (header row bold/muted).
  - Other text → `<pre>` of first 20 lines.
  - If `input_context.intent` or `inputFiles` present → italic intent quote + "Input files: …" block.
- **Information flow:** `/url` → `previewUrl` → `FilePreview` fetches `.text()` (non-image) → split/limit → table or pre.
- **Pass criteria:** correct render per ext; preview toggle hidden for non-previewable / ≥1 MB files.
- **Edge/error cases:** text fetch fails → `(preview failed)`; loading → `Loading…`.

### UC-FT-07 · Upload (picker + drag-drop) + refresh
- **Preconditions/state:** `canEdit===true`.
- **Action flow:**
  1. Click `project-files-upload-btn` → hidden `project-files-input` file dialog → `handleUpload` POSTs each file to `/files/upload` → `load()`.
  2. Drag files onto the tree → `dragOver` ring + "Drop files to upload" overlay → drop → `handleUpload`.
  3. Click `project-files-refresh-btn` → `load()`.
- **Expected output:** uploading shows spinner on the Upload button; on success the new files appear; drop overlay appears only while `dragOver`.
- **Information flow:** FormData POST `/files/upload` → reload GET `/files`; also listens for `window` event `biomate:project-files-updated` to auto-refresh.
- **Pass criteria:** uploads reload the tree; `canEdit===false` hides Upload and blocks drop.
- **Edge/error cases:** upload non-OK → `error` string; desktop path uses `desktopPickAndUpload`.

---

## `##` Dataset object — `frontend/client/src/components/datasets/dataset-object.tsx` + `datasets-api.ts`

Purpose: a file rendered as a first-class object. Root: `data-testid="dataset-object"`. Header: breadcrumb (`Data / Inputs|Outputs / <id>`), name (mono), content-type + size badges, `Export RO-Crate` + `Download` buttons. Six tabs: **Preview · Quality · Lineage · Consumers · Versions · Origin** (`defaultValue="preview"`). Lineage/Consumers/Versions lazily fetch on first open; Preview/Quality share the perception profile (fetched on mount).

### UC-DS-01 · Header identity + action buttons
- **Preconditions/state:** a `DatasetRef` with name/size/contentType; `dataset.ref` set; `onDownload` provided.
- **Expected output:** `dataset-object-id` (mono id), `dataset-object-name`, contentType badge (when set), size badge (`formatBytes`), `dataset-object-rocrate` (only when `dataset.ref` truthy), `dataset-object-download` (only when `onDownload` provided). Breadcrumb shows `Outputs` when `source==='run_output'` else `Inputs`. `dataset-object-back` present when `onBack`.
- **Information flow:** `DatasetRef` fields → header; `isRunOutput = source==='run_output'`.
- **Pass criteria:** identity fields non-fabricated; RO-Crate hidden when `ref` null.
- **Edge/error cases:** null size → badge `—`; null contentType → no badge.

### UC-DS-02 · Preview tab (data table + identity)
- **Preconditions/state:** perception profile returns `columns` + `sampleRows`.
- **Action flow:** 1. Object opens (default Preview). 2. `usePerceptionProfile(ref,name)` resolves.
- **Expected output:** `dataset-preview`; when `columns.length && sampleRows.length` → `dataset-preview-table` HTML table (header from `columns`, rows from `sampleRows`, cells `r[ci] ?? ""`) + caption `First N rows[ of <shape.rows>]`. Below always: identity `Row`s — `Name`, `Size`, `Type`, `Reference` — then the "A dataset is an object…" note.
- **Information flow:** POST `/api/perception/profile` → `profile.columns`/`sampleRows`/`shape.rows` → table; `dataset` fields → identity rows.
- **Pass criteria:** table renders only when both columns and rows present; identity rows always render.
- **Edge/error cases:** no columns/rows (e.g. non-tabular) → only identity rows; profile error → identity rows still render (table skipped).

### UC-DS-03 · Quality tab — perception panel (good / watch / blocked)
- **Preconditions/state:** `dataset.ref` set; profile resolved with a `quality` verdict.
- **Action flow:** 1. Click `dataset-tab-quality`. 2. `DataPerception` mounts with `profile`, `planImpact`, `datasetName`.
- **Expected output:** `dataset-quality` wraps `data-perception` (`data-quality="good|watch|blocked"`):
  - `perception-quality-badge` label **Good** (emerald+CheckCircle) / **Watch** (amber+AlertTriangle) / **Blocked** (red+XCircle).
  - Stat strip: Rows, Columns, optional `perception-effective-n` (with "below row count…" hint when `effectiveN < rows`).
  - Optional `perception-leakage`, `perception-class-balance`, `perception-signal`, `perception-notes`, `perception-plan-impact` (each rendered only when its data present).
  - Footer provenance note "Perception is computed by the backend profiler at ingest…".
- **Information flow:** shared `profile` from `usePerceptionProfile` → `DataPerception`; `profile.planImpact` → plan-impact block.
- **Pass criteria:** each of the three verdicts renders the matching badge/icon/colour and `data-quality`; only present sections show.
- **Edge/error cases:** covered by UC-DS-04 (no-ref / loading / error).

### UC-DS-04 · Quality tab — no-ref / loading / error
- **Preconditions/state:** three variants: `dataset.ref===null`; profile `isLoading`; profile `isError || !profile`.
- **Expected output:**
  - No ref: `dataset-quality-noref` — "No resolvable reference — quality profiling is not available for this dataset."
  - Loading: `dataset-quality-loading` skeletons.
  - Error: `dataset-quality-error` — "Quality not available — the profiler could not read this dataset."
- **Information flow:** `usePerceptionProfile(ref)` `enabled: !!ref`, `retry:false` → `isLoading`/`isError` branches.
- **Pass criteria:** each branch shows its honest state; no fabricated verdict.

### UC-DS-05 · Lineage tab (produced-by / prop-fallback / uploaded)
- **Preconditions/state:** three variants.
- **Action flow:** 1. Click `dataset-tab-lineage` → `setLineageOpened(true)` → `useDatasetLineage(ref)` GET `/api/datasets/:ref/lineage`.
- **Expected output:** `dataset-lineage`:
  - Loading: `dataset-lineage-loading` skeletons.
  - `available && producedBy` → Rows: Produced-by run, Workflow (`producedBy.workflow ?? dataset.workflowName`), Status, Step + note "This dataset was written by a workflow run…".
  - Else if `isRunOutput` (backend has no surviving provenance) → Rows from `dataset.runId/workflowName/stepName` + note "live provenance is no longer retained for this run."
  - Else → `dataset-lineage-uploaded` — "Uploaded input — no upstream workflow produced this dataset."
- **Information flow:** `/lineage` → `{available, producedBy}` → produced-by branch; falls back to prop refs; else uploaded.
- **Pass criteria:** correct branch per lineage availability; never a fabricated run id.
- **Edge/error cases:** fetch error (`retry:false`) → not loading, `data` undefined → falls to prop/uploaded branch by `isRunOutput`.

### UC-DS-06 · Consumers tab (live / prop / empty)
- **Action flow:** 1. Click `dataset-tab-consumers` → `setConsumersOpened(true)` → GET `/api/datasets/:ref/consumers`.
- **Expected output:** `dataset-consumers`:
  - Loading: `dataset-consumers-loading` skeletons.
  - Live consumers → row per `dataset-consumer-<runId>` with "reads" badge, `workflow ?? runId` mono, optional status badge.
  - Else prop consumers (`dataset.consumers`) → `dataset-consumer-<c>` rows.
  - Else → `dataset-no-consumers` — "No runs are recorded as reading this dataset yet."
  - Always: note "When consumers are recorded, replacing a dataset becomes a decision with a visible blast radius…".
- **Information flow:** `/consumers` → `consumers[]` → rows; fallback to prop list; else empty.
- **Pass criteria:** correct source precedence (live > prop > empty); each row keyed by runId.

### UC-DS-07 · Versions tab (list / prop / empty) + append note
- **Action flow:**
  1. Click `dataset-tab-versions` → `setVersionsOpened(true)` → GET `/api/datasets/:ref/versions`.
  2. Type a note into `dataset-version-note-input`; press Enter or click `dataset-version-add-button` → POST `/api/datasets/:ref/versions` `{ note }`.
- **Expected output:** `dataset-versions`:
  - Loading: `dataset-versions-loading`.
  - Live versions → `dataset-version-<version>` cards (label bold mono, `current` badge when `v.current`, formatted `createdAt`, optional note + author).
  - Else prop versions → `dataset-version-<v>` simple rows.
  - Else → `dataset-no-versions` — "Version history is not available yet — only the current dataset is recorded."
  - Append UI (only when `dataset.ref`): `dataset-version-add` block; button label "Adding…" while pending; disabled when note empty; on success clears the note; error → `dataset-version-add-error`; note "Version entries are append-only…".
- **Information flow:** GET `/versions` → list; POST returns fresh list (seeded into cache via `setQueryData`); backend 200 with `error` field → thrown → `dataset-version-add-error`.
- **Pass criteria:** appended entry appears without a full refetch; a rejected/empty note surfaces the error; prior entries never rewritten.
- **Edge/error cases:** empty/whitespace note → button disabled + no request (`note.trim()` guard); POST non-OK → mutation error.

### UC-DS-08 · Origin tab
- **Expected output:** `dataset-origin` Rows: Source (`dataset.source`), Storage ref (`dataset.ref`, mono), Added (`createdAt` localized or `—`).
- **Information flow:** `dataset` fields → Rows.
- **Pass criteria:** values reflect the ref; no fetch.

### UC-DS-09 · Export RO-Crate (success + error)
- **Preconditions/state:** `dataset.ref` set.
- **Action flow:** 1. Click `dataset-object-rocrate` → `downloadDatasetRoCrate(ref,name)` GET `/api/datasets/:ref/ro-crate` (blob). 2. Save `<sanitized-name>-ro-crate-metadata.json`.
- **Expected output:** button toggles to "Exporting…" while pending; on error `dataset-rocrate-error` shows the message; success triggers a JSON download.
- **Information flow:** blob → object URL → anchor click → revoke.
- **Pass criteria:** file downloads with the correct name; non-OK surfaces the error (no silent failure).
- **Edge/error cases:** `ref` null → button not rendered → export unreachable; fetch non-OK → thrown "<status>: failed to export RO-Crate".

---

## `##` Models panel — `frontend/client/src/components/models/models-panel.tsx`

Purpose: the 5-track Models surface at `/models`. Root: `data-testid="models-panel"`. Tracks (order fixed by `MODELS_TRACKS`): `models-track-0` **Train**, `-1` **Adapt**, `-2` **Optimise**, `-3` **Run a pre-trained model**, `-4` **Registry**. Opening a model (Registry row / track link) replaces the whole surface with `ModelObjectLoader`.

### UC-MP-01 · Header + count + track tabs
- **Preconditions/state:** authenticated at `/models`.
- **Expected output:** breadcrumb `<project> / Models`; title `Models`; `models-count` badge `"<N> registered"` (N from `useModels().length`, 0 when empty). `models-tabs` list with five triggers `models-track-0..4` each with an icon + label.
- **Information flow:** GET `/api/models` → `models.length` → count badge; tab index drives `TabsContent`.
- **Pass criteria:** five tracks present; count reflects `/api/models`.
- **Edge/error cases:** `/api/models` non-array / error → `useModels` returns `[]` → count `0 registered`.

### UC-MP-02 · Registry — loading / error / empty / table
- **Action flow:** 1. Open track 4 (`models-track-4`). 2. `useModels` resolves.
- **Expected output:** `TabsContent value="4"` → `RegistryTrack`:
  - Loading: `registry-loading` skeletons.
  - Error: `registry-error` — "Could not load the model registry."
  - Empty: `registry-empty` — "No models registered in this account yet…".
  - Populated: `registry-track` + `registry-table` with header (Model / Family / Origin / Used by) and a `registry-row-<id>` button per model (name + version, family, origin, `usedByCount`, chevron).
- **Information flow:** GET `/api/models` → `ModelSummary[]` → rows.
- **Pass criteria:** correct branch; rows show real summary fields.

### UC-MP-03 · Registry row → ModelObject takeover
- **Action flow:** 1. Click `registry-row-<id>` → `onOpenModel(id)` → `setOpenModelId(id)`. 2. Panel renders `ModelObjectLoader`.
- **Expected output:** `models-panel` now contains `ModelObjectLoader` (loading → `model-object`); `model-object-back` returns to the tracks.
- **Information flow:** `openModelId` truthy → early return renders loader → GET `/api/models/:id`.
- **Pass criteria:** clicking a row opens the object; Back restores the last track.

### UC-MP-04 · Train track — loop + runs + families
- **Action flow:** 1. Open `models-track-0`. 2. `useTrainTrack(project)` GET `/api/model-tracks/train`.
- **Expected output:** `track-train`:
  - `train-loop` with 4 fixed steps `train-loop-step-0..3` (Dataset / Train / Quality gate / Register).
  - `train-runs`: when `runs.length` → `train-run-<name>` cards (name, family badge, `when`, status badge `train-run-status-<name>` coloured by `trainStatusColor`: completed=green/failed=red/running=blue/other=grey; metric badge, gate badge, dataset mono; running/`modelId` → `train-run-open-<name>` "watch live →" / "open experiment →"; optional version line). When empty → `train-runs-empty` — "This project hasn't trained a model yet…".
  - `train-families`: 4 fixed cards (Language / Tabular AutoML / Diffusion / Molecular property).
- **Information flow:** `/api/model-tracks/train` → `{runs:[]}` honest-empty → empty state; loop + families are fixed design content (always render).
- **Pass criteria:** loop + families always render; runs list reflects backend (never fabricated).
- **Edge/error cases:** no runs → empty copy; `open experiment` fires `onOpenModel(modelId)` only when `modelId` set.

### UC-MP-05 · Adapt track — ladder + learned pairs + toggle + retrain
- **Action flow:** 1. Open `models-track-1`. 2. `useAdaptTrack` GET `/api/model-tracks/adapt`. 3. Toggle a pair; click retrain.
- **Expected output:** `track-adapt`:
  - `adapt-levels`: fixed 3-rung ladder (Prompt rule / Few-shot index / Trained adapter) + `adapt-retrain` button "Re-train on my edits[ (<pendingCount>)]".
  - `adapt-learned`: when `pairs.length` → `adapt-pair-<id>` cards (learned label, scope badge, `adapt-pair-toggle-<id>` switch `aria-checked=on`, before→after `adapt-pair-before-<id>` (strikethrough red) → `adapt-pair-after-<id>` (green), source line; `opacity-60` when off) + "<active> of <total> active". When empty → `adapt-learned-empty` — "Nothing learned yet…".
  - Toggle click → `effectiveAdaptToggle` → `useAdaptToggle` POST `/api/model-tracks/adapt/:pairId/toggle` (unless parent `onAdaptToggle` passed).
  - Retrain click → `effectiveAdaptRetrain` → POST `/api/model-tracks/adapt/retrain`.
- **Information flow:** `/adapt` → `{pairs, pendingCount}`; toggle/retrain mutations invalidate the adapt (and train, for retrain) queries.
- **Pass criteria:** toggle flips `aria-checked` + opacity; retrain fires the POST; empty state honest.
- **Edge/error cases:** no pending → button has no count suffix; parent-supplied callbacks override the persisted mutations.

### UC-MP-06 · Optimise track — empty vs running
- **Action flow:** 1. Open `models-track-2`. 2. `useOptimiseTrack` GET `/api/model-tracks/optimise`.
- **Expected output:** `track-optimise`:
  - No data (`{active:false}` → `undefined`): `optimise-empty` — "No optimisation loop is running in this project yet…" + 4 bullet design points.
  - Running: `optimise-loop` (header `optimise-loop-state` "running · round N" green / "stopped" grey; `optimise-surrogates` with `optimise-surrogate-<id>` links; optional Budget / Refit policy; `optimise-rounds` → `optimise-round-<round>` rows) + `optimise-proposal` (`optimise-proposal-table`; `optimise-proposal-<id>` rows with candidate, score, confidence, `optimise-proposal-verdict-<id>` coloured by `proposalVerdictColor`: accepted=green / reject*=red / else=amber; empty proposal → "No proposal for this round yet.").
- **Information flow:** `/optimise` → `undefined` when inactive → empty state; else full `OptimiseData`.
- **Pass criteria:** empty and running states both correct; a rejected proposal stays listed with red verdict (safety-gate reason preserved).
- **Edge/error cases:** surrogate click → `onOpenModel(id)`; body not an array of rounds → treated as inactive.

---

## `##` Model object — `frontend/client/src/components/models/model-object.tsx`

Purpose: a model as an object (identity + 5 tabs). Root: `data-testid="model-object"` (loaded via `ModelObjectLoader`). Header: breadcrumb `Models / Registry / <id>`, name+version, family badge, optional confidence-band badge, origin, `model-object-supersede` + `model-object-use-in-run` buttons. Tabs: **Evidence · Lineage · Used by · Interface · Versions** (`defaultValue="evidence"`).

### UC-MO-01 · Evidence gate — pass / fail / not_evaluated
- **Preconditions/state:** three `ModelDetail.evidence.gate.verdict` variants.
- **Action flow:** 1. Load model → GET `/api/models/:id`. 2. Read Evidence tab (default).
- **Expected output:** `model-evidence` → `model-gate-row` grid (Held-out gate / Measured / Threshold / Verdict): `model-gate-measured` (`fmt(gate.measured)`), `model-gate-threshold`, `model-gate-verdict` via `GateVerdict`:
  - `pass` → green dot+label.
  - `fail` → red dot+label.
  - `not_evaluated` (and any unknown) → grey dot+label (`verdictColor` default `#94a3b8`).
  Optional calibration line (when `calibration != null`) and held-out set id (`evalSetId`). Footer note "A floor, not a ranking…".
- **Information flow:** `/api/models/:id` → `evidence.gate` → measured/threshold/verdict cells.
- **Pass criteria:** each verdict renders the correct colour + label; `not_evaluated` shown honestly (not a fabricated pass); null measured/threshold → `—`.
- **Edge/error cases:** `calibration`/`evalSetId` null → those lines omitted.

### UC-MO-02 · Lineage / Used-by / Interface / Versions
- **Action flow:** open each tab (`model-tab-lineage`, `-used`, `-iface`, `-versions`).
- **Expected output:**
  - **Lineage** (`model-lineage`): Dataset (`lineage-dataset-link` button when `datasetVersion && onOpenData`, else mono/`—`), Training run (`lineage-run-link` similar), Prior versions (`lineage-prior-<pv>` buttons or `—`). Note "Same lineage discipline as a dataset…".
  - **Used by** (`model-used`): `consumers.length` → `model-consumer-<c>` rows parsed into kind / where / how with `model-consumer-open-<c>` "open →"; else `model-no-consumers` — "No consumers yet — nothing in the account calls this model." Note "Because consumers are listed, superseding is a decision with a visible cost…".
  - **Interface** (`model-iface`): `model-iface-kind` badge (`interface.kind` capitalized) + `model-iface-signature` (from `ifaceSignature` — real signature or generic per kind: python→`call(inputs) -> result`, container→`run(inputs) -> result`, rest→`POST /infer {inputs} -> result`).
  - **Versions** (`model-versions`): `model-version-<v>` rows with verdict chip (`GateVerdict`), `current` badge when `v.v===identity.version`, `model-version-compare-<v>` "compare" for non-current. Note "Superseding never deletes…".
- **Information flow:** `ModelDetail.{lineage,consumers,interface,versions}` → tab bodies; `identity.version` marks current.
- **Pass criteria:** links appear only when the corresponding `onOpen*` action is wired and the field is present; empty consumers honest; interface signature never fabricated per-model.
- **Edge/error cases:** no prior versions → `—`; consumer string without `kind:` prefix → kind defaults "consumer".

### UC-MO-03 · Loader — loading / error
- **Preconditions/state:** `ModelObjectLoader` mid-fetch, then error.
- **Expected output:** loading → `model-object-loading` skeletons; error (`isError || !data`) → `model-object-error` "Could not load model <id>[: <message>]." + Back button (when `onBack`).
- **Information flow:** `useModel(id)` GET `/api/models/:id`.
- **Pass criteria:** error shows the id + message; Back returns.

---

## `##` Run pre-trained — `frontend/client/src/components/models/run-pretrained.tsx`

Purpose: the "Run a pre-trained model" track (`data-testid="run-pretrained"`). Pick a domain (structure / genomic / chemical), supply input, submit inference, poll, render via evidence-class viewers.

### UC-RP-01 · Domain pick + model resolve
- **Action flow:** 1. Open Models track 3. 2. Click `domain-structure` / `domain-genomic` / `domain-chemical` (`domain-picker`).
- **Expected output:** selecting a domain sets `domainId`, clears runId + input; goal text + `domain.id` badge; resolved model id: `pickModelId` picks first catalog model whose `family` matches the domain's `families`, else the domain default (`bionemo:boltz2` structure, `bionemo:evo2_7b` genomic, `""` chemical). Model shown as `run-pretrained-model` link (opens the model via `onOpenModel`) OR `run-pretrained-no-model` "no <id> model registered" when empty. Example chip `run-pretrained-example` fills the first placeholder line; input label + `run-pretrained-input` textarea.
- **Information flow:** GET `/api/models` catalog → `pickModelId` → model id/link.
- **Pass criteria:** correct model resolution per domain; chemical with no matching catalog model + empty default → `run-pretrained-no-model` (covered by UC-RP-05).

### UC-RP-02 · Submit → running → completed
- **Preconditions/state:** input non-empty; a resolvable `modelId`.
- **Action flow:**
  1. Enter input; click `run-pretrained-submit`.
  2. `useInfer` POST `/api/models/:id/infer` `{ inputs }` (structure/genomic → `{sequence}`, chemical → `{smiles:[]}` split by newlines) → `{ run_id }` → `setRunId`.
  3. `useInferenceResult(runId)` polls GET `/api/inference/:runId/result` every 1500 ms until non-running.
- **Expected output:** submit button shows "Running…" spinner while `infer.isPending || result.status==='running'`; `run-pretrained-result-card` appears once `runId` set; `result-status-running` badge while running; `result-pending` copy "Inference is running — the result renders here when it completes."; on `completed` → `result-status-completed` badge + `InferenceResultView`.
- **Information flow:** infer → run_id → polled result → status badge + viewer.
- **Pass criteria:** poll stops on terminal status; completed result routes to the correct viewer by `domainId`.
- **Edge/error cases:** `canRun` false (empty input or no modelId or pending) disables submit.

### UC-RP-03 · Failed inference
- **Preconditions/state:** poll returns `status:'failed'`.
- **Expected output:** `result-status-failed` destructive badge; `result-error` shows `result.error ?? "Inference did not complete."`; no viewer rendered.
- **Information flow:** `/result` → `status:'failed'` → error branch.
- **Pass criteria:** error message static (poll stopped); no completed viewer.
- **Edge/error cases:** infer POST itself throws → `run-pretrained-error` inline message ("<message>" or "Inference failed"); no result card (runId never set).

### UC-RP-04 · Stub result banner
- **Preconditions/state:** completed result with `stub:true` (backend/NIM unreachable → shape-only).
- **Action flow:** submit → completed with `stub:true` + optional `stub_reason`.
- **Expected output:** `InferenceResultView` renders `inference-stub-badge` — "Shape-only (stub) — the model backend was unreachable, so this shows the result layout without measured values.[ <reason>]"; viewers below render their empty/held states honestly (no fabricated numbers).
- **Information flow:** `isStub(result)` → `StubBanner`; viewers still dispatch by `evidenceClass`.
- **Pass criteria:** stub badge present; viewers show empty/held, not fake data.

### UC-RP-05 · No model registered (honest state)
- **Preconditions/state:** chemical domain, catalog has no matching family and default is `""`.
- **Expected output:** `run-pretrained-no-model` "no chemical model registered"; submit disabled (`canRun` false because `!modelId`).
- **Pass criteria:** no fabricated model id; run blocked honestly.

---

## `##` Inference result + wave-1 viewers — `inference-result.tsx` + `viewers/*`

Purpose: route a completed result to the viewer for its evidence class. Root: `data-testid="inference-result"` with `data-evidence-class="structure|genomic|chemical"`.

### UC-VW-01 · Structure viewer (PlddtChart + PaeHeatmap)
- **Preconditions/state:** `evidenceClass==='structure'` completed result.
- **Expected output:** `inference-structure`: 3D slot `inference-structure-slot` naming the viewer + `structureFileRef` (or "no structure file returned"); `PlddtChart` (`plddt-chart`): `plddt-mean` badge, `plddt-bar-<i>` bars coloured by band (90+ green / 70–89 blue / 50–69 amber / <50 red), `plddt-readout`, `plddt-regions` → `plddt-region-<label>`; empty `plddt: []` → "No per-residue confidence data available." `PaeHeatmap` (`pae-heatmap`): `pae-grid` with `pae-cell-<i>-<j>`, `pae-readout` (reliable <8 Å); empty `pae: []` → "No pairwise alignment error data available."
- **Information flow:** `StructureResult.{plddt,pae,regions,structureFileRef}` → chart/heatmap.
- **Pass criteria:** bar colours match pLDDT bands; empty arrays render the honest empty copy (stub case).
- **Edge/error cases:** hover a bar/cell updates read-out; click a bar/region fires `onSelectResidue` (not wired here → no-op).

### UC-VW-02 · Genomic viewer (SeqTracks)
- **Preconditions/state:** `evidenceClass==='genomic'` completed result.
- **Expected output:** `inference-genomic` → `SeqTracks` (`seq-tracks`): locus badge (`r.locus ?? "user-supplied"`), `seq-track-rows` with `seq-track-<name>` per track (line/marks/ticks SVG), and when `flagged.length` → `seq-flagged` → `seq-flag-<i>` rows (range, context badge, why, "open").
- **Information flow:** `GenomicResult.{locus,tracks,flagged}` → mapped to `SeqTrack`/`FlaggedInterval` → SeqTracks.
- **Pass criteria:** tracks render by kind; flagged intervals listed as the actionable output.
- **Edge/error cases:** empty tracks/flagged (stub) → tracks area empty, no flagged block; note always shows.

### UC-VW-03 · Chemical viewer (HitGrid table/grid + held)
- **Preconditions/state:** `evidenceClass==='chemical'` completed result.
- **Expected output:** `inference-chemical` → `HitGrid` (`hit-grid`): view toggle `hit-view-table` / `hit-view-grid`; table (`hit-table`) sortable headers `hit-sort-id|score|confidence|verdict`, rows `hit-row-<id>` with `hit-score-<id>` (held rows show italic "held", greyed `opacity-60`), hERG, drug-like, `VerdictChip` (accepted green / flagged amber / rejected red / held grey); depictions view (`hit-depictions`) → `hit-card-<id>` with `hit-depiction-<id>` (SMILES slot) + `hit-card-score-<id>` + out-of-domain badge; `hit-model-link` model attribution; `hit-held-note` listing held ids when any.
- **Information flow:** `ChemicalResult.hits` → mapped (score `?? null`, verdict narrowed via `toHitVerdict`) → HitGrid; unscored held hits sort to the end (score null never coerced to 0).
- **Pass criteria:** held/out-of-domain hits show no confident number and sort last; verdict colours correct; both views render.
- **Edge/error cases:** stub → hits held / score `—`; `onOpenModel` fires from `hit-model-link`.

---

## Cross-surface integration flows (recommended canonical E2E, per project consolidation rules)

- **Flow A (DataHub → Dataset object):** login → `/files` → pick project → expand `inputs` → observe quality dots (UC-FT-03) → open a CSV file (UC-FT-04) → Preview table (UC-DS-02) → Quality panel verdict (UC-DS-03) → Lineage (UC-DS-05) → Consumers (UC-DS-06) → Versions + append a note (UC-DS-07) → Export RO-Crate (UC-DS-09).
- **Flow B (Models):** login → `/models` → verify 5 tracks + count (UC-MP-01) → Registry table → open a model → Evidence verdict (UC-MO-01) → Interface/Versions (UC-MO-02) → back → Run pre-trained: structure domain → submit → poll → completed structure viewer (UC-RP-02 / UC-VW-01); repeat chemical for HitGrid held rows (UC-VW-03).
- Auth-gate probe: unauthenticated GET of `/api/projects`, `/api/models` → 401.

---

## Open questions / undeterminable from code

1. **Perception verdict source:** `QualityDot` and `DataPerception` render whatever `quality` the backend `/api/perception/profile` returns. Which file types actually yield `good/watch/blocked` vs stay `unknown` depends on `data_perception.py` (backend, not in scope). Test with a known profilable file to assert a concrete verdict.
2. **`not_evaluated` availability:** the WS1 thin layer is documented (in `types.ts`) to return `not_evaluated` for the gate verdict; a `pass`/`fail` requires a model with a measured held-out gate in the account catalog. On a fresh account you may only be able to exercise `not_evaluated` — flagging so the plan does not assume a real `pass`/`fail` model exists.
3. **Stub vs real inference:** whether `/api/inference/:runId/result` returns `stub:true` depends on backend reachability of the BioNeMo NIM / custom scorer. Both stub (UC-RP-04) and real (UC-RP-02) paths must be tested; the stub path is the deterministic one when NIMs are unreachable.
4. **Optimise / Train / Adapt live data:** `/api/model-tracks/*` map to real backend stores (regulatory training jobs, DPO pair recorder, Bayesian-optimizer rounds). On an empty project all three return honest-empty; exercising the populated branches (UC-MP-04/05/06 non-empty) requires seeded backend state — flagged as data-dependent.
5. **`ModelObject` action links** (`onOpenData`, `onOpenRun`, `onOpenConsumer`, `onCompareVersion`, `onUseInRun`, `onSupersede`): in `ModelsPanel` only `onOpenModel` is wired to `ModelObjectLoader`; the others are `undefined` there, so those links render as plain text / buttons that no-op. Confirm the intended wiring before asserting navigation on them.
6. **`data.round` keying in Optimise proposal:** rounds keyed by `r.round` and proposals by `p.id` — assumes unique values from the backend; duplicate keys would collide (React warning). Not observable without populated data.
7. **Preview table vs inline FileTree preview:** the DatasetObject Preview tab uses `/api/perception/profile` columns/rows (structured), while the FileTree inline preview fetches the raw file `/url` and parses client-side. These are two different render paths for "the same file" — verify both independently.

---

## Summary

- **Surfaces covered:** 3 (`##` sections split into DataHub page, ProjectFileTree, DatasetObject, ModelsPanel, ModelObject, RunPretrained, InferenceResult+viewers = 7 `##` component sections).
- **Use cases:** 40 (`UC-DH-01..07`, `UC-FT-01..07`, `UC-DS-01..09`, `UC-MP-01..06`, `UC-MO-01..03`, `UC-RP-01..05`, `UC-VW-01..03`).
- **Coverage:** every dataset-object tab (Preview/Quality/Lineage/Consumers/Versions/Origin) incl. loading/empty/error branches; every Models track (Train/Adapt/Optimise/Run-pretrained/Registry) + every ModelObject block (Evidence/Lineage/Used-by/Interface/Versions) + all three gate verdicts (pass/fail/not_evaluated); RunPretrained success AND failed AND stub AND no-model paths; all four wave-1 viewers incl. empty/held states; every honest-empty state.
- **All testids/routes/endpoints are real** (extracted from source, not invented). 7 items flagged as undeterminable / data-dependent above.
