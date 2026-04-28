// Tutorial Tour — spotlight + callout tooltip, step-driven
// For the Workflow Panel Redesign. Steps can optionally set tweaks to drive the UI.
//
// Step shape:
//   { id, target: '[data-tour="..."]' | null,
//     title, body,
//     placement: 'top'|'bottom'|'left'|'right'|'center',
//     setup: (tweaks) => partial tweak updates,
//     cta: 'text' }

const WF_TOUR_STEPS = [
  {
    id: 'welcome',
    target: null,
    placement: 'center',
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
    id: 'chat-handoff',
    target: '[data-tour="chat-handoff"]',
    placement: 'right',
    title: 'From chat to workflow',
    body: <>You ask Biomate to run something in plain language. It resolves the intent to a concrete pipeline and hands off to the right side — the <b>Workflow Panel</b> — for everything executable.</>,
    setup: () => ({ scenario: 'nfcore', disambig: false }),
  },
  {
    id: 'panel-header',
    target: '[data-tour="panel-header"]',
    placement: 'left',
    title: 'Run status at a glance',
    body: <>Workflow name, domain, and a <b>live progress bar</b> — steps completed / total, plus percent. This stays visible while phases are collapsed below.</>,
  },
  {
    id: 'phase-list',
    target: '[data-tour="phase-list"]',
    placement: 'left',
    title: 'Phases, not a flat step list',
    body: <>A pipeline is grouped into <b>phases</b>. Only the phase you're watching needs to be expanded — the rest stay collapsed with status chips so the panel doesn't become a wall of rows.</>,
  },
  {
    id: 'running-phase',
    target: '[data-tour="phase-list"] .phase.open',
    placement: 'left',
    title: 'Drill into the running phase',
    body: <>The active phase auto-expands. Inside you see <b>steps</b> with live status, per-step actions (skip, rerun, adjust), and any outputs already produced.</>,
  },
  {
    id: 'qc-halt',
    target: '[data-tour="phase-list"]',
    placement: 'left',
    title: 'When a QC gate fails',
    body: <>If a quality gate trips, Biomate can <b>auto-loop</b> — retry with adjusted parameters, up to a cap. You stay in control: accept the suggestion or dismiss it.</>,
    setup: () => ({ qcHalt: true, runState: 'running' }),
  },
  {
    id: 'blocked',
    target: '[data-tour="panel-body"]',
    placement: 'left',
    title: 'Blocking errors surface inline',
    body: <>Missing parameters, license issues, or credential gaps show as an <b>alert at the top of the panel</b> — not a toast that disappears. One click to fix, or confirm anyway.</>,
    setup: () => ({ qcHalt: false, blocked: true, licenseGate: true }),
  },
  {
    id: 'run-button',
    target: '[data-tour="run-footer"]',
    placement: 'top',
    title: 'One primary action',
    body: <>The footer always shows <b>one</b> primary button — Confirm & Run, Cancel, or Run Again — matched to current state. No ambiguity about what "go" does.</>,
    setup: () => ({ blocked: false, licenseGate: false, runState: 'running' }),
  },
  {
    id: 'watcher',
    target: '[data-tour="watcher"]',
    placement: 'top',
    title: 'Detach without losing the run',
    body: <>Long runs move to cloud batch. You can <b>detach the watcher</b> (close your laptop, come back tomorrow) and the job keeps going — reconnect and the panel rehydrates live.</>,
  },
  {
    id: 'tweaks',
    target: null,
    placement: 'center',
    title: "You're ready to explore",
    body: (
      <>
        Flip the <b>Tweaks</b> toggle in the toolbar to:
        <ul style={{ paddingLeft: 18, margin: '8px 0 0', lineHeight: 1.6 }}>
          <li>Switch scenario (nf-core, GATK, CryoSPARC, ADMET).</li>
          <li>Jump between idle / running / completed / failed states.</li>
          <li>Toggle edge cases — QC halt, license gate, blocked, disambiguation.</li>
          <li>Collapse the sidebar to a rail or hide it entirely.</li>
        </ul>
        <div className="hint">Replay this tour anytime from the <b>Tutorial</b> button.</div>
      </>
    ),
    cta: 'Got it',
  },
];

const WFSpotlight = ({ rect, padding = 8 }) => {
  if (!rect) {
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
      <defs>
        <mask id="wf-tour-mask">
          <rect x="0" y="0" width="100%" height="100%" fill="white"/>
          <rect x={x} y={y} width={w} height={h} rx={r} ry={r} fill="black"/>
        </mask>
      </defs>
      <rect x="0" y="0" width="100%" height="100%" fill="rgba(12, 14, 20, 0.58)" mask="url(#wf-tour-mask)"/>
      <rect x={x} y={y} width={w} height={h} rx={r} ry={r}
        fill="none" stroke="rgba(99, 140, 255, 0.9)" strokeWidth="2" className="tour-ring"/>
    </svg>
  );
};

const WFTour = ({ step, total, onNext, onPrev, onSkip, targetRect, placement }) => {
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

  return (
    <>
      <WFSpotlight rect={targetRect}/>
      <div
        ref={calloutRef}
        className={`tour-callout ${placement === 'center' ? 'center' : ''}`}
        style={calloutStyle}
      >
        <div className="tour-meta">
          <span className="tour-step-n">Step {step + 1} of {total}</span>
          <button className="tour-skip" onClick={onSkip} aria-label="Skip tutorial">Skip tour ×</button>
        </div>
        <div className="tour-title">{WF_TOUR_STEPS[step].title}</div>
        <div className="tour-body">{WF_TOUR_STEPS[step].body}</div>
        <div className="tour-foot">
          <div className="tour-dots">
            {WF_TOUR_STEPS.map((_, i) => (
              <span key={i} className={`tour-dot ${i === step ? 'active' : i < step ? 'done' : ''}`}/>
            ))}
          </div>
          <div className="tour-actions">
            {!isFirst && <button className="btn sm ghost" onClick={onPrev}>← Back</button>}
            <button className="btn sm primary" onClick={onNext}>
              {isLast ? (WF_TOUR_STEPS[step].cta || 'Done') : 'Next →'}
            </button>
          </div>
        </div>
      </div>
    </>
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
  const [active, setActive] = React.useState(false);
  const [step, setStep] = React.useState(0);
  const [rect, setRect] = React.useState(null);

  const measure = React.useCallback(() => {
    if (!active) return;
    const s = WF_TOUR_STEPS[step];
    if (!s.target) { setRect(null); return; }
    const el = document.querySelector(s.target);
    if (!el) { setRect(null); return; }
    const r = el.getBoundingClientRect();
    const vh = window.innerHeight;
    setRect(clipRectWF(r, vh));
  }, [active, step]);

  // Apply setup, then measure
  React.useEffect(() => {
    if (!active) return;
    const s = WF_TOUR_STEPS[step];
    if (s.setup) {
      const updates = s.setup(tweaks);
      if (updates) setTweak(updates);
    }
    let id1 = requestAnimationFrame(() => {
      id1 = requestAnimationFrame(() => measure());
    });
    const t = setTimeout(measure, 320);
    return () => { cancelAnimationFrame(id1); clearTimeout(t); };
    // eslint-disable-next-line
  }, [active, step]);

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
      if (e.key === 'Escape') setActive(false);
      else if (e.key === 'ArrowRight' || e.key === 'Enter') next();
      else if (e.key === 'ArrowLeft') prev();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line
  }, [active, step]);

  const start = () => { setStep(0); setActive(true); };
  const stop = () => { setActive(false); try { localStorage.setItem('biomate_wf_tour_seen', '1'); } catch {} };
  const next = () => {
    if (step >= WF_TOUR_STEPS.length - 1) stop();
    else setStep(s => s + 1);
  };
  const prev = () => setStep(s => Math.max(0, s - 1));

  const node = active && (
    <WFTour
      step={step}
      total={WF_TOUR_STEPS.length}
      onNext={next}
      onPrev={prev}
      onSkip={stop}
      targetRect={rect}
      placement={WF_TOUR_STEPS[step].placement || 'bottom'}
    />
  );

  return { active, start, stop, node };
};

window.useWFTour = useWFTour;
window.WF_TOUR_STEPS = WF_TOUR_STEPS;
