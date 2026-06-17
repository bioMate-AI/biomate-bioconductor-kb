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

// ── inline markdown ───────────────────────────────────────────────
// Chat lines carry lightweight markdown: **bold**, `code`, *italic*.
// Render them as real elements instead of leaking literal ** / ` to the UI.
function renderRich(text) {
  if (text == null) return null;
  if (typeof text !== 'string') return text;
  const parts = [];
  const re = /(`[^`]+`|\*\*[^*]+\*\*|\*[^*\s][^*]*\*)/g;
  let last = 0, m, key = 0;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) parts.push(text.slice(last, m.index));
    const tok = m[0];
    if (tok[0] === '`')            parts.push(<code key={key++} className="md-code">{tok.slice(1, -1)}</code>);
    else if (tok.slice(0, 2) === '**') parts.push(<strong key={key++}>{tok.slice(2, -2)}</strong>);
    else                          parts.push(<em key={key++}>{tok.slice(1, -1)}</em>);
    last = m.index + tok.length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return parts;
}

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
        {renderRich(line.m)}
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

// ── Section signpost — the arc of the run (Understanding → Choosing →
// Running → Results) so the chat reads as a story, not an event log.
function SectionHeader({ title, n, total }) {
  // No "n / total" badge — it reads like a phase counter and clashed with the
  // panel's phase count (e.g. "3 / 4" vs 5 phases). These are narrative
  // signposts, so show the title alone.
  return (
    <div className="chat-section">
      <span className="cs-title">{title}</span>
      <span className="cs-rule" aria-hidden="true"/>
    </div>
  );
}

// ── Reasoning block — promotes a decision line (route choice, object
// handoff, a statistical correction) to a first-class block: a plain-
// language headline, the technical detail, and the "why" shown INLINE
// (no hover). This is where the logic of the run actually lives.
function ReasoningBlock({ line }) {
  const sp = SPEAKERS[line.s] || SPEAKERS.agent;
  const [whyOpen, setWhyOpen] = useState(false);
  const rationale = line.rationaleId
    ? (window.RESEARCH_PHASE_TRACE[line.rationaleId] || {}).rationale : null;
  const why = line.why || (rationale && rationale.text) || null;
  const cite = rationale && rationale.cite && rationale.cite.title;
  return (
    <div className={'reason-block ' + sp.cls + (line.entering ? ' entering' : '')}>
      <div className="rb-head">
        <span className={'pill ' + sp.cls}>{sp.code}</span>
        {line.lead && <span className="rb-lead">{line.lead}</span>}
      </div>
      <div className="rb-msg">{renderRich(line.m)}</div>
      {why && (
        <div className={'rb-why' + (whyOpen ? ' open' : '')}>
          <button type="button" className="rb-why-toggle"
            onClick={() => setWhyOpen(o => !o)} aria-expanded={whyOpen}>
            <span className="rb-why-caret" aria-hidden="true">▸</span>
            <span className="rb-why-k">Why</span>
            <span className="rb-why-hint">{whyOpen ? 'hide' : 'the deeper reasoning'}</span>
          </button>
          {whyOpen && (
            <div className="rb-why-t">{why}{cite && <span className="rb-cite"> — {cite}</span>}</div>
          )}
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

// ProgressFold — groups consecutive progress-speaker lines into a
// Claude/ChatGPT-style "thinking" block. Folded by default; clicking the
// header toggles. While the group is the latest in the stream and a
// new line just landed, the newest line peeks under the header so the
// user still sees activity without having to expand.
// FIND lines are conclusions — keep them visible inline, never folded.
const PROGRESS_SPEAKERS = new Set(['plan', 'wf', 'qc', 'qc-err', 'loop']);

function ProgressFold({ lines, placement, showTs, isLatest }) {
  const [open, setOpen] = useState(false);
  const [userToggled, setUserToggled] = useState(false);
  const count = lines.length;
  const latest = lines[lines.length - 1];

  // Auto-collapse once the group is no longer the active stream tail
  // (i.e. a card or agent line has been pushed after it). Respect a
  // manual toggle so the user can keep it open if they expanded it.
  useEffect(() => {
    if (!isLatest && open && !userToggled) setOpen(false);
  }, [isLatest, open, userToggled]);

  // Summarise speaker mix for the header (e.g. "PLAN · WF · QC")
  const speakerCodes = [];
  for (const l of lines) {
    const code = (SPEAKERS[l.s] || SPEAKERS.wf).code;
    if (!speakerCodes.includes(code)) speakerCodes.push(code);
  }
  const trail = speakerCodes.slice(0, 4).join(' · ') + (speakerCodes.length > 4 ? ' …' : '');

  // Preview = latest line while the group is the streaming tail and closed
  const showPreview = isLatest && !open;

  return (
    <div className={'progress-fold' + (open ? ' open' : '') + (isLatest ? ' streaming' : '')}>
      <button
        type="button"
        className="pf-head"
        onClick={() => { setUserToggled(true); setOpen(o => !o); }}
      >
        <span className="pf-caret" aria-hidden="true">▸</span>
        <span className="pf-dot" aria-hidden="true"/>
        <span className="pf-label">
          {isLatest ? 'Working' : 'Progress'} · {count} update{count === 1 ? '' : 's'}
        </span>
        <span className="pf-trail">{trail}</span>
        <span className="pf-hint">{open ? 'hide' : 'show'}</span>
      </button>
      {open && (
        <div className="pf-body">
          {lines.map((line, i) => (
            <ChatLine key={'pf' + i} line={line} placement={placement} showTs={showTs}/>
          ))}
        </div>
      )}
      {showPreview && latest && (
        <div className="pf-preview">
          <ChatLine line={latest} placement={placement} showTs={showTs}/>
        </div>
      )}
    </div>
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

  // Build display sequence: group consecutive progress-speaker lines into
  // a foldable block (collapsed by default). AGENT lines and cards break
  // the group so they render inline as normal chat content.
  const display = useMemo(() => {
    const out = [];
    let i = 0;
    while (i < events.length) {
      const e = events[i];
      if (e.kind === 'line' && PROGRESS_SPEAKERS.has(e.s) && !e.explain) {
        let j = i;
        const run = [];
        while (
          j < events.length &&
          events[j].kind === 'line' &&
          PROGRESS_SPEAKERS.has(events[j].s) &&
          !events[j].explain
        ) {
          run.push(events[j]);
          j++;
        }
        out.push({ kind: 'fold', lines: run, startIdx: i, _key: 'f' + i });
        i = j;
      } else if (e.kind === 'line') {
        out.push({ ...e, _key: 'l' + i });
        i++;
      } else {
        out.push({ ...e, _key: 'c' + i });
        i++;
      }
    }
    // Mark the last fold (if it's also the last event) as the streaming tail
    for (let k = out.length - 1; k >= 0; k--) {
      if (out[k].kind === 'fold') { out[k].isLatest = (k === out.length - 1); break; }
    }
    return out;
  }, [events]);

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
          if (e.kind === 'section') {
            return <SectionHeader key={e._key} title={e.title} n={e.n} total={e.total}/>;
          }
          if (e.kind === 'fold') {
            return <ProgressFold key={e._key} lines={e.lines} placement={placement}
              showTs={showTs} isLatest={!!e.isLatest}/>;
          }
          if (e.kind === 'collapse') {
            return <CollapsedSpeakerBlock key={e._key} speaker={e.s} count={e.count}
              hidden={e.hidden} placement={placement} showTs={showTs}/>;
          }
          if (e.kind === 'line') {
            if (e.explain) return <ReasoningBlock key={e._key} line={e}/>;
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
