# 2026-11-11 — Hospital-name scrub, UI internal-reference hiding, immunology examples

Branch: `fix/images-and-reroute-20261111` (shared worktree). Commits below are on
top of the images/coldstart line; deploy is gated on the convergence bot
(`68177db6`) landing its WIP and a forward-merge of current dev HEAD.

## 1. Hospital-name scrub (never in code or UI) — `90d7f12ff2`
The partner hospital's name must never appear in shipped code, UI, or served demo
data. Scrubbed catalog-wide:
- Renamed demo bundle `sysucc_synthetic/` → `hospital_synthetic/`; sample IDs
  `SYSUCC_*` → `S_*` in the 6 CSVs (these render in the data-panel preview =
  UI-visible); neutralized README + `provenance.json`; **recomputed sha256**
  (row/col counts unchanged, verified by the demo-catalog contract test).
- Backend comments/docstrings (`multiomics/*.py`, `bcell_epitope_immunogen/main.nf`,
  drug-discovery tests, `operation-skills.ts`, `generator-adaptation.md`) — all
  non-functional text, no identifiers touched.
- Rule recorded in memory `feedback_no_hospital_name_in_code_ui`. Internal `docs/`
  (61 files) left as-is per founder (not shipped/executed).

## 2. Two immunology design examples — `90d7f12ff2`
Added to `PREPARED_EXAMPLES` (built-in sample data, real-exec-validated workflows),
**routing + end-to-end verified live on dev** (HTTP 200 → real cloud runs → outputs
→ findings):
- `bcell_epitope_immunogen` — EBV antigen → 2 B-cell epitopes (GPSSQT, GDRSNPEV) +
  immunogen construct `MGPSSQTGPGPGGDRSNPEV` (GPGPG linker, 20 aa, 69 nt mRNA).
- `mhc_binding_prediction` — neoantigen HLA class-I; GILGFVFTL/HLA-A*02:01 25.84 nM
  (MHCflurry 2, scientifically correct).
- i18n display copy added for both (`b3859853ff`, cold-start locale-parity contract).

## 3. "View sample data" preview + object-array bug fix — `90d7f12ff2`
Workflow param panel: a JSON-string default (peptides, EBV antigen, ELISA table)
renders as a readable table (`sampleDataTable()` in `nextflow-workflow-viewer.tsx`)
instead of a raw blob. Also fixed a latent bug where an array-of-objects param
rendered as `[object Object]` rows (`parseListParam` now only accepts scalar arrays).

## 4. Never reveal storage path/key/id in the UI — `eda2401496`
- Data-panel file row: tooltip "Copy S3 path" → "Copy path" (en+zh); copy action
  now copies the file **name**, not the raw s3 key (`onPickFile` still gets the key).
- Workflow panel Inputs card: hover `title` no longer exposes the storage URI /
  dataset id — clean name only.
- Workflow panel file params (Phase + Settings editor): render the clean filename
  read-only instead of the raw storage path.

## 5. Never **show** galaxy id / internal path / s3 to the user — `c4c61d6efc`, `0e18bb80fb`, `85e6cc6a98`
Display-layer redaction (`redactInternalRefs()` in `shared/chat-system-blocks.ts`),
applied at every user-facing surface: assistant markdown, speaker-pill text,
copy + txt/md/docx download (`chat-message.tsx`), and run_code tool-input JSON,
stdout, output, file previews + code display/copy (`code-execution-block.tsx`).
Covers:
- `galaxy_dataset_id` (JSON / key=value / prose; bare keyword → `data_id`, never "galaxy").
- internal run_code staging paths → clean filename: `os.path.join(os.environ['DATA_DIR'],
  '<id>', '<file>')` → `INPUT_FILES['<file>']`; `/work/input|/work/output/…`,
  `/tmp/biomate_code/…`, `$DATA_DIR/<id>/<file>` → basename. Ordinary user paths untouched.
- s3: `s3_uri` pairs dropped; bare `s3://bucket/key/<file>` → filename; bucket-only → neutral.
19 shared-util tests + chat-message/code-exec suites green; tsc clean. These are the
agreed **stopgap**; the full fix is renaming the protocol field in `galaxy-assistant.ts`
(blocked — that file is in the convergence bot's uncommitted WIP).

Already-clean surfaces (verified, no change needed): `AfterRunReport` (uses s3_uri
functionally, maps `s3://` → "Cloud storage", never surfaces opaque ids) and
`galaxy-dataset-browser` (displays name+type+size; ids are functional binding values).

## Open / next
- **Full `galaxy_dataset_id` protocol rename** (construction in `chat-interface.tsx` +
  parsers + LLM instruction in `galaxy-assistant.ts`) — atomic, blocked on the
  contended `galaxy-assistant.ts`.
- **Deploy**: blocked on the convergence bot committing/stashing its 8 WIP files
  (dirty tree aborts `sync_to_dev`), then forward-merge current dev HEAD (was
  `ac7a665d` → now `bb9c8889`, moving), resolve 2 self-conflicts (hospital provenance +
  cold-start-examples), confirm superset with `biomate-review-b2`, sync.
- Disk reclaimed this session (~4.7 GB: scratchpad venvs + 4 clean idle worktrees).
