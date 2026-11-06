/* Part A3 — machine learning inside the project: Train · Adapt · Infer.
   Training reuses the run language (phases, gates, tracking) so it reads as a
   run, not a separate product. Adaptation is shown as things learned, each
   switchable. Inference is a registry plus where predictions are consumed. */
const ML_TABS = ['Train', 'House style', 'Rounds', 'Run a model', 'Registry'];

function TrainTab({ onToast, onOpenRun }) {
  const [cfg, setCfg] = React.useState(false);
  return <>
    {cfg && <TrainConfig onClose={() => setCfg(false)} onToast={onToast} onOpenRun={onOpenRun}/>}
    <div className="card2 col" style={{ gap:'11px' }}>
      <div className="row ac"><span className="k2">The training loop</span><span className="spacer"/><span className="hint dim">same compute, same gates, same tracking as a workflow run</span></div>
      <div className="loop">
        {TRAIN_LOOP.map(([k, d, v], i) => <div key={k} className="loopstep">
          <span className="lnum">{i + 1}</span>
          <span style={{ fontSize:'12.5px', fontWeight:600 }}>{k}</span>
          <span className="hint">{d}</span>
          <span className="mono lval">{v}</span>
        </div>)}
      </div>
      <span className="hint">Only the first and last steps are new decisions: which dataset, and whether to register. Everything between reuses the run experience, which is the point — <b>training should feel like running a workflow</b>.</span>
    </div>

    <div className="card2 col" style={{ gap:'10px' }}>
      <div className="row ac"><span className="k2">Training runs</span><span className="spacer"/>
        <button className="btn sm" onClick={() => setCfg(true)}>New training run</button></div>
      <div className="col" style={{ gap:'8px' }}>
        {TRAIN_RUNS.map(r => <div key={r.name} className="card2 col" style={{ gap:'7px' }}>
          <div className="row ac" style={{ gap:'9px', flexWrap:'wrap', rowGap:'6px' }}>
            <span style={{ fontWeight:600, fontSize:'13px' }}>{r.name}</span>
            <span className="chip">{r.family}</span><span className="spacer"/>
            <span className="hint dim">{r.when}</span><StatusPill s={r.status}/>
          </div>
          <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
            <span className="chip">{r.metric}</span>
            <span className={'chip ' + (r.status === 'failed' ? 'err' : r.status === 'completed' ? 'ok' : '')}><span className="dot"/>{r.gate}</span>
            <span className="hint dim mono" style={{ fontSize:'11px' }}>{r.ds}</span>
            <span className="spacer"/>
            <button className="linkish" onClick={r.status === 'running' ? onOpenRun : () => onToast('Experiment record: dataset version, parameters, metrics, artefacts, and the gate decision.')}>{r.status === 'running' ? 'watch live →' : 'open experiment →'}</button>
          </div>
          <span className="hint">{r.v}</span>
        </div>)}
      </div>
    </div>

    <div className="card2 col" style={{ gap:'9px' }}>
      <span className="k2">Model families available</span>
      <div className="famgrid">
        {MODEL_FAMILIES.map(([n, s, use]) => <div key={n} className="fam">
          <span style={{ fontSize:'12.5px', fontWeight:600 }}>{n}</span>
          <span className="hint">{s}</span>
          <span className="hint dim">{use}</span>
        </div>)}
      </div>
    </div>
  </>;
}

function AdaptTab({ onToast }) {
  const [pairs, setPairs] = React.useState(EDIT_PAIRS);
  const toggle = i => { setPairs(p => p.map((x, j) => j === i ? { ...x, on:!x.on } : x)); onToast('Turned ' + (pairs[i].on ? 'off' : 'on') + '. House style is a list of switchable rules, not an opaque model change.'); };
  return <>
    <div className="card2 col" style={{ gap:'11px' }}>
      <div className="row ac" style={{ flexWrap:'wrap', rowGap:'6px' }}><span className="k2">How BioMate writes for us</span><span className="spacer"/>
        <span className="chip">scope: organisation</span>
        <button className="btn sm" onClick={() => onToast('Queued a job over the 214 pending pairs. It runs as a tracked training run, with its own quality gate.')}>Re-train on my edits</button></div>
      <span className="hint">This is style, not science: it changes wording, units and house conventions in what BioMate writes — never a predicted number. Fine-tuning a scientific model on your data is <b>Tune on our data</b>, a different job with held-out evidence and a gate.</span>
      <span className="hint">When you correct BioMate’s output, the before→after pair is queued. Nothing is learned silently: every learned rule appears below and can be switched off.</span>
      <div className="lvls">
        {ADAPT_LEVELS.map(([n, cost, state, on]) => <div key={n} className={'lvl' + (on === 'active' ? ' on' : '')}>
          <span className="row ac" style={{ gap:'7px' }}><span className={'chip ' + (on === 'active' ? 'ok' : '')}><span className="dot"/>{on}</span><span style={{ fontSize:'12.5px', fontWeight:600 }}>{n}</span></span>
          <span className="hint dim">{cost}</span>
          <span className="hint">{state}</span>
        </div>)}
      </div>
      <span className="hint dim">Cheapest first: a rule is preferred over an index, and an index over a trained adapter. The level in use is visible, because it changes what “forget this” means.</span>
    </div>

    <div className="card2 col" style={{ gap:'10px' }}>
      <div className="row ac"><span className="k2">What was learned</span><span className="spacer"/><span className="hint dim">{pairs.filter(p => p.on).length} of {pairs.length} active</span></div>
      <div className="col" style={{ gap:'8px' }}>
        {pairs.map((p, i) => <div key={p.doc + i} className={'pair' + (p.on ? '' : ' off')}>
          <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'5px' }}>
            <span style={{ fontSize:'12.5px', fontWeight:600 }}>{p.learned}</span><span className="spacer"/>
            <span className="chip">{p.scope}</span>
            <button className={'sw' + (p.on ? ' on' : '')} onClick={() => toggle(i)}><span/></button>
          </div>
          <div className="pairdiff">
            <span className="dbefore">{p.before}</span>
            <span className="dafter">{p.after}</span>
          </div>
          <span className="hint dim">from your edit in <b>{p.doc}</b> · {p.when}</span>
        </div>)}
      </div>
    </div>
  </>;
}

function InferTab({ onToast, onOpenModel }) {
  return <>
    <div className="card2 col" style={{ gap:'10px' }}>
      <div className="row ac" style={{ flexWrap:'wrap', rowGap:'6px' }}><span className="k2">Model registry</span><span className="spacer"/>
        <span className="hint dim">account-level · a model trained in one project is callable from any</span>
        <button className="btn sm" onClick={() => onToast('Plug in a model: Python function, container, or REST endpoint.')}>Plug in a model</button></div>
      <div className="reg">
        <div className="regh"><span>Model</span><span>Family</span><span>Called as</span><span>Origin</span><span>Used by</span></div>
        {REGISTRY.map(m => <div key={m.name} className="regr" onClick={() => onOpenModel(m.name)}>
          <span className="mono" style={{ fontWeight:600 }}>{m.name} <span className="dim">{m.v}</span></span>
          <span className="hint">{m.family}</span>
          <span className="chip">{m.plug}</span>
          <span className="hint dim">{m.by}</span>
          <span className="hint">{m.used}</span>
        </div>)}
      </div>
      <span className="hint dim">A row opens the model object — evidence, lineage, consumers, interface, versions.</span>
    </div>

    <div className="two">
      <div className="card2 col" style={{ gap:'9px' }}>
        <span className="k2">Three ways to plug one in</span>
        {PLUG_WAYS.map(([k, d, when]) => <div key={k} className="qline"><span className="chip acc">{k}</span><span className="col" style={{ gap:'2px', minWidth:0 }}><span className="hint" style={{ color:'var(--text)' }}>{d}</span><span className="hint dim">{when}</span></span></div>)}
        <span className="hint">A lab's own model drops in without rewriting the pipeline — the pipeline calls the registry, not the implementation.</span>
      </div>
      <div className="card2 col" style={{ gap:'9px' }}>
        <span className="k2">Where predictions are consumed</span>
        {INFER_USES.map(([k, d, ex]) => <div key={k} className="qline"><span className="chip">{k}</span><span className="col" style={{ gap:'2px', minWidth:0 }}><span className="hint" style={{ color:'var(--text)' }}>{d}</span><span className="hint dim">{ex}</span></span></div>)}
        <span className="hint dim">A prediction can halt a run, so it inherits the same gate presentation as any other quality gate — measured, threshold, evidence.</span>
      </div>
    </div>
  </>;
}

function Models({ project, onToast, onOpenRun, onOpenData, tab, setTab, unused, scope, openModel, clearOpenModel }) {
  const [model, setModel] = React.useState(openModel || null);
  useVersionTick();
  React.useEffect(() => { if (openModel) setModel(openModel); }, [openModel]);
  const ws = scope === 'workspace';
  if (model) return <ModelObject id={model} onBack={() => { setModel(null); clearOpenModel && clearOpenModel(); }} onToast={onToast} onOpenRun={onOpenRun} onOpenData={onOpenData || (() => onToast('Opens the dataset object.'))}/>;
  if (unused) return <div className="mainpane">
    <div className="objhead">
      <div className="crumb"><span>{project}</span><span className="sep">/</span><span>Models</span></div>
      <div className="objtitle"><h2 style={{ fontFamily:'var(--font-ui)' }}>Models</h2><span className="spacer"/></div>
    </div>
    <div className="objbody"><div className="card2 col" style={{ gap:'10px', alignItems:'flex-start' }}>
      <span className="k2">This project hasn't done model work yet</span>
      <span className="hint">Nothing has been trained or adapted here, and no run in this project has called a model — so normally this tab would not exist. It appears the first time the project does model work; until then the account registry is the Models entry in the workspace sidebar.</span>
      <span className="hint dim">The registry itself is account-level: a model trained in one project is callable from any of them. What a project shows is only what it actually uses — in a run's Methods, as “scored by admet-herg v3”.</span>
      <button className="btn sm ghost" onClick={() => onToast('Ask for model work in this project — “train a potency predictor on our assay data” — and the surface appears here as the run is configured.')}>How does it appear?</button>
    </div></div>
  </div>;
  return <div className="mainpane">
    <div className="objhead">
      <div className="crumb"><span>{project}</span><span className="sep">/</span><span>Models</span></div>
      <div className="objtitle">
        <h2 style={{ fontFamily:'var(--font-ui)' }}>Models</h2>
        <span className="chip acc">{REGISTRY.length} registered</span>
        {ws && <span className="chip">account-level</span>}
        <span className="spacer"/>
        <button className="btn sm ghost" onClick={() => onToast(ws
          ? 'The registry is account-level, so every model is reachable here. Training, tuning and inference belong to a project, because they consume that project\u2019s data under its instructions.'
          : 'Training, tuning and inference sit in the project because they consume the project\u2019s data and are governed by its instructions. The registry underneath is shared across the account.')}>{ws ? 'Why is training in projects?' : 'Why is this in the project?'}</button>
      </div>
      {ws && <span className="hint">Every model in the account, and where each is used. To train, tune or run one against data, open the project that holds the data — the surface appears there the first time that project does model work.</span>}
      <div className="tabs2">{ML_TABS.map((t, i) => <button key={t} className={'tab2' + (i === tab ? ' on' : '')} onClick={() => setTab(i)}>{t}</button>)}</div>
    </div>
    <div className="objbody">
      {tab === 0 && <TrainTab onToast={onToast} onOpenRun={onOpenRun}/>}
      {tab === 1 && <AdaptTab onToast={onToast}/>}
      {tab === 2 && <OptimiseTab onToast={onToast} onOpenModel={setModel} onOpenData={onOpenData}/>}
      {tab === 3 && <PretrainedTab onToast={onToast} onOpenRun={onOpenRun}/>}
      {tab === 4 && <InferTab onToast={onToast} onOpenModel={setModel}/>}
    </div>
  </div>;
}
Object.assign(window, { Models, TrainTab, AdaptTab, InferTab });
