# 2026-11-17 — Design requirements: Dataset panel / data-perception surfaces (for the Claude design reference & tutorial demos)

**Why this doc:** the "Galaxy-leverage arc" (Nov 13–14) shipped dataset-panel surfaces that do **not** exist in the Claude design reference (`localhost:7779`): a **content-first perception read-out** (format + columns + roles), **folder → one samplesheet** attach, a **Confirm & Run datatype gate**, **deferred URL/FTP import**, **inline IGV.js BAM/VCF preview**, the **reproducibility-pack** zip, and `input_kinds`-driven **"what can I run with this"** matching. These are the requirements to (a) add these surfaces to the design reference and (b) build the tutorial demo around them. Everything below reflects **as-built, deployed behavior on DEV** (verified), not a proposal.

Audience: design-reference authors + tutorial authors. Companion docs: `20261114_1406Z_GALAXY_LEVERAGE_COMMITTEE_AUDIT.md` (the capability table + commits), `20261113_GALAXY_LEVERAGE_DEEP_SESSION.md` (folder→samplesheet + deferred import), `20261114_IGV_PREVIEW_SLOTS.md` (BAM/VCF viewer), `20261112_DATASET_PANEL_AUDIT.md` (profiling hardening + the "what NOT to depict" bug list). Demo deck already drafted: `~/Downloads/demo_recording_pack 2/tutorials_v3/dataset-panel-perception/`.

> Honesty contract (same as the demos): depict only "Have" capabilities below. The "Open" list is **not** to be drawn as working. No Nov-12 R1–R16 profiling bugs as features.

---

## 1. Scope of the new surfaces

Lives in the **dataset panel / Data Hub** and the **chat attach** flow. New/changed surfaces vs the reference:
1. **Perception read-out** — a file's **format chip from content** (not extension), a **columns view** (type · %-missing · distinct · role), and a per-column **watch chip** when a profiler finding names that column.
2. **Folder profile actions** — **Use samplesheet** (primary for FASTQ; collapses a folder of reads into ONE samplesheet input) vs **Attach all files** (all files as one Analysis/Models input). R1/R2 pairing, lane rollup, orphan-mate flag, 10x-bundle recognition.
3. **"What can I run with this"** — `input_kinds` match: the panel shows which workflows a dataset is compatible with (strong-kind match), and flags a mismatch.
4. **Confirm & Run datatype gate** — a blocked-prereq alert when a bound input's perceived kind ≠ the param's expected kind (e.g. a counts matrix bound to a `reads`/FASTQ param) — **blocks before Batch**.
5. **Remote import** — deferred large-URL import + **RemoteSourcePicker** (public FTP/HTTP → project file); **materialize on Confirm & Run**.
6. **Inline viewers** — IGV.js **BAM / VCF.gz** preview in the existing output/preview slots (no Interactive Tools; HTTP Range/206).
7. **Reproducibility-pack** download (zip) on a completed run.

---

## 2. Component spec (where each lives in code — pull exact testids/markup from these)

| Surface | Primary component(s) | Key hook / field |
|---|---|---|
| Format-from-content chip | `backend/.../data_perception.py` `decide()`; chip in `datasets/dataset-presentation.ts` / `dataset-object.tsx` | kind from content; name-disagreement = a finding (chip "format ok" vs "format not checked") |
| Columns view | `datasets/dataset-columns-view.tsx` `computeColumnStats` | type / %-missing / distinct / watch-chip; sample-labelled "n of N loaded" |
| File preview (tables, FASTA/VCF, images, IGV) | `datasets/dataset-file-preview.tsx` | per-format preview; IGV slot for BAM/VCF.gz |
| Folder profile + samplesheet | server `project-folders.ts` (`POST /api/projects/:id/folders/samplesheet`), client `folder-as-input.ts`; backend `folder_profile.py` | "Use samplesheet" (FASTQ primary) + "Attach all files" |
| input_kinds match | backend `_perceive_user_input_kinds` / `infer_input_kinds`; search `_score` step 8a (`_kinds_mismatch`, `input_compatible`) | per-workflow `input_kinds`; ~4167/4233 tagged |
| **Datatype gate** | `frontend/.../input-mapping-status.ts` `expectedViewKindsForParam` / `perceptionMismatch` → `datatypeGateBlocked` → `isPrereqBlocked` | blocks Confirm & Run; commit `82524c3839` |
| Remote import | Data Hub `RemoteSourcePicker` (`82524c3839`); deferred materialize (`94ae1391d5`, re-wired `0b63d793`) | deferred URL/FTP; materialize on Confirm & Run |
| IGV preview | IGV.js slot (`7ec27c15b6`); see `20261114_IGV_PREVIEW_SLOTS.md` | BAM/VCF.gz; Range/206 |
| Repro pack | `GET /api/runs/:id/reproducibility-pack` (`3e8b2db292`) | zip |

> Design-reference authors: the exact `data-testid`/`data-region` names are in the components above — mirror them so the reference's parity tests pass. The drafted deck `_ui/runs-datapanel.js` already models the generic region set.

---

## 3. States (required coverage in the design reference)

- **Perceived · format ok** (content matches) vs **format not checked** (strong-kind only); **name-disagrees** finding.
- **Columns view**: numeric / categorical / text; %-missing; a **role** found (e.g. `condition` group); a **watch chip** on a flagged column; the honest "n of N rows loaded" sample label.
- **Folder**: FASTQ → **samplesheet (one chip)** vs **all files**; paired R1/R2; **orphan-mate** warning; 10x bundle.
- **input_kinds**: **compatible** (workflow offered) vs **mismatch** (workflow dimmed/flagged).
- **Datatype gate**: **blocked** state on Confirm & Run — red prereq alert, names the offending param + the perceived vs expected kind, offers the compatible workflow/input. (Distinct from the missing-required-input blocked state.)
- **Remote import**: picking a URL/FTP source; **deferred** (not yet materialized) chip; **materializing on Confirm & Run**.
- **IGV**: BAM/VCF.gz loaded in the preview slot.
- **Repro pack**: available on a completed run.

---

## 4. Tutorial demo flow (drafted; ready to record)

Deck: `dataset-panel-perception` (8 scenes, Read · Match · Run · Report; bilingual en+zh). **Story:** attach `expression_counts.txt` (a counts matrix behind a `.txt` name) + `samples.csv` → BioMate reads the **format from content**, profiles the columns, finds the `condition` grouping → shows **"what can I run"** (input_kinds) → **the catch** → runs differential expression → answer → report.

**Self-correction beat (the signature scene-4 "catch your own mistake"):** the user points at "the RNA-seq pipeline," whose `reads` input needs FASTQ — but the file is a counts matrix, so the **datatype gate blocks the run before any Batch compute** (`perceptionMismatch → isPrereqBlocked`) and re-points to **differential expression** (whose `matrix` input accepts the table), where the chip reads "format ok". This is a shipped "Have" that **actually blocks** — not a narrated re-route.

Secondary beat available: messy **FASTQ folder → one correct samplesheet** (not N wrong single-end samples).

---

## 5. APIs the UI drives (for demo fixtures / connectors)

- `POST /api/projects/:id/folders/samplesheet` — persist the folder profiler CSV as one input.
- `POST /api/perception/folder_profile` — folder profile (gate: only `files[].datatRef` under the caller's project — see audit S5 fix).
- Perception / datatype-gate: client-side via `input-mapping-status.ts` (`perceptionMismatch`), fed by the per-file profiler.
- Remote import (deferred URL/FTP) + **materialize on Confirm & Run** (execute path).
- `GET /api/runs/:id/reproducibility-pack` — zip.
- IGV: output-file range reads (`/api/runs/:id/output/...`, Range/206).

---

## 6. Open — do NOT depict as working (honesty)

Pre-run **cost badge** (honesty redesign pending — do not draw the static table / fake 503), inline estimate-vs-actual cost strip, **h5ad viewer**, **datatype auto-converters**, workflow landings/shareable run links, storage purge, run-complete notifications. In code: **"Open in Jupyter/RStudio" is hard-disabled** (`OPEN_IN_AVAILABLE = false`); dense-vector rescue disabled; a residual datatype-gate overbreadth on a generic `input` param name. The Nov-12 `DATASET_PANEL_AUDIT` R1–R16/S1–S6 are the historical bug list — **not** features.

---

## 7. i18n

Bilingual (en + 中文) required on every new surface — the datatype-gate alert, the format/columns read-out, the folder actions, the import picker. CN region policy applies (same voice-env handling as the rest of the platform).
