  // ── 00 — Website Quickstart (first-time visitor orientation, cartoon) ─
  'website-quickstart': {
    label: '00 — Website Quickstart · first-time visitor',
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
            <div className="hint">BioMate understands domain vocabulary. You don't need to know the pipeline name or parameter flags.</div>
          </>
        ),
      },
      {
        target: '[data-tour="chat-handoff"]', placement: 'right',
        icon: '🗂️',
        title: 'BioMate proposes a workflow',
        body: (
          <>
            A <b>workflow card</b> appears directly in the chat — with the pipeline name, domain, and a one-line description. If BioMate isn't sure which pipeline you meant, it shows candidates and lets you choose.
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
            Clicking the card opens the <b>Workflow Panel</b> on the right. At the top you'll see the pipeline name, its scientific domain, and a live status badge.
            <div className="hint">The panel stays open alongside the chat — run, explore outputs, and keep the conversation going at the same time.</div>
          </>
        ),
      },
      {
        target: '[data-tour="phase-list"]', placement: 'left',
        icon: '⚙️',
        title: 'Parameters are pre-filled',
        body: (
          <>
            BioMate extracts values from your message — pixel size, voltage, file paths — and maps them to the right pipeline parameters automatically. Phases are laid out so you can see what will run before anything starts.
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
            When you're satisfied with the parameters, click <b>Confirm and run workflow</b>. The job is submitted to AWS Batch — GPU or CPU instances, right-sized for your pipeline automatically.
            <div className="hint">The footer always shows exactly one primary action. No wall of options, no mode-switching.</div>
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
            As soon as the job starts, phase cards update live via a streaming connection to AWS Batch. Each card flips from <code>pending</code> → <code>running</code> → <code>completed</code> as work progresses.
            <div className="hint">You can close the browser and come back — the job keeps running and the panel rehydrates to the current state when you reopen it.</div>
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
            BioMate monitors quality metrics as the pipeline runs. If a metric falls outside its threshold — CTF fit resolution, particle yield, hERG cardiotoxicity, Q30 percentage — a <b>QC gate</b> fires and BioMate proposes a fix.
            <div className="hint">You can accept the auto-suggested parameter adjustment, or dismiss the gate and proceed. BioMate never makes changes without showing you first.</div>
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
            When all phases finish, the status badge flips to <b>completed</b> and an <b>After run</b> section appears at the bottom of the panel — links to outputs, a methods report, and the AI Findings card.
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
            BioMate reads the actual output files and writes an <b>AI Findings card</b> — a short narrative summarising what happened, the key metrics, and what to do next. For cryo-EM that means resolution, particle yield, and half-map agreement.
            <div className="hint">Generated from your actual outputs — not a template. Different dataset, different findings.</div>
          </>
        ),
      },
      {
        target: '[data-tour="link-methods"]', placement: 'top',
        icon: '📄',
        title: 'Methods Report — publication-ready',
        body: (
          <>
            One click generates a <b>Methods section in IMRaD format</b> — exact software versions, all parameters used, dataset statistics, and citations to every tool. Export as DOCX, Markdown, or LaTeX.
            <div className="hint">No copy-paste from logs. The report is built from the run record — the same parameters that actually ran.</div>
          </>
        ),
      },
      {
        target: null, placement: 'center',
        icon: '🌟',
        title: "You're ready to go deeper",
        body: (
          <>
            That's the full BioMate loop: <b>ask → review → run → get results</b>. From a plain-English prompt to a publication-ready map and methods section.
            <br/><br/>
            When you're ready to go deeper:
            <ul style={{margin: '6px 0 0 14px', padding: 0, lineHeight: 1.6}}>
              <li><b>CryoSPARC SPA walkthrough</b> — every phase explained, step by step</li>
              <li><b>Outputs, Findings &amp; Reports</b> — deep-dive on the After-run section</li>
            </ul>
            <div className="hint">Use the <b>Tutorial</b> button at the top to pick any demo.</div>
          </>
        ),
        cta: 'Get started',
      },
    ],
  },
