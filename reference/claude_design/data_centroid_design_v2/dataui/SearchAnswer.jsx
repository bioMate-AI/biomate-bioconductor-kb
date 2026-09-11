/* Search & evidence — the surface an example actually opens.
   Search is the instant lane: clicking an example does not configure a run, it
   asks the question and returns a cited answer. What was searched, what was
   dropped, and where every claim came from are all part of the answer. */

function SrcRow({ s, phase }) {
  const pct = phase === 'done' ? 100 : phase === 'search' ? 62 : 8;
  return <div className="srcrow">
    <span className="srcn">{s.n}</span>
    <span className="srcbar"><i style={{ width:pct + '%' }}/></span>
    {phase === 'done'
      ? <span className="hint dim mono">{s.got} found · <b style={{ color:'var(--text)' }}>{s.kept} kept</b></span>
      : <span className="hint dim">searching…</span>}
  </div>;
}

function RefCard({ r, n, onToast, compact }) {
  return <div className={'refcard' + (compact ? ' compact' : '')}>
    <span className="refn">{n}</span>
    <div className="col" style={{ gap:'3px', minWidth:0 }}>
      <span className="reft">{r.title}</span>
      <span className="hint">{r.who} · {r.venue} · {r.year}</span>
      <span className="refq">“{r.snippet}”</span>
      <div className="row ac" style={{ gap:'7px', flexWrap:'wrap', rowGap:'5px' }}>
        <span className="chip">{REF_KIND[r.kind] || r.kind}</span>
        <button className="linkish" onClick={() => onToast('Opens the source itself — resolved by title at answer time, never a transcribed identifier, so a reference cannot point at the wrong paper.')}>open source →</button>
      </div>
    </div>
  </div>;
}

function SearchAnswer({ query, track, project, onToast, onBack, onRun, onSaveFile, onOpenFile, onOpenProject }) {
  const c = React.useMemo(() => window.searchCaseFor(query, track), [query, track]);
  const [phase, setPhase] = React.useState('search');
  const [openRef, setOpenRef] = React.useState(null);
  const [showDropped, setShowDropped] = React.useState(false);
  const [saved, setSaved] = React.useState(false);
  React.useEffect(() => { setPhase('search'); setOpenRef(null); setSaved(false);
    const t = setTimeout(() => setPhase('done'), 1150); return () => clearTimeout(t); }, [c.id]);
  const ids = Object.keys(c.refs);
  const num = id => ids.indexOf(id) + 1;
  const kept = c.sources.reduce((n, s) => n + s.kept, 0), got = c.sources.reduce((n, s) => n + s.got, 0);

  const Marks = ({ refs }) => <span className="marks">{refs.map(id => <button key={id} className={'mark' + (openRef === id ? ' on' : '')}
    onClick={() => setOpenRef(openRef === id ? null : id)} title={c.refs[id].title}>{num(id)}</button>)}</span>;

  return <div className="mainpane">
    <div className="objhead">
      <div className="crumb"><button className="linkish" onClick={onOpenProject}>{project}</button><span className="sep">/</span><span>Search &amp; evidence</span><span className="sep">/</span><span>{c.track}</span></div>
      <div className="objtitle">
        <h2 style={{ fontFamily:'var(--font-ui)', fontSize:'17px', lineHeight:1.35 }}>{query && query !== c.q ? query : c.q}</h2>
        <span className="spacer"/>
        {onBack && <button className="btn sm ghost" onClick={onBack}>Back</button>}
      </div>
      {query && query !== c.q && <span className="hint dim">Answered here as the worked example “{c.q}” — the retrieval below is that one, not yours.</span>}
      <div className="row ac wrap" style={{ gap:'7px', rowGap:'6px' }}>
        <span className="chip acc">Instant · cited answer</span>
        <span className="chip">{c.track}</span>
        <span className="hint dim">{c.subject}</span>
        <span className="spacer"/>
        {phase === 'done' && <span className="hint dim">{c.took} · nothing ran on your data</span>}
      </div>
    </div>

    <div className="objbody">
      <div className="card2 col" style={{ gap:'10px' }}>
        <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
          <span className="k2">How this was searched</span>
          <span className="spacer"/>
          {phase === 'done' && <span className="chip">{kept} of {got} kept</span>}
        </div>
        <div className="col" style={{ gap:'6px' }}>{c.sources.map(s => <SrcRow key={s.n} s={s} phase={phase}/>)}</div>
        <div className="row ac wrap" style={{ gap:'6px', rowGap:'6px' }}>
          {c.filters.map(([k, v]) => <button key={k} className="fchip" onClick={() => onToast('Filters are editable — change ' + k.toLowerCase() + ' and the answer is re-derived, with the new retrieval recorded alongside the old one.')}>
            <span className="fk">{k}</span>{v}</button>)}
          <button className="fchip add" onClick={() => onToast('Add a constraint — a date window, a species, a journal set, or a source to exclude.')}>＋ constraint</button>
        </div>
        {phase === 'done' && <>
          <button className="linkish" style={{ alignSelf:'flex-start' }} onClick={() => setShowDropped(d => !d)}>{showDropped ? 'hide what was dropped' : 'what was dropped, and why →'}</button>
          {showDropped && <span className="hint">{c.dropped}</span>}
        </>}
      </div>

      {phase === 'search'
        ? <div className="card2 col" style={{ gap:'8px' }}><span className="k2">Composing the answer</span>
            <span className="hint">Each claim is held until a source can be attached to it. A claim with no source does not get written.</span></div>
        : <>
          <div className="card2 col" style={{ gap:'12px' }}>
            <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
              <span className="k2">Answer</span>
              <span className="chip ok"><Icon name="check" size={10}/>every claim cited</span>
              <span className="spacer"/>
              <button className="btn sm ghost" onClick={() => onToast('Copied with its references, formatted for the project memo template.')}><Icon name="copy" size={11}/>Copy</button>
            </div>
            {c.answer.map((a, i) => <div key={i} className="col" style={{ gap:'6px' }}>
              {a.lead && <span className="anslead">{a.lead}</span>}
              <p className="anspara">{a.t}<Marks refs={a.refs}/></p>
              {a.refs.indexOf(openRef) >= 0 && <RefCard r={c.refs[openRef]} n={num(openRef)} onToast={onToast}/>}
            </div>)}
            <div className="boundary"><span className="bl">Boundary</span><span className="hint">{c.boundary}</span></div>
          </div>

          <div className="card2 col" style={{ gap:'9px' }}>
            <span className="k2">{c.disagree ? c.disagree.t : 'What the record contains'}</span>
            {c.disagree && <><span className="hint">{c.disagree.s}</span>
              <div className="row ac" style={{ gap:'6px' }}>{c.disagree.refs.map(id => <button key={id} className="mark" onClick={() => setOpenRef(openRef === id ? null : id)}>{num(id)}</button>)}</div>
              {c.disagree.refs.indexOf(openRef) >= 0 && <RefCard r={c.refs[openRef]} n={num(openRef)} onToast={onToast}/>}</>}
            <div className="evtable">
              <div className="evrow evhd">{c.table.cols.map(h => <span key={h}>{h}</span>)}</div>
              {c.table.rows.map((r, i) => <div key={i} className="evrow" style={{ gridTemplateColumns:'repeat(' + c.table.cols.length + ', minmax(0,1fr))' }}>
                {r.map((v, j) => <span key={j} className={j === 0 ? 'mono' : ''}>{v}</span>)}</div>)}
            </div>
          </div>

          <div className="card2 col" style={{ gap:'9px' }}>
            <div className="row ac"><span className="k2">References</span><span className="spacer"/>
              <button className="btn sm ghost" onClick={() => onToast('Bibliography exported — BibTeX, RIS or the project’s citation style.')}><Icon name="download" size={11}/>Bibliography</button></div>
            <div className="col" style={{ gap:'7px' }}>{ids.map(id => <RefCard key={id} r={c.refs[id]} n={num(id)} onToast={onToast} compact/>)}</div>
            <span className="hint dim">Every link was opened and confirmed to resolve before the answer was allowed to use it.</span>          </div>

          <div className="card2 col" style={{ gap:'10px' }}>
            <span className="k2">What to do next</span>
            <div className="row wrap" style={{ gap:'8px', rowGap:'8px' }}>
              {c.next.map(([k, label, sub]) => <button key={k} className="nextcard" onClick={() => {
                if (k === 'run') return onRun(c);
                setSaved(true); onSaveFile && onSaveFile(c);
              }}>
                <Icon name={k === 'run' ? 'beaker' : 'file'} size={14}/>
                <span className="col" style={{ gap:'2px', minWidth:0, textAlign:'left' }}>
                  <span style={{ fontWeight:600, fontSize:'12.5px' }}>{label}</span><span className="hint">{sub}</span></span>
                <Icon name="chevronRight" size={13}/>
              </button>)}
            </div>
            {saved && <div className="row ac wrap" style={{ gap:'8px', rowGap:'6px' }}>
              <span className="chip ok"><Icon name="check" size={10}/>saved as {DOCS.ans1.name}</span>
              <button className="btn sm" onClick={() => onOpenFile && onOpenFile('ans1')}>Open it in Files →</button>
              <span className="hint dim">A document now: editable, versioned, downloadable.</span>
            </div>}
          </div>
        </>}
    </div>
  </div>;
}
Object.assign(window, { SearchAnswer, RefCard, SrcRow });
