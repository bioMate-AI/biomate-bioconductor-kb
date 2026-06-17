// Tutorial Tour — scenario-specific demo tours for video recording.
//
// Structure:
//   DEMO_TOURS[demoId] = { label, scenario, steps: [...] }
// Each step can set `setup(tweaks)` to drive the UI into the right state
// before the step shows.

const DEMO_TOURS = {
  // ── Overview (original general walkthrough) ──────────────────────
  overview: {
    label: 'Overview — full walkthrough',
    group: 'General',
    scenario: 'nfcore',
    steps: [
      {
        target: null, placement: 'center',
        title: 'Welcome to the Workflow Panel',
        body: (
          <>
            A quick walkthrough of how BioMate runs a bioinformatics pipeline — the{' '}
            <b>phase hierarchy</b>, <b>live progress</b>, <b>QC gates</b>, and{' '}
            <b>recovery flows</b> when things go sideways.
            <div className="hint">Use <kbd>→</kbd>/<kbd>←</kbd> to step, <kbd>Esc</kbd> to skip.</div>
          </>
        ),
        setup: () => ({
          scenario: 'nfcore', runState: 'running', qcHalt: false,
          licenseGate: false, blocked: false, disambig: false,
          watcherAttached: true, sidebarMode: 'auto',
        }),
      },
      {
        target: '[data-tour="chat-handoff"]', placement: 'right',
        title: 'From chat to workflow',
        body: <>You ask Biomate to run something in plain language. It resolves the intent to a concrete pipeline and hands off to the <b>Workflow Panel</b>.</>,
        setup: () => ({ scenario: 'nfcore', disambig: false }),
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'Run status at a glance',
        body: <>Workflow name, domain, and a <b>live progress bar</b> — steps completed / total, plus percent.</>,
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Phases, not a flat step list',
        body: <>A pipeline is grouped into <b>phases</b>. Only the phase you're watching needs to be expanded.</>,
      },
      {
        target: '[data-tour="phase-list"] .phase.open', placement: 'left',
        title: 'Drill into the running phase',
        body: <>The active phase auto-expands — <b>steps</b> with live status, per-step actions, and any outputs already produced.</>,
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'When a QC gate fails',
        body: <>If a quality gate trips, Biomate can <b>auto-loop</b> — retry with adjusted parameters, up to a cap.</>,
        setup: () => ({ qcHalt: true, runState: 'running' }),
      },
      {
        target: '[data-tour="panel-body"]', placement: 'left',
        title: 'Blocking errors surface inline',
        body: <>Missing parameters or license gaps show as an <b>alert at the top of the panel</b> — not a toast that disappears.</>,
        setup: () => ({ qcHalt: false, blocked: true, licenseGate: true }),
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        title: 'One primary action',
        body: <>The footer always shows <b>one</b> primary button — Confirm & Run, Cancel, or Run Again.</>,
        setup: () => ({ blocked: false, licenseGate: false, runState: 'running' }),
      },
      // Watcher tour step removed — detach/reconnect feature is commented out
      // in the panel for this release. Restore alongside the watcher row.
      {
        target: null, placement: 'center',
        title: "You're ready to explore",
        body: (
          <>
            Flip the <b>Tweaks</b> toggle to jump between scenarios, run states, and edge cases.
            Replay any demo from the <b>Tutorial</b> dropdown.
          </>
        ),
        cta: 'Got it',
      },
    ],
  },

  // ── R01 — Bulk RNA-seq · chat-side surfaces walkthrough ──────────
  // ── BIOC — Bioconductor · KB routing & execution ─────────────────
  //
  // FULLY FF-DRIVEN. Each step jumps the engine to a named marker so the
  // visible UI matches the hint. Shows the three KB beats: ranked
  // disambiguation, context-based package routing, and typed object
  // handoffs through the DESeq2 chain.
  'bioc-kb-routing': {
    label: 'BIO — Bioconductor · KB routing & execution',
    group: 'Bioconductor',
    scenario: 'bioc_kb',
    cartoon: true,
    manualStream: true,
    steps: [
      {
        target: null, placement: 'center',
        icon: '🧬',
        title: 'Knowledge-based routing & execution',
        body: (
          <>
            BioMate embeds your request against a curated <b>Bioconductor knowledge base</b>,
            disambiguates close matches, routes each step to the right package, then runs the chain.
            <div className="hint">One end-to-end DESeq2 analysis — match, route, execute.</div>
          </>
        ),
        setup: () => { window.__tourReset && window.__tourReset(); return { scenario: 'bioc_kb', runState: 'idle' }; },
      },
      {
        target: '[data-tour="disambig-card"]', placement: 'right',
        icon: '⤳',
        title: 'Ranked KB match',
        body: (
          <>
            Two chains scored similarly, so BioMate surfaces both with their match scores rather than
            guessing. The top match is pre-selected; a countdown commits to it if you don't choose.
            <div className="hint">Ranked selection runs server-side — the card just exposes the decision.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_kb_disambig'); return null; },
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '🧭',
        title: 'Routed by data format',
        body: (
          <>
            The <b>AGENT</b> block — <i>Route by the data type, not by habit</i> — explains the choice:
            a raw <b>count matrix</b> means DESeq2, not limma. The reasoning and citation are shown inline,
            right under the headline.
            <div className="hint">Same goal ("find DE genes") routes to different packages by data type.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_kb_routed'); return null; },
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '📦',
        title: 'Typed object handoff',
        body: (
          <>
            After normalisation the agent names the output object — <code>DESeqDataSet</code>. The object
            class is the contract that lets Bioconductor packages compose cleanly down the chain.
            <div className="hint">DESeqDataSet → DESeqResults → shrunk LFCs, each a typed handoff.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_kb_norm_done'); return null; },
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '🎚️',
        title: 'Why apeglm shrinkage',
        body: (
          <>
            apeglm isn't always the default — the <b>AGENT</b> block <i>Shrink noisy fold-changes before ranking</i>
            explains why BioMate applies it here, so noisy low-count fold-changes don't pollute the ranked list.
            <div className="hint">Architectural choices stay legible, inline in chat.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_kb_shrink_done'); return null; },
      },
      {
        target: '[data-tour="findings-chat"]', placement: 'right',
        icon: '✨',
        title: '2,841 DE genes · chain complete',
        body: (
          <>
            All six phases done: DESeq2 → apeglm → clusterProfiler → EnhancedVolcano —{' '}
            <b>2,841 DE genes</b> at FDR &lt; 0.05, top pathway <i>regulation of apoptotic process</i>.
            <div style={{marginTop:9, fontWeight:600, fontSize:10.5, letterSpacing:'0.05em', textTransform:'uppercase', opacity:0.65}}>Outputs delivered</div>
            <ul style={{margin:'4px 0 0 15px', padding:0, lineHeight:1.65}}>
              <li><code>de_results.csv</code> — full DESeq2 table (2,841 genes)</li>
              <li><code>volcano.png</code> — EnhancedVolcano plot</li>
              <li><code>go_dotplot.png</code> — clusterProfiler GO enrichment</li>
              <li><code>top_genes_heatmap.png</code> — top DE-gene heatmap</li>
              <li><code>methods_2026-05-31.md</code> — reproducible methods report</li>
            </ul>
            <div className="hint">Match → route → execute → report — one complete thread.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_kb_done'); return { runState: 'completed' }; },
        cta: 'Done',
      },
    ],
  },

  // ── BIO2 — Bioconductor · single-cell (scRNA-seq) chain ──────────
  //
  // FULLY FF-DRIVEN. Highlights the beats that make single-cell distinct
  // from the bulk DESeq2 demo: routing to the OSCA / SingleCellExperiment
  // stack, a PARALLEL marker+annotation branch, and the pseudobulk-vs-naive
  // teaching warning before condition DE.
  'bioc-sc-routing': {
    label: 'BIO2 — Bioconductor · scRNA-seq → pseudobulk DE',
    group: 'Bioconductor',
    scenario: 'bioc_sc',
    cartoon: true,
    manualStream: true,
    steps: [
      {
        target: null, placement: 'center',
        icon: '🔬',
        title: 'Single-cell, the Bioconductor way',
        body: (
          <>
            Same agent, a single-cell request. BioMate routes to the <b>OSCA</b> stack, clusters and
            annotates in parallel, then does condition DE the statistically correct way — pseudobulk.
            <div className="hint">Cluster → annotate → pseudobulk DE, one SingleCellExperiment throughout.</div>
          </>
        ),
        setup: () => { window.__tourReset && window.__tourReset(); return { scenario: 'bioc_sc', runState: 'idle' }; },
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '🧭',
        title: 'Routed to the OSCA stack',
        body: (
          <>
            The <b>AGENT</b> block — <i>Pick the toolkit by working backward from the goal</i> — explains why a
            <code>SingleCellExperiment</code> + scran/scater, not Seurat: staying Bioconductor-native lets the
            final pseudobulk step hand off to DESeq2 with no lossy conversion. The reasoning is shown inline.
            <div className="hint">Routing isn't just the tool — it's the whole object ecosystem.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_sc_routed'); return null; },
      },
      {
        target: '[data-tour="plan-checklist"]', placement: 'bottom',
        icon: '⑂',
        title: 'A parallel plan branch',
        body: (
          <>
            Marker detection and cell-type annotation both read the clustered object, so BioMate groups
            them to run <b>concurrently</b> — the checklist shows the two rows running side by side.
            <div className="hint">Independent steps fan out; the engine tracks the join.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_sc_cluster_done'); return null; },
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '⚠️',
        title: 'Pseudobulk, not naive per-cell DE',
        body: (
          <>
            The key teaching moment, told in two stacked blocks: the <b>QC</b> block flags the trap —
            testing thousands of cells as replicates is <b>pseudoreplication</b> — and the <b>AGENT</b> block
            gives the fix: aggregate to pseudobulk so the 6 samples are the real replicates, then DESeq2 per cell type.
            <div className="hint">The agent corrects the stats trap before it runs the test.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_sc_pseudobulk_warn'); return null; },
      },
      {
        target: '[data-tour="findings-chat"]', placement: 'right',
        icon: '✨',
        title: '8 cell types · CD8⁺ T strongest',
        body: (
          <>
            All seven phases done — routed to the OSCA stack, clustered, annotated, then pseudobulk DE.
            <b> 8 cell types</b>; CD8⁺ T the strongest responder (214 DE genes on true replicates).
            <div style={{marginTop:9, fontWeight:600, fontSize:10.5, letterSpacing:'0.05em', textTransform:'uppercase', opacity:0.65}}>Outputs delivered</div>
            <ul style={{margin:'4px 0 0 15px', padding:0, lineHeight:1.65}}>
              <li><code>umap_celltypes.png</code> — annotated UMAP (8 types)</li>
              <li><code>marker_heatmap.png</code> — per-cluster marker heatmap</li>
              <li><code>pseudobulk_DE/</code> — per-cell-type DE tables (48 profiles)</li>
              <li><code>sce_annotated.rds</code> — the SingleCellExperiment object</li>
            </ul>
            <div className="hint">Route → cluster → annotate → pseudobulk DE — one complete thread.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_sc_done'); return { runState: 'completed' }; },
        cta: 'Done',
      },
    ],
  },

  // ── BIO3 — Bioconductor · 450k methylation (epigenomics) chain ───
  //
  // FULLY FF-DRIVEN. The signature beat here is a different backbone
  // object lineage — MethylSet → GenomicRatioSet → GRanges — plus the
  // CpG-density bias correction for enrichment (missMethyl::gometh).
  'bioc-methyl-routing': {
    label: 'BIO3 — Bioconductor · 450k methylation → DMRs',
    group: 'Bioconductor',
    scenario: 'bioc_methyl',
    cartoon: true,
    manualStream: true,
    steps: [
      {
        target: null, placement: 'center',
        icon: '🧫',
        title: 'Epigenomics — a genomic backbone',
        body: (
          <>
            A methylation-array request. This chain rides a <b>GRanges</b> backbone instead of a count
            matrix — probe coordinates travel with the data so region-level analysis is possible.
            <div className="hint">IDAT → GenomicRatioSet → DMRs → CpG-corrected GO.</div>
          </>
        ),
        setup: () => { window.__tourReset && window.__tourReset(); return { scenario: 'bioc_methyl', runState: 'idle' }; },
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '🧭',
        title: 'Routed to minfi',
        body: (
          <>
            The <b>AGENT</b> block — <i>The input format picks the whole toolkit</i> — explains why raw
            <b>IDAT</b> + a 450k manifest routes to <b>minfi</b>: it needs a genomic object, not a plain matrix,
            for the DMR step downstream.
            <div className="hint">The input format picks the whole ecosystem, not just one tool.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_methyl_routed'); return null; },
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '📦',
        title: 'GenomicRatioSet — coordinates attached',
        body: (
          <>
            After QC + normalisation the object is a <code>GenomicRatioSet</code>: β-values <i>with</i> probe
            genomic coordinates. That GRanges backbone is what lets bumphunter later collapse CpGs into regions.
            <div className="hint">MethylSet → GenomicRatioSet → data.frame → GRanges, each typed.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_methyl_grset_done'); return null; },
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '⚠️',
        title: 'CpG-density bias correction',
        body: (
          <>
            The teaching beat, in two blocks: the <b>QC</b> block flags the trap — a normal GO over-represents
            CpG-rich promoters on the array — and the <b>AGENT</b> block gives the fix: <code>missMethyl::gometh</code>
            weights genes by CpG count so enrichment p-values are calibrated.
            <div className="hint">The agent reaches for the array-aware tool, not the generic one.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_methyl_cpg_warn'); return null; },
      },
      {
        target: '[data-tour="findings-chat"]', placement: 'right',
        icon: '✨',
        title: '847 DMRs · chain complete',
        body: (
          <>
            All five phases done — minfi read, normalised, DMPs, bumphunter DMRs, CpG-corrected GO.
            <b> 847 DMRs</b> collapsed from 12,403 significant CpGs.
            <div style={{marginTop:9, fontWeight:600, fontSize:10.5, letterSpacing:'0.05em', textTransform:'uppercase', opacity:0.65}}>Outputs delivered</div>
            <ul style={{margin:'4px 0 0 15px', padding:0, lineHeight:1.65}}>
              <li><code>dmps.csv</code> — 12,403 significant CpGs</li>
              <li><code>dmrs.rds</code> — 847 DMRs as a GRanges object</li>
              <li><code>gometh_GO.csv</code> — CpG-corrected enrichment table</li>
            </ul>
            <div className="hint">Read → normalise → DMP → DMR → corrected GO — one complete thread.</div>
          </>
        ),
        setup: () => { window.__tourReset(); window.__tourFFTo('bioc_methyl_done'); return { runState: 'completed' }; },
        cta: 'Done',
      },
    ],
  },

  // ── R01 — Bulk RNA-seq · chat surfaces ───────────────────────────
  'rnaseq-chat': {
    label: 'R01 — Bulk RNA-seq · chat surfaces',
    group: 'Bulk RNA-seq',
    scenario: 'rnaseq',
    cartoon: true,
    steps: [
      {
        target: null, placement: 'center',
        icon: '🧬',
        title: 'Chat-side surfaces for Bulk RNA-seq',
        body: (
          <>
            BioMate's chat is more than a log — it carries a <b>plan checklist</b>,
            speaker-pilled progress lines, and decision cards for the pilot and comparisons.
            <div className="hint">Run a 120-sample DESeq2 from start to finish in 4 steps.</div>
          </>
        ),
        setup: () => ({ scenario: 'rnaseq', runState: 'idle' }),
      },
      {
        target: '[data-tour="plan-checklist"]', placement: 'bottom',
        icon: '📋',
        title: 'Plan checklist',
        body: (
          <>
            When a query decomposes into multiple sub-tasks, BioMate posts a sticky <b>plan checklist</b> at the
            top of the chat. Items tick from <span className="kbd">○</span> → <span className="kbd">●</span> → <span className="kbd">✓</span> in place
            and parallel groups show a <code>⇄</code> glyph.
            <div className="hint">For this 5-task RNA-seq run, two enrichment items are grouped as parallel.</div>
          </>
        ),
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '🗣️',
        title: 'Speaker-pilled chat lines',
        body: (
          <>
            Every progress line carries a color-coded pill: <b>PLAN</b>, <b>WF</b>, <b>QC</b>, <b>LOOP</b>, <b>AGENT</b>, <b>FIND</b>.
            Hover any pill for its role. Three consecutive same-speaker lines collapse to a caret.
            <div className="hint">Same speaker taxonomy across plan, chat, and Tweaks — pill colors are stable everywhere.</div>
          </>
        ),
      },
      {
        target: '[data-tour="pilot-prompt"]', placement: 'right',
        icon: '🔬',
        title: 'Pilot-first prompt',
        body: (
          <>
            When the run is heavy enough to justify it, BioMate posts a pilot prompt inline. Sampling fraction
            and strategy are part of the card — no separate dialog.
            <div className="hint">Hover any <code>(why?)</code> anchor on a step-decision line to see why BioMate picked that tool.</div>
          </>
        ),
        cta: 'Done',
      },
    ],
  },

  // ── R02 — Drug screen · auto-loop + comparison ───────────────────
  //
  // FULLY AUTOMATED. Each step's setup() jumps the engine to a named
  // marker (window.__tourFFTo) so the visible UI always matches the
  // hint. The tour auto-advances on a timer — the user just watches.
  // Esc exits at any point.
  'drugscreen-compare': {
    label: 'R02 — Drug screen · auto-loop + comparison',
    group: 'Drug screen',
    scenario: 'drugscreen',
    cartoon: true,
    steps: [
      {
        target: null, placement: 'center',
        icon: '⚖️',
        title: 'Pilot · fail · auto-loop · compare',
        body: (
          <>
            Drug screens often need a pilot, fail QC, and recover via auto-loop. We'll watch the whole sequence inline — and meet the only scenario that surfaces the <b>Run-vs-Run comparison card</b> by default.
            <div className="hint">Fully automated · ~90 seconds. Just read along; the tour drives every decision.</div>
          </>
        ),
        setup: () => {
          if (window.__tourSetScenario) window.__tourSetScenario('drugscreen');
          if (window.__tourReset) window.__tourReset();
          return null;
        },
        autoAdvance: 7000,
      },
      {
        target: '[data-tour="plan-checklist"]', placement: 'bottom',
        icon: '📋',
        title: 'Plan checklist · 5 sub-tasks',
        body: (
          <>
            Ingest → ADMET → hERG gate → Ames gate → rank. Each ticks in place. QC gates surface as <b>warn ⚠</b> pills on plan items when triggered.
            <div className="hint">Watch the hERG and Ames rows — they'll trip mid-pilot.</div>
          </>
        ),
        setup: () => {
          if (window.__tourFFTo) window.__tourFFTo('plan_visible');
          return null;
        },
        autoAdvance: 6500,
      },
      {
        target: '[data-tour="pilot-prompt"]', placement: 'right',
        icon: '🔬',
        title: 'Pilot-first prompt',
        body: (
          <>
            10k compounds is heavy. The DeepAgent suggests a <b>5% pilot</b> first. The card carries sampling fraction + strategy side-by-side with the full run.
            <div className="hint">No separate dialog — the decision lives in chat.</div>
          </>
        ),
        setup: () => {
          if (window.__tourFFTo) window.__tourFFTo('pilot_prompt');
          return null;
        },
        autoAdvance: 7000,
      },
      {
        target: '[data-tour="plan-checklist"]', placement: 'bottom',
        icon: '⏳',
        title: 'Pilot running',
        body: (
          <>
            The pilot is now running on 500 of 10,000 compounds. Plan items tick from <span className="kbd">○</span> → <span className="kbd">●</span> → <span className="kbd">✓</span> as the engine advances.
            <div className="hint">A small pilot validates the QC gates before committing the full run.</div>
          </>
        ),
        setup: () => {
          if (window.__tourFFTo) window.__tourFFTo('pilot_running');
          return null;
        },
        autoAdvance: 6500,
      },
      {
        target: '[data-tour="plan-checklist"]', placement: 'bottom',
        icon: '⚠️',
        title: 'QC failure mid-pilot',
        body: (
          <>
            <b>hERG</b> and <b>Ames</b> trip — the plan items flip to amber warn pills in place. No interruption of the running pipeline; the next surface carries the decision.
            <div className="hint">QC gates evaluate per phase; a trip here means the auto-loop will propose fixes.</div>
          </>
        ),
        setup: () => {
          if (window.__tourFFTo) window.__tourFFTo('qc_failed');
          return null;
        },
        autoAdvance: 7000,
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '🛑',
        title: 'QC speaker pills',
        body: (
          <>
            Two <b>QC</b> pill lines land in chat: one for hERG, one for Ames. Pill colour is amber — same speaker taxonomy as the warn pills on the plan.
            <div className="hint">Pill colours never lie — they're stable across plan, chat, and Tweaks.</div>
          </>
        ),
        autoAdvance: 6000,
      },
      {
        target: '[data-tour="pilot-promotion"]', placement: 'right',
        icon: '🔬',
        title: 'Pilot stopped · QC gates triggered',
        body: (
          <>
            The pilot promotion card explains what failed and shows the auto-loop's <b>fix suggestion</b> right there — new logp_max and mw_max values, with a one-click "Apply fixes and re-pilot" action.
            <div className="hint">No silent retry — the user always sees the proposed change before it runs.</div>
          </>
        ),
        setup: () => {
          if (window.__tourFFTo) window.__tourFFTo('pilot_promotion_shown');
          return null;
        },
        autoAdvance: 8000,
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '🔁',
        title: 'Auto-loop · LOOP speaker',
        body: (
          <>
            We just applied the fix. The <b>LOOP</b> speaker (purple pill) takes over — every line under LOOP is an auto-loop decision so the audit trail is clear.
            <div className="hint">QC re-evaluates and both gates pass on the second run.</div>
          </>
        ),
        setup: () => {
          if (window.__tourFFTo) window.__tourFFTo('autoloop_running');
          return null;
        },
        autoAdvance: 6500,
      },
      {
        target: '[data-tour="comparison-card"]', placement: 'right',
        icon: '🏆',
        title: 'Run-vs-Run comparison card',
        body: (
          <>
            Two pilots done. The comparison card lays them side-by-side: metrics table with a <b>Δ column</b>, parameter diffs tagged by origin (auto-loop vs user), and a 🏆 recommendation badge with confidence + p-value.
            <div className="hint">QC outcomes are coloured — Run A red, Run B green — so the decision reads at a glance.</div>
          </>
        ),
        setup: () => {
          if (window.__tourFFTo) window.__tourFFTo('comparison_shown');
          return null;
        },
        autoAdvance: 8500,
      },
      {
        target: '[data-tour="comparison-card"]', placement: 'right',
        icon: '⏱️',
        title: '10-second auto-pick',
        body: (
          <>
            When confidence is <b>high</b> (here: p &lt; 0.01), the recommended button shows a 10s countdown. Hover any button to pause; click to commit. Auto-fire emits a "No response — using Run B automatically" line so nothing happens silently.
            <div className="hint">Medium/low confidence: no auto-fire. The card sits until the user picks.</div>
          </>
        ),
        autoAdvance: 7000,
      },
      {
        target: '[data-tour="plan-checklist"]', placement: 'bottom',
        icon: '🚀',
        title: 'Full run · Run B params',
        body: (
          <>
            Decision committed (Run B). The full screen now runs on 10k compounds using the auto-loop's tuned parameters. Plan items tick again — fast, since the pilot already proved the gates.
            <div className="hint">Real backend would skip ingest if cached; the UI surface is identical either way.</div>
          </>
        ),
        setup: () => {
          if (window.__tourFFTo) window.__tourFFTo('fullrun_running');
          return null;
        },
        autoAdvance: 6500,
      },
      {
        target: '[data-tour="findings-chat"]', placement: 'right',
        icon: '✨',
        title: 'Findings card · 47 candidates',
        body: (
          <>
            The completion summary lands inline — final candidate count, runtime, QC pass-rate, and a link to the full <b>Report</b> (Findings · Outputs · Methods · Parameters · Software · Citations).
            <div className="hint">Hover any <code>(why?)</code> anchor on earlier step lines to see the rationale that drove tool choice.</div>
          </>
        ),
        setup: () => {
          if (window.__tourFFTo) window.__tourFFTo('findings_shown');
          return null;
        },
        autoAdvance: 7000,
      },
      {
        target: null, placement: 'center',
        icon: '🌟',
        title: "End-to-end auto-loop, done",
        body: (
          <>
            You just watched <b>pilot → fail → auto-loop → compare → full → findings</b>. Three decision cards, one comparison card, and a clean audit trail by speaker.
            <div className="hint">The Variant calling tutorial covers nested plans + step retry — try it next.</div>
          </>
        ),
        cta: 'Done',
      },
    ],
  },

  // ── R03 — Variant calling · nested plan + retry ──────────────────
  'variant-retry': {
    label: 'R03 — Variant calling · plan edit + retry',
    group: 'Variant calling',
    scenario: 'variant',
    cartoon: true,
    steps: [
      {
        target: null, placement: 'center',
        icon: '🧫',
        title: 'Plan edit · failure · retry',
        body: (
          <>
            We'll watch BioMate plan a 5-step GATK4 variant-calling run, give you a 10-second window to edit the plan before it locks, then handle a real failure on step 3 with an auto-loop retry.
            <div className="hint">Tour drives the engine — no clicking in-app, just read along.</div>
          </>
        ),
        setup: () => ({ scenario: 'variant', runState: 'idle' }),
      },
      {
        target: '[data-tour="plan-checklist"]', placement: 'bottom',
        icon: '📋',
        title: 'Plan checklist · 3 phases',
        body: (
          <>
            Decomposed into <b>reference + alignment → variant calling → annotation</b>. Same three units the workflow panel groups under phases A–C — chat and panel stay 1-to-1.
            <div className="hint">Plan items are phase-level across every scenario — step detail lives in the panel.</div>
          </>
        ),
      },
      {
        target: '[data-tour="plan-checklist"]', placement: 'bottom',
        icon: '⏱️',
        title: 'Edit before run · 10s auto-lock',
        body: (
          <>
            For 10 seconds before execution starts you can drag-reorder, remove, or add plan items. A countdown bar makes the auto-lock time visible.
            <div className="hint">Auto-lock fires a "No response — locking plan automatically" line so the user always knows what happened.</div>
          </>
        ),
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '🛑',
        title: 'Step 3 fails · agent investigates',
        body: (
          <>
            HaplotypeCaller dies inside the <b>variant calling</b> phase on a chromosome-17 contig mismatch. The plan item turns red and expands inline with the reason plus <b>Retry</b>, <b>Skip</b>, and <b>Ask DeepAgent</b> actions.
            <div className="hint">The <b>AGENT</b> speaker investigates the cause and proposes a fix in the chat alongside.</div>
          </>
        ),
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        icon: '🔁',
        title: 'Auto-loop · LOOP speaker',
        body: (
          <>
            BioMate retries with the patched reference (hg38-noalt). Every line under the <b>LOOP</b> speaker is an auto-loop decision — separate from the rest of the audit trail.
            <div className="hint">The Variant calling tutorial is the simplest of the three R-series; the auto-loop pattern reappears in R02 with the comparison card.</div>
          </>
        ),
        cta: 'Done',
      },
    ],
  },

  // ── 09a — nfcore normal run ──────────────────────────────────────
  'nfcore-normal': {
    label: '09a — nfcore normal run',
    group: 'nf-core',
    scenario: 'nfcore',
    steps: [
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        title: 'Parameters auto-filled',
        body: <>Parameters auto-filled from your message. Review, then click <b>Confirm & Run</b>.</>,
        setup: () => ({ scenario: 'nfcore', runState: 'idle', qcHalt: false, blocked: false, licenseGate: false, disambig: false }),
      },
      {
        target: '[data-tour="plan-checklist"]', placement: 'bottom',
        title: 'Chat narrates in parallel',
        body: <>While the panel tracks the technical pipeline, the chat side shows the plan checklist and speaker-pilled progress lines — same run, two views.</>,
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'Live progress bar',
        body: <>Steps completed / total. Phase A is running <b>fastp QC</b>.</>,
        setup: () => ({ runState: 'running' }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Phase hierarchy',
        body: <>Phases group related steps. Only the active phase expands — the rest show a status chip.</>,
        setup: () => ({ runState: 'running' }),
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        title: 'Run complete',
        body: <><b>View Results</b>, <b>Download All</b>, and <b>Report</b> are now active.</>,
        setup: () => ({ runState: 'completed' }),
        cta: 'Done',
      },
    ],
  },

  // ── 09b — nfcore QC autoloop ─────────────────────────────────────
  'nfcore-qcloop': {
    label: '09b — nfcore QC autoloop',
    group: 'nf-core',
    scenario: 'nfcore',
    steps: [
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'QC step active',
        body: <>Phase B running — <b>fastp QC</b> step active. A <code>q30_pct</code> threshold is being evaluated.</>,
        setup: () => ({ scenario: 'nfcore', runState: 'running', qcHalt: false, blocked: false, licenseGate: false }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'QC gate tripped',
        body: <><code>q30_pct</code> below threshold. BioMate proposes adjusted parameters automatically.</>,
        setup: () => ({ qcHalt: true, runState: 'running' }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Accept or dismiss',
        body: <>Accept to rerun Phase B with corrected params, or dismiss to proceed anyway.</>,
        setup: () => ({ qcHalt: true }),
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'Auto-loop closed',
        body: <>QC passed on retry. Auto-loop closed after 1 iteration.</>,
        setup: () => ({ qcHalt: false, runState: 'completed' }),
        cta: 'Done',
      },
    ],
  },

  // ── 09c — blocking errors ────────────────────────────────────────
  'nfcore-blocked': {
    label: '09c — blocking errors',
    group: 'nf-core',
    scenario: 'nfcore',
    steps: [
      {
        target: '[data-tour="panel-body"]', placement: 'left',
        title: 'Two blockers found',
        body: <>A missing <b>license</b> and an unfilled <b>required parameter</b>. Run is disabled.</>,
        setup: () => ({ scenario: 'nfcore', runState: 'idle', blocked: true, licenseGate: true, qcHalt: false }),
      },
      {
        target: '[data-tour="panel-body"]', placement: 'left',
        title: 'License configured',
        body: <>One blocker remains — the required parameter still needs a value.</>,
        setup: () => ({ licenseGate: true, blocked: false }),
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        title: 'All clear',
        body: <>Run button is now active — no blockers pending.</>,
        setup: () => ({ blocked: false, licenseGate: false, runState: 'idle' }),
        cta: 'Done',
      },
    ],
  },

  // ── 09d — CryoSPARC SPA (extended ~3 min walkthrough, cartoon style) ─
  // ── 09d — CryoSPARC SPA · 3-minute deep dive ────────────────────
  'cryosparc-main': {
    label: '09d — CryoSPARC SPA · 3-minute deep dive',
    group: 'CryoSPARC',
    scenario: 'cryosparc',
    cartoon: true,
    steps: [
      {
        target: null, placement: 'center',
        icon: '👋',
        title: "Hi! Let's run cryo-EM together",
        body: (
          <>
            A complete <b>CryoSPARC single-particle analysis</b> — raw movies to a sharpened 3D map.
            <div className="hint">No CryoSPARC experience needed; BioMate handles the parameters.</div>
          </>
        ),
        setup: () => { if (window.__tourManual) window.__tourManual(true); if (window.__tourReset) window.__tourReset(); if (window.__wfPin) window.__wfPin({ idle: true }); return { scenario: 'cryosparc', runState: 'idle', qcHalt: false, blocked: false, licenseGate: false, watcherAttached: true }; },
      },
      {
        target: '[data-tour="plan-checklist"]', placement: 'bottom',
        icon: '💬',
        title: 'Two views, one run',
        body: (
          <>
            <b>Left</b> — chat narrates progress. <b>Right</b> — the workflow panel shows phases, steps, parameters, outputs. They stay in sync.
          </>
        ),
        setup: () => { if (window.__tourFFTo) window.__tourFFTo('cryo_plan'); if (window.__wfPin) window.__wfPin({ idle: true }); return { runState: 'idle' }; },
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        icon: '🧭',
        title: 'Run header',
        body: (
          <>
            Workflow name, status badge, live progress bar. Status is <b>idle</b> — loaded but not started.
          </>
        ),
        setup: () => { if (window.__wfPin) window.__wfPin({ idle: true }); return { runState: 'idle' }; },
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '🧱',
        title: '5 phases, 23 steps total',
        body: (
          <>
            CryoSPARC SPA is grouped into <b>5 phases</b>. Each phase contains several steps:
            <ul style={{margin:'6px 0 0 14px', padding:0, lineHeight:1.55}}>
              <li><b>A.</b> Movie preprocessing (motion + CTF)</li>
              <li><b>B.</b> Particle picking</li>
              <li><b>C.</b> 2D classification</li>
              <li><b>D.</b> 3D reconstruction</li>
              <li><b>E.</b> Sharpening &amp; validation</li>
            </ul>
            <div className="hint">Only the active phase auto-expands — the rest collapse to a chip so the panel stays scannable.</div>
          </>
        ),
        setup: () => { if (window.__wfPin) window.__wfPin({ idle: true }); return { runState: 'idle' }; },
      },
      {
        target: '[data-tour="phase-list"] .phase.open', placement: 'left',
        icon: '🔍',
        title: "What's inside Phase A?",
        body: (
          <>
            The active phase is <b>auto-expanded</b> so you can see its steps. Phase A runs <b>MotionCor2</b> (frame alignment) and <b>CTFFIND4</b> (defocus estimation).
            <div className="hint">Click any other phase header to peek inside without disturbing the run.</div>
          </>
        ),
        setup: () => { if (window.__wfPin) window.__wfPin({ idle: true }); return { runState: 'idle' }; },
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        icon: '🎯',
        title: 'Confirm & Run',
        body: (
          <>
            Parameters were pre-filled from your chat message. <b>Confirm and run workflow</b> submits to AWS Batch.
            <div className="hint">The footer always shows exactly <b>one</b> primary button — never a wall of choices.</div>
          </>
        ),
        setup: () => {
          if (window.__wfPin) window.__wfPin({ idle: true });
          const __el = document.querySelector('[data-tour="run-footer"]');
          if (__el) __el.scrollIntoView({ behavior: 'smooth', block: 'end' });
          return { runState: 'idle' };
        }
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        icon: '🚀',
        title: "We're off! Phase A is running",
        body: (
          <>
            The status badge has flipped to <b>running</b> and the progress bar is moving. Phase A motion correction is in progress on Batch GPUs.
            <div className="hint">Typical Phase A runtime: <b>3–6 min</b> for a small dataset, longer for thousands of movies.</div>
          </>
        ),
        setup: () => { if (window.__tourFFTo) window.__tourFFTo('cryo_a_run'); if (window.__wfPin) window.__wfPin({ running: 'A', runningStepIdx: 0 }); return { runState: 'running', qcHalt: false }; },
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '📈',
        title: 'Live progress per step',
        body: (
          <>
            Inside Phase A, each step shows a <b>live status chip</b>: <code>queued</code>, <code>running</code>, <code>completed</code>, or <code>failed</code>. As MotionCor2 finishes a movie, the count ticks up.
            <div className="hint">Step chips update via the same SSE stream the chat reads — both views stay in sync.</div>
          </>
        ),
        setup: () => { if (window.__wfPin) window.__wfPin({ running: 'A', runningStepIdx: 2 }); return { runState: 'running' }; },
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '🛡️',
        title: 'QC gate tripped',
        body: (
          <>
            <b>CTF fit resolution</b> below threshold mid-CTF — likely a too-narrow defocus search range. BioMate halts before producing a low-quality map.
          </>
        ),
        setup: () => { if (window.__tourFFTo) window.__tourFFTo('cryo_a_done'); if (window.__wfPin) window.__wfPin({ running: 'A', runningStepIdx: 4 }); return { qcHalt: true, runState: 'running' }; },
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '🛠️',
        title: 'Halt card — accept, edit, or dismiss',
        body: (
          <>
            BioMate suggests <b>defocus 0.5–4.0 µm</b> (was 1.0–3.0). <b>Accept</b> the suggestion, <b>Edit</b> the values, or <b>Dismiss</b>.
            <div className="hint">Toggle auto-loop on and BioMate applies fixes without asking, capped at 3 retries.</div>
          </>
        ),
        setup: () => { if (window.__wfPin) window.__wfPin({ running: 'A', runningStepIdx: 4 }); return { qcHalt: true, runState: 'running' }; },
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '✅',
        title: 'Gate cleared — Phase A done',
        body: (
          <>
            Phase A reruns CTF with the new range, gate passes, Phase B kicks off automatically. Every accept/edit/retry is logged for the QC audit.
          </>
        ),
        setup: () => { if (window.__tourFFTo) window.__tourFFTo('cryo_b_run'); if (window.__wfPin) window.__wfPin({ done: ['A'], running: 'B', runningStepIdx: 0 }); return { qcHalt: false, runState: 'running' }; },
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '📎',
        title: 'Step outputs appear inline',
        body: (
          <>
            As soon as a step finishes, its output files show up as chips on the step row — <b>view</b> and <b>download</b>, no waiting for the whole run.
          </>
        ),
        setup: () => { if (window.__wfPin) window.__wfPin({ done: ['A'], running: 'B', runningStepIdx: 1 }); return { runState: 'running' }; },
      },
      {
        target: '.preview-modal', placement: 'left',
        icon: '🖼️',
        title: 'Click view → inline preview',
        body: (
          <>
            MotionCor2's <code>aligned_sums/</code> renders right here — 12 motion-corrected micrographs from the 842 in the run.
            <div className="hint">BioMate picks the right viewer per file type: tables, plots, 2D classes, 3D maps.</div>
          </>
        ),
        setup: () => {
          if (window.__openTourModal) {
            window.__openTourModal('preview', {
              file: { name: 'aligned_sums/', type: 'folder', viz: 'micrographs' },
            });
          }
          return null;
        },
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '⏩',
        title: 'Phases B → E run through',
        body: (
          <>
            <b>Pick</b> → <b>2D classify</b> → <b>3D refine</b> → <b>sharpen + validate</b>. Each phase passes its outputs to the next; the panel auto-expands whatever's running.
          </>
        ),
        setup: () => {
          if (window.__closeTourModal) window.__closeTourModal();
          if (window.__wfPin) window.__wfPin({ done: ['A','B','C'], running: 'D', runningStepIdx: 1 });
          if (window.__tourFFTo) window.__tourFFTo('cryo_de_run');
          const __el = document.querySelector('[data-tour="phase-list"]');
          if (__el) __el.scrollIntoView({ behavior: 'smooth', block: 'center' });
          return { runState: 'running' };
        }
      },
      // Watcher tour step removed — detach/reconnect feature is commented
      // out in the panel for this release. Restore alongside the watcher row.
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        icon: '🎉',
        title: 'All 23 steps complete',
        body: (
          <>
            Status flipped to <b>completed</b>. Raw movies → sharpened 3D map. Reconstruction converged at <b>3.1 Å</b> by GSFSC 0.143 — publication-quality.
          </>
        ),
        setup: () => {
          if (window.__wfPin) window.__wfPin({ complete: true });
          if (window.__tourFFTo) window.__tourFFTo('cryo_done');
          const __el = document.querySelector('[data-tour="panel-header"]');
          if (__el) __el.scrollIntoView({ behavior: 'smooth', block: 'start' });
          return { runState: 'completed', qcHalt: false };
        },
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        icon: '⬇️',
        title: 'Outputs are downloadable',
        body: (
          <>
            Primary button is now <b>Run again</b>. Scroll up for <b>View Results</b>, <b>Download All</b>, and the auto-generated <b>Findings</b>.
            <div className="hint">The <b>Outputs, Findings &amp; Reports</b> tutorial covers each post-run surface.</div>
          </>
        ),
        setup: () => {
          const __el = document.querySelector('[data-tour="run-footer"]');
          if (__el) __el.scrollIntoView({ behavior: 'smooth', block: 'end' });
          return null;
        }
      },
      {
        target: '[data-tour="after-run"]', placement: 'left',
        icon: '📦',
        title: 'After run section unlocked',
        body: (
          <>
            Every completed run drops an <b>After run</b> block at the bottom of the panel — outputs and a one-click <b>Report</b> (findings, methods, citations).
          </>
        ),
        setup: () => {
          const __el = document.querySelector('[data-tour="after-run-header"]');
          if (__el) __el.scrollIntoView({ behavior: 'smooth', block: 'start' });
          return null;
        }
      },
      {
        target: null, placement: 'center',
        icon: '🌟',
        title: "That's a full cryo-EM run",
        body: (
          <>
            Raw movies → sharpened 3D map in 23 steps. Real runs take 30–90 min; this tutorial fast-forwarded the cloud time so you'd see every milestone.
            <div className="hint"><kbd>Esc</kbd> to close, or open the next tutorial from the <b>Tutorial</b> button up top.</div>
          </>
        ),
        cta: 'Done',
      },
    ],
  },

  // ── 09f — Outputs, Findings & Reports (cartoon, completed run) ─
  //
  // Single forward narrative:
  //   intro → after-run block → 4 output links (overview + each) →
  //   Findings card (visible TL;DR in the panel) → open Report modal →
  //   walk 6 tabs → open QC modal → walk 4 sections → done.
  //
  // Every step has a short hint for visual consistency in cartoon mode.
  // Tab-switching setups click the target tab so the content always
  // matches the narrative, even if the user steps back/forward.
  'outputs-findings-report': {
    label: '09f — After run · all tabs',
    group: 'CryoSPARC',
    scenario: 'cryosparc',
    cartoon: true,
    steps: [
      {
        target: null, placement: 'center',
        icon: '📊',
        title: "Let's tour the After run report",
        body: (
          <>
            Your run just finished. The <b>After run</b> block at the bottom of the panel has 7 tabs covering everything BioMate produced. We'll walk each tab in order — content switches automatically.
            <div className="hint">Click <kbd>→</kbd> to step forward, <kbd>Esc</kbd> to exit at any time.</div>
          </>
        ),
        setup: () => ({ scenario: 'cryosparc', runState: 'completed', qcHalt: false, blocked: false, licenseGate: false }),
      },
      {
        target: '[data-tour="after-run-header"]', placement: 'left',
        icon: '📦',
        title: 'After run · header + Download',
        body: (
          <>
            Every completed run leaves an <b>After run</b> section. The <b>Download report</b> link on the right bundles every tab below into one structured DOCX / Markdown / LaTeX document.
            <div className="hint">One-click manuscript-ready export — no need to open each tab.</div>
          </>
        ),
        setup: () => {
          // Scroll the panel down so the After-run section is in view
          const el = document.querySelector('[data-tour="after-run-header"]');
          if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
          return null;
        },
      },
      {
        target: '[data-tour="results-links"]', placement: 'left',
        icon: '🗂️',
        title: '7 tabs · the whole story',
        body: (
          <>
            <b>Findings · Outputs · Methods · Parameters · Software · Citations · QC audit</b>. We'll switch through each tab in order — the tab content below follows automatically.
            <div className="hint">Order matches the natural read order: narrative first, raw artifacts next, then methods + reproducibility, ending with audit.</div>
          </>
        ),
      },
      {
        target: '[data-tour="after-run-body"]', placement: 'left',
        icon: '✨',
        title: 'Findings · the headline',
        body: (
          <>
            Headline metric (<b>3.21 Å resolution</b>), 2–3 bullets capturing what to look at, and a numeric table — runtime, particles, resolution. Every number is read from the run manifest, not generated.
            <div className="hint">If a finding has no citation, BioMate tags it <i>"author judgment"</i>.</div>
          </>
        ),
        setup: () => {
          const btn = document.querySelector('[data-tour="link-report"]');
          if (btn) btn.click();
          return null;
        },
      },
      {
        target: '[data-tour="after-run-body"]', placement: 'left',
        icon: '📁',
        title: 'Outputs · every file produced',
        body: (
          <>
            One row per file, grouped by phase and step, with <b>view</b> for inline preview and <b>download</b> for the single file. <b>Download all</b> grabs the full bundle.
            <div className="hint">Click <b>view</b> on any row and BioMate picks the right viewer for that file type.</div>
          </>
        ),
        setup: () => {
          const btn = document.querySelector('[data-tour="link-view-results"]');
          if (btn) btn.click();
          return null;
        },
      },
      {
        target: '.preview-modal', placement: 'left',
        icon: '🌀',
        title: 'CTF diagnostic · Thon rings',
        body: (
          <>
            Click view on <code>ctf_diagnostic.png</code> — Thon-ring power spectrum from Gctf. Visual confirmation that the CTF fit is sane before reconstruction.
          </>
        ),
        setup: () => {
          if (window.__openTourModal) {
            window.__openTourModal('preview', {
              file: { name: 'ctf_diagnostic.png', type: 'image', viz: 'thon_rings' },
            });
          }
          return null;
        },
      },
      {
        target: '.preview-modal', placement: 'left',
        icon: '🗂️',
        title: '2D classes · cleaned',
        body: (
          <>
            <code>2d_classes_round2.mrcs</code> — clean 2D averages after junk classes are dropped. Each tile is a class showing a distinct view of the particle.
          </>
        ),
        setup: () => {
          if (window.__openTourModal) {
            window.__openTourModal('preview', {
              file: { name: '2d_classes_round2.mrcs', type: 'image', viz: 'class2d_clean' },
            });
          }
          return null;
        },
      },
      {
        target: '.preview-modal', placement: 'left',
        icon: '🧬',
        title: '3D half-map',
        body: (
          <>
            <code>half_map_A.mrc</code> — isosurface of the unsharpened reconstruction. The matching half-map B is what feeds the gold-standard FSC.
          </>
        ),
        setup: () => {
          if (window.__openTourModal) {
            window.__openTourModal('preview', {
              file: { name: 'half_map_A.mrc', type: 'image', viz: 'volume_iso' },
            });
          }
          return null;
        },
      },
      {
        target: '.preview-modal', placement: 'left',
        icon: '📈',
        title: 'Gold-standard FSC',
        body: (
          <>
            <code>gsfsc.csv</code> — FSC curve from the two half-maps. The 0.143 cutoff lands at <b>3.21 Å</b> — that's the headline resolution.
          </>
        ),
        setup: () => {
          if (window.__openTourModal) {
            window.__openTourModal('preview', {
              file: { name: 'gsfsc.csv', type: 'table', viz: 'fsc_curve' },
            });
          }
          return null;
        },
      },
      {
        target: '.preview-modal', placement: 'left',
        icon: '🪞',
        title: 'Sharpened map · ship-ready',
        body: (
          <>
            <code>sharpened_map.mrc</code> — B-factor sharpened final map. This is what gets deposited at EMDB.
          </>
        ),
        setup: () => {
          if (window.__openTourModal) {
            window.__openTourModal('preview', {
              file: { name: 'sharpened_map.mrc', type: 'image', viz: 'volume_sharp' },
            });
          }
          return null;
        },
      },
      {
        target: '[data-tour="after-run-body"]', placement: 'left',
        icon: '📝',
        title: 'Methods · paste-ready IMRaD',
        body: (
          <>
            Paragraph-form Methods you can drop into a manuscript. Tool names, versions, exact parameters — written so peers can replicate the run.
            <div className="hint">Italics at the bottom flag values that were inferred vs. read from the manifest.</div>
          </>
        ),
        setup: () => {
          if (window.__closeTourModal) window.__closeTourModal();
          // After the preview-modal step we're back in the panel — scroll
          // down again so the After-run body is in view for the tab walk.
          const el = document.querySelector('[data-tour="after-run-header"]');
          if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
          const btn = document.querySelector('[data-tour="after-tab-imrad"]');
          if (btn) btn.click();
          return null;
        },
      },
      {
        target: '[data-tour="after-run-body"]', placement: 'left',
        icon: '🧮',
        title: 'Parameters · every knob',
        body: (
          <>
            Phase · step · parameter · value. Every parameter the run touched, in one table. Hand this to reviewers as a supplementary file.
            <div className="hint">Defaults are flagged separately from user overrides and auto-loop adjustments.</div>
          </>
        ),
        setup: () => {
          const btn = document.querySelector('[data-tour="after-tab-params"]');
          if (btn) btn.click();
          return null;
        },
      },
      {
        target: '[data-tour="after-run-body"]', placement: 'left',
        icon: '🧰',
        title: 'Software · pinned versions',
        body: (
          <>
            Every tool that touched the run with its exact version — orchestrator, container runtime, scientific packages. Match these and you'll get the same outputs.
            <div className="hint">Used together with Parameters, this is the reproducibility baseline.</div>
          </>
        ),
        setup: () => {
          const btn = document.querySelector('[data-tour="after-tab-software"]');
          if (btn) btn.click();
          return null;
        },
      },
      {
        target: '[data-tour="after-run-body"]', placement: 'left',
        icon: '📚',
        title: 'Citations · pre-formatted refs',
        body: (
          <>
            Auto-generated reference list for the tools and methods cited in the Methods prose. Click any PMID to open PubMed in a new tab.
            <div className="hint">Citations + Methods come pre-bundled in the Download report DOCX/MD/LaTeX export.</div>
          </>
        ),
        setup: () => {
          const btn = document.querySelector('[data-tour="after-tab-cite"]');
          if (btn) btn.click();
          return null;
        },
      },
      {
        target: '[data-tour="after-run-body"]', placement: 'left',
        icon: '🛡️',
        title: 'QC audit · compliance lens',
        body: (
          <>
            Every QC gate that fired, with timestamp, threshold, observed value, result, and action. <b>21 CFR Part 11</b> friendly — chain-of-custody and operator e-signature included.
            <div className="hint">Manual interventions = 0 means the run was fully automated and auditable.</div>
          </>
        ),
        setup: () => {
          const btn = document.querySelector('[data-tour="link-qc"]');
          if (btn) btn.click();
          return null;
        },
      },
      {
        target: null, placement: 'center',
        icon: '🌟',
        title: "That's the After run report",
        body: (
          <>
            Every tab is generated from the same run manifest. The <b>Download report</b> link at the top wraps all 7 tabs into one structured document — DOCX for Word, Markdown for Notion / GitHub, LaTeX for journal templates.
            <div className="hint">Tip: share the run URL with a collaborator — they get the same panel, read-only.</div>
          </>
        ),
        setup: () => {
          // Reset to Findings so the user lands back on the default tab
          const btn = document.querySelector('[data-tour="link-report"]');
          if (btn) btn.click();
          return null;
        },
        cta: 'Done',
      },
    ],
  },
  // ── 09e — disambiguation ─────────────────────────────────────────
  'nfcore-disambig': {
    label: '09e — disambiguation',
    group: 'nf-core',
    scenario: 'nfcore',
    steps: [
      {
        target: '[data-tour="chat-handoff"]', placement: 'right',
        title: 'Two matching pipelines',
        body: <>Your query matched two pipelines. BioMate shows candidates rather than guessing.</>,
        setup: () => ({ scenario: 'nfcore', disambig: true, runState: 'idle' }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Selected pipeline loaded',
        body: <>The correct workflow is now loaded with parameters pre-filled.</>,
        setup: () => ({ disambig: false, runState: 'idle' }),
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'Running with confidence',
        body: <>Disambiguating before launch prevents wasted Batch compute on the wrong pipeline.</>,
        setup: () => ({ runState: 'running' }),
        cta: 'Done',
      },
    ],
  },

  // ── A01 — nfcore idle ────────────────────────────────────────────
  'nfcore-idle': {
    label: 'A01 — nfcore idle',
    group: 'nf-core',
    scenario: 'nfcore',
    steps: [
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'Idle state',
        body: <>BioMate parsed your message and pre-filled the parameters.</>,
        setup: () => ({ scenario: 'nfcore', runState: 'idle', qcHalt: false, blocked: false, licenseGate: false, disambig: false }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Preview phases',
        body: <>Phases are previewed before launch. Expand any phase to review steps and <b>QC gates</b>.</>,
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        title: 'One primary action',
        body: <><b>Confirm & Run</b> sends the job to AWS Batch.</>,
        cta: 'Done',
      },
    ],
  },

  // ── A04 — nfcore failed ──────────────────────────────────────────
  'nfcore-failed': {
    label: 'A04 — nfcore failed',
    group: 'nf-core',
    scenario: 'nfcore',
    steps: [
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'Run failed',
        body: <>The status badge turns red and the panel shows what went wrong.</>,
        setup: () => ({ scenario: 'nfcore', runState: 'failed', qcHalt: false, blocked: false, licenseGate: false }),
      },
      {
        target: '[data-tour="panel-body"]', placement: 'left',
        title: 'Failed step highlighted',
        body: <>Error message, exit code, and log tail — inline with the step.</>,
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        title: 'Run again, or diagnose',
        body: <><b>Run Again</b> re-submits with the same parameters. Or ask BioMate in chat to diagnose first.</>,
        cta: 'Done',
      },
    ],
  },

  // ── A08 — nfcore watcher (removed) ───────────────────────────────
  //   The watcher detach/reconnect feature is commented out in the panel
  //   for this release. The demo is removed alongside it. Restore both
  //   together when SSE work lands.

  // ── B01 — GATK idle ──────────────────────────────────────────────
  'gatk-idle': {
    label: 'B01 — GATK idle',
    group: 'GATK',
    scenario: 'gatk',
    steps: [
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'WGS Germline GATK4',
        body: <>3 phases: <b>FASTQ Download</b>, <b>Alignment & QC</b>, <b>Variant Calling</b>.</>,
        setup: () => ({ scenario: 'gatk', runState: 'idle', qcHalt: false, blocked: false, licenseGate: false }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Phase breakdown',
        body: <>Phase A stages reads from <b>SRA</b>. Phase B aligns with <b>BWA-MEM2</b>. Phase C calls variants with <b>GATK HaplotypeCaller</b>.</>,
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        title: 'Ready to run',
        body: <><b>hg38</b> reference and SRA accession pre-filled. Confirm & Run submits to AWS Batch.</>,
        cta: 'Done',
      },
    ],
  },

  // ── B02 — GATK running ───────────────────────────────────────────
  'gatk-running': {
    label: 'B02 — GATK running',
    group: 'GATK',
    scenario: 'gatk',
    steps: [
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'GATK WGS running',
        body: <>Phase A downloading reads from SRA via <code>fasterq-dump</code>.</>,
        setup: () => ({ scenario: 'gatk', runState: 'running', qcHalt: false, blocked: false, licenseGate: false }),
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        title: 'Chat surfaces · speaker pills',
        body: <>The chat narrates the same run with pills for <b>PLAN</b>, <b>WF</b>, and <b>QC</b> speakers — you can see what each subsystem is doing at a glance.</>,
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Phase B queued',
        body: <><b>BWA-MEM2</b>, <b>MarkDuplicates</b>, <b>BQSR</b> waiting for Phase A output.</>,
      },
      // SSE-stream watcher step removed (watcher feature is commented
      // out in the panel for this release).
    ],
  },

  // ── B03 — GATK completed ─────────────────────────────────────────
  'gatk-completed': {
    label: 'B03 — GATK completed',
    group: 'GATK',
    scenario: 'gatk',
    steps: [
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'All 3 phases done',
        body: <><b>VCF</b>, <b>BAM</b>, <b>QC reports</b>, and <b>SnpEff annotations</b> are ready.</>,
        setup: () => ({ scenario: 'gatk', runState: 'completed', qcHalt: false, blocked: false, licenseGate: false }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Per-phase outputs',
        body: <>Each phase shows Done. Click any to see step outputs — <b>coverage stats</b>, <b>Ti/Tv ratio</b>, <b>variant counts</b>.</>,
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        title: 'Download & Report',
        body: <><b>Download All</b> packages every output as a ZIP. <b>Report</b> auto-generates findings, outputs, and a publication-ready Methods section.</>,
        cta: 'Done',
      },
    ],
  },

  // ── C01 — ADMET ──────────────────────────────────────────────────
  'admet-main': {
    label: 'C01 — ADMET',
    group: 'ADMET',
    scenario: 'admet',
    steps: [
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Single-step workflow',
        body: <>ADMET Property Prediction. SMILES was parsed directly from your query.</>,
        setup: () => ({ scenario: 'admet', runState: 'idle', qcHalt: false, blocked: false, licenseGate: false }),
      },
      {
        target: '[data-tour="chat-stream"]', placement: 'right',
        title: 'No plan checklist · single task',
        body: <>For single-step workflows the plan checklist stays hidden — the chat-side <b>WF</b> and <b>FIND</b> speakers narrate the run directly.</>,
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'ADMET-AI computing',
        body: <>Absorption, <b>hERG cardiotoxicity</b>, CYP inhibition, hepatotoxicity, and <b>Lipinski Ro5</b>.</>,
        setup: () => ({ runState: 'running' }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Safety threshold tripped',
        body: <><b>hERG IC50</b> below safety threshold. BioMate proposes a structural modification to reduce cardiotoxicity.</>,
        setup: () => ({ qcHalt: true, runState: 'running' }),
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        title: 'Endpoints computed',
        body: <>Download CSV or open the <b>Report</b> for a drug-property narrative + findings table.</>,
        setup: () => ({ qcHalt: false, runState: 'completed' }),
        cta: 'Done',
      },
    ],
  },
};

// Build groups for the picker
const DEMO_GROUPS = (() => {
  const by = {};
  for (const [id, tour] of Object.entries(DEMO_TOURS)) {
    (by[tour.group] ||= []).push({ id, label: tour.label });
  }
  return by;
})();

// ── Rendering primitives ──────────────────────────────────────────

const WFSpotlight = ({ rect, padding = 8, cartoon }) => {
  // No backdrop dimming — we just highlight the target with a glowing ring
  // so the rest of the page stays fully visible.
  if (!rect) return null;
  const r = cartoon ? 14 : 8;
  const x = rect.left - padding;
  const y = rect.top - padding;
  const w = rect.width + padding * 2;
  const h = rect.height + padding * 2;
  if (cartoon) {
    return (
      <svg className="tour-overlay" aria-hidden="true">
        {/* Soft outer glow */}
        <rect x={x - 6} y={y - 6} width={w + 12} height={h + 12} rx={r + 6} ry={r + 6}
          fill="none" stroke="oklch(0.78 0.10 250 / 0.35)" strokeWidth="10" className="tour-ring-glow"/>
        {/* Dashed accent ring */}
        <rect x={x} y={y} width={w} height={h} rx={r} ry={r}
          fill="none" stroke="oklch(0.55 0.18 250)" strokeWidth="2.5"
          strokeDasharray="6 5" className="tour-ring-dash"/>
      </svg>
    );
  }
  return (
    <svg className="tour-overlay" aria-hidden="true">
      <rect x={x} y={y} width={w} height={h} rx={r} ry={r}
        fill="none" stroke="rgba(99, 140, 255, 0.9)" strokeWidth="2" className="tour-ring"/>
    </svg>
  );
};

const WFTour = ({ steps, step, total, onNext, onPrev, onSkip, targetRect, placement, demoLabel, cartoon }) => {
  const calloutRef = React.useRef(null);
  const [calloutH, setCalloutH] = React.useState(180);

  // Auto-advance — when the current step declares `autoAdvance: ms`, fire
  // onNext after that delay. Each step controls its own pacing so the
  // tour can match the scenario's natural rhythm without the user clicking.
  // Use a ref for onNext so re-renders don't reschedule overlapping timeouts.
  const onNextRef = React.useRef(onNext);
  React.useEffect(() => { onNextRef.current = onNext; }, [onNext]);
  React.useEffect(() => {
    const s = steps[step];
    if (!s || !s.autoAdvance) return;
    if (step >= total - 1) return;
    const t = setTimeout(() => onNextRef.current(), s.autoAdvance);
    return () => clearTimeout(t);
  }, [step, total]);
  React.useLayoutEffect(() => {
    if (calloutRef.current) setCalloutH(calloutRef.current.offsetHeight);
  }, [step, targetRect]);

  const CW = placement === 'center' ? 420 : 360;
  const CH = calloutH;
  const OFFSET = 14;
  const MARGIN = 16;
  const vw = typeof window !== 'undefined' ? window.innerWidth : 1200;
  const vh = typeof window !== 'undefined' ? window.innerHeight : 800;

  let calloutStyle = {};
  let effectivePlacement = placement;

  if (placement === 'center' || !targetRect) {
    calloutStyle = { left: '50%', top: '50%', transform: 'translate(-50%, -50%)' };
  } else {
    const spaceBelow = vh - targetRect.bottom;
    const spaceAbove = targetRect.top;
    const spaceLeft = targetRect.left;
    const spaceRight = vw - targetRect.right;
    const needed = CH + OFFSET + MARGIN;

    if (placement === 'bottom' && spaceBelow < needed && spaceAbove > needed) effectivePlacement = 'top';
    else if (placement === 'top' && spaceAbove < needed && spaceBelow > needed) effectivePlacement = 'bottom';
    else if (placement === 'left' && spaceLeft < CW + OFFSET + MARGIN && spaceRight > CW + OFFSET + MARGIN) effectivePlacement = 'right';
    else if (placement === 'right' && spaceRight < CW + OFFSET + MARGIN && spaceLeft > CW + OFFSET + MARGIN) effectivePlacement = 'left';

    const cx = targetRect.left + targetRect.width / 2;
    let left, top;
    if (effectivePlacement === 'bottom') { left = cx - CW / 2; top = targetRect.bottom + OFFSET; }
    else if (effectivePlacement === 'top') { left = cx - CW / 2; top = targetRect.top - OFFSET - CH; }
    else if (effectivePlacement === 'left') { left = targetRect.left - OFFSET - CW; top = targetRect.top + targetRect.height / 2 - CH / 2; }
    else if (effectivePlacement === 'right') { left = targetRect.right + OFFSET; top = targetRect.top + targetRect.height / 2 - CH / 2; }

    left = Math.max(MARGIN, Math.min(vw - CW - MARGIN, left));
    top = Math.max(MARGIN, Math.min(vh - CH - MARGIN, top));
    calloutStyle = { left, top };
  }

  const isFirst = step === 0;
  const isLast = step === total - 1;
  const currentStep = steps[step];
  // Defensive: if the step index ever desyncs past the array (e.g. a stale
  // auto-advance fires mid-transition), bail instead of crashing the app.
  if (!currentStep) return null;

  return (
    <>
      <WFSpotlight rect={targetRect} cartoon={cartoon}/>
      <div
        ref={calloutRef}
        className={`tour-callout ${placement === 'center' ? 'center' : ''} ${cartoon ? 'cartoon' : ''}`}
        style={calloutStyle}
      >
        {cartoon && currentStep.icon && (
          <div className="tour-icon" aria-hidden="true">{currentStep.icon}</div>
        )}
        <div className="tour-meta">
          <span className="tour-step-n">{demoLabel} · Step {step + 1}/{total}</span>
          <button className="tour-skip" onClick={onSkip} aria-label="Skip tutorial">Skip ×</button>
        </div>
        <div className="tour-title">{currentStep.title}</div>
        <div className="tour-body">{currentStep.body}</div>
        <div className="tour-foot">
          <div className="tour-dots">
            {steps.map((_, i) => (
              <span key={i} className={`tour-dot ${i === step ? 'active' : i < step ? 'done' : ''}`}/>
            ))}
          </div>
          <div className="tour-actions">
            {!isFirst && <button className="btn sm ghost" onClick={onPrev}>← Back</button>}
            <button className="btn sm primary" onClick={onNext}>
              {isLast ? (currentStep.cta || 'Done') : 'Next →'}
            </button>
          </div>
        </div>
      </div>
    </>
  );
};

// Picker shown when the Tutorial button is clicked — lists all demos grouped.
const TourPicker = ({ currentScenario, onPick, onClose }) => {
  // Put current-scenario group first
  const scenarioGroup = {
    nfcore: 'nf-core', gatk: 'GATK', cryosparc: 'CryoSPARC', admet: 'ADMET',
    rnaseq: 'Bulk RNA-seq', drugscreen: 'Drug screen', variant: 'Variant calling',
    bioc_kb: 'Bioconductor', bioc_sc: 'Bioconductor', bioc_methyl: 'Bioconductor',
  }[currentScenario];
  const groupOrder = ['General', scenarioGroup,
    'Bioconductor', 'Bulk RNA-seq', 'Drug screen', 'Variant calling',
    'nf-core', 'GATK', 'CryoSPARC', 'ADMET']
    .filter((g, i, a) => g && a.indexOf(g) === i);

  return (
    <div className="tour-picker-backdrop" onClick={onClose}>
      <div className="tour-picker" onClick={e => e.stopPropagation()}>
        <div className="tour-picker-head">
          <div>
            <div className="tour-picker-title">Tutorial demos</div>
            <div className="tour-picker-sub">Pick a scenario to record a focused walkthrough</div>
          </div>
          <button className="tour-skip" onClick={onClose}>×</button>
        </div>
        <div className="tour-picker-body">
          {groupOrder.map(group => {
            const items = DEMO_GROUPS[group] || [];
            if (!items.length) return null;
            return (
              <div className="tour-picker-group" key={group}>
                <div className="tour-picker-group-label">{group}</div>
                {items.map(item => (
                  <button
                    key={item.id}
                    className="tour-picker-item"
                    onClick={() => onPick(item.id)}
                  >
                    <span className="tour-picker-item-label">{item.label}</span>
                    <span className="tour-picker-item-go">Start →</span>
                  </button>
                ))}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};

const clipRectWF = (r, vh) => {
  const top = Math.max(8, r.top);
  const bottom = Math.min(vh - 8, r.bottom);
  return {
    left: r.left, right: r.right, width: r.width,
    top, bottom, height: Math.max(40, bottom - top),
  };
};

const useWFTour = (tweaks, setTweak) => {
  const [demoId, setDemoId] = React.useState(null);     // null = not running
  const [picking, setPicking] = React.useState(false);  // picker open?
  const [step, setStep] = React.useState(0);
  const [rect, setRect] = React.useState(null);

  const active = demoId !== null;
  const steps = active ? DEMO_TOURS[demoId].steps : [];
  const total = steps.length;
  const currentStep = active ? steps[step] : null;

  const measure = React.useCallback(() => {
    if (!active) return;
    const s = steps[step];
    if (!s || !s.target) { setRect(null); return; }
    // Use the LAST match — for selectors like `.reason-block` this lands the
    // spotlight on the newest block (what the step narrates) rather than the
    // first, and keeps the highlight scoped tightly instead of wrapping a
    // whole tall container.
    // Use the last VISIBLE match — for selectors like `.reason-block` this
    // lands the spotlight on the newest block, and it skips hidden/zero-size
    // duplicates (e.g. a display:none header) that would put the ring in a
    // corner.
    const all = [...document.querySelectorAll(s.target)];
    const vis = all.filter(e => { const rr = e.getBoundingClientRect(); return rr.width > 1 && rr.height > 1; });
    const el = vis.length ? vis[vis.length - 1] : null;
    if (!el) { setRect(null); return; }
    // Keep the spotlighted element on-screen (instant, only if needed) so the
    // ring wraps visible content rather than a viewport-clipped empty band.
    try {
      const rr = el.getBoundingClientRect();
      const vh0 = window.innerHeight;
      if (rr.top < 8 || rr.bottom > vh0 - 8) el.scrollIntoView({ block: 'center' });
    } catch (e) {}
    const r = el.getBoundingClientRect();
    const vh = window.innerHeight;
    setRect(clipRectWF(r, vh));
  }, [active, step, demoId]);

  // Apply setup, then measure
  React.useEffect(() => {
    if (!active) return;
    const s = steps[step];
    if (s && s.setup) {
      const updates = s.setup(tweaks);
      if (updates) setTweak(updates);
    }
    let id1 = requestAnimationFrame(() => {
      id1 = requestAnimationFrame(() => measure());
    });
    const t = setTimeout(measure, 320);
    return () => { cancelAnimationFrame(id1); clearTimeout(t); };
    // eslint-disable-next-line
  }, [active, step, demoId]);

  React.useEffect(() => {
    if (!active) return;
    const onR = () => measure();
    window.addEventListener('resize', onR);
    window.addEventListener('scroll', onR, true);
    return () => {
      window.removeEventListener('resize', onR);
      window.removeEventListener('scroll', onR, true);
    };
  }, [active, measure]);

  React.useEffect(() => {
    if (!active) return;
    const onKey = (e) => {
      if (e.key === 'Escape') stop();
      else if (e.key === 'ArrowRight' || e.key === 'Enter') next();
      else if (e.key === 'ArrowLeft') prev();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line
  }, [active, step, demoId]);

  const openPicker = () => setPicking(true);
  const closePicker = () => setPicking(false);
  const startDemo = (id) => {
    if (window.__wfUnpin) window.__wfUnpin();
    const demo = DEMO_TOURS[id];
    const manual = !!(demo && demo.manualStream);
    // FF-driven demos drive the chat stream themselves (each step jumps the
    // engine to a marker). Put the engine in manual mode so the tape doesn't
    // also auto-play and race the fast-forward, and pre-switch the scenario the
    // moment the demo is picked — a full render BEFORE any step's setup() runs
    // its fast-forward. Without this, the first FF step can fire against the
    // previous scenario's tape and silently no-op (frozen panel / empty chat).
    // Non-manual demos keep their original behavior (switch in their own
    // step-1 setup) to avoid regressing the v1 / cryosparc tours.
    if (window.__tourManual) window.__tourManual(manual);
    if (manual && demo.scenario && window.__tourSetScenario) window.__tourSetScenario(demo.scenario);
    setPicking(false);
    setStep(0);
    setDemoId(id);
  };
  // start() is a convenience: if a specific demo is inferred from current scenario/state, use that; else open picker
  const start = () => {
    // Default: open the picker so user can choose which demo to record
    openPicker();
  };
  const stop = () => {
    if (window.__wfUnpin) window.__wfUnpin(); // release any tour pin on exit
    if (window.__tourManual) window.__tourManual(false); // resume normal stream auto-play
    setDemoId(null);
    setPicking(false);
  };
  const next = () => {
    setStep(s => {
      if (s >= total - 1) { Promise.resolve().then(stop); return s; }
      return s + 1;
    });
  };
  const prev = () => setStep(s => Math.max(0, s - 1));

  const node = (
    <>
      {picking && (
        <TourPicker
          currentScenario={tweaks.scenario}
          onPick={startDemo}
          onClose={closePicker}
        />
      )}
      {active && (
        <WFTour
          steps={steps}
          step={step}
          total={total}
          onNext={next}
          onPrev={prev}
          onSkip={stop}
          targetRect={rect}
          placement={currentStep?.placement || 'bottom'}
          demoLabel={DEMO_TOURS[demoId].label}
          cartoon={DEMO_TOURS[demoId].cartoon}
        />
      )}
    </>
  );

  return { active, start, stop, node };
};

window.useWFTour = useWFTour;
window.DEMO_TOURS = DEMO_TOURS;
