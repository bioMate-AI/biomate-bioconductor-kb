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
    title: 'Filing an IND, end-to-end',
    body: (
      <>
        Before a new drug enters human trials, the sponsor files an <b>Investigational New Drug (IND)</b> application — and the bulk of it is <b>eCTD Module 2.6</b>: nonclinical pharmacology &amp; toxicology written summaries.
        <div style={{marginTop:8}}>BioMate assembles that module from your screening data — ADMET predictions, PBPK qualification, lead selection — drafts §2.6.1 through §2.6.6, and walks it through sign-and-freeze for <b>FDA · EMA · NMPA · PMDA</b>.</div>
        <div className="hint">5-step pipeline on the left · live document on the right · <kbd>→</kbd> to start.</div>
      </>
    ),
    setup: () => ({ stage: 'main' }),
  },
  {
    id: 'layout',
    target: null,
    placement: 'center',
    title: 'Two panels, same project',
    body: (
      <>
        <b>Left</b> — the 5-step pipeline you'll drive. <b>Right</b> — the IND document, regenerated in place as each step completes. Tour drives both.
      </>
    ),
  },
  {
    id: 'projects',
    target: '[data-tour="ind-projects"]',
    placement: 'right',
    title: 'Project list',
    body: <>One project per drug program. Status dot: green = signed · blue = in progress · amber = blocked. State persists per project.</>,
  },
  {
    id: 'new',
    target: '[data-tour="ind-new-project"]',
    placement: 'right',
    title: 'Start a new IND',
    body: <>Click <b>New Project</b> here, or run ADMET in BioMate chat and hit the <b>Generate IND</b> chip on the results — steps 1 + 2 land here pre-filled.</>,
  },
  {
    id: 'step1',
    target: '[data-tour="ind-step-1"]',
    placement: 'left',
    title: 'Step 1 — Project Setup',
    body: <>Molecule, target, indication, sponsor, and target <b>regions</b>. Each region adds its own blocks (NMPA → GLP declaration; PMDA → ethnic bridging).</>,
    setup: () => { window.__indOpenStep && window.__indOpenStep('s1'); },
  },
  {
    id: 'regions',
    target: '[data-tour="ind-regions"]',
    placement: 'top',
    title: 'Multi-region in one pass',
    body: <>Toggle any combo of FDA · EMA · NMPA · PMDA. Region-specific paragraphs re-render inline; the common body stays put.</>,
    setup: () => { window.__indOpenStep && window.__indOpenStep('s1'); },
  },
  {
    id: 'step2',
    target: '[data-tour="ind-step-2"]',
    placement: 'left',
    title: 'Step 2 — ADMET screening',
    body: <>Runs <span className="mono">predict_admet_properties</span> on Batch — 41 endpoints (hERG, DILI, Ames, PPBR, Caco-2, BBB, CYPs, P-gp). Feeds §2.6.1.3 and §2.6.4.</>,
    setup: () => { window.__indOpenStep && window.__indOpenStep('s2'); },
  },
  {
    id: 'admet-table',
    target: '[data-tour="ind-admet-table"]',
    placement: 'left',
    title: 'Per-compound triage',
    body: <>Open <b>View ADMET table</b>. Green ✓ / amber ~ / red ✗ per endpoint; column headers tooltip to the guideline citation (hERG → Redfern 2003 / ICH S7B).</>,
    setup: () => { window.__indOpenStep && window.__indOpenStep('s2'); },
  },
  {
    id: 'wetlab',
    target: '[data-tour="ind-wetlab"]',
    placement: 'left',
    title: 'Bring in wet-lab data',
    body: <>Drop in an NTP GLP report or FDA NDA review — measured values override predictions and computational-only sections upgrade to <b>Full</b> coverage.</>,
    setup: () => { window.__indOpenStep && window.__indOpenStep('s2'); },
  },
  {
    id: 'step3',
    target: '[data-tour="ind-step-3"]',
    placement: 'left',
    title: 'Step 3 — PBPK qualification',
    body: <>Qualifies the PBPK model against a 30-drug reference set (EMA/CHMP/EWP/37498/2011). The gate: Cmax + AUC within 2-fold for ≥67% of drugs.</>,
    setup: () => { window.__indOpenStep && window.__indOpenStep('s3'); },
  },
  {
    id: 'pbpk-criterion',
    target: '[data-tour="ind-pbpk-criterion"]',
    placement: 'right',
    title: 'EMA criterion — the gateway',
    body: <>The blocking badge of the pipeline. Fail and IND assembly halts until re-qualification. <b>Re-run with new params</b> to tweak clearance / Vd.</>,
    setup: () => { window.__indOpenStep && window.__indOpenStep('s3'); },
  },
  {
    id: 'step4',
    target: '[data-tour="ind-step-4"]',
    placement: 'left',
    title: 'Step 4 — Lead selection',
    body: <>GP · EHVI · Morgan fingerprints. Ranks all 12 candidates on a 5-axis surrogate (hERG, DILI, Ames, potency, AD).</>,
    setup: () => { window.__indOpenStep && window.__indOpenStep('s4'); },
  },
  {
    id: 'leads-table',
    target: '[data-tour="ind-leads-table"]',
    placement: 'left',
    title: 'Read the ranking',
    body: <>●●●●○ = potency strength. <b>OOD</b> = out of applicability domain — ranked but flagged in §2.6.1.5 with a limitation statement.</>,
    setup: () => { window.__indOpenStep && window.__indOpenStep('s4'); },
  },
  {
    id: 'step5',
    target: '[data-tour="ind-step-5"]',
    placement: 'left',
    title: 'Step 5 — IND document',
    body: <>Assembles when steps 1–4 are green. §2.6.1.1 → §2.6.6 drafted and reviewable in the right panel.</>,
  },
  {
    id: 'coverage',
    target: '[data-tour="ind-coverage"]',
    placement: 'right',
    title: 'Section coverage',
    body: <>● Full · ◑ Partial (computational only) · ○ Not generated. §2.6.5 and §2.6.6 need GLP data to upgrade.</>,
  },
  {
    id: 'doc-panel',
    target: '[data-tour="ind-doc-panel"]',
    placement: 'left',
    title: 'Live document viewer',
    body: <>Always visible on the right. Each pipeline step populates its sections in place — no reload.</>,
  },
  {
    id: 'doc-tabs',
    target: '[data-tour="ind-doc-tabs"]',
    placement: 'bottom',
    title: 'Jump to any section',
    body: <>Click any §2.6.x tab to scroll. Dot colour = coverage at a glance (green Full, amber Partial).</>,
  },
  {
    id: 'doc-region',
    target: '[data-tour="ind-doc-region"]',
    placement: 'bottom',
    title: 'Per-region view',
    body: <>Switch the rendered region. NMPA adds GLP declaration; PMDA adds ethnic-bridging assumptions. All-regions combined is what ships.</>,
  },
  {
    id: 'feedback-edit',
    target: '[data-tour="ind-doc-panel"]',
    placement: 'left',
    title: 'Edit any paragraph',
    body: <>Every paragraph is editable. Each edit is captured as a training pair (chosen=yours, rejected=ours) so the regulatory model improves with every customer.</>,
  },
  {
    id: 'cite-add',
    target: '[data-tour="ind-doc-panel"]',
    placement: 'left',
    title: 'Suggest a citation',
    body: <>The <b>+</b> at the end of any paragraph proposes a missing guideline — useful for NMPA / CDE refs we haven't indexed. Approved suggestions roll into the corpus.</>,
  },
  {
    id: 'audit',
    target: '[data-tour="ind-audit-summary"]',
    placement: 'top',
    title: 'Regulatory audit',
    body: <><b>0 CRITICAL · 0 MAJOR · 2 MINOR · 4 INFO</b> = signable. CRITICAL blocks signing; MAJOR is an amber warning you can override on judgment.</>,
    setup: () => ({ auditOpen: false }),
  },
  {
    id: 'audit-overlay',
    target: '[data-tour="ind-audit-overlay"]',
    placement: 'left',
    title: 'Each finding has a recommendation',
    body: <>Click a finding for its trigger + fix. <b>Dismiss</b> with a reason (e.g. "not applicable to this topical product") and the checker rule refines for everyone.</>,
    setup: () => ({ auditOpen: true }),
  },
  {
    id: 'sign',
    target: '[data-tour="ind-sign-btn"]',
    placement: 'top',
    title: 'Sign & freeze',
    body: <>21 CFR Part 11 §11.200 — reviewer credentials, 6-digit TOTP, and meaning-of-signature are baked into the frozen document.</>,
    setup: () => ({ auditOpen: false, docSigned: false }),
  },
  {
    id: 'versions',
    target: '[data-tour="ind-version-chip"]',
    placement: 'bottom',
    title: 'Versions are immutable',
    body: <>Signed versions are SHA-256 frozen. v3 supersedes v2 but the v2 signature record stays in the audit trail forever.</>,
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
    // IND tour highlights with just the ring — no dimming of the rest of the page.
    window.TOUR_DIM_OVERLAY = false;
    baseTour.start();
  };
  const stop = () => {
    baseTour.stop();
    if (window.__SAVED_TOUR_STEPS) {
      window.TOUR_STEPS = window.__SAVED_TOUR_STEPS;
      delete window.__SAVED_TOUR_STEPS;
    }
    // Restore default dim behaviour for any other tour on the page.
    window.TOUR_DIM_OVERLAY = true;
  };
  return { ...baseTour, start, stop };
};

window.IND_TOUR_STEPS = IND_TOUR_STEPS;
window.useIndTour = useIndTour;
