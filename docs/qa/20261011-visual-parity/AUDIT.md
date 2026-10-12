# Dev UI visual parity audit — vs data_centroid_design_v2

**Date:** 2026-10-11 · **Method:** screenshots (Playwright, fixture account) of the LIVE dev build after syncing current code, compared against the reference prototype `reference/claude_design/data_centroid_design_v2/` (standalone HTML + `dataui/*.jsx` + `spec/*.html`). Reference is the **visual-style** target; `SIMPLIFICATION_DECISIONS.md` and the user's nav decisions override the prototype where they conflict.

Screenshots: `reference/*.png`, `dev/*.png` in this folder.

## Critical process finding
Dev was **stale** — it lagged the committed code (still showed Workflows/Connectors as primary nav; `/settings/connections` 404'd). Auditing the deployed build was auditing the *wrong* code. After `sync_to_dev.sh` (which first needed a fix — see below), dev reflected current code and most "discrepancies" from the first pass turned out to be **stale-build artifacts already fixed** (logo overlap, double-composer empty state, empty void).

## Intentional — NOT discrepancies (confirmed via SIMPLIFICATION_DECISIONS.md)
- `BioMate^AI BETA` logo (vs reference plain wordmark) — correct brand.
- Connectors + Import workflow under **Settings** (not primary nav) — explicitly required ("infrastructure... not a primary research navigation item").
- Module-card order (Search & evidence first) — matches the decisions doc, not the prototype.
- No "Lane: auto" in composer — lane switching is Advanced, not primary. Do NOT port the prototype's Lane button.
- Data preview omits the "Ask BioMate to edit this" box — server-backed editing must not be *claimed* until its API exists.

## Findings & actions (current dev vs reference)
| Panel | Finding | Action |
|---|---|---|
| Home | logo overlap / double-composer / empty void | stale build — already fixed ✅ |
| Home | breadcrumb, 4 cards, single composer, clean | matches reference ✅ |
| Connectors | ResidencyBadge used amber(cloud)/blue(mount)/violet(local) | **FIXED** → reference palette: gray cloud (neutral default), green on-prem/mount/local, blue prompt; pill + uppercase + icon (`14e2dd2b5`) |
| Connectors | flat rows, no zebra | **FIXED** → zebra band on even rows in the bordered card (`14e2dd2b5`) |
| Connectors | breadcrumb "Connections" | **FIXED** → "Connectors" (`14e2dd2b5`) |
| Connectors | dev shows 64 public DBs w/ category; reference shows 5 curated connected sources | product's richer real data — **kept** (not a regression) |
| Data hub | project picker, dataset-object w/ Preview/Quality/Lineage/Consumers/Versions/Origin, "Use in chat", quality badge | matches reference intent ✅; extra tabs = product function |
| Data preview | table has zebra (`odd:bg-muted/20`) + header (`bg-muted/50`) but **neutral-gray & subtle**; reference uses a **blue-tinted** header/band | deferred — fine aesthetic nuance (judgment call) |
| Data preview | breadcrumb shows raw dataset UUID | deferred — minor nit |

## Workflow panel (pre-run) — audited via cold-start ADMET example
Captured `Predict ADMET Properties (AI)` pre-run (`dev/23-workflow-panel-prerun.png`). Well-aligned:
- Eyebrow "DRUG DISCOVERY · WORKFLOW", title, phase count; **three tabs** Workflow settings / Phases / After run (matches reference + decisions doc); "Confirm & Run" footer.
- Chat shows the workflow card with "● In panel" badge. ✅
- Nits: a header checkbox icon of unclear purpose; no project/version/input-origin subtitle (honest here — AI workflow, no project). Running/completed/failed states not captured (would need to launch the Batch run).

## ✅ Functional bug found AND FIXED (cold-start demo upload)
The cold-start **Validated workflows → ADMET** demo attaches 4 files; the two **`.md`** files failed with HTTP 500 `{"error":"Internal server error"}` while the `.csv` files succeeded.
- **Root cause (ground-truthed):** the chat-attachment endpoint `/api/datasets/upload` uses a multer `fileFilter` (`routes.ts` `allowedExtensions`) that was **missing `.md`**; the reject surfaced as a 500. Reproduced directly: `.md`→500, `.csv`→200. (The project-files endpoint had no filter and already accepted `.md`.)
- **Fix (`e39887b63`):** added `.md`/`.markdown` to the allowlist (markdown is first-class: cold-start provenance, IND sections, after-run reports).
- **Verified on dev:** `/api/datasets/upload` `.md` → **200**; re-running the cold-start ADMET demo shows **no upload warnings** and both `demo_notes.md` + `pilot_README.md` attach. Synced at `95d6b574`.

## Data-preview polish — DONE (`a75ceddae`, verified live `dev/12-dataset-preview.png`)
- Breadcrumb now ends in the human filename (`Data / Inputs / counts_matrix.csv`), raw UUID moved to hover `title`. ✅
- Preview-table header: light-blue band (`--bm-accent-soft`) + accent-ink text, matching the reference data-table header. ✅

## Deferred / needs direction
- Workflow panel running/completed/failed states (needs a launched Batch run — cost).
- Reference extras not yet mirrored (judgment): Table/Columns/Plot toggle on preview; ROWS/COLUMNS/MISSING stat tiles (dev shows these in the Quality tab instead).

## Infra fix made en route
`sync_to_dev.sh` frontend deploy failed on root-owned stale files in `/opt/biomate/frontend_sync`; fixed with `sudo rm -rf` of the staging dir (`9f87d91e3`).
