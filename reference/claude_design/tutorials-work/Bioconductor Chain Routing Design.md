# Bioconductor Chain Routing Design — Research Agent UI

**For:** Claude design / engineering handoff  
**Builds on:** `Research Agent UI.html` + `HANDOFF_RESEARCH_AGENT_UI.md`  
**What this adds:** How multi-step Bioconductor workflow chains map onto the existing tape engine, plan checklist, and speaker pills. No new UI surfaces needed — chains reuse the same five surfaces already in the prototype.

---

## 1. What changes for chained workflows

A single-package scenario has one WF phase: one tool runs, one result lands. A chain has multiple sequential phases where the **output object class of step N is the input type of step N+1**. The Research Agent UI already supports this — phases are the unit — but chains require:

1. **Plan checklist items = chain phases**, not individual steps. Step-level granularity lives in the workflow panel's phase cards (same as today).
2. **WF speaker narrates the data handoff between phases** — the SCE object, the GRanges, the DESeqResults — so the user understands why packages compose.
3. **QC gates can fire mid-chain**, not just at the end. The existing QC pill and halt card handle this without modification.
4. **Disambiguation card** appears when the user's query matches multiple chains at similar score (see section 4).

---

## 2. Chain → tape mapping

### 2.1 Plan items

Chain phases map one-to-one to plan items. For `bulk_rnaseq_de_analysis`:

```js
[
  { id: 'c1', title: 'QC & filtering',   status: 'pending', est_s: 10 },
  { id: 'c2', title: 'Normalisation',    status: 'pending', est_s: 15 },
  { id: 'c3', title: 'DE testing',       status: 'pending', est_s: 30 },
  { id: 'c4', title: 'LFC shrinkage',    status: 'pending', est_s: 8  },
  { id: 'c5', title: 'Pathway enrichment', status: 'pending', est_s: 20 },
  { id: 'c6', title: 'Visualisation',    status: 'pending', est_s: 10 },
]
```

### 2.2 WF lines narrate the object handoff

After each phase, the WF speaker announces the output object class that feeds the next phase. This is the key teaching moment for chained workflows — users learn why Bioconductor packages compose cleanly:

```js
// After normalisation completes:
{ kind: 'chatLine', s: 'wf',
  m: 'Normalisation complete → `DESeqDataSet` (size factors estimated, counts stored). Passing to DE testing.' },

// After DE testing completes:
{ kind: 'chatLine', s: 'wf',
  m: 'DE results → `DESeqResults` object (log2FC, padj, baseMean per gene). Passing to LFC shrinkage.' },

// After shrinkage:
{ kind: 'chatLine', s: 'wf',
  m: 'Shrinkage complete → posterior log2FC estimates (apeglm). Passing to enrichment and visualisation.' },
```

### 2.3 QC gate mid-chain

For chains where a gate can fail a middle phase (e.g., too few replicates for DESeq2), the existing halt card fires and pauses the chain:

```js
{ kind: 'chatLine', s: 'qc-err',
  m: 'QC gate: DESeq2 requires ≥2 biological replicates per condition. Only 1 detected in "treated" group.' },
// → halt card appears. User edits sample metadata or dismisses.
// → on accept: tape resumes from c3
```

No new components needed. The existing `AutoLoopCard` with `autoloop: false` covers this.

---

## 3. Full tape — `bulk_rnaseq_de_analysis` chain

```js
RESEARCH_SCENARIOS.bioc_deseq2 = {
  id: 'bioc_deseq2',
  label: 'Bulk RNA-seq DE (DESeq2 chain)',
  v1Panel: 'nfcore',
  tape: [

    // ── Plan ──────────────────────────────────────────────
    { kind: 'planShow' },
    { kind: 'chatLine', s: 'plan',
      m: 'Routing query to chain: **bulk_rnaseq_de_analysis** (6 phases, DESeq2 → apeglm → clusterProfiler → EnhancedVolcano).',
      rationaleId: 'bioc_deseq2:chain_routing' },

    // ── Phase 1: QC ───────────────────────────────────────
    { kind: 'planUpdate', id: 'c1', status: 'running' },
    { kind: 'runState',   value: 'running' },
    { kind: 'phaseUpdate', id: 'phase-qc', status: 'running' },
    { kind: 'chatLine', s: 'wf',
      m: 'Phase 1 · QC. `edgeR::filterByExpr` — removing genes with <10 counts in ≥2 samples. 18,421 → 14,203 genes retained.' },
    { kind: 'phaseUpdate', id: 'phase-qc', status: 'completed' },
    { kind: 'planUpdate', id: 'c1', status: 'done' },

    // ── Phase 2: Normalisation ────────────────────────────
    { kind: 'planUpdate', id: 'c2', status: 'running' },
    { kind: 'phaseUpdate', id: 'phase-norm', status: 'running' },
    { kind: 'chatLine', s: 'wf',
      m: 'Phase 2 · Normalisation. `DESeq2::estimateSizeFactors` (median-of-ratios). Size factors: 0.91–1.14 (healthy range).' },
    { kind: 'phaseUpdate', id: 'phase-norm', status: 'completed' },
    { kind: 'chatLine', s: 'wf',
      m: '→ `DESeqDataSet` object ready. Passing to DE testing.',
      rationaleId: 'bioc_deseq2:dds_handoff' },
    { kind: 'planUpdate', id: 'c2', status: 'done' },

    // ── Phase 3: DE testing ───────────────────────────────
    { kind: 'planUpdate', id: 'c3', status: 'running' },
    { kind: 'phaseUpdate', id: 'phase-de', status: 'running' },
    { kind: 'chatLine', s: 'wf',
      m: 'Phase 3 · DE testing. Design: `~ condition`. Wald test, nbinom model. 2,841 genes FDR < 0.05.' },
    { kind: 'phaseUpdate', id: 'phase-de', status: 'completed' },
    { kind: 'chatLine', s: 'wf',
      m: '→ `DESeqResults` object. log2FC + padj per gene. Passing to LFC shrinkage.' },
    { kind: 'planUpdate', id: 'c3', status: 'done' },

    // ── Phase 4: Shrinkage ────────────────────────────────
    { kind: 'planUpdate', id: 'c4', status: 'running' },
    { kind: 'phaseUpdate', id: 'phase-shrink', status: 'running' },
    { kind: 'chatLine', s: 'wf',
      m: 'Phase 4 · LFC shrinkage. `apeglm` posterior estimation. Stabilises log2FC estimates for low-count genes.',
      rationaleId: 'bioc_deseq2:apeglm_why' },
    { kind: 'phaseUpdate', id: 'phase-shrink', status: 'completed' },
    { kind: 'planUpdate', id: 'c4', status: 'done' },

    // ── Phase 5: Enrichment ───────────────────────────────
    { kind: 'planUpdate', id: 'c5', status: 'running' },
    { kind: 'phaseUpdate', id: 'phase-enrich', status: 'running' },
    { kind: 'chatLine', s: 'wf',
      m: 'Phase 5 · Pathway enrichment. clusterProfiler `gseGO` (gene-set enrichment, GO BP). Top: "regulation of apoptotic process" (p.adj 2.1e-11).' },
    { kind: 'phaseUpdate', id: 'phase-enrich', status: 'completed' },
    { kind: 'planUpdate', id: 'c5', status: 'done' },

    // ── Phase 6: Visualisation ────────────────────────────
    { kind: 'planUpdate', id: 'c6', status: 'running' },
    { kind: 'phaseUpdate', id: 'phase-viz', status: 'running' },
    { kind: 'chatLine', s: 'wf',
      m: 'Phase 6 · Visualisation. EnhancedVolcano (volcano), enrichplot dotPlot (pathways), ComplexHeatmap (top 50 DE genes).' },
    { kind: 'phaseUpdate', id: 'phase-viz', status: 'completed' },
    { kind: 'planUpdate', id: 'c6', status: 'done' },

    // ── Done ──────────────────────────────────────────────
    { kind: 'runState',  value: 'completed' },
    { kind: 'planLock' },
    { kind: 'showCard', card: 'findings', data: {
        headline: '2,841 differentially expressed genes (FDR < 0.05)',
        bullets: [
          'DESeq2 Wald test (design: ~ condition) · apeglm shrinkage applied',
          'Top pathway: regulation of apoptotic process (GO BP, p.adj 2.1e-11)',
          'Outputs: DE table, volcano, dotplot, heatmap, R script, methods prose',
        ],
    }},
    { kind: 'chatLine', s: 'find',
      m: '**2,841 genes significant.** Full chain: DESeq2 → apeglm → clusterProfiler → EnhancedVolcano. After-run report ready.' },
    { kind: 'marker', id: 'bioc_deseq2_done' },
  ],
};
```

### `RESEARCH_PHASE_TRACE` entries

```js
'bioc_deseq2:chain_routing': {
  rationale: 'The user\'s query matched chain bulk_rnaseq_de_analysis (cosine similarity 0.71 > 0.5 threshold) over single-step DESeq2 because the query mentioned "end-to-end analysis" — a signal that a full multi-step chain is needed, not just the DE step.',
  citation: 'BioMate chain routing: Tier-1 cosine (all-MiniLM-L6-v2) + Tier-2 Jaccard, 90% accuracy on 15 chains',
},
'bioc_deseq2:dds_handoff': {
  rationale: 'DESeqDataSet is the S4 object that carries: raw count matrix, colData (sample metadata), design formula, and estimated size factors. All downstream DESeq2 functions operate on this single object — the immutable-input pattern prevents accidental use of pre-normalised values.',
  citation: 'Love et al. (2014) Genome Biology 15:550',
},
'bioc_deseq2:apeglm_why': {
  rationale: 'Standard maximum-likelihood log2FC estimates are noisy for low-count genes. apeglm applies adaptive t-prior shrinkage — genes with high variance (low counts) are shrunk toward zero; high-count genes are barely moved. This is essential for ranked-list enrichment downstream (fgsea, GSEA): noisy extreme LFCs for low-count genes pollute the ranking.',
  citation: 'Zhu et al. (2019) Bioinformatics 35:2084',
},
```

---

## 4. Disambiguation — multiple chains match

When two chains score similarly (e.g., "end-to-end FASTQ to DE pipeline" matches both `bulk_rnaseq_de_analysis` and `bp4_rnaseq_best_practices_pipeline`), the disambiguation card already exists in the prototype (`ComparisonCard` can be repurposed, or a new `disambigCard` event can be added to the tape).

### Tape pattern for disambiguation

```js
{ kind: 'chatLine', s: 'plan',
  m: 'Two workflows match your request at similar confidence. Showing options.' },
{ kind: 'showCard', card: 'disambig', data: {
    options: [
      {
        id: 'bulk_rnaseq_de_analysis',
        label: 'Standard DE Analysis',
        sub: '6 steps · start from count matrix',
        detail: 'DESeq2 → apeglm → clusterProfiler → EnhancedVolcano',
        badge: 'faster',
      },
      {
        id: 'bp4_rnaseq_best_practices_pipeline',
        label: 'Best-Practices Pipeline (BP4)',
        sub: '9 steps · start from raw FASTQ',
        detail: 'STAR → featureCounts → DESeq2 → fgsea',
        badge: 'full run',
      },
    ],
}},
{ kind: 'await', label: 'disambig_selected' },
// tape resumes with the selected chain's events
```

**`AWAIT_ACCEPTS` entry to add:**
```js
'disambig_selected': ['chain_option_click'],
```

The `disambigCard` differs from `ComparisonCard` in that it has no metrics table or delta column — it's a pre-run choice, not a post-run comparison. Simplest implementation: a new card variant in `ChatCards.jsx` that renders two option columns with a `[Select]` button each.

---

## 5. The epigenomics chain (`methylation_450k_array_analysis`)

This chain demonstrates a different backbone object: **GRanges / GenomicRatioSet** instead of DESeqDataSet. Include it as the third Bioconductor demo to show the GRanges handoff pattern.

### Plan items

```js
[
  { id: 'm1', title: 'Read IDAT files',      status: 'pending', est_s: 20 },
  { id: 'm2', title: 'QC + normalisation',   status: 'pending', est_s: 30 },
  { id: 'm3', title: 'DMP calling',          status: 'pending', est_s: 25 },
  { id: 'm4', title: 'DMR calling',          status: 'pending', est_s: 40 },
  { id: 'm5', title: 'GO enrichment (CpG-corrected)', status: 'pending', est_s: 15 },
]
```

### Key WF handoff lines

```js
{ kind: 'chatLine', s: 'wf',
  m: 'Phase 1 → `MethylSet` (raw M-values + U-values from IDAT). 450,000 probes, 24 samples.' },

{ kind: 'chatLine', s: 'wf',
  m: 'Phase 2 → `GenomicRatioSet` (β-values, QC-passed, quantile-normalised). Probe coordinates attached.' },

{ kind: 'chatLine', s: 'wf',
  m: 'Phase 3 DMP results → `data.frame` of 12,403 significant CpGs (FDR < 0.05). Passing to bumphunter for regional analysis.' },

{ kind: 'chatLine', s: 'wf',
  m: 'Phase 4 → `GRanges` of 847 DMRs. Passing to missMethyl for CpG-bias-corrected enrichment.',
  rationaleId: 'bioc_methyl:cpg_bias' },
```

### `RESEARCH_PHASE_TRACE` entry

```js
'bioc_methyl:cpg_bias': {
  rationale: 'Standard GO enrichment (clusterProfiler, topGO) treats all genes equally. But CpG-dense gene promoters are over-represented on the 450k array — so standard ORA is biased toward CpG-rich gene sets. missMethyl::gometh corrects for the number of CpGs per gene as a prior probability, giving calibrated enrichment p-values.',
  citation: 'Phipson et al. (2016) Bioinformatics 32:1165',
},
```

---

## 6. DEMO_TOURS entry for the DESeq2 chain

```js
{
  id: 'bioc-deseq2-chain',
  label: 'Bioconductor · DESeq2 chain (6 phases)',
  group: 'bioconductor',
  scenario: 'bioc_deseq2',
  cartoon: true,
  steps: [
    {
      target: null,
      placement: 'center',
      title: 'Six phases, one chain',
      body: <>
        DESeq2 → apeglm → clusterProfiler → EnhancedVolcano.
        Each phase hands off a typed R object to the next.
        Watch how BioMate narrates the handoffs.
        <div className="hint">~2 min</div>
      </>,
    },
    {
      target: '[data-speaker="plan"][data-rationale-id="bioc_deseq2:chain_routing"]',
      placement: 'right',
      title: 'Chain selected',
      body: <>The PLAN pill announces which chain was matched and why. (why?) shows the routing score.</>,
      setup: () => { window.__tourFFTo('bioc_deseq2_chain_announced'); return null; },
    },
    {
      target: '[data-speaker="wf"][data-rationale-id="bioc_deseq2:dds_handoff"]',
      placement: 'right',
      title: 'Object handoff narrated',
      body: <>After normalisation, the WF pill names the output object class — DESeqDataSet — so users understand what flows into the next phase.</>,
      setup: () => { window.__tourFFTo('bioc_deseq2_norm_done'); return null; },
    },
    {
      target: '[data-speaker="wf"][data-rationale-id="bioc_deseq2:apeglm_why"]',
      placement: 'right',
      title: 'Shrinkage explained',
      body: <>
        apeglm is not the default in all DESeq2 workflows. The (why?) explains why BioMate applies it here —
        especially important for downstream ranked-list enrichment.
      </>,
      setup: () => { window.__tourFFTo('bioc_deseq2_shrink_done'); return null; },
    },
    {
      target: '[data-tour="after-tab-outputs"]',
      placement: 'top',
      title: 'Outputs across all 6 phases',
      body: <>The Outputs tab in the After-run report lists every file: DE table, volcano PNG, dotplot PNG, heatmap PNG, R script, methods prose. One download, all phases.</>,
      setup: () => {
        window.__tourFFTo('bioc_deseq2_done');
        return { runState: 'completed' };
      },
    },
    {
      target: null,
      placement: 'center',
      title: 'The chain pattern',
      body: <>
        Each Bioconductor chain follows the same structure: plan items = phases,
        WF pill narrates object handoffs, QC gates can halt mid-chain,
        findings card summarises at the end.
      </>,
      cta: 'Done',
    },
  ],
},
```

---

## 7. Voiceover script — DESeq2 chain (~2 min)

> **Scenario context.** A biologist submits a raw count matrix and asks for a full DE analysis. BioMate routes to the `bulk_rnaseq_de_analysis` chain, runs 6 phases, narrates each typed object handoff, and delivers a findings card.

**[00:00–00:10]** · **[Step 1 — Welcome, centered]**
"Six Bioconductor packages, one chain. D-E-Seq-two, apeglm, clusterProfiler, EnhancedVolcano. Watch how BioMate narrates what flows between phases."

**[00:11–00:22]** · **[Step 2 — Chain selected]**
"The PLAN pill announces which chain was matched — bulk underscore r-n-a-seq underscore D-E underscore analysis — and the (why?) shows the routing confidence score."

**[00:23–00:40]** · **[Step 3 — Object handoff after normalisation]**
"After Phase two completes, the WF pill names the output: DESeqDataSet, with size factors estimated and counts stored. That's what flows into DE testing. Users learn why packages compose — the object class is the contract."

**[00:41–00:55]** · **[Step 4 — DE results]**
"Phase three. Wald test, negative binomial model. Two thousand eight hundred forty-one genes FDR less than zero-point-zero-five. The DESeqResults object flows to apeglm."

**[00:56–01:12]** · **[Step 5 — Shrinkage]**
"apeglm applies adaptive shrinkage to log-two fold changes — low-count genes are shrunk toward zero, stabilising the ranking for downstream enrichment. Hover (why?) to read the Zhu et al. two-thousand-nineteen citation."

**[01:13–01:30]** · **[Step 6 — Enrichment and visualisation]**
"clusterProfiler gene-set enrichment. Top pathway: regulation of apoptotic process, p-adjusted two-point-one times ten to the negative eleven. EnhancedVolcano, dotplot, heatmap — all land as output chips on their phase rows."

**[01:31–01:50]** · **[Step 7 — Findings + outputs tab]**
"Findings card inline. Switch to the Outputs tab in the After-run report — every file across all six phases, one download. The methods prose is already written in I-M-Ra-D format, ready for the manuscript."

**[01:51–02:05]** · **[Step 8 — Wrap-up, centered]**
"Plan items equal chain phases. WF pills narrate object handoffs. QC gates can halt mid-chain. Findings card closes the loop. Same pattern for the methylation chain, the ChIP-seq chain, the single-cell chain."
