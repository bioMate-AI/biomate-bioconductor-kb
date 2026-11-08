# Connector: guided "Add a connector" + directory scan-preview (2026-11-01)

Built to match the design (`reference/claude_design/data_centroid_design_v2/dataui/Connectors.jsx`,
`ADD_CONNECTOR`). Replaces the bare 4-button add-switcher with the design's guided
multi-kind picker and a real directory scan-preview-before-attach flow.

## Frontend — `frontend/client/src/components/add-connector-flow.tsx`
`AddConnectorFlow` renders the 5 design kinds, each with kind + mode chips, a
plain-language question, and a note:
1. **A directory** (Data source · index in place / copy in) → opens `DirectoryScanFlow`
2. **A database** (Data source · connection + read scope) → existing Private DB form
3. **A model** (Model · endpoint + residency) → Settings model provider
4. **An instrument** (Data source · feed + residency) → Instruments section
5. **A skill or expert** (Skill) → Skills tab
6. **An MCP server** (MCP server · URL + auth + capability review) → MCP tab

`DirectoryScanFlow`: path input → **Scan** → a type table (Type · Files · Size ·
"Becomes") + warnings → choose **Index in place / Copy in** → **Attach**. Nothing is
attached until the scan result is shown. Wired into `connectors-dialog.tsx` (the
`adding` panel now renders `<AddConnectorFlow/>`).

## Backend — `frontend/server/routes.ts`
Two new endpoints after `/api/datasets/register-path`:
- `POST /api/connectors/directory/scan` `{ path }` → `{ ok, summary:{totalFiles,totalBytes,root}, mapping:[{ext,label,becomes,count,bytes}], warnings }`. Walks the dir (bounded: 20k files, depth 8), classifies by extension (`EXT_KIND`: fastq→reads, bam→alignment, vcf→variants, mrc→cryo-EM, mzml→mass-spec, …), **never follows symlinks**.
- `POST /api/connectors/directory/attach` `{ path, mode, projectId? }` → registers the directory as ONE path dataset ref (residency `mount`, nothing copied) via the same `req.session.uploadedDatasets[]` shape as `register-path`. Returns `{ ok, created, message }`.

## Security (the important part)
Scanning arbitrary **server** paths must never be possible on cloud. Guard
`resolveScanDir()` (modelled on Galaxy `library_datasets.py:453-521`):
- **Allow-roots allowlist** from `BIOMATE_CONNECTOR_SCAN_ROOTS` (colon-separated absolute roots). **Empty by default ⇒ every path is refused** — the cloud default. On-prem sets it to the real shares.
- `fs.realpath` the requested path AND each root, then require the resolved path to equal or be under a resolved root (prefix check) — blocks `..` traversal and symlink escape.
- The walk skips every symbolic link (`dirent.isSymbolicLink()`), so a link inside an allowed root can't point out of it.

**On dev (cloud):** `BIOMATE_CONNECTOR_SCAN_ROOTS` is unset, so the scan returns a
clear "Directory scanning is not enabled on this deployment — it is an on-prem
feature" message. The guided picker and the other 5 kinds work normally. To exercise
the scan on an on-prem box, set `BIOMATE_CONNECTOR_SCAN_ROOTS=/mnt/shares:/data`.

## Follow-ups
- `copy` mode currently registers the path + records intent; a true bulk copy-in
  belongs to a background job (not a synchronous request).
- For paths that ARE configured Galaxy file-sources, the browse layer
  (`/api/data/sources`, `/api/data/browse` → `remote_files.py`) could back a picker
  instead of a typed path. Deferred.
