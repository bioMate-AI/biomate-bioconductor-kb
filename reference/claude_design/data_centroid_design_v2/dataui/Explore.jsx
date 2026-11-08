/* Exploration & visualization for the dataset object — charts drawn from the
   fixture's real numbers, plus the launch points that make the dataset the
   centroid of *doing*, not just of reading provenance. */

function Bars({ values, labels, floor, unit }) {
  const max = Math.max(...values);
  return <div className="chart">
    <div className="bars">
      {values.map((v, i) => <div key={i} className="barcol" title={`${labels[i]} · ${v}${unit || ''}`}>
        <div className={'barfill' + (floor != null && v < floor ? ' bad' : '')} style={{ height:(v / max * 100) + '%' }}/>
      </div>)}
      {floor != null && <div className="floorline" style={{ bottom:(floor / max * 100) + '%' }}><span>floor</span></div>}
    </div>
    <div className="axis"><span>{labels[0]}</span><span>{labels[labels.length - 1]}</span></div>
  </div>;
}

function Scatter({ points, xl, yl, legend, sigLabel }) {
  const xs = points.map(p => p.x), ys = points.map(p => p.y);
  const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
  const px = v => ((v - x0) / (x1 - x0 || 1)) * 100, py = v => ((v - y0) / (y1 - y0 || 1)) * 100;
  return <div className="chart">
    <div className="plot">
      {points.map((p, i) => <span key={i} className={'pt' + (p.sig ? ' sig' : '') + (p.flag ? ' flag' : '') + (p.g === 'TREAT' ? ' g2' : '')}
        style={{ left:px(p.x) + '%', bottom:py(p.y) + '%' }} title={p.l || `${p.x.toFixed(2)}, ${p.y.toFixed(2)}`}/>)}
    </div>
    <div className="axis"><span>{xl}</span><span>{yl}</span></div>
    {legend && <div className="row wrap" style={{ gap:'10px' }}>{legend.map(([cls, t]) => <span key={t} className="legitem"><span className={'pt ' + cls}/>{t}</span>)}</div>}
  </div>;
}

function EditableTable({ prof, editing, onToast }) {
  const [rows, setRows] = React.useState(prof.rows);
  React.useEffect(() => setRows(prof.rows), [prof]);
  const bad = (v) => /^Control$/.test(v) || v === '—';
  return <div className="col" style={{ gap:'10px' }}>
    <div className="dtable" style={{ gridTemplateColumns:`repeat(${prof.cols.length}, max-content)` }}>
      {prof.cols.map(c => <div key={c} className="dth">{c}</div>)}
      {rows.map((r, i) => r.map((v, j) => editing
        ? <input key={i + '-' + j} className={'dtd dtin r' + (i % 2) + (bad(v) ? ' flag' : '')} value={v}
            onChange={ev => setRows(rs => rs.map((row, ri) => ri === i ? row.map((cv, ci) => ci === j ? ev.target.value : cv) : row))}/>
        : <div key={i + '-' + j} className={'dtd r' + (i % 2) + (bad(v) ? ' flag' : '')}>{v}</div>))}
    </div>
    <span className="hint dim">{editing
      ? 'Cells are editable.'
      : 'First rows, as stored in this version. Sorting, filtering and full paging use the existing table viewer.'}</span>
  </div>;
}

function ColumnProfile({ prof }) {
  return <div className="col" style={{ gap:'0' }}>
    {prof.columns.map(c => <div key={c.n} className="profrow">
      <span className="pname">{c.n}</span>
      <span className="chip">{c.t}</span>
      <div className="missbar" title={`${c.miss}% missing`}><span style={{ width:Math.max(c.miss * 6, c.miss ? 3 : 0) + '%' }} className={c.bad ? 'bad' : ''}/></div>
      <span className="hint" style={{ minWidth:'72px' }}>{c.miss}% missing</span>
      <span className="hint" style={{ flex:1 }}>{c.note || c.uniq}</span>
      {c.bad && <span className="chip warn"><span className="dot"/>watch</span>}
    </div>)}
  </div>;
}

function Visualize({ ds, onToast, onSeed }) {
  const prof = PROFILES[ds.id];
  const has = prof && (prof.libsize || prof.pca || prof.volcano);
  return <div className="col" style={{ gap:'14px' }}>
    {has ? <>
      {prof.libsize && <div className="card2 col" style={{ gap:'10px' }}>
        <div className="row ac"><span className="k2">Library size per sample</span><span className="spacer"/><span className="chip warn"><span className="dot"/>2 samples below floor</span></div>
        <Bars values={prof.libsize} labels={prof.libLabels} floor={prof.libFloor} unit="M reads"/>
        <span className="hint">This is the plot behind the amber quality note — the two flagged samples are visible rather than described. Both were excluded at gate 3 of the differential-expression run.</span>
      </div>}
      {prof.pca && <div className="card2 col" style={{ gap:'10px' }}>
        <div className="row ac"><span className="k2">Sample similarity (PCA)</span><span className="spacer"/><button className="btn sm ghost" onClick={() => onToast('Colour by: condition · batch · library size · sex')}>Colour by ▾</button></div>
        <Scatter points={prof.pca} xl="PC1 · 41% variance" yl="PC2 · 18%" legend={[['', 'control'], ['g2', 'treated'], ['flag', 'low depth']]}/>
        <span className="hint">Groups separate on PC1, which is the reassurance a scientist wants <b>before</b> committing hours of compute. The two low-depth samples sit apart on PC2.</span>
      </div>}
      {prof.volcano && <div className="card2 col" style={{ gap:'10px' }}>
        <div className="row ac"><span className="k2">Effect size vs significance</span><span className="spacer"/><span className="chip ok">412 at FDR &lt; 0.05</span></div>
        <Scatter points={prof.volcano} xl="log2 fold change" yl="−log10 padj" legend={[['', 'not significant'], ['sig', 'FDR < 0.05']]}/>
        <span className="hint">Rendered from this dataset's own columns, so the figure and the table can never disagree. Saving it writes a figure output back into this dataset's lineage.</span>
      </div>}
      <div className="row wrap" style={{ gap:'7px' }}>
        <button className="btn sm" onClick={() => onToast('Saved as a figure output — it joins this dataset\u2019s derived outputs and its lineage.')}>Save as output</button>
        <button className="btn sm" onClick={() => onToast('Export → PNG, SVG or a vector PDF for a manuscript figure.')}>Export figure</button>
        <button className="btn sm ghost" onClick={() => onSeed('Plot ' + ds.name + ' — I want a different view of it.')}>Ask for another plot</button>
      </div>
    </> : <div className="card2 col" style={{ gap:'9px' }}>
      <span className="k2">Nothing plotted yet</span>
      <span className="hint">Charts appear here as soon as a dataset has numeric columns or a run has profiled it. You can also ask for a specific view in plain language and it will be computed in the sandbox.</span>
      <button className="btn sm accent" style={{ alignSelf:'flex-start' }} onClick={() => onSeed('Plot ' + ds.name + ' — show me the distribution of each numeric column.')}>Ask for a plot</button>
    </div>}
  </div>;
}

Object.assign(window, { Bars, Scatter, ColumnProfile, EditableTable, Visualize });
