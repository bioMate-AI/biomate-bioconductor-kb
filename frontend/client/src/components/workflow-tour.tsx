/**
 * WorkflowTour — spotlight + callout tutorial tour
 * Ported from reference/claude_design/cro/src/Tour.jsx
 *
 * Usage:
 *   const { tourNode, startTour } = useWorkflowTour();
 *   ...
 *   <button onClick={startTour}>Tutorial</button>
 *   {tourNode}
 */
import React, { useState, useEffect, useRef, useCallback, useLayoutEffect } from 'react';
import ReactDOM from 'react-dom';

interface TourStep {
  id: string;
  target: string | null;
  placement: 'top' | 'bottom' | 'left' | 'right' | 'center';
  title: string;
  body: React.ReactNode;
  cta?: string;
}

const TOUR_STEPS: TourStep[] = [
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
        <div className="tour-hint">Use <kbd>→</kbd> / <kbd>←</kbd> to step, <kbd>Esc</kbd> to exit.</div>
      </>
    ),
  },
  {
    id: 'chat-handoff',
    target: '[data-tour="chat-handoff"]',
    placement: 'right',
    title: 'From chat to workflow',
    body: (
      <>
        You ask BioMate to run something in plain language. It resolves the intent to a
        concrete pipeline and hands off to the <b>Workflow Panel</b> on the right — for
        everything executable.
      </>
    ),
  },
  {
    id: 'panel-header',
    target: '[data-tour="panel-header"]',
    placement: 'left',
    title: 'Run status at a glance',
    body: (
      <>
        Workflow name, domain chip, and a <b>live progress bar</b> — steps completed / total,
        plus percent. This stays visible while phases are collapsed below.
      </>
    ),
  },
  {
    id: 'phase-list',
    target: '[data-tour="phase-list"]',
    placement: 'left',
    title: 'Phases, not a flat step list',
    body: (
      <>
        A pipeline is grouped into <b>phases</b>. Only the phase you're watching needs to be
        expanded — the rest stay collapsed with status chips so the panel doesn't become a wall
        of rows.
      </>
    ),
  },
  {
    id: 'qc-halt',
    target: '[data-tour="phase-list"]',
    placement: 'left',
    title: 'When a QC gate fails',
    body: (
      <>
        If a quality gate trips, BioMate can <b>auto-loop</b> — retry with adjusted
        parameters, up to a cap. You stay in control: accept the suggestion or dismiss it.
      </>
    ),
  },
  {
    id: 'blocked',
    target: '[data-tour="panel-body"]',
    placement: 'left',
    title: 'Blocking errors surface inline',
    body: (
      <>
        Missing parameters, license issues, or credential gaps show as an{' '}
        <b>alert at the top of the panel</b> — not a toast that disappears. One click to fix,
        or confirm anyway.
      </>
    ),
  },
  {
    id: 'run-footer',
    target: '[data-tour="run-footer"]',
    placement: 'top',
    title: 'One primary action',
    body: (
      <>
        The footer always shows <b>one</b> primary button — Confirm &amp; Run, Cancel, or Run
        Again — matched to current state. No ambiguity about what "go" does.
      </>
    ),
  },
  {
    id: 'watcher',
    target: '[data-tour="watcher"]',
    placement: 'top',
    title: 'Detach without losing the run',
    body: (
      <>
        Long runs move to cloud batch. You can <b>detach the watcher</b> (close your laptop,
        come back tomorrow) and the job keeps going — reconnect and the panel rehydrates live.
      </>
    ),
  },
  {
    id: 'done',
    target: null,
    placement: 'center',
    title: "You're ready",
    body: (
      <>
        That's the full panel. Click <b>Confirm &amp; Run Workflow</b> when parameters look
        right. BioMate takes care of the rest — from AWS Batch submission to AI-generated
        findings in your results.
        <div className="tour-hint">Replay this tour anytime from the <b>Tutorial</b> button.</div>
      </>
    ),
    cta: 'Got it',
  },
];

// ── Spotlight SVG overlay ─────────────────────────────────────────────────────

interface SpotlightProps {
  rect: DOMRect | null;
  padding?: number;
}

const Spotlight: React.FC<SpotlightProps> = ({ rect, padding = 8 }) => {
  if (!rect) {
    return (
      <svg className="tour-overlay" aria-hidden="true">
        <rect x="0" y="0" width="100%" height="100%" fill="rgba(12, 14, 20, 0.45)" />
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
          <rect x="0" y="0" width="100%" height="100%" fill="white" />
          <rect x={x} y={y} width={w} height={h} rx={r} ry={r} fill="black" />
        </mask>
      </defs>
      <rect
        x="0" y="0" width="100%" height="100%"
        fill="rgba(12, 14, 20, 0.45)"
        mask="url(#wf-tour-mask)"
      />
      <rect
        x={x} y={y} width={w} height={h} rx={r} ry={r}
        fill="none"
        stroke="rgba(99, 140, 255, 0.9)"
        strokeWidth="2"
        className="tour-ring"
      />
    </svg>
  );
};

// ── Callout tooltip ────────────────────────────────────────────────────────────

interface CalloutProps {
  step: number;
  total: number;
  onNext: () => void;
  onPrev: () => void;
  onSkip: () => void;
  targetRect: DOMRect | null;
  placement: TourStep['placement'];
}

const Callout: React.FC<CalloutProps> = ({ step, total, onNext, onPrev, onSkip, targetRect, placement }) => {
  const calloutRef = useRef<HTMLDivElement>(null);
  const [calloutH, setCalloutH] = useState(180);

  useLayoutEffect(() => {
    if (calloutRef.current) setCalloutH(calloutRef.current.offsetHeight);
  }, [step, targetRect]);

  const CW = placement === 'center' ? 420 : 360;
  const CH = calloutH;
  const OFFSET = 14;
  const MARGIN = 16;
  const vw = window.innerWidth;
  const vh = window.innerHeight;

  let calloutStyle: React.CSSProperties = {};
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
    let left = 0, top = 0;
    if (effectivePlacement === 'bottom') { left = cx - CW / 2; top = targetRect.bottom + OFFSET; }
    else if (effectivePlacement === 'top') { left = cx - CW / 2; top = targetRect.top - OFFSET - CH; }
    else if (effectivePlacement === 'left') { left = targetRect.left - OFFSET - CW; top = targetRect.top + targetRect.height / 2 - CH / 2; }
    else if (effectivePlacement === 'right') { left = targetRect.right + OFFSET; top = targetRect.top + targetRect.height / 2 - CH / 2; }

    left = Math.max(MARGIN, Math.min(vw - CW - MARGIN, left));
    top = Math.max(MARGIN, Math.min(vh - CH - MARGIN, top));
    calloutStyle = { left, top, width: CW };
  }

  const isFirst = step === 0;
  const isLast = step === total - 1;
  const current = TOUR_STEPS[step];

  return (
    <>
      <Spotlight rect={targetRect} />
      <div
        ref={calloutRef}
        className={`tour-callout${placement === 'center' ? ' center' : ''}`}
        style={calloutStyle}
        role="dialog"
        aria-label={`Tutorial step ${step + 1} of ${total}`}
      >
        <div className="tour-meta">
          <span className="tour-step-n">Step {step + 1} of {total}</span>
          <button className="tour-skip" onClick={onSkip} aria-label="Skip tutorial">
            Skip tour ×
          </button>
        </div>
        <div className="tour-title">{current.title}</div>
        <div className="tour-body">{current.body}</div>
        <div className="tour-foot">
          <div className="tour-dots">
            {TOUR_STEPS.map((_, i) => (
              <span
                key={i}
                className={`tour-dot${i === step ? ' active' : i < step ? ' done' : ''}`}
              />
            ))}
          </div>
          <div className="tour-actions">
            {!isFirst && (
              <button className="tour-btn ghost" onClick={onPrev}>← Back</button>
            )}
            <button className="tour-btn primary" onClick={onNext}>
              {isLast ? (current.cta || 'Done') : 'Next →'}
            </button>
          </div>
        </div>
      </div>
    </>
  );
};

// ── Hook ───────────────────────────────────────────────────────────────────────

function clipRect(r: DOMRect, vh: number): DOMRect {
  const top = Math.max(8, r.top);
  const bottom = Math.min(vh - 8, r.bottom);
  return new DOMRect(r.left, top, r.width, Math.max(40, bottom - top));
}

export function useWorkflowTour() {
  const [active, setActive] = useState(false);
  const [step, setStep] = useState(0);
  const [rect, setRect] = useState<DOMRect | null>(null);

  const measure = useCallback(() => {
    const s = TOUR_STEPS[step];
    if (!s.target) { setRect(null); return; }
    const el = document.querySelector(s.target);
    if (!el) { setRect(null); return; }
    const r = el.getBoundingClientRect();
    setRect(clipRect(r as DOMRect, window.innerHeight));
  }, [step]);

  useEffect(() => {
    if (!active) return;
    let id1 = requestAnimationFrame(() => {
      id1 = requestAnimationFrame(() => measure());
    });
    const t = setTimeout(measure, 320);
    return () => { cancelAnimationFrame(id1); clearTimeout(t); };
  }, [active, step, measure]);

  useEffect(() => {
    if (!active) return;
    const onResize = () => measure();
    window.addEventListener('resize', onResize);
    window.addEventListener('scroll', onResize, true);
    return () => {
      window.removeEventListener('resize', onResize);
      window.removeEventListener('scroll', onResize, true);
    };
  }, [active, measure]);

  useEffect(() => {
    if (!active) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') stop();
      else if (e.key === 'ArrowRight' || e.key === 'Enter') next();
      else if (e.key === 'ArrowLeft') prev();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active, step]);

  const start = useCallback(() => {
    setStep(0);
    setActive(true);
  }, []);

  const stop = useCallback(() => {
    setActive(false);
    try { localStorage.setItem('biomate_wf_tour_seen', '1'); } catch {}
  }, []);

  const next = useCallback(() => {
    if (step >= TOUR_STEPS.length - 1) stop();
    else setStep(s => s + 1);
  }, [step, stop]);

  const prev = useCallback(() => {
    setStep(s => Math.max(0, s - 1));
  }, []);

  const tourNode = active ? ReactDOM.createPortal(
    <Callout
      step={step}
      total={TOUR_STEPS.length}
      onNext={next}
      onPrev={prev}
      onSkip={stop}
      targetRect={rect}
      placement={TOUR_STEPS[step].placement}
    />,
    document.body,
  ) : null;

  return { tourNode, startTour: start, tourActive: active };
}
