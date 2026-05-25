// Research Tweaks panel
// Surfaces:
//   - Scenario picker
//   - Replay speed
//   - Theme + density
//   - Panel width + sidebar mode
//   - Q1: Plan editability (open question recommendation: yes, with auto-lock)
//   - Q2: Same-speaker collapse threshold (3 / never)
//   - Q3: Comparison placement (inline / panel)
//   - Q4: Pilot default ON for heavy runs / always opt-in
//   - Q5: Phase expand inline / modal
//   - Q6: Pill placement after-marker / before-marker
//   - Q7: Auto-proceed countdown seconds

function TweakGroup({ label, sub, children }) {
  return (
    <div className="group">
      <div className="label">{label}{sub && <div className="sub">{sub}</div>}</div>
      {children}
    </div>
  );
}

function OptRow({ children, column }) {
  return <div className={'options' + (column ? ' column' : '')}>{children}</div>;
}

function Pill({ active, onClick, children, title }) {
  return (
    <button className={'opt' + (active ? ' active' : '')} onClick={onClick} title={title}>
      {children}
    </button>
  );
}

function ResearchTweaks({
  scenarioId, setScenarioId,
  speed,
  theme, density, panelWidth, sidebarMode,
  pillPlacement, collapseThreshold, showTs,
  planEditDefault, phaseExpandMode,
  comparePlacement, pilotDefaultOn,
  countdownSeconds,
  setTweak, onClose, onRestart,
}) {
  return (
    <div className="tweaks research-tweaks">
      <div className="tweaks-head">
        <span>Tweaks</span>
        <button className="btn ghost sm" onClick={onClose}>
          <Icon name="x" size={12}/>
        </button>
      </div>
      <div className="tweaks-body">

        <TweakGroup label="Scenario" sub="picks the chat + plan + cards + phases">
          <OptRow column>
            {Object.values(window.RESEARCH_SCENARIOS).map(s => (
              <Pill key={s.id} active={scenarioId === s.id}
                onClick={() => setScenarioId(s.id)}
                title={s.oneLiner}
              >
                <strong>{s.name.split(' · ')[0]}</strong>
                <div style={{fontSize:10, fontWeight:400, color:'var(--text-dim)', marginTop:2}}>
                  {s.oneLiner}
                </div>
              </Pill>
            ))}
          </OptRow>
          <button className="btn sm" onClick={onRestart} style={{marginTop:4}}>
            <Icon name="refresh" size={11}/> Replay from start
          </button>
        </TweakGroup>

        <hr/>

        <TweakGroup label={`Replay speed · ${speed.toFixed(2)}×`}>
          <input type="range" min="0.25" max="2.5" step="0.25" value={speed}
            onChange={e => setTweak({ speed: +e.target.value })} style={{width:'100%'}}/>
        </TweakGroup>

        <TweakGroup label="Theme">
          <OptRow>
            <Pill active={theme === 'light'} onClick={() => setTweak({ theme: 'light' })}>Light</Pill>
            <Pill active={theme === 'dark'}  onClick={() => setTweak({ theme: 'dark' })}>Dark</Pill>
          </OptRow>
        </TweakGroup>

        <TweakGroup label="Density">
          <OptRow>
            <Pill active={density === 'comfortable'} onClick={() => setTweak({ density: 'comfortable' })}>Comfortable</Pill>
            <Pill active={density === 'compact'}     onClick={() => setTweak({ density: 'compact' })}>Compact</Pill>
          </OptRow>
        </TweakGroup>

        <hr/>

        <div style={{fontSize: 10, fontWeight: 600, letterSpacing: '0.05em',
          textTransform: 'uppercase', color: 'var(--accent)', padding: '4px 0' }}>
          Open questions · spec review
        </div>

        <TweakGroup label="Q1 · Plan editability" sub="Recommend: yes, with 10s auto-lock">
          <OptRow>
            <Pill active={planEditDefault === true}  onClick={() => setTweak({ planEditDefault: true })}
              title="Recommended">Edit + auto-lock</Pill>
            <Pill active={planEditDefault === false} onClick={() => setTweak({ planEditDefault: false })}
              title="Alternative — locked from the start">Locked from the start</Pill>
          </OptRow>
        </TweakGroup>

        <TweakGroup label={`Q2 · Same-speaker collapse · ${collapseThreshold === 0 ? 'never' : `≥${collapseThreshold}`}`}
          sub="Recommend: collapse after 3">
          <OptRow>
            <Pill active={collapseThreshold === 3} onClick={() => setTweak({ collapseThreshold: 3 })}>≥3</Pill>
            <Pill active={collapseThreshold === 2} onClick={() => setTweak({ collapseThreshold: 2 })}>≥2</Pill>
            <Pill active={collapseThreshold === 0} onClick={() => setTweak({ collapseThreshold: 0 })}>Never</Pill>
          </OptRow>
        </TweakGroup>

        <TweakGroup label="Q3 · Comparison card placement" sub="Recommend: inline in chat">
          <OptRow>
            <Pill active={comparePlacement === 'inline'} onClick={() => setTweak({ comparePlacement: 'inline' })}>Inline</Pill>
            <Pill active={comparePlacement === 'panel'}  onClick={() => setTweak({ comparePlacement: 'panel' })}>Side panel</Pill>
          </OptRow>
        </TweakGroup>

        <TweakGroup label="Q4 · Pilot default" sub="Recommend: auto-ON for heavy runs">
          <OptRow>
            <Pill active={pilotDefaultOn === true}  onClick={() => setTweak({ pilotDefaultOn: true })}>Auto-ON (heavy)</Pill>
            <Pill active={pilotDefaultOn === false} onClick={() => setTweak({ pilotDefaultOn: false })}>Always opt-in</Pill>
          </OptRow>
        </TweakGroup>

        <TweakGroup label="Q5 · Phase rationale" sub="This version: hover-tooltip on (why?) anchor in chat lines">
          <div style={{fontSize: 11, color: 'var(--text-dim)', fontStyle: 'italic', lineHeight: 1.5}}>
            Hover any <span style={{borderBottom: '1px dotted var(--border-strong)', fontFamily: 'var(--font-mono)'}}>(why?)</span> anchor
            after a chat line to read the rationale for that phase. Inline panel-card expansion was dropped from this version per design review.
          </div>
        </TweakGroup>

        <TweakGroup label="Q6 · Speaker pill placement" sub="Recommend: after ◆ marker">
          <OptRow>
            <Pill active={pillPlacement === 'after-marker'}  onClick={() => setTweak({ pillPlacement: 'after-marker' })}>◆ PILL msg</Pill>
            <Pill active={pillPlacement === 'before-marker'} onClick={() => setTweak({ pillPlacement: 'before-marker' })}>PILL ◆ msg</Pill>
          </OptRow>
        </TweakGroup>

        <TweakGroup label={`Q7 · Auto-proceed countdown · ${countdownSeconds}s`}
          sub="Recommend: 10s · governs every blocking decision">
          <OptRow>
            <Pill active={countdownSeconds === 5}  onClick={() => setTweak({ countdownSeconds: 5 })}>5s</Pill>
            <Pill active={countdownSeconds === 10} onClick={() => setTweak({ countdownSeconds: 10 })}>10s</Pill>
            <Pill active={countdownSeconds === 30} onClick={() => setTweak({ countdownSeconds: 30 })}>30s</Pill>
          </OptRow>
        </TweakGroup>

        <hr/>

        <TweakGroup label="Chat options">
          <OptRow>
            <Pill active={showTs} onClick={() => setTweak({ showTs: !showTs })}>
              Timestamps {showTs ? '✓' : ''}
            </Pill>
          </OptRow>
        </TweakGroup>

        <TweakGroup label={`Panel width · ${panelWidth}px`}>
          <input type="range" min="420" max="640" step="10" value={panelWidth}
            onChange={e => setTweak({ panelWidth: +e.target.value })} style={{width:'100%'}}/>
        </TweakGroup>

        <TweakGroup label="Sidebar">
          <OptRow>
            <Pill active={sidebarMode === 'auto'}     onClick={() => setTweak({ sidebarMode: 'auto' })}>Auto-rail</Pill>
            <Pill active={sidebarMode === 'expanded'} onClick={() => setTweak({ sidebarMode: 'expanded' })}>Expanded</Pill>
            <Pill active={sidebarMode === 'hidden'}   onClick={() => setTweak({ sidebarMode: 'hidden' })}>Hidden</Pill>
          </OptRow>
        </TweakGroup>

      </div>
    </div>
  );
}

window.ResearchTweaks = ResearchTweaks;
