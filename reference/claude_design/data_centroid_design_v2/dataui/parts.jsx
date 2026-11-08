/* Shared atoms for the BioMate data-centric prototype. */
const QUAL = { pass:{ c:'var(--ok)', bg:'var(--ok-soft)', label:'Quality: pass' }, watch:{ c:'var(--warn)', bg:'var(--warn-soft)', label:'Quality: watch' } };
const CONF = { high:{ c:'var(--ok)', bg:'var(--ok-soft)' }, medium:{ c:'var(--warn)', bg:'var(--warn-soft)' }, low:{ c:'var(--err)', bg:'var(--err-soft)' } };

/* Glyphs come from the shipped src/Icon.jsx set — no parallel icon language here. */
function Ico({ n, s = 14 }) { return <Icon name={n} size={s}/>; }

function QPill({ q, compact }) {
  const v = QUAL[q] || QUAL.pass;
  return <span className="chip" style={{ background:v.bg, color:v.c }}><span className="dot"/>{compact ? q : v.label}</span>;
}
function ConfPill({ level }) {
  const v = CONF[level] || CONF.high;
  return <span className="chip" style={{ background:v.bg, color:v.c }}>{level} confidence</span>;
}
function StatusPill({ s }) {
  const m = { completed:['ok','completed'], failed:['err','failed'], running:['run','running'] }[s] || ['','—'];
  return <span className={'chip ' + m[0]}><span className={'dot' + (s === 'running' ? ' pulse' : '')}/>{m[1]}</span>;
}
/* The shipped .file-chip, extended — same chip, now the dataset object's handle:
   a quality dot, and clicking it opens the dataset instead of doing nothing. */
function DataChip({ id, onClick, note }) {
  const d = DATASETS.find(x => x.id === id);
  if (!d) return null;
  return <span className={'file-chip is-dataset' + (note ? ' auto' : '')} onClick={() => onClick && onClick(d.id)}
    title={`${d.kind} · ${QUAL[d.quality].label} — open the dataset`}>
    <span className="fc-q" style={{ background:QUAL[d.quality].c }}/>
    <span className="fc-name">{d.name}</span>
    {note && <span className="fc-note">{note}</span>}
  </span>;
}
function md(t) {
  return t.split(/(\*\*[^*]+\*\*|`[^`]+`)/).map((s, i) => {
    if (s.startsWith('**')) return <b key={i}>{s.slice(2, -2)}</b>;
    if (s.startsWith('`')) return <code key={i} className="mono" style={{ fontSize:'12px', background:'var(--surface-2)', padding:'1px 4px', borderRadius:'3px' }}>{s.slice(1, -1)}</code>;
    return s;
  });
}

/* removed: the five-column graph — superseded by Versions + “Where it came from”.
function LineageGraph({ dsId, onOpenDataset, onToast }) {
  const ds = DATASETS.find(d => d.id === dsId) || DATASETS[0];
  const runs = (ds.runs || []).map(r => RUNS[r]).filter(Boolean);
  const outs = [];
  runs.forEach(r => (r.outputs || []).forEach(o => outs.push(OUTPUTS[o])));
  const reuse = runs.filter(r => false);
  const nextRuns = [];
  DATASETS.filter(d => d.derivedFrom && runs.some(r => r.id === d.derivedFrom)).forEach(d => {
    (d.runs || []).forEach(rid => { const r = RUNS[rid]; if (r && !nextRuns.some(n => n.r.id === rid)) nextRuns.push({ r, via:d }); });
  });
  const src = ds.origin;
  return <div className="col" style={{ gap:'12px' }}>
    <div className="row ac"><span className="k2">Lineage · {ds.name}</span><span className="spacer"/><span className="chip">left → right = time</span></div>
    <div className="lingraph">
      <div className="lincol"><div className="linhd">Source</div>
        <div className="node"><span className="nl">{src.type}</span><span className="nn">{src.label}</span><span className="nm">{src.when} · by {src.by}</span></div>
      </div>
      <span className="linarrow">→</span>
      <div className="lincol"><div className="linhd">Dataset</div>
        <button className="node on" onClick={() => onOpenDataset(ds.id)}><span className="nl">{ds.kind}</span><span className="nn">{ds.name}</span><div className="row"><QPill q={ds.quality} compact/></div></button>
        {ds.id === 'd1' && <button className="node" onClick={() => onOpenDataset('d2')}><span className="nl">sample design</span><span className="nn">design.csv</span><div className="row"><QPill q="watch" compact/></div></button>}
      </div>
      <span className="linarrow">→</span>
      <div className="lincol"><div className="linhd">Run</div>
        {runs.length ? runs.map(r => <div key={r.id} className="node isrun"><span className="nl">workflow · {r.steps} steps</span><span className="nn" style={{ fontFamily:'var(--font-ui)', fontWeight:600, fontSize:'12px' }}>{r.name}</span><span className="nm">{r.version} · {r.dur}</span><div className="row wrap" style={{ gap:'5px' }}><StatusPill s={r.status}/></div></div>)
          : <div className="node isrun" style={{ color:'var(--text-dim)' }}><span className="nl">no runs yet</span><span className="nm">This dataset has been ingested and quality-checked but not consumed.</span></div>}
      </div>
      <span className="linarrow">→</span>
      <div className="lincol"><div className="linhd">Outputs</div>
        {outs.length ? outs.map(o => <button key={o.id} className="node" onClick={() => o.isDataset ? onOpenDataset(o.id) : onToast('Preview opens inline — image in a lightbox, table as a sortable grid.')}><span className="nl">{o.kind}</span><span className="nn">{o.name}</span><span className="nm">{o.meta}</span></button>)
          : <div className="node" style={{ color:'var(--text-dim)', borderStyle:'dashed' }}><span className="nm">Nothing produced yet.</span></div>}
      </div>
      <span className="linarrow">→</span>
      <div className="lincol"><div className="linhd">Re-used as input</div>
        {nextRuns.length ? nextRuns.map(({ r, via }) => <div key={r.id} className="node" style={{ borderStyle:'dashed', borderColor:'var(--accent)' }}><span className="nl">next run</span><span className="nn" style={{ fontFamily:'var(--font-ui)', fontWeight:600, fontSize:'12px' }}>{r.name}</span><span className="nm">consumes {via.name}</span><div className="row"><StatusPill s={r.status}/></div></div>)
          : <div className="node" style={{ borderStyle:'dashed', color:'var(--text-dim)' }}><span className="nm">The cycle closes here — outputs are datasets too, so this column is where re-use appears.</span></div>}
      </div>
    </div>
    <div className="row ac wrap" style={{ borderTop:'1px solid var(--border)', paddingTop:'12px', gap:'8px' }}>
      <span className="hint" style={{ fontWeight:600, color:'var(--text)' }}>Export</span>
      {['PNG for a figure', 'RO-Crate for deposit', 'CSV manifest', 'Audit-trail PDF'].map(x =>
        <button key={x} className="btn sm" onClick={() => onToast('Export → ' + x + ' (stub in this prototype)')}>{x}</button>)}
    </div>
  </div>;
}
*/

/* panel-width origin summary */
function LineageVertical({ dsId, onOpenFull, onToast }) {
  const ds = DATASETS.find(d => d.id === dsId) || DATASETS[0];
  const runs = (ds.runs || []).map(r => RUNS[r]).filter(Boolean);
  const outs = runs.flatMap(r => (r.outputs || []).map(o => OUTPUTS[o]));
  return <div className="card2 col" style={{ gap:'9px' }}>
    <span className="k2">Where it came from</span>
    <div className="vlin">
      <div className="node"><span className="nl">{ds.origin.type}</span><span className="nn">{ds.origin.label}</span></div>
      <span className="va">↓</span>
      <div className="node on"><span className="nl">this dataset</span><span className="nn">{ds.name}</span><div className="row"><QPill q={ds.quality} compact/></div></div>
      <span className="va">↓</span>
      {runs.length ? runs.map(r => <React.Fragment key={r.id}>
        <div className="node isrun"><span className="nl">run · {r.dur}</span><span className="nn" style={{ fontFamily:'var(--font-ui)', fontWeight:600, fontSize:'12px' }}>{r.name}</span><div className="row"><StatusPill s={r.status}/><span className="chip">{r.gates}</span></div></div>
        <span className="va">↓</span>
      </React.Fragment>) : <><div className="node isrun" style={{ color:'var(--text-dim)' }}><span className="nm">not consumed yet</span></div><span className="va">↓</span></>}
      <div className="node"><span className="nl">outputs · {outs.length}</span><span className="nn">{outs.length ? outs.map(o => o.name).join(' · ') : '—'}</span></div>
    </div>
    <div className="row" style={{ gap:'8px' }}>
      <button className="btn sm" onClick={() => onToast('Export → RO-Crate for deposit (stub)')}>Export</button>

    </div>
  </div>;
}

Object.assign(window, { QUAL, CONF, Ico, QPill, ConfPill, StatusPill, DataChip, md, LineageVertical });
