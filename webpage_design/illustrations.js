/* SVG illustrations for application cards — drawn, not stock */
window.BM_ILLUS = {
  binding: `<svg viewBox="0 0 320 200" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <linearGradient id="bgB" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#e2dcc8"/>
        <stop offset="1" stop-color="#ece7d8"/>
      </linearGradient>
      <radialGradient id="pocketB" cx="50%" cy="55%" r="55%">
        <stop offset="0" stop-color="#4a7a8a" stop-opacity=".22"/>
        <stop offset="1" stop-color="#4a7a8a" stop-opacity="0"/>
      </radialGradient>
    </defs>
    <rect width="320" height="200" fill="url(#bgB)"/>
    <!-- protein contour (organic blob lines) -->
    <g fill="none" stroke="#3a6878" stroke-width="1" opacity=".55">
      <path d="M40,140 C70,80 110,60 160,70 C220,82 260,110 280,150 C266,170 230,180 180,176 C120,170 70,170 40,140 Z"/>
      <path d="M60,135 C85,90 120,75 160,85 C210,95 245,118 264,148"/>
      <path d="M80,128 C100,100 130,90 160,98 C200,108 230,124 248,144"/>
    </g>
    <!-- binding pocket -->
    <ellipse cx="170" cy="118" rx="44" ry="30" fill="url(#pocketB)"/>
    <!-- ligand atoms -->
    <g>
      <line x1="158" y1="112" x2="178" y2="124" stroke="#1c2b32" stroke-width="1.2"/>
      <line x1="178" y1="124" x2="190" y2="108" stroke="#1c2b32" stroke-width="1.2"/>
      <line x1="178" y1="124" x2="172" y2="142" stroke="#1c2b32" stroke-width="1.2"/>
      <line x1="158" y1="112" x2="148" y2="96"  stroke="#1c2b32" stroke-width="1.2"/>
      <circle cx="158" cy="112" r="6.5" fill="#4a7a8a" stroke="#1c2b32" stroke-width="1"/>
      <circle cx="178" cy="124" r="5.5" fill="#f3ecd8" stroke="#1c2b32" stroke-width="1"/>
      <circle cx="190" cy="108" r="5.5" fill="#b06a4a" stroke="#1c2b32" stroke-width="1"/>
      <circle cx="172" cy="142" r="5"   fill="#4d7656" stroke="#1c2b32" stroke-width="1"/>
      <circle cx="148" cy="96"  r="5"   fill="#3a6878" stroke="#1c2b32" stroke-width="1"/>
    </g>
    <!-- distance ticks -->
    <g stroke="#5a7280" stroke-dasharray="2 3" stroke-width=".8" opacity=".6">
      <line x1="158" y1="112" x2="120" y2="100"/>
      <line x1="178" y1="124" x2="220" y2="138"/>
    </g>
    <text x="14" y="22" font-family="ui-monospace,monospace" font-size="9" fill="#5a7280">PDB · binding pose</text>
    <text x="14" y="186" font-family="ui-monospace,monospace" font-size="9" fill="#3a6878">ΔG = −9.4 kcal/mol</text>
  </svg>`,

  screening: `<svg viewBox="0 0 320 200" xmlns="http://www.w3.org/2000/svg">
    <rect width="320" height="200" fill="#ece7d8"/>
    <!-- 96-well plate -->
    <g>
      <rect x="22" y="30" width="276" height="140" rx="8" fill="#e2dcc8" stroke="#cec5ae"/>
      ${(() => {
        let s = '';
        const cols = 12, rows = 8;
        for (let r=0; r<rows; r++) {
          for (let c=0; c<cols; c++) {
            const cx = 38 + c * 22, cy = 46 + r * 16;
            // hit pattern
            const score = (Math.sin(c*1.3) + Math.cos(r*0.9) + Math.sin((c+r)*0.7))/3;
            const isHit = score > 0.4;
            const isStrong = score > 0.7;
            const fill = isStrong ? '#4a7a8a' : isHit ? 'rgba(74,122,138,.4)' : '#f5f0e4';
            s += `<circle cx="${cx}" cy="${cy}" r="5.5" fill="${fill}" stroke="#cec5ae" stroke-width=".7"/>`;
          }
        }
        return s;
      })()}
    </g>
    <text x="22" y="22" font-family="ui-monospace,monospace" font-size="9" fill="#5a7280">virtual screen · 1.2M cmpds</text>
    <text x="190" y="190" font-family="ui-monospace,monospace" font-size="9" fill="#3a6878">23 hits · top 0.002%</text>
  </svg>`,

  admet: `<svg viewBox="0 0 320 200" xmlns="http://www.w3.org/2000/svg">
    <rect width="320" height="200" fill="#ece7d8"/>
    <!-- radar chart -->
    <g transform="translate(160,108)">
      <g fill="none" stroke="#cec5ae" stroke-width=".7">
        <polygon points="0,-72 62,-36 62,36 0,72 -62,36 -62,-36"/>
        <polygon points="0,-54 47,-27 47,27 0,54 -47,27 -47,-27"/>
        <polygon points="0,-36 31,-18 31,18 0,36 -31,18 -31,-18"/>
        <polygon points="0,-18 15,-9 15,9 0,18 -15,9 -15,-9"/>
      </g>
      <g stroke="#cec5ae" stroke-width=".7">
        <line x1="0" y1="-72" x2="0" y2="72"/>
        <line x1="-62" y1="-36" x2="62" y2="36"/>
        <line x1="62" y1="-36" x2="-62" y2="36"/>
      </g>
      <!-- molecule profile -->
      <polygon points="0,-58 55,-28 38,30 0,60 -42,28 -50,-22"
               fill="rgba(74,122,138,.28)" stroke="#3a6878" stroke-width="1.5"/>
      <g fill="#3a6878">
        <circle cx="0" cy="-58" r="3"/>
        <circle cx="55" cy="-28" r="3"/>
        <circle cx="38" cy="30" r="3"/>
        <circle cx="0" cy="60" r="3"/>
        <circle cx="-42" cy="28" r="3"/>
        <circle cx="-50" cy="-22" r="3"/>
      </g>
    </g>
    <g font-family="ui-monospace,monospace" font-size="9" fill="#5a7280">
      <text x="148" y="26">LogP</text>
      <text x="232" y="78">TPSA</text>
      <text x="232" y="148">HBD</text>
      <text x="148" y="190">Sol</text>
      <text x="48" y="148">PPB</text>
      <text x="40" y="78">CL</text>
    </g>
    <text x="14" y="20" font-family="ui-monospace,monospace" font-size="9" fill="#3a6878">ADMET profile · drug-likeness</text>
  </svg>`,

  pbpk: `<svg viewBox="0 0 320 200" xmlns="http://www.w3.org/2000/svg">
    <rect width="320" height="200" fill="#ece7d8"/>
    <!-- pk curve -->
    <g transform="translate(36,30)">
      <line x1="0" y1="140" x2="252" y2="140" stroke="#cec5ae"/>
      <line x1="0" y1="0"   x2="0"   y2="140" stroke="#cec5ae"/>
      <g stroke="#cec5ae" stroke-dasharray="2 4" stroke-width=".7">
        <line x1="0" y1="40" x2="252" y2="40"/>
        <line x1="0" y1="80" x2="252" y2="80"/>
        <line x1="0" y1="120" x2="252" y2="120"/>
      </g>
      <!-- two PK profiles -->
      <path d="M0,140 C20,40 40,16 70,12 C110,8 140,40 170,80 C200,118 230,134 252,138"
            fill="none" stroke="#3a6878" stroke-width="2"/>
      <path d="M0,140 C18,70 38,46 64,42 C100,42 130,68 160,98 C195,128 225,138 252,140"
            fill="none" stroke="#b06a4a" stroke-width="2" stroke-dasharray="3 3"/>
      <!-- Cmax marker -->
      <circle cx="70" cy="12" r="3.5" fill="#3a6878"/>
      <circle cx="64" cy="42" r="3.5" fill="#b06a4a"/>
      <text x="78" y="14" font-family="ui-monospace,monospace" font-size="9" fill="#3a6878">Cmax</text>
      <text x="0"  y="158" font-family="ui-monospace,monospace" font-size="8.5" fill="#5a7280">0h</text>
      <text x="118" y="158" font-family="ui-monospace,monospace" font-size="8.5" fill="#5a7280">12h</text>
      <text x="232" y="158" font-family="ui-monospace,monospace" font-size="8.5" fill="#5a7280">24h</text>
      <text x="-26" y="6" font-family="ui-monospace,monospace" font-size="8.5" fill="#5a7280" transform="rotate(-90,-26,6)">conc.</text>
    </g>
    <text x="14" y="20" font-family="ui-monospace,monospace" font-size="9" fill="#3a6878">PBPK · plasma profile</text>
    <g font-family="ui-monospace,monospace" font-size="8.5" fill="#5a7280">
      <rect x="200" y="40" width="106" height="36" fill="rgba(255,255,255,.55)" stroke="#cec5ae" rx="4"/>
      <line x1="208" y1="52" x2="222" y2="52" stroke="#3a6878" stroke-width="2"/>
      <text x="226" y="55" fill="#3a6878">predicted</text>
      <line x1="208" y1="66" x2="222" y2="66" stroke="#b06a4a" stroke-width="2" stroke-dasharray="3 3"/>
      <text x="226" y="69" fill="#b06a4a">observed</text>
    </g>
  </svg>`,

  trial: `<svg viewBox="0 0 320 200" xmlns="http://www.w3.org/2000/svg">
    <rect width="320" height="200" fill="#ece7d8"/>
    <!-- trial timeline -->
    <g transform="translate(20,40)">
      <text font-family="ui-monospace,monospace" font-size="9" fill="#5a7280" x="0" y="-12">adaptive trial · 4 cohorts</text>
      ${(() => {
        const phases = [
          {x:0, w:60, label:'P1', color:'#4d7656'},
          {x:64, w:80, label:'P2a', color:'#3a6878'},
          {x:148, w:60, label:'P2b', color:'#3a6878'},
          {x:212, w:68, label:'P3', color:'#b06a4a'}
        ];
        return phases.map(p =>
          `<rect x="${p.x}" y="0" width="${p.w}" height="22" rx="4" fill="${p.color}" opacity=".75"/>
           <text x="${p.x + p.w/2}" y="14.5" text-anchor="middle" font-family="ui-monospace,monospace" font-size="9" fill="#fff">${p.label}</text>`
        ).join('');
      })()}
      <!-- dose ladder -->
      <g transform="translate(0,40)">
        ${(() => {
          let s = '';
          const doses = [10, 25, 50, 100, 200];
          for (let i=0; i<doses.length; i++) {
            const y = i*16;
            const width = 30 + i*38;
            s += `<line x1="0" y1="${y+6}" x2="${width}" y2="${y+6}" stroke="#cec5ae" stroke-width=".7"/>`;
            s += `<rect x="0" y="${y}" width="${width}" height="11" rx="3" fill="rgba(58,104,120,.32)" stroke="#3a6878" stroke-width=".7"/>`;
            s += `<text x="${width+6}" y="${y+9}" font-family="ui-monospace,monospace" font-size="8.5" fill="#5a7280">${doses[i]} mg</text>`;
          }
          return s;
        })()}
      </g>
    </g>
    <text x="186" y="190" font-family="ui-monospace,monospace" font-size="9" fill="#3a6878">RP2D = 100 mg · projected</text>
  </svg>`,

  omics: `<svg viewBox="0 0 320 200" xmlns="http://www.w3.org/2000/svg">
    <rect width="320" height="200" fill="#ece7d8"/>
    <!-- heatmap -->
    <g transform="translate(20,30)">
      ${(() => {
        let s = '';
        const cols = 16, rows = 10;
        for (let r=0; r<rows; r++) {
          for (let c=0; c<cols; c++) {
            const x = c*17, y = r*13;
            const v = Math.sin(c*0.7 + r*0.4) + Math.cos((c-r)*0.5)*0.7 + Math.sin(r*0.9)*0.5;
            // map v in [-2,2] to color
            const t = (v+2)/4;
            let fill;
            if (t < 0.5) {
              const k = t*2;
              fill = `rgb(${Math.round(74 + (236-74)*k)}, ${Math.round(122 + (231-122)*k)}, ${Math.round(138 + (216-138)*k)})`;
            } else {
              const k = (t-0.5)*2;
              fill = `rgb(${Math.round(236 + (176-236)*k)}, ${Math.round(231 + (106-231)*k)}, ${Math.round(216 + (74-216)*k)})`;
            }
            s += `<rect x="${x}" y="${y}" width="16" height="12" fill="${fill}"/>`;
          }
        }
        return s;
      })()}
    </g>
    <text x="14" y="20" font-family="ui-monospace,monospace" font-size="9" fill="#3a6878">RNA-seq · DEGs (n=160)</text>
    <text x="14" y="190" font-family="ui-monospace,monospace" font-size="9" fill="#5a7280">log₂FC · row-scaled</text>
    <!-- legend -->
    <g transform="translate(220,178)">
      <rect width="80" height="8" fill="url(#omicsGrad)"/>
      <text x="0" y="-3" font-family="ui-monospace,monospace" font-size="8" fill="#5a7280">−2</text>
      <text x="74" y="-3" font-family="ui-monospace,monospace" font-size="8" fill="#5a7280">+2</text>
    </g>
    <defs>
      <linearGradient id="omicsGrad" x1="0" x2="1">
        <stop offset="0" stop-color="#4a7a8a"/>
        <stop offset=".5" stop-color="#ece7d8"/>
        <stop offset="1" stop-color="#b06a4a"/>
      </linearGradient>
    </defs>
  </svg>`
};

window.BM_ICON = {
  data: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v6c0 1.7 3.6 3 8 3s8-1.3 8-3V5"/><path d="M4 11v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/></svg>',
  route: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="M8.5 6H14a4 4 0 0 1 4 4v0a4 4 0 0 1-4 4h-4a4 4 0 0 0-4 4v0"/></svg>',
  chat: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l.9-5.4A8 8 0 1 1 21 12Z"/><path d="M8 11h8M8 14h5"/></svg>',
  shield: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 4 6v6c0 4.5 3.4 8.5 8 9 4.6-.5 8-4.5 8-9V6l-8-3Z"/><path d="m9 12 2.2 2.2L15 10.5"/></svg>',
  community: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8" r="3"/><circle cx="17" cy="10" r="2.5"/><path d="M3 20c0-3 2.7-5.5 6-5.5s6 2.5 6 5.5"/><path d="M14.5 14.5c2.6.3 4.5 2.4 4.5 5"/></svg>',
  cloud: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M7 18A5 5 0 1 1 8 8.1 6 6 0 0 1 20 11a4 4 0 0 1-1 7.9H7Z"/><path d="m11 13 2 2-2 2"/><path d="M9 17h6"/></svg>',
  defensible: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3h-4l-1 4-3-1-2 3 3 2v4l-3 2 2 3 3-1 1 4h4l1-4 3 1 2-3-3-2v-4l3-2-2-3-3 1-1-4Z"/><circle cx="12" cy="12" r="2"/></svg>',
  scale: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17V7l4 3 5-5 5 5 4-3v10"/><path d="M3 21h18"/></svg>',
  brain: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M9 4a3 3 0 0 0-3 3v0a3 3 0 0 0-2 5 3 3 0 0 0 2 5v0a3 3 0 0 0 3 3"/><path d="M15 4a3 3 0 0 1 3 3v0a3 3 0 0 1 2 5 3 3 0 0 1-2 5v0a3 3 0 0 1-3 3"/><path d="M12 4v16"/></svg>',
  dollar: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M15 9h-4a2 2 0 0 0 0 4h2a2 2 0 0 1 0 4H9"/><path d="M12 7v10"/></svg>',
  globe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18 14 14 0 0 1 0-18Z"/></svg>'
};
