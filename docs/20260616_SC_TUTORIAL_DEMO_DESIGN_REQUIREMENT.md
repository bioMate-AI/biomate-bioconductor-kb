# Single-Cell Tutorial Demos — Detailed Requirement for Claude Design

**Date:** 2026-06-16
**For:** Claude design / engineering handoff
**Builds on:**
- `reference/claude_design/design_handoff_tier0_design_pipelines/Tier-0 Demo Requirement.md` (the 8-beat / 9-screenshot pattern this doc inherits unchanged)
- `reference/claude_design/tutorials-work/Demo Narratives.md` (cryo-EM tutorial template — VO + timestamps + scene annotations)
- `reference/claude_design/tutorials-work/Bioconductor Tutorial Scenarios.md` (scenario design pattern — plan checklist + tape events + findings card)
- `docs/20260616_SC_WORKFLOW_IMPLEMENTATION_REQUIREMENT_3_WORKFLOWS.md` (the engineering contract for the three workflows these demos run; **the demos cannot be faked from design only** — the workflows must execute on AWS Batch with `real_exec_status='ok'` before recording starts)
- `frontend/e2e/demo-T01-bispecific-format.demo.ts` (canonical Playwright `.demo.ts` shape)

---

## Goal

Three **3-minute tutorial demos**, one per single-cell workflow added in Doc A, that teach a new user how BioMate routes a scRNA-seq design request into an executable workflow chain and reads the result. Like Tier-0, these are instructional — every beat answers "where am I, what should I look at, what did the system just do for me." The output of this requirement is:

- 3 voice-over scripts with timestamps (≤3:00 strict, no exceptions)
- 3 `.demo.ts` Playwright recorder scripts under `frontend/e2e/`
- 3 sets of post-edited MP4 + WebM at 1920×1080 30fps
- 3 reusable still-frames per demo (intro card + outcome card)
- 1 chapter playlist page connecting the 3 demos (the *thematic arc* — see §6)

The 3 demos must share the Tier-0 visual grammar (8-beat structure, tip-card style, screenshot ladder, mandatory affordances). They additionally introduce one new affordance: **chained-workflow visualisation** — see §5.

---

## Shared visual grammar (inherited from Tier-0)

### 1. The 8-beat structure

Identical to Tier-0. Reproduced here for completeness; any deviation requires explicit approval.

| # | Beat | Target | On-screen | VO purpose |
|---|---|---|---|---|
| 1 | Cold open — what BioMate will do | 0:00–0:14 | Empty chat, BioMate logo | Tease problem + 1-sentence outcome |
| 2 | User types the design query | 0:14–0:30 | Chat input fills letter-by-letter, then sends | Show exact phrasing — input contract |
| 3 | AI routes the intent | 0:30–0:55 | SSE delta events render; intent kicker visible | "BioMate reads target + modality → picks the right pipeline" |
| 4 | Workflow panel opens with prefilled params | 0:55–1:18 | Panel right rail; PARAMETERS line visible; first phase expanded | Point at canonical-keyed params + provenance hint badges |
| 5 | Click Confirm & Run | 1:18–1:28 | Submit + dispatch confirmation | Sets up live execution |
| 6 | Live phase-by-phase narration | 1:28–2:35 | Phase cards flip pending → running → completed | 4–5 tips total |
| 7 | Outputs + findings card | 2:35–2:50 | File chips inline; AI findings card materializes | Show how user reads result |
| 8 | Closing 1-liner + outcome card | 2:50–3:00 | Status badge "Completed"; outcome graphic | Tie back to cold-open promise |

### 2. Tip-card design (unchanged from Tier-0)

- 480×120px translucent card, 16px round corners, BioMate brand-bg-2
- Two-line max, 18pt Inter Medium
- Renders 3.5–5s per tip; fade-in/out 200ms
- VO actor reads tip text verbatim — no improvisation

### 3. Screenshot ladder (unchanged from Tier-0)

| Slug | When captured | Use in marketing |
|---|---|---|
| `00_start` | Beat 1 start | Chapter cover |
| `01_intro_tip` | Beat 1 tip mid-render | Cold-open frame |
| `02_query_sent` | Beat 2 end | "User just typed" frame |
| `03_workflow_ready` | Beat 3 end | "AI just routed" frame |
| `04_panel_review` | Beat 4 mid (tip on params) | **Hero shot** for case-study pages |
| `05_submitted` | Beat 5 end | "Run dispatched" frame |
| `06_phase_running` | Beat 6 mid (peak liveness) | Animated GIF source |
| `07_outputs` | Beat 7 mid (findings just rendered) | Outcome screenshot |
| `08_closing` | Beat 8 end | Chapter outro |

### 4. Mandatory UI affordances (per demo)

Every demo must demonstrate, even if only on-screen for 2s:

- **Intent kicker** above assistant reply
- **PARAMETERS (N CONFIGURED)** summary line
- **Per-param "from your message" hint badges**
- **`data-status` attribute flips** on phase + overall badge
- **Findings card** at the end

### 5. NEW affordance: chained-workflow sub-phase rendering

This series introduces workflow chaining (Spec 1 → iSEE; Spec 3 → CCPlotR → InterCellar). The chained workflow MUST render as a **sub-phase of the parent workflow's "Output & Reporting" card**, not as a new top-level workflow row. Reasons:

- The user's mental model is one task: "run scRNA-seq end-to-end." A new top-level row breaks that.
- Each chained call adds at most ~30s of compute; promoting them to top-level wastes 8-beat budget.
- The demo loses momentum mid-recording if the user has to click "next workflow."

UI contract for the chained call:
- Parent phase card shows a `child-runs` sub-section with one badge per chained call
- Each child badge shows: name + `data-status` + link to its output artifact
- Click-through to the chained workflow's full panel is available but not required for the tutorial

**Frontend gate (P0 blocker — see Doc A item #16):** if chained-call rendering is not implemented as sub-phases at recording start, demos D01 and D03 cannot record cleanly. Mitigation: record once the UX lands; do not back-fill the recording around a missing affordance.

### 6. Cross-demo continuity — the thematic arc

The three demos share a single dataset family (Jerby-Arnon GSE115978 melanoma) and tell one connected story:

> *D01:* Annotate the tumour microenvironment (TME).
> *D02:* Trace the T-cell exhaustion trajectory we discovered.
> *D03:* Reveal the immune-checkpoint signalling axis driving exhaustion.

This is encoded in:
- Identical opening + closing music stings (inherited from Tier-0)
- D02 opens from a saved D01 output in the user's workspace (a continuation visible on screen)
- D03 opens from a saved D02 output similarly
- The chapter playlist page (the deliverable in §0 "Goal") presents them as a single playthrough with chapter markers

---

## Demo D01 — Standard scRNA-seq end-to-end (annotate the melanoma TME)

### Workflow ID under test
`scrnaseq_standard_endtoend` (id 14435, Doc A Spec 1)

### Audience hook (Beat-1 tip)

> "Jerby-Arnon 2018 — 7,000 cells from 33 melanoma patients. Watch BioMate take raw 10X FASTQs and emit a fully annotated TME in 70 minutes."

### Query

```
Run standard scRNA-seq on the Jerby-Arnon melanoma dataset and annotate cell types.
```

### Expected routing

- Workflow: `scrnaseq_standard_endtoend` (id 14435)
- Canonical params:
  - `species: human`
  - `aligner: starsolo`
  - `harmony_batch_key: patient` (auto-detected from samplesheet)
  - `celltypist_model: Immune_All_High` (TME-tuned default)
  - `leiden_resolution: 0.5`

### Plan checklist

1. Validate samplesheet + locate FASTQ pairs (~5s)
2. Sub-workflow call: `nf-core/scrnaseq` (12777) alignment (~40 min)
3. Per-cell QC + scDblFinder doublet filter (~3 min)
4. Normalize + HVGs + PCA + Harmony batch correction (~5 min)
5. Leiden clustering + UMAP (~2 min)
6. celltypist annotation + marker genes (~3 min)
7. Chained: iSEE app (id 11653) + Methods Report (~30s)

### Beat 3 — special routing callout

Tip-card text:

> "Notice the intent kicker: 'standard scRNA-seq pipeline.' BioMate disambiguated standard 10X analysis from spatial / multiome / nuclei variants based on the dataset metadata."

### Beat 4 — special prefill callout

Tip-card text:

> "`harmony_batch_key=patient` was auto-detected from the samplesheet's `patient` column — provenance badge shows where each param came from."

### Beat 6 phase narration

| Sub-beat | Timing | Tip |
|---|---|---|
| 6a | 1:28–1:50 | "Phase A — Alignment. STARsolo via the nf-core/scrnaseq sub-workflow. ~95% reads mapped, ~70% reads in cells. Both gates passing." |
| 6b | 1:50–2:10 | "Phase B — QC + doublet removal. Violins show n_genes, n_counts, percent mito. scDblFinder flags ~6% doublets — within expected range for 10X." |
| 6c | 2:10–2:25 | "Phase C — Harmony integration by patient. Before-and-after UMAPs show patient batch effect collapsed; biological structure preserved. Silhouette = 0.14." |
| 6d | 2:25–2:35 | "Phase D — celltypist annotation. UMAP re-colors by cell type: tumour cells, Treg, exhausted-CD8 (LAG3+), macrophage, endothelial, CAF. Mean confidence 0.78." |

### Beat 7 outputs

- `annotated.h5ad`
- `celltype_assignments.csv`
- `marker_genes_per_cluster.csv`
- `qc_metrics.csv`
- `methods_report.html`
- **Chained from iSEE (11653):** `isee_app.tar.gz` — visible as sub-phase badge under the Output & Reporting card

### Beat 8 closing

> "An entire melanoma TME — annotated and explorable — from a single sentence."

### Outcome card

- UMAP of annotated cell types with patient-batch overlay
- Subtitle: *"7K cells. 6 cell types. PD-1 axis cells highlighted in red."*

---

## Demo D02 — Trajectory analysis (trace T-cell exhaustion)

### Workflow ID under test
`scrnaseq_trajectory_pseudotime` (id 14436, Doc A Spec 2)

### Continuity note for VO actor
This demo opens with a clearly-visible "Continue from D01 output" affordance — the user's workspace shows the D01 `annotated.h5ad` from the previous demo. The recording starts with that visual context.

### Audience hook (Beat-1 tip)

> "PD-1 blockade works because exhausted CD8 T-cells regain function. Watch BioMate trace the exhaustion path — and rank PDCD1, TIGIT, TOX, LAG3 as the molecular drivers."

### Query

```
Find the T-cell exhaustion trajectory starting from naive CD8.
```

### Expected routing

- Workflow: `scrnaseq_trajectory_pseudotime` (id 14436)
- Input source: D01's `annotated.h5ad` (auto-resolved from workspace)
- Canonical params:
  - `start_celltype: Naive-CD8` (extracted from query)
  - `embedding: X_umap`
  - `n_top_hvgs_for_trajectory: 2000`
  - `bpparam_workers: 4`
  - `lineage_split_threshold: 20000`

### Plan checklist

1. Load + validate input h5ad (~2s)
2. HVG subset + build SCE (~10s)
3. Slingshot lineage fit (~3 min)
4. tradeSeq GAM fit (~12 min)
5. Association + startVsEnd + earlyDE genes (~3 min)
6. Methods report (~30s)

### Beat 4 — special prefill callout

Tip-card text:

> "Input pre-resolved from D01's `annotated.h5ad`. BioMate detected the chain — provenance badge says 'from previous run'."

### Beat 6 — special live auto-loop callout

This demo MUST demonstrate auto-loop. Inject a forced 25,000-cell input via `--demo_force_large` flag so the `peak_mem_gb` gate fires.

| Sub-beat | Timing | Tip |
|---|---|---|
| 6a | 1:28–1:48 | "Phase A — HVG subset + SCE build. 2,000 highly variable genes selected. Memory budget: 56 GB." |
| 6b | 1:48–2:08 | "Phase B — Slingshot fits two lineages: one to exhausted-CD8, one to effector-memory. Pseudotime UMAP renders on the right." |
| 6c | 2:08–2:25 | "Auto-loop fires: tradeSeq peak memory projected at 62 GB > 56 GB ceiling. BioMate suggests lineage-split + drop HVGs 2000 → 1000. Accept." |
| 6d | 2:25–2:35 | "Phase C — GAM fits per-lineage. Association-gene table emits 327 genes at FDR 0.05. TOX, PDCD1, TIGIT, LAG3, ENTPD1, HAVCR2 in top 30 early-DE — the canonical exhaustion signature." |

### Beat 7 outputs

- `pseudotime_per_cell.csv`
- `association_genes.csv` (TOX, PDCD1, TIGIT, LAG3 etc. ranked)
- `startvsend_genes.csv`
- `earlyDE_genes.csv`
- `umap_slingshot.png`
- `methods_report.html` (cites Slingshot Street 2018 + tradeSeq Van den Berge 2020)

### Beat 8 closing

> "The PD-1 axis recovered — not by us specifying it, but by BioMate finding it as the dominant trajectory signal."

### Outcome card

- Pseudotime-coloured UMAP with the two lineages annotated
- Subtitle: *"PDCD1, TIGIT, TOX, LAG3 — the exhaustion drivers, top-ranked by FDR."*

---

## Demo D03 — Cell-cell communication (reveal the checkpoint signalling axis)

### Workflow ID under test
`scrnaseq_cellcell_communication` (id 14437, Doc A Spec 3)

### Continuity note for VO actor
Opens from D02 workspace; user has both D01's `annotated.h5ad` and D02's trajectory results available.

### Audience hook (Beat-1 tip)

> "Now the why. Exhausted T-cells get there because tumour cells signal them PD-L1, TIGIT-ligand, LAG3-ligand. BioMate ranks every immune-checkpoint pair — stratified by treatment response."

### Query

```
Show me the immune-checkpoint signalling between tumour and T-cells in this melanoma dataset, comparing treatment-naive vs treatment-resistant.
```

### Expected routing

- Workflow: `scrnaseq_cellcell_communication` (id 14437)
- Input source: D01's `annotated.h5ad`
- Canonical params:
  - `celltype_key: celltype`
  - `condition_key: lesion_type` (auto-detected from `adata.obs`)
  - `methods: ["consensus"]`
  - `resource_name: consensus`
  - `run_decoupler_followup: true`
  - `assume_raw_counts: true`

### Plan checklist

1. Validate celltype col + min cells + raw counts (~5s) — **auto-loop fires here in demo**
2. Load LR resource from bundled OmniPath cache (~3s)
3. Run LIANA+ scoring (~6 min)
4. Aggregate + rank pairs across methods (~30s)
5. Condition-stratified comparison naive vs resistant (~2 min)
6. decoupler TF-activity follow-up (~3 min)
7. Chained: CCPlotR (11052) viz + InterCellar (11646) Shiny (~45s)

### Beat 3 — special routing callout

Tip-card text:

> "Three intents detected: 'signalling between celltypes,' 'tumour vs T-cells,' 'comparing conditions.' BioMate routes to cell-cell communication with `condition_key=lesion_type` auto-set."

### Beat 4 — special raw-counts callout (live auto-loop)

The demo MUST demonstrate the `mean_X_modulus_check` halt. To force it, pre-stage the workspace to point at the log-normalized layer first.

Tip-card text:

> "Auto-loop fires immediately: LIANA+ needs raw counts. BioMate detects log-normalized input. Remediation switches to `adata.layers['counts']`. Accept."

### Beat 6 phase narration

| Sub-beat | Timing | Tip |
|---|---|---|
| 6a | 1:28–1:50 | "Phase A — LIANA+ scoring. Six methods voted: consensus + NATMI + CellPhoneDB + SCA + Connectome + logFC. Top hits emerging." |
| 6b | 1:50–2:10 | "Phase B — Aggregation. PDCD1-PDCDLG1, TIGIT-PVR, HLA-C-LAG3 in top 10 across all methods. Direct Merck IO portfolio targets." |
| 6c | 2:10–2:25 | "Phase C — Condition-stratified. TIGIT-PVR upregulated in resistant lesions. PDCD1-PDL1 retained across naive + resistant — consistent with the post-PD-1-blockade resistance signature." |
| 6d | 2:25–2:35 | "Phase D — decoupler TF activity. NF-κB and STAT1 elevated in tumour-receiving cells. IFN-γ response signature confirmed." |

### Beat 7 outputs

- `liana_results.csv` (full source-target-LR with method scores)
- `top_lr_pairs.csv` (consensus rank)
- `condition_diff_lr.csv` (naive vs resistant)
- `tf_activity_per_target.csv`
- `methods_report.html` (LIANA Dimitrov 2022 + OmniPath Türei 2021 citations)
- **Chained from CCPlotR (11052)** as sub-phase: `cc_heatmap.png`, `cc_dotplot.png`, `cc_network.png`
- **Chained from InterCellar (11646)** as sub-phase: `intercellar_shiny_app.tar.gz`

### Beat 8 closing

> "Tumour-to-T-cell PD-L1, TIGIT, LAG3 — the entire IO axis ranked, stratified by resistance, in one sentence."

### Outcome card

- Chord diagram of immune-checkpoint axis (from CCPlotR cc_network) with PDCD1-PDL1 and TIGIT-PVR highlighted
- Subtitle: *"The IO axis Merck Keytruda + ipilimumab + new TIGIT trials are built on — recovered de novo."*

---

## Recording infrastructure requirements

### 1. Server setup

- Local dev server on `:5001` with `SCHEMA_GROUNDED_EXTRACTION=1`, `CORS_ORIGINS=http://localhost:5001`, `E2E_TEST_TOKEN=<from env>`
- Galaxy backend on `:8081` healthy
- Fixture user `lifeifei163361@163.com` pre-provisioned and logged in via cookie before recording starts
- **Workspace pre-staged with the three Jerby-Arnon dataset variants:**
  - `D01_input/`: raw FASTQ + samplesheet (real data, ~12 GB)
  - `D02_input/`: D01's `annotated.h5ad` from a previous successful run
  - `D03_input/`: D02's workspace + a log-normalized fixture (to force the auto-loop in Beat 4)

### 2. Per-demo Playwright shape

One file per demo at `frontend/e2e/demo-D0N-<slug>.demo.ts`. Each conforms to the Tier-0 shape (reproduced in `reference/claude_design/design_handoff_tier0_design_pipelines/Tier-0 Demo Requirement.md` §"Recording infrastructure requirements" §2). Additional requirement: each demo MUST call `expectChainedCallVisible(page, {parent: 'Output & Reporting', children: [<expected children>]})` once during Beat 7 to verify the new chained-call affordance rendered.

### 3. Helper additions to `frontend/e2e/demo-helpers.ts`

Existing helpers (`tip`, `pause`, `shot`, `sendAndWait`, `clickRunOnly`, `waitForCompletion`, `expectParamsLineVisible`, `handleIntentClarification`) are reused unchanged. New helpers:

- `expectChainedCallVisible(page, {parent, children: string[]})` — asserts the parent phase's `child-runs` sub-section contains a badge per child name with `data-status` in `{running, completed}`
- `forceAutoLoop(page, gate: string)` — for D02 + D03 demo paths; sets a `data-demo-force=<gate>` attribute that the test build of the QC monitor reads to fire the gate deterministically
- `expectContinuityBanner(page, fromDemo: 'D01' | 'D02')` — for D02 + D03; asserts the "continue from previous output" affordance is visible at recording start

### 4. Recording cadence

Each demo records live at full duration. Spec 1 (D01) is ~70 min wall-clock end-to-end — the recording captures real Beat-1 through Beat-5 live, then **timelapse-compresses Beat 6 to 60s** (jump-cuts between phase-card transitions every ~10s wall-clock + 8s tip rendering). Beats 7, 8 record live.

D02 + D03 are short enough (~25 min) to record straight-through without timelapse.

Post-edit trims dead air to the strict 3:00 budget. Tip cards anchor the cuts — every cut happens between tips, never during.

### 5. Acceptance checklist (per demo)

| Check | Pass criterion |
|---|---|
| All 9 screenshots captured | files exist with non-zero size |
| Video duration | 175–200 seconds |
| Audio level | -20 LUFS ±2 |
| Tip cards visible | exactly 8–10 cards rendered |
| PARAMETERS summary visible | `04_panel_review.png` shows the line with all expected canonical keys |
| Intent kicker visible | `03_workflow_ready.png` shows intent kicker text |
| Hint badges visible | `04_panel_review.png` shows at least one "from your message" badge |
| `data-status` transition captured | `06_phase_running.png` shows at least one phase with `data-status="running"` |
| Findings card present | `07_outputs.png` shows non-empty findings card |
| Chained sub-phase visible (D01, D03) | `07_outputs.png` shows the Output & Reporting card with at least one `child-runs` badge |
| Auto-loop remediation visible (D02, D03) | a screenshot between 04 and 06 shows the remediation card |
| Continuity banner visible (D02, D03) | `00_start.png` or `01_intro_tip.png` shows "continue from D01 / D02" affordance |
| Closing outcome card | `08_closing.png` shows outcome graphic + "Completed" badge |

If ANY check fails, re-record (don't ship partial demos).

### 6. Post-production handoff

- Source MP4 (1920×1080, 30fps, H.264, 8 Mbps) and WebM (VP9, 6 Mbps) → `reference/claude_design/tutorials-work/sc_tier0/<demo>/`
- Edited 3-min MP4 → same folder, suffix `_final.mp4`
- Hero shot `04_panel_review.png` → `.../sc_tier0/<demo>/hero.png`
- **Chapter playlist HTML page** generated from the 3 demos for the marketing site — must include a banner "Watch end-to-end: D01 → D02 → D03 (9 min total)"

---

## Out of scope (intentionally)

- Multi-language dubs (English only for v1)
- Mobile-format vertical 9:16 cuts
- Animated branded intro/outro stings (use Tier-0's intro card unchanged)
- Showing failure / error states for workflows themselves (auto-loop remediation IS shown; "what if the whole workflow crashed" is a separate tutorial series)
- Spatial transcriptomics, multiome, or in-vivo perturbation variants (separate future demos)
- Recording until workflows reach `real_exec_status='ok'` on the Doc A acceptance datasets — **the demos cannot be faked from design alone**

---

## Open questions for the design lead

1. **Continuity banner UX** — does the existing "continue from previous run" affordance support a *different demo's* output as the source, or does it need a small extension to recognise the saved D01 output as available to D02? Likely needs the latter; engineering input required.
2. **Chained-call sub-phase rendering** — Doc A item #16 flags this as the P0 frontend blocker. If not implemented by recording start, D01 and D03 cannot be recorded cleanly. Recommend frontend confirms a delivery date this sprint.
3. **D01 timelapse compression** — record Beat 6 live and post-edit, or record at 4× wall-clock with hold-still pauses at each phase transition for clean tip-card overlays? Recommend live + post-edit; tip cards are the anchor.
4. **Auto-loop forcing** — `forceAutoLoop()` helper accesses a test-only mechanism in QC monitor. Confirm with engineering that this is acceptable for demo recording (not in production).
5. **Voice talent** — same voice as the Tier-0 + cryo-EM tutorials for cross-series continuity. Recommend same.

---

## Sign-off

This requirement is the contract for the recording session. Any change to the 8-beat structure, the screenshot ladder, the tip-card style, or the chained-call sub-phase affordance requires explicit approval — otherwise the post-edited videos won't compose as a consistent series with Tier-0.

Approval needed from:
- **Product** (final query phrasing per demo)
- **Design** (tip-card style + outcome-card mocks + chapter playlist banner)
- **Engineering** (test-only flags, helper additions, chained-call sub-phase UX, Jerby-Arnon dataset staging)
- **Marketing** (chapter titles + playlist page layout)

**Pre-recording acceptance gate:** all three workflows (14435, 14436, 14437) must reach `real_exec_status='ok'` on their Doc A acceptance tests; frontend chained-call sub-phase rendering must be live; Doc A item #16 frontend confirmation in place.
