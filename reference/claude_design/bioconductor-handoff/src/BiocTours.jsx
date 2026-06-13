// BiocTours.jsx — comprehensive ~3-minute walkthroughs for the three
// Bioconductor demos. Loaded AFTER Tour.jsx; it overrides the `.steps` of
// the three tours already registered in window.DEMO_TOURS (the picker reads
// only {id,label} so labels stay intact; startDemo reads .steps live).
//
// Each tutorial follows one arc:
//   understand → choose (route) → RUN the chain phase-by-phase →
//   walk the full After-run report, tab by tab.
// FF-driven: every step resets the engine and fast-forwards to a named
// marker so the visible chat + panel always match the narration.

(function () {
  const T = window.DEMO_TOURS;
  if (!T) return;

  // Reset the engine and fast-forward to a marker (markers only resolve
  // forward of head, so we reset first for deterministic back/forward nav).
  const ff = (m) => {
    if (window.__tourReset) window.__tourReset();
    if (window.__tourFFTo) window.__tourFFTo(m);
  };
  const tab = (sel) => { const b = document.querySelector(sel); if (b) b.click(); };
  const scroll = (sel, block) => {
    const e = document.querySelector(sel);
    if (e) e.scrollIntoView({ behavior: 'smooth', block: block || 'start' });
  };

  // Shared After-run tab walk. `done` is the scenario's completion marker;
  // `sw` is a per-scenario blurb naming the actual tools in each tab.
  const afterRunSteps = (done, sw) => ([
    { target: '[data-tour="findings-chat"]', placement: 'right', icon: '✨',
      title: sw.completeTitle,
      body: sw.completeBody,
      setup: () => { ff(done); return { runState: 'completed' }; },
      },

    { target: '[data-tour="results-links"]', placement: 'left', icon: '📦',
      title: 'After run · one structured report',
      body: (<>The completed run opens a tabbed <b>After run</b> report — seven tabs in natural read order: results first, methods + reproducibility next, audit last. We'll walk each one.<div className="hint">The whole report also exports to one DOCX / Markdown / LaTeX document.</div></>),
      setup: () => { if (window.__tourFFTo) window.__tourFFTo(done); tab('[data-tour="link-report"]'); scroll('[data-tour="results-links"]', 'start'); return { runState: 'completed' }; },
      },

    { target: '[data-tour="after-run-body"]', placement: 'left', icon: '✨',
      title: 'Findings · the headline',
      body: sw.findingsBody,
      setup: () => { if (window.__tourFFTo) window.__tourFFTo(done); tab('[data-tour="link-report"]'); return { runState: 'completed' }; },
      },

    { target: '[data-tour="after-run-body"]', placement: 'left', icon: '📁',
      title: 'Outputs · every file produced',
      body: sw.outputsBody,
      setup: () => { if (window.__tourFFTo) window.__tourFFTo(done); tab('[data-tour="link-view-results"]'); return { runState: 'completed' }; },
      },

    { target: '.preview-modal', placement: 'left', icon: '🖼️',
      title: sw.previewTitle,
      body: sw.previewBody,
      setup: () => { if (window.__tourFFTo) window.__tourFFTo(done); if (window.__openTourModal) window.__openTourModal('preview', { file: sw.preview }); return { runState: 'completed' }; },
      },

    { target: '[data-tour="after-run-body"]', placement: 'left', icon: '📝',
      title: 'Methods · paste-ready prose',
      body: sw.methodsBody,
      setup: () => { if (window.__closeTourModal) window.__closeTourModal(); if (window.__tourFFTo) window.__tourFFTo(done); tab('[data-tour="after-tab-imrad"]'); return { runState: 'completed' }; },
      },

    { target: '[data-tour="after-run-body"]', placement: 'left', icon: '🧮',
      title: 'Parameters · every knob',
      body: sw.paramsBody,
      setup: () => { if (window.__tourFFTo) window.__tourFFTo(done); tab('[data-tour="after-tab-params"]'); return { runState: 'completed' }; },
      },

    { target: '[data-tour="after-run-body"]', placement: 'left', icon: '🧰',
      title: 'Software · pinned versions',
      body: sw.softwareBody,
      setup: () => { if (window.__tourFFTo) window.__tourFFTo(done); tab('[data-tour="after-tab-software"]'); return { runState: 'completed' }; },
      },

    { target: '[data-tour="after-run-body"]', placement: 'left', icon: '📚',
      title: 'Citations · pre-formatted refs',
      body: sw.citeBody,
      setup: () => { if (window.__tourFFTo) window.__tourFFTo(done); tab('[data-tour="after-tab-cite"]'); return { runState: 'completed' }; },
      },

    { target: '[data-tour="after-run-body"]', placement: 'left', icon: '🛡️',
      title: 'QC audit · the compliance lens',
      body: sw.qcBody,
      setup: () => { if (window.__tourFFTo) window.__tourFFTo(done); tab('[data-tour="link-qc"]'); return { runState: 'completed' }; },
      },
  ]);

  // ─────────────────────────────────────────────────────────────
  // BIO — Bioconductor · DESeq2 chain (bulk RNA-seq)
  // ─────────────────────────────────────────────────────────────
  if (!T['bioc-kb-routing']) T['bioc-kb-routing'] = { id: 'bioc-kb-routing', label: 'BIO — Bioconductor · KB routing & execution' };
  {
    T['bioc-kb-routing'].steps = [
      { target: null, placement: 'center', icon: '🧬',
        title: 'Bioconductor · DESeq2 chain',
        body: (<>A differential-expression run, end to end. BioMate <b>matches</b> your request to a curated Bioconductor workflow, <b>routes</b> each step to the right package, runs the <b>six-phase chain</b>, then hands you a full report.<div className="hint">~3 min · match → route → run → report. Sit back — the tour drives every step.</div></>),
        setup: () => { if (window.__tourReset) window.__tourReset(); return { scenario: 'bioc_kb', runState: 'idle' }; },
        },

      { target: '.wf-unselected', placement: 'left', icon: '🔎',
        title: 'Understanding the request',
        body: (<>BioMate embeds your request against the <b>Bioconductor knowledge base</b>. The panel stays empty for now — it won't commit to a pipeline before the match is resolved.<div className="hint">No phases yet: the workflow is still being selected.</div></>),
        setup: () => { ff('bioc_kb_plan'); scroll('.wf-unselected', 'center'); return null; },
        },

      { target: '[data-tour="disambig-card"]', placement: 'right', icon: '⤳',
        title: 'Ranked knowledge-base match',
        body: (<>Two curated chains scored close — a count-matrix DESeq2 path (0.71) and a fuller FASTQ pipeline (0.66). Rather than guess, BioMate surfaces both with scores; the top match is pre-selected with a commit countdown.<div className="hint">Tip: ranked retrieval runs server-side — the card just exposes the decision.</div></>),
        setup: () => { ff('bioc_kb_disambig'); return null; },
        },

      { target: '[data-tour="phase-list"]', placement: 'left', icon: '🗂️',
        title: 'Selected · the chain populates the panel',
        body: (<>With <b>bulk_rnaseq_de_analysis</b> chosen, the panel fills with its <b>six phases</b> — QC → normalise → DE test → shrink → enrich → visualise. Only now does a pipeline exist; chat and panel track the same run.<div className="hint">Phases appear only once the workflow is committed.</div></>),
        setup: () => { ff('bioc_kb_selected'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '.reason-block', placement: 'right', icon: '🧭',
        title: 'Routed by data format, not habit',
        body: (<>The <b>AGENT</b> block explains the choice: a raw integer <b>count matrix</b> calls for a negative-binomial model — <b>DESeq2</b> — not limma/voom, which is for continuous log₂ intensities.<div className="hint">Tip: the <i>“Why”</i> line under the headline expands to the full reasoning + citation.</div></>),
        setup: () => { ff('bioc_kb_routed'); return null; },
        },

      { target: '[data-tour="phase-list"] .phase.open', placement: 'left', icon: '🔬',
        title: 'Phase A running · QC filtering',
        body: (<>Execution starts and the active phase auto-expands. <code>edgeR::filterByExpr</code> drops genes under 10 counts; as each step finishes its parameters and output files appear inline.<div className="hint">Only the running phase is open — the rest stay collapsed and scannable.</div></>),
        setup: () => { ff('bioc_kb_A_run'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '.reason-block', placement: 'right', icon: '📦',
        title: 'One typed object carries the analysis',
        body: (<>After normalisation, counts + metadata + size factors fold into a single <code>DESeqDataSet</code>. That object class is the contract every downstream DESeq2 step reads from.<div className="hint">DESeqDataSet → DESeqResults → shrunk LFCs, each a typed handoff.</div></>),
        setup: () => { ff('bioc_kb_norm_done'); return null; },
        },

      { target: '[data-tour="phase-list"] .phase.open', placement: 'left', icon: '🧮',
        title: 'Phase C running · DE testing',
        body: (<>The Wald test runs on design <code>~ condition</code> — <b>2,841 genes</b> at FDR &lt; 0.05 — producing a <code>DESeqResults</code> table of log₂FC, p-adj and baseMean per gene.<div className="hint">Phases A–B already read DONE above; progress tracks in lockstep.</div></>),
        setup: () => { ff('bioc_kb_C_run'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '.reason-block', placement: 'right', icon: '🎚️',
        title: 'Shrink noisy fold-changes first',
        body: (<>Before ranking, <code>apeglm</code> shrinks low-count fold-changes toward zero, so the gene list feeding enrichment isn’t dominated by noisy extremes.<div className="hint">Tip: apeglm isn’t a blind default — the AGENT block says why it’s applied here.</div></>),
        setup: () => { ff('bioc_kb_shrink_done'); return null; },
        },

      { target: '[data-tour="phase-list"] .phase.open', placement: 'left', icon: '🧬',
        title: 'Phase E running · enrichment',
        body: (<>clusterProfiler <code>gseGO</code> runs on the shrunk, ranked list — top GO term <i>regulation of apoptotic process</i>. Phase F then renders the volcano, dotplot and heatmap.<div className="hint">Enrichment reads the ranked list, so shrinkage quality matters here.</div></>),
        setup: () => { ff('bioc_kb_E_run'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      ...afterRunSteps('bioc_kb_done', {
        preview: { name: 'volcano.png', type: 'image', viz: 'volcano' },
        previewTitle: 'Visualised · volcano plot',
        previewBody: (<>Clicking <b>view</b> on <code>volcano.png</code> renders it inline — log₂ fold-change vs −log₁₀ p.adj, up genes in red, down in blue, cutoff lines drawn. BioMate picks the volcano viewer from the file type.<div className="hint">Every output renders inline; no need to download to look.</div></>),
        completeTitle: 'Chain complete · 2,841 DE genes',
        completeBody: (<>All six phases done: DESeq2 → apeglm → clusterProfiler → EnhancedVolcano. The chat drops a findings card and the panel flips to the <b>After run</b> report.<div className="hint">Next: we walk every tab of that report.</div></>),
        findingsBody: (<>Headline metric, a few bullets, and figures read straight from the run manifest — DE direction split, top GO terms, the gene-filtering QC bar. No numbers are invented.<div className="hint">Findings without a citation are tagged <i>author judgment</i>.</div></>),
        outputsBody: (<>One row per file, grouped by phase and step — <code>deseq_results.rds</code>, <code>volcano.png</code>, the GO dotplot, the top-50 heatmap. <b>view</b> previews inline; <b>download</b> grabs one file or all.<div className="hint">BioMate picks the right viewer per file type.</div></>),
        methodsBody: (<>Paragraph-form Methods you can paste into a manuscript — tools, versions and exact parameters, written so peers can replicate the DESeq2 run.<div className="hint">Inferred values are flagged separately from manifest-read ones.</div></>),
        paramsBody: (<>Phase · step · parameter · value for everything the run touched — from <code>filterByExpr</code> thresholds to the <code>apeglm</code> shrinkage type. A ready supplementary table.<div className="hint">Defaults, user overrides and auto-loop tweaks are distinguished.</div></>),
        softwareBody: (<>Every package with its exact version — DESeq2, apeglm, edgeR, clusterProfiler, EnhancedVolcano. Match these with Parameters and you reproduce the run.<div className="hint">This pair is the reproducibility baseline.</div></>),
        citeBody: (<>An auto-generated reference list for the tools and methods named in Methods — Love 2014 (DESeq2), Zhu 2019 (apeglm), Wu 2021 (clusterProfiler), and more.<div className="hint">Methods + Citations ship together in the Download report export.</div></>),
        qcBody: (<>Every QC gate that fired — gene-retention, size-factor range, replicate count — with threshold, observed value, result and action. <b>21 CFR Part 11</b> friendly, with chain-of-custody.<div className="hint">Zero manual interventions means the run was fully automated and auditable.</div></>),
      }),

      { target: null, placement: 'center', icon: '🌟',
        title: 'That’s the full DESeq2 thread',
        body: (<>Match → route → run six phases → a seven-tab report, all from one request. <b>Download report</b> wraps it into a single document for Word, Notion / GitHub, or a journal template.<div className="hint">Try the scRNA-seq and methylation tutorials next — same agent, different science.</div></>),
        cta: 'Done' },
    ];
  }

  // ─────────────────────────────────────────────────────────────
  // BIO2 — Bioconductor · scRNA-seq → pseudobulk DE
  // ─────────────────────────────────────────────────────────────
  if (!T['bioc-sc-routing']) T['bioc-sc-routing'] = { id: 'bioc-sc-routing', label: 'BIO — Bioconductor · single-cell RNA-seq chain' };
  {
    T['bioc-sc-routing'].steps = [
      { target: null, placement: 'center', icon: '🔬',
        title: 'Bioconductor · scRNA-seq chain',
        body: (<>Same agent, a single-cell request. BioMate routes to the <b>OSCA</b> stack, clusters and annotates in parallel, then runs condition DE the statistically correct way — pseudobulk.<div className="hint">~3 min · route → cluster → annotate → pseudobulk DE → report.</div></>),
        setup: () => { if (window.__tourReset) window.__tourReset(); return { scenario: 'bioc_sc', runState: 'idle' }; },
        },

      { target: '[data-tour="phase-list"]', placement: 'left', icon: '🗂️',
        title: 'Seven phases · a parallel branch',
        body: (<>QC → normalise → feature/PCA → cluster → <b>markers and annotation in parallel</b> → pseudobulk DE. Marker detection and annotation both read the clustered object, so they’re grouped to run concurrently.<div className="hint">The panel mirrors the chat 1-to-1, parallel phases included.</div></>),
        setup: () => { ff('bioc_sc_plan'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '.reason-block', placement: 'right', icon: '🧭',
        title: 'Routed to the OSCA stack',
        body: (<>The <b>AGENT</b> block works backward from the goal: condition DE with DESeq2 means a <code>SingleCellExperiment</code> + scran/scater — not Seurat — so the final pseudobulk step hands off with no lossy conversion.<div className="hint">Tip: routing is the whole object ecosystem, not just one tool.</div></>),
        setup: () => { ff('bioc_sc_routed'); return null; },
        },

      { target: '[data-tour="phase-list"] .phase.open', placement: 'left', icon: '🔬',
        title: 'Phase A running · cell QC',
        body: (<><code>emptyDrops</code> separates real cells from ambient barcodes, then <code>perCellQCMetrics</code> flags high-mito / low-count cells — <b>9,814 of 12,402</b> retained. The running phase auto-expands.<div className="hint">Step params and outputs land inline as each finishes.</div></>),
        setup: () => { ff('bioc_sc_A_run'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '.reason-block', placement: 'right', icon: '📦',
        title: 'One SingleCellExperiment throughout',
        body: (<>QC + normalisation fold into a single <code>SingleCellExperiment</code> carrying counts, logcounts, metadata and size factors. Every step below — including pseudobulk DESeq2 — reads from this one object.<div className="hint">Staying SCE-native is what avoids a lossy conversion at the end.</div></>),
        setup: () => { ff('bioc_sc_sce_handoff'); return null; },
        },

      { target: '[data-tour="phase-list"]', placement: 'left', icon: '🕸️',
        title: 'Phases B–D done · 11 clusters',
        body: (<>Normalisation, HVG selection + PCA, and graph-based clustering (<code>buildSNNGraph</code> + Louvain) are complete — <b>11 clusters</b>, with a UMAP for visualisation only.<div className="hint">UMAP is a picture, not the clustering — clusters come from the SNN graph.</div></>),
        setup: () => { ff('bioc_sc_cluster_done'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '[data-tour="phase-list"]', placement: 'left', icon: '⑂',
        title: 'Parallel branch · markers ∥ annotation',
        body: (<>Phases E and F open together: <code>scoreMarkers</code> and <code>SingleR</code> (vs the Human Primary Cell Atlas) both read the clustered object, so the engine fans them out and tracks the join.<div className="hint">Independent steps run concurrently; dependent ones wait.</div></>),
        setup: () => { ff('bioc_sc_parallel_run'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '.reason-block', placement: 'right', icon: '⚠️',
        title: 'Pseudobulk, not naive per-cell DE',
        body: (<>The key teaching beat: the <b>QC</b> block flags the trap — testing thousands of cells as replicates is <b>pseudoreplication</b> — and the <b>AGENT</b> block gives the fix: aggregate to pseudobulk so the 6 samples are the real replicates, then DESeq2 per cell type.<div className="hint">The agent corrects the stats trap before running the test.</div></>),
        setup: () => { ff('bioc_sc_pseudobulk_warn'); return null; },
        },

      ...afterRunSteps('bioc_sc_done', {
        preview: { name: 'umap.png', type: 'image', viz: 'umap' },
        previewTitle: 'Visualised · annotated UMAP',
        previewBody: (<>Clicking <b>view</b> on <code>umap.png</code> renders the embedding inline — 9,814 cells coloured by the 8 SingleR cell types, with a legend. The UMAP is for visualisation; clusters come from the SNN graph.<div className="hint">Every output renders inline; no need to download to look.</div></>),
        completeTitle: 'Chain complete · 8 cell types',
        completeBody: (<>All seven phases done — routed to OSCA, clustered, annotated in parallel, then pseudobulk DE. CD8⁺ T cells are the strongest responder (214 DE genes on true replicates).<div className="hint">Next: we walk every tab of the report.</div></>),
        findingsBody: (<>Headline plus figures from the manifest — DE genes per cell type, cell-type composition, and QC retention. Pseudobulk means significance rests on the 6 biological replicates.<div className="hint">Findings without a citation are tagged <i>author judgment</i>.</div></>),
        outputsBody: (<>Files grouped by phase and step — <code>umap.png</code>, the marker heatmap, per-cell-type DE tables, and the cell-type calls (<code>celltypes.csv</code>). <b>view</b> previews; <b>download</b> grabs one or all.<div className="hint">BioMate picks the right viewer per file type.</div></>),
        methodsBody: (<>Paste-ready Methods — emptyDrops QC, scran normalisation, SNN/Louvain clustering, SingleR annotation, and aggregateAcrossCells → DESeq2, with versions and parameters.<div className="hint">Inferred values are flagged separately from manifest-read ones.</div></>),
        paramsBody: (<>Phase · step · parameter · value — <code>emptyDrops</code> FDR, HVG count, SNN <code>k</code>, the SingleR reference, the pseudobulk design. A ready supplementary table.<div className="hint">Defaults, overrides and auto-loop tweaks are distinguished.</div></>),
        softwareBody: (<>Exact versions — DropletUtils, scran, scater, SingleR, DESeq2. Match these with Parameters and you reproduce the run.<div className="hint">This pair is the reproducibility baseline.</div></>),
        citeBody: (<>References for the methods named above — Amezquita 2020 (OSCA), Lun 2019 (emptyDrops), Aran 2019 (SingleR), Love 2014 (DESeq2).<div className="hint">Methods + Citations ship together in the Download report export.</div></>),
        qcBody: (<>Every QC gate — cells retained, size-factor range, cluster count, pruned clusters, and the replicate-unit gate (sample, not cell). Threshold, observed value, result, action.<div className="hint">The replicate-unit gate is what enforces pseudobulk over per-cell DE.</div></>),
      }),

      { target: null, placement: 'center', icon: '🌟',
        title: 'That’s the single-cell thread',
        body: (<>Route to OSCA → cluster → annotate in parallel → pseudobulk DE → a seven-tab report. One object, one request, statistically honest DE.<div className="hint">Compare with the bulk DESeq2 and methylation tutorials — same agent, different data.</div></>),
        cta: 'Done' },
    ];
  }

  // ─────────────────────────────────────────────────────────────
  // BIO3 — Bioconductor · 450k methylation → DMRs
  // ─────────────────────────────────────────────────────────────
  if (!T['bioc-methyl-routing']) T['bioc-methyl-routing'] = { id: 'bioc-methyl-routing', label: 'BIO — Bioconductor · 450k methylation chain' };
  {
    T['bioc-methyl-routing'].steps = [
      { target: null, placement: 'center', icon: '🧫',
        title: 'Bioconductor · 450k methylation chain',
        body: (<>A methylation-array request. This chain rides a <b>genomic backbone</b> object instead of a count matrix — probe coordinates travel with the data so region-level analysis is possible.<div className="hint">~3 min · IDAT → GenomicRatioSet → DMRs → CpG-corrected GO → report.</div></>),
        setup: () => { if (window.__tourReset) window.__tourReset(); return { scenario: 'bioc_methyl', runState: 'idle' }; },
        },

      { target: '[data-tour="phase-list"]', placement: 'left', icon: '🗂️',
        title: 'Five phases, mirrored in the panel',
        body: (<>Read IDAT → QC + normalise → DMP calling → DMR calling → CpG-corrected enrichment. The panel shows the same five phases the chat narrates.<div className="hint">Each phase lists its real minfi steps, parameters and outputs.</div></>),
        setup: () => { ff('bioc_methyl_plan'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '.reason-block', placement: 'right', icon: '🧭',
        title: 'Routed to minfi',
        body: (<>The <b>AGENT</b> block explains it: raw <b>IDAT</b> + a 450k manifest routes to <b>minfi</b>, because the downstream DMR step needs a genomic object, not a plain matrix.<div className="hint">Tip: the input format picks the whole ecosystem, not just one tool.</div></>),
        setup: () => { ff('bioc_methyl_routed'); return null; },
        },

      { target: '[data-tour="phase-list"] .phase.open', placement: 'left', icon: '🔬',
        title: 'Phase A running · read IDAT',
        body: (<><code>minfi::read.metharray.exp</code> reads the IDAT pairs into a <code>MethylSet</code> — raw methylated + unmethylated intensities, 450k probes × 24 samples. The running phase auto-expands.<div className="hint">Step params and outputs land inline as each finishes.</div></>),
        setup: () => { ff('bioc_methyl_A_run'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '.reason-block', placement: 'right', icon: '📦',
        title: 'GenomicRatioSet · coordinates attached',
        body: (<>After QC + normalisation the object is a <code>GenomicRatioSet</code>: β-values <i>with</i> each probe’s genomic coordinate. That GRanges backbone is what lets the next step collapse CpGs into regions.<div className="hint">MethylSet → GenomicRatioSet → data.frame → GRanges, each typed.</div></>),
        setup: () => { ff('bioc_methyl_grset_done'); return null; },
        },

      { target: '[data-tour="phase-list"] .phase.open', placement: 'left', icon: '🧮',
        title: 'Phase C running · DMP calling',
        body: (<>Per-CpG differential methylation with <code>limma</code> eBayes on <b>M-values</b> (design <code>~ group</code>) — <b>12,403</b> significant CpGs at FDR &lt; 0.05. Per-CpG statistics flow into DMRcate next.<div className="hint">M-values for testing; β-values for reporting.</div></>),
        setup: () => { ff('bioc_methyl_C_run'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '[data-tour="phase-list"]', placement: 'left', icon: '🧬',
        title: 'Phase D done · 847 DMRs',
        body: (<><code>DMRcate</code> smooths the per-CpG limma statistics along the genome (kernel λ = 1000) and calls <b>847 regions</b> — a <code>GRanges</code> object of DMRs, ready for enrichment.<div className="hint">Region-level analysis is only possible because coordinates rode along.</div></>),
        setup: () => { ff('bioc_methyl_dmr_done'); scroll('[data-tour="phase-list"]', 'center'); return null; },
        },

      { target: '.reason-block', placement: 'right', icon: '⚠️',
        title: 'CpG-density bias correction',
        body: (<>The teaching beat: the <b>QC</b> block flags the trap — a normal GO over-represents CpG-rich promoters on the array — and the <b>AGENT</b> block gives the fix: <code>missMethyl::gometh</code> weights genes by CpG count so enrichment p-values stay calibrated.<div className="hint">The agent reaches for the array-aware tool, not the generic one.</div></>),
        setup: () => { ff('bioc_methyl_cpg_warn'); return null; },
        },

      ...afterRunSteps('bioc_methyl_done', {
        preview: { name: 'dmr_tracks.png', type: 'image', viz: 'manhattan' },
        previewTitle: 'Visualised · DMR manhattan',
        previewBody: (<>Clicking <b>view</b> on <code>dmr_tracks.png</code> renders it inline — −log₁₀ p across chromosomes, with the 847 significant DMRs above the region-wide threshold highlighted.<div className="hint">Every output renders inline; no need to download to look.</div></>),
        completeTitle: 'Chain complete · 847 DMRs',
        completeBody: (<>All five phases done — minfi read, normalised, limma DMPs, DMRcate DMRs, CpG-corrected GO. 847 DMRs from 12,403 significant CpGs.<div className="hint">Next: we walk every tab of the report.</div></>),
        findingsBody: (<>Headline plus figures from the manifest — DMR direction (hyper / hypo), top CpG-corrected GO terms, and probe-QC retention. Numbers read from the run, not generated.<div className="hint">Findings without a citation are tagged <i>author judgment</i>.</div></>),
        outputsBody: (<>Files by phase and step — <code>dmps.csv</code> (12,403 CpGs), <code>dmrs.rds</code> (847 DMRs as GRanges), and the CpG-corrected <code>go_enrichment.csv</code>. <b>view</b> previews; <b>download</b> grabs one or all.<div className="hint">BioMate picks the right viewer per file type.</div></>),
        methodsBody: (<>Paste-ready Methods — read.metharray, detection-p QC, SNP/cross-reactive filtering, preprocessQuantile, limma DMPs, DMRcate DMRs, gometh enrichment — with versions and parameters.<div className="hint">Inferred values are flagged separately from manifest-read ones.</div></>),
        paramsBody: (<>Phase · step · parameter · value — detection-p cutoff, the M-value design, DMRcate kernel λ + significance cutoff, the gometh array type. A ready supplementary table.<div className="hint">Defaults, overrides and auto-loop tweaks are distinguished.</div></>),
        softwareBody: (<>Exact versions — minfi, limma, DMRcate, missMethyl. Match these with Parameters and you reproduce the run.<div className="hint">This pair is the reproducibility baseline.</div></>),
        citeBody: (<>References for the methods above — Aryee 2014 (minfi), Peters 2015 (DMRcate), Phipson 2016 (missMethyl), Ritchie 2015 (limma).<div className="hint">Methods + Citations ship together in the Download report export.</div></>),
        qcBody: (<>Every QC gate — samples read, probes retained, significant-CpG count, DMR count, and the CpG-bias-corrected flag. Threshold, observed value, result, action.<div className="hint">The bias-corrected gate is what enforces gometh over a generic GO test.</div></>),
      }),

      { target: null, placement: 'center', icon: '🌟',
        title: 'That’s the epigenomics thread',
        body: (<>A GRanges backbone → DMPs → DMRs → CpG-corrected enrichment → a seven-tab report. A different object lineage from the other two demos, same orchestration.<div className="hint">That completes the three Bioconductor tutorials.</div></>),
        cta: 'Done' },
    ];
  }
  window.BIOC_TOURS_LOADED = true;
})();
