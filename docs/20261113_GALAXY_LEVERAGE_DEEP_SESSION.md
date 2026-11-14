# Galaxy leverage deep session — 20261113

**Trigger:** User “go deep” after (1) coverage checklist committed and (2) folder→all-files E2E PASS on live `562908a3`.

**Constraint:** No HDCA→Nextflow; no Interactive Tools as default. Preserve voice env. Don’t fight concurrent syncs.

---

## Shipped this session

### 1. FASTQ folder → samplesheet as ONE Analysis input (Partial → Have)

| Piece | Change |
|-------|--------|
| `POST /api/projects/:id/folders/samplesheet` | Persist profiler CSV via `_storeProjectInput` (`source: upload`) → `{ file: { id, name } }` |
| Helpers | `pickFolderSamplesheetCsv`, `samplesheetStoredName` in `project-folders.ts` |
| Client | `persistFolderSamplesheet`, `analyzeFileChatUrl` in `folder-as-input.ts` |
| UI | Folder profile: **Use samplesheet** (primary for FASTQ) + **Attach all files** (keeps all-files path) |

Complement, does not replace, folder→all-files.

### 2. Deferred large URL import in primary UX (Partial → mostly Have)

| Surface | Change |
|---------|--------|
| Chat `UrlImportForm` (`galaxy-dataset-browser.tsx`) | Immediate / Defer radio → `/api/datasets/import-url` vs `/api/datasets/deferred` |
| Data Hub URL row (`project-file-tree.tsx`) | Defer checkbox; **413 oversize** auto-falls back to deferred |

**Closed 2026-11-13 (follow-on):** `POST /api/workflows/execute` Nextflow path calls
`ensureDeferredDatasetsMaterialized` (`deferred-materialize.ts`) — materialize → wait `ok` →
download → session/`_uuidFilePaths` (+ rewrite bare HDA ids in `rawParams` to local paths) →
`stageLocalFilesForBatch` (now resolves **any** registry key, not UUID-only — Galaxy hex HDAs).
Hard-fails with `deferred_materialize_failed` if download never becomes ready. Explicit
`POST /api/datasets/:id/materialize` now requires auth + `userProxy`.

### 3. Remote browse → project_files (Partial → Have for product path)

| Piece | Change |
|-------|--------|
| `remote-source-picker.tsx` | `GET /api/data/sources` → browse → `POST /api/data/fetch` → `POST …/files/import-url` |
| Data Hub | **Public FTP** button next to URL import |

Agent/MCP paths were already wired; this finishes the Data Hub land-in-tree flow.

### 4. Perception → Confirm & Run datatype gate (Partial → Have)

| Piece | Change |
|-------|--------|
| `input-mapping-status.ts` | `expectedViewKindsForParam`, `perceptionMismatch`; strong kinds only (binary/archive unchecked) |
| Panel | `datatypeGateBlocked` folded into `isPrereqBlocked`; chip **format ok** vs **format not checked** |

Samplesheet/`input`/`matrix` accept table kinds; `reads`+CSV blocks before Batch.

### 5. Folder E2E deepened

`frontend/e2e/folder-attach-all-files.e2e.ts` now asserts:

- Top folder count (incl. nested descendants)
- Nested-only count + no sibling leakage
- Empty folder → 404 `folder_not_found`
- Analysis chips = N; Models `(N files)` for top + nested
- Samplesheet persist → one chip **when** the new route is live (skips cleanly if 404)

---

## Tests run (local)

- `vitest`: `folder-as-input`, `input-mapping-status`, `folder-profile-view`, `project-folders` — **41 passed**
- `tsc --noEmit` — run in this session before sync

---

## Still open (from checklist high-value Missing / residual Partial)

1. ~~Reproducibility pack zip~~ → **Have** (`GET /api/runs/:id/reproducibility-pack`, 2026-11-13)
2. Pre-run cost estimate badge restore (honesty redesign — historical/prior; do not uncomment static table)
3. BAM/VCF viewers without IT; datatype converters; workflow landings; storage purge; in-app notifications
4. Live E2E for remote FTP + deferred materialize (API smoke) after sync
5. Samplesheet E2E attach assert requires feature commit on live

---

## Deploy notes

- Live tip at session start: `562908a3` (folder-attach merge)
- Feature commit: `82524c3839` — `feat(galaxy-leverage): samplesheet attach, deferred URL, remote FTP, datatype gate`
- Ancestry merge: `dd58dfaae9` — merge live `429c3dbc` (Run Manager + license) onto deep-session line
- Pushed to `origin/devline/ds-audit-20261112` (`562908a3e7..dd58dfaae9`)
- **Sync blocked in this agent sandbox:** `scripts/sync_to_dev.sh` needs AWS EC2 Instance Connect / SSM (`ssm.us-west-2.amazonaws.com`), which the Cursor sandbox cannot reach (`Could not connect to the endpoint URL`). Static `~/.ssh/biomate_ec2_ed25519` is no longer accepted (Permission denied). **Parent/operator should run `bash scripts/sync_to_dev.sh` from a full-network shell when remote lease is FREE.**
- Pre-sync live tip observed while blocked: `429c3dbc` (does **not** yet include samplesheet/deferred/remote/gate)
- Branch tip after doc + E2E harden: `b9f468b249` (pushed)

### Live E2E on `429c3dbc` (folder deepen — before feature sync)

**PASS** `folder-attach-all-files.e2e.ts` (~9.5s):

- API `pairs/` → **5** files (3 top + 2 nested); nested `pairs/lane1` → **2**; empty → 404
- Analysis attachFolder → **5** chips; Models `pairs/ (5 files)`
- Samplesheet persist → **404 skipped** (route not on live until sync)

Screenshots: `frontend/e2e/execshots/folder-attach-20261113/`
