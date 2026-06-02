// IND Report tour — separate from the CRO compliance tour.
// Uses the same useTour hook + Tour component infrastructure (from cro/Tour.jsx),
// but with its own ordered step list aware of IND surfaces.
//
// Step shape mirrors cro/Tour.jsx:
//   { id, target: '[data-tour="..."]' | null, title, body, placement, setup, cta }

const IND_TOUR_STEPS = [
  {
    id: 'welcome',
    target: null,
    placement: 'center',
    title: 'Welcome — BioMate IND Report',
    body: (
      <>
        Take a quick tour of the IND Report product. We'll walk through the 5-step
        pipeline, the live document viewer, the sign-and-freeze flow, and the
        regulatory audit.
        <div className="hint">Use <kbd>→</kbd>/<kbd>←</kbd> to step, <kbd>Esc</kbd> to skip.</div>
      </>
    ),
    setup: () => ({ stage: 'main' }),
  },
  {
    id: 'projects',
    target: '[data-tour="ind-projects"]',
    placement: 'right',
    title: 'Project list',
    body: <>Each pharma program lives as its own project. Coloured dots = status (green = signed, blue = in progress, amber = blocked). Click to switch — your work is preserved per project.</>,
  },
  {
    id: 'new',
    target: '[data-tour="ind-new-project"]',
    placement: 'right',
    title: 'Start a new IND',
    body: <>Two ways in: click <b>New Project</b> here, or start from the BioMate <b>chat</b> — when you run ADMET there, an "Generate IND" chip appears beneath the results and lands you here with steps 1 + 2 already filled.</>,
  },
  {
    id: 'step1',
    target: '[data-tour="ind-step-1"]',
    placement: 'left',
    title: 'Step 1 — Project Setup',
    body: <>Molecule, target, indication, sponsor, and which <b>regions</b> you're filing in. Each region adds region-specific blocks to the document (NMPA → GLP declaration; PMDA → ethnic bridging).</>,
  },
  {
    id: 'regions',
    target: '[data-tour="ind-regions"]',
    placement: 'top',
    title: 'Multi-region in one pass',
    body: <>FDA · EMA · NMPA · PMDA — toggle any combination. The document panel re-renders region-specific paragraphs inline; the body that applies to all regions stays put.</>,
  },
  {
    id: 'step2',
    target: '[data-tour="ind-step-2"]',
    placement: 'left',
    title: 'Step 2 — ADMET screening',
    body: <>Runs the BioMate <span className="mono">predict_admet_properties</span> workflow on AWS Batch. 41 endpoints across hERG, DILI, Ames, PPBR, Caco-2, BBB, CYPs, P-gp. Feeds §2.6.1.3 and §2.6.4.</>,
  },
  {
    id: 'admet-table',
    target: '[data-tour="ind-admet-table"]',
    placement: 'left',
    title: 'Per-compound triage',
    body: <>Click <b>View ADMET table</b>. Column headers tooltip to the guideline citation (hERG: Redfern 2003 / ICH S7B, &lt; 10 µM = liability). Green ✓ / amber ~ / red ✗.</>,
  },
  {
    id: 'wetlab',
    target: '[data-tour="ind-wetlab"]',
    placement: 'left',
    title: 'Bring in wet-lab data',
    body: <>Upload an NTP GLP report PDF or an FDA NDA review — BioMate auto-extracts measured values which take precedence over predictions. Computational-only sections become <b>Full</b> coverage.</>,
  },
  {
    id: 'step3',
    target: '[data-tour="ind-step-3"]',
    placement: 'left',
    title: 'Step 3 — PBPK qualification',
    body: <>Qualify the PBPK model against a 30-drug reference set per EMA/CHMP/EWP/37498/2011. Cmax + AUC within 2-fold for ≥67% is the regulatory gate.</>,
  },
  {
    id: 'pbpk-criterion',
    target: '[data-tour="ind-pbpk-criterion"]',
    placement: 'right',
    title: 'EMA criterion — the gateway',
    body: <>The most important badge in the whole pipeline. If this fails, downstream IND assembly is blocked until re-qualification. Click <b>Re-run with new params</b> to try clearance/Vd updates.</>,
  },
  {
    id: 'step4',
    target: '[data-tour="ind-step-4"]',
    placement: 'left',
    title: 'Step 4 — Lead selection',
    body: <>Gaussian Process · EHVI acquisition · Morgan fingerprints. Ranks all 12 candidates on a 5-axis surrogate (hERG, DILI, Ames, potency, AD).</>,
  },
  {
    id: 'leads-table',
    target: '[data-tour="ind-leads-table"]',
    placement: 'left',
    title: 'Read the ranking',
    body: <>Filled circles = potency (●●●●○ = strong). <b>OOD</b> = out of applicability domain — still ranked, but flagged in §2.6.1.5 with a limitation statement.</>,
  },
  {
    id: 'step5',
    target: '[data-tour="ind-step-5"]',
    placement: 'left',
    title: 'Step 5 — IND document',
    body: <>Assembled when steps 1–4 complete. §2.6.1.1 through §2.6.6 generated and ready for review. The right panel shows the live document.</>,
  },
  {
    id: 'coverage',
    target: '[data-tour="ind-coverage"]',
    placement: 'right',
    title: 'Section coverage',
    body: <>● Full (computational + measured ready for submission) · ◑ Partial (computational only — flagged for wet-lab enrichment) · ○ Not generated. <b>§2.6.5 and §2.6.6 need GLP data</b> to upgrade.</>,
  },
  {
    id: 'doc-panel',
    target: '[data-tour="ind-doc-panel"]',
    placement: 'left',
    title: 'Live document viewer',
    body: <>The document is always visible on the right. As each pipeline step completes, the corresponding section is populated in place — no page reload.</>,
  },
  {
    id: 'doc-tabs',
    target: '[data-tour="ind-doc-tabs"]',
    placement: 'bottom',
    title: 'Jump to any section',
    body: <>Click §2.6.1, §2.6.2, … to scroll. The dot next to each tab shows coverage at a glance: green = Full, amber = Partial.</>,
  },
  {
    id: 'doc-region',
    target: '[data-tour="ind-doc-region"]',
    placement: 'bottom',
    title: 'Per-region view',
    body: <>Switch the rendered region — NMPA adds the GLP declaration; PMDA adds the ethnic bridging assumption table. All-regions combined is what gets shipped.</>,
  },
  {
    id: 'feedback-edit',
    target: '[data-tour="ind-doc-panel"]',
    placement: 'left',
    title: 'Edit any paragraph',
    body: <>Every paragraph is editable. When you change one, a small "✎ edited — saved for model improvement" note appears. Your edit silently becomes a training pair (chosen=yours, rejected=ours). This is how BioMate's regulatory model gets better with every customer.</>,
  },
  {
    id: 'cite-add',
    target: '[data-tour="ind-doc-panel"]',
    placement: 'left',
    title: 'Suggest a citation',
    body: <>Click the <b>+</b> icon at the end of any paragraph to suggest a missing guideline. Especially useful for NMPA / CDE technical guidelines we haven't indexed. Approved suggestions roll into the corpus.</>,
  },
  {
    id: 'audit',
    target: '[data-tour="ind-audit-summary"]',
    placement: 'top',
    title: 'Regulatory audit',
    body: <><b>0 CRITICAL · 0 MAJOR · 2 MINOR · 4 INFO</b> here means the document is signable. CRITICAL blocks signing; MAJOR shows an amber warning but lets you proceed (regulatory scientist's judgment).</>,
  },
  {
    id: 'audit-overlay',
    target: '[data-tour="ind-audit-overlay"]',
    placement: 'left',
    title: 'Each finding has a recommendation',
    body: <>Click any finding to see what triggered it and how to fix it. <b>Dismiss</b> a finding (e.g. "not applicable to this topical product") and pick a reason — that reason refines the checker rule for everyone, automatically.</>,
    setup: () => ({ auditOpen: true }),
  },
  {
    id: 'sign',
    target: '[data-tour="ind-sign-btn"]',
    placement: 'top',
    title: 'Sign & freeze',
    body: <>21 CFR Part 11 §11.200. Reviewer credentials are recorded in the frozen document. A 6-digit TOTP and the meaning-of-signature are permanent.</>,
    setup: () => ({ auditOpen: false }),
  },
  {
    id: 'versions',
    target: '[data-tour="ind-version-chip"]',
    placement: 'bottom',
    title: 'Versions are immutable',
    body: <>Signed versions are frozen by SHA-256. Creating v3 supersedes v2 but the v2 signature record is preserved in the audit trail forever.</>,
  },
  {
    id: 'reference',
    target: null,
    placement: 'center',
    title: "That's the tour!",
    body: (
      <>
        <b>Three things worth trying</b> while recording:
        <ul style={{paddingLeft: 18, margin: '8px 0 0', lineHeight: 1.55, fontSize: 13}}>
          <li>Click <b>Sign & Freeze</b> at the bottom of step 5 to walk through the full TOTP overlay.</li>
          <li>Edit any paragraph in the document panel and watch the "✎ edited" hint appear.</li>
          <li>Open <b>Dismiss</b> on any minor finding and pick a reason — that closes the feedback loop.</li>
        </ul>
      </>
    ),
    cta: 'Start recording',
  },
];

// Tour hook — reuses cro/Tour.jsx's primitives. Just register our steps via TOUR_STEPS.
// Since cro/Tour.jsx already binds window.TOUR_STEPS, we ship a hook that overrides it.
const useIndTour = (knobs, setKnobs) => {
  // Use the same useTour hook from cro/Tour.jsx but swap the step list in place.
  // To avoid touching cro/Tour.jsx, we expose a wrapper that temporarily replaces
  // window.TOUR_STEPS with the IND-specific steps before calling start().
  const baseTour = window.useTour(knobs, setKnobs);
  const start = () => {
    window.__SAVED_TOUR_STEPS = window.TOUR_STEPS;
    window.TOUR_STEPS = IND_TOUR_STEPS;
    baseTour.start();
  };
  const stop = () => {
    baseTour.stop();
    if (window.__SAVED_TOUR_STEPS) {
      window.TOUR_STEPS = window.__SAVED_TOUR_STEPS;
      delete window.__SAVED_TOUR_STEPS;
    }
  };
  return { ...baseTour, start, stop };
};

window.IND_TOUR_STEPS = IND_TOUR_STEPS;
window.useIndTour = useIndTour;
