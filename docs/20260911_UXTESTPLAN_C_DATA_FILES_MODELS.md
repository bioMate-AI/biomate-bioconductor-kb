# UX Test Plan — Cluster C: Data, Files & Models (Upgrade + V2)

*2026-09-11. The UX companion to the functional plan
`docs/20260909_TESTPLAN_DATAHUB_DATASET_MODELS.md`. Where that plan asked "does the
function work?", this one asks — for **every** function, on **all 7 rubric
dimensions**, for **both** the Upgrade and V2 versions — "**is the user's journey
through it smooth, honest, and visually correct?**"*

Follows the shared rubric and test-case shape in
`docs/20260911_UXTESTPLAN_MASTER_INDEX.md`. Cluster C maps to **v2 spec §§02, 03,
04, 10** (`reference/claude_design/data_centroid_design_v2/spec/`). Deltas are read
against `docs/20260909_V2GAP_MODELS_DESIGN_MODALITIES.md`, with the corrections
noted in the **"V2GAP corrections"** box below — several items the V2GAP doc marked
UNDONE have since shipped.

---

## Scope & surface map (source of truth — read from live components 2026-09-11)

| # | Surface | Route / entry | Component file | v2 § |
|---|---|---|---|---|
| C1 | Data-analysis hub + datasets | `/files` (`App.tsx:673`) | `pages/data-hub.tsx` | §02 |
| C2 | Project file tree | inside `/files` left pane | `components/project-file-tree.tsx` | §04 |
| C3 | Dataset object (6 tabs) | inside `/files` right pane | `components/datasets/dataset-object.tsx` + `datasets-api.ts` | §04 |
| C3q | Quality / perception panel | Dataset "Quality" tab | `components/data-perception.tsx` | §02, §04 |
| C4 | Models panel (5 tracks) | `/models` (`App.tsx:654`) | `components/models/models-panel.tsx` | §03, §10.1 |
| C5 | Model object (5 tabs) | Registry row / track link | `components/models/model-object.tsx` | §03 |
| C6 | Run a model (inference) | Models track 3 | `components/models/run-pretrained.tsx` | §03.2.4 |
| C7 | Inference result + viewers | RunPretrained result body | `components/models/inference-result.tsx` + `viewers/{plddt-chart,pae-heatmap,seq-tracks,hit-grid}.tsx` | §03.8 |
| C8 | Model use cases (worked-case page) | — | **NOT BUILT** (see C8) | §10 |

Routes: `/models` → `<ModelsPanel />` (no props), `/files` → `<DataHubPage />`,
both wrapped in `AuthenticatedPageLayout`. Endpoints unchanged from the functional
plan (`/api/projects…`, `/api/perception/profile`, `/api/datasets/:ref/…`,
`/api/models`, `/api/models/:id`, `/api/models/:id/infer`,
`/api/inference/:runId/result`, `/api/model-tracks/{train,adapt,optimise}`).

### V2GAP corrections (read the live source, not the 2026-09-09 gap doc)

The V2GAP doc (`docs/20260909_V2GAP_…`) predates the current tree. Verified live on
2026-09-11:

1. **Track renames ARE shipped.** `MODELS_TRACKS = ["Train","House style","Rounds",
   "Run a model","Registry"]` (`models-panel.tsx:37-43`). The V2GAP doc's "Adapt→House
   style / Optimise→Rounds / Run-a-pre-trained→Run a model = UNDONE" rows are **now
   DONE at the label level**. ⚠️ *But routing is index-based and the bodies were NOT
   renamed*: track 1 ("House style") still renders `AdaptTrack` (all `track-adapt` /
   `adapt-*` testids + "Adaptation level" / "Re-train on my edits" copy); track 2
   ("Rounds") still renders `OptimiseTrack` (all `track-optimise` / `optimise-*`
   testids + "Optimise · design · make · test · analyse" copy). **This is a
   label↔body mismatch bug — see UC-C4-b1.**
2. **RunPretrained header copy is v2** ("Run a model", "A pre-trained, integrated
   open-source model · nothing of yours is trained") — `run-pretrained.tsx:136-141`.
3. **Modality (Spec 11) IS now built** in `DesignGenerate.tsx` (`MODALITIES`,
   `MODALITY_META`, `modalityOf`) — but Design & Generate is **Cluster D**, not C.
4. **Still UNDONE in Cluster C:** the Spec-10 `ModelCase` worked-case page (grep
   `ModelCase|modelCaseFor|MODEL_CASES` → 0 hits) — see C8; the **owner-role register
   gate** (§3.6 — no RBAC anywhere in the models UI); the explicit
   **published-vs-held-out** label on the pretrained inference result (§3.2.4/§3.8);
   the **real 3D viewer + pLDDT→3D linkage** in the pretrained structure path (slot is
   a placeholder; `onSelectResidue` updates only an in-slot caption, never a mounted
   `structure-viewer.tsx`).

### "Upgrade" vs "V2" for this cluster — what the two columns actually mean

The Data-hub, dataset object, Models panel, model object, RunPretrained and all four
wave-1 viewers are the **same deployed code** for both versions — there is no separate
"Upgrade build". The distinction is:

- **Upgrade** = the data-centric surfaces as specified by `data_centroid_design`
  (spec v1): dataset-as-centroid, deep view, cold-start, skippable phases. The Models
  module and the dataset-object tabs are the v1 baseline.
- **V2** = the `data_centroid_design_v2` deltas (§§02/03/04/10): the track renames,
  "Run a model" track + §3.8 domain viewers, the ModelCase worked-case page, the
  published-vs-held-out / owner-role additions.

So for most functions the **Δ column** records: (a) which v2 delta the deployed code
already satisfies, (b) which is still a v1-only baseline waiting on a v2 delta, and
(c) where the deployed code sits *between* the two (e.g. v2 labels over v1 bodies).
Any function that exists **only in v2** is flagged **"NEW in v2 — absent in Upgrade
baseline"**.

### Rubric (all 7 dimensions scored per function — abbreviated inline)

1. **Journey** · 2. **States & transitions** · 3. **Visual fidelity** (no
`undefined`/NaN/blank) · 4. **Honesty** (honest-empty, no fabricated numbers, failed≠
"in progress") · 5. **Interaction & feedback** · 6. **Responsiveness & a11y** · 7.
**Cross-version Δ**.

Rules (from CLAUDE.md + master index): **no mocked APIs** in any live step — real
backend on `dev-public.biomate.ai`, fixture `lifeifei163361@163.com`, bypass
`x-e2e-test-token: biomate-e2e-bypass-token-dev-only`; **a skip is a fail** (untested,
not passed); **audit — screenshot each state, diff against the reference**; cite the
v2 § each function maps to.

---

# C1 · Data-analysis hub + datasets (`/files`) — v2 §02

Root `data-testid="data-hub"`. Breadcrumb `Data / <project>`, title `Data`, status +
`primaryDomain` badges, "Change project" (`data-hub-change-project`). No active project
→ `ProjectPicker` (`data-hub-picker`); active project → two-pane grid
`data-hub-panes` (`[300px_1fr]`): left `ProjectFileTree`, right `DatasetObject` or
`data-hub-detail-empty`. This is the "dataset-as-centroid" surface (§02): the page copy
is "Every dataset is an object: its identity, ingest quality, the runs that read it, its
versions and where it came from — not just a path in a chat message."

### C1 › Project picker — loading / empty / grid (dataset-as-centroid entry)
- Journey: nav to `/files` → (no active project) pick a project card → panes open.
- Precondition / data setup: log in as fixture; **real** `GET /api/projects` (no mock).
  For the empty case use a freshly created account with zero projects; for the grid,
  the fixture's real project list.
- Steps: 1. Load `/files` before projects resolve. 2. After resolve with 0 projects.
  3. After resolve with ≥1 project.
- Expected UX:
  - states: loading → `data-hub-picker` card "Loading projects…"; empty →
    `FolderOpen` icon + "No projects yet" + "A project holds your datasets, runs and
    models…"; grid → `data-hub-project-grid` with one `data-hub-project-<id>` card
    each. No flash of empty-state while still loading.
  - visual: status dot colour matches `STATUS_DOT` (active=emerald, completed=sky,
    archived/unknown=muted); status badge capitalized; `primaryDomain` + created date
    shown **only when present** — never a fabricated domain or "Invalid Date".
  - honesty: absent description/domain/date render nothing (not "undefined"); unknown
    status falls to muted dot (not a broken/empty dot).
  - interaction: card hover shows chevron (`opacity-0 group-hover:opacity-100`) +
    border/bg change; whole card is one button (single click → panes).
  - a11y: dot has `title={status}`; card is a real `<button>` (focusable, Enter
    activates); grid reflows `sm:grid-cols-2` → 1 col on narrow.
- Acceptance (UX-pass ⇔): exactly one card per real project, only real fields; picking
  a card mounts `data-hub-panes` and clears any prior selection; no `undefined`/`NaN`;
  loading never co-renders with grid.
- Upgrade: dataset-as-centroid picker is the v1 baseline (spec v1 dataui/DataHub.jsx).
  V2: §02 keeps the same picker (no v2 delta to the picker itself). Δ: **neutral** —
  unchanged between versions.
- Known gap / deferred: none.

### C1 › Two-pane hub + detail-empty + header breadcrumb/badges
- Journey: pick project → left tree + right pane; before selecting a file the right
  pane is an honest prompt, not blank.
- Precondition: active project with ≥1 file (real).
- Steps: 1. Pick project. 2. Observe right pane with nothing selected. 3. Read header.
  4. Click "Change project".
- Expected UX:
  - states: right pane `data-hub-detail-empty` "Select a dataset" + Database icon +
    "Pick a file from the tree to open it as an object…"; header breadcrumb `Data /
    <name>`, status badge, optional domain badge; "Change project" resets to picker.
  - visual: grid is `[300px_1fr]` on `md+`, stacks on narrow; detail-empty fills the
    pane height (no collapsed box).
  - honesty: empty pane is a labelled prompt (never a blank rectangle); switching
    project clears the prior file selection (a file id from another project is
    meaningless).
  - interaction: "Change project" (`data-hub-change-project`) immediate return to
    picker; no stale `dataset-object` left in the DOM.
  - a11y: breadcrumb text truncates (`truncate`) rather than overflowing.
- Acceptance: `data-hub-detail-empty` visible until a file is opened; header fields
  equal the active project record; change-project fully resets.
- Upgrade/V2/Δ: same code both versions; **neutral**.

### C1 › Dataset → workflow / Models routing (does the hub dead-end?)
- Journey: from an opened dataset, can the user get to running a workflow on it, or
  hand it to Models as training data?
- Precondition: dataset object open (see C3).
- Steps: 1. Open a dataset. 2. Look for an affordance to route the dataset into a
  run / composer / design / Models.
- Expected UX (per rubric — **honesty/journey focus**): §02 frames the dataset as the
  centroid that runs flow *from*; §2.6 + §4.7 name explicit handoffs — dataset → workflow
  input slot, workflow output → dataset object, and a result table → **Models as training
  data, carrying its quality flags** (§2.6, §3.3). Also §4.3.1 "Open in" (Jupyter /
  RStudio / plot / Ask in chat) is a spec'd affordance on the object header. Audit
  whether the deployed `DatasetObject` offers any of these.
- Acceptance: **document the truth** — as of 2026-09-11 `DatasetObject` exposes only
  Export RO-Crate + Download (`dataset-object-rocrate`, `dataset-object-download`) and
  the 6 read tabs; there is **no dataset→workflow CTA, no dataset→Models handoff, and no
  §4.3.1 "Open in" row** in the object. UX-pass ⇔ the plan records these as **journey
  dead-end gaps** (the centroid can be inspected but not acted on from here) — not a
  silent pass.
- Upgrade: v1 baseline has no such CTA. V2 §02/§04.7/§2.6 make the dataset a launch
  point + explicit cross-module handoff; Δ: **regression risk / gap** — flag for the
  D-cluster Design "entry routes" (`?from=…` markers) which originate elsewhere, not
  from the dataset object.
- Known gap / deferred: dataset→run routing, dataset→Models handoff (§2.6), and the
  §4.3.1 "Open in Jupyter/RStudio" launcher are not built in the object; verify whether
  chat/composer accepts a dataset ref by another path before calling it a hard block.

---

# C2 · Project file tree — v2 §04 (files & the dataset object)

Root `data-testid="project-file-tree"`. `inputs/` folder + `outputs/<runId>/` folders;
per-row lazy quality dot; Open / Copy / Download / Delete; inline preview; upload
(picker + drag-drop) + refresh. Testids: `project-files-refresh-btn`,
`project-files-upload-btn`, `project-files-input`, `folder-<path>`, and per-row
`file-open-<id>`, `file-quality-<id>`, `file-copy-<id>`, `file-download-<id>`,
`file-delete-<id>`.

### C2 › Tree states: loading / error / empty ("No files yet")
- Journey: mount tree → `load()` GET `/api/projects/:id/files`.
- Precondition: real project — empty case = project with 0 files; error case = force a
  non-OK response via a real bad project id (never `page.route`).
- Expected UX:
  - states: loading → refresh-button icon spins, no rows; error → red div with the
    **server** message text; empty → `Folder` icon + "No files yet" + "Drag & drop or
    click Upload".
  - visual: empty state not shown while loading; error text not truncated to "Error".
  - honesty: error surfaces the real `res.text()`, not a generic string; empty is a
    real prompt.
  - interaction: refresh button always clickable; spinner is the only running signal.
  - a11y: refresh button needs an accessible label (icon-only) — **audit**: confirm
    `aria-label`/`title` present; if missing, that's an a11y fail to record.
- Acceptance: each of 3 states renders its honest content; no state stuck.
- Upgrade/V2/Δ: §04 formalizes the file tree as part of the dataset-object surface;
  code identical both versions; **neutral**.

### C2 › Folders (inputs / outputs) + expand/collapse + run labelling
- Journey: browse `inputs/` (open by default) and one folder per run
  `outputs/<runId>`.
- Precondition: project with both an uploaded file and a run_output file (real run).
- Expected UX:
  - states: `folder-inputs` seeded expanded; each run folder labelled
    "`<workflow_name> · <Mon D HH:MM>`"; child-count on the right; toggle mounts/unmounts
    children.
  - visual: chevron rotates on expand; indentation consistent.
  - honesty: missing `workflow_name` → "Workflow · …" (not "undefined ·"); missing
    `created_at` → `runId.slice(0,8)` fallback; null `run_id` → grouped under
    "unknown" (not dropped).
  - interaction: click anywhere on the folder row toggles; state persists while the
    pane is open.
  - a11y: folder row is a button; expanded state should be conveyed (audit
    `aria-expanded` — record if absent).
- Acceptance: run folders carry workflow + timestamp; toggles add/remove the path from
  `expandedFolders`; no fabricated labels.
- Upgrade/V2/Δ: identical; **neutral**.

### C2 › Per-row quality dot (lazy `/api/perception/profile`)
- Journey: a profilable row auto-profiles on render → coloured ingest-quality dot.
- Precondition: a **real** profilable file (csv/tsv/txt/tab/vcf/fastq/fq/gz incl.
  `.fastq.gz`) whose backend profile returns a concrete verdict, plus a non-profilable
  file (e.g. `.bam`, `.png`).
- Expected UX:
  - states: `file-quality-<id>` with `data-quality` = good→emerald / watch→amber /
    blocked→red / unknown→muted-grey; non-profilable rows never fetch (stay grey).
  - visual: dot colour matches `QUALITY_DOT`; `title` = "Ingest quality: <quality>" or
    "…not profiled (unsupported file type)".
  - honesty (**critical**): a fetch failure / non-OK / non-string quality stays grey
    (never a fabricated green); unsupported types never call the endpoint (verify no
    network call in the audit).
  - interaction: dot is informational (hover title); no click behaviour expected.
  - a11y: colour is not the only signal — the `title` carries the verdict text
    (adequate); contrast of amber/grey on the row bg — audit.
- Acceptance: profilable dot reflects the **real** returned verdict; unsupported dot is
  grey with the "not profiled" title and made **no** request; unmount cancels in-flight
  (no state-update-after-unmount warning).
- Upgrade/V2/Δ: perception-at-ingest is the v1 centroid idea (§02); §04 keeps it.
  Δ: **neutral**.
- Known gap / undeterminable: which real file types yield good/watch/blocked vs stay
  unknown depends on backend `data_perception.py` — test with a known file to assert a
  concrete non-grey verdict, else the dimension is untested (= fail per skip-rule).

### C2 › Open / Copy S3 path / Download / Delete + step chip
- Journey: hover a row → action buttons appear → open opens the object; copy/download/
  delete act.
- Precondition: one upload row and one run_output row (real).
- Expected UX:
  - states: actions `opacity-0 group-hover:opacity-100`; copy icon flips to green
    `Check` for 1.5 s; download saves via presigned `/url`; delete → `confirm()` →
    DELETE → row removed.
  - visual: run-output row shows a blue mono `step_name` chip (title "Produced by
    step: <name>") beside the name.
  - honesty: **Delete absent** on `run_output` rows and when `canEdit===false`
    (verify it does NOT render — a delete on a run output would be data loss);
    download uses the real presigned URL.
  - interaction: `confirm()` cancel → no request; non-OK download/delete sets the
    `error` string (no silent failure).
  - a11y: icon-only action buttons need labels — audit `file-copy/download/delete`
    for `aria-label`/`title`.
- Acceptance: copy writes `s3_key` + green tick; download saves the file; delete only
  on upload rows and only after confirm; step chip only on produced files.
- Upgrade/V2/Δ: identical; **neutral**.

### C2 › Inline preview (image / CSV table / text) + input_context
- Journey: Eye toggle on a previewable (<1 MB, allowed ext) row → inline render.
- Precondition: a small real csv, a small png, a small txt with `input_context`.
- Expected UX:
  - states: image → `<img>` ≤200px; csv/tsv → 6-line HTML table (bold/muted header);
    other text → `<pre>` first 20 lines; `input_context.intent`/`inputFiles` → italic
    intent quote + "Input files: …".
  - visual: preview toggle **hidden** for non-previewable / ≥1 MB (no dead toggle).
  - honesty: text fetch failure → "(preview failed)"; loading → "Loading…" (both
    honest, not blank).
  - interaction: first open lazily fetches `/url`; toggle collapses.
  - a11y: `<img>` needs alt text — audit.
- Acceptance: correct render per ext; toggle absent when not previewable; failure text
  shown.
- Upgrade/V2/Δ: §14 (panes & output previews) refines this in Cluster B; the tree's
  inline preview is the v1 baseline here. Δ: **neutral** (deep pane view covered in B).

### C2 › Upload (picker + drag-drop) + refresh + auto-refresh event
- Journey: upload via button or drag-drop → tree reloads.
- Precondition: `canEdit===true`, a small real file.
- Expected UX:
  - states: Upload button spinner while posting; drop overlay "Drop files to upload"
    only while `dragOver`; on success new rows appear; refresh re-`load()`s.
  - visual: drag ring highlights the tree; overlay centered.
  - honesty: `canEdit===false` hides Upload and blocks drop (verify); upload non-OK →
    `error` string.
  - interaction: also auto-refreshes on `window` event `biomate:project-files-updated`.
  - a11y: hidden `project-files-input` is triggered by the visible button (label
    association) — audit.
- Acceptance: upload reloads the tree; overlay only during drag; edit-gate respected.
- Upgrade/V2/Δ: identical; **neutral**.

---

# C3 · Dataset object — v2 §04 (a file rendered as a first-class object)

Root `dataset-object`. Header: breadcrumb `Data / Inputs|Outputs / <id>`, mono name,
contentType + size badges, `dataset-object-rocrate` (only when `ref`), `dataset-object-
download` (only when `onDownload`), `dataset-object-back`. Six tabs (defaultValue
`preview`): **Preview · Quality · Lineage · Consumers · Versions · Origin**
(`dataset-tab-*`). Lineage/Consumers/Versions lazily fetch on first open; Preview +
Quality share the perception profile fetched on mount.

### C3 › Header identity + RO-Crate + Download
- Journey: open a file from the tree → object header.
- Precondition: a real DatasetRef with name/size/contentType and a resolvable `ref`.
- Expected UX:
  - states: `dataset-object-id` (mono), `dataset-object-name`, contentType badge (only
    when set), size badge (`formatBytes`), RO-Crate button only when `ref` truthy,
    Download only when `onDownload` wired; breadcrumb "Outputs" for run_output else
    "Inputs".
  - visual: long names truncate; badges wrap.
  - honesty: null size → "—", null contentType → no badge; RO-Crate hidden when ref is
    null (export is genuinely unreachable, not a dead button).
  - interaction: RO-Crate toggles "Exporting…" while pending → JSON download; error →
    `dataset-rocrate-error` (no silent fail).
  - a11y: RO-Crate has `title`; Back is a button.
- Acceptance: identity fields non-fabricated; RO-Crate/Download presence matches
  props; export downloads `<name>-ro-crate-metadata.json` or shows the error.
- Upgrade: dataset-object template is the v1 centroid deep-view. V2 §04 keeps it
  verbatim. Δ: **neutral**.

### C3 › Preview tab (perception table + identity rows)
- Journey: object opens on Preview by default; profile resolves → table + identity.
- Precondition: profilable file → `/api/perception/profile` returns columns +
  sampleRows.
- Expected UX:
  - states: `dataset-preview-table` when `columns.length && sampleRows.length` (header
    from columns, cells `r[ci] ?? ""`), caption "First N rows[ of <shape.rows>]"; below
    always Name/Size/Type/Reference rows + "A dataset is an object…" note.
  - visual: table horizontally scrolls (`overflow-x-auto`); zebra rows; mono cells.
  - honesty: non-tabular / profile error → identity rows only, **no** fabricated table;
    empty cells render "" not "undefined".
  - interaction: caption points to the full table viewer for sort/filter/paging (this
    inline table is preview-only).
  - a11y: real `<table>` with `<thead>`/`<th>` — screen-reader navigable.
- Acceptance: table only when both columns and rows present; identity rows always;
  no `undefined` in any cell.
- Upgrade/V2/Δ: **neutral** (this is a *different* render path than the file-tree inline
  preview — verify both independently; the object uses profiler columns, the tree
  parses the raw file).
- Known gap vs §4.3: the v2 Preview spec is **four sub-views over the same bytes —
  Table / Columns (per-column type, %-missing bar, `watch` chips) / Plot (distributions,
  PCA, volcano) / Edit (in-place, append-only)**. The deployed Preview tab renders only
  a static profiler table + identity rows — **no Columns/Plot/Edit sub-views**. Record
  as **PARTIAL / deferred**: the amber-flagged-cell evidence view (§4.3 "flagged cells
  are actual evidence for the amber verdict") and the **append-only edit** ("saving
  writes v4 and leaves earlier versions intact" — §4.3, "the single most important
  sentence in the file system") are **not built here**. Also §4.3.1 **"Open in"**
  (Jupyter/RStudio/plot/Ask-in-chat) is absent — deferred.

### C3 › Quality tab — perception panel (good / watch / blocked) + no-ref/loading/error
- Journey: click Quality → `DataPerception` fed by the shared profile.
- Precondition: (a) profilable ref with a verdict; (b) `ref===null`; (c) loading;
  (d) profiler error.
- Expected UX:
  - states: `dataset-quality` wraps `data-perception` with `data-quality=
    good|watch|blocked`; `perception-quality-badge` = Good(emerald+CheckCircle) /
    Watch(amber+AlertTriangle) / Blocked(red+XCircle); stat strip Rows/Columns +
    optional `perception-effective-n` (with "below row count…" hint when
    effectiveN<rows); optional `perception-leakage`, `-class-balance`, `-signal`,
    `-notes`, `-plan-impact` (each only when data present); footer provenance note.
    No-ref → `dataset-quality-noref`; loading → `dataset-quality-loading` skeletons;
    error → `dataset-quality-error`.
  - visual: badge colour/icon match the verdict; only present sections render (no empty
    boxes).
  - honesty (**critical**): the three honest non-verdict states (no-ref/loading/error)
    never show a fabricated verdict; a real profiler failure says "the profiler could
    not read this dataset" — not a fake "Good".
  - interaction: none beyond tab switch; the panel is read-only.
  - a11y: verdict conveyed by icon+label+colour (not colour alone); contrast audit on
    amber Watch.
- Acceptance: each verdict renders matching badge+`data-quality`; each honest state
  renders its own testid; no fabricated verdict anywhere.
- Upgrade/V2/Δ: perception-at-ingest is the v1 centroid feature (§02) reused by §04.
  Δ: **neutral**.
- Known gap: verdict source is backend `data_perception.py` — assert a concrete verdict
  with a known file (else untested).
- Additional honesty check vs §4.5.2 — **amber travels (inheritance rule)**: §04
  requires that anything produced from a Watch/amber input **stays amber until a human
  clears it** (a figure built from a watch-flagged table carries the flag; the quality
  verdict always carries its evidence notes — "a dot with no notes is a rumour", §4.9).
  Audit: does a **run_output** dataset whose input was amber surface an inherited amber
  verdict + notes? The deployed perception panel profiles each dataset independently at
  ingest and does **not** propagate an upstream amber flag — record inheritance as
  **deferred / not built** (a run output profiles clean even if its input was flagged).

### C3 › Lineage tab (produced-by / prop-fallback / uploaded)
- Journey: click Lineage → lazy GET `/api/datasets/:ref/lineage`.
- Precondition: (a) run_output with surviving provenance; (b) run_output with no
  backend record; (c) uploaded input.
- Expected UX:
  - states: loading skeletons; `available && producedBy` → Produced-by run / Workflow
    (`producedBy.workflow ?? dataset.workflowName`) / Status / Step + note "…written by
    a workflow run…"; else if run_output → prop refs + note "live provenance is no
    longer retained"; else `dataset-lineage-uploaded` "Uploaded input — no upstream
    workflow produced this dataset."
  - visual: two-col Row grid; mono values.
  - honesty (**critical**): never a fabricated run id — the three branches degrade
    honestly from live → prop → uploaded.
  - interaction: (in the hub, `onOpenData`/`onOpenRun` are not wired — lineage values
    are plain text, not links; that's correct for this surface).
  - a11y: Row labels are text; adequate.
- Acceptance: correct branch per real lineage availability; no invented provenance.
- Upgrade/V2/Δ: §04 "same lineage discipline as a dataset" — v1 baseline satisfies it.
  Δ: **neutral**.

### C3 › Consumers tab (live / prop / empty) — the blast radius
- Journey: click Consumers → lazy GET `/api/datasets/:ref/consumers`.
- Precondition: dataset with real reader runs; one with none.
- Expected UX:
  - states: loading skeletons; live → `dataset-consumer-<runId>` rows ("reads" badge,
    `workflow ?? runId` mono, optional status); else prop consumers; else
    `dataset-no-consumers` "No runs are recorded as reading this dataset yet."; always
    the blast-radius note.
  - visual: rows keyed by runId; status badge right-aligned.
  - honesty: precedence live > prop > empty; empty is honest, not a zero-count fib.
  - interaction: read-only rows (no open action wired in the hub).
  - a11y: badges are text; adequate.
- Acceptance: correct source precedence; empty state honest.
- Upgrade/V2/Δ: **neutral** (§04 blast-radius concept, v1 baseline).

### C3 › Versions tab (list / prop / empty) + append-only note
- Journey: click Versions → lazy GET; type a note → Enter or Add → POST.
- Precondition: dataset with `ref`; try an empty note and a real note.
- Expected UX:
  - states: loading skeleton; live → `dataset-version-<version>` cards (mono label,
    `current` badge, formatted `createdAt`, optional note + author); else prop rows;
    else `dataset-no-versions`; append UI `dataset-version-add` only when `ref`.
  - visual: current version highlighted; timestamps localized (handles both epoch-sec
    and ISO).
  - honesty: append is **append-only** — a new entry appears without rewriting priors;
    the note copy says so.
  - interaction: Add button disabled on empty/whitespace note (`note.trim()` guard) —
    no request; "Adding…" while pending; success clears the input; error →
    `dataset-version-add-error` (incl. a backend 200-with-error-field).
  - a11y: input has placeholder; Enter submits; button reflects disabled reason
    (empty note) — audit whether the *why* is conveyed (tooltip) beyond disabled.
- Acceptance: appended entry appears without a full refetch; empty note blocked; prior
  entries never rewritten; error surfaced.
- Upgrade/V2/Δ: §04 append-only versioning — v1 baseline. Δ: **neutral**.

### C3 › Origin tab
- Journey: click Origin → static Rows (no fetch).
- Expected UX: `dataset-origin` Rows Source / Storage ref (mono) / Added (localized or
  "—"); honesty: values straight off the ref, no fetch, "—" when absent.
- Acceptance: values reflect the DatasetRef; no `undefined`.
- Upgrade/V2/Δ: **neutral**.

### C3 › Export RO-Crate (success + error)
- Journey: click Export RO-Crate → GET `/api/datasets/:ref/ro-crate` (blob) → save.
- Precondition: `ref` set.
- Expected UX: button "Exporting…" while pending; success = JSON download
  `<sanitized-name>-ro-crate-metadata.json`; non-OK → `dataset-rocrate-error` with the
  status message (no silent failure).
- Acceptance: correct filename downloads OR the error is shown; ref-null hides the
  button entirely.
- Upgrade/V2/Δ: **neutral** (§04 provenance export).

---

# C4 · Models panel (5 tracks) — v2 §03 + §10.1

Root `models-panel`. Header breadcrumb `<project> / Models`, title "Models",
`models-count` badge "<N> registered". `models-tabs` with five triggers
`models-track-0..4`, labels **Train · House style · Rounds · Run a model · Registry**
(`MODELS_TRACKS`, v2 §10.1). Opening a model (Registry row / track link) replaces the
whole surface with `ModelObjectLoader`. **No leaderboard anywhere** (§03 honesty rule).

### C4 › Header + count + five track tabs (v2 labels)
- Journey: nav `/models` → header + tab bar.
- Precondition: authenticated; real `GET /api/models`.
- Expected UX:
  - states: `models-count` = "<N> registered" (0 when empty / non-array / error);
    five `models-track-0..4` each with an icon (GraduationCap/Wand2/Repeat/Rocket/
    Library) + label.
  - visual: tab labels read **Train / House style / Rounds / Run a model / Registry**
    (the v2 §10.1 vocabulary) — **not** the v1 "Adapt / Optimise / Run a pre-trained
    model".
  - honesty: count reflects the real catalog; no leaderboard, no "top model" ranking on
    the panel.
  - interaction: tabs switch content; uncontrolled Radix `defaultValue` with `key`
    remount for a controlled `tab` prop.
  - a11y: tabs are Radix (roving tabindex, aria-selected) — verify keyboard arrow nav.
- Acceptance: five tracks present with the v2 labels; count matches `/api/models`.
- Upgrade: v1 labels were "Adapt / Optimise / Run a pre-trained model". V2 §10.1:
  "House style / Rounds / Run a model". Δ: **DONE — v2 labels shipped**
  (`models-panel.tsx:37-43`); improvement (legibility).

### C4-b1 › ⚠️ Label↔body mismatch on House style & Rounds tracks (BUG)
- Journey: click "House style" (track 1); click "Rounds" (track 2).
- Precondition: any state (empty is fine).
- Steps: 1. Open track 1. 2. Read the card titles/copy/testids. 3. Open track 2. Same.
- Expected UX (per rubric — **visual fidelity + honesty**): a v2-compliant surface has
  the tab label and the panel body agree. §10.1 renames Adapt→House style ("learns
  wording, never changes a number") and Optimise→Rounds ("propose & test in rounds").
- Observed (2026-09-11): track 1 label "House style" but body is `AdaptTrack` —
  `track-adapt`, "Adaptation level", "scope: organisation", "Re-train on my edits",
  `adapt-retrain`, `adapt-learned` / `adapt-pair-*`. Track 2 label "Rounds" but body is
  `OptimiseTrack` — `track-optimise`, card title "Optimise · design · make · test ·
  analyse", `optimise-*` testids.
- Acceptance (UX-pass ⇔): **FAIL as-is** — record the mismatch. A user who clicks
  "House style" lands on a card headed "Adaptation level"; a user who clicks "Rounds"
  lands on a card headed "Optimise". UX-pass requires either the bodies re-titled to the
  v2 vocabulary, or the labels reverted — currently they disagree. This is the single
  most user-visible Cluster-C v2 defect.
- Upgrade: v1 labels+bodies agreed (both "Adapt"/"Optimise"). V2: labels renamed,
  bodies not. Δ: **regression** — the rename is half-applied.
- Known gap / deferred: bodies (card titles, testids, copy) still carry v1 vocabulary;
  §10.1 "Tune on our data" sub-label and the House-style "learns wording, never changes
  a number" framing are absent.

### C4 › Registry track — loading / error / empty / table + row → model object
- Journey: open track 4 → catalog table → click a row → model object takeover.
- Precondition: real `GET /api/models` (populated + an empty-account case).
- Expected UX:
  - states: loading → `registry-loading` skeletons; error → `registry-error` "Could
    not load the model registry."; empty → `registry-empty` "No models registered in
    this account yet…"; populated → `registry-track` + `registry-table` (header
    Model/Family/Origin/Used by) with `registry-row-<id>` buttons (name+version, family,
    origin, `usedByCount`, chevron).
  - visual: mono model name, muted version; columns align to the header grid.
  - honesty: rows show only real summary fields; empty state honest.
  - interaction: row hover bg; click → `onOpenModel(id)` → `ModelObjectLoader` takes
    over the whole panel; `model-object-back` returns to the last track.
  - a11y: rows are `<button>` (focusable); chevron is decorative.
- Acceptance: correct branch; clicking a row opens `model-object`; Back restores the
  track.
- Upgrade/V2/Δ: registry is a v1 baseline; §03 unchanged. Δ: **neutral**. (§3.4
  workspace-vs-project scope split is **PARTIAL/UNDONE** — copy says "Account-level" but
  there is no `scope` prop or workspace/project split; record as deferred.)

### C4 › Train track — loop + runs (empty/list) + families
- Journey: open track 0 → `useTrainTrack(project)` GET `/api/model-tracks/train`.
- Precondition: real endpoint — empty project (honest-empty) + (data-dependent) a
  project with a real training run.
- Expected UX:
  - states: `train-loop` with 4 fixed steps `train-loop-step-0..3` (Dataset / Train /
    Quality gate / Register); `train-runs` → `train-run-<name>` cards (family badge,
    when, `train-run-status-<name>` coloured completed=green/failed=red/running=blue/
    other=grey; metric + gate badges; dataset mono; `train-run-open-<name>` "watch
    live →" / "open experiment →" when running or `modelId`; optional version line);
    empty → `train-runs-empty`; `train-families` 4 fixed cards (Language / Tabular
    AutoML / Diffusion / Molecular property).
  - visual: loop numbered 1–4; family grid 2-col.
  - honesty: loop + families are **fixed design content** (a description, not measured
    data) and always render; the runs list is the only data-bearing part and shows an
    honest empty ("hasn't trained a model yet…") — never a fabricated run/metric.
  - interaction: `open experiment` fires `onOpenModel(modelId)` only when `modelId` set.
  - a11y: status conveyed by dot+label.
- Acceptance: loop + families always render; runs reflect the backend; metric/gate
  labels never invented (they're strings from the run).
- Upgrade/V2/Δ: §03.2.1 train-as-a-run; v1 baseline. Δ: **neutral** (§10 adds the
  ModelCase *train_potency* worked page, which is C8 / UNDONE).

### C4 › "House style" (AdaptTrack) — ladder + learned pairs + toggle + retrain
*(v2 label; v1 body — see C4-b1.)*
- Journey: open track 1 → `useAdaptTrack` → toggle a learned pair; click retrain.
- Precondition: real `GET /api/model-tracks/adapt` — empty + (data-dependent) with
  learned pairs.
- Expected UX:
  - states: `adapt-levels` fixed 3-rung ladder (Prompt rule / Few-shot index / Trained
    adapter) + `adapt-retrain` "Re-train on my edits[ (<pendingCount>)]"; `adapt-learned`
    → `adapt-pair-<id>` cards (learned label, scope badge, `adapt-pair-toggle-<id>`
    switch `aria-checked`, before→after `adapt-pair-before-<id>` strikethrough-red →
    `adapt-pair-after-<id>` green, source line, `opacity-60` when off) + "<active> of
    <total> active"; empty → `adapt-learned-empty` "Nothing learned yet…".
  - visual: before red strikethrough, after green; off pairs dimmed.
  - honesty: "nothing is learned silently" — every learned rule appears and is
    switchable; empty is honest.
  - interaction: toggle flips `aria-checked` + opacity and fires the persisted POST
    `/adapt/:pairId/toggle` (unless a parent callback overrides); retrain fires POST
    `/adapt/retrain`; pending-count suffix only when >0.
  - a11y: switch has `role="switch"` + `aria-checked` (good); label association —
    audit.
- Acceptance: toggle flips state + fires the POST; retrain fires; empty honest.
- Upgrade/V2/Δ: v1 "Adapt" body. Δ: **label renamed to House style, body not** (C4-b1);
  the §10.1 "learns wording, never changes a number" copy is absent (deferred).

### C4 › "Rounds" (OptimiseTrack) — empty vs running (DMTA loop + proposal)
*(v2 label; v1 body — see C4-b1.)*
- Journey: open track 2 → `useOptimiseTrack` GET `/api/model-tracks/optimise`.
- Precondition: real endpoint — inactive project (`{active:false}` → honest-empty) +
  (data-dependent) a running loop.
- Expected UX:
  - states: no data → `optimise-empty` "No optimisation loop is running…" + 4 design
    bullets; running → `optimise-loop` (`optimise-loop-state` "running · round N" green
    / "stopped" grey; `optimise-surrogates` with `optimise-surrogate-<id>` links;
    optional Budget/Refit policy; `optimise-rounds` → `optimise-round-<round>` rows) +
    `optimise-proposal` (`optimise-proposal-table`; `optimise-proposal-<id>` rows with
    candidate/score/confidence/`optimise-proposal-verdict-<id>` coloured accepted=green/
    reject*=red/else=amber; empty proposal → "No proposal for this round yet.").
  - visual: verdict dot+label colour per `proposalVerdictColor`.
  - honesty (**critical**): a **rejected proposal stays listed with its safety-gate
    reason** (red verdict) — never silently dropped; scores are strings the loop
    reported, never invented on the client; censored values stay censored.
  - interaction: surrogate click → `onOpenModel(id)`.
  - a11y: verdict conveyed by dot+text.
- Acceptance: empty + running both correct; rejected proposal visible with reason.
- Upgrade/V2/Δ: §03.2.3 DMTA; v1 body kept. Δ: **label renamed to Rounds, body not**
  (C4-b1); the OptimiseTrack copy is already DMTA-rounds framed (good), only the card
  title still says "Optimise".
- Additional honesty checks vs §3.7 (wet-lab loop) — when a **populated** loop is
  present, audit: (a) **censored values stay censored** — `IC50 > 30 µM` shown as an
  inequality, **never coerced to 30** (§3.7.4); (b) **partial returns are first-class**
  — every proposal accounted for including "not synthesised / insufficient material /
  assay QC failed" each with a reason (no survivor bias, §3.7.4); (c) a **rejected
  proposal stays listed with its safety-gate reason** (§3.2.3, verified in the empty-
  state copy). The deployed OptimiseTrack renders these as *strings from the loop* (the
  `optimise-empty` bullets state the rules; the proposal table shows verdicts) — so the
  honesty is enforced backend-side. Record: the **round-as-contract stage bar** (§3.7.1
  Proposed→Ordered→At the bench→Results in→Refit) and the **predicted-vs-measured per
  round** view (§3.7.6) are **not built** in the deployed track — deferred.
- Known gap / undeterminable: populated Train/Adapt/Optimise branches require seeded
  backend state (regulatory training jobs / DPO pairs / Bayesian rounds) — on an empty
  project all three honest-empty; the populated branches are **data-dependent** (test
  only if the fixture project has them, else record as untested).

### C4 › Run a model (track 3) — see C6 (RunPretrained).

---

# C5 · Model object (5 tabs) — v2 §03.3 (a model presented like a dataset)

Root `model-object` (via `ModelObjectLoader`). Header: breadcrumb `Models / Registry /
<id>`, mono name+version, family badge, optional confidence-band badge, origin,
`model-object-supersede` + `model-object-use-in-run`. Tabs (default `evidence`):
**Evidence · Lineage · Used by · Interface · Versions** (`model-tab-*`). §03 honesty
rule: **never a leaderboard, never a loss curve** — the evidence gate is a floor.

### C5 › Evidence gate — pass / fail / not_evaluated (measured · threshold · verdict)
- Journey: open a model → Evidence tab (default).
- Precondition: real `GET /api/models/:id`. On a fresh account only `not_evaluated` may
  be reachable (WS1 thin layer); a real `pass`/`fail` needs a catalog model with a
  measured held-out gate — **data-dependent**.
- Expected UX:
  - states: `model-gate-row` grid Held-out gate / Measured / Threshold / Verdict;
    `model-gate-measured` = `fmt(gate.measured)`, `model-gate-threshold`,
    `model-gate-verdict` via `GateVerdict` (pass=green / fail=red / not_evaluated &
    unknown=grey `#94a3b8`); optional calibration line + held-out set id (`evalSetId`);
    footer "A floor, not a ranking…".
  - visual: verdict dot+label colour correct; null measured/threshold → "—".
  - honesty (**critical**): `not_evaluated` shown **honestly** (grey), never a
    fabricated pass; the floor copy explicitly denies a leaderboard.
  - interaction: read-only.
  - a11y: verdict conveyed by dot+text.
- Acceptance: each verdict → correct colour+label; `not_evaluated` honest; "—" for
  null; no leaderboard/loss-curve anywhere.
- Upgrade/V2/Δ: §03.3 model-object is **unchanged** between v1 and v2. Δ: **neutral —
  DONE**.
- Known gap / deferred: the **published-vs-held-out** distinction (§3.2.4 — "published
  by authors + local spot-check earns the gate") is **not surfaced** as a label here;
  record as deferred.

### C5 › Lineage / Used-by / Interface / Versions
- Journey: open each tab.
- Precondition: a real model detail.
- Expected UX:
  - Lineage (`model-lineage`): Dataset (`lineage-dataset-link` button only when
    `datasetVersion && onOpenData`, else mono/"—"), Training run (`lineage-run-link`),
    Prior versions (`lineage-prior-<pv>` or "—") + "same lineage discipline as a
    dataset" note.
  - Used by (`model-used`): `model-consumer-<c>` rows parsed kind/where/how +
    `model-consumer-open-<c>` "open →"; else `model-no-consumers` "No consumers yet —
    nothing in the account calls this model." + "superseding is a decision with a
    visible cost" note.
  - Interface (`model-iface`): `model-iface-kind` badge (capitalized) +
    `model-iface-signature` — real signature or an honest generic per kind (python→
    `call(inputs) -> result`, container→`run(inputs) -> result`, rest→
    `POST /infer {inputs} -> result`).
  - Versions (`model-versions`): `model-version-<v>` rows with `GateVerdict` chip,
    `current` badge when `v.v===identity.version`, `model-version-compare-<v>` for
    non-current + "superseding never deletes…" note.
  - honesty (**critical**): interface signature **never fabricated per-model** (falls
    back to a generic shape by kind); empty consumers honest; a completed run keeps its
    exact version (reproducibility copy).
  - interaction: links appear **only when** the matching `onOpen*` is wired AND the
    field is present. **In `ModelsPanel` only `onOpenModel` is wired** — `onOpenData`/
    `onOpenRun`/`onOpenConsumer`/`onCompareVersion`/`onUseInRun`/`onSupersede` are
    `undefined`, so those controls render but no-op. Audit: do the buttons *look*
    actionable while doing nothing? Record as an interaction-honesty concern (a button
    that gives no feedback fails dimension 5).
  - a11y: buttons focusable; a no-op button should ideally be disabled — audit.
- Acceptance: each tab renders its real fields; interface signature honest; links only
  when wired+present.
- Upgrade/V2/Δ: **neutral — DONE** (model object unchanged in v2). Δ note: the unwired
  actions (`onUseInRun`/`onSupersede` etc.) are a **journey dead-end** on this surface
  — Use-in-a-run / Supersede look live but do nothing from `/models`.
- Known gap / deferred: **owner-role register gate (§3.6) is UNDONE** — there is no RBAC
  anywhere in the models UI; Supersede/Use-in-a-run are ungated *and* unwired.

### C5 › Loader — loading / error
- Journey: open a model → loader fetches by id.
- Expected UX: loading → `model-object-loading` skeletons; error/`!data` →
  `model-object-error` "Could not load model <id>[: <message>]." + Back (when `onBack`).
- Honesty: error shows the id + real message; no fabricated object.
- Acceptance: error surfaces id+message; Back returns to the track.
- Upgrade/V2/Δ: **neutral**.

---

# C6 · Run a model (inference) — v2 §03.2.4 (track 3)

Root `run-pretrained`. Header "Run a model" + copy "A pre-trained, integrated
open-source model · nothing of yours is trained.". Domain picker
(`domain-structure`/`-genomic`/`-chemical`, `domain-picker`), goal + `domain.id` badge,
resolved `run-pretrained-model` link OR `run-pretrained-no-model`, example chip
`run-pretrained-example`, `run-pretrained-input` textarea, `run-pretrained-submit`,
result card `run-pretrained-result-card` with `result-status-{running,completed,failed}`
→ `InferenceResultView`.

### C6 › Domain pick + model resolve (structure / genomic / chemical)
- Journey: open track 3 → pick a domain → resolved model shown.
- Precondition: real `GET /api/models` catalog.
- Expected UX:
  - states: selecting a domain sets `domainId`, clears runId + input; goal text +
    `domain.id` badge; `pickModelId` = first catalog model whose family ∈ domain families
    else the default (structure→`bionemo:boltz2`, genomic→`bionemo:evo2_7b`, chemical→
    `""`); model shown as `run-pretrained-model` link OR `run-pretrained-no-model` "no
    <id> model registered".
  - visual: active domain button `variant="default"`, others outline.
  - honesty (**critical**): chemical with no matching catalog family and empty default
    → `run-pretrained-no-model` (**never a fabricated model id**); the "produces …"
    line names the real output type.
  - interaction: example chip fills the first placeholder line; model link →
    `onOpenModel`.
  - a11y: domain buttons are a real toggle group — verify pressed state.
- Acceptance: correct model resolution per domain; no-model honest for chemical when
  unregistered.
- Upgrade/V2/Δ: **NEW in v2 — absent in Upgrade baseline** (§3.2.4 added the 4th "Run a
  model" track). Δ: **DONE (new)**.

### C6 › Submit → running → completed
- Journey: enter input → Submit → poll → viewer.
- Precondition: non-empty input + resolvable modelId (structure/genomic use
  `bionemo:*` defaults so the real endpoint is always exercised).
- Expected UX:
  - states: submit disabled unless `canRun` (non-empty input, modelId, not pending);
    while running the button shows "Running…" spinner; `run-pretrained-result-card`
    appears once `runId` set; `result-status-running` + `result-pending` "Inference is
    running — the result renders here when it completes."; on completed →
    `result-status-completed` + `InferenceResultView`.
  - visual: spinner animates; status badge swaps.
  - honesty: poll (1500 ms) **stops** on terminal status — no spinner forever;
    completed routes to the correct viewer by `domainId`.
  - interaction: `canRun=false` disables submit (empty/no-model/pending).
  - a11y: spinner has a text label ("Running…"); button disabled state visible.
- Acceptance: poll stops on terminal; completed → correct viewer; no stuck spinner.
- Upgrade/V2/Δ: **NEW in v2**. Δ: **DONE (new)**.

### C6 › Failed inference + submit error
- Journey: a run that returns `status:failed`, and an infer POST that throws.
- Expected UX: `result-status-failed` destructive badge; `result-error` = `result.error
  ?? "Inference did not complete."` (static — poll stopped, **no** "in progress"
  spinner); infer POST throw → `run-pretrained-error` inline ("<message>" / "Inference
  failed"), no result card (runId never set).
- Honesty (**critical, per Chat/Panel Presentation Standard**): a failed run shows a
  **static error**, never "Analysis in progress…"; no viewer renders.
- Acceptance: failed → static error, no viewer; POST-throw → inline error, no card.
- Upgrade/V2/Δ: **NEW in v2**. Δ: **DONE (new)**.

### C6 › Stub result banner (backend unreachable)
- Journey: completed result with `stub:true` (BioNeMo NIM unreachable — the
  deterministic path when NIMs are down).
- Expected UX: `inference-stub-badge` "Shape-only (stub) — the model backend was
  unreachable, so this shows the result layout without measured values.[ <reason>]";
  viewers below render their **empty/held** states (no fabricated numbers).
- Honesty (**critical**): stub is loudly badged amber; viewers show empty/held, never
  fake data.
- Acceptance: stub badge present; viewers honest-empty; no fabricated science.
- Upgrade/V2/Δ: **NEW in v2** (honest-stub is a v2 §03.2.4 requirement). Δ: **DONE
  (new)**.

### C6 › No model registered (honest state)
- Journey: chemical domain, no matching catalog family, empty default.
- Expected UX: `run-pretrained-no-model` "no chemical model registered"; submit
  disabled (`!modelId`).
- Honesty: run blocked honestly, no fabricated id.
- Acceptance: no-model shown; submit disabled.
- Upgrade/V2/Δ: **NEW in v2**. Δ: **DONE (new)**.

---

# C7 · Inference result + wave-1 viewers — v2 §03.8 (viewer per evidence class)

Root `inference-result` with `data-evidence-class`. Routes by class: structure →
3D-slot + `PlddtChart` + `PaeHeatmap`; genomic → `SeqTracks`; chemical → `HitGrid`.

### C7 › Structure viewer (3D slot + PlddtChart + PaeHeatmap)
- Journey: completed structure result → the two-confidence view.
- Precondition: `evidenceClass==='structure'` (real or stub).
- Expected UX:
  - states: `inference-structure`; 3D slot `inference-structure-slot` naming the viewer
    + `structureFileRef` (or "no structure file returned"); `PlddtChart` (`plddt-chart`:
    `plddt-mean` badge, `plddt-bar-<i>` bars coloured by band 90+green/70-89blue/
    50-69amber/<50red, `plddt-readout`, `plddt-regions` → `plddt-region-<label>`; empty
    `plddt:[]` → "No per-residue confidence data available."); `PaeHeatmap`
    (`pae-heatmap`: `pae-grid` with `pae-cell-<i>-<j>`, `pae-readout` reliable <8 Å;
    empty `pae:[]` → "No pairwise alignment error data available.").
  - visual: bar colours match pLDDT bands; heatmap blue→red.
  - honesty (**critical**): a structure picture without a confidence chart "invites a
    claim its low-confidence loops cannot support — the two are one output"; empty arrays
    (stub) render the honest empty copy, never fake bars/cells.
  - interaction: hover a bar/cell updates the read-out; clicking a bar/region fires
    `onSelectResidue` → the slot caption "centred on residue N — open the structure file
    to view" (`inference-structure-selection`).
  - a11y: SVGs have `role="img"` + `aria-label`.
- Acceptance: bars/heatmap render from real data; empty arrays → honest empty; hover
  read-outs update; click updates the slot caption.
- Upgrade/V2/Δ: **NEW in v2** (§3.8.1 domain viewers). Δ: **PARTIAL** — pLDDT/PAE +
  regions DONE; **the 3D slot is a placeholder** (not the real `structure-viewer.tsx`)
  and the pLDDT→3D **linkage lands only in an in-slot caption**, not a mounted 3Dmol
  view. Record: the click *does* fire `onSelectResidue` and the caption *does* update
  (so the selection is wired UI-side), but there is **no live 3D structure** in this
  path — deferred (§3.8.1 "click centres 3D" is not literally satisfied).

### C7 › Genomic viewer (SeqTracks + flagged intervals)
- Journey: completed genomic result → tracks + the actionable flagged list.
- Precondition: `evidenceClass==='genomic'`.
- Expected UX:
  - states: `inference-genomic` → `SeqTracks` (`seq-tracks`): locus badge
    (`r.locus ?? "user-supplied"`), `seq-track-rows` with `seq-track-<name>` per track
    (line/marks/ticks SVG on a shared coordinate domain), and when `flagged.length` →
    `seq-flagged` → `seq-flag-<i>` rows (range, context badge, why, "open").
  - visual: tracks align on one coordinate domain (a variant tick and a mark at the same
    position line up); line=blue area, marks=amber, ticks=grey.
  - honesty: "a per-base score is only actionable as an interval — flagged regions are
    the output"; empty tracks/flagged (stub) → empty tracks area, no flagged block, note
    still shows.
  - interaction: flagged "open" fires `onOpenInterval` (not wired here → no-op — record).
  - a11y: SVGs `role="img"` + `aria-label` per track.
- Acceptance: tracks render by kind on a shared domain; flagged list is the output;
  empty honest.
- Upgrade/V2/Δ: **NEW in v2** (§3.8.2). Δ: **DONE (new)**.

### C7 › Chemical viewer (HitGrid table/grid + held rows)
- Journey: completed chemical result → ranked hits, table ⇄ depictions.
- Precondition: `evidenceClass==='chemical'`.
- Expected UX:
  - states: `inference-chemical` → `HitGrid` (`hit-grid`): view toggle `hit-view-table`
    / `hit-view-grid` (labelled "Table" / "Depictions"); table (`hit-table`) sortable
    headers `hit-sort-{id,score,confidence,verdict}`, rows `hit-row-<id>` with
    `hit-score-<id>` (held rows italic "held", greyed `opacity-60`), hERG, drug-like,
    `VerdictChip` (accepted=green / flagged=amber / rejected=red / held=grey);
    depictions (`hit-depictions`) → `hit-card-<id>` with `hit-depiction-<id>` (SMILES
    slot) + `hit-card-score-<id>` + out-of-domain badge; `hit-model-link` attribution
    ("<model> →"); `hit-held-note` listing held ids.
  - visual: verdict colours from reference tokens (`--ok/--warn/--err/--text-dim`),
    theme-aware; left-border ring per verdict in the grid view.
  - honesty (**critical**): a **held / out-of-domain hit shows NO confident number**
    (italic "held", greyed) and **sorts to the end** regardless of direction (score null,
    never coerced to 0); every score **names the model behind it** (`hit-model-link`);
    stub → all held / "—".
  - interaction: header click sorts (score sort keeps held last both directions); view
    toggle switches table↔depictions (this IS the §5.5.1 "two views of one ranking");
    `hit-model-link` fires `onOpenModel`.
  - a11y: sortable `<th>` are clickable — audit for `aria-sort` / button semantics
    (currently plain `<th onClick>` — record as an a11y gap: not keyboard-operable).
- Acceptance: held rows unscored + greyed + last; verdict colours correct; both views
  render; model named; stub honest.
- Upgrade/V2/Δ: **NEW in v2** (§3.8.3 + §5.5.1 two-views). Δ: **DONE (new)** for the
  viewer; the depiction slot is an honest keyed placeholder (no client SMILES renderer)
  — the actual 2D structure drawing renders server-side / is a slot, so "chemist reads
  structures" is **PARTIAL** (record).

---

# C8 · Model use cases — worked-case page (ModelCase) — v2 §10 — NOT BUILT

- Journey (as v2 §10 intends): from a Models track, clicking a worked example lands on
  a `ModelCase` page — one spine for all four tracks answering: **what model → what it
  was given → what came back → how much to trust (floor) → what it left behind
  (boundary) → next steps** (§10.4). Four cases: `run_fold`, `train_potency`,
  `adapt_gen`, `opt_loop` (§10.5); each leaves its own report in `runs/models/` (§10.6);
  a new **`register`** helper atomically moves the registry row + card and marks the
  prior superseded (§10.4).
- Precondition / data setup: n/a — the surface does not exist.
- Steps: 1. grep `ModelCase|modelCaseFor|MODEL_CASES|CASE_REGISTER` across
  `frontend/client/src` → **0 hits** (verified 2026-09-11). 2. No route, no example-click
  → case-page landing anywhere in the Models tracks.
- Expected UX (per rubric) — the exact §10.4 spine to test when built, one layout for
  all four tracks, top→bottom:
  1. **model chip** — name+version as a link into the model object; **only
     registry-existing names may appear** (e.g. `potency-gp v3 (candidate)`).
  2. **WHAT THIS WAS GIVEN** — inputs resolved to versions + the decision each row
     encodes + what was excluded and on what rule. Copy exemplars: "Training data
     assay_2026_08.csv · v4 — *a version, not a name*"; "Split scaffold 70/15/15 —
     *random split leaks*"; "Excluded 311 censored values — *kept as inequalities*".
  3. **stages chips** — the run's phases (Featurise / Fit / Held-out evaluation / Gate /
     Offer); before a result exists they read **"waiting"** — nothing reported until the
     evaluation stage finishes.
  4. **WHAT CAME BACK** — a headline sentence + labelled blocks, one of which is
     **always the honest one** (a flag, a "narrower than it looks", or a round still in
     flight). Copy exemplar: "It clears the floor, and it is narrower than it looks";
     HELD OUT metrics; WHERE IT APPLIES (applicability region).
  5. **BOUNDARY** — what the result is **NOT** evidence for; present on all four cases.
     Copy: "Passing a gate means it cleared a floor on one held-out split — not that
     predictions are correct elsewhere."
  6. **MEASURED AGAINST A FLOOR** — the floor table metric · value · threshold ·
     pass/flag (a floor, not a ranking). Copy: "RMSE · held out  0.62 log  ≤ 0.75 to
     gate a loop  pass".
  7. **WHAT IT LEFT BEHIND** — every artefact is a file: reports get **Open & edit** +
     download; tables/model artefacts get **Open in Files**.
  8. **WHAT TO DO NEXT** — decisions, never automatic: [Register as v3] [Model object]
     [Fix upstream]. The **`register` helper (new)** moves the registry row + card
     atomically, marks the prior version superseded (not deleted), and re-reads every
     surface live so the toast and the registry cannot disagree.
  Four cases (§10.3), one per track: **run_fold** (`fold-predict v2.3`, pre-trained —
  pLDDT 84.2, two regions below floor), **train_potency** (`potency-gp v3` — RMSE 0.62,
  clears floor, not registered), **adapt_gen** (`molgen v4.1 + adapter` — in-series
  12%→71%, novelty flagged), **opt_loop** (`admet-herg v3` + `potency-gp v2` — pIC50
  7.1→7.9, 3 of 12 returned no data). Each leaves its own report in `runs/models/`
  (`fold_report.md` / `train_report.md` / `adapt_report.md` / `loop_report.md`, §10.6).
- Acceptance (UX-pass ⇔): **FAIL / untested — the surface is not built.** Per the
  skip-is-a-fail rule, this whole section is recorded as an **UNDONE v2 delta**, not a
  pass. Do not fabricate a test result against a missing page.
- Upgrade: **absent in Upgrade baseline too** (ModelCase is a v2-only chapter). V2 §10:
  required, not shipped. Δ: **UNDONE — the single largest Cluster-C v2 gap** alongside
  the C4-b1 label/body mismatch.
- Known gap / deferred (from V2GAP + verified): worked-case page, four-case spine,
  per-case reports, the `register` atomic helper, and the two registry additions
  (fold-predict v2.3, molgen v4.1 so every case names an openable object) — all UNDONE.

---

## Cross-surface canonical E2E flows (per project consolidation rules — login once,
## one project, real backend, 90 s LLM timeouts)

- **Flow C-A (Data → dataset object, §02/§04):** login → `/files` → pick project →
  expand `inputs` → observe a real quality dot (C2 quality) → open a CSV
  (`file-open-<id>`) → Preview table (C3 Preview) → Quality verdict (C3 Quality) →
  Lineage (C3) → Consumers (C3) → Versions + append a real note (C3) → Export RO-Crate
  (C3). Screenshot every tab; assert no `undefined`/`NaN`, honest-empty where the
  backend has no data.
- **Flow C-B (Models, §03/§10.1):** login → `/models` → assert 5 tracks with the **v2
  labels** + count (C4) → **assert the C4-b1 label/body mismatch** on House style &
  Rounds → Registry table → open a model → Evidence verdict (C5, expect
  `not_evaluated` on a fresh catalog) → Interface/Versions (C5) → Back → Run a model:
  structure domain → submit against `bionemo:boltz2` → poll → completed or **stub**
  (badge asserted) → structure viewer empty/held honest (C7) → repeat chemical for
  HitGrid held rows + table↔depictions toggle (C7).
- **Auth-gate probe (Flow C-C):** unauthenticated `GET /api/projects`, `/api/models`,
  `/api/models/<fake>` → 401/404 (cheap, no fixture state).
- **Coverage notes (do NOT re-implement in e2e):** the functional per-testid coverage
  is already in `docs/20260909_TESTPLAN_DATAHUB_DATASET_MODELS.md` (40 UCs) and the
  component unit tests (`components/models/models.test.tsx`,
  `viewers/dl-viewers.test.tsx`, `design-generate/DesignGenerate.test.tsx`). This UX
  plan's e2e job is the **journey + honesty + visual audit** across states, not
  re-asserting every testid.

---

## Δ (Upgrade → V2) summary table — per module

| Module | v2 § | Upgrade baseline | V2 delta | Deployed status (2026-09-11) |
|---|---|---|---|---|
| Data hub picker / two-pane / detail-empty | §02 | dataset-as-centroid picker + panes | unchanged | **DONE** (neutral) |
| Dataset → workflow routing | §02 | no CTA | dataset as launch point | **GAP** — no dataset→run CTA in the object (C1 dead-end) |
| File tree (states/folders/quality/actions/preview/upload) | §04 | full tree | formalized as part of dataset-object surface | **DONE** (neutral) |
| Dataset object (6 tabs + RO-Crate) | §04 | identity/quality/lineage/consumers/versions/origin | unchanged | **DONE** (neutral) |
| Preview sub-views (Table/Columns/Plot/Edit) | §4.3 | static profiler table | Columns/Plot + append-only in-place Edit ("writes v4") | **PARTIAL/DEFERRED** — only static table; no Columns/Plot/Edit |
| "Open in" (Jupyter/RStudio/plot/chat) | §4.3.1 | — | launch environments from the object header | **UNDONE** — no launcher on the dataset object |
| Amber inheritance (quality travels) | §4.5.2 | per-dataset verdict | amber input → amber output until human clears | **DEFERRED** — no upstream-flag propagation |
| Perception / quality panel | §02, §04 | good/watch/blocked + honest states | unchanged | **DONE** (neutral) |
| Models panel labels | §10.1 | Adapt / Optimise / Run a pre-trained model | House style / Rounds / Run a model | **DONE (labels)** but ⚠️ **label↔body mismatch** (C4-b1) |
| House style body (AdaptTrack) | §10.1 | "Adapt" ladder + learned pairs | rename + "learns wording, never changes a number" | **PARTIAL** — body not renamed; framing copy absent |
| Rounds body (OptimiseTrack) | §10.1 | "Optimise" DMTA | rename to "Propose & test in rounds" | **PARTIAL** — card title still "Optimise" |
| Registry track + row→object | §03 | catalog table | workspace/project scope split (§3.4) | **DONE** table; **PARTIAL** scope split (no `scope` prop) |
| Model object (5 tabs, evidence gate, no leaderboard) | §03.3 | full object | unchanged in v2 | **DONE** (neutral). Unwired actions = journey dead-end on `/models` |
| Published-vs-held-out label | §3.2.4 | — | published+spot-check earns the gate | **DEFERRED** — not surfaced |
| Owner-role register gate | §3.6 | — | RBAC on register | **UNDONE** — no RBAC in models UI |
| Run a model track (inference) | §3.2.4 | — (no such track) | NEW 4th track, honest stub | **DONE (new)** |
| Structure viewer (pLDDT/PAE) | §3.8.1 | — | NEW; chart LINKED to 3D | **PARTIAL** — chart/PAE done; 3D slot is a placeholder, pLDDT→3D lands only in a caption |
| Genomic viewer (SeqTracks + flagged) | §3.8.2 | — | NEW | **DONE (new)** |
| Chemical viewer (HitGrid, held rows, 2 views) | §3.8.3, §5.5.1 | — | NEW; table↔depiction, held no-number | **DONE (new)**; 2D depiction is a keyed slot (**PARTIAL** drawing) |
| Wet-lab loop: round-as-contract stage bar + predicted-vs-measured | §3.7 | — | NEW | **UNDONE** — DMTA rounds render as a list; no stage bar / pred-vs-meas view |
| ModelCase worked-case page (4 cases, register helper) | §10 | absent | NEW chapter | **UNDONE** — not built (C8) |

---

## Summary (5 lines)

1. Covers every Cluster-C function — data hub (§02), file tree + dataset object (§04),
   the 5 Models tracks + model object (§03/§10.1), Run-a-model inference + all four
   wave-1 viewers (§3.8), and the ModelCase worked-case page (§10) — each scored on all
   7 rubric dimensions for both Upgrade and V2, with real testids and endpoints from the
   live source.
2. **V2GAP corrections from reading the live tree:** the §10.1 track **labels ARE now
   shipped** (Train/House style/Rounds/Run a model/Registry) and the "Run a model" track
   + §3.8 viewers + honest stub are DONE — contradicting the 2026-09-09 gap doc's
   "UNDONE" rows.
3. **New Cluster-C defect found (C4-b1):** the v2 track **labels were renamed but the
   bodies were not** — "House style" renders the `AdaptTrack` ("Adaptation level"),
   "Rounds" renders the `OptimiseTrack` ("Optimise …"); the tab label and the card title
   disagree. This is the most user-visible v2 gap here.
4. **Still UNDONE / deferred (honestly marked):** the Spec-10 `ModelCase` worked-case
   page (0 hits — C8), the owner-role register gate (§3.6, no RBAC), the
   published-vs-held-out label (§3.2.4), a real 3D viewer + literal pLDDT→3D centring in
   the pretrained path (§3.8.1 — slot placeholder, caption-only linkage).
5. **Journey/honesty gaps to record as fails-not-passes:** no dataset→workflow CTA in
   the dataset object (§02 centroid dead-ends); `onUseInRun`/`onSupersede` +
   lineage/consumer links render but no-op on `/models` (unwired); populated
   Train/House-style/Rounds and a real evidence `pass`/`fail` are **data-dependent**
   (test only against seeded state, else untested = fail per the skip rule).
