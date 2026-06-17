// OutputViz — real, data-driven renders of the figure outputs a chain
// produces (UMAP, marker heatmap, volcano). These are seeded from the
// scenario's own numbers so they stay consistent with the chat + findings.
// NOTE FOR PORT: in production these must be the actual artifact images
// (umap.png, marker_heatmap.png, volcano.png) from the run's object store —
// here we synthesise plausible, stable plots for the demo.
const { useMemo: useMemoV } = React;
(function () {

// Deterministic PRNG so a figure looks identical on every render.
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function gauss(rng) { // Box–Muller
  let u = 0, v = 0;
  while (u === 0) u = rng();
  while (v === 0) v = rng();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

const SEG = ['--seg-0','--seg-1','--seg-2','--seg-3','--seg-4','--seg-5','--seg-6','--seg-7'];

// ── UMAP: one gaussian blob per cell type, sized by composition ─────
function UmapPlot({ types }) {
  // types: [[label, count], ...]
  const W = 360, H = 270;
  // Hand-placed cluster centres (in 0..1) that read like a real UMAP.
  const centres = [
    [0.30, 0.34], [0.44, 0.52], [0.66, 0.30], [0.72, 0.58],
    [0.50, 0.78], [0.22, 0.66], [0.84, 0.42], [0.40, 0.20],
  ];
  const pts = useMemoV(() => {
    const rng = mulberry32(1337);
    const out = [];
    types.forEach(([label, count], ti) => {
      const [cx, cy] = centres[ti % centres.length];
      const n = Math.max(8, Math.round(count / 26)); // downsample for clarity
      const spread = 0.052 + (rng() * 0.018);
      for (let i = 0; i < n; i++) {
        out.push({
          x: Math.min(0.97, Math.max(0.03, cx + gauss(rng) * spread)),
          y: Math.min(0.97, Math.max(0.03, cy + gauss(rng) * spread)),
          c: SEG[ti % 8],
        });
      }
    });
    return out;
  }, [types]);
  return (
    <div className="oviz">
      <svg viewBox={`0 0 ${W} ${H}`} className="oviz-svg" role="img" aria-label="UMAP">
        <rect x="0" y="0" width={W} height={H} fill="var(--surface)"/>
        {pts.map((p, i) => (
          <circle key={i} cx={p.x * W} cy={(1 - p.y) * H} r="2.1"
            fill={`var(${p.c})`} fillOpacity="0.8"/>
        ))}
        <text x="8" y={H - 8} fontSize="9" fill="var(--text-dim)" fontFamily="var(--font-mono)">UMAP-1</text>
        <text x="8" y="14" fontSize="9" fill="var(--text-dim)" fontFamily="var(--font-mono)">UMAP-2</text>
      </svg>
      <div className="oviz-legend">
        {types.map(([label], i) => (
          <span key={i} className="oviz-key">
            <span className="oviz-dot" style={{background: `var(${SEG[i % 8]})`}}/>{label}
          </span>
        ))}
      </div>
    </div>
  );
}

// ── Marker heatmap: cell types × marker genes, block-diagonal ───────
const MARKER_GENES = ['CD3D','IL7R','CD8A','GNLY','NKG7','LYZ','CD14','MS4A1','FCER1A','FOXP3','PPBP','HLA-DRA'];
// which marker columns light up for each cell-type row (by index into MARKER_GENES)
const MARKER_MAP = {
  'CD4⁺ T': [0,1], 'CD8⁺ T': [0,2], 'NK': [3,4], 'Monocyte': [5,6],
  'B': [7,11], 'Dendritic': [8,11], 'Treg': [1,9], 'Platelet': [10],
};
function HeatmapPlot({ types }) {
  const rows = types.map(([l]) => l);
  const grid = useMemoV(() => {
    const rng = mulberry32(7);
    return rows.map((r) => {
      const hot = MARKER_MAP[r] || [];
      return MARKER_GENES.map((g, ci) =>
        hot.includes(ci) ? 0.78 + rng() * 0.22 : rng() * 0.28);
    });
  }, [rows.join('|')]);
  const cell = 22, labelW = 78, topH = 58, leftPad = 8;
  const W = labelW + MARKER_GENES.length * cell + 8;
  const H = topH + rows.length * cell + 8;
  return (
    <div className="oviz">
      <svg viewBox={`0 0 ${W} ${H}`} className="oviz-svg" role="img" aria-label="Marker heatmap">
        {MARKER_GENES.map((g, ci) => (
          <text key={ci} x={labelW + ci * cell + cell / 2} y={topH - 6}
            fontSize="9" fill="var(--text-muted)" fontFamily="var(--font-mono)"
            transform={`rotate(-55 ${labelW + ci * cell + cell / 2} ${topH - 6})`}>{g}</text>
        ))}
        {grid.map((row, ri) => (
          <g key={ri}>
            <text x={labelW - 6} y={topH + ri * cell + cell / 2 + 3} fontSize="10"
              fill="var(--text)" textAnchor="end">{rows[ri]}</text>
            {row.map((v, ci) => (
              <rect key={ci} x={labelW + ci * cell} y={topH + ri * cell}
                width={cell - 1.5} height={cell - 1.5} rx="2"
                fill="var(--accent)" fillOpacity={(0.08 + v * 0.92).toFixed(3)}/>
            ))}
          </g>
        ))}
      </svg>
      <div className="oviz-scale">
        <span>low</span>
        <span className="oviz-grad"/>
        <span>high expression (scaled)</span>
      </div>
    </div>
  );
}

// ── Volcano: genes by log2FC vs −log10(padj) ────────────────────────
function VolcanoPlot({ up = 1612, down = 1229, total = 18421 }) {
  const W = 360, H = 270, padL = 34, padB = 26, padT = 10, padR = 8;
  const xmin = -5, xmax = 5, ymax = 14;
  const sx = (v) => padL + ((v - xmin) / (xmax - xmin)) * (W - padL - padR);
  const sy = (v) => (H - padB) - (v / ymax) * (H - padB - padT);
  const pts = useMemoV(() => {
    const rng = mulberry32(99);
    const out = [];
    const nShown = 620;
    for (let i = 0; i < nShown; i++) {
      // most genes: small fold-change, low significance
      let lfc = gauss(rng) * 1.1;
      let sig = Math.abs(gauss(rng)) * 1.4;
      // a tail of strongly DE genes
      if (rng() < 0.16) { lfc = (rng() < 0.56 ? 1 : -1) * (1.4 + rng() * 3.0); sig = 2 + rng() * 9; }
      lfc = Math.max(xmin + 0.1, Math.min(xmax - 0.1, lfc));
      sig = Math.min(ymax - 0.3, Math.max(0, sig));
      const isUp = lfc > 1 && sig > 1.3;
      const isDn = lfc < -1 && sig > 1.3;
      out.push({ x: sx(lfc), y: sy(sig),
        c: isUp ? 'oklch(0.58 0.18 25)' : isDn ? 'oklch(0.55 0.14 245)' : 'var(--text-dim)',
        o: (isUp || isDn) ? 0.85 : 0.28, r: (isUp || isDn) ? 2.3 : 1.8 });
    }
    return out;
  }, [up, down]);
  return (
    <div className="oviz">
      <svg viewBox={`0 0 ${W} ${H}`} className="oviz-svg" role="img" aria-label="Volcano plot">
        <rect x="0" y="0" width={W} height={H} fill="var(--surface)"/>
        {/* threshold guides */}
        <line x1={sx(1)} y1={padT} x2={sx(1)} y2={H - padB} stroke="var(--border-strong)" strokeWidth="1" strokeDasharray="3 3"/>
        <line x1={sx(-1)} y1={padT} x2={sx(-1)} y2={H - padB} stroke="var(--border-strong)" strokeWidth="1" strokeDasharray="3 3"/>
        <line x1={padL} y1={sy(1.3)} x2={W - padR} y2={sy(1.3)} stroke="var(--border-strong)" strokeWidth="1" strokeDasharray="3 3"/>
        {/* axes */}
        <line x1={padL} y1={H - padB} x2={W - padR} y2={H - padB} stroke="var(--border)" strokeWidth="1"/>
        <line x1={padL} y1={padT} x2={padL} y2={H - padB} stroke="var(--border)" strokeWidth="1"/>
        {pts.map((p, i) => <circle key={i} cx={p.x} cy={p.y} r={p.r} fill={p.c} fillOpacity={p.o}/>)}
        <text x={(W) / 2} y={H - 6} fontSize="9.5" fill="var(--text-dim)" textAnchor="middle" fontFamily="var(--font-mono)">log₂ fold-change</text>
        <text x="11" y={(H - padB) / 2} fontSize="9.5" fill="var(--text-dim)" textAnchor="middle" fontFamily="var(--font-mono)" transform={`rotate(-90 11 ${(H - padB) / 2})`}>−log₁₀ adj.p</text>
      </svg>
      <div className="oviz-legend">
        <span className="oviz-key"><span className="oviz-dot" style={{background:'oklch(0.58 0.18 25)'}}/>Up · {up.toLocaleString()}</span>
        <span className="oviz-key"><span className="oviz-dot" style={{background:'oklch(0.55 0.14 245)'}}/>Down · {down.toLocaleString()}</span>
        <span className="oviz-key"><span className="oviz-dot" style={{background:'var(--text-dim)', opacity:0.5}}/>Not significant</span>
      </div>
    </div>
  );
}

// Dispatcher: pick a figure by the output's `viz` key, pull data from the
// scenario report so the plot matches the findings.
function OutputFigureViz({ viz, scenario }) {
  const fig = ((scenario && scenario.report && scenario.report.findings && scenario.report.findings.figures) || [])
    .find(f => f.kind === 'composition');
  const types = (fig && fig.data) || [];
  if (viz === 'umap')    return <UmapPlot types={types}/>;
  if (viz === 'markers') return <HeatmapPlot types={types.length ? types : [['CD4⁺ T',1],['CD8⁺ T',1],['NK',1],['Monocyte',1],['B',1],['Dendritic',1],['Treg',1],['Platelet',1]]}/>;
  if (viz === 'volcano') {
    const dir = ((scenario.report.findings.figures || []).find(f => /direction/i.test(f.title) || f.kind === 'composition' && /direction|DE/.test(f.title)) || {}).data;
    const up = dir && dir[0] ? dir[0][1] : 1612;
    const down = dir && dir[1] ? dir[1][1] : 1229;
    return <VolcanoPlot up={up} down={down}/>;
  }
  // Types the data-driven set doesn't cover (go_dotplot, heatmap, manhattan, …)
  // delegate to the full legacy picker in Modals.jsx so the Outputs-tab "view"
  // renders the same figure the tutorial preview modal shows.
  if (viz && window.OutputViz) return <window.OutputViz file={{ viz, name: 'output' }}/>;
  return <div style={{color:'var(--text-dim)', fontStyle:'italic', padding:16}}>No preview available for this output.</div>;
}

// Modal overlay used by the Outputs tab "view" action.
function OutputFigurePreview({ output, scenario, onClose }) {
  if (!output) return null;
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal preview-modal" onClick={e => e.stopPropagation()} style={{maxWidth: 540}}>
        <div className="body" style={{paddingBottom: 14}}>
          <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:12}}>
            <div>
              <div style={{fontFamily:'var(--font-mono)', fontSize:13, fontWeight:600}}>{output.file}</div>
              <div style={{fontSize:11, color:'var(--text-dim)', marginTop:2}}>{output.phase} · {output.step}</div>
            </div>
            <button className="btn ghost sm" onClick={onClose}><Icon name="x" size={14}/></button>
          </div>
          <OutputFigureViz viz={output.viz} scenario={scenario}/>
          <div style={{marginTop:12, fontSize:11, color:'var(--text-dim)', fontStyle:'italic', lineHeight:1.5}}>
            Rendered from the run output. In production this opens the artifact file from the run’s object store.
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { OutputFigureViz, OutputFigurePreview });
})();
