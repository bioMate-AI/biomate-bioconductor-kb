# BioMate UI — comprehensive end-to-end test plan

Date: 2026-11-04. Target: **dev** (`https://dev-public.biomate.ai`), logged in as the shared fixture `lifeifei163361@163.com`. Desktop viewport (≥1300px) for side-by-side chat+panel; a second pass at ≤800px for the responsive/mobile layout.

## Purpose & method

Verify **every UI element, in every state, through real end-to-end flows** — not a shallow "it renders" pass. Every workflow element is exercised by actually generating and running a workflow on the live backend (AWS Batch), watching the real SSE state transitions, and inspecting the real outputs/findings. No mocking. Each row below is `PASS` / `ISSUE` / `BLOCKED` with a one-line evidence note (screenshot id, error text, or behaviour observed).

This plan doubles as the coverage contract for the CLAUDE.md "UX E2E Completeness Standard" and "Chat + Workflow Panel Presentation Standard".

Legend: ☐ not yet run · ✅ pass · ⚠️ issue · ⛔ blocked.

---

## A. Global chrome — sidebar (left)

| # | Element | E2E action | Status | Evidence / note |
|---|---|---|---|---|
| A1 | Collapse/expand sidebar toggle | click → icon rail; click again → expand | ☐ | auto-collapses when the workflow panel opens at ~1325px (observed) |
| A2 | WORKSPACE › New Chat | click → fresh chat session | ☐ | |
| A3 | WORKSPACE › Workflows | click → **Starred Workflows** dialog | ⚠️ | **Dead/orphaned feature.** Dialog renders (search, filters, list, View/Run/delete), but the 3 items (RNA-seq / Variant Calling / QC) are **hardcoded demo defaults** (`getDefaultStarred()` in `lib/starred-workflows.ts`, returned when localStorage is empty — which is always). `starWorkflow()` (add) is **never called anywhere** in the client — no star affordance exists. Fake "Starred N days ago" timestamps. Fix: wire a star action, or remove the dead dialog/seed. |
| A4 | WORKSPACE › Data | click → datasets browser | ☐ | |
| A5 | WORKSPACE › Connectors | click → connectors directory | ☐ | |
| A6 | WORKSPACE › Models | click → models view | ☐ | |
| A7 | PROJECTS › list + expand | expand a project → Instructions / Files / chats / New chat | ☐ | MG PBMC expands to Instructions, Files, chat entries, + New chat |
| A8 | PROJECTS › + New project | click → create-project flow | ☐ | |
| A9 | OTHER CHATS › list | open a past chat → restores its messages+panel | ☐ | server-backed (`/api/sessions/:id`); tests session restore |
| A10 | User footer › Settings (gear) | open Settings dialog → traverse every tab/control | ☐ | |
| A11 | User footer › Sign out | present + styled (do NOT click) | ☐ | |
| A12 | User footer › avatar/name | shows fixture identity | ✅ | "WPM F… / lifeifei1…" |

## B. Global chrome — top bar

| # | Element | E2E action | Status | Evidence / note |
|---|---|---|---|---|
| B1 | Project breadcrumb | reflects active project/chat | ✅ | "MG PBMC — sample data demo / chat" |
| B2 | Go to project | click → project detail | ☐ | |
| B3 | Close project context (X) | click → leaves project scope | ☐ | |
| B4 | Hide chat | click → collapses chat, panel full-width | ☐ | |
| B5 | Run Manager (count) | click → run manager; count reflects runs | ✅ | count moved 50→0 (new chat) →1 (run started); live |
| B6 | Refresh run list | click → re-polls | ☐ | |

## C. Chat empty-state (composer)

| # | Element | E2E action | Status | Evidence / note |
|---|---|---|---|---|
| C1 | Goal input ("What are you trying to do?") | type → intent preview appears | ✅ | preview "Prepare an analysis · review before starting · Drug discovery" on an ADMET prompt |
| C2 | Goal send button | submit → routes to chat | ✅ | |
| C3 | Card: Search & evidence | click → seeds search intent | ☐ | |
| C4 | Card: Data analysis | click → seeds data-analysis intent | ☐ | |
| C5 | Card: Molecule design & generate | click → seeds generate intent | ☐ | |
| C6 | Card: Models | click → seeds model intent | ☐ | |
| C7 | Bottom input + Send | type + send | ✅ | submitted the ADMET request |
| C8 | Attach data (paperclip) | click → dataset picker / upload | ☐ | |
| C9 | Skills & experts dropdown | open → options | ☐ | |
| C10 | Instructions (standing) | click → instructions panel | ☐ | has a status dot |

## D. Chat conversation elements

| # | Element | E2E action | Status | Evidence / note |
|---|---|---|---|---|
| D1 | User message bubble | renders sent text | ✅ | |
| D2 | AI text response (markdown, structured) | correct domain reasoning, **no "undefined"** | ✅ | terfenadine hERG/FDA-1998 reasoning + "I've generated a workflow" |
| D3 | Workflow card (name, domain, step count) | appears below AI text | ✅ | "Predict ADMET Properties (AI)" |
| D4 | wf-chip "In panel" badge | shows when open in panel | ✅ | green "In panel" |
| D5 | Card status badge (Running/Completed/Failed) | tracks live run status | ✅ | flipped idle→**Running** live; failure toast on fail |
| D6 | Card action row (copy/save/re-run/download/thumbs) | each present + clickable | ☐ | row visible; re-run behaviour = scenario UC-R |
| D7 | Findings preview / answer-block | post-run summary in chat | ☐ | needs a completed run |
| D8 | Alert banners (warn/error/info) | correct icon+colour | ☐ | |
| D9 | DisambiguationCard | when `workflow_type==='disambiguation'` | ☐ | needs an ambiguous prompt |

## E. Workflow panel — elements & states (the core)

### E-elements
| # | Element | Status | Evidence / note |
|---|---|---|---|
| E1 | Header: domain · WORKFLOW + name (not "undefined") | ✅ | "DRUG DISCOVERY · WORKFLOW / Predict ADMET Properties (AI)" |
| E2 | Header: project chip, expand, close | ✅ | Project chip + expand + X |
| E3 | Status badge (idle/Running/Failed/Completed) | ✅ | saw Running + Failed |
| E4 | Tabs: Workflow settings (N) / Phases (N) / After run | ✅ | counts shown (3/1); After-run red dot on fail |
| E5 | Workflow settings › Inputs mapped | ✅ | "takes parameters only — no data inputs to bind" |
| E6 | Parameters: Required (Smiles List, Admet Model Type) | ✅ | **extracted hERG, DILI correctly**; Recommended/Override chips; Add |
| E7 | Parameters: Optional (collapsed) | ✅ | "1 param — collapsed by default" |
| E8 | Phases: step list + progress + per-step status | ✅ | Admet Infer Shard RUNNING, Predict Admet Properties pending, 0/2 |
| E9 | QC GATES table | ✅ | Cipa Qnet High/Intermediate thresholds |
| E10 | Show logs & AI status | ☐ | collapsible present |
| E11 | After run › AI Diagnosis | ✅ | "stopped before completing… Resume from last step… transient" |
| E12 | After run › RUN FAILED/COMPLETED banner + full error | ✅ | full `NoSuchFileException` cause shown (not truncated) |
| E13 | After run › Download | ☐ | dropdown present |
| E14 | After run tabs: Summary / Outputs / Report | ☐ | present; need completed run for content |
| E15 | Findings tab content (completed) | ☐ | **must show real values, not "Analysis in progress…"** |
| E16 | Footer buttons by state | ✅ | Confirm & Run (idle) · Pause+Stop (running) · **Restart** (failed) · Reset to defaults |

### E-states matrix (each must be observed live)
| State | Required UI | Status | Evidence |
|---|---|---|---|
| pre-run (idle) | name, param strip, Confirm & Run | ✅ | ss pre-run |
| running | Running badge, live phase/step SSE, Pause+Stop | ✅ | live step transitions |
| **completed** | COMPLETED badge, Run again, Outputs+Findings+Report | ☐ | **pending a successful run** |
| failed | FAILED badge, Restart, full error, Findings="not available" (no spinner) | ✅ | NoSuchFileException run |
| QC-blocked | gate alert, measured-vs-threshold, Fix/Confirm | ☐ | needs a run that trips a gate |
| paused | paused footer, resume | ☐ | click Pause on a running run |
| **re-run → new card** | finished card preserved + new card appended (my fix) | ☐ | scenario UC-R |

## F. Use-case E2E scenarios (each full lifecycle)

| ID | Scenario | Prompt / setup | Status | Evidence / note |
|---|---|---|---|---|
| UC-ADMET | ADMET screening | terfenadine SMILES, flag hERG/DILI | ⚠️ | pre-run✅ running✅ **failed** (NoSuchFileException on ADMET_INFER_SHARD output — infra/shard path, flagged transient; UI handled failure correctly). **Retry to get a completed run.** |
| UC-RNAseq | RNA-seq DE | FASTQ paths / sample data | ☐ | nf-core/rnaseq → SSE steps → findings |
| UC-WGS | WGS / variant calling | genome param | ☐ | sarek → GATK → VCF preview |
| UC-CryoEM | CryoEM SPA | MRC files | ☐ | cryosparc_standard_spa → 3D output |
| UC-CRO | CRO compliance | CRO Library → campaign → attach ADMET → export | ☐ | (CRO Library nav may be relocated — confirm) |
| UC-IND | Drug-discovery IND | PBPK + clinical → §2.6.1 narrative → DOCX | ☐ | |
| UC-R | **Re-run card (my fix)** | on a completed run, click Run again | ☐ | expect new card appended + finished card preserved + per-card reopen (`isInPanel` fix) |
| UC-SSE | **SSE resilience (my fix)** | navigate away mid-run + return | ☐ | panel must resume live updates (reconnect + poll fallback) |
| UC-QC | **QC degraded (my fix)** | run where QC can't evaluate | ☐ | after-run QC shows amber "UNAVAILABLE", not empty "all passed" |

## G. Dialogs & routes

| # | Surface | Status | Evidence / note |
|---|---|---|---|
| G1 | Starred Workflows dialog | ✅ | A3 |
| G2 | Data / datasets browser | ☐ | |
| G3 | Connectors directory | ☐ | |
| G4 | Models view | ☐ | |
| G5 | Settings dialog (all tabs) | ☐ | |
| G6 | Run Manager / dashboard | ☐ | open a past run → its outputs |
| G7 | Project detail (Instructions / Files) | ☐ | |
| G8 | `/histories` + `/datasets` error surfacing (my fix) | ☐ | induce an error path → "couldn't load — retry" (hard to force) |

## H. Cross-cutting

| # | Check | Status | Note |
|---|---|---|---|
| H1 | Console error sweep (per surface) | ☐ | read_console_messages onlyErrors across the session |
| H2 | No "undefined" in any visible text | ✅ so far | none seen |
| H3 | Responsive layout (≤800px) | ☐ | "limited on mobile" banner at <768px |
| H4 | Panel error boundary (my fix) | ☐ | a render crash shows localized fallback, not blank app (hard to induce) |

---

## DEEP findings — content & logic correctness (completed ADMET run 82c1245a, terfenadine)

Pulled the real output files (`toxicity_report.json`, `qc_metrics.json`, `findings_data.json`) via `/api/files/preview` and checked the actual values, not just rendering.

> **CONFIRMED IN CURRENT CODE** (root-cause audit of the current worktree — not an old-run artifact):
> - **BUG 1 root cause** — `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf`: top-level `toxicity.dili_probability` is seeded by a **Phase-1 RDKit logP heuristic** `0.55 + 0.05*(logP−4)` → 0.672 for terfenadine (logP 6.4). The Phase-2 ADMET-AI override is **asymmetric** (lines ~479-485: `if dili_p>=0.65: high; elif >=0.40 and risk!=high: medium` — **no `else`**), so a LOW AI DILI (0.0408 < 0.40) never overwrites the stale 0.672/"high". hERG & clintox are overwritten **unconditionally** (hence hERG is correct); DILI is the sole asymmetric metric. `per_compound` is synced to the AI value (0.041), so aggregate≠per-compound for n=1. **QC gate reads the stale aggregate** (`main.nf` qc_metrics lines ~789-815 + executor `_extract` `nextflow_executor.py` ~4741/4855) → DILI gate FAILS wrongly. Same bug in `ADMET_pred/main.nf` (~lines 127-158, 274-280) + its archived copy. Fix: make DILI aggregation unconditional/single-source like hERG (described in the audit).
> - **BUG 2 root cause** — two independently-computed liability verdicts merged with NO reconciliation: flat `summary`/`key_results` from `routes.ts` `_parseAdmetOutput` (~15258-15294, flags hERG+CYP2D6) vs embedded `findings_document.summary` from `shared/findings-extract.ts` `buildFindingsDocument` (~193-197) whose `ADMET_REPORT` descriptor (`shared/findings-descriptors.ts` ~55-76) carries **no hERG-prob / CYP2D6 metric** → "No major liabilities flagged." Merged at `routes.ts:15806`. Generalizes to the **VARIANT/raredisease** descriptor too (can also produce liability-vs-"none" contradictions); DESeq2/enrichGO milder (wording only). Frontend fix (reconcile the two) is safe to edit; the `.nf` DILI fix needs human application per CLAUDE.md.

**Correct (validated):** hERG_probability **0.977** + herg_ic50 **0.0103 µM** (sub-µM) → terfenadine IS a potent hERG blocker, withdrawn 1998 — scientifically right, and the AI narrative matched it. MW **471.7**, logP **6.45** → correct for terfenadine. `herg_safe_above_10uM: false` → correct hERG gate logic. Real citations (Redfern 2003, Kazius 2005, Mulliner 2016). CYP2D6 0.861 flagged — sensible.

**⚠️ BUG 1 — DILI aggregation is inconsistent for a 1-compound run (propagates to the QC gate).**
Same run, same compound, three different DILI numbers:
- `toxicity.dili_probability = 0.672`, `dili_risk="high"`, `dili_aggregation="worst_compound_in_panel"`
- `per_compound[0].dili_probability = 0.041`, `dili_risk="low"`; `per_compound_admet_ai[0].DILI_prob = 0.0408`
- `qc_metrics.json`: `dili_probability = 0.672`, `admet_dili_probability_passes = false` (0.672 > 0.5 threshold)
For **one** compound, "worst_compound_in_panel" must equal the per-compound value (**0.041**), not 0.672. So the top-level DILI (0.672) is wrong, and because **qc_metrics uses the 0.672 value, the DILI QC gate is recorded as FAILING** when the compound's real DILI (0.041) passes. A wrong aggregate drives a wrong safety-gate decision.

**⚠️ BUG 2 — `findings_data.json` self-contradicts on the liability verdict.**
- `summary` + `key_results`: flags **hERG (0.977, "potential liability")** and **CYP2D6 (0.861, "potential liability")**.
- embedded `findings_document.summary`: **"No major liabilities flagged."**
The two summaries in the same file disagree; the findings-document verdict ignores the hERG/CYP2D6 flags the same file raises.

These are exactly the kind of content/logic defects that a render-only pass misses. Both are **backend ADMET-aggregation/findings bugs** (not UI), to be filed and fixed in the ADMET workflow's report/aggregation step. The hERG path is correct; the DILI aggregation and the findings-document verdict are not.

## Cross-domain deep content audit (4 completed runs, parallel agent)

All runs below are **1–2 weeks old** (ran 2026-10-26…10-29) → same caveat: verify against current code before filing.

- **🐞 BUG 3 (safety) — clinical/BOIN dose escalation** (`c93845cd`, ran 2026-10-26, `clinical_trial_simulation`). Same class as the ADMET bug: a downstream recommendation contradicts the run's own safety analysis. The run computes `true_MTD_dose_mg = 20` (40 mg flagged overdosing, P_select 5.9%) and its own BOIN rule de-escalates at DLT/n ≥ 0.325 while 40 mg has `true_DLT_rate = 0.362` — yet `recommended_Phase2_dose = "40 mg QD"`. Root cause: Phase-2 dose is picked purely by efficacy `P_success` (40 mg = 1.0), ignoring the MTD safety ceiling the same run produced (20 mg had a safe P_success 0.84). **Recommends an overdose its own safety flags.** Everything else in the run is numerically coherent (probabilities sum to 1.0, DLT monotonic, Cmax linear) → the bug is isolated to dose-selection logic. Minor: `qc_events` labels the gate "FASTP" (a read-trimmer) for a clinical trial — nonsensical but `not_evaluated`, no false gating.
- **⚠️ GAP — `inline_findings` is empty `[]` on ALL FOUR non-transcriptomics completed runs** → the AI-findings/summary layer is not populated for these domains, so the **Findings panel would be empty despite rich output files** (findings↔outputs gap). (This also means the ADMET-style "two summaries disagree" bug can't occur here — there's no summary at all.) Verify whether current code populates findings for these domains.
- **CLEAN (with proof values):** CAR-T co-design (`dc9f3235`) — construct `total_aa_length=519` matches a residue count of the FASTA (519) ✓, atlas VIABLE + no fratricide ⇒ GO. hERG QSAR (`d3b10f85`) — safety_margin 0.248/0.4532 = 0.547 ⇒ QTc HIGH correctly derived. QSAR RF (`131ec76f`) — cv_r2 0.201 < 0.50 ⇒ QC FAIL correctly derived. These domains' raw outputs are internally consistent.

## Transcriptomics/RNA-seq deep content audit (6 runs, parallel agent)

- **CLEAN (proof):** `4dbcc0cf` nf-core/differentialabundance (MG_AChR_pos vs HC) — independently counted exactly 10 sig genes (padj<0.05 & |log2FC|≥1) matching `qc_metrics.n_significant=10`; BH ordering valid (0 padj<pvalue); biologically correct (complement cascade CFD/C3/C4↑ — right for AChR+ myasthenia gravis). `2aa0891e` airway/dex — canonical dex genes (SPARCL1/PER1/MT2A) with real Ensembl IDs, correct stats.
- **🐞 BUG 4 — GEO pseudobulk contrast is biologically meaningless** (`640b7e9d`, `geo_scrna_pseudobulk`): the DE contrast is `"Public on Jun 10 2010_vs_Public on May 28 2010"` — it grouped samples by **GEO publication date** and "ran DE" on it. No DESeq2 results file produced despite status **completed**; gene IDs are bare integers ("1","2","3"), first row all-zeros.
- **🐞 BUG 5 — GEO pseudobulk contrast mixes two metadata axes** (`863429cf`): contrast = `"disease state: HNSCC, N+ _vs_ sample type: 15 human cell lines (…)"` — compares a *disease-state* label against a *sample-type* label (different GEO characteristic keys). No DE output, "completed". Both 4 & 5: the **scRNA-pseudobulk workflow was misapplied to bulk microarray** (`data_type=microarray`, `pseudobulk_method=none`) and the GEO metadata/contrast parser picked a non-biological field. Real correctness bug in the GEO→contrast path.
- nf-core/rnaseq quantification runs (`9248235b`, `27ee39ab`) — appropriately make no DE claims (quantification only); not fabricated.

## Cross-cutting structural gaps (seen on EVERY completed run, both content agents)

- **⚠️ GAP A (CORRECTED — earlier overstated):** `inline_findings` (run-record field) is empty on all runs, but findings ARE generated for ADMET (`findings_data.json` present + renders in the UI). Real split: **(5a)** findings-file generation is wired for ADMET but NOT CAR-T/clinical/DE (no `findings_data.json` → *those* Findings tabs empty); **(5b)** the `inline_findings` field is vestigial/unpopulated even for ADMET, but the UI reads the file, so it does not blank the Findings tab. NOT "findings broken everywhere." See fix-spec #5.
- **⚠️ GAP B — run-record `metrics` block is all-zero** (runtime 0, resources 0, fileCount 0) on every run despite real output files present → runtime/resource bookkeeping never populated (also means billing/usage attribution from this block would read zero).

## Dead / half-wired / mock-as-real features (code audit — CURRENT worktree code, no date caveat)

The Starred-Workflows pattern generalizes broadly. All verified against call sites.

- **[HIGH] Starred Workflows** — worse than first seen: besides no star-add + fake `getDefaultStarred()` demo data, the dialog is mounted WITHOUT an `onWorkflowSelect` prop (`app-sidebar.tsx:490`), so **Run + card-click are no-ops** (just close), and **View** is a comment-only no-op (`starred-workflows-dialog.tsx:237`). Only Unstar works.
- **[HIGH] Recent Tools** — `recentToolsService.addRecentTool()` is only ever called from inside the dialog itself, so the list is always `getDefaultRecent()` = 5 hardcoded demo tools (FastQC/HISAT2/SAMtools/DESeq2/Trimmomatic) with fake "N hours ago". **Star** and **View documentation** buttons are comment-only no-ops. Clicking a tool opens `ToolIntroductionDialog` whose **Start chat** / **Add to workflow** CTAs are `console.log` stubs (`App.tsx:883,888`). A whole browse→detail→act flow that is demo-data end to end, terminating in no-ops.
- **[HIGH/MED] Projects page serves demo projects as the user's real ones** — `pages/projects.tsx:59,61,64` falls back to `projectService.getAllProjects()` → `getDefaultProjects()` (fake "biomate AI", "LIS"…) whenever `/api/memory/projects` returns empty OR errors. They're clickable into real-looking detail pages (`project-detail.tsx:243`). A new user (or any user on an empty/erroring API) sees fabricated projects. (Sidebar itself is clean — uses live `/api/projects`.)
- **[LOW] ConnectorsDialog mounted but unreachable** (`app-sidebar.tsx:492`; `setShowConnectorsDialog(true)` never called — Connectors nav routes to `/settings/connections`). Dead mount.
- **[LOW] Orphan mock components** (not imported anywhere): `tool-browser.tsx` (`mockCategories`), `enhanced-workflow-builder.tsx` (`mockWorkflowSteps`, console.log handlers, + a `.tsx.backup`), `workflow-builder.tsx`, `dataset-dialog.tsx` (`mockDatasets` "Sample RNA-seq FASTQ"…). Dead files, but mock-as-real if ever mounted.
- **[LOW] Dead plumbing:** `onCategorySelect`/`handleCategorySelect` threaded through ~8 layers to a console.log; `recentProjects` computed but unrendered.
- **Checked & FINE:** settings DO persist (`updateSetting`→localStorage), corrections/feedback wired, chat-history has no mock fallback (`getDefaultSessions` returns `[]`).
- **Actionable:** a CI guard for this class already exists — `__wiring__/wiring-contracts.test.ts` (no-dead-affordance / trust-boundary contracts) — but it does NOT cover the three HIGH findings above. Adding them would prevent regressions.

## Findings so far (surface/UI)

1. **UC-ADMET failed at `ADMET_INFER_SHARD`** with `java.nio.file.NoSuchFileException` — the shard couldn't dump its output file. Fast failure (~1–2 min) ⇒ a launch/output-path issue, not compute. The AI diagnosis flags it transient ("Resume from last step"). This is an **infra/workflow** issue to investigate separately (possibly the same docking/ADMET shard output-path class seen earlier), **not a UI defect**. A retry (or a different clean workflow) is needed to reach the **completed** state and exercise Outputs/Findings/Report + the re-run card fix.
2. **The failure UI is correct** — FAILED badge, Restart (not "Run again"), full untruncated error, AI diagnosis, and no stuck "Analysis in progress…" — matching the Chat+Panel Presentation Standard and my deployed changes.
3. **Pre-run and running states are fully correct** — accurate name/params (hERG,DILI extracted), live SSE step transitions, QC gates shown.

## Execution order (next)

1. Reach a **completed** run (retry ADMET, or run a known-good workflow e.g. RNA-seq/differentialabundance from an existing fixture run) → verify E14/E15 Outputs+Findings+Report and the **completed** state.
2. **UC-R** re-run card fix on that completed run.
3. **UC-SSE** navigate-away-and-return during a run.
4. Breadth: A2–A11, B2–B6, C3–C10, G2–G7.
5. Console sweep (H1) + responsive pass (H3).
</content>
