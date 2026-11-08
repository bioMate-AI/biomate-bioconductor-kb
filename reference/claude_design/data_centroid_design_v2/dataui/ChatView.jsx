/* Chat surface — empty state (option C1), composer affordances (option B1), and the
   right panel with its new Data mode (option B2). */

/* The lane sentence per lane. One source, keyed by the lane the router
   returns — the preview must never be able to disagree with the router. */
const LANE_COPY = {
  'Instant · search':['Instant · cited answer', 'I will answer from literature and curated databases, with every claim cited.'],
  'Instant · compute':['Instant · compute', 'I will write and run code on your attached data in a sandbox and show you the code.'],
  'Cloud · workflow':['Cloud · validated workflow', 'This reads like a standardised analysis — a validated pipeline with quality gates and an audit-ready report. Typically tens of minutes.'],
  'Cloud · design':['Cloud · design', 'This reads like design work — candidates generated, scored and ranked, with the trade-off shown rather than collapsed into one number. Typically tens of minutes.'],
  'Cloud · models':['Cloud · models', 'This reads like model work — it produces a model or a prediction, with the model and version named on the result. Typically minutes to hours.']
};
/* Where a lane covers several modalities, the sentence follows the matched
   domain so the chip and the sentence say the same thing. */
const DOM_COPY = {
  'Peptide design':'This reads like peptide design — sequences proposed and scored against binding, stability and permeability together. Typically tens of minutes.',
  'Protein & biologic design':'This reads like protein or biologic design — designs proposed and filtered on structure, developability and expression risk. Typically tens of minutes.'
};
function LanePreview({ text }) {
  const t = (text || '').trim();
  if (!t) return null;
  const hit = (window.ROUTES || []).find(r => r.m.test(t));
  const lane = hit ? hit.lane : 'Instant · search';
  const sentence = (hit && DOM_COPY[hit.dom]) || (LANE_COPY[lane] || LANE_COPY['Instant · search'])[1];
  const isCloud = /^Cloud/.test(lane);
  return <div className="lanepreview">
    <div className="row ac" style={{ gap:'9px', flexWrap:'wrap', rowGap:'5px' }}>
      <span className={'lanedot ' + (isCloud ? 'cloud' : 'instant')}/>
      {hit && <span className="chip">{hit.dom}</span>}
      <span className="hint">{sentence}</span>
    </div>
    <div className="row wrap" style={{ gap:'6px' }}>
      <span className="chip">{isCloud ? 'answer it instantly instead' : 'run a validated pipeline instead'}</span>
      <span className="chip">why this?</span>
    </div>
  </div>;
}

function Composer({ value, onChange, onSend, projectOn, onDeviate, onToast, laneHint, instrCount, onOpenInstr, project }) {
  const [openEx, setOpenEx] = React.useState(false);
  /* What is on here comes from the project (Instructions → Skills & experts).
     A deviation is per-question and does not change the project. */
  const [dev, setDev] = React.useState({});
  React.useEffect(() => { setDev({}); }, [project]);
  const isOn = n => (n in dev ? dev[n] : !!(projectOn || {})[n]);
  const list = (window.ACCOUNT_ADDONS || []);
  const onCount = list.filter(isOn).length;
  const deviated = Object.keys(dev).filter(n => dev[n] !== !!(projectOn || {})[n]).length;
  return <div className="composerwrap">
    {laneHint && <LanePreview text={value}/>}
    <div className="composer2">
      <textarea value={value} placeholder="What would you like to analyze?" onChange={e => onChange(e.target.value)}
        onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); onSend(); } }}/>
      <div className="crow">
        <button className="btn sm ghost" onClick={() => onToast('Ingest panel: drop files, paste a URL, or browse public repositories — with the quality card shown before anything runs.')}><Icon name="paperclip" size={13}/> data</button>
        <div className="expwrap">
          <button className="btn sm" onClick={() => setOpenEx(v => !v)} style={{ borderColor:'var(--accent)', color:'var(--accent-ink)', background:'var(--accent-soft)' }}>Skills &amp; experts · {onCount} on{deviated ? ' · changed' : ''} ▾</button>
          {openEx && <div className="expop">
            <span className="k2">On in {project}</span>
            <span className="hint">Set on the project's Instructions page. Change one here and it applies to this question only.</span>
            <div className="expoplist">
            {list.map(p => { const pd = !!(projectOn || {})[p]; const on = isOn(p); return <label key={p} className="row ac" style={{ gap:'8px', fontSize:'12.5px', cursor:'pointer' }}>
              <input type="checkbox" checked={on} onChange={() => { setDev(d => ({ ...d, [p]:!on })); onDeviate && onDeviate(p, !on); }}/>
              <span style={{ minWidth:0 }}>{p}</span>
              {pd && <span className="hint dim expbadge">project</span>}
            </label>; })}
            </div>
            {!onCount && <span className="hint dim">Nothing is on in this project yet.</span>}
          </div>}
        </div>
        <button className="btn sm" onClick={() => onToast('Lane override: Ask · Compute · Workflow. Three choices — an override of the router, not a menu of everything.')}>Lane: auto ▾</button>
        {instrCount ? <button className="btn sm ghost" onClick={onOpenInstr} title={'Standing instructions from ' + project + ' are in context'}><Icon name="file" size={12}/>{instrCount}</button> : null}
        <span className="sendgrp"><span className="kbd">⏎</span>
        <button className="btn sm accent" onClick={onSend}><Icon name="send" size={13}/></button></span>
      </div>
    </div>
  </div>;
}

function EmptyState({ style, onSeed, thin, setThin, onToast, experts, scope }) {
  if (style === 'modules') return <ModuleDash onSeed={onSeed} onToast={onToast} thin={thin} setThin={setThin} experts={experts} scope={scope}/>;
  if (style === 'chips') return <div className="emptystate">
    <span className="hint">Input your use case here</span>
    <div className="row wrap" style={{ justifyContent:'center', gap:'8px' }}>
      {['MG patient stratification → ADMET', 'ADMET screen from SMILES', 'RNA-seq differential expression', 'Variant calling on WGS sample'].map(c =>
        <button key={c} className="btn sm" onClick={() => onSeed(c)}>{c}</button>)}
    </div>
    <span className="hint dim" style={{ maxWidth:'46ch', textAlign:'center' }}>Today's empty state: four chips, no sense of reach. Switch the tweak to compare.</span>
  </div>;
  return <div className="emptystate">
    <div className="col" style={{ alignItems:'center', gap:'5px' }}>
      <span style={{ fontSize:'17px', fontWeight:600, letterSpacing:'-0.02em' }}>What are you working on?</span>
      <span className="hint">Pick the closest — or say it in your own words below.</span>
    </div>
    <div className="tilegrid">
      {EMPTY_TILES.map(t => <button key={t.d} className="tile" onClick={() => onSeed(t.seed)}>
        <span className="k2">{t.d}</span>
        <span className="tq">{t.q}</span>
        <span className="spacer"/>
        {t.tier === 'cloud' ? <span className="chip ok" style={{ fontSize:'10px' }}><span className="dot"/>validated pipeline</span>
          : t.tier === 'instant' ? <span className="chip run" style={{ fontSize:'10px' }}><span className="dot"/>instant</span>
          : <span className="chip" style={{ fontSize:'10px' }}>routed automatically</span>}
      </button>)}
    </div>
  </div>;
}

function ChatView({ started, seed, setSeed, onSend, onOpenData, empty, laneHint, projectOn, onDeviate, onToast, session, project, onOpenProjectData, instrCount, onOpenInstr, scoped, onPromote, thin, setThin, suggest, onFile, revealPanel, revealLabel, onPick, onHide }) {
  const sdata = (session && session.data) || [];
  return <div className="mainpane">
    <div className="topbar">
      <span className="col" style={{ gap:'2px', minWidth:0 }}>
        {scoped && project && <span className="chatcrumb">
          <Icon name="folder" size={10}/>
          <button className="crumblink" onClick={onOpenProjectData}>{project}</button>
          <span className="sep">/</span>
          <span className="dim">{session ? 'chat' : 'new chat'}</span>
          {project === 'Unfiled (scratch)' && <><span className="chip warn sm">unfiled</span><button className="crumblink acc" onClick={onPromote}>promote to a project</button></>}
        </span>}
        <span className="title">{session ? session.title : 'New chat'}</span>
      </span>
      <span className="spacer"/>
      {revealPanel && <button className="btn sm revealbtn" onClick={revealPanel} title={'Show the ' + revealLabel}><Icon name="chevronLeft" size={12}/><span className="btnlabel">{revealLabel}</span></button>}
      {onHide && <button className="btn sm ghost" onClick={onHide} title="Hide the chat and give the run its full width"><Icon name="chevronLeft" size={12}/><span className="btnlabel">Hide chat</span></button>}
      <button className="btn sm ghost" onClick={() => onToast('Run Manager: an inventory of runs — unchanged by this proposal.')} title="Run Manager"><Icon name="beaker" size={13}/><span className="btnlabel">Run Manager</span> <span className="chip run">1</span></button>
      <button className="btn sm ghost" onClick={() => onToast('Refresh — unchanged by this proposal.')}><Icon name="refresh" size={13}/></button>
    </div>
    {started ? <div className="chatscroll"><div className="chatinner">
      {CHAT_TAPE.map((m, i) => <div key={i} className="turn">
        <span className="who">{m.who === 'you' ? 'You' : 'BioMate'}</span>
        {m.who === 'you' ? <div className="bubble">{m.text}{m.chips && <div className="row wrap" style={{ gap:'6px', marginTop:'8px' }}>{m.chips.map(c => <DataChip key={c} id={c} onClick={onOpenData} note={c === 'd1' ? 'from GEO' : null}/>)}</div>}</div>
          : <div className="col" style={{ gap:'9px' }}>
            {m.text && <span className="said">{md(m.text)}</span>}
            {m.kind === 'mapping' && <div className="mapcard">
              <div className="mh"><span className="k2">Inputs mapped</span><span className="spacer"/><span className="chip">click a file to see where it came from</span></div>
              {RUNS[m.run].inputs.map(([slot, did, conf, why]) => <div key={slot} className="slot">
                <span className="sname">{slot}</span><DataChip id={did} onClick={onOpenData}/><span className="spacer"/><ConfPill level={conf}/>
              </div>)}
              <div className="slot" style={{ background:'var(--surface)' }}><span className="hint">“{RUNS[m.run].inputs[1][3]}” — the reason travels with the badge, everywhere it appears.</span></div>
            </div>}
            {m.kind === 'steps' && <div className="steplog">{m.steps.map(([s, t], j) => <div key={j} className="sl"><span className={'chip ' + (s === 'ok' ? 'ok' : 'warn')}><span className="dot"/></span>{t}</div>)}</div>}
            {m.kind === 'result' && <div className="row wrap" style={{ gap:'7px' }}>{m.outputs.map(o => OUTPUTS[o].isDataset
              ? <DataChip key={o} id={o} onClick={onOpenData}/>
              : <span key={o} className="chip">{OUTPUTS[o].kind} · {OUTPUTS[o].name}</span>)}</div>}
          </div>}
      </div>)}
    </div></div> : seed.trim() ? <div style={{ flex:1, minHeight:0, overflow:'auto', display:'flex' }}>
      <div className="emptystate" style={{ maxWidth:'620px' }}>
        <div className="card2 col" style={{ gap:'8px', width:'100%' }}>
          <span className="k2">Ready to send</span>
          <span className="said">{seed}</span>
          <span className="hint">Attach data if it needs your files, or edit the wording below — nothing has run yet.</span>
        </div>
        <button className="btn sm ghost" onClick={() => setSeed('')}>Clear and see suggestions</button>
      </div>
    </div>
    : <div style={{ flex:1, minHeight:0, overflow:'auto', display:'flex' }}><EmptyState style={empty} onSeed={onPick || setSeed} thin={thin} setThin={setThin} onToast={onToast} experts={Object.values(projectOn || {}).filter(Boolean).length} scope={scoped ? project : null}/></div>}
    {suggest && !started && <div className="suggestrow">
      <Icon name="folder" size={13}/>
      <span className="col" style={{ gap:'2px', minWidth:0 }}>
        <span style={{ fontSize:'12.5px', fontWeight:600 }}>This reads like <b>{suggest.name}</b></span>
        <span className="hint dim">Filing it there puts {suggest.why} in context. Nothing runs either way.</span>
      </span>
      <span className="spacer"/>
      <button className="btn sm" onClick={() => onFile(suggest.name)}>File it there</button>
      <button className="btn sm ghost" onClick={() => onToast('Left unfiled. It stays in the scratch project, and you can promote it at any time — the chat, its files and any run move together.')}>Keep unfiled</button>
    </div>}
    <Composer value={seed} onChange={setSeed} onSend={onSend} projectOn={projectOn} onDeviate={onDeviate} onToast={onToast} laneHint={laneHint}
      instrCount={instrCount} onOpenInstr={onOpenInstr} project={project}/>
  </div>;
}

/* ── right panel — the shipped structure (Workflow settings · Phases ·
   After run) with one section tab added: Data. Nothing else moves. ── */
const GLOBAL_PARAMS = [
  ['Input', 'GSE184880_counts.tsv', 'from your message'],
  ['Design', '~ condition', 'from your message'],
  ['Reference level', 'control', 'inferred'],
  ['Species / build', 'human · GRCh38', 'from your message'],
  ['LFC shrinkage', 'apeglm', 'default'],
  ['Alpha', '0.05', 'default']
];
const PHASES = [
  ['A', 'Input & preparation', 'completed', 2, 'nf-core/rnaseq · 24 samples aligned'],
  ['B', 'Differential abundance', 'completed', 3, 'DESeq2 Wald · apeglm shrinkage'],
  ['C', 'Enrichment & report', 'completed', 2, 'clusterProfiler gseGO · report written']
];
const AFTER_TABS = ['Findings', 'Outputs', 'Methods', 'Parameters', 'Software', 'Citations', 'QC audit'];

function RightPanel({ mode, setMode, dsId, onClose, onOpenFull, onToast, showInherit }) {
  const [sect, setSect] = React.useState('after');
  const [at, setAt] = React.useState(1);
  const run = RUNS.r1;
  const ds = DATASETS.find(d => d.id === dsId) || DATASETS[0];
  React.useEffect(() => { setSect(mode === 'data' ? 'data' : 'after'); }, [mode, dsId]);
  const go = s => { setSect(s); setMode(s === 'data' ? 'data' : 'run'); };
  const ROW1 = [['settings', 'Workflow settings', GLOBAL_PARAMS.length], ['phases', 'Phases', PHASES.length]];
  const ROW2 = [['after', 'After run', null]];
  const Tab = ([id, label, n]) => <button key={id} className={'sectab' + (sect === id ? ' on' : '')} onClick={() => go(id)}>
    {label}{n != null && <span className="sn">{n}</span>}
  </button>;

  return <div className="panel">
    <div className="paneltop">
      <div className="row ac" style={{ gap:'8px' }}>
        <span className="k2">Workflow</span><span className="spacer"/>
        <StatusPill s={run.status}/>
        <button className="btn sm ghost" onClick={onClose}><Icon name="x" size={13}/></button>
      </div>
      <span className="wfname">Bulk RNA-seq Differential Expression Analysis</span>
    </div>
    {sect !== 'data' && <>
      <div className="sectabs">{ROW1.map(Tab)}</div>
      <div className="sectabs row2">{ROW2.map(Tab)}<span className="spacer"/><span className="hint dim" style={{ fontSize:'11px' }}>{run.status === 'completed' ? 'report ready' : ''}</span></div>
    </>}
    {sect === 'data' && <div className="datasheet-hd"><span className="k2">Dataset</span><span className="spacer"/><span className="chip">{ds.kind}</span></div>}

    <div className="panelbody">
      {sect === 'settings' && <div className="col" style={{ gap:'2px' }}>
        {GLOBAL_PARAMS.map(([k, v, prov]) => <div key={k} className="paramrow">
          <span className="pk">{k}</span>
          <span className="pv">{v}</span>
          <span className={'prov' + (prov === 'from your message' ? ' msg' : '')}>{prov}</span>
          <button className="linkish" onClick={() => onToast('Edit “' + k + '” in workflow settings.')}>edit</button>
        </div>)}
        <span className="hint" style={{ marginTop:'8px' }}>Unchanged surface — shown so the added Data tab can be judged in context.</span>
      </div>}

      {sect === 'phases' && <div className="col" style={{ gap:'8px' }}>
        {PHASES.map(([id, name, st, steps, summary]) => <div key={id} className="card2 col" style={{ gap:'7px' }}>
          <div className="row ac" style={{ gap:'9px' }}><span className="phletter">{id}</span><span style={{ fontWeight:600, fontSize:'13px' }}>{name}</span><span className="spacer"/><span className="chip">{steps} steps</span><StatusPill s={st}/></div>
          <span className="hint">{summary}</span>
        </div>)}
        <div className="card2 col" style={{ gap:'6px' }}>
          <span className="k2">QC gate · phase B</span>
          <div className="row ac" style={{ gap:'8px' }}><span className="chip warn"><span className="dot"/>2 samples excluded</span><span className="hint">library size below floor — auto-loop off</span></div>
        </div>
      </div>}

      {sect === 'after' && <div className="col" style={{ gap:'10px' }}>
        <div className="row ac"><span className="k2">After run</span><span className="spacer"/><button className="linkish" onClick={() => onToast('Download report — unchanged by this proposal.')}>↓ Download report</button></div>
        <div className="aftertabs">{AFTER_TABS.map((x, i) => <button key={x} className={'atab' + (i === at ? ' on' : '')} onClick={() => setAt(i)}>{x}</button>)}</div>
        {at === 0 && <div className="card2 col" style={{ gap:'8px' }}>
          <div className="row ac" style={{ gap:'7px', flexWrap:'wrap', rowGap:'5px' }}><span className="chip acc"><Icon name="file" size={11}/>Internal target-triage memo</span><span className="hint">written to the project template · v3</span></div>
          <span className="hint"><b>412 genes</b> move at FDR &lt; 0.05 (DESeq2 Wald); the response is dominated by interferon signalling. Two low-depth samples were excluded at gate 3, as the project instructions require, and the effect survives their removal.</span>
          <span className="hint dim">Findings wording and length follow the project's output requirement; exclusions are listed because a standing instruction says they must be.</span>
        </div>}
        {at === 1 && <div className="col" style={{ gap:'8px' }}>
          {run.outputs.map(o => <div key={o} className="card2 row ac" style={{ gap:'9px', padding:'10px 12px', flexWrap:'wrap', rowGap:'6px' }}>
            <span className="chip">{OUTPUTS[o].kind}</span><span className="mono" style={{ fontSize:'12px' }}>{OUTPUTS[o].name}</span><span className="spacer"/>
            {showInherit && <span className="chip warn"><span className="dot"/>watch</span>}
            {OUTPUTS[o].isDataset
              ? <button className="btn sm" onClick={() => go('data')}>open as dataset →</button>
              : <button className="btn sm ghost" onClick={() => onToast('view · download — unchanged by this proposal.')}>view</button>}
          </div>)}
          <span className="hint"><b>The change here:</b> an output that is data links to its dataset object, and carries the weakest upstream badge instead of presenting a clean file.</span>
        </div>}
        {at > 1 && <div className="card2 col" style={{ gap:'7px' }}>
          <span className="k2">{AFTER_TABS[at]}</span>
          <span className="hint">Existing after-run tab — unchanged by this proposal. {AFTER_TABS[at] === 'QC audit' ? 'The chain of quality and confidence badges is the audit record, and it is what the Data tab exports as a deposit bundle.' : 'Shown so the added Data tab can be judged against the real panel structure.'}</span>
        </div>}
      </div>}

      {sect === 'data' && <div className="col" style={{ gap:'12px' }}>
        <div className="row ac" style={{ gap:'8px' }}>
          <button className="btn sm ghost" onClick={() => go('after')}><Icon name="chevronLeft" size={13}/>Back to the run</button>
          <span className="spacer"/><span className="chip">opened from a file in the conversation</span>
        </div>
        <div className="card2 col" style={{ gap:'8px' }}>
          <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}><span className="mono" style={{ fontSize:'12.5px', fontWeight:500 }}>{ds.name}</span><span className="spacer"/><QPill q={ds.quality} compact/></div>
          <span className="hint">{ds.stats[0][1]} × {ds.stats[1][1]} · {ds.stats[2][1]} missing · {ds.origin.label}</span>
          {ds.qnotes.slice(0, 2).map(([q, x], i) => <span key={i} className="hint" style={{ display:'flex', gap:'7px' }}><QPill q={q} compact/>{x}</span>)}
        </div>
        <LineageVertical dsId={ds.id} onOpenFull={onOpenFull} onToast={onToast}/>
        <div className="card2 col" style={{ gap:'7px' }}>
          <span className="k2">Same object, two sizes</span>
          <span className="hint">The panel borrows itself for a moment to show the file, then hands back to the run — no permanent tab, because a file is not part of the workflow's structure. The full view lives in the project's Files.</span>
          <button className="btn sm" onClick={onOpenFull}>Open in project Files →</button>
        </div>
      </div>}
    </div>

    <div className="panelfoot">
      <button className="btn wide" onClick={() => onToast('Restart — unchanged by this proposal.')}>Restart</button>
    </div>
  </div>;
}
Object.assign(window, { ChatView, RightPanel, Composer, EmptyState, LanePreview });
