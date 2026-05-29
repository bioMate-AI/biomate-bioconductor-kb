// @ts-nocheck
import React from "react";
// Surface 2 — Speaker-pilled chat lines, plus the chat container.
// Renders a sequence of "events" — each event is either a speaker line
// or a chat card (pilot promotion / comparison / findings). The same-
// speaker collapse logic folds 3+ consecutive lines of the same speaker
// into a "WF — 5 updates" caret.

const { useState, useEffect, useRef, useMemo } = React;

// ── speaker meta ──────────────────────────────────────────────────
const SPEAKERS = {
  plan:    { code: 'PLAN',  label: 'Planner',        cls: 'plan'  },
  wf:      { code: 'WF',    label: 'Workflow executor', cls: 'wf' },
  qc:      { code: 'QC',    label: 'Quality control gate', cls: 'qc' },
  'qc-err':{ code: 'QC',    label: 'Quality control gate (blocked)', cls: 'qc-err' },
  loop:    { code: 'LOOP',  label: 'Auto-loop remediation', cls: 'loop' },
  agent:   { code: 'AGENT', label: 'Deep Analysis Agent', cls: 'agent' },
  find:    { code: 'FIND',  label: 'Findings',       cls: 'find' },
};

function ChatLine({ line, placement, showTs }) {
  // placement: 'after-marker' (default, spec recommendation) or 'before-marker'
  const sp = SPEAKERS[line.s] || SPEAKERS.wf;
  const [tip, setTip] = useState(null);
  const [whyTip, setWhyTip] = useState(null);

  // Rationale tooltip — Surface 3 ("why this step") as a lightweight
  // anchor instead of an inline phase-card expansion. Triggered when
  // the line carries a `rationaleId` key into RESEARCH_PHASE_TRACE.
  const rationale = line.rationaleId
    ? (window.RESEARCH_PHASE_TRACE[line.rationaleId] || {}).rationale
    : null;

  return (
    <div className={'chat-line ' + (placement === 'before-marker' ? 'placement-before-marker ' : '') + (line.entering ? 'entering' : '')}>
      <span className={'marker ' + sp.cls}>◆</span>
      <span
        className={'pill ' + sp.cls}
        onMouseEnter={e => setTip({ x: e.clientX, y: e.clientY })}
        onMouseLeave={() => setTip(null)}
      >{sp.code}</span>
      <span className="msg">
        {line.m}
        {rationale && (
          <span
            className="why-anchor"
            onMouseEnter={e => setWhyTip({ x: e.clientX, y: e.clientY })}
            onMouseMove={e => setWhyTip({ x: e.clientX, y: e.clientY })}
            onMouseLeave={() => setWhyTip(null)}
          > (why?)</span>
        )}
      </span>
      {showTs && line.ts && <span className="ts">{line.ts}</span>}
      {tip && (
        <div className="speaker-tooltip" style={{left: tip.x + 10, top: tip.y + 14}}>
          {sp.label}
        </div>
      )}
      {whyTip && rationale && (
        <div className="rationale-tooltip" style={{left: whyTip.x + 12, top: whyTip.y + 16}}>
          <div className="rt-h">Why this step</div>
          <div className="rt-body">{rationale.text}</div>
          {rationale.cite && <div className="rt-cite">— {rationale.cite.title}</div>}
        </div>
      )}
    </div>
  );
}

function CollapsedSpeakerBlock({ speaker, count, hidden, placement, showTs }) {
  const sp = SPEAKERS[speaker] || SPEAKERS.wf;
  const [open, setOpen] = useState(false);
  return (
    <React.Fragment>
      <div className={'chat-collapsed' + (open ? ' open' : '')} onClick={() => setOpen(o => !o)}>
        <span className="caret">▶</span>
        <span>{sp.code} — {count} earlier update{count === 1 ? '' : 's'} · click to {open ? 'hide' : 'show'}</span>
      </div>
      {open && hidden && hidden.map((line, i) => (
        <ChatLine key={'h' + i} line={line} placement={placement} showTs={showTs}/>
      ))}
    </React.Fragment>
  );
}

// ── chat thread (events sequence) ─────────────────────────────────
function ChatStream({
  userQuery, userName, userTs,
  workflowName, workflowSub, panelOpen, onReopenPanel,
  events,                          // [{kind:'line'|'card', ...}]
  placement, collapseThreshold, showTs,
}) {
  const tail = useRef(null);
  // Auto-scroll on new events. Use requestAnimationFrame so the scroll
  // fires after React commits the new chat node, not before.
  useEffect(() => {
    requestAnimationFrame(() => {
      if (!tail.current) return;
      const thread = tail.current.closest('.thread');
      if (thread) thread.scrollTop = thread.scrollHeight;
    });
  }, [events.length]);

  // Build display sequence applying same-speaker collapse
  const display = useMemo(() => {
    if (!collapseThreshold || collapseThreshold <= 0) {
      return events.map((e, i) => ({ ...e, _key: i }));
    }
    const out = [];
    let i = 0;
    while (i < events.length) {
      const e = events[i];
      // Try collapsing a run of consecutive lines with same speaker
      if (e.kind === 'line') {
        let j = i;
        while (j < events.length && events[j].kind === 'line' && events[j].s === e.s && !events[j].collapseAnchor) {
          j++;
        }
        const run = events.slice(i, j);
        if (run.length > collapseThreshold) {
          // Show first 0, keep latest visible. Mark all but last as collapsible.
          const hidden = run.slice(0, run.length - 1);
          const latest = run[run.length - 1];
          out.push({ kind: 'collapse', s: e.s, count: hidden.length, hidden, _key: 'c' + i });
          out.push({ ...latest, _key: i + (run.length - 1) });
        } else {
          for (let k = 0; k < run.length; k++) out.push({ ...run[k], _key: i + k });
        }
        i = j;
      } else {
        out.push({ ...e, _key: i });
        i++;
      }
    }
    return out;
  }, [events, collapseThreshold]);

  return (
    <React.Fragment>
      {/* User message */}
      <div className="msg user">
        <div className="who">{userName || 'You'} · {userTs || '3:40 pm'}</div>
        <div className="bubble">{userQuery}</div>
      </div>

      {/* Assistant intro — compact single line + wf chip only when panel is closed */}
      <div className="msg assistant">
        <div className="who">Biomate</div>
        <div className="bubble">
          <strong>{workflowName}</strong> staged in the panel.
          {!panelOpen && (
            <div className="wf-chip">
              <div className="ic"><Icon name="flask" size={16}/></div>
              <div className="body">
                <div className="name">{workflowName}</div>
                <div className="sub">{workflowSub}</div>
              </div>
              <button className="btn sm" onClick={onReopenPanel}>
                <Icon name="external" size={12}/> Open in panel
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Streaming speaker-pilled lines + inline chat cards (Surfaces 2/4/5) */}
      <div className="chat-stream" data-tour="chat-stream">
        {display.map(e => {
          if (e.kind === 'collapse') {
            return <CollapsedSpeakerBlock key={e._key} speaker={e.s} count={e.count}
              hidden={e.hidden} placement={placement} showTs={showTs}/>;
          }
          if (e.kind === 'line') {
            return <ChatLine key={e._key} line={e} placement={placement} showTs={showTs}/>;
          }
          if (e.kind === 'card') {
            return <div key={e._key}>{e.node}</div>;
          }
          return null;
        })}
        <div ref={tail}/>
      </div>
    </React.Fragment>
  );
}

Object.assign(window, { ChatStream, ChatLine, SPEAKERS });
