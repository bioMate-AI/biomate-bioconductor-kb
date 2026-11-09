# UI / System refinement issues — triage (2026-11-08)

Source: `Desktop/.../UI_refinement/Archive.zip` (30 screenshots), captured on the
`MG PBMC — sample data demo` project (nf-core/differentialabundance), **Chinese UI**.
Each issue below: **[F]** = format/appearance mismatch, **[X]** = functional failure.
Grouped by root-cause cluster so one fix closes several screenshots.

---

## Cluster 1 — Internal IDs / raw paths leak into user-facing text  [F]
The LLM and several panels print run IDs, file UUIDs and full S3 URIs that users
should never see; names should be shown, IDs kept internal.
- `ID_everywhere.png` — chat prints `run ID 7ed96e78`.
- `unnecessary_id_response.png` — chat file list prints `counts_matrix.csv (id: 6ad52149-…)` ×3.
- `crowd_parameters_unnessaryid_sameQC_eachphase.png` — param summary embeds `contrasts.csv (id: b716…)`.
- `unnecessary_detail_workflowpanel.png` — input mapping shows friendly name **plus** full
  `s3://biomate-nextflow-work/uploads/project-…/file.csv` **plus** the UUID, and the
  Contrasts row prints `contrasts.csv (id:…)` **twice**.
- `missing_file_context.png` — tells the user to paste `s3://biomate-nextflow-work/…`.
**Fix:** (a) prompt/response rule to never surface run/file IDs or bucket URIs in prose;
(b) input-mapping component shows basename only (UUID/S3 path behind a hover/"details"),
de-duplicate the Contrasts row.

## Cluster 2 — i18n: English strings in the Chinese UI / EN–CN mixing  [F]
Large coverage gap — whole surfaces render English under a `zh` locale, and some
components mix both in one card.
- `English_in_Chinese_UI_oldinfo.png` — after-run empty state ("Run not started yet…").
- `duplicate_after_run.png` — "AFTER RUN" heading (also a *duplicate*, see Cluster 6).
- `half_half_views.png`, `un_expected_workflow_otherintent.png` — "✅ I've generated a
  workflow…", "Input files required: Samplesheet, Contrasts…" inside otherwise-Chinese cards.
- `MG_workflow_failed.png` — failure alert English, button "重试" Chinese.
- `commentout_skip_phase.png`, `crowd_parameters….png` — phase descriptions ("Phase B —
  Normalisation — this workflow does not declare a skip parameter…") English; Phase D Chinese.
- `lack_multi_select.png`, `biomate_history_weirditem.png`, `need_better_design_claude.png` —
  the whole **Select dataset** dialog (tabs, buttons, body) English; search box Chinese.
- `formats_duplications.png` — project page ("All projects", "Start a new chat…", "Standing
  instructions", "active") English under a Chinese shell.
- `noteasexample_instruction_rule.png` — seeded rule text English.
**Fix:** audit these components for hard-coded English → `t()` keys in `locales/{en,zh}`;
the workflow-panel phase/skip/input strings and the dataset-picker dialog are the biggest gaps.
Note: some English comes from the **LLM response** (Cluster 5), not a static string — those
need a prompt/locale instruction, not a `t()` key.

## Cluster 3 — Dataset profiler fails on small CSVs → false "needs attention"  [X]
The analyzer cannot profile the demo CSVs even though the client parses them fine
(Table preview and Edit view both render the rows/cols).
- `QC_wrong_under_溯源.png` — "概况不可用 — 分析器无法读取该数据集" (profile unavailable).
- `cannot_handle_csv_dataset.png` — stat grid 行数/列数 = "—" (but Table shows "1 行 × 5 列").
- `needattention_why_dataset.png` — amber **需关注** badge with no stated reason.
- `only_manual_editing_dataset.png` — **same file**, Edit view shows 行数=1 列数=5 (so the
  data is parseable; the profile path is what fails).
**Fix:** find why the profiler returns "cannot read" for these (likely a
header-only / 1-row CSV or a size/delimiter edge in the perception profiler); fall back to
the client-parsed sample for rows/cols when the full profile is unavailable; and do **not**
show amber "需关注" when the cause is "couldn't profile" — show a neutral "未分析" with a reason.

## Cluster 4 — Workflow panel: wrong/duplicated QC gates & param logic  [X]
- `crowd_parameters_unnessaryid_sameQC_eachphase.png` — the **same** alignment QC gate
  (Reads Surviving Trim ≥50%, Mitochondrial Reads ≤80%, Alignment Rate ≥5%) is shown on
  **every** phase, including Phase C (Differential Abundance) and Phase D (Report) where
  alignment metrics don't apply. QC gates are being applied generically, not per-phase.
- `file_input_necessary_or_not.png` + `half_half_views.png` — Samplesheet/Contrasts labelled
  **可选——留空 (optional)** per-row, but the run gate says **Input files required:
  Samplesheet, Contrasts**. Required-ness computed inconsistently (ties to commit
  `5e812ef429` "null params are required only when the workflow enforces them").
- `confusing_workflow_parameter.png` — Settings tab says "此工作流没有可配置的参数" while the
  Phases tab shows 4 configured params. The two tabs disagree on whether params exist.
- `path_parameter_editissue.png` — S3-path param input truncates to `s3://biomate-nextf…`,
  too narrow to read or edit the value.
**Fix:** (a) only render a phase's QC gate when metrics are declared for *that* phase;
(b) single source of truth for required-vs-optional (don't block the run for inputs labelled
optional, or label them required); (c) reconcile the Settings "no parameters" copy with
per-phase params; (d) widen/auto-expand the path input (textarea or full-width on focus).

## Cluster 5 — Chat intent & file-context failures  [X]
- `missing_file_context.png` — assistant says `sample_metadata.csv`/`contrasts.csv` are
  **缺失 (missing)** and asks the user to upload them, though both are already in the
  project's Files. The assistant isn't seeing already-uploaded project files.
- `un_expected_workflow_otherintent.png` — "also add the other two files" (an attach/context
  action) triggers **workflow generation** ("✅ I've generated a workflow…"). Intent misrouted.
- `ID_everywhere.png` — "edit the findings report" → assistant asks the user to *paste the
  report text* / "confirm you've opened it", instead of fetching the saved report itself.
**Fix:** inject the project's existing files into the chat context (so the model doesn't call
them missing); gate workflow-card generation so a pure "add files" turn doesn't spawn one;
wire `edit_report` to load the run's stored report rather than asking the user to paste it.

## Cluster 6 — Controls that should be hidden / de-duplicated  [F]
- `commentout_skip_phase.png` — the whole **跳过阶段** section renders 4 disabled checkboxes +
  4 "无法跳过" warnings because nothing is skippable. Per the design standard (skip controls
  hidden when unsupported), hide the section when no phase is skippable.
- `comment_out_chat_for_newstep.png` — "+ 通过聊天建议新步骤" button (no backend) — remove/hide.
- `duplicate_after_run.png` — "AFTER RUN" heading duplicates the "运行结果" tab name — drop it.
- `formats_duplications.png` — three redundant chat-start entry points (top-right **Chat**,
  center **+ New Chat**, **Chat/Files** tabs) + sidebar 新对话/新建对话 — consolidate.

## Cluster 7 — "Open in Jupyter" (interactive tool) fails  [X]
The open-in endpoint stages the file but the IT session isn't reachable/ready.
- `jupiter_failed.png` — `Jupyter: connect ECONNREFUSED 172.19.0.2:8080` (raw internal IP
  shown to the user).
- `jupiter_fail_anothermessage.png` — "The file was staged, but the notebook session is not
  ready. This launch may still be active…".
**Fix:** the HDA-readiness follow-up I flagged earlier — poll the staged HDA to `ok` and the
IT session to ready before returning a URL; surface a friendly "starting your notebook…"
state instead of ECONNREFUSED/IP; de-duplicate repeat launches.

## Cluster 8 — Dataset picker ("Select dataset") quality  [X/F]
- `lack_multi_select.png` — one **Use** button per row; no multi-select, so "add the other
  two files" is one-at-a-time. Add checkboxes + "Use selected".
- `biomate_history_weirditem.png` — BioMate-history tab lists **errored "Executed Notebook"
  (ipynb)** items and internal `GalaxyChat-2026-10-10` history names as selectable datasets.
  Filter out errored/non-dataset history items.
- `need_better_design_claude.png` — **From URL** tab is a wall of English example URIs; needs
  a cleaner, localized design.

## Cluster 9 — Layout / empty-state polish  [F]
- `large_blank_dataset.png` — data hub right pane is a huge empty box with one centered
  "选择一个数据集"; auto-select the first dataset or make the empty state compact/useful.
- `half_half_views.png` — workflow panel right side mostly blank under "此工作流没有可配置的参数".

## Cluster 10 — Project collaboration / memory concepts (needs product decision)  [F/X]
- `note_memory_howworks.png` — Notes "不会被助手读取" vs Rules "每次对话读取" vs project memory —
  the three concepts are confusing; clarify or consolidate.
- `how_works_teammember.png` — verify invite-link / email-invite / role (查看者/所有者) actually
  functions end-to-end (sends invite, enforces role).
- `noteasexample_instruction_rule.png` — a seeded tutorial instruction shows as a real user
  Rule; make demo-seeded rules distinguishable from user-authored ones.
- `preview_confusing_report_template.png` — report-template **预览** UX is unclear.

---

## Priority (recommended)
1. **Cluster 3** (profiler false-amber) + **Cluster 5** (missing file context / intent) —
   functional, hit the core demo flow, erode trust.
2. **Cluster 2** (i18n) + **Cluster 1** (ID leakage) — high-visibility, mostly mechanical.
3. **Cluster 4** (QC-gate/params logic) + **Cluster 7** (Jupyter readiness) — functional.
4. **Cluster 6** (hide dead controls) + **Cluster 8/9** (picker/layout) — polish.
5. **Cluster 10** — needs product decisions; triage with the user.

## Status

### Batch 1 — FIXED (low-conflict files, tsc clean, suites green)
- **Cluster 1** — input-mapping rows show the **basename only** (full S3 URI / dataset id
  moved to a hover title); the Contrasts duplicate is gone (dedupe by name in
  `buildViewerParameters`, required entry wins). `nextflow-workflow-viewer.tsx`.
- **Cluster 3** — dataset profiler no longer false-fails small CSVs:
  - frontend `datasetShape` (`dataset-presentation.ts`) now reconciles the stat grid with the
    parsed preview — derives rows/cols from `columns`/`sampleRows` when `shape` is absent, so a
    file the Table/Columns/Edit views can display never shows "—".
  - backend `data_perception.py` `_profile_table`: a header-only / 0-data-row CSV is now a
    **readable empty table** (columns surfaced, rows=0) instead of `blocked`/"cannot read";
    test `test_blocked_empty_and_missing` updated to the corrected contract. Verified:
    header-only → good/0×3/columns; 1-row → 1×3; missing file → still blocked.
- **Cluster 4** —
  - Settings tab no longer says "no configurable parameters" when params are pinned to phases;
    shows "configured per phase — open the Phases tab" instead.
  - required-vs-optional **contradiction** resolved: the run gate (`missingFileInputs`) now
    respects `p.required` (was blocking every empty file input), matching the per-row
    "optional — empty" label + the footer. (cf. commit 5e812ef429.)
- **Cluster 5** — path-param `<Input>` gets `flex-1 min-w-0` so S3 URIs are readable/editable
  (`parameter-group.tsx`).
- **Cluster 6** — skip-phases section hidden unless ≥1 phase is actually skippable;
  "+ suggest new step via chat" button removed; the duplicate "AFTER RUN" kicker on the pre-run
  placeholder now honours `!embedded` (`AfterRunReport.tsx`) and the empty-state strings are
  localized (`afterrun.empty_*` added to zh).

### Batch 2 — TODO (this session, lower conflict)
- **Cluster 2 (i18n sweep)** — remaining hard-coded English, exact locations mapped:
  - run-footer msgs `nextflow-workflow-viewer.tsx` ~4660–4678 (License required / Fill in N
    required params / Input files required / Prerequisites not met).
  - Select-dataset dialog `galaxy-dataset-browser.tsx` (tabs, Use/Import, From-URL help) —
    also **Cluster 8** (multi-select, filter errored "Executed Notebook" + internal history).
  - project page `project-detail.tsx` (All projects / Start a new chat / Standing instructions / status badge).
  - skip-dependency `why` prose (`skip-dependency.tsx:129`) — backend phrase → client key map.
- **Cluster 9** — oversized blank dataset/workflow empty states.

### Batch 3 — DEFERRED (HOT files owned by the live chat-tools session — document, don't edit now)
- **Cluster 5 (chat)** — missing project-file context (`routes.ts` `_sessionDatasetsResolved`
  ~7126; inject all `project_files`), intent misrouting "add files"→workflow
  (`galaxy-assistant.ts` guard ~5357 + `inferActionsFromType`), `edit_report` self-load
  (`galaxy-assistant.ts` `_toolEditReport` ~11274 — reconstruct report server-side).
- **Cluster 7 (Jupyter)** — HDA/IT readiness poll before returning a URL; friendly error vs
  `ECONNREFUSED <ip>` (open-in endpoint in `routes.ts`).
- **Cluster 4 (QC-per-phase)** — needs per-phase metric declaration plumbed through
  (`ViewerPhase`); gate the QC block to a phase's own metrics instead of one shared array.

### Batch 4 — NEEDS PRODUCT DECISION (Cluster 10)
- Notes vs Rules vs memory consolidation; team-invite/role functionality; demo-seeded-rule labeling;
  report-template preview UX.
