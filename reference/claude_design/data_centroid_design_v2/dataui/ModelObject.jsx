/* The model object, the training configuration, and the Optimise loop.
   A model is presented like a dataset: identity, evidence, lineage, blast
   radius, interface, versions. Never a leaderboard, never a loss curve. */

function ConfBand({ level }) {
  return <span className={'confb ' + level}><span className="dot"/>{level} confidence</span>;
}

function ModelObject({ id, onBack, onToast, onOpenRun, onOpenData }) {
  const m = MODEL_CARDS[id];
  const [vtab, setVtab] = React.useState('evidence');
  if (!m) return null;
  const gates = m.evidence.filter(e => e[3]);
  const passed = gates.filter(e => e[3] === 'pass').length;
  return <div className="mainpane">
    <div className="objhead">
      <div className="crumb"><button className="linkish" onClick={onBack}>Models</button><span className="sep">/</span><span>Registry</span><span className="sep">/</span><span>{m.name}</span></div>
      <div className="objtitle">
        <h2 className="mono" style={{ fontSize:'19px' }}>{m.name} <span style={{ color:'var(--text-dim)' }}>{m.v}</span></h2>
        <span className="chip">{m.family}</span>
        <ConfBand level={m.conf}/>
        <span className="spacer"/>
        <button className="btn sm ghost" onClick={() => onToast('Supersede: train a new version. The current one stays callable until a consumer moves to the new version.')}>Supersede</button>
        <button className="btn sm" onClick={() => onToast('Call this model from a workflow gate, a score column, or an optimisation loop.')}>Use in a run</button>
      </div>
      <div className="modelsub">
        <span className="hint">{m.goal}</span>
        <span className="hint dim">{m.origin} · {m.state}</span>
      </div>
      <div className="tabs2">
        {[['evidence', 'Evidence'], ['lineage', 'Lineage'], ['used', 'Used by'], ['iface', 'Interface'], ['versions', 'Versions']].map(([k, l]) =>
          <button key={k} className={'tab2' + (vtab === k ? ' on' : '')} onClick={() => setVtab(k)}>{l}</button>)}
      </div>
    </div>
    <div className="objbody">
      {vtab === 'evidence' && <>
        <div className="card2 col" style={{ gap:'10px' }}>
          <div className="row ac"><span className="k2">Held-out evidence</span><span className="spacer"/>
            <span className="chip ok"><span className="dot"/>{passed} of {gates.length} gates passed</span></div>
          <div className="col" style={{ gap:'0' }}>
            {m.evidence.map(([k, val, thr, verdict]) => <div key={k} className="evrow">
              <span className="hint">{k}</span>
              <span className="mono evval">{val}</span>
              <span className="hint dim">{thr}</span>
              {verdict ? <span className={'chip ' + (verdict === 'pass' ? 'ok' : 'err')}><span className="dot"/>{verdict}</span> : <span/>}
            </div>)}
          </div>
          <span className="hint">A floor, not a ranking. Clearing it by more does not make a model better, and there is no leaderboard to climb.</span>
        </div>
        <div className="card2 col" style={{ gap:'8px' }}>
          <span className="k2">What this model is not evidence for</span>
          <span className="hint">Outside the applicability region above, a prediction is reported with low confidence and does not satisfy a gate. Confidence travels with every predicted value, into tables, reports and proposals.</span>
        </div>
      </>}
      {vtab === 'lineage' && <div className="card2 col" style={{ gap:'10px' }}>
        <span className="k2">Where this model came from</span>
        <div className="col" style={{ gap:'0' }}>
          {m.lineage.map(([k, v, note]) => <div key={k} className="linrow">
            <span className="hint dim">{k}</span>
            <button className="linkish" onClick={() => k === 'Dataset' ? onOpenData() : k === 'Training run' ? onOpenRun() : onToast('Opens that version of the model object.')}>{v}</button>
            <span className="hint dim">{note}</span>
          </div>)}
        </div>
        <span className="hint">Same lineage discipline as a dataset: the training run and the dataset version are objects, not strings in a description.</span>
      </div>}
      {vtab === 'used' && <div className="card2 col" style={{ gap:'10px' }}>
        <div className="row ac"><span className="k2">Consumers</span><span className="spacer"/><span className="hint dim">the blast radius of a version bump</span></div>
        <div className="col" style={{ gap:'7px' }}>
          {m.usedBy.map(([kind, where, how]) => <div key={where} className="qline">
            <span className="chip">{kind}</span>
            <span className="col" style={{ gap:'2px', minWidth:0 }}>
              <span style={{ fontSize:'12.5px', fontWeight:600 }}>{where}</span>
              <span className="hint dim">{how}</span>
            </span>
            <span className="spacer"/>
            <button className="linkish" onClick={() => onToast('Opens the surface that consumes this model.')}>open →</button>
          </div>)}
        </div>
        <span className="hint">Because consumers are listed, superseding is a decision with a visible cost rather than a silent change under a running campaign.</span>
      </div>}
      {vtab === 'iface' && <div className="card2 col" style={{ gap:'10px' }}>
        <span className="k2">Called as</span>
        <div className="row ac" style={{ gap:'9px', flexWrap:'wrap', rowGap:'6px' }}>
          <span className="chip acc">{m.iface[0]}</span><span className="mono" style={{ fontSize:'12px' }}>{m.iface[1]}</span>
        </div>
        <span className="hint">{m.iface[2]}</span>
        <span className="hint dim">The pipeline calls the registry, not the implementation — so a lab's own model drops in without rewriting a workflow.</span>
      </div>}
      {vtab === 'versions' && <div className="card2 col" style={{ gap:'10px' }}>
        <span className="k2">Versions</span>
        <div className="col" style={{ gap:'0' }}>
          {m.versions.map(([v, when, res, st]) => <div key={v} className={'vrow' + (st === 'current' ? ' cur' : '')}>
            <span className="mono" style={{ fontWeight:600 }}>{v}</span>
            <span className="hint dim">{when}</span>
            <span className="hint">{res}</span>
            <span className={'chip ' + (st === 'current' ? 'ok' : '')}>{st}</span>
            <button className="linkish" onClick={() => onToast('Compares this version against the current one on the same held-out set.')}>compare</button>
          </div>)}
        </div>
        <span className="hint">Superseding never deletes. A completed run keeps the exact version it called, so an old report stays reproducible.</span>
      </div>}
    </div>
  </div>;
}

/* The only two new decisions in a training run: which dataset, and whether to
   register. Everything after Start is the run surface. */
function TrainConfig({ onClose, onToast, onOpenRun }) {
  const c = TRAIN_CFG;
  return <div className="card2 col" style={{ gap:'11px' }}>
    <div className="row ac"><span className="k2">New training run</span><span className="spacer"/>
      <button className="zoomb" onClick={onClose}><Icon name="x" size={11}/></button></div>
    <div className="intentbar small">
      <Icon name="sparkles" size={14}/>
      <input className="intentin" defaultValue={c.goal} onChange={() => {}}/>
    </div>
    <div className="col" style={{ gap:'0' }}>
      {c.slots.map(([k, v, note]) => <div key={k} className="evrow">
        <span className="hint">{k}</span><span className="mono evval">{v}</span><span className="hint dim">{note}</span><span/>
      </div>)}
    </div>
    <div className="inline-params wide">
      {c.params.map(([k, v, src, why]) => <div className="inline-row" key={k}>
        <div className="k">{k}<span className={'srcb ' + src}>{src}</span></div>
        <div className="ipv"><input defaultValue={v}/></div>
        {why && <div className="ipwhy">{why}</div>}
      </div>)}
    </div>
    <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
      <button className="btn sm accent" onClick={() => { onToast('Training started. It runs on the run surface — same phases, same gates, same step views as a workflow.'); onOpenRun(); }}><Icon name="play" size={10}/>Start training</button>
      <button className="btn sm ghost" onClick={onClose}>Cancel</button>
      <span className="spacer"/>
      <span className="hint dim">A passing model is offered for registration, never registered silently.</span>
    </div>
  </div>;
}

/* Optimise — the closed loop, as rounds. Moved out of Adapt: adapting how
   BioMate writes and optimising a compound series are different jobs. */
/* The wet-lab round — how external bench data gets back into the loop.
   Four things the UI has to be honest about: latency, mapping, partial
   returns, and censored values. */
function WetLabRound({ onToast, onOpenData }) {
  const w = WETLAB;
  const [tab, setTab] = React.useState('returns');
  const measured = w.returns.filter(r => r[2] === 'measured').length;
  const noData = w.returns.length - measured;
  return <div className="card2 col" style={{ gap:'11px' }}>
    <div className="row ac" style={{ gap:'9px', flexWrap:'wrap', rowGap:'6px' }}>
      <span className="k2">Wet-lab round {w.round}</span>
      <span className="chip warn"><span className="dot pulse"/>{w.state}</span>
      <span className="spacer"/>
      <span className="hint dim">{w.back} of {w.total} back</span>
      <button className="btn sm" onClick={() => onToast('Upload a plate export. The saved mapping template is applied, and you see a diff of anything it could not match before it is accepted.')}><Icon name="download" size={11}/>Add results</button>
    </div>
    <div className="wlbar">
      {[['Proposed', 'done'], ['Ordered', 'done'], ['At the bench', 'now'], ['Results in', w.back ? 'part' : ''], ['Refit', w.back ? 'part' : ''], ['Round 5', '']].map(([k, st]) =>
        <span key={k} className={'wlstep ' + st}><span className="wldot"/>{k}</span>)}
    </div>
    <div className="row ac" style={{ gap:'10px', flexWrap:'wrap', rowGap:'4px' }}>
      <span className="hint dim">{w.ordered}</span><span className="hint dim">·</span><span className="hint">{w.due}</span>
      <span className="spacer"/>
      <button className="linkish" onClick={() => onToast('Exports the order sheet and plate map in the format your lab registers from — platform candidate ids paired with your registry ids, so identity survives the round trip.')}>export order sheet →</button>
    </div>

    <div className="trackbar">
      {[['returns', 'What came back'], ['routes', 'How results get in'], ['mapping', 'Mapping template'], ['refit', 'Refit']].map(([k, l]) =>
        <button key={k} className={'trackb' + (tab === k ? ' on' : '')} onClick={() => setTab(k)}>{l}</button>)}
    </div>

    {tab === 'returns' && <div className="col" style={{ gap:'7px' }}>
      <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'5px' }}>
        <span className="chip ok"><span className="dot"/>{measured} measured</span>
        <span className="chip warn"><span className="dot"/>{noData} returned no data</span>
        <span className="spacer"/>
        <span className="hint dim">every proposal accounted for</span>
      </div>
      {w.returns.map(([id, val, kind, note]) => <div key={id} className="wlrow">
        <span className="mono" style={{ fontWeight:600, fontSize:'12px' }}>{id}</span>
        <span className={'mono' + (kind === 'measured' ? '' : ' dim')} style={{ fontSize:'11.5px' }}>{val}</span>
        <span className={'chip ' + (kind === 'measured' ? 'ok' : 'warn')}>{kind}</span>
        <span className="hint dim">{note}</span>
      </div>)}
      <span className="hint">A proposal that produced no number still returns a <b>reason</b>. Dropping those rows would train the surrogate on survivors only, and it would quietly learn that everything it proposes gets made.</span>
      <span className="hint dim">Censored values stay censored: <span className="mono">IC50 &gt; 30 µM</span> is fitted as an inequality, never as 30.</span>
    </div>}

    {tab === 'routes' && <div className="col" style={{ gap:'7px' }}>
      {w.routes.map(([k, what, how, state]) => <div key={k} className="qline">
        <span className="chip acc">{k}</span>
        <span className="col" style={{ gap:'2px', minWidth:0 }}>
          <span className="hint" style={{ color:'var(--text)' }}>{what}</span>
          <span className="hint dim">{how}</span>
        </span>
        <span className="spacer"/>
        <span className={'chip ' + (/connected|used/.test(state) ? 'ok' : '')}>{state}</span>
      </div>)}
      <span className="hint">Every route lands in the same place: a dataset object in this project, with the instrument or system as its origin and a version per pull (Files → Where it came from).</span>
      <button className="btn sm ghost" style={{ alignSelf:'flex-start' }} onClick={onOpenData}>Open the results dataset →</button>
    </div>}

    {tab === 'mapping' && <div className="col" style={{ gap:'8px' }}>
      <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'5px' }}>
        <span className="chip">{w.mapping.name}</span><span className="hint dim">saved {w.mapping.saved}</span>
        <span className="spacer"/>
        <button className="linkish" onClick={() => onToast('Edit the template. Changing it re-maps future uploads only — results already ingested keep the mapping they were read with.')}>edit</button>
      </div>
      <div className="col" style={{ gap:'0' }}>
        {w.mapping.cols.map(([k, v, note]) => <div key={k} className="evrow">
          <span className="hint">{k}</span><span className="mono evval">{v}</span><span className="hint dim">{note}</span><span/>
        </div>)}
      </div>
      <span className="hint">Mapped once per assay type, then applied automatically. An upload that does not fit the template is held and shown as a diff — it is never silently coerced into the columns the loop wanted.</span>
    </div>}

    {tab === 'refit' && <div className="col" style={{ gap:'8px' }}>
      <div className="col" style={{ gap:'0' }}>
        {[['Policy', w.refit.policy, 'partial results are useful; waiting for all 12 wastes a week'],
          ['Last refit', w.refit.last, ''],
          ['Effect', w.refit.effect, 'held-out, on the same evaluation set'],
          ['Produces', w.refit.next, 'a new model version, gated before it scores anything']].map(([k, v, note]) =>
          <div key={k} className="evrow"><span className="hint">{k}</span><span className="mono evval">{v}</span><span className="hint dim">{note}</span><span/></div>)}
      </div>
      <div className="row" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
        <button className="btn sm" onClick={() => onToast('Refit queued on the 7 returned results. It runs as a tracked training run with its own gate, and the new version does not score until it passes.')}>Refit on what is back</button>
        <button className="btn sm ghost" onClick={() => onToast('The round closes, unreturned proposals are recorded as no-data with their reasons, and round 5 is proposed from the refitted surrogate.')}>Close round &amp; propose next</button>
      </div>
      <span className="hint dim">A refit is a training run, so it inherits the run surface, its gates and its audit trail — nothing about the loop is exempt from the evidence rules.</span>
    </div>}
  </div>;
}

function OptimiseTab({ onToast, onOpenModel, onOpenData }) {
  const [loop, setLoop] = React.useState(DMTA.state === 'running');
  return <>
    <div className="card2 col" style={{ gap:'11px' }}>
      <div className="row ac" style={{ flexWrap:'wrap', rowGap:'6px' }}><span className="k2">Design · make · test · analyse</span><span className="spacer"/>
        <span className={'chip ' + (loop ? 'ok' : '')}><span className={'dot' + (loop ? ' pulse' : '')}/>{loop ? 'running · round ' + DMTA.round : 'stopped'}</span>
        <button className="btn sm ghost" onClick={() => { setLoop(l => !l); onToast(loop ? 'Loop stopped. Nothing refits until you start it again.' : 'Loop started — it refits under the policy below.'); }}>{loop ? 'Stop loop' : 'Start loop'}</button>
        <button className="btn sm ghost" onClick={() => onToast('Immediate refit queued on the current assay results.')}>Refit now</button></div>
      <div className="loopmeta">
        <div className="lm"><span className="hint dim">Surrogate</span><span className="row ac" style={{ gap:'6px', flexWrap:'wrap' }}>
          <button className="linkish mono" onClick={() => onOpenModel('admet-herg')}>admet-herg v3</button><span className="hint dim">+</span>
          <button className="linkish mono" onClick={() => onOpenModel('potency-gp')}>potency-gp v2</button></span></div>
        <div className="lm"><span className="hint dim">Budget</span><span className="hint">96 assays per round · set by you, never inferred</span></div>
        <div className="lm"><span className="hint dim">Refit policy</span><span className="hint">{WETLAB.refit.policy}</span></div>
      </div>
      <div className="rounds">
        {DMTA.rounds.map(([r, st, what, when]) => <div key={r} className="round">
          <span className="rdot"/><span style={{ fontSize:'12.5px', fontWeight:600 }}>{r}</span>
          <span className="chip">{st}</span><span className="hint">{what}</span><span className="hint dim">{when}</span>
        </div>)}
      </div>
    </div>
    <div className="card2 col" style={{ gap:'9px' }}>
      <div className="row ac"><span className="k2">Round {DMTA.round} proposal</span><span className="spacer"/>
        <span className="hint dim">steerable before anything is ordered</span></div>
      {DMTA.proposal.map(([id, sc, conf, verdict]) => <div key={id} className="prop">
        <span className="mono" style={{ fontSize:'12px', fontWeight:600 }}>{id}</span>
        <span className="hint">{sc}</span>
        <ConfPill level={conf.split(' ')[0]}/>
        <span className={'chip ' + (verdict === 'accepted' ? 'ok' : verdict.includes('rejected') ? 'err' : 'warn')}><span className="dot"/>{verdict}</span>
        <button className="linkish" onClick={() => onOpenModel('admet-herg')}>why?</button>
      </div>)}
      <span className="hint">A rejected proposal stays on the list with its reason. You must be able to see what the loop wanted to do and why it was not allowed to.</span>
    </div>
    <WetLabRound onToast={onToast} onOpenData={onOpenData || (() => onToast('Opens the results dataset.'))}/>
  </>;
}
Object.assign(window, { ModelObject, TrainConfig, OptimiseTab, ConfBand, WetLabRound });
