# Bioconductor Tutorial Scenarios — Research Agent UI Design

**For:** Claude design / engineering handoff  
**Builds on:** `Research Agent UI.html` + `HANDOFF_RESEARCH_AGENT_UI.md`  
**What this adds:** Two new research scenarios (`bioc_rnaseq`, `bioc_scrna`) and their DEMO_TOURS entries. Format follows the existing `rnaseq`, `drugscreen`, `variant` pattern exactly.

---

## Why these two scenarios

The ablation benchmark (see `docs/20260527_KB_ABLATION_BENCHMARK.md`) showed that the single most important demonstration of the Bioconductor KB is **context-sensitive routing**: the same biological goal ("find differentially expressed genes") routes to different packages depending on data type. The existing `rnaseq` scenario uses nf-core as the v1 panel stand-in and doesn't show the routing decision. These two scenarios fill that gap.

| Scenario | ID | v1 panel scenario | Key decision shown |
|---|---|---|---|
| Bulk RNA-seq DE | `bioc_rnaseq` | `nfcore` | limma vs DESeq2 based on data format |
| Single-cell RNA-seq | `bioc_scrna` | `nfcore` | pseudo-bulk path vs cell-level (anti-pattern warning) |

---

## Scenario B1 — Bulk RNA-seq DE (`bioc_rnaseq`)

### Context

A computational biologist asks: *"I have an Affymetrix microarray dataset with 36 samples across 4 groups. Which package should I use to find differentially expressed probes?"* BioMate routes away from DESeq2 (count-only) to limma, explains why, runs the pipeline, and surfaces results with a `(why?)` rationale on the routing decision.

Second beat of the same scenario: the user follows up with a new dataset — raw RNA-seq counts — and the agent re-routes to DESeq2, showing the contrast explicitly.

### Plan checklist items

```js
[
  { id: 'p1', title: 'Parse data format',          status: 'pending', est_s: 5  },
  { id: 'p2', title: 'Select DE package',           status: 'pending', est_s: 8  },
  { id: 'p3', title: 'Run limma (microarray path)', status: 'pending', est_s: 60 },
  { id: 'p4', title: 'Pathway enrichment',          status: 'pending', est_s: 20 },
  { id: 'p5', title: 'Generate report',             status: 'pending', est_s: 10 },
]
```

### Tape events (`RESEARCH_SCENARIOS.bioc_rnaseq.tape`)

```js
tape: [
  // 1. Plan appears
  { kind: 'planShow' },
  { kind: 'chatLine', s: 'plan', m: 'Breaking down your request into 5 steps.' },
  { kind: 'planUpdate', id: 'p1', status: 'running' },

  // 2. Format detection
  { kind: 'chatLine', s: 'agent',
    m: 'Data format: continuous log₂ intensities from an Affymetrix array. This is **not** count data.',
    rationaleId: 'bioc_rnaseq:format_check' },
  { kind: 'planUpdate', id: 'p1', status: 'done' },

  // 3. Routing decision — the key teaching moment
  { kind: 'planUpdate', id: 'p2', status: 'running' },
  { kind: 'chatLine', s: 'wf',
    m: 'Routing to **limma** (empirical Bayes linear model). DESeq2 and edgeR require raw integer counts — they would mismodel continuous log₂ intensities.',
    rationaleId: 'bioc_rnaseq:routing' },
  { kind: 'planUpdate', id: 'p2', status: 'done' },

  // 4. limma run
  { kind: 'planUpdate', id: 'p3', status: 'running' },
  { kind: 'runState', value: 'running' },
  { kind: 'phaseUpdate', id: 'phase-normalise', status: 'running' },
  { kind: 'chatLine', s: 'wf', m: 'Phase 1 · Normalisation (quantile norm via `normalizeBetweenArrays`).' },
  { kind: 'phaseUpdate', id: 'phase-normalise', status: 'completed' },
  { kind: 'phaseUpdate', id: 'phase-model',     status: 'running' },
  { kind: 'chatLine', s: 'wf', m: 'Phase 2 · Model fitting. Design matrix: `~ 0 + group`. Four contrasts.' },
  { kind: 'phaseUpdate', id: 'phase-model',     status: 'completed' },
  { kind: 'phaseUpdate', id: 'phase-eb',        status: 'running' },
  { kind: 'chatLine', s: 'wf', m: 'Phase 3 · Empirical Bayes moderation (`eBayes`). Borrowing variance across probes.' },
  { kind: 'phaseUpdate', id: 'phase-eb',        status: 'completed' },
  { kind: 'planUpdate', id: 'p3', status: 'done' },

  // 5. QC check — nothing trips on microarray path
  { kind: 'chatLine', s: 'qc', m: 'QC · All 36 samples passed array-quality filter. No outliers detected.' },

  // 6. Enrichment
  { kind: 'planUpdate', id: 'p4', status: 'running' },
  { kind: 'phaseUpdate', id: 'phase-enrich',    status: 'running' },
  { kind: 'chatLine', s: 'wf', m: 'Phase 4 · Pathway enrichment via clusterProfiler `enrichKEGG`. Top hit: Metabolic pathways (p.adj = 4.1e-9).' },
  { kind: 'phaseUpdate', id: 'phase-enrich',    status: 'completed' },
  { kind: 'planUpdate', id: 'p4', status: 'done' },

  // 7. Report + findings
  { kind: 'planUpdate', id: 'p5', status: 'running' },
  { kind: 'runState',   value: 'completed' },
  { kind: 'planUpdate', id: 'p5', status: 'done' },
  { kind: 'planLock' },
  { kind: 'showCard', card: 'findings', data: {
      headline: '1,204 differentially expressed probes (FDR < 0.05)',
      bullets: [
        'limma eBayes linear model, 4-group design, empirical Bayes variance moderation',
        'Top pathway: Metabolic pathways (KEGG, 312 genes, p.adj 4.1e-9)',
        'Note: would have been wrong to use DESeq2 on pre-normalised intensities',
      ],
  }},
  { kind: 'chatLine', s: 'find', m: '**1,204 probes significant.** Methods section and R script in the After-run report.' },
  { kind: 'marker', id: 'bioc_rnaseq_done' },
]
```

### `RESEARCH_PHASE_TRACE` entries

```js
'bioc_rnaseq:format_check': {
  rationale: 'DESeq2 and edgeR model raw integer counts using the negative binomial distribution. Affymetrix intensities are continuous log₂ values after background correction and normalisation — the distributional assumptions are violated if count-based tools are applied.',
  citation: 'limma User\'s Guide §7; Law et al. (2016) Genome Biology 17:181',
},
'bioc_rnaseq:routing': {
  rationale: 'limma\'s empirical Bayes linear model handles both microarray (continuous) and RNA-seq (counts, via voom) data. For pre-normalised continuous data, limma is the canonical Bioconductor tool. DESeq2 explicitly rejects non-integer input.',
  citation: 'Ritchie et al. (2015) Nucleic Acids Research 43:e47',
},
```

### v1 panel scenario

Use the existing `nfcore` scenario as the v1 right-panel stand-in (same as the existing `rnaseq` research scenario). The phase names should be renamed in `data.js` `SCENARIOS.nfcore` to `Normalise`, `Model & contrast`, `eBayes`, `Enrichment` for this demo — or create a minimal `bioc_rnaseq` entry in `SCENARIOS`.

### DEMO_TOURS entry

```js
{
  id: 'bioc-rnaseq-routing',
  label: 'Bioconductor · Microarray vs RNA-seq routing',
  group: 'bioconductor',
  scenario: 'bioc_rnaseq',
  cartoon: true,
  steps: [
    {
      target: null,
      placement: 'center',
      title: 'Context changes everything',
      body: <>
        The same question — "find differentially expressed genes" —
        routes to <strong>limma</strong> for microarray, <strong>DESeq2</strong> for
        RNA-seq counts. We'll watch BioMate make and explain that decision.
        <div className="hint">~2 min · fully narrated</div>
      </>,
    },
    {
      target: '[data-tour="plan-checklist"]',
      placement: 'bottom',
      title: 'Plan · 5 steps',
      body: <>BioMate decomposes the request: detect format, pick package, run, enrich, report.</>,
      setup: () => { window.__tourFFTo('bioc_rnaseq_plan_shown'); return null; },
    },
    {
      target: '[data-speaker="agent"]',
      placement: 'right',
      title: 'Format detected',
      body: <>
        Continuous log₂ intensities detected. This is the disqualifier for
        DESeq2 and edgeR — they require raw integer counts.
        <div className="hint">Hover (why?) to see the citation.</div>
      </>,
    },
    {
      target: '[data-speaker="wf"][data-rationale-id="bioc_rnaseq:routing"]',
      placement: 'right',
      title: 'Routed to limma',
      body: <>
        The WF agent explains the routing. The (why?) anchor opens the rationale
        with the Ritchie et al. citation — reviewers can verify the logic.
      </>,
    },
    {
      target: '[data-tour="phase-list"]',
      placement: 'left',
      title: 'Four phases run',
      body: <>Normalise → Model → eBayes → Enrichment. Each phase ticks as it completes.</>,
      setup: () => { window.__tourFFTo('bioc_rnaseq_done'); return null; },
    },
    {
      target: '[data-tour="findings-card"]',
      placement: 'top',
      title: '1,204 probes significant',
      body: <>
        Results inline in chat. The findings card also flags what
        <em>would have been wrong</em> — a pattern borrowed from the SKILL.md
        "When NOT to Use" field.
      </>,
    },
    {
      target: null,
      placement: 'center',
      title: 'Try it with counts next',
      body: <>
        The next demo shows the same flow with a raw count matrix — DESeq2 is
        selected, and the (why?) explains the switch.
      </>,
      cta: 'Done',
    },
  ],
},
```

---

## Scenario B2 — Single-cell RNA-seq (`bioc_scrna`)

### Context

A biologist uploads a 10x Genomics count matrix and asks: *"Find markers for each cell cluster."* BioMate shows the full scRNA-seq chain (scuttle QC → scran normalization → scater dim-reduction → SingleR annotation → pseudo-bulk DE), and surfaces the key anti-pattern warning: **don't run DESeq2 cell-by-cell without aggregating by donor** (inflated Type I error).

### Plan checklist items

```js
[
  { id: 'p1', title: 'QC + doublet removal',       status: 'pending', est_s: 15 },
  { id: 'p2', title: 'Normalise + feature select',  status: 'pending', est_s: 20 },
  { id: 'p3', title: 'Cluster (graph-based)',        status: 'pending', est_s: 30 },
  { id: 'p4', title: 'Cell type annotation',        status: 'pending', est_s: 15,
    parallel: 'p3p4' },
  { id: 'p5', title: 'Pseudo-bulk DE per cell type', status: 'pending', est_s: 40 },
]
```

Note: `p3` and `p4` carry the same `parallel` key — they render with a connector line indicating they run concurrently after QC completes.

### Tape highlights (abbreviated)

```js
tape: [
  { kind: 'planShow' },
  // QC phase
  { kind: 'planUpdate', id: 'p1', status: 'running' },
  { kind: 'chatLine', s: 'wf',  m: 'scuttle · perCellQCMetrics. 15,423 cells in, 13,891 after filtering (MAD-based thresholds on lib size + n_genes + mt%).' },
  { kind: 'chatLine', s: 'wf',  m: 'scDblFinder · Doublet score. 412 doublets removed. 13,479 cells retained.' },
  { kind: 'planUpdate', id: 'p1', status: 'done' },

  // Normalise
  { kind: 'planUpdate', id: 'p2', status: 'running' },
  { kind: 'chatLine', s: 'wf',  m: 'scran · pooledSizeFactors. Deconvolution-based normalisation; log-normalised counts stored as `logcounts` assay.' },
  { kind: 'chatLine', s: 'wf',  m: 'Top 2,000 HVGs selected via scran::modelGeneVar.' },
  { kind: 'planUpdate', id: 'p2', status: 'done' },

  // Cluster + annotate (parallel plan items)
  { kind: 'planUpdate', id: 'p3', status: 'running' },
  { kind: 'planUpdate', id: 'p4', status: 'running' },
  { kind: 'chatLine', s: 'wf',  m: 'scater · runPCA (50 PCs) → runUMAP. Graph-based clustering (k=20 SNN) via bluster::clusterRows → 14 clusters.' },
  { kind: 'chatLine', s: 'wf',  m: 'SingleR · Reference: HumanPrimaryCellAtlasData. Annotating clusters.' },
  { kind: 'planUpdate', id: 'p3', status: 'done' },
  { kind: 'planUpdate', id: 'p4', status: 'done' },

  // Pseudo-bulk DE — QC warning about naive approach
  { kind: 'planUpdate', id: 'p5', status: 'running' },
  { kind: 'chatLine', s: 'qc',
    m: 'Anti-pattern detected: running DESeq2 on individual cells inflates Type I error — each cell is not an independent biological replicate.',
    rationaleId: 'bioc_scrna:pseudobulk_warning' },
  { kind: 'chatLine', s: 'wf',
    m: 'Using pseudo-bulk aggregation: summing counts per donor per cell type → DESeq2 on 8 donor-level observations per cluster.',
    rationaleId: 'bioc_scrna:pseudobulk_choice' },
  { kind: 'planUpdate', id: 'p5', status: 'done' },

  { kind: 'runState',  value: 'completed' },
  { kind: 'showCard',  card: 'findings', data: {
      headline: '14 cell types identified · 847 cluster markers (FDR < 0.05)',
      bullets: [
        'scuttle QC → scran normalisation → scater UMAP → SingleR annotation → pseudo-bulk DESeq2',
        'CD14+ Mono (cluster 3) top marker: S100A9, log2FC 4.2, FDR 1.4e-18',
        'Pseudo-bulk used — avoids inflated p-values from treating cells as independent replicates',
      ],
  }},
  { kind: 'marker', id: 'bioc_scrna_done' },
]
```

### `RESEARCH_PHASE_TRACE` entries

```js
'bioc_scrna:pseudobulk_warning': {
  rationale: 'Cells from the same donor share genetic background and batch effects — they are not independent observations. Running standard DE (DESeq2, edgeR) cell-by-cell massively inflates the number of false positives because the effective sample size is the number of donors, not the number of cells.',
  citation: 'Squair et al. (2021) Nature Communications 12:5692 — "Confronting false discoveries in single-cell differential expression"',
},
'bioc_scrna:pseudobulk_choice': {
  rationale: 'Pseudo-bulk aggregation sums raw counts per donor per cell type, then runs bulk DE methods (DESeq2, edgeR) on those donor-level sums. This correctly treats donors as the unit of replication. Requires ≥3 donors per condition; works best with ≥6.',
  citation: 'Crowell et al. (2020) Nature Communications 11:6077',
},
```

### DEMO_TOURS entry

```js
{
  id: 'bioc-scrna-chain',
  label: 'Bioconductor · Single-cell RNA-seq chain',
  group: 'bioconductor',
  scenario: 'bioc_scrna',
  cartoon: true,
  steps: [
    {
      target: null,
      placement: 'center',
      title: 'Single-cell RNA-seq in BioMate',
      body: <>
        Five-step chain: QC → normalise → cluster → annotate → DE.
        Watch how BioMate catches the most common single-cell mistake mid-pipeline.
        <div className="hint">~2.5 min</div>
      </>,
    },
    {
      target: '[data-tour="plan-checklist"]',
      placement: 'bottom',
      title: 'Parallel steps',
      body: <>Clustering and cell-type annotation run in parallel — the plan checklist shows the connector line between p3 and p4.</>,
      setup: () => { window.__tourFFTo('bioc_scrna_cluster_start'); return null; },
    },
    {
      target: '[data-speaker="qc"]',
      placement: 'right',
      title: 'Anti-pattern caught',
      body: <>
        A red QC pill — not a gate failure, but an architectural warning.
        BioMate detects the request to run DESeq2 cell-by-cell and flags it before it runs.
        <div className="hint">Hover (why?) for the Squair et al. citation.</div>
      </>,
      setup: () => { window.__tourFFTo('bioc_scrna_pseudobulk_warn'); return null; },
    },
    {
      target: '[data-speaker="wf"][data-rationale-id="bioc_scrna:pseudobulk_choice"]',
      placement: 'right',
      title: 'Corrected to pseudo-bulk',
      body: <>BioMate switches to donor aggregation automatically and explains the correction in chat. No user action needed.</>,
    },
    {
      target: '[data-tour="findings-card"]',
      placement: 'top',
      title: '14 cell types, 847 markers',
      body: <>Results include a note that pseudo-bulk was used — so anyone reading the Methods section sees the correct statistical design.</>,
      setup: () => { window.__tourFFTo('bioc_scrna_done'); return null; },
      cta: 'Done',
    },
  ],
},
```

---

## Voiceover scripts (Demo Narratives style)

### B1 · Microarray vs RNA-seq routing (~2 min)

> **Scenario context.** A biologist asks BioMate to find differentially expressed probes in an Affymetrix microarray dataset. BioMate detects the data format, routes away from DESeq2, explains the routing with a citation, and runs limma. A (why?) anchor on the routing line lets users verify the decision.

**[00:00–00:10]** · **[Step 1 — Welcome, centered]**
"Same question, different data, different tool. BioMate routes to limma for microarray and DESeq2 for RNA-seq counts — and explains the decision inline."

**[00:11–00:22]** · **[Step 2 — Plan checklist]**
"Five steps: detect format, select package, run, enrich, report. The format-detection step is what makes the routing safe."

**[00:23–00:36]** · **[Step 3 — Format detected]**
"Continuous log-two intensities from an Affymetrix array. That's the disqualifier for DESeq2 — it models raw integer counts. The AGENT pill surfaces this before any tool runs."

**[00:37–00:52]** · **[Step 4 — Routed to limma]**
"The WF pill announces limma. The (why?) anchor to the right of the line opens the rationale — Ritchie et al. two-thousand-fifteen, Nucleic Acids Research. Reviewers and collaborators can follow the citation directly from chat."

**[00:53–01:20]** · **[Step 5 — Four phases run]**
"Normalise, model and contrast, empirical Bayes, enrichment. limma's eBayes borrows variance across probes — that's what stabilises estimates when some genes have few observations. Phase cards tick as they complete."

**[01:21–01:38]** · **[Step 6 — Findings card]**
"Twelve hundred and four probes significant. The findings card includes a note: would have been wrong to use DESeq2 on pre-normalised intensities. That note comes from the limma SKILL.md When-NOT-to-Use field — a direct link between the knowledge base and the report."

**[01:39–02:00]** · **[Step 7 — Wrap-up, centered]**
"Context-sensitive routing, inline rationale, citable decision trail. Try the same flow with a raw count matrix — DESeq2 is selected and the (why?) explains the switch."

---

### B2 · Single-cell RNA-seq chain (~2.5 min)

> **Scenario context.** A biologist submits a 10x Genomics count matrix. BioMate runs the full scRNA-seq chain — QC, normalise, cluster, annotate — and catches the most common single-cell DE mistake before it happens.

**[00:00–00:10]** · **[Step 1 — Welcome, centered]**
"Five Bioconductor packages, one chain. And one anti-pattern catch that changes the statistical design mid-pipeline."

**[00:11–00:22]** · **[Step 2 — Plan · parallel items]**
"Five plan items. Clustering and cell-type annotation run in parallel — the plan checklist shows the connector line between them. Both must complete before pseudo-bulk DE starts."

**[00:23–00:42]** · **[Step 3 — QC and normalise]**
"scuttle filters fifteen thousand cells down to thirteen thousand on library size, gene count, and mitochondrial percent — all MAD-based thresholds. scDblFinder removes four hundred twelve doublets. scran pooled size factors for normalisation."

**[00:43–01:00]** · **[Step 4 — Cluster + annotate]**
"scater runs P-C-A then U-M-A-P. Fourteen clusters emerge from graph-based clustering. SingleR annotates each cluster against the Human Primary Cell Atlas. Both plan items complete together."

**[01:01–01:25]** · **[Step 5 — Anti-pattern caught]**
"A red QC pill — not a gate failure, an architectural warning. Running DESeq2 on individual cells inflates false positives — cells from the same donor aren't independent replicates. The effective sample size is the number of donors, not the number of cells. Hover (why?) to read the Squair et al. two-thousand-twenty-one citation."

**[01:26–01:45]** · **[Step 6 — Corrected to pseudo-bulk]**
"BioMate switches automatically to pseudo-bulk aggregation — summing raw counts per donor per cell type, then running DESeq2 on eight donor-level observations. No user action, correct statistics, auditable decision in chat."

**[01:46–02:10]** · **[Step 7 — Findings]**
"Fourteen cell types, eight hundred forty-seven markers at FDR less than zero-point-zero-five. The findings card notes that pseudo-bulk was used — so the Methods section reflects the correct statistical design from the start."

**[02:11–02:30]** · **[Step 8 — Wrap-up, centered]**
"The QC pill does double duty: it flags gate failures and flags design anti-patterns. The (why?) anchor makes every architectural decision citable. Download the After-run report for the full R script and methods prose."
