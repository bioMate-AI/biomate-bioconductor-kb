/* The detail page a Models example opens. Same spine for all four tracks —
   what model, what it was given, what came back, how much to trust it, what it
   left behind — so a pre-trained inference and a closed loop read alike. */

function ModelCase({ query, track, project, onToast, onBack, onOpenModel, onOpenFile, onOpenRun, onOpenProject, onOpenModels }) {
  const c = React.useMemo(() => window.modelCaseFor(query, track), [query, track]);
  if (!c) return null;
  const [phase, setPhase] = React.useState('work');
  const [registered, setRegistered] = React.useState(false);
  React.useEffect(() => { setPhase('work'); setRegistered(false);
    const t = setTimeout(() => setPhase('done'), 1250); return () => clearTimeout(t); }, [c.id]);
  const flags = c.metrics.filter(m => m[3] === 'flag').length;
  const doc = window.CASE_DOC[c.id];
  const reg = window.CASE_REGISTER[c.id];

  return <div className="mainpane">
    <div className="objhead">
      <div className="crumb"><button className="linkish" onClick={onOpenProject}>{project}</button><span className="sep">/</span><button className="linkish" onClick={onOpenModels}>Models</button><span className="sep">/</span><span>{c.track}</span></div>
      <div className="objtitle">
        <h2 style={{ fontFamily:'var(--font-ui)', fontSize:'17px', lineHeight:1.35 }}>{query && query !== c.q ? query : c.q}</h2>
        <span className="spacer"/>
        {onBack && <button className="btn sm ghost" onClick={onBack}>Back</button>}
      </div>
      {query && query !== c.q && <span className="hint dim">Shown as the worked example “{c.q}” — the run below is that one, not yours.</span>}
      <div className="row ac wrap" style={{ gap:'7px', rowGap:'6px' }}>
        <span className="chip acc">{c.lane}</span>
        <button className="chip mono linkish" onClick={() => onOpenModel(c.model.name)}>{c.model.name} {c.model.v}</button>
        <span className="hint dim">{c.subject}</span>
        <span className="spacer"/>
        <span className="hint dim">{c.took}</span>
      </div>
    </div>

    <div className="objbody">
      <div className="card2 col" style={{ gap:'10px' }}>
        <div className="row ac wrap" style={{ gap:'8px', rowGap:'6px' }}>
          <span className="k2">What this was given</span>
        </div>
        <div className="col" style={{ gap:'0' }}>
          {c.setup.map(([k, v, note]) => <div key={k} className="evrow mcrow">
            <span className="hint">{k}</span><span className="mono evval">{v}</span><span className="hint dim">{note}</span></div>)}
        </div>
        <div className="mcstages">
          {c.stages.map(([k, st]) => <span key={k} className={'mcstage ' + (phase === 'work' && st !== 'done' ? '' : st.replace(/\s.*/, ''))}>
            <span className="mcdot"/>{k}<span className="hint dim">{phase === 'work' && st !== 'done' ? 'waiting' : st}</span></span>)}
        </div>
      </div>

      {phase === 'work'
        ? <div className="card2 col" style={{ gap:'8px' }}><span className="k2">Working</span>
            <span className="hint">Nothing is reported until the evaluation step finishes — a number without its confidence is not an answer here.</span></div>
        : <>
          <div className="card2 col" style={{ gap:'12px' }}>
            <div className="row ac wrap" style={{ gap:'8px', rowGap:'6px' }}>
              <span className="k2">What came back</span>
              <ConfBand level={c.model.conf}/>
              <span className="spacer"/>
              <span className={'chip ' + (flags ? 'warn' : 'ok')}><span className="dot"/>{flags ? flags + ' flagged' : 'no flags'}</span>
            </div>
            <span className="anslead">{c.result.head}</span>
            {c.result.blocks.map((b, i) => <div key={i} className="col" style={{ gap:'5px' }}>
              <span className="mclead">{b.lead}</span>
              <p className="anspara">{b.t}</p>
            </div>)}
            <div className="boundary"><span className="bl">Boundary</span><span className="hint">{c.boundary}</span></div>
          </div>

          <div className="card2 col" style={{ gap:'9px' }}>
            <div className="row ac"><span className="k2">Measured against a floor</span><span className="spacer"/>
              <span className="hint dim">clearing it by more does not make a model better</span></div>
            <div className="col" style={{ gap:'0' }}>
              {c.metrics.map(([k, v, thr, verdict]) => <div key={k} className="evrow">
                <span className="hint">{k}</span><span className="mono evval">{v}</span><span className="hint dim">{thr}</span>
                <span className={'chip ' + (verdict === 'pass' ? 'ok' : 'warn')}><span className="dot"/>{verdict}</span></div>)}
            </div>
          </div>

          <div className="card2 col" style={{ gap:'9px' }}>
            <div className="row ac wrap" style={{ gap:'8px', rowGap:'6px' }}>
              <span className="k2">What it left behind</span>
              <span className="spacer"/>
              <span className="hint dim">every artefact is a file in {project}, with its own versions</span>
            </div>
            {c.artifacts.map(([n, d]) => <div key={n} className="qline">
              <Icon name="file" size={13}/>
              <span className="col" style={{ gap:'2px', minWidth:0 }}>
                <span className="mono" style={{ fontSize:'12px', fontWeight:600 }}>{n}</span>
                <span className="hint dim">{d}</span></span>
              <span className="spacer"/>
              {/\.md$/.test(n)
                ? <><button className="btn sm ghost" onClick={() => onOpenFile && onOpenFile(doc)}>Open &amp; edit</button>
                    <DownloadMenu name={n} onToast={onToast}/></>
                : <button className="btn sm ghost" onClick={() => onToast('Opens as a file object — preview, versions, where it came from, and the same download and ask-to-edit affordances as any other file.')}>Open in Files</button>}
            </div>)}
          </div>

          <div className="card2 col" style={{ gap:'10px' }}>
            <span className="k2">What to do next</span>
            <div className="row wrap" style={{ gap:'8px', rowGap:'8px' }}>
              {c.next.map(([k, label, sub]) => <button key={k} className="nextcard" onClick={() => {
                if (k === 'model') return onOpenModel(c.model.name);
                if (k === 'data') return onOpenFile && onOpenFile(doc);
                if (k === 'register') { window.registerModel(reg[0], reg[1]); setRegistered(true);
                  return onToast('Registered as ' + reg[0] + ' ' + reg[1] + '. The registry row and the model card both moved, the previous version is marked superseded rather than deleted, and every consumer is listed on the model object before a version bump.'); }
                onOpenRun && onOpenRun();
              }}>
                <Icon name={k === 'model' ? 'sparkles' : k === 'data' ? 'file' : k === 'register' ? 'check' : 'beaker'} size={14}/>
                <span className="col" style={{ gap:'2px', minWidth:0, textAlign:'left' }}>
                  <span style={{ fontWeight:600, fontSize:'12.5px' }}>{label}</span><span className="hint">{sub}</span></span>
                <Icon name="chevronRight" size={13}/>
              </button>)}
            </div>
            {registered && <span className="chip ok"><Icon name="check" size={10}/>registered as {reg[0]} {reg[1]}</span>}
          </div>
        </>}
    </div>
  </div>;
}
Object.assign(window, { ModelCase });
