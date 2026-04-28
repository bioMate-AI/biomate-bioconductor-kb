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
      {
        target: '[data-tour="watcher"]', placement: 'top',
        title: 'Detach without losing the run',
        body: <>Long runs move to cloud batch. You can <b>detach the watcher</b> — the job keeps going — then reconnect later.</>,
      },
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
        body: <><b>View Results</b>, <b>AI Analysis</b>, and <b>Download All</b> are now active.</>,
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
  'cryosparc-main': {
    label: '09d — CryoSPARC SPA · full walkthrough',
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
            We'll go through a complete <b>CryoSPARC single-particle analysis</b> from raw movies all the way to a sharpened 3D map.
            <div className="hint">Raw movies → 3D map, start to finish, zero config required.</div>
          </>
        ),
        setup: () => ({ scenario: 'cryosparc', runState: 'idle', qcHalt: false, blocked: false, licenseGate: false, watcherAttached: true }),
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        icon: '🧭',
        title: 'This is the run header',
        body: (
          <>
            The header is your <b>command-center</b>. Workflow name, status badge, and the live progress bar.
            <div className="hint">The progress bar stays visible even while the panel is collapsed.</div>
          </>
        ),
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
            <div className="hint">Each phase runs on independent Batch workers — B starts the moment A finishes.</div>
          </>
        ),
      },
      {
        target: '[data-tour="phase-list"] .phase.open', placement: 'left',
        icon: '🔍',
        title: "What's inside Phase A?",
        body: (
          <>
            The active phase is <b>auto-expanded</b> so you can see its steps. Phase A runs <b>MotionCor2</b> (frame alignment) and <b>CTFFIND4</b> (defocus estimation).
            <div className="hint">MotionCor2 alone typically accounts for 60 % of total Phase A runtime.</div>
          </>
        ),
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        icon: '🎯',
        title: 'One primary action — Confirm & Run',
        body: (
          <>
            Parameters were pre-filled by BioMate from your chat message. When you're ready, the <b>Confirm and run workflow</b> button submits the job to AWS Batch.
            <div className="hint">You can still edit any pre-filled param before clicking Confirm — nothing is locked.</div>
          </>
        ),
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        icon: '🚀',
        title: "We're off! Phase A is running",
        body: (
          <>
            The status badge has flipped to <b>running</b> and the progress bar is moving. Phase A motion correction is in progress on Batch GPUs.
            <div className="hint">BioMate auto-selects GPU instance type based on movie count — you never size the cluster.</div>
          </>
        ),
        setup: () => ({ runState: 'running', qcHalt: false }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '📈',
        title: 'Live progress per step',
        body: (
          <>
            Inside Phase A, each step shows a <b>live status chip</b>: <code>queued</code>, <code>running</code>, <code>completed</code>, or <code>failed</code>. As MotionCor2 finishes a movie, the count ticks up.
            <div className="hint">Click any step row to expand its raw log output inline.</div>
          </>
        ),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '🛡️',
        title: 'CTF fit quality gate just tripped',
        body: (
          <>
            Halfway through CTF estimation, BioMate noticed the <b>CTF fit resolution</b> is below threshold — likely too narrow a defocus search range.
            <div className="hint">Gates fire mid-phase — you don't wait until the whole run finishes to hear bad news.</div>
          </>
        ),
        setup: () => ({ qcHalt: true, runState: 'running' }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '🔄',
        title: 'Auto-loop: try again with better parameters',
        body: (
          <>
            BioMate proposes <b>defocus range 0.5–4.0 µm</b> (was 1.0–3.0). You can <b>Accept</b> to rerun Phase A with the new params, or <b>Dismiss</b> to proceed anyway.
            <div className="hint">Hit Dismiss to skip the fix and continue — the choice is always yours.</div>
          </>
        ),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '✅',
        title: 'Gate cleared — Phase A done',
        body: (
          <>
            Retry succeeded. CTF fit resolution now meets threshold. Phase A is marked <b>completed</b> and Phase B kicks off automatically.
            <div className="hint">The fixed defocus range is saved to the run record — no manual note needed.</div>
          </>
        ),
        setup: () => ({ qcHalt: false, runState: 'running' }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '🎯',
        title: 'Phase B: particle picking',
        body: (
          <>
            <b>Topaz</b> (a neural-network picker) scans every micrograph for particles. The output is a coordinate file per micrograph — these become the input particles for 2D classification.
            <div className="hint">Topaz outperforms template matching on flexible or heterogeneous samples.</div>
          </>
        ),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '🗂️',
        title: 'Phase C: 2D classification',
        body: (
          <>
            Particles are sorted into 2D classes. <b>Junk classes</b> (ice, carbon edges, aggregates) are dropped; only well-defined views advance to 3D.
            <div className="hint">Keeping 30–60 % of particles after 2D clean-up is normal, not a data loss.</div>
          </>
        ),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '🧬',
        title: 'Phase D: 3D reconstruction',
        body: (
          <>
            Cleaned particles go into <b>ab-initio reconstruction</b> followed by <b>homogeneous refinement</b>. The output is an unsharpened 3D density map and a half-map pair for resolution estimation.
            <div className="hint">Ab-initio requires no reference — it cannot inherit model bias from a prior structure.</div>
          </>
        ),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '🪞',
        title: 'Phase E: sharpening & validation',
        body: (
          <>
            Final phase: <b>B-factor sharpening</b>, <b>FSC resolution estimation</b> from the half-maps, and <b>local resolution</b> mapping. The result is the publication-ready map you'll deposit at EMDB.
            <div className="hint">Local resolution coloring reveals flexible loops — useful before building an atomic model.</div>
          </>
        ),
      },
      {
        target: '[data-tour="watcher"]', placement: 'top',
        icon: '📡',
        title: 'You can detach the watcher anytime',
        body: (
          <>
            The watcher is a <b>live SSE stream</b> from AWS Batch. Close the panel, take a coffee break, restart your laptop — the job keeps going on the cloud and reattaches when you reopen the panel.
            <div className="hint">Reattach takes under one second — no events are missed while disconnected.</div>
          </>
        ),
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        icon: '🎉',
        title: 'All 23 steps complete!',
        body: (
          <>
            Status flipped to <b>completed</b>. Your dataset went from raw movies to a sharpened 3D map.
            <div className="hint">3.1 Å is enough to place side chains and build a reliable atomic model.</div>
          </>
        ),
        setup: () => ({ runState: 'completed', qcHalt: false }),
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        icon: '⬇️',
        title: 'Outputs are downloadable now',
        body: (
          <>
            The footer's primary button has changed to <b>Run again</b>. Scroll up to find <b>View Results</b>, <b>Download All</b>, and the auto-generated <b>AI Findings</b>.
            <div className="hint">Download All bundles every output into one zip — handy for EMDB deposition.</div>
          </>
        ),
      },
      {
        target: '[data-tour="after-run"]', placement: 'left',
        icon: '📦',
        title: 'After-run section unlocked',
        body: (
          <>
            Every completed run drops a fresh <b>After run</b> block at the bottom of the panel — links to outputs, an AI summary, and a one-click Methods Report.
            <div className="hint">The Methods Report drafts your Materials &amp; Methods section — paste-ready for a journal submission.</div>
          </>
        ),
      },
      {
        target: null, placement: 'center',
        icon: '🌟',
        title: "That's a full cryo-EM run!",
        body: (
          <>
            You just watched <b>raw movies → sharpened 3D map</b> in 19 steps. Real runs take 30–90 minutes; this tutorial fast-forwarded the cloud time so you could see every milestone.
            <div className="hint">Try <b>Outputs, Findings &amp; Reports</b> next to dive into post-run analysis.</div>
          </>
        ),
        cta: 'Done',
      },
    ],
  },

  // ── 09f — Outputs, Findings & Reports (cartoon, completed run) ─
  'outputs-findings-report': {
    label: '09f — Outputs, Findings & Reports',
    group: 'CryoSPARC',
    scenario: 'cryosparc',
    cartoon: true,
    steps: [
      {
        target: null, placement: 'center',
        icon: '📊',
        title: "Let's look at what BioMate produced",
        body: (
          <>
            Your run just finished. This tutorial walks through every part of the <b>After run</b> section — what each link does, how to read the AI Findings, and what's in the auto-generated Methods Report.
            <div className="hint">All five links and the findings card are generated automatically — you never configure them.</div>
          </>
        ),
        setup: () => ({ scenario: 'cryosparc', runState: 'completed', qcHalt: false, blocked: false, licenseGate: false, watcherAttached: true }),
      },
      {
        target: '[data-tour="after-run"]', placement: 'left',
        icon: '📦',
        title: 'The After-run block',
        body: (
          <>
            At the bottom of the panel, BioMate creates an <b>After run</b> block for every completed workflow. It's split into two parts: the <b>output links</b> (top row) and the <b>AI Findings card</b> (below).
            <div className="hint">The layout separates quick actions (links) from analysis (findings) — doing vs. deciding.</div>
          </>
        ),
      },
      {
        target: '[data-tour="results-links"]', placement: 'top',
        icon: '🔗',
        title: 'Five quick links',
        body: (
          <>
            Each link opens a different view of the same run. They're rendered as <b>plain links</b> on purpose — so the panel stays calm and the cards below get the visual weight.
            <div className="hint">All five reference the same underlying run data — just different angles on it.</div>
          </>
        ),
      },
      {
        target: '[data-tour="link-view-results"]', placement: 'top',
        icon: '👀',
        title: 'View results — the file browser',
        body: (
          <>
            Opens the <b>output explorer</b>. Every file produced by every step, grouped by phase: micrographs, particle stacks, 2D class images, half-maps, the final sharpened map, and the FSC plot.
            <div className="hint">MRC volumes open in a browser-native 3D viewer — no extra software needed.</div>
          </>
        ),
      },
      {
        target: '[data-tour="link-view-results"]', placement: 'top',
        icon: '🗂️',
        title: 'Files are grouped by phase',
        body: (
          <>
            Inside the file browser, outputs are nested under their phase so you never have to search a flat directory. Phase A produces motion-corrected micrographs and CTF thumbnails. Phase B adds coordinate files. Phase C adds 2D class averages. Phase D and E add the density maps and FSC curves.
            <div className="hint">Go straight to Phase E first — sharpened map and FSC curve are what you need.</div>
          </>
        ),
      },
      {
        target: '[data-tour="link-download"]', placement: 'top',
        icon: '⬇️',
        title: 'Download all — the ZIP bundle',
        body: (
          <>
            Packages every output into a single <b>ZIP file</b>: maps, half-maps, sharpening masks, particle stacks, motion-corrected micrographs, FSC curves, and the run manifest (a JSON describing every step's parameters).
            <div className="hint">The manifest JSON inside the ZIP is machine-readable — useful for automated re-analysis pipelines.</div>
          </>
        ),
      },
      {
        target: '[data-tour="link-ai"]', placement: 'top',
        icon: '🧠',
        title: 'AI analysis — interactive narrative',
        body: (
          <>
            Opens a <b>chat-style summary</b> of the run. You can ask follow-up questions: "Why did Phase A retry?", "How does this resolution compare to my last run?", "Should I worry about the particle distribution?"
            <div className="hint">Ask "how does this compare to my last run?" — BioMate can query your run history.</div>
          </>
        ),
      },
      {
        target: '[data-tour="link-methods"]', placement: 'top',
        icon: '📄',
        title: 'Methods report — paste-ready prose',
        body: (
          <>
            Generates a <b>publication-ready Methods section</b> in IMRaD format — software versions, parameters, dataset size, resolution by FSC 0.143, sharpening B-factor — with citations to every tool used.
            <div className="hint">Software versions are pinned to the exact build that ran — not the current installed version.</div>
          </>
        ),
      },
      {
        target: '[data-tour="link-methods"]', placement: 'top',
        icon: '📋',
        title: 'Four tabs inside the report',
        body: (
          <>
            The Methods Report modal has four tabs:
            <ul style={{margin:'6px 0 0 14px', padding:0, lineHeight:1.6}}>
              <li><b>Methods section</b> — IMRaD prose, paste-ready</li>
              <li><b>Parameters</b> — every input value, with the default and any overrides you made</li>
              <li><b>Software</b> — tool names, versions, and their DOIs</li>
              <li><b>Citations</b> — BibTeX-ready references for every tool used</li>
            </ul>
            <div className="hint">The Parameters tab is what peer reviewers actually want — exact values, not prose.</div>
          </>
        ),
      },
      {
        target: '[data-tour="link-qc"]', placement: 'top',
        icon: '🛡️',
        title: 'QC audit log — every gate, every retry',
        body: (
          <>
            A timestamped table of <b>every QC gate</b> that fired during the run: which metric, what threshold, what the value was, whether it passed, and what BioMate did about it. Includes a chain-of-custody block and an e-signature field.
            <div className="hint">Chain-of-custody captures every parameter change across retries — required for GxP submissions.</div>
          </>
        ),
      },
      {
        target: '[data-tour="findings-card"]', placement: 'left',
        icon: '✨',
        title: 'AI Findings card — the TL;DR',
        body: (
          <>
            The <b>AI Findings card</b> is the executive summary. Three sections: a <b>narrative</b> at the top, a <b>metrics table</b> in the middle, and <b>citations</b> at the bottom.
            <div className="hint">Generated once on completion — a new run produces a fresh card.</div>
          </>
        ),
      },
      {
        target: '[data-tour="findings-header"]', placement: 'top',
        icon: '🏷️',
        title: 'Generated, not retrieved',
        body: (
          <>
            The header says <b>"generated from outputs"</b> deliberately — every sentence below is produced by feeding the actual output files into the model, not by pattern-matching against the workflow name.
            <div className="hint">Two runs of the same workflow on different datasets produce different findings.</div>
          </>
        ),
      },
      {
        target: '[data-tour="findings-body"]', placement: 'right',
        icon: '📝',
        title: 'Read the narrative',
        body: (
          <>
            One or two sentences capturing <b>what happened</b> and <b>what to do next</b>. For cryo-EM: resolution, half-map agreement, particle heterogeneity, and any sharpening notes.
            <div className="hint">Gate fires appear in the narrative with a direct link to the relevant QC threshold.</div>
          </>
        ),
      },
      {
        target: '[data-tour="findings-body"]', placement: 'right',
        icon: '🔬',
        title: 'Cryo-EM: the three numbers that matter',
        body: (
          <>
            For a cryo-EM run, the narrative always surfaces:
            <ul style={{margin:'6px 0 0 14px', padding:0, lineHeight:1.6}}>
              <li><b>Resolution</b> — the GSFSC 0.143 number; below 4 Å is publication-ready</li>
              <li><b>Particle yield</b> — fraction surviving 2D classification; below 20% is a red flag</li>
              <li><b>Half-map agreement</b> — divergence means overfitting</li>
            </ul>
            <div className="hint">These map directly to the three most common grounds for reviewer rejection in cryo-EM papers.</div>
          </>
        ),
      },
      {
        target: '[data-tour="findings-table"]', placement: 'right',
        icon: '📐',
        title: 'The metrics table — runtime, cost, files',
        body: (
          <>
            Three numbers you'll always want to know:
            <ul style={{margin:'6px 0 0 14px', padding:0, lineHeight:1.55}}>
              <li><b>Runtime</b> — wall-clock time on AWS Batch</li>
              <li><b>Cost estimate</b> — GPU hours × instance rate</li>
              <li><b>Outputs</b> — total file count (everything in the ZIP)</li>
            </ul>
            <div className="hint">Cost is estimated — actual AWS billing may differ if spot instances were interrupted mid-step.</div>
          </>
        ),
      },
      {
        target: '[data-tour="findings-cite"]', placement: 'right',
        icon: '📚',
        title: 'Citations — what the AI relied on',
        body: (
          <>
            Every claim in the narrative is grounded in either an <b>internal benchmark</b> or a <b>peer-reviewed paper</b>. Click a PMID to open PubMed. Uncited findings are marked <i>"author judgment"</i> — never hidden.
            <div className="hint">These are the same references you need for your Methods section — no double-lookup.</div>
          </>
        ),
      },
      {
        target: '[data-tour="findings-card"]', placement: 'left',
        icon: '🆚',
        title: 'Findings vs. Methods — different audiences',
        body: (
          <>
            <b>Findings</b> are for you — opinionated, short, interpretive. <b>Methods</b> are for your reviewer — exhaustive, passive-voice, factual.
            <br/><br/>
            One tells you what the result means. The other proves how it was obtained.
            <div className="hint">Findings interpret. Methods record. Never paste Findings into a manuscript.</div>
          </>
        ),
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        icon: '🔁',
        title: 'Want to rerun?',
        body: (
          <>
            The primary button is now <b>Run again</b> — re-submits the same workflow. To change parameters first, expand the <b>Workflow settings</b> strip above the After-run block.
            <div className="hint">Change one parameter — only downstream steps re-execute, not the whole pipeline.</div>
          </>
        ),
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        icon: '🔗',
        title: 'Share this run with anyone',
        body: (
          <>
            Every completed run has a <b>permanent URL</b>. Send it to a collaborator, PI, or CRO partner. They see the full panel — findings, methods, QC audit — in <b>read-only mode</b>.
            <div className="hint">No account needed to view — the link is self-contained.</div>
          </>
        ),
      },
      {
        target: null, placement: 'center',
        icon: '🌟',
        title: "You're done!",
        body: (
          <>
            That's the full <b>output → findings → report</b> story. Every BioMate run produces exactly this surface — whether it's cryo-EM, GATK WGS, ADMET, or a custom nf-core pipeline.
            <div className="hint">Try the GATK or ADMET tutorials next — same After-run structure, different findings.</div>
          </>
        ),
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

  // ── A08 — nfcore watcher ─────────────────────────────────────────
  'nfcore-watcher': {
    label: 'A08 — nfcore watcher',
    group: 'nf-core',
    scenario: 'nfcore',
    steps: [
      {
        target: '[data-tour="watcher"]', placement: 'top',
        title: 'Watcher attached',
        body: <>Live SSE connection. Every Nextflow event streams directly here.</>,
        setup: () => ({ scenario: 'nfcore', runState: 'running', watcherAttached: true, qcHalt: false, blocked: false }),
      },
      {
        target: '[data-tour="watcher"]', placement: 'top',
        title: 'Detach without stopping',
        body: <>Close the panel without stopping the run. Job continues on AWS Batch.</>,
        setup: () => ({ watcherAttached: false }),
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        title: 'Reopen any time',
        body: <>Reopen from the chat message badge. Panel rehydrates live from current run state.</>,
        setup: () => ({ watcherAttached: true }),
        cta: 'Done',
      },
    ],
  },

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
        target: '[data-tour="phase-list"]', placement: 'left',
        title: 'Phase B queued',
        body: <><b>BWA-MEM2</b>, <b>MarkDuplicates</b>, <b>BQSR</b> waiting for Phase A output.</>,
      },
      {
        target: '[data-tour="watcher"]', placement: 'top',
        title: 'SSE stream open',
        body: <>GATK WGS typically takes <b>45–90 min</b> depending on coverage.</>,
        cta: 'Done',
      },
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
        title: 'Download & Methods Report',
        body: <><b>Download All</b> packages every output as a ZIP. <b>Methods Report</b> auto-generates a publication-ready Methods section.</>,
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
        body: <>Download CSV or open <b>AI Analysis</b> for a drug property narrative.</>,
        setup: () => ({ qcHalt: false, runState: 'completed' }),
        cta: 'Done',
      },
    ],
  },

  // ── 00 — Website Quickstart (first-time visitor orientation, cartoon) ─
  'website-quickstart': {
    label: '00 — Workflow Panel · first-time orientation',
    group: 'General',
    scenario: 'cryosparc',
    cartoon: true,
    steps: [
      {
        target: null, placement: 'center',
        icon: '🧬',
        title: 'Welcome to BioMate',
        body: (
          <>
            BioMate is a <b>conversational bioinformatics platform</b>. You describe your experiment in plain English — BioMate picks the right pipeline, fills in the parameters, runs it on cloud infrastructure, and hands back publication-ready results.
            <div className="hint">No Nextflow. No AWS setup. No pipeline configuration. Just science.</div>
          </>
        ),
        setup: () => ({
          scenario: 'cryosparc', runState: 'idle', qcHalt: false,
          blocked: false, licenseGate: false, disambig: false,
          watcherAttached: true, sidebarMode: 'auto',
        }),
      },
      {
        target: '[data-tour="chat-handoff"]', placement: 'right',
        icon: '💬',
        title: 'Ask in plain English',
        body: (
          <>
            Type your experiment the same way you'd explain it to a colleague: <i>"Run cryo-EM single-particle analysis on my MRC movies — pixel size 1.06 Å, 300 kV."</i>
            <div className="hint">BioMate understands domain vocabulary — you don't need to know the pipeline name or parameter flags.</div>
          </>
        ),
      },
      {
        target: '[data-tour="chat-handoff"]', placement: 'right',
        icon: '🗂️',
        title: 'BioMate proposes a workflow',
        body: (
          <>
            A <b>workflow card</b> appears directly in the chat — pipeline name, domain, and a one-line description. If BioMate isn't sure which pipeline you meant, it shows candidates and lets you choose.
            <div className="hint">The card is a preview. Nothing runs until you confirm.</div>
          </>
        ),
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        icon: '🧭',
        title: 'The Workflow Panel opens',
        body: (
          <>
            Clicking the card opens the <b>Workflow Panel</b> on the right. At the top: pipeline name, scientific domain, and a live status badge.
            <div className="hint">The panel stays open alongside the chat — run, explore outputs, and keep the conversation going simultaneously.</div>
          </>
        ),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '⚙️',
        title: 'Parameters are pre-filled',
        body: (
          <>
            BioMate extracts values from your message — pixel size, voltage, file paths — and maps them to pipeline parameters automatically. Phases are laid out so you see what will run before anything starts.
            <div className="hint">Every parameter has an <b>Edit</b> button if you want to override a value before launching.</div>
          </>
        ),
      },
      {
        target: '[data-tour="run-footer"]', placement: 'top',
        icon: '🚀',
        title: 'Confirm & Run — one button',
        body: (
          <>
            Click <b>Confirm and run workflow</b>. The job is submitted to AWS Batch — GPU or CPU instances, right-sized for your pipeline automatically.
            <div className="hint">The footer always shows exactly one primary action — no wall of options, no mode-switching.</div>
          </>
        ),
        setup: () => ({ runState: 'idle' }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '📡',
        title: 'Live progress in real time',
        body: (
          <>
            Phase cards update live via a streaming connection to AWS Batch. Each flips <code>pending</code> → <code>running</code> → <code>completed</code> as work progresses.
            <div className="hint">Close the browser and come back — the job keeps running and the panel rehydrates to current state when you reopen it.</div>
          </>
        ),
        setup: () => ({ runState: 'running', qcHalt: false }),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '🛡️',
        title: 'QC gates catch problems automatically',
        body: (
          <>
            BioMate monitors quality metrics as the pipeline runs. If a metric falls outside its threshold, a <b>QC gate</b> fires and BioMate proposes a fix.
            <div className="hint">You accept or dismiss — BioMate never makes parameter changes without showing you first.</div>
          </>
        ),
        setup: () => ({ qcHalt: true, runState: 'running' }),
      },
      {
        target: '[data-tour="panel-header"]', placement: 'left',
        icon: '🎉',
        title: 'Run completes',
        body: (
          <>
            When all phases finish, the status badge flips to <b>completed</b> and an <b>After run</b> section appears — links to outputs, a methods report, and the AI Findings card.
          </>
        ),
        setup: () => ({ runState: 'completed', qcHalt: false }),
      },
      {
        target: '[data-tour="findings-card"]', placement: 'left',
        icon: '✨',
        title: 'AI Findings — the executive summary',
        body: (
          <>
            BioMate reads the actual output files and writes an <b>AI Findings card</b> — a short narrative of what happened, the key metrics, and what to do next.
            <div className="hint">Generated from your actual outputs — different dataset, different findings.</div>
          </>
        ),
      },
      {
        target: '[data-tour="link-methods"]', placement: 'top',
        icon: '📄',
        title: 'Methods Report — publication-ready',
        body: (
          <>
            One click generates a <b>Methods section in IMRaD format</b> — exact software versions, all parameters, dataset statistics, and citations to every tool. Export as DOCX, Markdown, or LaTeX.
            <div className="hint">No copy-paste from logs — built from the run record, same parameters that actually ran.</div>
          </>
        ),
      },
      {
        target: null, placement: 'center',
        icon: '🌟',
        title: "You're ready to go deeper",
        body: (
          <>
            That's the full BioMate loop: <b>ask → review → run → results</b>. From a plain-English prompt to a publication-ready output in one session.
            <br/><br/>
            When you're ready:
            <ul style={{margin:'6px 0 0 14px', padding:0, lineHeight:1.6}}>
              <li><b>CryoSPARC SPA walkthrough</b> — every phase, step by step</li>
              <li><b>Outputs, Findings &amp; Reports</b> — deep-dive on the After-run section</li>
            </ul>
            <div className="hint">Use the <b>Tutorial</b> button at the top to pick any demo.</div>
          </>
        ),
        cta: 'Get started',
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
  const scenarioGroup = { nfcore: 'nf-core', gatk: 'GATK', cryosparc: 'CryoSPARC', admet: 'ADMET' }[currentScenario];
  const groupOrder = ['General', scenarioGroup, 'nf-core', 'GATK', 'CryoSPARC', 'ADMET'].filter((g, i, a) => g && a.indexOf(g) === i);

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
    const el = document.querySelector(s.target);
    if (!el) { setRect(null); return; }
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
    setDemoId(null);
    setPicking(false);
  };
  const next = () => {
    if (step >= total - 1) stop();
    else setStep(s => s + 1);
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
