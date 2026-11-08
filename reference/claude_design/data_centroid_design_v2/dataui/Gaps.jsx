/* Typed clarification · human approval · agent trajectory · roles ·
   the one verification pattern. */

/* Gap 2 — a typed confirm-inference card. Every option carries the value it
   binds to, so an answer is a schema value or a workflow id, never a
   sentence to re-parse. */
function ClarifyCard({ onDone, onToast, dom }) {
  const cset = window.clarifyFor ? clarifyFor(dom) : CLARIFY;
  const qs = cset.qs, N = qs.length;
  const [i, setI] = React.useState(0);
  const [ans, setAns] = React.useState(() => qs.map(q => q.opts.findIndex(o => o.pick)));
  const [own, setOwn] = React.useState('');
  const q = qs[i], pick = ans[i];
  const set = v => setAns(a => a.map((x, j) => j === i ? v : x));
  const advance = () => {
    if (i < N - 1) return setI(i + 1);
    const bound = qs.map((qq, j) => qq.field + ' = ' + (ans[j] === -1 ? '(your words)' : qq.opts[ans[j]].val)).join(' · ');
    onToast('Bound: ' + bound + '. No free-text re-parse; recorded in the run\u2019s trajectory.');
    onDone && onDone();
  };
  return <div className="clarify">
    <div className="clhead">
      <span className="clq-ic"><Icon name="warn" size={13}/></span>
      <span className="clq">{q.q}</span>
      <span className="clcount">{i + 1}/{N}</span>
      <button className="zoomb" title="Skip all and configure manually" onClick={() => { onToast('Skipped. The run is configured with the inferred values, each marked as inferred on its parameter row.'); onDone && onDone(); }}><Icon name="x" size={12}/></button>
    </div>
    <span className="hint clwhy">{q.why}</span>
    <div className="clopts">
      {q.opts.map((o, n) => <button key={o.val} className={'clopt' + (pick === n ? ' on' : '')} onClick={() => set(n)}>
        <span className="cln">{n + 1}</span>
        <span className="col" style={{ gap:'3px', minWidth:0 }}>
          <span className="row ac" style={{ gap:'7px', flexWrap:'wrap', rowGap:'3px' }}>
            <span className="cllabel">{o.label}</span>
            {o.pick && <span className="chip acc">recommended</span>}
          </span>
          <span className="hint dim">{o.note}</span>
          <span className="mono clbind">{q.field} = {o.val}</span>
        </span>
      </button>)}
      <button className={'clopt other' + (pick === -1 ? ' on' : '')} onClick={() => set(-1)}>
        <span className="cln">{q.opts.length + 1}</span>
        <span className="col" style={{ gap:'4px', minWidth:0, width:'100%' }}>
          <span className="cllabel">None of these — I'll say it in my own words</span>
          {pick === -1 && <input className="clown" autoFocus value={own} placeholder="e.g. GRCh38 but with our internal annotation" onChange={ev => setOwn(ev.target.value)}/>}
        </span>
      </button>
    </div>
    <div className="clfoot">
      <span className="hint dim">binds to a {q.binds}</span>
      <span className="spacer"/>
      <button className="btn sm ghost" onClick={() => { onToast('Skipped this one \u2014 the inferred value is used and marked as inferred on its parameter row.'); i < N - 1 ? setI(i + 1) : advance(); }}>Skip</button>
      <button className="btn sm ghost" disabled={i === 0} onClick={() => setI(i - 1)}>Previous</button>
      <button className="btn sm accent" onClick={advance}>{i < N - 1 ? 'Next' : 'Confirm and configure'}</button>
    </div>
  </div>;
}

/* Gap 7 — human approval, in the same vocabulary as a QC gate. */
function ApprovalGate({ onResolve, onToast }) {
  const a = APPROVAL;
  return <div className="gate approval">
    <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
      <Icon name="warn" size={15}/>
      <span style={{ fontWeight:600, fontSize:'13px' }}>Paused — needs your approval</span>
      <span className="spacer"/><span className="chip warn"><span className="dot pulse"/>human gate</span>
    </div>
    <div className="col" style={{ gap:'4px' }}>
      <span className="k2">{a.what}</span>
      <span className="hint">{a.why}</span>
      <span className="hint dim">{a.cost}</span>
    </div>
    <div className="col" style={{ gap:'0' }}>
      {a.measured.map(([k, m, t, v]) => <div key={k} className="meas">
        <span className="hint">{k}</span><span className="mono mval">{m}</span><span className="hint dim">{t}</span>
        <span className={'chip ' + (v === 'pass' ? 'ok' : 'warn')}><span className="dot"/>{v}</span>
      </div>)}
    </div>
    <span className="hint"><b>Who:</b> {a.who} <span className="dim">{a.policy}</span></span>
    <div className="row" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
      <button className="btn sm" onClick={() => { onResolve('approve'); onToast('Approved by you at ' + new Date().toLocaleTimeString() + ' — recorded in the audit trail with your name and the reason shown here.'); }}>Approve</button>
      <button className="btn sm ghost" onClick={() => { onResolve('deny'); onToast('Denied. The run stays paused, nothing was registered, and the denial is in the audit trail.'); }}>Deny</button>
      <button className="btn sm ghost" onClick={() => onToast('Delegates to a reviewer. The run stays paused until someone with the role answers.')}>Ask a reviewer</button>
    </div>
  </div>;
}

/* Gap 8 — the agent-side complement to data lineage. */
function Trajectory({ onToast }) {
  const [only, setOnly] = React.useState('all');
  const kinds = [['all', 'Everything'], ['route', 'Decisions'], ['tool', 'Tool calls'], ['clarify', 'Your answers'], ['note', 'What it told you']];
  const rows = TRAJ.filter(r => only === 'all' || r.kind === only || (only === 'route' && r.kind === 'gate'));
  const ic = { route:'sparkles', tool:'settings', clarify:'check', note:'book', gate:'warn' };
  return <div className="col" style={{ gap:'10px' }}>
    <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
      <span className="k2">Agent trajectory</span>
      <span className="spacer"/>
      <button className="linkish" onClick={() => onToast('Exports the trajectory with the run\u2019s audit trail — the routing decision, every tool call, and every answer you gave.')}>export →</button>
    </div>
    <span className="hint">Data lineage says where a number came from. This says what the agent decided, what it called, and what you told it — the other half of an auditable run.</span>
    <div className="trackbar">
      {kinds.map(([k, l]) => <button key={k} className={'trackb' + (only === k ? ' on' : '')} onClick={() => setOnly(k)}>{l}</button>)}
    </div>
    <div className="traj">
      {rows.map((r, i) => <div key={i} className={'trow ' + r.kind}>
        <span className="tdot"><Icon name={ic[r.kind]} size={10}/></span>
        <span className="col" style={{ gap:'3px', minWidth:0 }}>
          <span className="thead"><span className="tk">{r.k}</span><span className="tt">{r.t}</span></span>
          <span className="hint">{r.d}</span>
          <span className="mono tmeta">{r.meta}</span>
        </span>
      </div>)}
    </div>
    <span className="hint dim">Two entries here are the assistant's own words to you — the mid-run progress line and the post-run answer. Narration is part of the record, not decoration.</span>
  </div>;
}

/* Gap 4 — roles, and the one verification pattern. */
function RolesCard({ onToast }) {
  return <div className="card2 col" style={{ gap:'10px' }}>
    <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
      <span className="k2">Your permissions here</span>
      <span className="chip acc">{ROLES.you}</span>
      <span className="spacer"/><span className="hint dim">{ROLES.project}</span>
    </div>
    <div className="col" style={{ gap:'0' }}>
      {ROLES.caps.map(([k, need, ok]) => <div key={k} className="evrow">
        <span className="hint">{k}</span>
        <span className="hint dim">needs {need}</span>
        <span/>
        <span className={'chip ' + (ok ? 'ok' : '')}><span className="dot"/>{ok ? 'you can' : 'you cannot'}</span>
      </div>)}
    </div>
    <span className="hint">A control you may not use is shown disabled with the role it needs — never hidden. Hiding it makes the product feel broken; naming the role makes it answerable.</span>
  </div>;
}

function VerifyPattern({ onToast }) {
  return <div className="card2 col" style={{ gap:'10px' }}>
    <div className="row ac"><span className="k2">One verification pattern</span><span className="spacer"/>
      <span className="hint dim">measured · threshold · verdict</span></div>
    <span className="hint">Every check in the product reads the same way, so a scientist learns it once. What differs is who measures and what a failure stops.</span>
    <div className="col" style={{ gap:'0' }}>
      {VERIFY_KINDS.map(([k, who, stops, where]) => <div key={k} className="evrow">
        <span className="hint" style={{ color:'var(--text)', fontWeight:600 }}>{k}</span>
        <span className="hint dim">measured by {who}</span>
        <span className="hint">{stops}</span>
        <span className="chip">{where}</span>
      </div>)}
    </div>
    <button className="linkish" style={{ alignSelf:'flex-start' }} onClick={() => onToast('A human approval is a gate whose measurement is a person. That is the only difference.')}>why a human counts as a gate →</button>
  </div>;
}
Object.assign(window, { ClarifyCard, ApprovalGate, Trajectory, RolesCard, VerifyPattern });
