// Tutorial Tour — spotlight + callout tooltip, step-driven
// Steps can optionally set knobs before showing, to drive the UI to the right state.
//
// Step shape:
//   { id, target: '[data-tour="..."]' | null,   // null = centered modal
//     title, body,
//     placement: 'top'|'bottom'|'left'|'right'|'center',  // default 'bottom'
//     setup: (knobs) => partial knob updates,  // applied before showing step
//     cta: 'text'  // custom label for "Got it" on last step
//   }

const TOUR_STEPS = [
  {
    id: 'welcome',
    target: null,
    placement: 'center',
    title: 'Welcome to the BioMate CRO tour',
    body: (
      <>
        I'll walk you through the compliance workspace in about 90 seconds.
        You'll see how the <b>DMTA loop</b>, <b>model validation</b>, <b>audit chain</b>,
        and <b>electronic signatures</b> work together to keep a campaign
        regulator-ready.
        <div className="hint">Use <kbd>→</kbd>/<kbd>←</kbd> to step, <kbd>Esc</kbd> to skip.</div>
      </>
    ),
    setup: () => ({ tab: 'dashboard', show: 'tabs', auditState: 'valid', loopState: 'running', validationState: 'pass', indState: 'generated' }),
  },
  {
    id: 'tabs',
    target: '[data-tour="tabs-bar"]',
    placement: 'bottom',
    title: 'Five surfaces, one campaign',
    body: <>Each tab is a regulated view into the same campaign — Dashboard, Validation, Audit, Auto-Retrain, and IND assembly. I'll visit each one.</>,
  },
  {
    id: 'dmta',
    target: '[data-tour="dmta-stepper"]',
    placement: 'bottom',
    title: 'The DMTA loop',
    body: <>Design → Make → Test → Analyse. This campaign is in Round 3 and currently <b>Making</b>. Auto-retrain advances the loop every time new assay data lands.</>,
    setup: () => ({ tab: 'dashboard', show: 'tabs' }),
  },
  {
    id: 'dashboard-actions',
    target: '[data-tour="dashboard-actions"]',
    placement: 'top',
    title: 'Regulated actions live here',
    body: <><b>Ingest Assay</b> and <b>Export CRO Order</b> are 21 CFR Part 11 actions — they require an electronic signature and they write to the audit chain.</>,
  },
  {
    id: 'validation',
    target: '[data-tour="validation-callout"]',
    placement: 'bottom',
    title: 'EMA 2-fold qualification',
    body: <>We qualify the PBPK model against a 31-drug reference set. Regulators need Cmax and AUC within 2× for ≥67% of drugs. The model passes — evidence you can cite directly in §2.6.1.2.</>,
    setup: () => ({ tab: 'validation', validationState: 'pass', show: 'tabs' }),
  },
  {
    id: 'validation-fail',
    target: '[data-tour="validation-callout"]',
    placement: 'bottom',
    title: 'What if validation fails?',
    body: <>If the criterion isn't met, downstream actions — CRO export, IND assembly — are <b>blocked</b> until the model is re-qualified. Try the Validation tweak to flip this state during the video.</>,
    setup: () => ({ tab: 'validation', validationState: 'fail', show: 'tabs' }),
  },
  {
    id: 'audit',
    target: '[data-tour="audit-list"]',
    placement: 'top',
    title: 'Tamper-evident audit chain',
    body: <>Every regulated action is a record. Each record carries the previous record's SHA-256 hash, so any change anywhere breaks the chain — and we show you exactly where.</>,
    setup: () => ({ tab: 'audit', auditState: 'valid', validationState: 'pass', show: 'tabs' }),
  },
  {
    id: 'audit-tampered',
    target: '[data-tour="audit-list"]',
    placement: 'top',
    title: 'What tampering looks like',
    body: <>Flip the <b>Audit</b> tweak to "Tampered" — record #6 goes red and the chain header flips to a breach warning. This is what an auditor would see if a DB row were modified after the fact.</>,
    setup: () => ({ tab: 'audit', auditState: 'tampered', show: 'tabs' }),
  },
  {
    id: 'retrain',
    target: '[data-tour="loop-strip"]',
    placement: 'bottom',
    title: 'Auto-retrain loop',
    body: <>The loop polls for new assay data. When it finds any, it retrains and proposes a new round of compounds. You can pause it, trigger it manually, or let it run.</>,
    setup: () => ({ tab: 'auto-retrain', loopState: 'running', validationState: 'pass', show: 'tabs' }),
  },
  {
    id: 'ind-generate',
    target: '[data-tour="ind-generate"]',
    placement: 'top',
    title: 'IND §2.6.1 — quick generation in-context',
    body: <>From here you can generate a quick §2.6.1 stub straight off the campaign — useful during DMTA review. For a <b>full ICH M4 §2.6.1–§2.6.6 submission package</b> (FDA · EMA · NMPA · PMDA, sign &amp; freeze, reviewer credentials, version history), open the dedicated <b>BioMate IND Report</b> product.</>,
    setup: () => ({ tab: 'ind-assembly', validationState: 'pass', indState: 'fresh', show: 'tabs' }),
  },
  {
    id: 'esig',
    target: '[data-tour="esig-btn"]',
    placement: 'bottom',
    title: 'Electronic signatures',
    body: <>Any regulated action opens a Part 11-compliant e-signature modal: TOTP code, meaning-of-signature, and a permanent audit record. Try clicking <b>Export CRO Order</b> on the dashboard to see the full flow.</>,
    setup: () => ({ tab: 'dashboard', show: 'tabs' }),
  },
  {
    id: 'tweaks',
    target: null,
    placement: 'center',
    title: 'You\'re ready to record',
    body: (
      <>
        While recording, you can:
        <ul style={{ paddingLeft: 18, margin: '8px 0 0', lineHeight: 1.6 }}>
          <li>Replay this tour anytime from the <b>Tutorial</b> button in the top bar.</li>
          <li>Flip between Valid / Tampered, EMA ✓ / ✗, and Enrolled / Not enrolled from the <b>Tweaks</b> panel.</li>
          <li>Click a regulated action to trigger the e-signature flow.</li>
        </ul>
      </>
    ),
    cta: 'Start recording',
  },
];

const Spotlight = ({ rect, padding = 8, placement }) => {
  // Tours can suppress the dimmed backdrop around highlighted targets by
  // setting window.TOUR_DIM_OVERLAY = false before start (see IndTour.jsx).
  // The highlight ring is always drawn when there's a rect.
  const dim = window.TOUR_DIM_OVERLAY !== false;

  // When no rect: only draw the solid dim backdrop for *intentionally* centered
  // steps (welcome / closing modals). If a step asked for a placement other
  // than 'center' but its target was missing, render nothing — the tooltip
  // alone, no full-screen black.
  if (!rect) {
    if (placement !== 'center' || !dim) return null;
    return (
      <svg className="tour-overlay" aria-hidden="true">
        <rect x="0" y="0" width="100%" height="100%" fill="rgba(12, 14, 20, 0.58)"/>
      </svg>
    );
  }
  const r = 8;
  const x = rect.left - padding;
  const y = rect.top - padding;
  const w = rect.width + padding * 2;
  const h = rect.height + padding * 2;
  return (
    <svg className="tour-overlay" aria-hidden="true">
      {dim && (
        <>
          <defs>
            <mask id="tour-mask">
              <rect x="0" y="0" width="100%" height="100%" fill="white"/>
              <rect x={x} y={y} width={w} height={h} rx={r} ry={r} fill="black"/>
            </mask>
          </defs>
          <rect x="0" y="0" width="100%" height="100%" fill="rgba(12, 14, 20, 0.58)" mask="url(#tour-mask)"/>
        </>
      )}
      <rect x={x} y={y} width={w} height={h} rx={r} ry={r}
        fill="none" stroke="rgba(99, 140, 255, 0.9)" strokeWidth="2" className="tour-ring"/>
    </svg>
  );
};

const Tour = ({ step, total, onNext, onPrev, onSkip, targetRect, placement }) => {
  // Measured callout height (default assumption → updated after first render)
  const calloutRef = React.useRef(null);
  const [calloutH, setCalloutH] = React.useState(180);
  React.useLayoutEffect(() => {
    if (calloutRef.current) {
      setCalloutH(calloutRef.current.offsetHeight);
    }
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
    // Auto-flip: if there's not enough room in the requested direction, flip to opposite
    const spaceBelow = vh - targetRect.bottom;
    const spaceAbove = targetRect.top;
    const spaceLeft = targetRect.left;
    const spaceRight = vw - targetRect.right;
    const needed = CH + OFFSET + MARGIN;

    if (placement === 'bottom' && spaceBelow < needed && spaceAbove > needed) {
      effectivePlacement = 'top';
    } else if (placement === 'top' && spaceAbove < needed && spaceBelow > needed) {
      effectivePlacement = 'bottom';
    } else if (placement === 'left' && spaceLeft < CW + OFFSET + MARGIN && spaceRight > CW + OFFSET + MARGIN) {
      effectivePlacement = 'right';
    } else if (placement === 'right' && spaceRight < CW + OFFSET + MARGIN && spaceLeft > CW + OFFSET + MARGIN) {
      effectivePlacement = 'left';
    }

    const cx = targetRect.left + targetRect.width / 2;
    let left, top;
    if (effectivePlacement === 'bottom') {
      left = cx - CW / 2;
      top = targetRect.bottom + OFFSET;
    } else if (effectivePlacement === 'top') {
      left = cx - CW / 2;
      top = targetRect.top - OFFSET - CH;
    } else if (effectivePlacement === 'left') {
      left = targetRect.left - OFFSET - CW;
      top = targetRect.top + targetRect.height / 2 - CH / 2;
    } else if (effectivePlacement === 'right') {
      left = targetRect.right + OFFSET;
      top = targetRect.top + targetRect.height / 2 - CH / 2;
    }

    // Clamp both axes to viewport (with MARGIN from edges)
    left = Math.max(MARGIN, Math.min(vw - CW - MARGIN, left));
    top = Math.max(MARGIN, Math.min(vh - CH - MARGIN, top));

    calloutStyle = { left, top };
  }

  const isFirst = step === 0;
  const isLast = step === total - 1;

  return (
    <>
      <Spotlight rect={targetRect} placement={placement}/>
      <div
        ref={calloutRef}
        className={`tour-callout ${placement === 'center' ? 'center' : ''}`}
        style={calloutStyle}
      >
        <div className="tour-meta">
          <span className="tour-step-n">Step {step + 1} of {total}</span>
          <button className="tour-skip" onClick={onSkip} aria-label="Skip tutorial">Skip tour ×</button>
        </div>
        <div className="tour-title">{TOUR_STEPS[step].title}</div>
        <div className="tour-body">{TOUR_STEPS[step].body}</div>
        <div className="tour-foot">
          <div className="tour-dots">
            {TOUR_STEPS.map((_, i) => (
              <span key={i} className={`tour-dot ${i === step ? 'active' : i < step ? 'done' : ''}`}/>
            ))}
          </div>
          <div className="tour-actions">
            {!isFirst && <button className="btn sm ghost" onClick={onPrev}>← Back</button>}
            <button className="btn sm primary" onClick={onNext}>
              {isLast ? (TOUR_STEPS[step].cta || 'Done') : 'Next →'}
            </button>
          </div>
        </div>
      </div>
    </>
  );
};

// Hook that owns tour state + the target rect measurement

// Clip a rect to the viewport so very tall targets (e.g. scrollable audit list)
// don't produce a spotlight taller than the screen.
const clipRect = (r, vh) => {
  const top = Math.max(8, r.top);
  const bottom = Math.min(vh - 8, r.bottom);
  return {
    left: r.left,
    right: r.right,
    width: r.width,
    top,
    bottom,
    height: Math.max(40, bottom - top),
  };
};

const useTour = (knobs, setKnobs) => {
  const [active, setActive] = React.useState(false);
  const [step, setStep] = React.useState(0);
  const [rect, setRect] = React.useState(null);

  // Measure target
  const measure = React.useCallback(() => {
    if (!active) return;
    const s = TOUR_STEPS[step];
    if (!s.target) { setRect(null); return; }
    const el = document.querySelector(s.target);
    if (!el) { setRect(null); return; }
    const r = el.getBoundingClientRect();
    const vh = window.innerHeight;

    // If target is off-screen or poorly positioned relative to placement, scroll into a nice position
    const placement = s.placement || 'bottom';
    const desiredTop = placement === 'top' ? Math.max(80, vh * 0.45) : 80;
    const needsScroll = r.top < 40 || r.top > vh - 120 || (placement === 'top' && r.top < vh * 0.35);
    if (needsScroll) {
      // Use window.scrollTo (not scrollIntoView) to avoid the "scrolled webapp off-screen" pitfall
      const scrollY = window.scrollY + r.top - desiredTop;
      window.scrollTo({ top: Math.max(0, scrollY), behavior: 'smooth' });
      // Re-measure after scroll settles
      setTimeout(() => {
        const r2 = el.getBoundingClientRect();
        setRect(clipRect(r2, vh));
      }, 350);
      return;
    }
    setRect(clipRect(r, vh));
  }, [active, step]);

  // Apply setup, then measure (after layout settles)
  React.useEffect(() => {
    if (!active) return;
    const s = TOUR_STEPS[step];
    if (s.setup) {
      const updates = s.setup(knobs);
      if (updates) setKnobs({ ...knobs, ...updates });
    }
    // Two RAFs to let React commit + layout
    let id1 = requestAnimationFrame(() => {
      id1 = requestAnimationFrame(() => measure());
    });
    // Extra pass after 250ms in case of animated layout
    const t = setTimeout(measure, 280);
    return () => { cancelAnimationFrame(id1); clearTimeout(t); };
    // eslint-disable-next-line
  }, [active, step]);

  // Re-measure on resize / scroll
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

  // Keyboard
  React.useEffect(() => {
    if (!active) return;
    const onKey = (e) => {
      if (e.key === 'Escape') setActive(false);
      else if (e.key === 'ArrowRight' || e.key === 'Enter') next();
      else if (e.key === 'ArrowLeft') prev();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line
  }, [active, step]);

  const start = () => { setStep(0); setActive(true); };
  const stop = () => { setActive(false); try { localStorage.setItem('biomate_tour_seen', '1'); } catch {} };
  const next = () => {
    if (step >= TOUR_STEPS.length - 1) stop();
    else setStep(s => s + 1);
  };
  const prev = () => setStep(s => Math.max(0, s - 1));

  const node = active && (
    <Tour
      step={step}
      total={TOUR_STEPS.length}
      onNext={next}
      onPrev={prev}
      onSkip={stop}
      targetRect={rect}
      placement={TOUR_STEPS[step].placement || 'bottom'}
    />
  );

  return { active, start, stop, node };
};

window.Tour = Tour;
window.useTour = useTour;
window.TOUR_STEPS = TOUR_STEPS;
