// Modals: Skip-phase confirm, Adjust & Rerun, Output preview, Methods report, QC audit
const { useState: useStateM } = React;

function SkipConfirmModal({ target, onCancel, onConfirm }) {
  if (!target) return null;
  const { targetKind: kind, name, downstream } = target;
  return (
    <div className="modal-backdrop" onClick={onCancel}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div className="body">
          <div className="confirm-icon"><Icon name="warn" size={18}/></div>
          <h3>Skip {kind} "{name}"?</h3>
          <p style={{color:'var(--text-muted)', lineHeight:1.55, margin:'6px 0 14px'}}>
            Skipping {kind === 'phase' ? 'a phase' : 'a step'} removes its output files.
            {downstream && downstream.length > 0 && (
              <> Downstream {downstream.length === 1 ? 'phase' : 'phases'}{' '}
                <span className="mono" style={{color:'var(--text)'}}>
                  {downstream.join(', ')}
                </span>{' '}
                depend on these outputs and may fail.
              </>
            )}
          </p>
          <div style={{
            border:'1px dashed var(--border-strong)', borderRadius:'var(--r-sm)',
            padding:'9px 12px', fontSize:12, color:'var(--text-muted)',
            background:'var(--surface)'
          }}>
            You can rerun the skipped {kind} at any time from its card.
          </div>
        </div>
        <div className="foot">
          <button className="btn ghost" onClick={onCancel}>Cancel</button>
          <button className="btn" style={{color:'var(--err)', borderColor:'var(--err)'}}
            onClick={onConfirm}>
            Skip {kind} anyway
          </button>
        </div>
      </div>
    </div>
  );
}

function AdjustModal({ step, onCancel, onRerun }) {
  if (!step) return null;
  return (
    <div className="modal-backdrop" onClick={onCancel}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div className="body">
          <h3>Adjust &amp; rerun — {step.name}</h3>
          <p style={{color:'var(--text-muted)', fontSize:12.5, margin:'4px 0 16px'}}>
            Parameters below apply to this step only. Downstream steps will rerun
            automatically from this point. A new <span className="mono">runId</span> will be created.
          </p>
          {step.params && step.params.map(p => (
            <div className="field" key={p.k}>
              <label>{p.k}</label>
              <input defaultValue={p.v}/>
            </div>
          ))}
          {(!step.params || step.params.length === 0) && (
            <div className="field">
              <label>No step-level parameters</label>
              <input placeholder="This step has no overridable parameters" disabled/>
            </div>
          )}
        </div>
        <div className="foot">
          <button className="btn ghost" onClick={onCancel}>Cancel</button>
          <button className="btn primary" onClick={onRerun}>
            <Icon name="refresh" size={12}/> Rerun from here
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Visualization sub-components for cryo-EM outputs ──────────────────

const Caption = ({ children }) => (
  <div style={{fontSize:11, color:'var(--text-dim)', marginTop:8, lineHeight:1.5}}>
    {children}
  </div>
);

// Helper: deterministic pseudo-random based on a seed string, so outputs render
// the same on every render and animations don't make charts jitter.
const seeded = (s) => {
  let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
  return () => { h ^= h << 13; h ^= h >>> 17; h ^= h << 5; return ((h >>> 0) % 10000) / 10000; };
};

const VizMotion = () => {
  const rng = seeded('motion');
  // 248-frame trajectory with cumulative drift + small jitter
  const pts = []; let x = 0, y = 0;
  for (let i = 0; i < 80; i++) {
    x += (rng() - 0.4) * 1.6 + 0.04;
    y += (rng() - 0.6) * 1.4 - 0.08;
    pts.push([200 + x*8, 150 + y*5]);
  }
  return (
    <div>
      <svg viewBox="0 0 400 280" style={{width:'100%', background:'var(--surface)', borderRadius:'var(--r-sm)'}}>
        {/* axes */}
        <line x1="40" y1="240" x2="380" y2="240" stroke="var(--border-strong)" strokeWidth="1"/>
        <line x1="40" y1="20"  x2="40" y2="240" stroke="var(--border-strong)" strokeWidth="1"/>
        <text x="210" y="266" fontSize="10" fill="var(--text-dim)" textAnchor="middle">Frame number</text>
        <text x="14" y="135" fontSize="10" fill="var(--text-dim)" textAnchor="middle" transform="rotate(-90 14 135)">Shift (Å)</text>
        {/* X-shift curve */}
        <polyline fill="none" stroke="oklch(0.55 0.18 250)" strokeWidth="1.5"
          points={pts.map((p,i) => `${40 + i*4.2},${130 - (p[0]-200)*0.4}`).join(' ')}/>
        {/* Y-shift curve */}
        <polyline fill="none" stroke="oklch(0.62 0.16 30)" strokeWidth="1.5"
          points={pts.map((p,i) => `${40 + i*4.2},${130 - (p[1]-150)*0.4}`).join(' ')}/>
        {/* Legend */}
        <rect x="290" y="30" width="80" height="34" fill="var(--bg-elev)" stroke="var(--border)" rx="3"/>
        <line x1="298" y1="42" x2="316" y2="42" stroke="oklch(0.55 0.18 250)" strokeWidth="1.5"/>
        <text x="320" y="45" fontSize="10" fill="var(--text)">X shift</text>
        <line x1="298" y1="56" x2="316" y2="56" stroke="oklch(0.62 0.16 30)" strokeWidth="1.5"/>
        <text x="320" y="59" fontSize="10" fill="var(--text)">Y shift</text>
      </svg>
      <Caption>
        Per-frame stage drift over 248 movie frames · total motion <b>3.42 Å</b> · max inter-frame
        shift <b>0.31 Å</b> · all within tolerance.
      </Caption>
    </div>
  );
};

const VizMicrographs = () => {
  // 4×3 grid of micrograph thumbnails — synthetic noise textures
  const cells = Array.from({length:12}, (_,i) => i);
  return (
    <div>
      <div style={{display:'grid', gridTemplateColumns:'repeat(4, 1fr)', gap:6}}>
        {cells.map(i => {
          const seed = i * 17 + 3;
          return (
            <div key={i} style={{position:'relative', aspectRatio:'1', background:'#0a0d12', borderRadius:4, overflow:'hidden'}}>
              <svg viewBox="0 0 60 60" preserveAspectRatio="none" style={{width:'100%', height:'100%'}}>
                <defs>
                  <radialGradient id={`mg-grad-${i}`} cx="50%" cy="50%">
                    <stop offset="0%"  stopColor="#3a4258"/>
                    <stop offset="60%" stopColor="#1a1f2c"/>
                    <stop offset="100%" stopColor="#080a10"/>
                  </radialGradient>
                </defs>
                <rect width="60" height="60" fill={`url(#mg-grad-${i})`}/>
                {/* particle dots */}
                {Array.from({length: 14}).map((_,j) => (
                  <circle key={j}
                    cx={(seed*7 + j*23) % 56 + 2}
                    cy={(seed*11 + j*31) % 56 + 2}
                    r={1.4 + ((seed+j) % 3) * 0.4}
                    fill="rgba(220,220,230,0.55)"/>
                ))}
              </svg>
              <span style={{position:'absolute', bottom:2, left:4, fontSize:8, color:'#aab', fontFamily:'var(--font-mono)'}}>
                mic_{String(i+1).padStart(3,'0')}
              </span>
            </div>
          );
        })}
      </div>
      <Caption>
        842 motion-corrected micrographs · 12 shown · downsampled 4× for preview · click a thumbnail
        in the file browser to load the full <span className="mono">mrc</span>.
      </Caption>
    </div>
  );
};

const VizThonRings = () => (
  <div>
    <svg viewBox="0 0 300 300" style={{width:'100%', maxWidth:340, display:'block', margin:'0 auto', background:'#000', borderRadius:'var(--r-sm)'}}>
      <defs>
        <radialGradient id="thon-ctf" cx="50%" cy="50%">
          <stop offset="0%"  stopColor="#fff" stopOpacity="0.0"/>
          <stop offset="3%"  stopColor="#fff" stopOpacity="0.95"/>
          <stop offset="6%"  stopColor="#fff" stopOpacity="0.05"/>
          <stop offset="10%" stopColor="#fff" stopOpacity="0.85"/>
          <stop offset="14%" stopColor="#fff" stopOpacity="0.10"/>
          <stop offset="20%" stopColor="#fff" stopOpacity="0.75"/>
          <stop offset="26%" stopColor="#fff" stopOpacity="0.10"/>
          <stop offset="34%" stopColor="#fff" stopOpacity="0.62"/>
          <stop offset="42%" stopColor="#fff" stopOpacity="0.10"/>
          <stop offset="52%" stopColor="#fff" stopOpacity="0.50"/>
          <stop offset="62%" stopColor="#fff" stopOpacity="0.10"/>
          <stop offset="72%" stopColor="#fff" stopOpacity="0.40"/>
          <stop offset="80%" stopColor="#fff" stopOpacity="0.10"/>
          <stop offset="90%" stopColor="#fff" stopOpacity="0.30"/>
          <stop offset="100%" stopColor="#fff" stopOpacity="0.0"/>
        </radialGradient>
      </defs>
      <rect width="300" height="300" fill="#000"/>
      <circle cx="150" cy="150" r="148" fill="url(#thon-ctf)"/>
      {/* Astigmatism stretch hint */}
      <ellipse cx="150" cy="150" rx="148" ry="142" fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth="1"/>
      {/* Resolution rings */}
      {[40, 80, 120].map(r => (
        <circle key={r} cx="150" cy="150" r={r} fill="none" stroke="oklch(0.62 0.16 30 / 0.35)" strokeDasharray="2 4" strokeWidth="0.7"/>
      ))}
      <text x="194" y="153" fontSize="9" fill="oklch(0.7 0.12 30)" fontFamily="var(--font-mono)">5.0 Å</text>
      <text x="234" y="153" fontSize="9" fill="oklch(0.7 0.12 30)" fontFamily="var(--font-mono)">3.0 Å</text>
    </svg>
    <Caption>
      Thon-ring power spectrum · best fit at <b>4.2 Å</b> · defocus 1.48 µm · astigmatism 280 Å (within tolerance).
    </Caption>
  </div>
);

const VizCtfTable = () => {
  const rng = seeded('ctf');
  const rows = Array.from({length: 6}, (_,i) => ({
    mg: `mic_${String(i+1).padStart(4,'0')}.mrc`,
    du: (10000 + rng()*8000).toFixed(0),
    dv: (10000 + rng()*8000).toFixed(0),
    ang: (rng()*180).toFixed(1),
    fit: (0.18 + rng()*0.18).toFixed(2),
    res: (3.6 + rng()*1.4).toFixed(2),
  }));
  return (
    <div>
      <table style={{width:'100%', borderCollapse:'collapse', fontFamily:'var(--font-mono)', fontSize:11}}>
        <thead>
          <tr style={{background:'var(--surface-2)', textAlign:'left'}}>
            <th style={{padding:'6px 8px'}}>Micrograph</th>
            <th style={{padding:'6px 8px'}}>DefU (Å)</th>
            <th style={{padding:'6px 8px'}}>DefV (Å)</th>
            <th style={{padding:'6px 8px'}}>Angle°</th>
            <th style={{padding:'6px 8px'}}>FitQ</th>
            <th style={{padding:'6px 8px'}}>CTF res (Å)</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(r => (
            <tr key={r.mg} style={{borderTop:'1px solid var(--border)'}}>
              <td style={{padding:'5px 8px'}}>{r.mg}</td>
              <td style={{padding:'5px 8px'}}>{r.du}</td>
              <td style={{padding:'5px 8px'}}>{r.dv}</td>
              <td style={{padding:'5px 8px'}}>{r.ang}</td>
              <td style={{padding:'5px 8px', color: parseFloat(r.fit) > 0.25 ? 'var(--ok)' : 'var(--text)'}}>{r.fit}</td>
              <td style={{padding:'5px 8px'}}>{r.res}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <Caption>
        842 rows · 6 shown · median CTF resolution <b>4.18 Å</b> · 12 micrographs flagged for FitQ &lt; 0.20 (auto-removed).
      </Caption>
    </div>
  );
};

const VizClass2D = ({ clean }) => {
  const cells = Array.from({length: 24}, (_,i) => i);
  return (
    <div>
      <div style={{display:'grid', gridTemplateColumns:'repeat(8, 1fr)', gap:4}}>
        {cells.map(i => {
          const isJunk = !clean && (i === 3 || i === 7 || i === 14 || i === 21);
          const seed = i * 13 + 5;
          return (
            <div key={i} style={{position:'relative', aspectRatio:'1', background:'#000', borderRadius:3, overflow:'hidden',
              outline: isJunk ? '1.5px solid var(--err)' : 'none'}}>
              <svg viewBox="0 0 40 40" style={{width:'100%', height:'100%'}}>
                <defs>
                  <radialGradient id={`c2d-${i}`} cx="50%" cy="50%">
                    <stop offset="0%" stopColor="#fff" stopOpacity={isJunk ? 0.35 : 0.85}/>
                    <stop offset="40%" stopColor="#dde" stopOpacity={isJunk ? 0.20 : 0.55}/>
                    <stop offset="100%" stopColor="#000" stopOpacity="0"/>
                  </radialGradient>
                </defs>
                <rect width="40" height="40" fill="#0a0a14"/>
                {/* class blob */}
                {!isJunk && (
                  <ellipse cx="20" cy="20"
                    rx={9 + (seed % 5)}
                    ry={7 + ((seed+3) % 5)}
                    transform={`rotate(${(seed*17) % 180} 20 20)`}
                    fill={`url(#c2d-${i})`}/>
                )}
                {/* secondary lobe */}
                {!isJunk && i % 3 === 0 && (
                  <ellipse cx={14 + ((seed*5)%10)} cy={14 + ((seed*7)%10)}
                    rx="3" ry="4" fill="rgba(255,255,255,0.4)"/>
                )}
                {isJunk && (
                  <circle cx="20" cy="20" r="14" fill={`url(#c2d-${i})`}/>
                )}
              </svg>
              <span style={{position:'absolute', top:2, left:3, fontSize:7, color:'#aab', fontFamily:'var(--font-mono)'}}>
                {String(i+1).padStart(2,'0')}
              </span>
            </div>
          );
        })}
      </div>
      <Caption>
        {clean ? '24/24 classes retained · all show clear secondary structure features.'
              : '24 classes · 4 flagged as junk (outlined red) — auto-excluded from particle subset.'}
      </Caption>
    </div>
  );
};

const VizFsc = () => {
  // FSC curve: starts at 1, drops with ripples, crosses 0.143 at ~3.2 Å
  const N = 80;
  const pts = [];
  for (let i = 0; i < N; i++) {
    const x = i / (N-1);
    const y = Math.max(0, Math.cos(x * 2.0) * (1 - x*0.7) + (Math.sin(x*8) * 0.04));
    pts.push([40 + x * 320, 240 - y * 200]);
  }
  return (
    <div>
      <svg viewBox="0 0 400 280" style={{width:'100%', background:'var(--surface)', borderRadius:'var(--r-sm)'}}>
        {/* Grid */}
        {[0, 0.143, 0.5, 1.0].map(v => (
          <g key={v}>
            <line x1="40" y1={240 - v*200} x2="360" y2={240 - v*200}
              stroke="var(--border)" strokeWidth="0.7" strokeDasharray={v===0.143 ? '4 3' : '1 3'}/>
            <text x="34" y={240 - v*200 + 3} fontSize="9" fill="var(--text-dim)" textAnchor="end">{v}</text>
          </g>
        ))}
        {/* axes */}
        <line x1="40" y1="240" x2="360" y2="240" stroke="var(--border-strong)"/>
        <line x1="40" y1="40"  x2="40"  y2="240" stroke="var(--border-strong)"/>
        <text x="200" y="266" fontSize="10" fill="var(--text-dim)" textAnchor="middle">Resolution (1/Å)</text>
        <text x="14" y="140" fontSize="10" fill="var(--text-dim)" textAnchor="middle" transform="rotate(-90 14 140)">FSC</text>
        {/* curve */}
        <polyline fill="none" stroke="oklch(0.55 0.18 250)" strokeWidth="1.8" points={pts.map(p=>p.join(',')).join(' ')}/>
        {/* 0.143 marker */}
        <circle cx="232" cy={240 - 0.143*200} r="3.5" fill="oklch(0.62 0.16 30)"/>
        <text x="240" y={240 - 0.143*200 - 6} fontSize="10" fill="oklch(0.55 0.18 30)">0.143 → 3.21 Å</text>
        {/* 0.5 marker */}
        <circle cx="146" cy={240 - 0.5*200} r="3" fill="oklch(0.6 0.13 200)"/>
        <text x="154" y={240 - 0.5*200 - 6} fontSize="10" fill="oklch(0.5 0.13 200)">0.5 → 3.62 Å</text>
      </svg>
      <Caption>
        Gold-standard FSC · two independent half-maps · resolution at FSC <b>0.143 = 3.21 Å</b>, FSC <b>0.5 = 3.62 Å</b>.
      </Caption>
    </div>
  );
};

const VizVolume = ({ kind = 'iso' }) => {
  // Simplified isosurface render — three rotated ellipsoids forming a protein silhouette
  const colour = kind === 'sharp' ? 'oklch(0.78 0.13 80)' : 'oklch(0.62 0.10 200)';
  return (
    <div>
      <svg viewBox="0 0 320 240" style={{width:'100%', background:'#0c1118', borderRadius:'var(--r-sm)'}}>
        <defs>
          <radialGradient id={`vol-grad-${kind}`} cx="35%" cy="32%">
            <stop offset="0%"  stopColor={colour} stopOpacity="0.95"/>
            <stop offset="55%" stopColor={colour} stopOpacity="0.55"/>
            <stop offset="100%" stopColor={colour} stopOpacity="0.05"/>
          </radialGradient>
          <filter id="blob-blur"><feGaussianBlur stdDeviation="1.5"/></filter>
        </defs>
        {/* lobes */}
        <g filter="url(#blob-blur)">
          <ellipse cx="130" cy="120" rx="62" ry="52" fill={`url(#vol-grad-${kind})`} transform="rotate(-12 130 120)"/>
          <ellipse cx="190" cy="110" rx="52" ry="40" fill={`url(#vol-grad-${kind})`} transform="rotate(20 190 110)"/>
          <ellipse cx="170" cy="160" rx="48" ry="32" fill={`url(#vol-grad-${kind})`} transform="rotate(-30 170 160)"/>
          <ellipse cx="100" cy="160" rx="32" ry="24" fill={`url(#vol-grad-${kind})`}/>
          <ellipse cx="220" cy="160" rx="28" ry="20" fill={`url(#vol-grad-${kind})`}/>
        </g>
        {/* helical detail lines (only in sharp mode) */}
        {kind === 'sharp' && Array.from({length: 14}).map((_,i) => (
          <line key={i}
            x1={80 + (i*12) % 180} y1={90 + ((i*7) % 80)}
            x2={80 + (i*12) % 180 + 14} y2={90 + ((i*7) % 80) + 8}
            stroke="rgba(255,255,255,0.5)" strokeWidth="0.8"/>
        ))}
        {/* axes ticker */}
        <g fontFamily="var(--font-mono)" fontSize="9" fill="rgba(220,225,235,0.5)">
          <text x="14" y="20">x</text><text x="14" y="32">y</text><text x="14" y="44">z</text>
          <text x="284" y="228">σ = 5.0</text>
        </g>
      </svg>
      <Caption>
        {kind === 'sharp'
          ? 'B-factor sharpened map · ChimeraX-rendered · σ-threshold 5.0 · helical features visible.'
          : kind === 'mask'
          ? 'Soft-edged solvent mask · used for the masked FSC calculation.'
          : 'Isosurface preview · σ-threshold 5.0 · rotate / threshold in the file viewer.'}
      </Caption>
    </div>
  );
};

const VizPickOverlay = () => {
  return (
    <div>
      <svg viewBox="0 0 360 240" style={{width:'100%', background:'#0a0d12', borderRadius:'var(--r-sm)'}}>
        <defs>
          <radialGradient id="pick-bg" cx="50%" cy="50%">
            <stop offset="0%"  stopColor="#384256"/>
            <stop offset="80%" stopColor="#10141d"/>
          </radialGradient>
        </defs>
        <rect width="360" height="240" fill="url(#pick-bg)"/>
        {Array.from({length:48}).map((_,i) => {
          const seed = i * 19 + 7;
          const cx = (seed * 13) % 340 + 10;
          const cy = (seed * 17) % 220 + 10;
          return (
            <g key={i}>
              <circle cx={cx} cy={cy} r="4" fill="rgba(220,220,230,0.5)"/>
              <circle cx={cx} cy={cy} r="11" fill="none" stroke="oklch(0.7 0.16 130)" strokeWidth="1"/>
            </g>
          );
        })}
      </svg>
      <Caption>
        Topaz picks overlaid on a representative micrograph · 48 boxes shown · <b>1.24M</b> particles total across 842 micrographs.
      </Caption>
    </div>
  );
};

const VizParticleGrid = () => {
  const cells = Array.from({length: 32}, (_,i) => i);
  return (
    <div>
      <div style={{display:'grid', gridTemplateColumns:'repeat(8, 1fr)', gap:3}}>
        {cells.map(i => {
          const seed = i * 11 + 1;
          return (
            <div key={i} style={{aspectRatio:'1', background:'#0a0a14', borderRadius:2, overflow:'hidden'}}>
              <svg viewBox="0 0 30 30" style={{width:'100%', height:'100%'}}>
                <defs>
                  <radialGradient id={`pg-${i}`} cx="50%" cy="50%">
                    <stop offset="0%" stopColor="#fff" stopOpacity="0.7"/>
                    <stop offset="60%" stopColor="#bbc" stopOpacity="0.35"/>
                    <stop offset="100%" stopColor="#000" stopOpacity="0"/>
                  </radialGradient>
                </defs>
                <rect width="30" height="30" fill="#0a0a14"/>
                <ellipse cx="15" cy="15"
                  rx={5 + (seed%4)} ry={5 + ((seed+2)%3)}
                  transform={`rotate(${(seed*23)%180} 15 15)`}
                  fill={`url(#pg-${i})`}/>
              </svg>
            </div>
          );
        })}
      </div>
      <Caption>
        Particle stack preview · 32 of <b>1,243,118</b> · 320 px box · CTF-corrected · ready for 2D classification.
      </Caption>
    </div>
  );
};

const VizTrainingCurve = () => {
  // Loss curve descending with a small bump
  const N = 40;
  const pts = Array.from({length: N}, (_, i) => {
    const x = i / (N - 1);
    const y = Math.max(0.1, 0.95 * Math.exp(-x * 2.5) + (Math.sin(i*0.7) * 0.02));
    return [40 + x * 320, 220 - y * 180];
  });
  return (
    <div>
      <svg viewBox="0 0 380 260" style={{width:'100%', background:'var(--surface)', borderRadius:'var(--r-sm)'}}>
        <line x1="40" y1="220" x2="360" y2="220" stroke="var(--border-strong)"/>
        <line x1="40" y1="40"  x2="40"  y2="220" stroke="var(--border-strong)"/>
        <text x="200" y="246" fontSize="10" fill="var(--text-dim)" textAnchor="middle">Epoch</text>
        <text x="16" y="130" fontSize="10" fill="var(--text-dim)" textAnchor="middle" transform="rotate(-90 16 130)">Loss</text>
        <polyline fill="none" stroke="oklch(0.55 0.18 250)" strokeWidth="1.8" points={pts.map(p=>p.join(',')).join(' ')}/>
      </svg>
      <Caption>
        Topaz model training · 10 epochs · final loss <b>0.083</b> · early-stopping not triggered.
      </Caption>
    </div>
  );
};

const VizValReport = () => {
  return (
    <div style={{background:'var(--surface)', padding:14, borderRadius:'var(--r-sm)', fontSize:12.5, lineHeight:1.55}}>
      <div style={{fontWeight:600, fontSize:14, marginBottom:6}}>EMDB Validation Report (preview)</div>
      <div style={{color:'var(--text-muted)'}}>
        <div><b>Map:</b> sharpened_map.mrc · <b>Pixel size:</b> 1.30 Å/px · <b>Box:</b> 320³ </div>
        <div><b>Resolution (FSC 0.143):</b> 3.21 Å · <b>Resolution (FSC 0.5):</b> 3.62 Å</div>
        <div><b>Recommended display threshold:</b> σ = 5.0</div>
        <div><b>Map–map correlation (half-maps):</b> 0.94 across resolution shells</div>
        <div style={{marginTop:8, color:'var(--ok)'}}>✓ Passes all EMDB validation checks at the deposited resolution.</div>
      </div>
    </div>
  );
};

// Picker — chooses the right visualization for an output file
function OutputViz({ file }) {
  const v = file.viz;
  if (v === 'motion')          return <VizMotion/>;
  if (v === 'micrographs')     return <VizMicrographs/>;
  if (v === 'thon_rings')      return <VizThonRings/>;
  if (v === 'ctf_table')       return <VizCtfTable/>;
  if (v === 'training_curve')  return <VizTrainingCurve/>;
  if (v === 'pick_overlay')    return <VizPickOverlay/>;
  if (v === 'particle_grid')   return <VizParticleGrid/>;
  if (v === 'class2d')         return <VizClass2D clean={false}/>;
  if (v === 'class2d_clean')   return <VizClass2D clean={true}/>;
  if (v === 'volume_slices')   return <VizVolume kind="slices"/>;
  if (v === 'volume_iso')      return <VizVolume kind="iso"/>;
  if (v === 'volume_sharp')    return <VizVolume kind="sharp"/>;
  if (v === 'mask_slice')      return <VizVolume kind="mask"/>;
  if (v === 'fsc_curve')       return <VizFsc/>;
  if (v === 'val_report')      return <VizValReport/>;
  // fallback — text preview
  const text = `# ${file.name}\n\n[ no visualization registered for this file type ]\n\nDownload to inspect locally.`;
  return <div className="preview-body" style={{padding:0}}>{text}</div>;
}

function PreviewModal({ file, onClose }) {
  if (!file) return null;
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal preview-modal" onClick={e => e.stopPropagation()} style={{maxWidth:560}}>
        <div className="body" style={{paddingBottom:0}}>
          <div style={{display:'flex', alignItems:'center', justifyContent:'space-between'}}>
            <div>
              <h3 className="mono" style={{fontSize:13, margin:0}}>{file.name}</h3>
              <div style={{fontSize:11, color:'var(--text-dim)', marginTop:3}}>
                Step output · interactive preview · σ / threshold / colormap available in the full viewer
              </div>
            </div>
            <button className="btn ghost sm" onClick={onClose}><Icon name="x" size={14}/></button>
          </div>
        </div>
        <div style={{padding:'8px 18px 16px'}}>
          <OutputViz file={file}/>
        </div>
        <div className="foot">
          <button className="btn sm"><Icon name="download" size={12}/> Download</button>
          <button className="btn sm"><Icon name="external" size={12}/> Open in viewer</button>
        </div>
      </div>
    </div>
  );
}

// ── Methods Report Modal ─────────────────────────────────────────────

function ReportModal({ scenario, onClose }) {
  if (!scenario) return null;
  const [tab, setTab] = useStateM('findings');

  // Per-scenario summary copy + headline metrics for the Findings tab.
  // Methods/Parameters/Software/Citations remain CryoSPARC-flavored for now
  // (they're paste-ready text examples for the spec). When this ships, the
  // text will be auto-generated from the run manifest.
  const findings = {
    cryosparc: {
      headline: 'Reconstruction converged at 3.21 Å (GSFSC 0.143).',
      bullets: [
        'Particle heterogeneity low; sharpening applied (B = −84 Å²).',
        '823,401 particles retained after 2D classification.',
        'Half-map FSC 0.5 at 3.62 Å · FSC 0.143 at 3.21 Å.',
      ],
      table: [
        ['Resolution (FSC 0.143)', '3.21 Å'],
        ['Particles (final)',      '823,401'],
        ['Runtime',                '42m 18s'],
        // ['Compute cost',           '$2.41'],  // commented out, leaving for future work
      ],
    },
    gatk: {
      headline: 'Called 4.21 M variants; Ts/Tv = 2.07.',
      bullets: [
        'dbSNP overlap 96.4% — consistent with high-quality WGS.',
        '142 ClinVar pathogenic hits flagged after annotation.',
        'VQSR retained 3.84 M PASS variants.',
      ],
      table: [
        ['PASS variants',           '3,840,217'],
        ['Ts/Tv ratio',             '2.07'],
        ['ClinVar pathogenic',      '142'],
        ['Runtime',                 '34m 18s'],
      ],
    },
    admet: {
      headline: 'Aspirin shows favorable absorption · moderate hERG risk.',
      bullets: [
        'Flag for DDI review on CYP2C9.',
        'Lipinski Ro5 compliant (0 violations).',
        'Predicted plasma protein binding 99.4%.',
      ],
      table: [
        ['Endpoints predicted', '7'],
        ['Ro5 violations',     '0'],
        ['hERG flag',          'moderate'],
        ['Runtime',            '8s'],
      ],
    },
    nfcore: {
      headline: '93.4% reads passed Q30. No adapter contamination.',
      bullets: [
        '2 accessions analyzed in parallel.',
        'Mean Phred score 36.2 across both runs.',
      ],
      table: [
        ['Reads passing Q30',   '93.4%'],
        ['Adapter contamination','none'],
        ['Mean Phred',          '36.2'],
        ['Runtime',             '6m 04s'],
      ],
    },
  }[scenario.id] || {
    headline: 'Run complete.',
    bullets: ['Outputs are listed in the Outputs tab.'],
    table: [['Runtime', '—']],
  };

  // Outputs list — flatten every step's outputs into one table.
  const outputs = [];
  scenario.phases.forEach(p => {
    (p.steps || []).forEach(s => {
      (s.outputs || []).forEach(o => {
        outputs.push({ phase: p.id + ' · ' + p.name, step: s.name, file: o.name, type: o.type });
      });
    });
  });

  const tabs = [
    ['findings', 'Findings'],
    ['outputs',  'Outputs'],
    ['imrad',    'Methods'],
    ['params',   'Parameters'],
    ['software', 'Software'],
    ['cite',     'Citations'],
  ];

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal preview-modal" onClick={e => e.stopPropagation()} style={{maxWidth:760, maxHeight:'88vh'}} data-tour="report-modal">
        <div className="body" style={{paddingBottom:0}}>
          <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:10}}>
            <div>
              <h3 style={{fontSize:14, margin:0}} data-tour="report-title">Report</h3>
              <div style={{fontSize:11, color:'var(--text-dim)', marginTop:3}}>
                {scenario.name} · outputs, findings, methods · paste-ready
              </div>
            </div>
            <button className="btn ghost sm" onClick={onClose}><Icon name="x" size={14}/></button>
          </div>
          <div style={{display:'flex', gap:0, borderBottom:'1px solid var(--border)', overflowX:'auto'}} data-tour="report-tabs">
            {tabs.map(([k, lbl]) => (
              <button key={k}
                data-tour={'report-tab-' + k}
                onClick={() => setTab(k)}
                style={{
                  padding:'8px 14px', fontSize:12, background:'none', border:'none', cursor:'pointer',
                  color: tab === k ? 'var(--text)' : 'var(--text-muted)',
                  borderBottom: tab === k ? '2px solid var(--accent, oklch(0.55 0.18 250))' : '2px solid transparent',
                  fontWeight: tab === k ? 600 : 500, whiteSpace: 'nowrap',
                }}>{lbl}</button>
            ))}
          </div>
        </div>
        <div style={{padding:'14px 22px 20px', overflowY:'auto', maxHeight:'62vh', fontSize:12.5, lineHeight:1.65, color:'var(--text)'}} data-tour="report-body">
          {tab === 'findings' && <ReportFindings findings={findings}/>}
          {tab === 'outputs'  && <ReportOutputs outputs={outputs} scenario={scenario}/>}
          {tab === 'imrad' && (
            <ReportMethodsImrad/>
          )}
          {tab === 'params' && <ReportParams/>}
          {tab === 'software' && <ReportSoftware/>}
          {tab === 'cite' && <ReportCitations/>}
        </div>
        <div className="foot" data-tour="report-foot">
          <span style={{flex:1, fontSize:11, color:'var(--text-dim)'}}>
            Generated 2026-04-19 · runId <span className="mono">cs_2026-0419-r3</span>
          </span>
          <button className="btn sm"><Icon name="download" size={12}/> DOCX</button>
          <button className="btn sm"><Icon name="download" size={12}/> Markdown</button>
          <button className="btn sm"><Icon name="download" size={12}/> LaTeX</button>
        </div>
      </div>
    </div>
  );
}

// ── Report sub-components (tab bodies) ───────────────────────────────

function ReportFindings({ findings }) {
  return (
    <div>
      <div style={{
        fontSize: 13, fontWeight: 600, color: 'var(--text)',
        marginBottom: 10, lineHeight: 1.5,
      }}>{findings.headline}</div>
      <ul style={{margin: '0 0 14px', paddingLeft: 18, color: 'var(--text-muted)'}}>
        {findings.bullets.map((b, i) => <li key={i} style={{marginBottom: 4}}>{b}</li>)}
      </ul>
      <div style={{
        fontSize: 11, color: 'var(--text-dim)', textTransform: 'uppercase',
        letterSpacing: '0.05em', fontWeight: 600, marginBottom: 6,
      }}>Headline metrics</div>
      <table style={{width: '100%', borderCollapse: 'collapse', fontSize: 12.5}}>
        <tbody>
          {findings.table.map((r, i) => (
            <tr key={i} style={{borderTop: i === 0 ? 'none' : '1px dashed var(--border)'}}>
              <td style={{padding: '7px 0', color: 'var(--text-muted)'}}>{r[0]}</td>
              <td style={{padding: '7px 0', fontFamily: 'var(--font-mono)', textAlign: 'right'}}>{r[1]}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <div style={{
        marginTop: 14, padding: 10, background: 'var(--surface)', borderRadius: 'var(--r-sm)',
        fontSize: 11.5, color: 'var(--text-dim)', fontStyle: 'italic', lineHeight: 1.55,
      }}>
        Findings are generated directly from the run manifest. Numbers in this section come from outputs,
        not from the LLM.
      </div>
    </div>
  );
}

function ReportOutputs({ outputs, scenario, onDownloadAll }) {
  if (outputs.length === 0) {
    return (
      <div style={{color: 'var(--text-dim)', fontStyle: 'italic', padding: '8px 0'}}>
        No outputs registered for this scenario yet.
      </div>
    );
  }
  const iconFor = (t) => t === 'image' ? 'image' : t === 'folder' ? 'folder' : 'table';
  return (
    <div>
      <div style={{display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10}}>
        <div style={{fontSize: 11.5, color: 'var(--text-dim)', flex: 1, lineHeight: 1.5}}>
          {outputs.length} file{outputs.length === 1 ? '' : 's'} across {scenario.phases.length} phase{scenario.phases.length === 1 ? '' : 's'}.
        </div>
        <button className="btn sm" onClick={onDownloadAll} data-tour="link-download">
          <Icon name="download" size={11}/> Download all
        </button>
      </div>
      <table style={{width: '100%', borderCollapse: 'collapse', fontSize: 12, fontFamily: 'var(--font-mono)'}}>
        <thead>
          <tr style={{background: 'var(--surface-2)', textAlign: 'left'}}>
            <th style={{padding: '6px 8px'}}>Phase / Step</th>
            <th style={{padding: '6px 8px'}}>File</th>
            <th style={{padding: '6px 8px', width: 80}}>Type</th>
            <th style={{padding: '6px 8px', width: 100}}></th>
          </tr>
        </thead>
        <tbody>
          {outputs.map((o, i) => (
            <tr key={i} style={{borderTop: '1px solid var(--border)'}}>
              <td style={{padding: '6px 8px', color: 'var(--text-muted)'}}>{o.phase} · {o.step}</td>
              <td style={{padding: '6px 8px'}}>
                <span style={{display: 'inline-flex', alignItems: 'center', gap: 5}}>
                  <Icon name={iconFor(o.type)} size={11}/>
                  <span style={{color: 'var(--text)'}}>{o.file}</span>
                </span>
              </td>
              <td style={{padding: '6px 8px', color: 'var(--text-dim)'}}>{o.type}</td>
              <td style={{padding: '6px 8px', fontFamily: 'var(--font-ui)'}}>
                <button className="linkish" style={{fontSize: 11, marginRight: 8}}>view</button>
                <button className="linkish" style={{fontSize: 11}}>dl</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── bioc Report tabs: pulled from existing handoff sources, no new prose.
// Methods/Software/QC bodies come from BiocTours.jsx sw.* blocks lifted as
// string constants. Parameters rows come from the active scenario's
// phases[].steps[].params (data.js BIOC_*). Citations are fetched by the
// caller from /api/workflows/:name/citations (qc_evidence.yaml).
const BIOC_KB_SW = {
  methodsBody: 'Paragraph-form Methods you can paste into a manuscript — tools, versions and exact parameters, written so peers can replicate the DESeq2 run.',
  paramsBody:  'Phase · step · parameter · value for everything the run touched — from filterByExpr thresholds to the apeglm shrinkage type. A ready supplementary table.',
  softwareList: ['DESeq2', 'apeglm', 'edgeR', 'clusterProfiler', 'EnhancedVolcano'],
  qcBody: 'Every QC gate that fired — gene-retention, size-factor range, replicate count — with threshold, observed value, result and action. 21 CFR Part 11 friendly, with chain-of-custody.',
  citations: [
    'Love MI, Huber W, Anders S. Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2. Genome Biology 2014;15:550.',
    'Zhu A, Ibrahim JG, Love MI. Heavy-tailed prior distributions for sequence count data: apeglm. Bioinformatics 2019;35:2084-2092.',
    'Wu T, Hu E, Xu S, et al. clusterProfiler 4.0: A universal enrichment tool for interpreting omics data. The Innovation 2021;2:100141.',
  ],
};
const BIOC_SC_SW = {
  methodsBody: 'Paste-ready Methods — emptyDrops QC, scran normalisation, SNN/Louvain clustering, SingleR annotation, and aggregateAcrossCells → DESeq2, with versions and parameters.',
  paramsBody:  'Phase · step · parameter · value — emptyDrops FDR, HVG count, SNN k, the SingleR reference, the pseudobulk design. A ready supplementary table.',
  softwareList: ['DropletUtils', 'scran', 'scater', 'SingleR', 'DESeq2'],
  qcBody: 'Every QC gate that fired — cells retained, HVG count, clusters resolved, pseudobulk replicates — with threshold, observed value, result and action.',
  citations: [
    'McCarthy DJ, Campbell KR, Lun ATL, Wills QF. Scater. Bioinformatics 2017;33:1179-1186.',
    'Lun ATL, McCarthy DJ, Marioni JC. A step-by-step workflow for low-level analysis of single-cell RNA-seq data with Bioconductor. F1000Research 2016;5:2122.',
    'Aran D, Looney AP, Liu L, et al. SingleR. Nature Immunology 2019;20:163-172.',
    'Crowell HL, Soneson C, Germain PL, et al. muscat (pseudobulk DESeq2). Nature Communications 2020;11:6077.',
  ],
};
const BIOC_METHYL_SW = {
  methodsBody: 'Paste-ready Methods — read.metharray, detection-p QC, SNP/cross-reactive filtering, preprocessQuantile, limma DMPs, DMRcate DMRs, gometh enrichment — with versions and parameters.',
  paramsBody:  'Phase · step · parameter · value — detection-p cutoff, the M-value design, DMRcate kernel λ + significance cutoff, the gometh array type. A ready supplementary table.',
  softwareList: ['minfi', 'limma', 'DMRcate', 'missMethyl'],
  qcBody: 'Every QC gate that fired — samples read, probes retained, significant CpG count, DMR count — with threshold, observed value, result and action.',
  citations: [
    'Aryee MJ, Jaffe AE, et al. minfi. Bioinformatics 2014;30:1363-1369.',
    'Ritchie ME, Phipson B, et al. limma. Nucleic Acids Res 2015;43:e47.',
    'Peters TJ, Buckley MJ, et al. De novo identification of differentially methylated regions (DMRcate). Epigenetics & Chromatin 2015;8:6.',
    'Phipson B, Maksimovic J, Oshlack A. missMethyl. Bioinformatics 2016;32:286-288.',
  ],
};
const BIOC_SW = { bioc_kb: BIOC_KB_SW, bioc_sc: BIOC_SC_SW, bioc_methyl: BIOC_METHYL_SW };

function ReportMethodsImrad({ scenario } = {}) {
  const sw = scenario && BIOC_SW[scenario.id];
  if (sw) {
    return (
      <div>
        <h4 style={{fontSize:13, margin:'4px 0 6px'}}>Methods · {scenario.name}</h4>
        <p style={{lineHeight:1.55}}>{sw.methodsBody}</p>
      </div>
    );
  }
  return (
    <div>
      <h4 style={{fontSize:13, margin:'4px 0 6px'}}>Methods (Cryo-electron microscopy)</h4>
      <p>
        Single-particle cryo-electron microscopy data were processed using BioMate (v0.9.4)
        orchestrating CryoSPARC (v4.4.1) on AWS Batch (g5.2xlarge × 4). Movie frames were aligned
        with <b>MotionCor2</b> using a 5×5 patch grid and a maximum allowed shift of 20 Å per
        frame; mean total motion across <b>842 micrographs</b> was 3.42 Å.
      </p>
      <p>
        Contrast transfer function (CTF) parameters were estimated with <b>Gctf</b> over the
        resolution range 3.0–30 Å and defocus range 0.5–4.0 µm; the median CTF fit resolution was
        4.18 Å. 12 micrographs failing fit-quality &gt; 0.20 were automatically discarded by the
        CTFQualityGate. Particles (<b>1.24 M</b>) were picked using a <b>Topaz</b> ResNet8 model
        trained for 10 epochs (final loss 0.083), then extracted into a 320 px box.
      </p>
      <p>
        Two-dimensional classification was performed in two rounds (50 classes × 25 iterations);
        4 junk classes were excluded between rounds, retaining <b>823,401</b> particles. Initial
        3D models were generated by ab-initio reconstruction with three classes; the dominant
        class entered <b>homogeneous</b>, then <b>non-uniform</b>, then <b>local</b> refinement.
        Half-map agreement was evaluated by <b>gold-standard FSC</b>; resolution by FSC = 0.143
        was <b>3.21 Å</b> (FSC = 0.5: 3.62 Å). The map was <b>B-factor sharpened</b> automatically
        (B = -84 Å²) for visualization at σ = 5.0.
      </p>
      <p style={{color:'var(--text-muted)', fontSize:12, fontStyle:'italic'}}>
        Resolution and B-factor values are read directly from the run manifest; no values in this
        paragraph were inferred.
      </p>
    </div>
  );
}

function ReportParams({ scenario } = {}) {
  const sw = scenario && BIOC_SW[scenario.id];
  if (sw) {
    // Pull rows directly from scenario.phases[].steps[].params (data.js).
    // Every value is designer-authored in the panel scenario — no fabrication.
    const dataRows = [];
    (scenario.phases || []).forEach(p => (p.steps || []).forEach(s => (s.params || []).forEach(kv =>
      dataRows.push([`${p.id} · ${s.name}`, kv.k, String(kv.v)])
    )));
    if (dataRows.length === 0) return (
      <div style={{fontSize:12, color:'var(--text-muted)'}}>{sw.paramsBody}</div>
    );
    return (
      <div>
        <p style={{fontSize:12, color:'var(--text-muted)', margin:'0 0 8px'}}>{sw.paramsBody}</p>
        <table style={{width:'100%', borderCollapse:'collapse', fontSize:12, fontFamily:'var(--font-mono)'}}>
          <thead><tr style={{background:'var(--surface-2)', textAlign:'left'}}>
            <th style={{padding:'6px 8px'}}>Phase / Step</th>
            <th style={{padding:'6px 8px'}}>Parameter</th>
            <th style={{padding:'6px 8px'}}>Value</th>
          </tr></thead>
          <tbody>
            {dataRows.map((r, i) => (
              <tr key={i} style={{borderTop:'1px solid var(--border)'}}>
                <td style={{padding:'6px 8px'}}>{r[0]}</td>
                <td style={{padding:'6px 8px'}}>{r[1]}</td>
                <td style={{padding:'6px 8px'}}>{r[2]}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  }
  const rows = [
    ['Global', 'pixel_size', '1.30 Å/px'],
    ['Global', 'accel_kv', '300'],
    ['A · MotionCor2', 'patch_x × patch_y', '5 × 5'],
    ['A · MotionCor2', 'max_shift', '20 Å'],
    ['A · Gctf', 'resolution_range', '3.0–30 Å'],
    ['A · Gctf', 'defocus_range', '0.5–4.0 µm'],
    ['B · Topaz Train', 'arch / epochs', 'resnet8 / 10'],
    ['B · Topaz Pick', 'threshold', '-2'],
    ['B · Extract', 'box_size', '320 px'],
    ['C · 2D Classify rd1', 'classes / iter', '50 / 25'],
    ['D · Hom Refine', 'symmetry', 'C1'],
    ['E · Sharpen', 'b_factor', 'auto (-84 Å²)'],
    ['E · FSC', 'mask', 'soft, 6 px cosine'],
  ];
  return (
    <table style={{width:'100%', borderCollapse:'collapse', fontSize:12, fontFamily:'var(--font-mono)'}}>
      <thead><tr style={{background:'var(--surface-2)', textAlign:'left'}}>
        <th style={{padding:'6px 8px'}}>Phase / Step</th>
        <th style={{padding:'6px 8px'}}>Parameter</th>
        <th style={{padding:'6px 8px'}}>Value</th>
      </tr></thead>
      <tbody>
        {rows.map((r, i) => (
          <tr key={i} style={{borderTop:'1px solid var(--border)'}}>
            <td style={{padding:'6px 8px'}}>{r[0]}</td>
            <td style={{padding:'6px 8px'}}>{r[1]}</td>
            <td style={{padding:'6px 8px'}}>{r[2]}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function ReportSoftware({ scenario } = {}) {
  const sw = scenario && BIOC_SW[scenario.id];
  if (sw) {
    return (
      <ul style={{paddingLeft:18, margin:0}}>
        {sw.softwareList.map((name, i) => (<li key={i}><b>{name}</b></li>))}
      </ul>
    );
  }
  return (
    <ul style={{paddingLeft:18, margin:0}}>
      <li><b>BioMate</b> v0.9.4 · workflow orchestrator</li>
      <li><b>CryoSPARC</b> v4.4.1 · particle processing pipeline (Punjani et al., 2017)</li>
      <li><b>MotionCor2</b> v1.6.4 · beam-induced motion correction (Zheng et al., 2017)</li>
      <li><b>Gctf</b> v1.18 · CTF estimation (Zhang, 2016)</li>
      <li><b>Topaz</b> v0.2.5 · particle picking (Bepler et al., 2019)</li>
      <li><b>ChimeraX</b> v1.7 · isosurface rendering (Pettersen et al., 2021)</li>
      <li><b>RELION</b> v4.0 (auxiliary, mask generation only)</li>
    </ul>
  );
}

function ReportCitations({ scenario } = {}) {
  const sw = scenario && BIOC_SW[scenario.id];
  if (sw) {
    return (
      <ol style={{paddingLeft:20, margin:0}}>
        {sw.citations.map((r, i) => (<li key={i} style={{marginBottom:6}}><i>{r}</i></li>))}
      </ol>
    );
  }
  return (
    <ol style={{paddingLeft:20, margin:0}}>
      <li>Punjani A, Rubinstein JL, Fleet DJ, Brubaker MA. <i>cryoSPARC: algorithms for rapid unsupervised cryo-EM structure determination.</i> Nat Methods. 2017;14:290–296.</li>
      <li>Zheng SQ, Palovcak E, Armache JP, et al. <i>MotionCor2: anisotropic correction of beam-induced motion for improved cryo-electron microscopy.</i> Nat Methods. 2017;14:331–332.</li>
      <li>Zhang K. <i>Gctf: Real-time CTF determination and correction.</i> J Struct Biol. 2016;193:1–12.</li>
      <li>Bepler T, Morin A, Rapp M, et al. <i>Positive-unlabeled convolutional neural networks for particle picking in cryo-electron micrographs.</i> Nat Methods. 2019;16:1153–1160.</li>
      <li>Pettersen EF, Goddard TD, Huang CC, et al. <i>UCSF ChimeraX: Structure visualization for researchers, educators, and developers.</i> Protein Sci. 2021;30:70–82.</li>
    </ol>
  );
}

// ── QC Audit Modal ───────────────────────────────────────────────────

function QcAuditModal({ scenario, phases, onClose }) {
  if (!scenario) return null;
  // Build an audit log from the scenario's QC gates
  const events = [];
  let t = new Date('2026-04-19T08:14:21Z');
  const tick = (mins) => { t = new Date(t.getTime() + mins * 60_000); return t.toISOString().replace('T',' ').slice(0,19) + 'Z'; };
  (phases || scenario.phases || []).forEach(p => {
    (p.qc || []).forEach((g, i) => {
      const obs = (g.metric.includes('count') ? '1.24M' :
                   g.metric.includes('resolution') ? '3.21 Å' :
                   g.metric.includes('quality') ? '0.31' :
                   g.metric.includes('astigmatism') ? '280 Å' :
                   '0.143');
      const passed = !(p.id === 'A' && i === 0 && phases?.[0]?.steps?.[0]?.runCount > 1);
      events.push({
        ts: tick(8 + i*3),
        phase: `Phase ${p.id} — ${p.name}`,
        gate: g.metric,
        op: g.op,
        threshold: g.threshold,
        observed: obs,
        passed,
        action: passed ? 'continue' : 'auto-loop · re-run with adjusted parameters',
      });
    });
  });
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal preview-modal" onClick={e => e.stopPropagation()} style={{maxWidth:840, maxHeight:'88vh'}} data-tour="qc-modal">
        <div className="body" style={{paddingBottom:0}}>
          <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:10}}>
            <div>
              <h3 style={{fontSize:14, margin:0}} data-tour="qc-title">QC Audit Report</h3>
              <div style={{fontSize:11, color:'var(--text-dim)', marginTop:3}}>
                {scenario.name} · runId <span className="mono">cs_2026-0419-r3</span> · {events.length} gate evaluations · 21 CFR Part 11 compliant
              </div>
            </div>
            <button className="btn ghost sm" onClick={onClose}><Icon name="x" size={14}/></button>
          </div>
        </div>
        <div style={{padding:'8px 22px 18px', overflowY:'auto', maxHeight:'68vh'}}>
          {/* Summary card */}
          <div data-tour="qc-summary" style={{
            display:'grid', gridTemplateColumns:'repeat(4, 1fr)', gap:10, marginBottom:16,
          }}>
            {[
              ['Gates evaluated', events.length],
              ['Passed', events.filter(e => e.passed).length, 'var(--ok)'],
              ['Auto-corrected', events.filter(e => !e.passed).length, 'oklch(0.62 0.16 60)'],
              ['Manual interventions', 0],
            ].map((s, i) => (
              <div key={i} style={{
                background:'var(--surface)', padding:'10px 12px', borderRadius:'var(--r-sm)',
                border:'1px solid var(--border)',
              }}>
                <div style={{fontSize:10, color:'var(--text-dim)', textTransform:'uppercase', letterSpacing:0.5}}>{s[0]}</div>
                <div style={{fontSize:20, fontWeight:600, color: s[2] || 'var(--text)', marginTop:2}}>{s[1]}</div>
              </div>
            ))}
          </div>

          {/* Audit table */}
          <div style={{fontSize:11, color:'var(--text-dim)', textTransform:'uppercase', letterSpacing:0.5, marginBottom:6}}>
            Gate evaluation log
          </div>
          <table data-tour="qc-table" style={{width:'100%', borderCollapse:'collapse', fontSize:11.5, fontFamily:'var(--font-mono)'}}>
            <thead>
              <tr style={{background:'var(--surface-2)', textAlign:'left'}}>
                <th style={{padding:'7px 8px'}}>Timestamp (UTC)</th>
                <th style={{padding:'7px 8px'}}>Phase</th>
                <th style={{padding:'7px 8px'}}>Gate</th>
                <th style={{padding:'7px 8px'}}>Threshold</th>
                <th style={{padding:'7px 8px'}}>Observed</th>
                <th style={{padding:'7px 8px'}}>Result</th>
                <th style={{padding:'7px 8px'}}>Action</th>
              </tr>
            </thead>
            <tbody>
              {events.map((e, i) => (
                <tr key={i} style={{borderTop:'1px solid var(--border)'}}>
                  <td style={{padding:'7px 8px'}}>{e.ts}</td>
                  <td style={{padding:'7px 8px'}}>{e.phase}</td>
                  <td style={{padding:'7px 8px'}}>{e.gate}</td>
                  <td style={{padding:'7px 8px'}}>{e.op} {e.threshold}</td>
                  <td style={{padding:'7px 8px'}}>{e.observed}</td>
                  <td style={{padding:'7px 8px', color: e.passed ? 'var(--ok)' : 'oklch(0.62 0.16 60)', fontWeight:600}}>
                    {e.passed ? '✓ PASS' : '↻ FAIL → loop'}
                  </td>
                  <td style={{padding:'7px 8px', color:'var(--text-muted)'}}>{e.action}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <div data-tour="qc-chain" style={{marginTop:16, padding:'12px 14px', background:'var(--surface)', borderRadius:'var(--r-sm)',
            border:'1px solid var(--border)', fontSize:11.5, lineHeight:1.55, color:'var(--text-muted)'}}>
            <div style={{fontWeight:600, color:'var(--text)', marginBottom:4}}>Chain of custody</div>
            All raw inputs, intermediate outputs, and parameter sets are versioned via content-addressed
            storage (SHA-256). Each row above corresponds to a tamper-evident manifest entry. No human
            override modified this run.
          </div>

          <div data-tour="qc-sig" style={{marginTop:12, padding:'12px 14px', background:'var(--surface)', borderRadius:'var(--r-sm)',
            border:'1px solid var(--border)', fontSize:11.5, lineHeight:1.55}}>
            <div style={{fontWeight:600, marginBottom:4}}>Operator e-signature</div>
            <div style={{display:'flex', justifyContent:'space-between', alignItems:'center', color:'var(--text-muted)'}}>
              <span>Reviewed by Andrew Chen, PhD · 2026-04-19 22:18 UTC · TOTP verified</span>
              <span className="mono" style={{fontSize:10}}>
                sig:9f2a…b7e1
              </span>
            </div>
          </div>
        </div>
        <div className="foot">
          <span style={{flex:1, fontSize:11, color:'var(--text-dim)'}}>
            Auto-generated · publishable as supplementary file
          </span>
          <button className="btn sm"><Icon name="download" size={12}/> PDF</button>
          <button className="btn sm"><Icon name="download" size={12}/> CSV</button>
          <button className="btn sm"><Icon name="download" size={12}/> JSON</button>
        </div>
      </div>
    </div>
  );
}

// ── QC Audit panel body (reusable, no modal chrome) ─────────────────

function QcAuditPanel({ scenario, phases }) {
  if (!scenario) return null;
  const events = [];
  let t = new Date('2026-04-19T08:14:21Z');
  const tick = (mins) => { t = new Date(t.getTime() + mins * 60_000); return t.toISOString().replace('T',' ').slice(0,19) + 'Z'; };
  (phases || scenario.phases || []).forEach(p => {
    (p.qc || []).forEach((g, i) => {
      const obs = (g.metric.includes('count') ? '1.24M' :
                   g.metric.includes('resolution') ? '3.21 Å' :
                   g.metric.includes('quality') ? '0.31' :
                   g.metric.includes('astigmatism') ? '280 Å' :
                   '0.143');
      const passed = !(p.id === 'A' && i === 0 && phases?.[0]?.steps?.[0]?.runCount > 1);
      events.push({ ts: tick(8 + i*3), phase: `Phase ${p.id} — ${p.name}`, gate: g.metric, op: g.op,
        threshold: g.threshold, observed: obs, passed,
        action: passed ? 'continue' : 'auto-loop · re-run with adjusted parameters' });
    });
  });
  return (
    <div>
      <div data-tour="qc-summary" style={{display:'grid', gridTemplateColumns:'repeat(4, 1fr)', gap:10, marginBottom:16}}>
        {[
          ['Gates evaluated', events.length],
          ['Passed', events.filter(e => e.passed).length, 'var(--ok)'],
          ['Auto-corrected', events.filter(e => !e.passed).length, 'oklch(0.62 0.16 60)'],
          ['Manual interventions', 0],
        ].map((s, i) => (
          <div key={i} style={{background:'var(--surface)', padding:'10px 12px', borderRadius:'var(--r-sm)',
            border:'1px solid var(--border)'}}>
            <div style={{fontSize:10, color:'var(--text-dim)', textTransform:'uppercase', letterSpacing:0.5}}>{s[0]}</div>
            <div style={{fontSize:20, fontWeight:600, color: s[2] || 'var(--text)', marginTop:2}}>{s[1]}</div>
          </div>
        ))}
      </div>
      {events.length === 0 ? (
        <div style={{fontSize:12, color:'var(--text-dim)', fontStyle:'italic', padding:'8px 0'}}>
          No QC gates fired for this scenario.
        </div>
      ) : (
        <React.Fragment>
          <div style={{fontSize:11, color:'var(--text-dim)', textTransform:'uppercase', letterSpacing:0.5, marginBottom:6}}>
            Gate evaluation log
          </div>
          <table data-tour="qc-table" style={{width:'100%', borderCollapse:'collapse', fontSize:11.5, fontFamily:'var(--font-mono)'}}>
            <thead>
              <tr style={{background:'var(--surface-2)', textAlign:'left'}}>
                <th style={{padding:'7px 8px'}}>Timestamp (UTC)</th>
                <th style={{padding:'7px 8px'}}>Phase</th>
                <th style={{padding:'7px 8px'}}>Gate</th>
                <th style={{padding:'7px 8px'}}>Threshold</th>
                <th style={{padding:'7px 8px'}}>Observed</th>
                <th style={{padding:'7px 8px'}}>Result</th>
                <th style={{padding:'7px 8px'}}>Action</th>
              </tr>
            </thead>
            <tbody>
              {events.map((e, i) => (
                <tr key={i} style={{borderTop:'1px solid var(--border)'}}>
                  <td style={{padding:'7px 8px'}}>{e.ts}</td>
                  <td style={{padding:'7px 8px'}}>{e.phase}</td>
                  <td style={{padding:'7px 8px'}}>{e.gate}</td>
                  <td style={{padding:'7px 8px'}}>{e.op} {e.threshold}</td>
                  <td style={{padding:'7px 8px'}}>{e.observed}</td>
                  <td style={{padding:'7px 8px', color: e.passed ? 'var(--ok)' : 'oklch(0.62 0.16 60)', fontWeight:600}}>
                    {e.passed ? '✓ PASS' : '↻ FAIL → loop'}
                  </td>
                  <td style={{padding:'7px 8px', color:'var(--text-muted)'}}>{e.action}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <div data-tour="qc-chain" style={{marginTop:16, padding:'12px 14px', background:'var(--surface)',
            borderRadius:'var(--r-sm)', border:'1px solid var(--border)', fontSize:11.5, lineHeight:1.55, color:'var(--text-muted)'}}>
            <div style={{fontWeight:600, color:'var(--text)', marginBottom:4}}>Chain of custody</div>
            All raw inputs, intermediate outputs, and parameter sets are versioned via content-addressed storage
            (SHA-256). Each row above corresponds to a tamper-evident manifest entry. No human override modified this run.
          </div>
          <div data-tour="qc-sig" style={{marginTop:12, padding:'12px 14px', background:'var(--surface)',
            borderRadius:'var(--r-sm)', border:'1px solid var(--border)', fontSize:11.5, lineHeight:1.55}}>
            <div style={{fontWeight:600, marginBottom:4}}>Operator e-signature</div>
            <div style={{display:'flex', justifyContent:'space-between', alignItems:'center', color:'var(--text-muted)'}}>
              <span>Reviewed by Andrew Chen, PhD · 2026-04-19 22:18 UTC · TOTP verified</span>
              <span className="mono" style={{fontSize:10}}>sig:9f2a…b7e1</span>
            </div>
          </div>
        </React.Fragment>
      )}
    </div>
  );
}

Object.assign(window, { SkipConfirmModal, AdjustModal, PreviewModal, ReportModal, QcAuditModal,
  ReportFindings, ReportOutputs, ReportMethodsImrad, ReportParams, ReportSoftware, ReportCitations,
  QcAuditPanel });
// Keep the old name as an alias so existing call-sites continue to work.
window.MethodsReportModal = ReportModal;
