/* Domain-specific evidence viewers — the concrete instances of the evidence
   classes for the pre-trained DL tools. Each is drawn from real data in
   data-part4.js, and each links a value back to where it is findable. */

const PL_BANDS = [[90, 'var(--ok)', 'very high'], [70, '#4b8fd6', 'confident'], [50, 'var(--warn)', 'low'], [0, '#c0563f', 'very low']];
const plColor = v => (PL_BANDS.find(b => v >= b[0]) || PL_BANDS[3])[1];
const plLabel = v => (PL_BANDS.find(b => v >= b[0]) || PL_BANDS[3])[2];

/* Per-residue confidence, linked to the 3D view. The chart is the honest
   companion to a structure picture: it says which parts of it to believe. */
function PlddtChart({ onToast, onFocus }) {
  const [hover, setHover] = React.useState(null);
  const [sel, setSel] = React.useState(null);
  const d = PLDDT, n = d.length, W = 100, H = 34;
  const mean = Math.round(d.reduce((a, b) => a + b, 0) / n);
  return <div className="col" style={{ gap:'9px' }}>
    <div className="row ac" style={{ gap:'9px', flexWrap:'wrap', rowGap:'6px' }}>
      <span className="k2">Per-residue confidence</span>
      <span className="chip">mean {mean}</span>
      <span className="spacer"/>
      <span className="plkey">{PL_BANDS.map(([, c, l]) => <span key={l}><i style={{ background:c }}/>{l}</span>)}</span>
    </div>
    <div className="plwrap">
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="plsvg" role="img" aria-label="Per-residue confidence">
        {[50, 70, 90].map(y => <line key={y} x1="0" x2={W} y1={H - H * y / 100} y2={H - H * y / 100} stroke="var(--border)" strokeWidth="0.25" vectorEffect="non-scaling-stroke"/>)}
        {d.map((v, i) => <rect key={i} x={i * W / n} y={H - H * v / 100} width={W / n * 0.92} height={H * v / 100}
          fill={plColor(v)} opacity={hover === null || hover === i ? 1 : 0.55}
          onMouseEnter={() => setHover(i)} onMouseLeave={() => setHover(null)}
          onClick={() => { setSel(i); onFocus && onFocus(i, v); }}/>)}
      </svg>
      <div className="plaxis"><span>1</span><span>{n}</span></div>
    </div>
    <div className="plread">
      {hover !== null || sel !== null
        ? (() => { const i = hover !== null ? hover : sel; return <>
            <span className="mono" style={{ fontWeight:600 }}>residue {i + 1}</span>
            <span className="mono">{d[i]}</span>
            <span className="chip" style={{ color:plColor(d[i]) }}>{plLabel(d[i])}</span>
            <span className="hint dim">click to centre the 3D view here</span></>; })()
        : <span className="hint dim">Hover a residue for its score; click to centre the 3D view on it.</span>}
    </div>
    <div className="col" style={{ gap:'6px' }}>
      {PLDDT_REGIONS.map(r => <button key={r.label} className="plregion" onClick={() => { setSel(r.from); onFocus && onFocus(r.from, d[r.from]); onToast('3D view centred on ' + r.label + '. The chart selection and the structure are one selection, not two.'); }}>
        <span className="dot" style={{ background:plColor(d[r.from]) }}/>
        <span style={{ fontWeight:600, fontSize:'12px' }}>{r.label}</span>
        <span className="hint dim">{r.why}</span>
      </button>)}
    </div>
    <span className="hint">A structure picture with no confidence chart invites a claim its low-confidence loops cannot support. The two are one output, shown together.</span>
  </div>;
}

/* Pairwise error — the answer to "can I trust the relative placement of these
   two domains", which per-residue confidence cannot give. */
function PaeHeatmap({ onToast }) {
  const m = PAE, n = m.length;
  const [cell, setCell] = React.useState(null);
  const col = v => { const t = Math.min(1, v / 30); return `rgb(${Math.round(30 + 210 * t)},${Math.round(80 + 140 * t)},${Math.round(140 + 90 * t)})`; };
  return <div className="col" style={{ gap:'9px' }}>
    <div className="row ac" style={{ gap:'9px', flexWrap:'wrap', rowGap:'6px' }}>
      <span className="k2">Pairwise alignment error</span>
      <span className="spacer"/><span className="hint dim">lower is better · Å</span>
    </div>
    <div className="paegrid" style={{ gridTemplateColumns:`repeat(${n},1fr)` }}>
      {m.flatMap((row, i) => row.map((v, j) =>
        <span key={i + '-' + j} className="paec" style={{ background:col(v) }}
          onMouseEnter={() => setCell([i, j, v])} onMouseLeave={() => setCell(null)}/>))}
    </div>
    <div className="plread">
      {cell ? <><span className="mono">block {cell[0] + 1} × {cell[1] + 1}</span><span className="mono" style={{ fontWeight:600 }}>{cell[2]} Å</span>
        <span className="hint dim">{cell[2] < 8 ? 'relative placement is reliable' : 'treat the relative placement as unresolved'}</span></>
        : <span className="hint dim">Two confident domains can still be placed wrongly relative to each other — that is what this reads.</span>}
    </div>
    <button className="linkish" style={{ alignSelf:'flex-start' }} onClick={() => onToast('The two dark blocks are the confident domains; the pale off-diagonal says their relative orientation is not resolved.')}>read this heatmap →</button>
  </div>;
}

/* Sequence and score tracks for the genomic models. */
function SeqTracks({ onToast }) {
  const t = TRACKS, W = 100;
  const path = d => d.map((v, i) => `${i === 0 ? 'M' : 'L'}${(i * W / (d.length - 1)).toFixed(2)},${(20 - 18 * v / 100).toFixed(2)}`).join(' ');
  return <div className="col" style={{ gap:'9px' }}>
    <div className="row ac" style={{ gap:'9px', flexWrap:'wrap', rowGap:'6px' }}>
      <span className="k2">Score tracks</span><span className="chip mono">{t.locus}</span>
      <span className="spacer"/><span className="hint dim">{t.bp.toLocaleString()} bp</span>
    </div>
    <div className="col" style={{ gap:'2px' }}>
      {t.rows.map(r => <div key={r.k} className="trk">
        <span className="trkk">{r.k}</span>
        <svg viewBox="0 0 100 20" preserveAspectRatio="none" className="trksvg">
          {r.kind === 'line' && <><path d={path(r.d) + ` L100,20 L0,20 Z`} fill="var(--accent-soft)"/>
            <path d={path(r.d)} fill="none" stroke="var(--accent)" strokeWidth="0.7" vectorEffect="non-scaling-stroke"/></>}
          {r.kind === 'marks' && r.d.map(([a, b], i) => <rect key={i} x={a * 100 / 70} y="4" width={(b - a) * 100 / 70} height="12" fill="var(--warn)" opacity="0.75" rx="0.6"/>)}
          {r.kind === 'ticks' && r.d.map((x, i) => <rect key={i} x={x * 100 / 70} y="3" width="0.5" height="14" fill="var(--text-muted)"/>)}
        </svg>
      </div>)}
    </div>
    <div className="col" style={{ gap:'0' }}>
      {t.flags.map(([loc, kind, why]) => <div key={loc} className="evrow">
        <span className="mono" style={{ fontSize:'11.5px' }}>{loc}</span>
        <span className="chip">{kind}</span>
        <span className="hint dim">{why}</span>
        <button className="linkish" onClick={() => onToast('Opens this interval with its per-base scores, and the sequence beneath.')}>open</button>
      </div>)}
    </div>
    <span className="hint">A per-base score is only actionable as an interval. Flagged regions are the output; the tracks are how you check them.</span>
  </div>;
}

/* Ranked hits + depiction grid. The depiction itself renders from SMILES at
   build time — the slot names what goes there rather than faking a drawing. */
function HitGrid({ onToast, onOpenModel }) {
  const [view, setView] = React.useState('table');
  const vchip = v => v === 'accepted' ? 'ok' : v === 'rejected' ? 'err' : 'warn';
  return <div className="col" style={{ gap:'9px' }}>
    <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
      <span className="k2">Ranked hits</span>
      <span className="spacer"/>
      <div className="trackbar" style={{ margin:0 }}>
        {[['table', 'Table'], ['grid', 'Depictions']].map(([k, l]) =>
          <button key={k} className={'trackb' + (view === k ? ' on' : '')} onClick={() => setView(k)}>{l}</button>)}
      </div>
    </div>
    {view === 'table' ? <div className="col" style={{ gap:'0' }}>
      <div className="hitr head"><span>Candidate</span><span>Score</span><span>Confidence</span><span>hERG</span><span>Drug-like</span><span>Verdict</span></div>
      {HITS.map(h => <div key={h.id} className="hitr">
        <span className="mono" style={{ fontWeight:600 }}>{h.id}</span>
        <span className="mono">{h.score}</span>
        <ConfPill level={h.conf === 'out-of-domain' ? 'low' : h.conf}/>
        <span className="mono">{h.herg}</span>
        <span className="hint">{h.dl}</span>
        <span className={'chip ' + vchip(h.v)}><span className="dot"/>{h.v}</span>
      </div>)}
    </div> : <div className="hitgrid">
      {HITS.map(h => <div key={h.id} className={'hitcard ' + h.v}>
        <div className="depict">
          <span className="dph">2D depiction</span>
          <span className="mono dpsmi">{h.smiles}</span>
          <span className="hint dim">renders from SMILES</span>
        </div>
        <div className="row ac" style={{ gap:'7px', flexWrap:'wrap', rowGap:'4px' }}>
          <span className="mono" style={{ fontWeight:600, fontSize:'11.5px' }}>{h.id}</span>
          <span className="spacer"/><span className="mono" style={{ fontSize:'11.5px' }}>{h.score}</span>
        </div>
        <div className="row ac" style={{ gap:'6px', flexWrap:'wrap', rowGap:'4px' }}>
          <span className={'chip ' + vchip(h.v)}>{h.v}</span>
          {h.conf === 'out-of-domain' && <span className="chip warn">out-of-domain</span>}
        </div>
      </div>)}
    </div>}
    <div className="row ac" style={{ gap:'9px', flexWrap:'wrap', rowGap:'6px' }}>
      <span className="hint">Every score names the model behind it.</span>
      <button className="linkish" onClick={() => onOpenModel ? onOpenModel('admet-herg') : onToast('Opens the model object.')}>admet-herg v3 →</button>
      <span className="hint dim">BM-4541 is held: outside the model's applicability region, so no confident number is offered.</span>
    </div>
  </div>;
}

/* Run a pre-trained model — the fourth Models track. */
function PretrainedTab({ onToast, onOpenRun }) {
  const [sel, setSel] = React.useState('struct');
  const [ran, setRan] = React.useState(false);
  const m = INFER.find(x => x.id === sel);
  return <>
    <div className="card2 col" style={{ gap:'11px' }}>
      <div className="row ac" style={{ flexWrap:'wrap', rowGap:'6px' }}>
        <span className="k2">Run a pre-trained model</span>
        <span className="spacer"/>
        <span className="hint dim">integrated open-source models · nothing of yours is trained</span>
      </div>
      <span className="hint">Distinct from Train: these models arrive already fitted. You supply an input and get an inference, so the questions are what it can speak to and how much of its answer to trust — not what it learned.</span>
      <div className="trackbar">
        {INFER.map(x => <button key={x.id} className={'trackb' + (sel === x.id ? ' on' : '')} onClick={() => { setSel(x.id); setRan(false); }}>{x.dom}</button>)}
      </div>
      <div className="col" style={{ gap:'7px' }}>
        <span style={{ fontSize:'13px', fontWeight:600 }}>{m.goal}</span>
        <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'5px' }}>
          <span className="chip">{m.t}</span><span className="chip acc">{m.ev}</span>
          <span className="hint dim">produces {m.out}</span>
        </div>
        {m.ex.map(e => <button key={e} className="exrow" onClick={() => onToast('Seeded the composer. Nothing has run yet.')}>
          <Icon name="sparkles" size={12}/><span>“{e}”</span></button>)}
      </div>
      <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
        <button className="btn sm accent" onClick={() => { setRan(true); onToast('Inference runs on the run surface — same phases, gates and step views as any workflow.'); }}><Icon name="play" size={10}/>Run inference</button>
        <button className="btn sm ghost" onClick={onOpenRun}>Open the run surface →</button>
      </div>
    </div>
    {ran && <div className="card2 col" style={{ gap:'12px' }}>
      <div className="row ac" style={{ flexWrap:'wrap', rowGap:'6px' }}>
        <span className="k2">Result</span>
        <span className="chip ok"><span className="dot"/>completed</span>
        <span className="spacer"/>
        <span className="mono" style={{ fontSize:'11.5px' }}>{INFER_MODEL.name} {INFER_MODEL.v}</span>
      </div>
      <span className="hint dim">{INFER_MODEL.note}</span>
      {sel === 'struct' && <><div className="imgstage"><span className="hint dim">3D structure viewer</span></div>
        <PlddtChart onToast={onToast} onFocus={() => {}}/><PaeHeatmap onToast={onToast}/></>}
      {sel === 'geno' && <SeqTracks onToast={onToast}/>}
      {sel === 'chem' && <HitGrid onToast={onToast}/>}
    </div>}
  </>;
}
Object.assign(window, { PlddtChart, PaeHeatmap, SeqTracks, HitGrid, PretrainedTab, plColor });
