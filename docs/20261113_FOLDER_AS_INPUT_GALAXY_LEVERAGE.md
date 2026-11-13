# Folder-as-one-input: Galaxy primitives + BioMate leverage

**Date:** 2026-11-13  
**Trigger:** User feedback — BioMate cannot use a project folder as one Analysis input (folder upload expands to files); Models cannot pick a folder at all.  
**Scope:** Read-only investigation + ordered leverage plan. **No code change** — nothing is a small, already-half-wired win that is safe to ship without a deliberate UX/engine decision.

---

## 1. How Galaxy handles folders / multi-file inputs (short)

Galaxy has **two different “folder” ideas**. They are not interchangeable.

### A. Dataset collections (the right abstraction for “N files → one tool input”)

| Primitive | Meaning |
|-----------|---------|
| **HDA** | History Dataset Association — one file in a history |
| **HDCA** | History Dataset Collection Association — one history item that wraps many HDAs |
| **LDDA** | Library Dataset Dataset Association — file in a Data Library (not history) |

**Collection types** (tool / workflow inputs of type `data_collection`):

- `list` — ordered set of datasets (e.g. N BAMs)
- `paired` — exactly two elements (`forward` / `reverse`)
- `list:paired` — list of pairs (typical multi-sample Illumina)

**Create API** (Galaxy): `POST /api/histories/{history_id}/contents` with  
`type: dataset_collection`, `collection_type`, `element_identifiers[]` (`src`: `hda` | `ldda` | `hdca`).

Galaxy also ships **auto-pairing** (`galaxy.model.dataset_collections.auto_pairing`) so R1/R2 naming can become `list:paired` without hand-wiring pairs.

Tools and **Galaxy native workflows** bind a collection via `src: "hdca"` on a `data_collection_input` step. Map/reduce over elements is Galaxy’s job.

### B. Data Library folders

Admin/shared tree of folders holding LDDAs. Useful for institutional data; **not** what BioMate’s project file tree is. BioMate does not surface library-folder pickers for Analysis/Models today.

### C. What Galaxy is *not*

Galaxy does **not** treat an arbitrary filesystem directory path as a first-class tool input the way Nextflow `--input_dir` or Batch staging of an S3 prefix does. “Folder” in Galaxy UI usually means either a **library folder** or a **collection** built from existing datasets.

---

## 2. What BioMate already wires

### Project “folders” (BioMate-native, not Galaxy HDCAs)

- `project_files` rows store **path-like names** (`pairs/S1_R1.fastq.gz`). Folders are **virtual** — reconstructed in the tree (`project-file-tree.tsx`) and in `project-folders.ts` (`filesUnderFolder`, `loadFolderFiles`).
- Upload of a local folder (`webkitdirectory` / folder-drop) **expands to many file rows** with relative paths. There is no single `project_files` row of type `folder`.
- Data Hub can **open** an input folder → `FolderProfileView` via `GET /api/projects/:id/folders/profile`.

### Folder intelligence (already reuses Galaxy)

- `backend/lib/galaxy/ai/folder_profile.py` profiles a folder as a whole (FASTQ pairs/orphans, 10x matrix sets, format rollup).
- Pairing is deliberately aligned with **Galaxy `auto_pairing`** (same filters / cross-check); Node never reimplements pairing (`project-folders.ts` comment).
- `?download=samplesheet` returns an **nf-core-style samplesheet CSV** for a paired FASTQ folder — the closest existing “folder → one artifact” path.

### Galaxy collections API (server wired, UI unused)

| Layer | Status |
|-------|--------|
| `GalaxyAPIProxy.createDatasetCollection` / `createPairedCollection` / `autoPairDatasets` | Implemented (`galaxy-api-proxy.ts`) |
| `POST /api/collections`, `/api/collections/auto-pair`, `/api/collections/create-paired` | Implemented (`routes.ts`) |
| Client UI calling those endpoints | **None** (composer only *mentions* collections / S3 prefix in the attachment-cap tooltip) |
| `WorkflowInput.src: 'hda' \| 'hdca' \| 'ldda'` | Typed; prerequisites / input-gate understand `data_collection_input` |
| Nextflow engine + Galaxy `inputs[]` with HDCA | **Blocked**: `inputsUnsupportedForNextflow` when Galaxy-style step inputs are supplied (`workflow-input-gate.ts`) — BioMate’s default execute path is Nextflow params / S3, not Galaxy HDCA binding |

### Analysis attach / Use (file-only)

- Data Hub **Ask in chat** / Use: `/?project=…&attachFile=<project_files.id>` — **one file id** (`data-hub.tsx` → `chat-input.tsx`).
- `FolderProfileView` has **no** Ask/Use action — folder open is view + samplesheet download only.
- Chat attach cap: `MAX_DATASET_REFS = 32` (`dataset-cap.ts`). Expanding a big folder into attach refs hits the cap; tooltip already steers users toward “S3 folder prefix (1 reference)” / collections — but **S3 folder import as one dataset is explicitly rejected** (`remote-source-validation.ts`: “An S3 folder cannot be imported as one file”).

### `run_code` / workspace

- Stages a **list of dataset/file ids** into flat `INPUT_FILES` / `INPUT_PATHS` — not a preserved directory tree as one input object.
- Optional `project_id` can resolve `project_files` rows from S3 into the sandbox; still per-file.

### Models (train + sandbox)

- `TrainingLauncher` / `POST /api/model-training/plan`: **required single `fileId`** (UUID of one project file) — tabular/SMILES table for sklearn/chemprop-style plans.
- Dataset `<select>` lists **files only**; upload is single-file (`input type="file"` without `webkitdirectory`).
- Code-sandbox path: `input_datasets = [fileId]` — same single-file assumption.

### Schema leftover

- `inputDatasetSchema.source` includes `'folder'` (`shared/schema.ts`) — documented historically as a Galaxy/collection-ish path enum; **no live consumer** found that attaches a folder this way.

---

## 3. The gap (why feedback is correct)

| Surface | What user wants | What happens today |
|---------|-----------------|--------------------|
| Analysis — chat attach | One folder = one input | Folder picker uploads/expands to N files; each burns an attach slot |
| Analysis — Data Hub | “Use” on a folder | Use/Ask exists only on **file** `DatasetObject`; folder profile has no parallel |
| Analysis — workflow params | Bind folder to `input` / reads | Nextflow expects samplesheet CSV or explicit file URIs; no “folder id” param type in the UI |
| Models | Pick a training folder | Launcher only lists files; plan API rejects non-file ids |
| Galaxy collections | Reuse HDCA | API exists; **no UI**; Nextflow path **does not consume** HDCAs |

**Root cause (not a missing Galaxy API):** BioMate’s product data plane is **project_files + S3 + Nextflow params**. Galaxy collections are half-integrated for a **Galaxy-tool** world. Folder UX was built for **browse/profile/upload**, not for **bind-as-single-input**. Galaxy already exposes create-collection; BioMate ignores it in the UI *and* cannot feed an HDCA into the default Nextflow executor without a new binding story.

---

## 4. Recommended leverage (prefer Galaxy *ideas*, not a parallel abstraction)

**Principle:** Do **not** invent a second “BioMate Collection” type. Prefer:

1. **Samplesheet / manifest as the one file** for Nextflow (already how nf-core thinks; folder_profile already builds it).
2. **Galaxy HDCA** only where the engine is Galaxy tools / `data_collection_input`.
3. **S3 prefix as one chat reference** only if staging/executor already understand prefixes (today URL import rejects folders — do not fake it).

### Analysis — ordered by effort

#### A. Low effort — “Use folder” → samplesheet (or expand-with-cap) *(best first ship)*

**Reuse:** `folders/profile?download=samplesheet`, `attachFile` query (already multi-value), `loadFolderFiles`.

1. On `FolderProfileView`, add **Ask in chat / Use** parallel to file `onAnalyze`.
2. For `kind` FASTQ with samplesheet: **persist samplesheet CSV** as a `project_files` row (or attach ephemeral content), then `attachFile=<that id>` — **one** Analysis input that Nextflow `--input` understands.
3. For small non-FASTQ folders (≤ cap): optional fallback `attachFile` repeated for each child id (honest N-file attach, still hits 32).
4. For 10x folders: same idea later — one “matrix set” manifest or the three required files with a single chat instruction; do not pretend one HDCA until Galaxy-tool path exists.

**Why first:** Matches BioMate’s Nextflow reality; reuses Galaxy pairing already in folder_profile; no HDCA↔Batch bridge.

#### B. Medium effort — chat/dataset ref type `folder` / `samplesheet`

1. Extend conversation dataset refs: `{ type: 'project_folder', projectId, path }` or `{ type: 'samplesheet', fileId }` counting as **one** toward `MAX_DATASET_REFS`.
2. Assistant + execute: when filling Nextflow file params, resolve folder → generate/cached samplesheet S3 URI (same as A) or pass listed S3 URIs for `dir`-like params if a workflow schema declares a directory.
3. Composer folder attach: stop treating webkitdirectory solely as N anonymous uploads when a **project** is linked — offer “keep as folder under inputs/…” (already path-preserving upload) **plus** “use folder as one analysis input” (A).

#### C. Medium–high — wire Galaxy collections for **Galaxy-engine** tools only

1. UI: “Create collection from this folder” → ensure HDAs exist (upload/stage to history) → `POST /api/collections` with `list` or `list:paired` from folder_profile pairs.
2. Bind `src: hdca` only when `executionEngine === 'galaxy'`.
3. Keep Nextflow on samplesheet/S3; **do not** claim HDCA works for nf-core until the executor learns collection→samplesheet materialization.

#### D. Higher effort — Nextflow directory / S3-prefix params

1. Schema: mark params that accept a directory or prefix.
2. Executor: stage `s3://bucket/project/.../folder/` as a directory for Batch, or materialize a samplesheet that points at sibling keys.
3. Only then is “one S3 folder reference” in chat truthful (today the tooltip over-promises relative to URL import).

### Models — ordered by effort

#### M1. Low — folder-aware **file** picker (not folder-as-dataset)

Training still needs **one table**. UX win: tree/folder filter in the dataset `<select>` so users open `train/` and pick `labels.csv`. No plan API change.

#### M2. Low–medium — sandbox: “use folder”

`code-sandbox-path`: allow selecting a project folder → `input_datasets = filesUnderFolder(...).map(id)` (respect size/cap). Preserves flat `INPUT_FILES` but matches “run code on everything in this folder.”

#### M3. Medium — multi-file / directory training (only if a training family needs it)

Extend `model-training/plan` only when a real workflow takes a directory or file list (not for current sklearn single-CSV path). Prefer generating a manifest file (same pattern as Analysis A) over inventing folder ids in the plan contract.

---

## 5. Explicit non-goals / traps

- **Do not** treat library folders as the product answer for project data — BioMate projects are already the ACL + S3 unit.
- **Do not** create HDCAs and pass their ids into Nextflow execute without a materialization step — the input gate already refuses that class of binding.
- **Do not** expand huge folders into 32 attach slots and call it “folder as one input.”
- **Do not** reimplement pairing in Node; keep Galaxy/`folder_profile` as the single pairing authority.

---

## 6. Suggested implementation sequence

| Order | Item | Effort | User-visible win |
|------:|------|--------|------------------|
| 1 | Folder profile **Use → samplesheet project file → attachFile** | S | Analysis: one input for RNA-seq-style folders |
| 2 | Models launcher **folder-filtered file pick** | S | Models: find the right file in a folder |
| 3 | Sandbox **folder → many input_datasets** | S–M | Models/adhoc: code over a directory |
| 4 | Chat ref type `project_folder` / samplesheet (cap = 1) | M | Composer + hub consistency |
| 5 | Collections UI + Galaxy-engine HDCA bind | M–H | True Galaxy collection workflows |
| 6 | Nextflow dir / S3-prefix param + staging | H | Bulk experiments without samplesheet |

---

## 7. Code map (anchors)

| Concern | Where |
|---------|--------|
| Create HDCA | `frontend/server/galaxy-api-proxy.ts` (`createDatasetCollection`, `createPairedCollection`) |
| HTTP collections | `frontend/server/routes.ts` `POST /api/collections*` |
| Folder rows / listing | `frontend/server/project-folders.ts` |
| Folder profile + samplesheet | `backend/lib/galaxy/ai/folder_profile.py`, `project-routes.ts` `GET …/folders/profile` |
| Folder UI (no Use) | `folder-profile-view.tsx`, `data-hub.tsx` |
| File Use → chat | `data-hub.tsx` `attachFile`, `chat-input.tsx` |
| Nextflow vs HDCA | `workflow-input-gate.ts` `inputsUnsupportedForNextflow` |
| Models single fileId | `model-training-plan.ts`, `training-launcher.tsx`, `code-sandbox-path.tsx` |
| Attach cap | `dataset-cap.ts` (`MAX_DATASET_REFS = 32`) |

---

## 8. Decision for this session

**Document only.** The collections API and samplesheet download are half-wired, but connecting them requires a product choice (samplesheet-as-file vs HDCA vs S3 prefix) and Nextflow vs Galaxy engine semantics. Shipping a half-connection (e.g. create HDCA with nowhere to bind it, or “Use folder” that expands to 32 files) would worsen the inconvenience.

**Next implementable slice when approved:** Analysis item **A** (folder Use → samplesheet → single `attachFile`).
