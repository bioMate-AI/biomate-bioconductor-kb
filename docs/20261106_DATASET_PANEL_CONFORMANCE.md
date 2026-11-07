# Dataset panel — design-conformance audit + increments (2026-11-06)

Audit of the dataset object/panel ("our central point") against `reference/claude_design/
data_centroid_design_v2/spec/04 Files and the dataset object.html`, and the increments that close
the gaps. Functional-coverage scope (the design is the reference; it shows major functions, the
product keeps more) — see `feedback_design_spec_is_source_of_truth`, `feedback_design_mockup_is_style_ref`.

## Audit result (spec 04 vs implementation)
Impl: `pages/data-hub.tsx`, `components/datasets/dataset-object.tsx`, `dataset-file-preview.tsx`,
`dataset-sample-plot.tsx`, `project-file-tree.tsx`, `add-connector-flow.tsx`, `data-perception.tsx`.

| Spec area | State before |
|---|---|
| File tree | 🟡 folders are auto `inputs`/`outputs/<runId>` not `uploads/results/shared`; quality dot (profiled exts only, N+1 fetch); ❌ version tag on rows; ❌ scope (project/account); ❌ content-hash dedup |
| "Open in" by file type | ❌ Jupyter/RStudio/Plot absent (needs dataset→history staging); only Ask-in-chat + Download |
| Preview | 🟡 Table (❌ amber cells); ❌ Columns view; **🟡 Plot = single-column histogram only — did NOT use the rich viewer suite**; ❌ Edit; 🟡 stat grid |
| Versions | 🟡 list (no used-by-N, note not words); ❌ Compare/Restore; append-only display-only |
| Where it came from | ✅ quality-at-ingest verdict + notes (DataPerception), ✅ RO-Crate; 🟡 origin (no who/how); ❌ content-hash/visibility; ❌ amber-inheritance; 🟡 lineage (❌ "what came out" evidence-typed outputs; ❌ training runs) |
| Ingest | ✅ drop; ❌ paste-URL (backend exists, UI doesn't call); 🟡 connector (separate dialog, not in ＋Add); 🟡 quality card lazy not at-ingest; ❌ column-mapping fix |
| Empty/failure | ✅ most; 🟡 blocked-file is a pill only |

## Visualization finding (the headline)
The dataset Preview rendered PDB as raw text, VCF/FASTA/BED as plain text, and "Plot" as a single
recharts histogram — while workflow **step outputs** already got BioMate's full viewer suite
(`components/viewers/` via `resolveViewer`): 3D structure (+pLDDT/PAE), VCF, sequence, annotation,
single-cell, density, cryo charts, hit grids. The two surfaces had reinvented separate previews.

## Increments shipped (both live on dev, PR #295)
### Increment 1 — Preview → shared rich viewer registry (`4bbdbe6aa`)
Extracted the ext→viewer registry (`resolveViewer`, `ViewerKind`, ext sets, `TEXT_VIEWERS`/
`SELF_FETCHING`) + the inline viewers (sequence, VCF, annotation, 3D structure + `parsePlddtFromPdb`)
out of `step-output-preview.tsx` into `components/viewers/inline-content-viewers.tsx`; both surfaces
import it. `dataset-file-preview.tsx` now dispatches the fetched text to the matching viewer:
`.pdb/.cif`→3D, `.vcf`→variant table, `.fasta/.fastq`→sequence cards, `.bed/.gff/.gtf`→annotation
table; `csv/tsv/json/star`→grid; HTML stays inert (security). No bespoke UI — same viewers the
run-output preview uses. tsc clean; full vitest 2221 pass; +3 dispatch tests.

### Increment 2 — Output tab → "Open as dataset" into the one Files object (`2006f91fa`)
Resolved the user's confusion ("another separate file list with another dataset panel"). Design
(§4.5.3/§4.7): a dataset-typed output "opens as a dataset object" into Files, not a second panel.
`AfterRunReport` Outputs tab resolves each output → its registered `project_files` id
(`source='run_output'`, matched by name, preferring this run) and shows **"Open as dataset ↗"** →
`/files?file=<id>` (the one Preview/Versions/Where-it-came-from object). Shown only for dataset-typed
outputs (via the shared `resolveViewer`), not figures/logs; best-effort (absent until the run is
saved to a project). tsc clean; +1 test (`.tsv` → `/files?file=ds-1`).

Net: one preview-visualization layer + one dataset object, reachable from both Files and the
after-run outputs.

### Increment 3 — Columns view (`3d99f7ced`)
Replaced the "columns coming soon" placeholder with the spec's §4.3 Columns view (the surface that
"makes the quality verdict arguable"): `dataset-columns-view.tsx` `computeColumnStats` derives per
column the inferred type (numeric/categorical/text/empty), % missing (bar), distinct / "all unique",
and a **watch chip** when a quality note names the column or >20% of its sampled cells are missing.
Client-side from the existing profiler `columns` + `sampleRows` + `notes` (no backend), **honestly
labelled** as sample-derived (never presents a sample stat as whole-file truth). en+zh i18n; +4 tests.

### Increment 4 — Lineage "what came out" (`89f5b3736`)
The Where-it-came-from tab now shows, beneath each run that READ the file, the datasets that run
PRODUCED — evidence-typed (`resolveViewer`) chips that each open as their own dataset object
(`/files?file=<id>`), the spec's §4.5.3 "lineage chains without a separate lineage viewer."
`DatasetObject` gained a `projectId` prop; produced outputs resolve from `project_files`
(`source='run_output'`, grouped by `run_id`). Frontend-only, lazy, uploads excluded. +1 test.

### Increment 5 (partial) — "used by N runs" on the current version (`pending`)
Versions tab now shows **used by N runs** on the current version row (spec §4.4), N = the consumers
count already fetched (`useDatasetConsumers`, now enabled for the Versions tab too). Small, honest,
from existing data. +1 test.

## Feasibility finding (2026-11-06) — why the rest is backend work
Investigated all four remaining gaps for a frontend-only path; each is genuinely backend-blocked (no
stubs shipped, per CLAUDE.md):
- **ProjectFile has no `content_hash` or `scope`/`visibility` column** (shape: id/name/s3_key/size/
  content_type/source/run_id/workflow_name/step_name/input_context/created_at). So scope promotion +
  content-hash dedup are a DB-schema change, not a UI wiring.
- **URL/connector ingest does NOT target `project_files`.** `POST /api/datasets/import-url` imports
  into the Galaxy history + `req.session.uploadedDatasets`; `POST /api/connectors/directory/attach`
  registers a session path-ref. Neither appears in the hub tree (which reads `/api/projects/:id/files`).
- **No byte-versioning.** `POST /api/datasets/:ref/versions` appends a NOTE only; there is no stored
  second byte-version to diff or restore.
- **The tree renderer is one level deep** (`project-file-tree.tsx` renders folder→file, not folder→
  folder), so true `results/<run>` sub-grouping needs a recursive renderer.

## Backend follow-ups (precise specs for the remaining gaps)
1. **Open-in Jupyter/RStudio/Plot by file type (§4.3.1):** add a dataset→history staging endpoint —
   `POST /api/projects/:id/files/:fid/stage-to-history` → copies the project file into the user's
   Galaxy history as an HDA and returns the HDA id, so `InteractiveToolLauncher` (exists) can mount it.
   Then the dataset-object header offers the file-type-appropriate tool (reuse `pickInteractiveTool`).
2. **In-hub ingest (§4.6):** ✅ **paste-URL SHIPPED** — `POST /api/projects/:id/files/import-url`
   (SSRF-validated, owner/editor-gated, 512 MiB-capped streaming fetch → project S3 prefix → a
   `project_files` row `source='url'`); the tree's ＋Add row now has a "URL" button that imports and
   the file shows in the tree (buildTree now groups any non-run_output source as an input). STILL
   TODO: connector→project attach writing a `project_files` row (connector flow currently registers a
   session ref), an at-ingest quality card, column-mapping correction, and a streaming/multipart path
   for files >512 MiB.
3. **Versioning writes (§4.4):** enable S3 object-versioning (or a versions prefix) for project files;
   `POST /api/datasets/:ref/versions` writes a new byte-version (edit-save), `GET …/versions/:v/diff`
   returns a cell/column diff vs current, `POST …/versions/:v/restore` writes the old bytes as a new
   version (append-only). Then wire Edit/Compare/Restore + a version tag on tree rows.
4. **Scope + content-hash dedup (§4.2.3/§4.5.1):** add `content_hash` (sha256) + `scope`
   ('project'|'account') columns to the files table; compute the hash at ingest (dedup: same hash →
   link one row); `POST /api/projects/:id/files/:fid/scope {scope}` promote/demote with a cross-project
   read of account-scope files. Then surface the hash + a visibility 2-button control + a `shared/`
   folder + the recursive `results/<run>` renderer.

## Remaining gaps (summary — all need the backend work specified above)
1. **"Open in" Jupyter/RStudio/Plot by file type** — needs a dataset→history staging endpoint
   (`InteractiveToolLauncher` exists).
2. **In-hub ingest** — paste-URL (backend `import-url` exists) + connector pull from ＋Add + at-ingest
   quality card + column-mapping correction.
3. **Versioning writes** — edit-in-place / Compare / Restore + version tags on rows + used-by-N
   (backend `POST versions` is note-only today).
4. **Scope (project/account) + content-hash dedup + `uploads/results/shared` folders** — backend fields.
5. **Amber-inheritance** ("amber travels" to descendants) — needs a downstream-quality field.
6. **Columns view — whole-file stats** (current is sample-derived) + amber cells in Table — needs the
   profiler to return per-column stats.

## Unrelated note
Full vitest shows 1 failure in `add-skill-form.helpers.test.ts` (`buildSkillMarkdown` emits
`name: "rev"` JSON-quoted vs test's bare `name: rev`) — from concurrent commit `de6cc8312`
(connectors skill-creation), not this work. Flagged, not modified.
