// Sidebar + Chat column + shared chrome components.
const { useState, useEffect, useRef } = React;

function Sidebar({ scenario, onScenarioChange, rail }) {
  const history = [
    { id: 'cryosparc', q: 'Cryo-EM SPA on EMPIAR-10025', active: scenario === 'cryosparc' },
    { id: 'gatk',      q: 'GATK4 germline variants, SRR123456', active: scenario === 'gatk' },
    { id: 'admet',     q: 'ADMET for aspirin', active: scenario === 'admet' },
    { id: 'nfcore',    q: 'nf-core fastp QC, 2 runs', active: scenario === 'nfcore' },
  ];
  const past = [
    'AlphaFold2 — UniProt P05067',
    'RNA-seq DESeq2 — liver tumor vs normal',
    'Docking — SARS-CoV-2 Mpro + ligand lib',
    'CYP-DDI screen, top-100 hits',
    'ATAC-seq peak calling',
  ];
  return (
    <aside className="sidebar" title={rail ? 'Sidebar auto-collapsed while panel is open' : ''}>
      <div className="brand">
        <div className="brand-mark"><img src="images/biomate-logo.png" alt="BioMate" /></div>
        <div>
          <div className="brand-name">BioMate <span className="brand-ai">AI</span></div>
          <div className="brand-sub">workflow console</div>
        </div>
      </div>

      <div>
        <div className="side-section-label">Workspace</div>
        <button className="side-link" title="Home"><span className="side-icon"><Icon name="home"/></span><span>Home</span></button>
        <button className="side-link" title="Workflows"><span className="side-icon"><Icon name="beaker"/></span><span>Workflows</span></button>
        <button className="side-link" title="Runs"><span className="side-icon"><Icon name="folder"/></span><span>Runs</span></button>
        <button className="side-link" title="Library"><span className="side-icon"><Icon name="book"/></span><span>Library</span></button>
      </div>

      <div className="side-history">
        <div className="side-section-label">Current</div>
        {history.map(h => (
          <button key={h.id}
            className={'side-link' + (h.active ? ' active' : '')}
            onClick={() => onScenarioChange(h.id)}
            title={h.q}>
            <span className="side-icon"><Icon name="dot" size={8}/></span>
            <span className="q">{h.q}</span>
          </button>
        ))}
        <div className="side-section-label" style={{marginTop:14}}>Recent</div>
        {past.map(q => (
          <button key={q} className="side-link" title={q}>
            <span className="side-icon" style={{width:8}}/>
            <span className="q">{q}</span>
          </button>
        ))}
      </div>

      <div className="side-foot">
        <div className="avatar">KM</div>
        <div style={{fontSize:12, lineHeight:1.2}}>
          <div style={{fontWeight:500}}>Kira M.</div>
          <div style={{color:'var(--text-dim)', fontSize:11}}>Broad Institute</div>
        </div>
      </div>
    </aside>
  );
}

function ChatColumn({ scenario, onReopenPanel, panelOpen, onTogglePanel, onStartTour, showDisambig }) {
  const scen = window.SCENARIOS[scenario];
  const [input, setInput] = useState('');

  return (
    <div className="chat-col">
      <div className="chat-top">
        <div style={{display:'flex', alignItems:'center', gap:10}}>
          {!panelOpen && (
            <button className="btn ghost sm" onClick={onTogglePanel} title="Show workflow panel">
              <Icon name="flask" size={13}/> Panel
            </button>
          )}
          <div className="title">
            New thread <span className="domain">· {scen.domain}</span>
          </div>
        </div>
        <div className="actions">
          <button className="tut-btn" onClick={onStartTour} title="Replay the tutorial">
            <span style={{ fontSize: 10 }}>▶</span> Tutorial
          </button>
          <button className="btn ghost sm"><Icon name="sparkles" size={13}/> Share</button>
          <button className="btn ghost sm"><Icon name="more" size={14}/></button>
        </div>
      </div>

      <div className="thread">
        <div className="msg user">
          <div className="who">You · 3:40 pm</div>
          <div className="bubble">{scen.query}</div>
        </div>

        <div className="msg assistant">
          <div className="who">Biomate</div>
          <div className="bubble">
            <strong>{scen.name}</strong> is ready in the panel — check the steps and parameters,
            then click <em>Confirm &amp; Run</em>.

            <div className="wf-chip" data-tour="chat-handoff">
              <div className="ic"><Icon name="flask" size={16}/></div>
              <div className="body">
                <div className="name">{scen.name}</div>
                <div className="sub">{scen.subtitle} · {scen.domain}</div>
              </div>
              {!panelOpen
                ? <button className="btn sm" onClick={onReopenPanel}>
                    <Icon name="external" size={12}/> Open in panel
                  </button>
                : <span className="chip ok"><span className="dot"/>In panel</span>}
            </div>

            {showDisambig && (
              <div className="disambig-card">
                <div className="h">2 workflows matched your query closely</div>
                <div className="opt">
                  <div style={{flex:1}}>
                    <div className="name">{scen.name}</div>
                    <div className="sub">Selected · most specific match</div>
                  </div>
                  <span className="score">0.87</span>
                </div>
                <div className="opt">
                  <div style={{flex:1}}>
                    <div className="name">nf-core/sarek — somatic variants</div>
                    <div className="sub">Alternative · matches tumour/normal intent</div>
                  </div>
                  <span className="score">0.74</span>
                  <button className="linkish" style={{fontSize:12}}>Use this instead</button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="chat-input-wrap">
        <div className="chat-input">
          <textarea
            placeholder="Ask Biomate to run a workflow, adjust parameters, or extend the pipeline…"
            value={input} onChange={e => setInput(e.target.value)}
            rows={1}
          />
          <div className="row">
            <div className="tools">
              <button className="btn ghost sm" title="Attach"><Icon name="paperclip" size={14}/></button>
              <button className="btn ghost sm"><Icon name="sparkles" size={13}/> Suggest</button>
            </div>
            <button className="send" disabled={!input.trim()}>
              <Icon name="send" size={13}/>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Sidebar, ChatColumn });
