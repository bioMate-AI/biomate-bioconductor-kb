/* Part 3 · Requirement B — the cold start: a function-module dashboard and an
   intent router. Categories and example shapes only; the router describes what
   it heard back to you, it never returns a browsable list of our inventory. */

function IntentBar({ value, onChange, onSeed, onToast, small }) {
  const hit = value.trim().length > 6 ? ROUTES.find(r => r.m.test(value)) : null;
  return <div className="col" style={{ gap:'8px', width:'100%' }}>
    {!small && <div className="barlab"><span>Describe the goal</span></div>}
    <div className={'intentbar' + (small ? ' small' : '')}>
      <Icon name="sparkles" size={15}/>
      <input className="intentin" value={value} onChange={e => onChange(e.target.value)} placeholder="e.g. screen these molecules for hERG, then rank by developability"
        onKeyDown={e => { if (e.key === 'Enter' && value.trim()) onSeed(value); }}/>
      <button className="btn sm accent" disabled={!value.trim()} onClick={() => value.trim() && onSeed(value)}><Icon name="send" size={12}/></button>
    </div>
    {hit && <div className="routebox">
      <div className="row ac wrap" style={{ gap:'8px' }}>
        <span className="chip">{hit.dom}</span>
        <span className="spacer"/>
        <button className="btn sm" onClick={() => onSeed(hit.seed)}>Start</button>
      </div>
    </div>}
  </div>;
}

function ModuleCard({ m, open, onOpen, onSeed, onToast }) {
  const [ti, setTi] = React.useState(0);
  const [dom, setDom] = React.useState(null);
  const [mod, setMod] = React.useState('sm');
  const tr = m.tracks[Math.min(ti, m.tracks.length - 1)];
  const ex = tr.exBy ? tr.exBy[mod] || tr.exBy.sm : tr.ex;
  const d = dom && DOMAINS.find(x => x.id === dom);
  return <div className={'modcard' + (open ? ' open' : '')}>
    <button className="modhd" onClick={onOpen}>
      <span className="modi"><Icon name={m.icon} size={16}/></span>
      <span className="col" style={{ gap:'3px', minWidth:0 }}>
        <span className="modk">{m.k}</span>
        <span className="modt">{m.t}</span>
      </span>
      <span className={'pchev' + (open ? ' on' : '')}><Icon name="chevronRight" size={13}/></span>
    </button>
    {open && <div className="modbody">
      <div className="trackbar">{m.tracks.map((x, i) => <button key={x.k} className={'trackb' + (i === ti ? ' on' : '')}
        onClick={() => { setTi(i); setDom(null); }}>{x.k}</button>)}</div>
      <div className="row ac wrap" style={{ gap:'7px', rowGap:'5px' }}>
        <span className="chip">{tr.lane}</span>
        {m.id === 'search' && <span className="chip ok"><Icon name="check" size={10}/>answers on click</span>}
        {m.id === 'models' && <span className="chip ok"><Icon name="check" size={10}/>opens a worked example</span>}
      </div>
      <span className="hint">{tr.s}</span>
      {m.modalities && <div className="row ac wrap" style={{ gap:'6px' }}>
        <span className="hint dim">Modality</span>
        {MODALITIES.map(([k, l]) => <button key={k} className={'schip' + (mod === k ? ' on' : '')} onClick={() => setMod(k)}>{l}</button>)}
      </div>}
      {tr.domains && <div className="row wrap" style={{ gap:'6px' }}>
        {DOMAINS.map(x => <button key={x.id} className={'schip' + (dom === x.id ? ' on' : '')} onClick={() => setDom(dom === x.id ? null : x.id)}>{x.name}</button>)}
      </div>}
      {d ? <div className="col" style={{ gap:'6px' }}>
        {d.shapes.map(s => <button key={s.t} className="shaperow" onClick={() => onSeed(s.seed)}>
          <span className="col" style={{ gap:'3px', minWidth:0 }}><span style={{ fontWeight:600, fontSize:'12.5px' }}>{s.t}</span><span className="hint">{s.needs} · {s.time}</span></span>
          <span className="spacer"/><Icon name="chevronRight" size={13}/>
        </button>)}
      </div> : <div className="col" style={{ gap:'6px' }}>
        {ex.map(x => <button key={x} className="exrow" onClick={() => onSeed(x, m.modalities ? mod : null)}>“{x}”<span className="spacer"/>
          {m.id === 'search' ? <span className="exgo">ask</span> : m.id === 'models' ? <span className="exgo">open</span> : null}<Icon name="chevronRight" size={12}/></button>)}
      </div>}
    </div>}
  </div>;
}

function ModuleDash({ onSeed, onToast, thin, setThin, experts = 2, scope }) {
  const [open, setOpen] = React.useState(null);
  const [q, setQ] = React.useState('');
  if (thin) return <div className="thinlaunch">
    <IntentBar value={q} onChange={setQ} onSeed={onSeed} onToast={onToast} small/>
    <div className="row wrap" style={{ gap:'6px', justifyContent:'center' }}>
      {MODULES.map(m => <button key={m.id} className="modpill" onClick={() => { setThin(false); setOpen(m.id); }}>
        <Icon name={m.icon} size={12}/>{m.k}</button>)}
      <button className="linkish" onClick={() => setThin(false)}>expand</button>
    </div>
  </div>;
  return <div className="colddash">
    <span style={{ fontSize:'18px', fontWeight:600, letterSpacing:'-0.02em' }}>What are you trying to do?</span>
    <IntentBar value={q} onChange={setQ} onSeed={onSeed} onToast={onToast}/>
    <div className="modgrid">
      {MODULES.map(m => <ModuleCard key={m.id} m={m} open={open === m.id} onOpen={() => setOpen(open === m.id ? null : m.id)}
        onSeed={onSeed} onToast={onToast}/>)}
    </div>
    <div className="row ac" style={{ gap:'10px', flexWrap:'wrap', rowGap:'6px', justifyContent:'center' }}>
      {scope && <span className="hint dim">In {scope} · its files and instructions are in context</span>}
      <button className="linkish" onClick={() => setThin(true)}>collapse</button>
    </div>
  </div>;
}
Object.assign(window, { IntentBar, ModuleCard, ModuleDash });
