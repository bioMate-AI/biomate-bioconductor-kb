/* The run surface, built on the shipped Research-Agent workflow panel:
   panel head + run bar · section tabs (Workflow settings · Phases · After run)
   · PhaseCard accordion with steps, outputs and QC gates · panel foot.
   Part-3 additions live inside that structure — skip toggles, a full-window
   step deep-view, evidence-typed outputs and number→source click-through. */
const RTABS = [['report', 'Report'], ['outputs', 'Outputs'], ['findings', 'Findings'], ['imrad', 'Methods'], ['params', 'Parameters'], ['software', 'Software'], ['cite', 'Citations'], ['qc', 'QC audit'], ['traj', 'Trajectory']];
const stepsOf = phases => phases.flatMap(p => p.steps.map((s, j) => ({ sk:p.id + (j + 1), phase:p.id, phaseName:p.name, name:s })));
const ALL_STEPS = stepsOf(RUN_PHASES);

function Slot({ s, onToast, licensed, onLicense }) {
  const blocked = s.license && !licensed;
  return <div className={'slot' + (blocked ? ' blocked' : '')}>
    <span className="slotk">{s.k}{s.req && <span className="req">required</span>}</span>
    <div className="slotv">
      {s.ds ? <DataChip id={s.ds} onClick={() => onToast('Opens the same dataset object as the Files tab — one file, many views.')}/>
        : blocked ? <span className="chip warn"><span className="dot"/>license not accepted</span>
        : <button className="btn sm ghost" onClick={() => onToast('Browse this project\u2019s files, or the account scope, without re-uploading.')}>Browse project files</button>}
    </div>
    <span className="hint">{s.note}</span>
    {blocked && <button className="btn sm" onClick={onLicense}>Accept license</button>}
  </div>;
}

/* Global parameters in the shipped .param-row vocabulary. */
function ParamRows({ onToast, wf }) {
  const [why, setWhy] = React.useState(null);
  return <div className="strip-body wf-settings-body">
    {wf.params.map(p => <React.Fragment key={p.k}>
      <div className="param-row">
        <div className="k">{p.k}</div>
        <div className="v" title={p.v}><span className="vval">{p.v}</span>
          <span className={'prov' + (p.src === 'project instructions' || p.src === 'recommended' ? ' src' : '')}>{p.src}</span></div>
        <button className="linkish edit" style={{ fontSize:11 }} onClick={() => setWhy(why === p.k ? null : p.k)}>{why === p.k ? 'hide' : 'why'}</button>
      </div>
      {why === p.k && <div className="whybox" style={{ margin:'0 18px 8px' }}>
        <span className="hint">{p.why}</span>{p.cite && <span className="cite"><Icon name="book" size={11}/>{p.cite}</span>}
      </div>}
    </React.Fragment>)}
    <div className="wf-autoloop-row">
      <div className="lbl"><div className="t">Auto-loop on QC failure</div>
        <div className="d">Retry a failed phase with adjusted params · max 3× · 10s review window</div></div>
      <span className="wf-autoloop-state">On</span>
      <span className="switch on" role="switch" aria-checked="true" onClick={() => onToast('Auto-loop toggled for every QC-gated phase.')}/>
    </div>
  </div>;
}

function GatePanel({ onResolve }) {
  return <div className="gate">
    <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
      <Icon name="warn" size={15}/><span style={{ fontWeight:600, fontSize:'13px' }}>Quality gate halted the run</span>
      <span className="spacer"/><span className="chip warn"><span className="dot"/>{QC_GATE.gate}</span>
    </div>
    <div className="col" style={{ gap:'0' }}>
      {QC_GATE.measured.map(([k, m, t]) => <div key={k} className="meas"><span className="hint">{k}</span><span className="mono mval">{m}</span><span className="hint dim">{t}</span></div>)}
    </div>
    <span className="hint"><b>Evidence level:</b> {QC_GATE.evidence}</span>
    <div className="diffbox">
      <span className="k2">Suggested change</span>
      <span className="diffline"><span className="dbefore">{QC_GATE.before}</span></span>
      <span className="diffline"><span className="dafter">{QC_GATE.after}</span></span>
      <span className="hint">{QC_GATE.rationale}</span>
    </div>
    <div className="row" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
      <button className="btn sm" onClick={() => onResolve('apply')}>Apply suggestion</button>
      <button className="btn sm ghost" onClick={() => onResolve('keep')}>Keep my parameters</button>
      <button className="btn sm ghost" onClick={() => onResolve('cancel')}>Cancel run</button>
    </div>
  </div>;
}

function RunSurface({ project, onToast, onOpenData, onOpenModels, onBack, startAt, deepDefault, onOpenFile, dom, mod }) {
  /* The card follows the routed domain, so the panel can never ask genomics
     questions about a biologics design request. */
  const wf = React.useMemo(() => (window.wfFor ? wfFor(dom, mod) : WF_CARD), [dom, mod]);
  const phases = wf.phases || RUN_PHASES;
  const allSteps = React.useMemo(() => stepsOf(phases), [phases]);
  /* Step detail is only fixtured for the shipped transcriptomics run; a phase
     from another domain says so rather than borrowing its evidence. */
  const deepOf = sk => (wf.phases ? null : STEP_DEEP[sk]);
  const needsLicence = wf.slots.some(s => s.license);
  const initial = startAt === 'report' ? 'completed' : startAt === 'watch' ? 'running' : 'idle';
  const [runState, setRunState] = React.useState(initial);
  const [section, setSection] = React.useState(initial === 'idle' ? 'settings' : 'phases');
  const [topFold, setTopFold] = React.useState(initial === 'completed');
  const [skip, setSkip] = React.useState({});
  const [openPhase, setOpenPhase] = React.useState(phases[0].id);
  const [deep, setDeep] = React.useState(null);
  const [deepMode, setDeepMode] = React.useState(deepDefault || 'full');
  React.useEffect(() => { setDeepMode(deepDefault || 'full'); }, [deepDefault]);
  const [rerun, setRerun] = React.useState(null);
  const [edit, setEdit] = React.useState({});
  const [licensed, setLicensed] = React.useState(initial !== 'idle');
  const [gate, setGate] = React.useState(null);
  const [appr, setAppr] = React.useState(null);
  const [clarified, setClarified] = React.useState(initial !== 'idle');
  const [decision, setDecision] = React.useState(null);
  const [tick, setTick] = React.useState(initial === 'completed' ? 99 : 0);

  const total = allSteps.length;
  const isSkipped = s => !!(skip[s.phase] || skip[s.sk]);
  const active = allSteps.filter(s => !isSkipped(s));
  const total2 = active.length;
  const doneN = Math.min(tick, total2);
  const pct = Math.round(100 * doneN / Math.max(1, total2));

  React.useEffect(() => {
    if (runState !== 'running' || gate === 'open' || appr === 'open') return;
    if (tick >= total2) { const t = setTimeout(() => { setRunState('completed'); setTopFold(true); }, 700); return () => clearTimeout(t); }
    const t = setTimeout(() => {
      const next = tick + 1;
      setTick(next);
      const s = active[next - 1];
      if (s) setOpenPhase(s.phase);
      if (s && s.sk === 'B2') setGate('open');
      if (s && s.sk === 'D1') setAppr('open');
    }, 850);
    return () => clearTimeout(t);
  }, [runState, tick, gate, appr, total2]);

  const stepState = s => {
    if (isSkipped(s)) return 'skipped';
    if (runState === 'completed') return 'completed';
    if (runState === 'idle') return 'pending';
    const pos = active.indexOf(s);
    return tick > pos ? 'completed' : tick === pos ? 'running' : 'pending';
  };
  const phaseStateOf = p => {
    const mine = allSteps.filter(s => s.phase === p.id);
    if (mine.every(isSkipped)) return 'skipped';
    const st = mine.filter(s => !isSkipped(s)).map(stepState);
    return st.every(x => x === 'completed') ? 'completed' : st.some(x => x === 'running' || x === 'completed') ? 'running' : 'pending';
  };
  const openStep = (sk, outId) => { const i = allSteps.findIndex(s => s.sk === sk); if (i >= 0) setDeep({ i, out:outId || null }); };
  const start = () => { setRunState('running'); setTick(0); setGate(null); setDecision(null); setSection('phases'); setTopFold(false); setOpenPhase(phases[0].id); };
  const resolve = k => {
    if (k === 'cancel') { setRunState('idle'); setTick(0); setGate(null); setSection('settings'); return onToast('Run cancelled at the gate. The configuration is kept, so you can change it and start again.'); }
    setGate(null); setDecision(k);
    onToast(k === 'apply' ? 'Applied: 2 low-depth samples excluded and listed in the report — the run continues from the gate.' : 'Kept your parameters — the run continues and the gate is recorded as overridden in the QC audit.');
  };
  const reportReady = runState === 'completed';

  return <div className="mainpane wfp">
    <div className="panel-head">
      <div className="top-row">
        <div style={{ minWidth:0 }}>
          <div className="kicker">{wf.domain} · {wf.kind || 'Workflow'}</div>
          <div className="name">{wf.name}</div>
          <div className="sub">{project} · {wf.version} · inputs resolved from this project's files</div>
        </div>
        <div style={{ display:'flex', gap:'2px' }}>
          <button className="iconbtn" title="Workflow docs" onClick={() => onToast('Workflow documentation — unchanged by this proposal.')}><Icon name="book" size={16}/></button>
          {onBack && <button className="iconbtn" title="Back to run history" onClick={onBack}><Icon name="x" size={16}/></button>}
        </div>
      </div>
      <div className="run-bar">
        <span className="meta">{runState === 'running' ? (gate === 'open' ? 'Halted' : appr === 'open' ? 'Awaiting approval' : 'Running') : runState === 'completed' ? 'Completed' : 'Ready'}</span>
        <div className="progress"><div className="fill" style={{ width:pct + '%' }}/></div>
        <span className="pct">{pct}%</span>
        <span className="meta">{doneN}/{total2}{total2 < total ? ' · ' + (total - total2) + ' skipped' : ''}</span>
      </div>
    </div>

    <div className={'panel-body wf-split' + (reportReady ? ' hasafter' : '')}>
      <div className={'wf-top' + (topFold ? ' folded' : '')}>
        <div className="wf-sectionbar" role="tablist">
          {[['settings', 'Workflow settings', wf.params.length], ['phases', 'Phases', phases.length]].map(([k, lbl, cnt]) => {
            return <button key={k} role="tab" aria-selected={section === k}
              className={'wf-sectiontab' + (section === k ? ' active' : '')}
              onClick={() => { setSection(k); setTopFold(false); }} title={lbl}>
              <span className="lbl">{lbl}</span>
              {cnt != null && <span className="cnt">{cnt}</span>}
            </button>;
          })}
          <button className="foldbtn" onClick={() => setTopFold(f => !f)} aria-expanded={!topFold}
            title={topFold ? 'Show the workflow and phase view' : 'Fold the workflow and phase view to give the report more room'}>
            <span className="fchev"><Icon name="chevronDown" size={11}/></span>{topFold ? 'Show workflow' : 'Fold workflow'}
          </button>
        </div>

        {topFold && <div className="foldsummary">
          <span className="chip ok"><Icon name="check" size={10}/>{allSteps.filter(s => stepState(s) === 'completed').length} finished</span>
          {runState === 'running' && <span className="chip run"><span className="dot"/>1 running</span>}
          <span className="chip">{active.filter(s => stepState(s) === 'pending').length} waiting</span>
          {total2 < total && <span className="chip">{total - total2} skipped</span>}
          <span>Phases folded — the report below has the room.</span>
        </div>}

        {!topFold && <div className="wf-section-body">
          {section === 'settings' && <>
            {!clarified && <div style={{ padding:'10px 18px 2px' }}>
              <ClarifyCard onToast={onToast} dom={dom} onDone={() => setClarified(true)}/>
            </div>}
            <ParamRows onToast={onToast} wf={wf}/>
            <div className="phase-list" style={{ paddingTop:'2px' }}>
              <div className="card2 col" style={{ gap:'8px' }}>
                <div className="row ac"><span className="k2">Inputs</span><span className="spacer"/><button className="linkish" onClick={onOpenData}>see all project files →</button></div>
                {wf.slots.map(s => <Slot key={s.k} s={s} onToast={onToast} licensed={licensed}
                  onLicense={() => { setLicensed(true); onToast('GENCODE v44 licence accepted for this account — recorded in the run\u2019s audit trail.'); }}/>)}
              </div>
              <div className="card2 col" style={{ gap:'8px' }}>
                <div className="row ac"><span className="k2">Phases to run</span><span className="spacer"/><span className="hint dim">{total2} of {total} steps</span></div>
                <span className="hint">Skipping is a choice, not a failure — but only where the workflow declares it. A load-bearing phase cannot be skipped, and says what depends on it.</span>
                {phases.map((p, i) => { const off = !!skip[p.id]; const dep = SKIPDEP[p.id] || { skippable:true };
                  return <div key={p.id} className={'qline' + (dep.skippable ? '' : ' locked')} style={off ? { opacity:.62 } : null}>
                  <span className={'switch' + (off ? '' : ' on') + (dep.skippable ? '' : ' disabled')} role="switch" aria-checked={!off} aria-disabled={!dep.skippable}
                    onClick={() => dep.skippable ? setSkip(s => ({ ...s, [p.id]:!off })) : onToast('Phase ' + p.id + ' cannot be skipped — ' + dep.why)}/>
                  <span className="col" style={{ gap:'2px', minWidth:0 }}>
                    <span style={{ fontSize:'12.5px', fontWeight:600, textDecoration:off ? 'line-through' : 'none' }}>Phase {p.id} · {p.name}</span>
                    <span className="hint dim">{p.steps.length} steps · {p.t}{off ? ' · will not run' : ''}</span>
                    {!dep.skippable && <span className="hint dim">{dep.why}</span>}
                    {dep.skippable && dep.param && <span className="mono skparam">{dep.param}</span>}
                  </span>
                  <span className="spacer"/>
                  {!dep.skippable
                    ? <span className="chip"><Icon name="warn" size={10}/>can’t skip · {dep.blocks.join(', ')} depend on it</span>
                    : off && i < phases.length - 1 ? <span className="chip warn"><span className="dot"/>{phases.slice(i + 1).map(q => q.id).join(', ')} read cached input</span>
                    : dep.warn ? <span className="hint dim">{dep.warn.join(', ')} would have nothing to work on</span> : null}
                </div>; })}
              </div>
              <RolesCard onToast={onToast}/>
              <VerifyPattern onToast={onToast}/>
            </div>
          </>}

          {section === 'phases' && <>
            {!licensed && needsLicence && <div className="alert warn">
              <span className="ic"><Icon name="warn" size={14}/></span>
              <div className="body"><strong>Credential required</strong> — the GENCODE v44 annotation licence has not been accepted.
                <div className="act"><button className="btn sm" onClick={() => { setLicensed(true); onToast('Licence accepted — recorded in the audit trail.'); }}>Accept licence</button>
                  <button className="linkish" onClick={() => onToast('The licence text and its terms open in a dialog.')}>Learn more</button></div></div>
            </div>}
            {gate === 'open' && <div style={{ padding:'0 18px 8px' }}><GatePanel onResolve={resolve}/></div>}
            {appr === 'open' && <div style={{ padding:'0 18px 8px' }}>
              <ApprovalGate onToast={onToast} onResolve={k => { setAppr(k === 'approve' ? null : 'denied'); if (k !== 'approve') setRunState('idle'); }}/>
            </div>}

            <div className="statuslegend">
              <span className="sl done"><i/>finished</span>
              <span className="sl run"><i/>running</span>
              <span className="sl wait"><i/>waiting</span>
              <span className="sl skip"><i/>skipped</span>
            </div>
            <div className="phase-list">
              {phases.map(p => {
                const ps = phaseStateOf(p);
                const mine = allSteps.filter(x => x.phase === p.id);
                const dn = mine.filter(x => stepState(x) === 'completed').length;
                const isOpen = openPhase === p.id || mine.some(x => stepState(x) === 'running');
                return <div key={p.id} className={'phase ' + ps + (isOpen ? ' open' : '')}>
                  <div className="phase-head" onClick={() => setOpenPhase(openPhase === p.id ? null : p.id)}>
                    <span className="caret"><Icon name="chevronRight" size={14}/></span>
                    <div className="letter">{p.id}</div>
                    <div className="titles">
                      <div className="title">Phase {p.id} · {p.name}</div>
                      <div className="sub">{mine.length} steps · {p.t}</div>
                    </div>
                    {ps === 'running' && <span className="chip run"><span className="spinner"/>RUNNING</span>}
                    {ps === 'completed' && <span className="chip ok"><Icon name="check" size={10}/>DONE</span>}
                    {ps === 'skipped' && <span className="chip"><Icon name="skip" size={10}/>SKIPPED</span>}
                    {ps === 'pending' && <span className="progress-chip wait">waiting · {mine.length} steps</span>}
                    {(ps === 'running' || ps === 'completed') && <span className="progress-chip">{dn}/{mine.length}</span>}
                  </div>
                  {isOpen && <div className="phase-body">
                    {p.steps.map((s, j) => {
                      const st = allSteps.find(x => x.sk === p.id + (j + 1));
                      const ss = stepState(st); const done = ss === 'completed';
                      const d = deepOf(st.sk) || { outs:[], params:[] };
                      return <div key={s} className={'step ' + ss + (deep && allSteps[deep.i].sk === st.sk ? ' issel' : '')}>
                        <div className="step-head">
                          <div className={'name' + (ss === 'skipped' ? ' dim' : '')}>{s}</div>
                          <StatusChip status={ss}/>
                          <div className="actions">
                            {!!d.params.length && <button className="btn ghost sm" title="Edit this step's parameters" onClick={() => setEdit(e => ({ ...e, [st.sk]:!e[st.sk] }))}><Icon name="settings" size={11}/></button>}
                            {done && <button className="btn ghost sm" title="Re-run from this step" onClick={() => setRerun(st.sk)}><Icon name="refresh" size={11}/></button>}
                            {(done || ss === 'skipped') && <button className="btn ghost sm" title="Open the full step view" onClick={() => openStep(st.sk)}><Icon name="eye" size={11}/> Full view</button>}
                          </div>
                        </div>
                        {ss !== 'pending' && !!d.params.length && !edit[st.sk] && <div className="step-meta">{d.tool} {d.ver} · {d.params.slice(0, 2).map(x => x[0] + ': ' + x[1]).join(' · ')}</div>}
                        {edit[st.sk] && <StepParams sk={st.sk} onToast={onToast} onRerun={() => setRerun(st.sk)}/>}
                        {done && !!d.outs.length && <div className="step-outputs">
                          {d.outs.map(o => <span className="output-file" key={o.id}>
                            <EvBadge ev={o.ev} compact/>
                            <span className="fn">{o.name}</span>
                            <span className="act" onClick={() => openStep(st.sk, o.id)}>view</span>
                            <span className="act" onClick={() => onToast('Download ' + o.name + ' — the artifact itself.')}>download</span>
                          </span>)}
                        </div>}
                      </div>;
                    })}
                    {p.id === 'B' && <QcGates decision={decision}/>}
                    <div className="phase-actions">
                      {(ps === 'pending' || ps === 'skipped') && (SKIPDEP[p.id] || {}).skippable !== false && <button className={'btn sm' + (ps === 'skipped' ? '' : ' ghost')}
                        onClick={() => { setSkip(s => ({ ...s, [p.id]:!s[p.id] })); onToast(skip[p.id] ? 'Phase ' + p.id + ' is back in the run.' : 'Phase ' + p.id + ' will not run — downstream steps read the cached outputs of the previous run.'); }}>
                        <Icon name="skip" size={11}/>{ps === 'skipped' ? 'Include phase ' + p.id : 'Skip phase ' + p.id}</button>}
                      {ps === 'pending' && (SKIPDEP[p.id] || {}).skippable === false && <span className="hint dim"><Icon name="warn" size={10}/> Can’t be skipped — {(SKIPDEP[p.id].blocks || []).join(', ')} depend on it.</span>}
                      {ps === 'pending' && runState !== 'running' && <button className="btn sm" onClick={start}><Icon name="play" size={10}/>Run phase {p.id}</button>}
                      <span style={{ flex:1 }}/>
                    </div>
                  </div>}
                </div>;
              })}
            </div>
            <div className="cap-hint">Tip — open any step in the full view for the parameters it actually ran with, its raw output, and where the data came from.</div>
          </>}
        </div>}
      </div>

      {reportReady && <div className="wf-after">
        <ReportTabs onToast={onToast} onOpenData={onOpenData} onOpenModels={onOpenModels} decision={decision} onOpenStep={openStep} onOpenFile={onOpenFile}/>
      </div>}
    </div>

    <div className="panel-foot">
      {runState !== 'running' && !licensed && needsLicence && <div className="footblock">
        <Icon name="warn" size={13}/>
        <span className="hint">GENCODE v44 annotation licence not accepted — required by this workflow's reference build.</span>
        <button className="btn sm" onClick={() => { setLicensed(true); onToast('Licence accepted for this account — recorded in the run\u2019s audit trail.'); }}>Accept licence</button>
      </div>}
      <div className="run-primary">
        {runState !== 'running'
          ? <button className="btn primary" disabled={needsLicence && !licensed} onClick={start}><Icon name="play" size={11}/>{runState === 'completed' ? 'Run again' : 'Confirm and run'}</button>
          : <button className="btn" style={{ flex:1, height:'38px', fontSize:'13.5px', fontWeight:600, borderRadius:'var(--r-md)' }}
              onClick={() => { setRunState('idle'); setTick(0); setGate(null); onToast('Cancelled. Partial outputs are kept and stay inspectable.'); }}><Icon name="stop" size={10}/> Cancel run</button>}
      </div>
    </div>

    {rerun && <div className={'deep ' + deepMode}><div className="deepbody"><RerunCard sk={rerun} onClose={() => setRerun(null)} onToast={onToast}/></div></div>}
    {deep && !rerun && (() => { const s = allSteps[deep.i]; return <StepDeep sk={s.sk} phase={s.phase} stepName={s.name} idx={deep.i + 1} total={allSteps.length}
      status={stepState(s)} mode={deepMode} setMode={setDeepMode} focusOut={deep.out}
      onClose={() => setDeep(null)} onToast={onToast} onOpenData={onOpenData}
      onStep={d => setDeep({ i:Math.min(allSteps.length - 1, Math.max(0, deep.i + d)), out:null })}
      onRerun={sk => setRerun(sk)}/>; })()}
  </div>;
}

/* QC gates in the shipped collapsed block. */
function QcGates({ decision }) {
  const [open, setOpen] = React.useState(false);
  return <div className={'qc-block' + (open ? ' open' : '')}>
    <button className="qc-toggle" onClick={() => setOpen(o => !o)} aria-expanded={open}>
      <span className="qc-caret"><Icon name="chevronRight" size={12}/></span>
      <Icon name="beaker" size={11}/>
      <span className="qc-toggle-label">QC gates</span>
      <span className="qc-count">{QC_GATE.measured.length}</span>
      <span className="qc-hint">{open ? 'hide' : 'show'}</span>
    </button>
    {open && <div className="qc-detail">
      <div className="qc-detail-head">Evaluated after phase · edit any threshold</div>
      {QC_GATE.measured.map(([k, m, thr]) => { const bad = /2 of 24|3\.7/.test(m); return <div key={k} className="qc-gate">
        <span className="metric">{k}</span><span className="op">≥</span><span className="thr">{thr.replace(/^[^:]*:\s*/, '')}</span>
        <span className="arrow">→</span>
        <span className={'obs ' + (bad ? (decision === 'apply' ? 'remediated' : 'flag') : '')}>{m}</span>
        <span className={'verdict ' + (bad ? (decision === 'apply' ? 'remediated' : 'flag') : '')}>{bad ? (decision === 'apply' ? '↻ fixed' : '⚑ flagged') : '✓'}</span>
      </div>; })}
    </div>}
  </div>;
}

/* Output previews — a small visual card per artifact, in a grid that reflows to
   the tab's width, searchable, and annotatable. Notes persist per output. */
const OUT_KIND = n => /\.(png|pdf|svg|jpg)$/i.test(n) ? 'figure'
  : /\.(csv|tsv|txt)$/i.test(n) ? 'table'
  : /\.(h5|h5ad|mtx|npz|rds)$/i.test(n) ? 'matrix'
  : /\.log$/i.test(n) ? 'log'
  : /\.(json|ya?ml)$/i.test(n) ? 'record' : 'file';

function OutThumb({ kind }) {
  if (kind === 'figure') return <div className="opv-thumb"><span className="tk">figure</span>
    <span className="bar" style={{ height:'26px' }}/><span className="bar" style={{ height:'44px' }}/><span className="bar" style={{ height:'18px' }}/><span className="bar" style={{ height:'52px' }}/><span className="bar" style={{ height:'33px' }}/></div>;
  if (kind === 'matrix') return <div className="opv-thumb"><span className="tk">matrix</span>
    <span className="cells">{Array.from({ length:18 }).map((_, i) => <i key={i}/>)}</span></div>;
  if (kind === 'record') return <div className="opv-thumb"><span className="tk">record</span>
    <span className="scat"><i style={{ left:'8%', top:'62%' }}/><i style={{ left:'26%', top:'40%' }}/><i style={{ left:'44%', top:'55%' }}/><i style={{ left:'62%', top:'22%' }}/><i style={{ left:'80%', top:'34%' }}/></span></div>;
  return <div className="opv-thumb"><span className="tk">{kind}</span>
    <span className="rows">{Array.from({ length:5 }).map((_, i) => <i key={i} style={{ width:(96 - i * 11) + '%' }}/>)}</span></div>;
}

function OutputGrid({ onToast, onOpenData, onOpenStep }) {
  const all = React.useMemo(() => Object.keys(STEP_DEEP).flatMap(sk => STEP_DEEP[sk].outs.map(o => ({ sk, o }))), []);
  const [q, setQ] = React.useState('');
  const [editing, setEditing] = React.useState(null);
  const [draft, setDraft] = React.useState('');
  const [notes, setNotes] = React.useState(() => { try { return JSON.parse(localStorage.getItem('bm-output-notes') || '{}'); } catch (e) { return {}; } });
  const save = (id, v) => {
    const next = { ...notes }; if (v.trim()) next[id] = v.trim(); else delete next[id];
    setNotes(next); try { localStorage.setItem('bm-output-notes', JSON.stringify(next)); } catch (e) {}
    setEditing(null); onToast(v.trim() ? 'Note saved on this output — it travels with the artifact into the report.' : 'Note removed.');
  };
  const needle = q.trim().toLowerCase();
  const list = all.filter(({ sk, o }) => !needle || (o.name + ' ' + (o.meta || '') + ' ' + (o.ev || '') + ' ' + sk + ' ' + (notes[o.id] || '')).toLowerCase().includes(needle));
  return <div className="col" style={{ gap:'10px' }}>
    <div className="opv-bar">
      <span className="searchbox sm">
        <Icon name="search" size={13}/>
        <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search outputs — name, step, evidence class, your notes" aria-label="Search outputs"/>
        {q && <button className="clr" onClick={() => setQ('')} title="Clear">✕</button>}
      </span>
      <span className="opv-count">{list.length} of {all.length}</span>
    </div>
    <div className="opv-grid">
      {list.map(({ sk, o }) => { const note = notes[o.id]; const isEd = editing === o.id;
        return <div key={o.id} className={'opv' + (note ? ' noted' : '')}>
          <OutThumb kind={OUT_KIND(o.name)}/>
          <div className="opv-meta">
            <span className="opv-name" title={o.name}>{o.name}</span>
            <span className="opv-sub" title={o.meta}>{o.meta}</span>
            <EvBadge ev={o.ev} compact/>
          </div>
          {isEd && <div className="opv-note">
            <textarea autoFocus value={draft} onChange={e => setDraft(e.target.value)} placeholder="What matters about this file — for you, later."/>
            <div className="row ac" style={{ gap:'6px' }}>
              <button className="btn sm accent" onClick={() => save(o.id, draft)}>Save note</button>
              <button className="btn sm ghost" onClick={() => setEditing(null)}>Cancel</button>
            </div>
          </div>}
          {!isEd && note && <div className="opv-notetext" onClick={() => { setEditing(o.id); setDraft(note); }}>
            <span className="nl">your note</span>{note}
          </div>}
          <div className="opv-foot">
            <span className="sk">step {sk}</span>
            {o.dataset && <button className="btn sm ghost" title="Open as a dataset in Files" onClick={onOpenData}><Icon name="file" size={11}/></button>}
            <button className="btn sm ghost" title={note ? 'Edit your note' : 'Add a note'} onClick={() => { setEditing(o.id); setDraft(note || ''); }}>{note ? 'edit note' : 'note'}</button>
            <button className="btn sm" onClick={() => onOpenStep(sk, o.id)}>open</button>
          </div>
        </div>; })}
    </div>
    {!list.length && <span className="hint dim">No output matches “{q}”.</span>}
    <span className="hint">Every artifact the run produced, tagged by evidence class and traceable to the step that made it. Notes you add here travel with the file into the report.</span>
  </div>;
}

function ReportTabs({ onToast, onOpenData, onOpenModels, decision, onOpenStep, onOpenFile }) {
  const [at, setAt] = React.useState('report');
  const [claim, setClaim] = React.useState(null);
  return <div className="after-run-report">
    <div className="after-run-head">
      <span className="kicker">After run</span><span style={{ flex:1 }}/>
    </div>
    <div className="after-run-tabs">{RTABS.map(([k, lbl]) => <button key={k} className={'after-run-tab' + (k === at ? ' active' : '')} onClick={() => setAt(k)}>{lbl}</button>)}</div>
    <div className="after-run-body">
      {at === 'report' && <DocEditor docId="rep1" onToast={onToast} onOpenFile={onOpenFile} framed/>}
      {at === 'outputs' && <OutputGrid onToast={onToast} onOpenData={onOpenData} onOpenStep={onOpenStep}/>}
      {at === 'findings' && <div className="col" style={{ gap:'9px' }}>
        <div className="findings-card">
          <span className="hint"><Claim id="c1" onPick={setClaim}/> move at <Claim id="c2" onPick={setClaim}/> (DESeq2 Wald); the response is dominated by interferon signalling. <Claim id="c3" onPick={setClaim}/> were excluded at the phase-B gate, as instruction 3 requires, and the effect survives their removal (<Claim id="c4" onPick={setClaim}/>).</span>
        </div>
        {claim && <ClaimPop id={claim} onClose={() => setClaim(null)} onOpenStep={(sk, out) => { setClaim(null); onOpenStep(sk, out); }}/>}
        <span className="hint dim">Every number is a link to the output it is findable in — the report is auditable by clicking, not just by reading.</span>
      </div>}
      {at === 'params' && <div className="col" style={{ gap:'8px' }}>
        <ParamRows onToast={onToast} wf={wf}/>
        <span className="hint" style={{ padding:'0 18px' }}>The same surface as configuration, read-only — and each step's <i>resolved</i> values live in its full view.</span>
      </div>}
      {at === 'qc' && <div className="col" style={{ gap:'9px' }}>
        <div className="qline"><span className="chip warn"><span className="dot"/>gate 2</span><span className="hint">Library-size floor halted the run; {decision === 'keep' ? 'your parameters were kept, and the gate is recorded as overridden' : 'the suggestion was applied — 2 samples excluded and listed'}. Evidence: {QC_GATE.evidence}.</span></div>
        <div className="qline"><span className="chip ok"><span className="dot"/>gates 1, 3, 4</span><span className="hint">Contamination, design consistency and FDR calibration passed.</span></div>
        <button className="btn sm ghost" style={{ alignSelf:'flex-start' }} onClick={onOpenModels}>These gates also run on model training →</button>
      </div>}
      {at === 'traj' && <Trajectory onToast={onToast}/>}
      {['imrad', 'software', 'cite'].indexOf(at) >= 0 && <div className="col" style={{ gap:'7px' }}>
        <span className="k2">{(RTABS.find(t => t[0] === at) || [])[1]}</span>
        <span className="hint">Existing after-run tab — unchanged. Shown so the added surfaces can be judged against the real panel structure.</span>
      </div>}
    </div>
  </div>;
}

/* One run record, scoped — not a per-project copy of the run history. */
function RunHistory({ scope, setScope, onToast, onOpenData, onOpenChat, onOpenModels, deepDefault, onOpenFile }) {
  const [open, setOpen] = React.useState(null);
  const all = PROJECTS.flatMap(p => (PROJECT_RUNS[p.name] || []).map(r => ({ ...r, project:p.name })));
  const list = scope ? all.filter(r => r.project === scope) : all;
  if (open) return <RunSurface project={open.project} onToast={onToast} onOpenData={onOpenData} onOpenModels={onOpenModels}
    onBack={() => setOpen(null)} startAt={open.stage} deepDefault={deepDefault} onOpenFile={onOpenFile}/>;
  return <div className="mainpane">
    <div className="objhead">
      <div className="crumb"><span>Workflows</span><span className="sep">/</span><span>Runs &amp; import</span>{scope && <><span className="sep">/</span><span>{scope}</span></>}</div>
      <div className="objtitle">
        <h2 style={{ fontFamily:'var(--font-ui)' }}>Workflows</h2>
        <span className="chip acc">{list.length} of {all.length}</span>
        <span className="spacer"/>
        <button className="btn sm" onClick={() => onToast('Import a workflow: a Nextflow or Snakemake pipeline from a repository, or a packaged bundle. It is validated, its parameters are read, and it becomes available to every project.')}><Icon name="plus" size={11}/>Import a workflow</button>
      </div>
      <span className="anchor">Every run this account has started, and where new pipelines come in. A run is one record wherever you reach it — the project chips below are a filter on this list, not a second copy of it. Importing a validated pipeline here makes it available to every project.</span>
      <div className="scopechips">
        <button className={'schip' + (!scope ? ' on' : '')} onClick={() => setScope(null)}>All projects</button>
        {PROJECTS.filter(p => (PROJECT_RUNS[p.name] || []).length).map(p => <button key={p.name} className={'schip' + (scope === p.name ? ' on' : '')} onClick={() => setScope(p.name)}>{p.name}<span className="kb">{(PROJECT_RUNS[p.name] || []).length}</span></button>)}
      </div>
    </div>
    <div className="objbody">
      {list.length ? <>
        <div className="col" style={{ gap:'8px' }}>
          {list.map(r => <button key={r.id} className="runrow" onClick={() => setOpen({ project:r.project, stage:r.status === 'completed' ? 'report' : r.status === 'running' ? 'watch' : 'cfg' })}>
            <span className="col" style={{ gap:'3px', flex:1, minWidth:0 }}>
              <span style={{ fontWeight:600 }}>{r.name}</span>
              <span className="hint dim">{r.from}</span>
            </span>
            {!scope && <span className="chip"><Icon name="folder" size={10}/>{r.project}</span>}
            <span className="chip">{r.gates}</span>
            <span className="hint dim">{r.when}</span>
            <StatusPill s={r.status}/>
          </button>)}
        </div>
        <span className="hint">Opening one gives the shipped workflow panel — settings, phases and the after-run report — anchored to a project instead of a conversation. The list itself stays global.</span>
      </> : <div className="card2 col" style={{ gap:'10px', alignItems:'flex-start' }}>
        <span className="k2">No runs in {scope}</span>
        <span className="hint">A run starts where the work starts — in a chat, or from the files themselves — and then appears here under this project's filter.</span>
        <div className="row" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px' }}>
          <button className="btn sm" onClick={onOpenChat}>Open a chat in this project</button>
          <button className="btn sm ghost" onClick={onOpenData}>Start from a file →</button>
        </div>
      </div>}
    </div>
  </div>;
}
Object.assign(window, { RunSurface, RunHistory, Slot, ParamRows, GatePanel, QcGates, ReportTabs, OutputGrid, OutThumb, ALL_STEPS });
