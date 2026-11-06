/* Part 3 · Requirement A + D — the step deep-view.
   Any step opens into the same object: provenance, the parameters it actually
   ran with, and its outputs rendered by evidence class, raw data included. */

/* Status chip in the shipped panel's vocabulary (PhaseCard.jsx). */
function StatusChip({ status }) {
  const map = { pending:['','PENDING'], running:['run','RUNNING'], completed:['ok','DONE'], failed:['err','FAILED'], skipped:['','SKIPPED'] };
  const s = map[status] || map.pending;
  return <span className={'chip ' + s[0]}>{status === 'running' ? <span className="spinner"/> : <span className="dot"/>}{s[1]}</span>;
}

function EvBadge({ ev, compact }) {
  const e = EVIDENCE[ev] || EVIDENCE.procedural;
  return <span className="evb" style={{ background:e.soft, color:e.hue }} title={e.what}>
    <Icon name={e.icon} size={11}/>{compact ? null : e.label}
  </span>;
}

/* A quantitative artifact is rendered FROM its own bytes, so the table, the raw
   view and the summary can never disagree. */
function profFromRaw(raw) {
  const lines = raw.trim().split('\n').filter(Boolean);
  const cols = lines[0].split('\t');
  const rows = lines.slice(1).map(l => l.split('\t'));
  const num = j => rows.every(r => r[j] !== undefined && r[j] !== '' && !isNaN(Number(r[j])));
  const columns = cols.map((n, j) => {
    const vals = rows.map(r => r[j]);
    const uniq = new Set(vals).size;
    const t = num(j) ? (vals.every(v => Number.isInteger(Number(v))) ? 'integer' : 'float') : /^(true|false)$/i.test(vals[0]) ? 'boolean' : 'string';
    const bad = /^(false)$/i.test(vals.join('|').split('|')[0]) ? false : vals.some(v => /^false$/i.test(v) || v === '—');
    return { n, t, miss:0, uniq:uniq + ' distinct', bad, note:bad ? 'contains a failing or missing value' : '' };
  });
  return { cols, rows, columns };
}

function rawText(o) {
  if (o.raw) return o.raw;
  const p = o.table && PROFILES[o.table];
  if (p) return p.cols.join('\t') + '\n' + p.rows.map(r => r.join('\t')).join('\n');
  return '— binary artifact · download to inspect —';
}

function OutViewer({ o, raw, onToast }) {
  if (raw) return <div className="rawbox">
    <div className="rawhd"><span className="mono">{o.name}</span><span className="spacer"/><span className="hint dim">first bytes · as written by the step</span></div>
    <pre className="rawpre">{rawText(o)}</pre>
  </div>;
  const ev = o.ev;
  if (ev === 'perceptual') {
    const prof = PROFILES.d1, res = PROFILES.o1;
    return <div className="viewer">
      <div className="viewbar"><span className="hint dim">{o.meta}</span><span className="spacer"/>
        {['fit','100%','200%'].map(z => <button key={z} className={'zoomb' + (z === 'fit' ? ' on' : '')} onClick={() => onToast('Zoom ' + z + ' — the full artifact, not a thumbnail.')}>{z}</button>)}
        <button className="zoomb" onClick={() => onToast('Opens the artifact full-bleed; ⎋ returns to the step.')}><Icon name="eye" size={11}/>full</button>
      </div>
      <div className="viewstage">
        {o.plot === 'lib' && <Bars values={prof.libsize} labels={prof.libLabels} floor={prof.libFloor} unit=" M"/>}
        {o.plot === 'pca' && <Scatter points={prof.pca} xl="PC1 · 41%" yl="PC2 · 12%" legend={[['','control'],['g2','treated'],['flag','below the floor']]}/>}
        {o.plot === 'volcano' && <Scatter points={res.volcano} xl="log2 fold-change" yl="−log10 p" legend={[['sig','FDR < 0.05'],['','not significant']]}/>}
      </div>
    </div>;
  }
  if (ev === 'quantitative') {
    const prof = o.raw ? profFromRaw(o.raw) : (PROFILES[o.table] || PROFILES.d1);
    return <div className="viewer">
      <div className="viewbar"><span className="hint dim">{o.meta}{o.raw ? ' · first ' + prof.rows.length + ' rows' : ''}</span><span className="spacer"/>
        <button className="zoomb" onClick={() => onToast('Sort, filter and page — the shipped table viewer, at full size.')}><Icon name="table" size={11}/>sort &amp; filter</button></div>
      <EditableTable prof={prof} editing={false} onToast={onToast}/>
      <div className="colstats"><span className="k2">Column stats</span><ColumnProfile prof={prof}/></div>
    </div>;
  }
  if (ev === 'symbolic') {
    const recs = RECORDS[o.records] || RECORDS.design;
    return <div className="viewer">
      <div className="viewbar"><span className="hint dim">{o.meta}</span><span className="spacer"/>
        <button className="zoomb" onClick={() => onToast('Record browser — jump by identifier, or page through.')}><Icon name="search" size={11}/>find a record</button></div>
      <div className="reclist">{recs.map((r, i) => <div key={i} className="rec">
        <span className="mono recid">{r[0]}</span>{r.slice(1).map((c, j) => <span key={j} className={'hint' + (/exclu/.test(c) ? ' warnt' : '')}>{c}</span>)}
      </div>)}</div>
    </div>;
  }
  return <div className="viewer">
    <div className="viewbar"><span className="hint dim">{o.meta}</span><span className="spacer"/>
      <button className="zoomb" onClick={() => onToast('Follows the tail while the step runs.')}><Icon name="terminal" size={11}/>follow</button></div>
    <pre className="console">{o.raw || '—'}</pre>
  </div>;
}

/* Requirement A1 — the parameters one step ran with, editable in place.
   Same .inline-params vocabulary as the shipped panel; each row knows whether
   it is a default, a project-inherited value, or an override. */
function StepParams({ sk, onToast, onRerun, wide }) {
  const d = STEP_DEEP[sk];
  const [vals, setVals] = React.useState(() => d.params.map(p => p[1]));
  React.useEffect(() => { setVals(d.params.map(p => p[1])); }, [sk]);
  const dirty = vals.some((v, i) => v !== d.params[i][1]);
  return <div className={'inline-params' + (wide ? ' wide' : '')}>
    {d.params.map(([k, v, src, why], i) => <div className="inline-row" key={k}>
      <div className="k">{k}<span className={'srcb ' + src}>{src}</span></div>
      <div className="ipv">
        <input value={vals[i]} onChange={e => setVals(vs => vs.map((x, j) => j === i ? e.target.value : x))}/>
        {vals[i] !== v && <button className="linkish" onClick={() => setVals(vs => vs.map((x, j) => j === i ? v : x))}>revert</button>}
      </div>
      {why && <div className="ipwhy">{why}</div>}
    </div>)}
    <div className="row ac" style={{ gap:'8px', marginTop:'6px', flexWrap:'wrap', rowGap:'6px' }}>
      <span className="hint dim">{dirty ? 'Changed values re-run this step and everything downstream; upstream comes from cache.' : 'Values as resolved for this step.'}</span>
      <span className="spacer"/>
      <button className="btn sm" disabled={!dirty} onClick={() => { onToast('Saved on this step. It re-runs from here — the alternate output appears beside the original.'); onRerun && onRerun(); }}>Apply &amp; re-run from here</button>
    </div>
  </div>;
}

function StepDeep({ sk, phase, stepName, idx, total, status, mode, setMode, onClose, onToast, onOpenData, onRerun, onStep, focusOut }) {
  const d = STEP_DEEP[sk];
  const [oi, setOi] = React.useState(0);
  const [raw, setRaw] = React.useState(false);
  const [showP, setShowP] = React.useState(true);
  React.useEffect(() => { setOi(Math.max(0, focusOut ? d.outs.findIndex(o => o.id === focusOut) : 0)); setRaw(false); }, [sk, focusOut]);
  if (!d) return null;
  const o = d.outs[oi] || d.outs[0];
  const overrides = d.params.filter(p => p[2] === 'override').length;

  return <div className={'deep ' + mode}>
    <div className="deephd">
      <div className="row ac" style={{ gap:'8px' }}>
        <span className="phletter">{phase}</span>
        <span className="col" style={{ gap:'2px', minWidth:0 }}>
          <span className="hint dim">step {idx} of {total} · {phase} phase{status === 'skipped' ? ' · not run' : ''}</span>
          <span style={{ fontWeight:600, fontSize:'13.5px' }}>{stepName}</span>
        </span>
        <span className="spacer"/>
        <button className="zoomb" onClick={() => setMode(mode === 'drawer' ? 'full' : 'drawer')} title="full window or side drawer">
          <Icon name={mode === 'drawer' ? 'external' : 'chevronRight'} size={11}/>{mode === 'drawer' ? 'full window' : 'dock right'}</button>
        <button className="btn sm ghost" onClick={onClose}><Icon name="x" size={13}/></button>
      </div>
      <div className="provrow">
        <span className="hint dim">ran with</span>
        {d.inputs.length ? d.inputs.map(id => <DataChip key={id} id={id} onClick={onOpenData}/>) : <span className="chip">upstream step output</span>}
        <span className="pvarrow">→</span>
        <span className="chip">{d.tool} <span className="mono">{d.ver}</span></span>
        <span className="pvarrow">→</span>
        <span className="chip">{d.outs.length + ' output' + (d.outs.length > 1 ? 's' : '')}</span>
        <span className="spacer"/>
        <span className="hint dim mono">{d.dur}</span>
      </div>
    </div>

    <div className="deepbody">
      {status === 'skipped' ? <div className="card2 col" style={{ gap:'8px' }}>
        <span className="k2">This step was skipped</span>
        <span className="hint">Nothing ran, so there is no output to look at. Its last recorded outputs from the previous run are still readable, and re-running from here re-enables it.</span>
        <button className="btn sm" onClick={() => onRerun(sk)}>Re-run from this step</button>
      </div> : <>
        <div className="outtabs">
          {d.outs.map((x, i) => <button key={x.id} className={'outtab' + (i === oi ? ' on' : '')} onClick={() => { setOi(i); setRaw(false); }}>
            <EvBadge ev={x.ev} compact/><span className="mono">{x.name}</span>
          </button>)}
          <span className="spacer"/>
          <span className="segd">
            <button className={'segb' + (!raw ? ' on' : '')} onClick={() => setRaw(false)}>rendered</button>
            <button className={'segb' + (raw ? ' on' : '')} onClick={() => setRaw(true)}>raw</button>
          </span>
          <button className="zoomb" onClick={() => onToast('Download ' + o.name + ' — the artifact itself, unmodified.')}><Icon name="download" size={11}/></button>
        </div>

        <div className="card2 col" style={{ gap:'9px' }}>
          <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
            <EvBadge ev={o.ev}/><span className="mono" style={{ fontSize:'12.5px' }}>{o.name}</span>
            <span className="spacer"/>
            {o.dataset && <button className="btn sm ghost" onClick={() => onOpenData(o.dataset)}>open as dataset →</button>}
          </div>
          <span className="hint">{o.summary}</span>
          <OutViewer o={o} raw={raw} onToast={onToast}/>
          <span className="hint dim">{raw ? 'Raw first: the summary above is derived from these bytes, and you can check it.' : EVIDENCE[o.ev].what + ' — the viewer is chosen by the evidence class resolved from the output itself, the same way on every surface.'}</span>
        </div>

        <div className="card2 col" style={{ gap:'8px' }}>
          <div className="row ac"><span className="k2">Parameters this step actually ran with</span><span className="spacer"/>
            <span className="chip">{overrides + ' not default'}</span>
            <button className="linkish" onClick={() => setShowP(v => !v)}>{showP ? 'hide' : 'edit'}</button></div>
          {showP && <StepParams sk={sk} onToast={onToast} onRerun={() => onRerun(sk)} wide/>}
          {showP && <span className="hint dim">Defaults are grey; anything the project or you changed is marked and carries its reason. Edit a value here and the step re-runs from this point.</span>}
        </div>
      </>}
    </div>

    <div className="deepfoot">
      <button className="btn sm ghost" disabled={idx <= 1} onClick={() => onStep(-1)}><Icon name="chevronLeft" size={12}/>previous step</button>
      <button className="btn sm ghost" disabled={idx >= total} onClick={() => onStep(1)}>next step<Icon name="chevronRight" size={12}/></button>
      <span className="spacer"/>
      <button className="btn sm ghost" onClick={() => onOpenData(d.inputs[0] || 'd1')}>see in lineage</button>
      <button className="btn sm" onClick={() => onRerun(sk)}><Icon name="refresh" size={12}/>Re-run from here</button>
    </div>
  </div>;
}

/* Requirement C — re-run from a chosen step, with the was→now diff up front. */
function RerunCard({ sk, onClose, onToast }) {
  const d = STEP_DEEP[sk];
  const [pi, setPi] = React.useState(0);
  const p = d.params[pi];
  return <div className="card2 col rerun" style={{ gap:'10px' }}>
    <div className="row ac" style={{ gap:'8px' }}><Icon name="refresh" size={14}/><span className="k2">Re-run from this step</span>
      <span className="spacer"/><button className="zoomb" onClick={onClose}><Icon name="x" size={11}/></button></div>
    <span className="hint">Everything upstream is reused from the cache, so only this step and what depends on it run again. Change one value and compare the alternate output.</span>
    <div className="row wrap" style={{ gap:'6px' }}>
      {d.params.map((x, i) => <button key={x[0]} className={'schip' + (i === pi ? ' on' : '')} onClick={() => setPi(i)}>{x[0]}</button>)}
    </div>
    <div className="diffbox">
      <span className="k2">{p[0]}</span>
      <span className="diffline"><span className="dbefore">was · {p[1]}</span></span>
      <span className="diffline"><span className="dafter">now · <input className="dafterin" defaultValue={p[1]}/></span></span>
      <span className="hint">Cached upstream: 4 steps · re-runs: this step and 3 downstream · est. 6 min instead of 41.</span>
    </div>
    <div className="row" style={{ gap:'8px' }}>
      <button className="btn sm accent" onClick={() => { onToast('Re-running from ' + sk + ' with the changed value. The alternate output appears beside the original, so the two can be compared.'); onClose(); }}>Run this branch</button>
      <button className="btn sm ghost" onClick={onClose}>Cancel</button>
    </div>
  </div>;
}
/* Requirement D3 — a reported number, and the output it is findable in. */
function Claim({ id, onPick }) {
  const c = CLAIMS[id];
  return <button className="claim" onClick={() => onPick(id)} title="where does this number come from?">{c.n}</button>;
}
function ClaimPop({ id, onClose, onOpenStep }) {
  const c = CLAIMS[id]; const o = STEP_DEEP[c.step].outs.find(x => x.id === c.out);
  return <div className="claimpop">
    <div className="row ac"><span className="k2">{c.n}</span><span className="spacer"/><button className="zoomb" onClick={onClose}><Icon name="x" size={11}/></button></div>
    <span className="hint">{c.how} — <span className="mono">{c.val}</span></span>
    <div className="row ac">
      <EvBadge ev={o.ev}/><span className="mono" style={{ fontSize:'11.5px' }}>{o.name}</span>
      <span className="hint dim">step {c.step}</span>
      <span className="spacer"/>
      <button className="btn sm" onClick={() => onOpenStep(c.step, c.out)}>Open the output it came from →</button>
    </div>
  </div>;
}
Object.assign(window, { EvBadge, OutViewer, StepDeep, RerunCard, Claim, ClaimPop, StatusChip, StepParams, profFromRaw });
