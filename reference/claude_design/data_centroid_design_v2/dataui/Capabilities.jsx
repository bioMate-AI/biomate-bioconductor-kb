/* Part 1 — capability surface, search-first.
   One question at a time: type what you want, or narrow by domain. Nothing is
   shown until it is relevant, and the domain row disappears once a domain is picked. */
function Capabilities({ onSeed, onToast, experts }) {
  const [q, setQ] = React.useState('');
  const [dom, setDom] = React.useState(null);
  const query = q.trim().toLowerCase();

  const hits = React.useMemo(() => {
    if (!query) return null;
    const out = [];
    DOMAINS.forEach(d => d.shapes.forEach(s => {
      const hay = (d.name + ' ' + d.sub + ' ' + s.t + ' ' + s.s).toLowerCase();
      if (query.split(/\s+/).every(w => hay.includes(w))) out.push({ d, s });
    }));
    INSTANT.forEach(i => {
      const hay = (i.k + ' ' + i.t + ' ' + i.s).toLowerCase();
      if (query.split(/\s+/).every(w => hay.includes(w))) out.push({ instant:i });
    });
    return out;
  }, [query]);

  const active = dom && DOMAINS.find(d => d.id === dom);

  const Shape = ({ d, s }) => <button className="shape" onClick={() => onSeed(s.seed)}>
    <div className="row ac" style={{ gap:'8px' }}>
      <span className="st">{s.t}</span><span className="spacer"/>
      {!dom && <span className="chip">{d.name}</span>}
      <span className="chip ok"><span className="dot"/>QC-gated</span>
    </div>
    <span className="ss">{s.s}</span>
    <div className="row wrap" style={{ gap:'6px' }}><span className="chip">typical {s.time}</span><span className="chip">{s.needs}</span></div>
  </button>;

  return <div className="scrollarea"><div className="capwrap">
    <div className="caphead">
      <h1>Say what you want to do.</h1>
      <p>Search finds it whether or not it is listed below — you never need a pipeline name. Anything that runs as a validated workflow says so, with how long it takes.</p>
    </div>

    <div className="searchbox">
      <Icon name="search" size={16}/>
      <input value={q} onChange={e => setQ(e.target.value)} placeholder="e.g. differential expression, ADMET, cryo-EM, cohort endpoint…"
        onKeyDown={e => { if (e.key === 'Enter' && query && !(hits || []).length) onSeed(q); }}/>
      {q && <button className="btn sm ghost" onClick={() => setQ('')}><Icon name="x" size={13}/></button>}
    </div>

    {query ? <div className="col" style={{ gap:'10px' }}>
      <span className="k2">{hits.length ? `${hits.length} match${hits.length === 1 ? '' : 'es'}` : 'No listed match'}</span>
      {hits.map((h, i) => h.instant
        ? <button key={i} className="shape" onClick={() => h.instant.seed ? onSeed(h.instant.seed) : onToast('Expert packs are toggled in the composer.')}>
            <div className="row ac"><span className="st">{h.instant.t}</span><span className="spacer"/><span className="chip run"><span className="dot"/>instant</span></div>
            <span className="ss">{h.instant.s}</span>
          </button>
        : <Shape key={i} d={h.d} s={h.s}/>)}
      <button className="shape" style={{ borderStyle:'dashed', borderColor:'var(--accent)' }} onClick={() => onSeed(q)}>
        <span className="st" style={{ color:'var(--accent-ink)' }}>Ask for “{q}” in your own words</span>
        <span className="ss">Coverage is wider than this list. Describe it and BioMate routes it — or tells you plainly that it cannot.</span>
      </button>
    </div> : active ? <div className="col" style={{ gap:'12px' }}>
      <div className="row ac" style={{ gap:'8px' }}>
        <button className="btn sm ghost" onClick={() => setDom(null)}>← All domains</button>
        <span style={{ fontSize:'14px', fontWeight:600 }}>{active.name}</span>
        <span className="hint">{active.sub}</span>
      </div>
      <div className="col" style={{ gap:'8px' }}>
        {active.shapes.map((s, i) => <Shape key={i} d={active} s={s}/>)}
        <button className="shape" style={{ borderStyle:'dashed', borderColor:'var(--accent)' }} onClick={() => onSeed('')}>
          <span className="st" style={{ color:'var(--accent-ink)' }}>Something else in {active.name.toLowerCase()}</span>
          <span className="ss">Search above, or describe it in the composer.</span>
        </button>
      </div>
    </div> : <div className="col" style={{ gap:'12px' }}>
      <span className="k2">Or narrow by domain</span>
      <div className="domrow">
        {DOMAINS.map(d => <button key={d.id} className="dompill" onClick={() => setDom(d.id)}>{d.name}</button>)}
        <button className="dompill ghost" onClick={() => onToast('Epigenomics, microbiome, imaging, metabolomics and more — search for what you need.')}>more…</button>
      </div>
      <div className="tiernote">
        <div className="row ac" style={{ gap:'9px' }}><span className="chip run"><span className="dot"/>Instant</span><span className="hint"><b>Seconds, in the conversation.</b> A cited answer from literature and curated databases, or code written and run on your data in a sandbox. {experts} expert reasoning pack{experts === 1 ? '' : 's'} on.</span></div>
        <div className="row ac" style={{ gap:'9px' }}><span className="chip ok"><span className="dot"/>Cloud</span><span className="hint"><b>Minutes to hours.</b> A validated multi-step pipeline with quality gates and an audit-ready report. BioMate picks the lane; you can override it in the composer.</span></div>
      </div>
    </div>}

    <div className="trust">
      <span className="chip ok"><span className="dot"/>Cited</span>
      <span className="chip ok"><span className="dot"/>Quality-gated</span>
      <span className="chip ok"><span className="dot"/>Audit-ready</span>
      <span className="hint" style={{ marginLeft:'6px' }}>True of every lane, and the evidence is kept with the dataset itself — its quality, its versions, and the runs that used it.</span>
    </div>
  </div></div>;
}
Object.assign(window, { Capabilities });
