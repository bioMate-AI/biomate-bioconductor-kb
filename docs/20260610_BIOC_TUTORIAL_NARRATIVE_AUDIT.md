# Bioconductor tutorial narrative audit — 2026-06-10

Pre-recording review of the three Bioconductor demos in
`reference/claude_design/bioconductor-handoff/src/BiocTours.jsx`,
checking each tutorial against three criteria:

1. **Clear logic** — does the arc read coherently end to end?
2. **High-quality content** — every number / package / claim defensible?
3. **Good timing** — does the per-step copy fit the 5-6 second dwell that
   `TIP_STEP_PAUSE` allots? (`5_500ms` default, 6_000ms for steps 0/3/5/9.)

Source of truth: the JSX step copy in `BiocTours.jsx`, cross-referenced
with `HANDOFF_BIOCONDUCTOR.md` §2.

---

## Architecture recap

| Tour ID | Label (shown in TourPicker) | Steps | Backbone object |
|---|---|---|---|
| `bioc-kb-routing` | BIO — Bioconductor · KB routing & execution | **21** (10 own + 10 after-run + 1 wrap) | `DESeqDataSet` |
| `bioc-sc-routing` | BIO2 — Bioconductor · scRNA-seq → pseudobulk DE | **19** (8 own + 10 after-run + 1 wrap) | `SingleCellExperiment` |
| `bioc-methyl-routing` | BIO3 — Bioconductor · 450k methylation → DMRs | **19** (8 own + 10 after-run + 1 wrap) | `GenomicRatioSet` |

Expected run time at 5.5-6 s/step: **~2-2.5 min per tutorial**.

The 10 shared after-run steps come from `afterRunSteps(done, sw)` in
`BiocTours.jsx` lines 30-90: completion card → 7 tabs (Findings, Outputs,
preview detour, Methods, Parameters, Software, Citations, QC audit).

---

## Tutorial 1 — `bioc-kb-routing` (DESeq2 chain)

**Arc:** match → route → run 6 phases → 7-tab report. The "match" beat is
the centerpiece — a disambig card with two close KB scores.

### Step-by-step quality matrix

| # | Title | Logic | Content | Timing |
|---|---|---|---|---|
| 1 | Bioconductor · DESeq2 chain | ✅ scene-set, no jargon |  ✅ "~3 min · match→route→run→report" | OK fit |
| 2 | Understanding the request | ✅ explains empty panel | ✅ "embeds your request against the Bioconductor knowledge base" | OK fit |
| 3 | Ranked KB match | ⚠ asks viewer to read scores 0.71/0.66; 5.5s tight | ✅ scientific defense ("count-matrix DESeq2 path vs FASTQ pipeline") | **TIGHT** — extend to 7s |
| 4 | Selected · panel populates | ✅ explains *why now* the phase list appears | ✅ "only now does a pipeline exist" | OK fit |
| 5 | Routed by data format, not habit | ✅ the central teaching beat | ✅ "negative-binomial for count matrix vs limma/voom for log₂ intensities" | OK fit |
| 6 | Phase A · QC filtering | ✅ shows what happens inside a phase | ✅ `edgeR::filterByExpr` 10-count cutoff | OK fit |
| 7 | Object handoff (DESeqDataSet) | ✅ types-as-contract framing | ✅ "DESeqDataSet → DESeqResults → shrunk LFCs" | OK fit |
| 8 | Phase C · DE testing | ✅ delivers the headline number | ✅ "2,841 genes at FDR < 0.05" | OK fit |
| 9 | Shrinkage (apeglm) | ✅ explains *why* not just *what* | ✅ "shrinks low-count fold-changes toward zero" | OK fit |
| 10 | Phase E · enrichment | ✅ where the GO term lives | ✅ "top GO term: regulation of apoptotic process" | OK fit |
| 11 | Complete · 2,841 DE genes | ✅ closure | ✅ matches headline | OK |
| 12 | After run · structured report | ✅ tab overview | ✅ "7 tabs cover findings → artifacts → reproducibility → audit" | OK |
| 13 | Findings tab | ✅ headline + bullets + figures | ✅ "no numbers invented" contract | OK |
| 14 | Outputs tab | ✅ per-file row, view/download | ✅ "BioMate picks the right viewer" | OK |
| 15 | Preview detour (volcano) | ⚠ requires user to spot the inline viewer mid-tour | ✅ "log₂FC vs −log₁₀ p, up red / down blue" | OK |
| 16 | Methods tab | ✅ paste-ready prose | ✅ "manuscript-ready" | OK |
| 17 | Parameters tab | ✅ supplementary-table framing | ✅ "ready supplementary table" | OK |
| 18 | Software tab | ✅ reproducibility baseline | ✅ "DESeq2, apeglm, edgeR, clusterProfiler, EnhancedVolcano" | OK |
| 19 | Citations tab | ✅ auto-references | ✅ "Love 2014 (DESeq2), Zhu 2019 (apeglm), Wu 2021 (clusterProfiler)" | OK |
| 20 | QC audit | ✅ compliance lens framing | ⚠ "21 CFR Part 11 friendly" — strong claim; needs the doc backup | OK |
| 21 | Wrap-up | ✅ ties to other tutorials | ✅ "match → route → run → 7-tab report" | OK |

**Defects spotted:**

- **D1.** Step 3 (disambig) crams "two scores · pre-selected with countdown ·
  scores 0.71/0.66" into 5.5s. The viewer needs to read both scores. Bump
  `TIP_STEP_PAUSE[2]` to 7000-7500ms for tour-2 (KB tour) OR shorten the body
  to drop the parenthetical scores (they're already visible on the card).
- **D2.** Step 20 ("21 CFR Part 11 friendly") is a regulatory claim. We
  should either back it up in the QC tab body (chain-of-custody, e-signature)
  OR soften to "audit-friendly". Recommend: **keep** the strong claim since
  the v2 QcAuditTab now actually renders chain-of-custody + e-signature
  (commit 8050e6c3d).
- **No factual errors found** — every package, version-pinnable tool, and
  numeric claim cross-checks against `HANDOFF_BIOCONDUCTOR.md` §2.1.

---

## Tutorial 2 — `bioc-sc-routing` (scRNA-seq → pseudobulk)

**Arc:** route → cluster → annotate (parallel) → pseudobulk DE → report.
Centerpiece is the **pseudoreplication warning** (step 8) — two-block
problem-fix structure.

### Step-by-step quality matrix

| # | Title | Logic | Content | Timing |
|---|---|---|---|---|
| 1 | Bioconductor · scRNA-seq chain | ✅ scene-set | ✅ "routes to OSCA, clusters and annotates in parallel" | OK |
| 2 | Seven phases · a parallel branch | ⚠ jargon "markers ∥ annotation" without lead-in | ✅ technically correct | **TIGHT** — viewers might miss "∥" symbol; extend to 6.5s or change to "in parallel" |
| 3 | Routed to the OSCA stack | ✅ explains why SCE over Seurat | ✅ "SingleCellExperiment + scran/scater so the pseudobulk hands off with no lossy conversion" | OK |
| 4 | Phase A · cell QC | ✅ delivers headline retention | ✅ "9,814 of 12,402 cells retained" | OK |
| 5 | One SingleCellExperiment throughout | ✅ types-as-contract beat | ✅ "counts, logcounts, metadata, size factors" | OK |
| 6 | Phases B–D done · 11 clusters | ✅ shows fast-forward | ✅ "buildSNNGraph + Louvain · 11 clusters · UMAP for visualisation only" | OK |
| 7 | Parallel branch · markers ∥ annotation | ✅ explains the fan-out | ✅ "scoreMarkers and SingleR both read the clustered object" | OK |
| 8 | **Pseudobulk, not naive per-cell DE** | ✅ centerpiece — two-block trap+fix | ✅ "pseudoreplication" labeled clearly | **TIGHT** — most content-dense step; bump to 7.5s |
| 9 | Complete · 8 cell types | ✅ closure with the headline | ✅ "CD8⁺ T strongest responder · 214 DE genes on true replicates" | OK |
| 10-19 | After-run tabs (10 steps) | ✅ shared with KB | ✅ adjusted body per scRNA specifics | OK |
| 20 | Wrap-up | ✅ ties back to other two | ✅ "one object, one request, statistically honest DE" | OK |

**Defects spotted:**

- **D3.** Step 2 uses the math symbol `∥` (parallel-to). Viewers reading the
  callout will trip on it. Recommend: spell out "in parallel" or use
  `markers + annotation`. The symbol can stay in the phase-card label
  where it's a visual icon.
- **D4.** Step 8 (pseudobulk) is the most content-dense in the entire
  series (two blocks: trap statement + fix mechanism). 5.5s is tight.
  Recommend extending dwell to 7-8s OR splitting into two callouts
  ("the trap" + "the fix").
- **No factual errors found.**

---

## Tutorial 3 — `bioc-methyl-routing` (450k methylation → DMRs)

**Arc:** IDAT → GenomicRatioSet → DMPs → DMRs → CpG-corrected GO → report.
Centerpiece is the **CpG-density bias correction** (step 8).

### Step-by-step quality matrix

| # | Title | Logic | Content | Timing |
|---|---|---|---|---|
| 1 | Bioconductor · 450k methylation chain | ✅ scene-set, contrasts the others | ✅ "genomic backbone instead of count matrix · probe coords travel with the data" | OK |
| 2 | Five phases mirrored in the panel | ✅ phase overview | ✅ "IDAT → QC/normalise → DMP → DMR → CpG-corrected enrichment" | OK |
| 3 | Routed to minfi | ✅ explains *why* minfi | ✅ "raw IDAT + 450k manifest needs a genomic object, not a plain matrix" | OK |
| 4 | Phase A · read IDAT | ✅ shows step output | ✅ "MethylSet — raw methylated + unmethylated, 450k probes × 24 samples" | OK |
| 5 | GenomicRatioSet · coordinates attached | ✅ object-lineage explanation | ✅ "MethylSet → GenomicRatioSet → data.frame → GRanges, each typed" | OK |
| 6 | Phase C · DMP calling | ✅ shows headline | ✅ "limma eBayes on M-values · 12,403 significant CpGs · M-values for testing, β for reporting" | OK |
| 7 | Phase D done · 847 DMRs | ✅ closure of region-level | ✅ "bumphunter 1,000 bootstraps · 847 regions as GRanges" | OK |
| 8 | **CpG-density bias correction** | ✅ centerpiece — two-block trap+fix | ✅ "missMethyl::gometh weights genes by CpG count" | **TIGHT** — same pattern as scRNA; bump to 7.5s |
| 9 | Complete · 847 DMRs | ✅ closure | ✅ matches headline | OK |
| 10-19 | After-run tabs (10 steps) | ✅ shared with KB | ✅ adjusted body per methyl specifics | OK |
| 20 | Wrap-up | ✅ ties all three together | ✅ "GRanges backbone → DMPs → DMRs → CpG-corrected enrichment" | OK |

**Defects spotted:**

- **D5.** Step 8 (CpG bias) is the centerpiece, same density issue as D4.
  Recommend same fix: extend dwell to 7.5s.
- **No factual errors found.** The 12,403 CpGs → 847 DMRs ratio is
  scientifically plausible; the "M-values for testing, β-values for
  reporting" line is correct minfi/limma practice.

---

## Cross-cutting observations

### Consistency wins (the three tours read coherently together)

| Beat | KB | scRNA | Methyl |
|---|---|---|---|
| Intro (~3 min · A → B → C → report) | ✅ | ✅ | ✅ |
| "Same agent, different X" wrap-up | ✅ | ✅ | ✅ |
| Object-handoff teaching beat | DESeqDataSet | SingleCellExperiment | GenomicRatioSet |
| Stats / domain trap beat | (n/a — no trap) | Pseudoreplication | CpG-density bias |
| After-run walk | shared 10 steps | shared 10 steps | shared 10 steps |
| Wrap-up CTA | "Try the others next" | "Compare with bulk + methyl" | "Completes the three" |

### Suggested global timing change (one place)

Apply per-tour overrides on top of `TIP_STEP_PAUSE` for the dense steps:

```ts
// In each demo file, before runTourDemo:
const KB_STEP_PAUSE  = { ...DEFAULTS, 2: 7500 };          // disambig
const SC_STEP_PAUSE  = { ...DEFAULTS, 1: 6500, 7: 8000 }; // parallel jargon + pseudobulk centerpiece
const MET_STEP_PAUSE = { ...DEFAULTS, 7: 8000 };          // CpG bias centerpiece
```

(`TIP_STEP_PAUSE` is currently a single shared `Record<number, number>` in
`demo-ref-helpers.ts`. To allow per-demo override, either extend the helper
signature with an optional pause override map, or just pass an explicit
"pauseMap" parameter to `runTourDemo`. The helper change is one parameter
addition — small.)

### Final recommendation before recording

| Action | Priority |
|---|---|
| **D1**: extend disambig step dwell on KB tour to 7.5s | **high** — viewers can't read both scores in 5.5s |
| **D3**: change "markers ∥ annotation" → "markers and annotation (in parallel)" | low — JSX change in BiocTours.jsx |
| **D4**: extend pseudobulk step dwell on SC tour to 8s | **high** — most content-dense step in series |
| **D5**: extend CpG-bias step dwell on Methyl tour to 8s | **high** — same density as D4 |
| **D2 (defensive)**: confirm QC audit panel renders chain-of-custody before recording | done — commit `8050e6c3d` |

Recording can proceed once the three timing overrides are wired in.

---

## Recording plan

1. Start a static HTTP server on a fresh port (8000) for the bioc handoff
   dir — `cd reference/claude_design/bioconductor-handoff && python3 -m http.server 8000`.
2. Add a `BIOC_REF_URL` constant in a new helper module that points to
   `http://localhost:8000/Research%20Agent%20UI.html`.
3. Add an optional `pauseMap` parameter to `runTourDemo()` so per-tutorial
   timing tweaks land cleanly (D1/D4/D5).
4. Write three new demo files following the existing pattern:
   - `demo-bioc-01-kb-routing.demo.ts` (21 steps)
   - `demo-bioc-02-sc-routing.demo.ts` (19 steps)
   - `demo-bioc-03-methyl-routing.demo.ts` (19 steps)
5. Run with `npx playwright test --config frontend/playwright.demo.config.ts`
   to land 1440p webm videos in `frontend/e2e/demo-videos/`.

Total recording time: ~3 × 2.5 min = 7.5 min of video; with the test
overhead (server boot, browser startup, picker open) probably 12-15 min
total wall-clock per pass.
