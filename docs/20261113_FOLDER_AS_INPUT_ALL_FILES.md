# Folder as input set — all files (Analysis + Models)

**Date:** 2026-11-13  
**Branch:** `devline/ds-audit-20261112`  
**Prior research:** `docs/20261113_FOLDER_AS_INPUT_GALAXY_LEVERAGE.md`  
**Product decision:** Selecting a project folder means **every input file under that path prefix** (recursive), not a samplesheet-only stand-in and not one fake file id. Samplesheet download remains available for nf-core-style workflows.

## UX before → after

| Surface | Before | After |
|---------|--------|-------|
| Data Hub folder profile | View + samplesheet download only | **Ask in chat** attaches all files under the folder via `?attachFolder=<path>` |
| Chat composer | `attachFile` only (one id each) | Also expands `attachFolder` → N dataset chips (full file list) |
| Models Train dataset `<select>` | Files only; plan requires single `fileId` | Files **and** folders; folder → `folderPath` on plan |
| Models Code sandbox | Optional single `fileId` → `input_datasets: [id]` | Folder → `input_datasets: [id1…idN]` |

## API / schema

- `GET /api/projects/:id/folders/files?path=` → `{ path, files: [{ id, name }] }` (inputs under prefix; uses `loadFolderFiles` with ids).
- `POST /api/model-training/plan` accepts **`fileId`** (legacy) **or** **`fileIds[]`** **or** **`folderPath`**. Stages every resolved file; forwards primary `dataset_s3_uri` plus `dataset_s3_uris` / `dataset_names` when N>1; response includes `fileIds` (and `folderPath` when used).
- Chat deep-link: `/?project=<id>&attachFolder=<path>` (preferred over huge multi-`attachFile` URLs).

## Non-goals (unchanged)

- Nextflow is **not** routed through Galaxy HDCA (still rejected by the input gate).
- Folder upload (`webkitdirectory`) still expands on upload; the new piece is selecting an **existing** project folder as the dataset set.

## Tests

- Folder Use / attachFolder → N chips (`chat-input.dataset-references.test.tsx`, `folder-profile-view.test.tsx`)
- Models folder → N `input_datasets` / `folderPath` (`code-sandbox-path.test.tsx`, `training-launcher.test.tsx`, `model-training-plan.test.ts`)
- `GET …/folders/files` (`project-folders.test.ts`)
