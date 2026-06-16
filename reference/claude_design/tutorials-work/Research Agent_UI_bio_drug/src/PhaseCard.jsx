// PhaseCard + Step + QC Block
const { useState: useStateP } = React;

function StatusChip({ status }) {
  const map = {
    pending:   { cls: '',     label: 'PENDING' },
    running:   { cls: 'run',  label: 'RUNNING' },
    completed: { cls: 'ok',   label: 'DONE' },
    failed:    { cls: 'err',  label: 'FAILED' },
    skipped:   { cls: '',     label: 'SKIPPED' },
  };
  const s = map[status] || map.pending;
  return (
    <span className={'chip ' + s.cls}>
      {status === 'running'
        ? <span className="spinner"/>
        : <span className={'dot' + (status === 'running' ? ' pulse' : '')}/>}
      {s.label}
    </span>
  );
}

function Step({ step, onSkip, onPreview, onDownload, onAdjust, onRerun }) {
  const [paramsOpen, setParamsOpen] = useStateP(false);
  const iconFor = (t) => t === 'image' ? 'image' : t === 'folder' ? 'folder' : 'table';
  const stop = (fn) => (e) => { e.stopPropagation(); e.preventDefault(); fn && fn(); };

  return (
    <div className={'step ' + step.status}>
      <div className="step-head">
        <div className={'name' + (step.status === 'skipped' ? ' dim' : '')}>
          {step.name}
        </div>
        {step.runCount > 1 && <span className="runcount">×{step.runCount}</span>}
        <StatusChip status={step.status}/>
        <div className="actions">
          {step.params && step.params.length > 0 && (
            <button className="btn ghost sm" onClick={stop(() => setParamsOpen(o => !o))}
              title="Inline params">
              <Icon name="settings" size={11}/>
            </button>
          )}
          {step.status === 'completed' && (
            <button className="btn ghost sm" onClick={stop(() => onRerun && onRerun(step))} title="Rerun">
              <Icon name="refresh" size={11}/>
            </button>
          )}
          {step.status === 'failed' && (
            <button className="btn ghost sm" onClick={stop(() => onAdjust && onAdjust(step))} title="Adjust & rerun">
              <Icon name="wand" size={11}/> Adjust
            </button>
          )}
          {/*
            Skip step — disabled for this release. Skipping a single step
            without recomputing downstream dependencies is risky; needs
            careful alignment with the auto-loop + dependency-graph work
            before it ships. Uncomment to restore.

            {(step.status === 'pending' || step.status === 'failed') && (
              <button className="btn ghost sm danger" onClick={stop(() => onSkip && onSkip(step))} title="Skip step">
                <Icon name="skip" size={11}/>
              </button>
            )}
          */}
        </div>
      </div>

      {step.params && step.params.length > 0 && !paramsOpen && step.status !== 'pending' && (
        <div className="step-meta">
          {step.params.slice(0, 3).map(p => `${p.k}: ${p.v}`).join(' · ')}
        </div>
      )}

      {paramsOpen && step.params && step.params.length > 0 && (
        <div className="inline-params">
          {step.params.map(p => (
            <div className="inline-row" key={p.k}>
              <div className="k">{p.k}</div>
              <input defaultValue={p.v}/>
            </div>
          ))}
        </div>
      )}

      {step.status === 'completed' && step.outputs && step.outputs.length > 0 && (
        <div className="step-outputs" data-tour="step-outputs">
          {step.outputs.map((o, oi) => (
            <span className="output-file" key={o.name} data-tour={oi === 0 ? 'step-output-first' : undefined}>
              <Icon name={iconFor(o.type)} size={11}/>
              <span className="fn">{o.name}</span>
              <span className="act" onClick={() => onPreview && onPreview(o)}>view</span>
              <span className="act" onClick={() => onDownload && onDownload(o)}>download</span>
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

// A single QC gate row. The threshold is editable inline — clicking "edit"
// swaps it for an input PREFILLED with the workflow's default value, so the
// scientist tweaks rather than retypes. "done" commits.
function QcGateRow({ g, onEdit }) {
  const [editing, setEditing] = useStateP(false);
  const [val, setVal] = useStateP(g.threshold);
  const commit = (v) => { setEditing(false); onEdit && onEdit(g, v); };
  return (
    <div className={'qc-gate' + (editing ? ' editing' : '')}>
      <span className="metric">{g.metric}</span>
      <span className="op">{g.op}</span>
      {editing ? (
        <input className="qc-thr-input" defaultValue={g.threshold} autoFocus
          onChange={(e) => setVal(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') commit(e.target.value); if (e.key === 'Escape') setEditing(false); }}/>
      ) : (
        <span className="thr">{val}</span>
      )}
      <button className="linkish edit"
        onClick={() => editing ? commit(val) : setEditing(true)}>{editing ? 'done' : 'edit'}</button>
    </div>
  );
}

// QC gates are HIDDEN by default — the phase body shows only a small,
// muted "QC gate(s)" toggle. Clicking reveals the editable gate rows +
// the auto-loop control; clicking again hides them again. Keeps phases
// clean and scannable; QC detail is opt-in.
//
// The auto-loop switch is offered on EVERY phase that has a QC gate. Its
// initial position is the workflow's suggested default (`autoloop` prop,
// off for Bioconductor); flipping it on makes the phase self-remediate on
// a failed gate — apply the suggested fix and re-run, auto-proceeding
// after a 10s review window if no one steps in.
function QcBlock({ qc, autoloop, onEdit, onToggleLoop, hasAutoloop }) {
  const [open, setOpen] = useStateP(false);
  if (!qc || qc.length === 0) return null;
  return (
    <div className={'qc-block' + (open ? ' open' : '')}>
      <button className="qc-toggle" onClick={() => setOpen(o => !o)} aria-expanded={open}>
        <span className="qc-caret"><Icon name="chevronRight" size={12}/></span>
        <Icon name="beaker" size={11}/>
        <span className="qc-toggle-label">QC gate{qc.length > 1 ? 's' : ''}</span>
        <span className="qc-count">{qc.length}</span>
        <span className="qc-hint">{open ? 'hide' : 'show'}</span>
      </button>
      {open && (
        <div className="qc-detail" data-tour="qc-detail">
          <div className="qc-detail-head">Evaluated after phase · edit any threshold</div>
          {qc.map(g => <QcGateRow key={g.metric} g={g} onEdit={onEdit}/>)}
          <div className="qc-autoloop" data-tour="qc-autoloop">
            <span className={'switch' + (autoloop ? ' on' : '')}
              onClick={onToggleLoop} role="switch" aria-checked={autoloop}/>
            <span>Auto-loop this phase on fail <span className="mono" style={{color:'var(--text-dim)'}}>(max 3×)</span></span>
          </div>
          {autoloop && (
            <div className="qc-autoloop-note">
              On a failed gate, BioMate applies the suggested fix and re-runs automatically — <b>auto-proceeding after a 10s review window</b> if you don’t step in.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function PhaseCard({ phase, open, onToggle, onRunPhase, onSkipPhase, onStepAction, onEditGate, onToggleLoop, autoloopOn }) {
  const total = phase.steps.length;
  const done  = phase.steps.filter(s => s.status === 'completed' || s.status === 'skipped').length;
  const running = phase.steps.some(s => s.status === 'running');
  const failed  = phase.steps.some(s => s.status === 'failed');

  let status = 'pending';
  if (failed) status = 'failed';
  else if (running) status = 'running';
  else if (done === total) status = 'completed';

  return (
    <div className={'phase ' + status + (open ? ' open' : '')}>
      <div className="phase-head" onClick={onToggle}>
        <span className="caret"><Icon name="chevronRight" size={14}/></span>
        <div className="letter">{phase.id}</div>
        <div className="titles">
          <div className="title">Phase {phase.id} · {phase.name}</div>
          <div className="sub">{phase.summary}</div>
        </div>
        {status === 'running' && <span className="chip run"><span className="spinner"/>RUNNING</span>}
        {status === 'completed' && <span className="chip ok"><Icon name="check" size={10}/>DONE</span>}
        {status === 'failed' && <span className="chip err"><Icon name="warn" size={10}/>FAILED</span>}
        {status === 'pending' && <span className="progress-chip">{total} step{total>1?'s':''}</span>}
        {(status === 'running' || status === 'completed') && (
          <span className="progress-chip">{done}/{total}</span>
        )}
      </div>

      {open && (
        <div className="phase-body">
          {phase.steps.map(step => (
            <Step key={step.id} step={step}
              onSkip={(s) => onStepAction('skip', s, phase)}
              onRerun={(s) => onStepAction('rerun', s, phase)}
              onAdjust={(s) => onStepAction('adjust', s, phase)}
              onPreview={(o) => onStepAction('preview', o, phase)}
              onDownload={(o) => onStepAction('download', o, phase)}
            />
          ))}

          <QcBlock qc={phase.qc} autoloop={autoloopOn} hasAutoloop={phase.autoloop}
            onEdit={onEditGate}
            onToggleLoop={onToggleLoop}/>

          <div className="phase-actions">
            {status === 'pending' && (
              <button className="btn sm" onClick={onRunPhase}>
                <Icon name="play" size={10}/>
                {phase.steps.some(s => s.status === 'completed') ? 'Resume phase ' : 'Run phase '}{phase.id}
              </button>
            )}
            {status === 'running' && (
              <button className="btn sm" onClick={onRunPhase}>
                <Icon name="stop" size={10}/> Stop phase
              </button>
            )}
            {/*
              Skip phase — disabled for this release. Same caveat as skip
              step: needs dependency-graph alignment before it ships safely.
              Uncomment to restore.

              {status !== 'completed' && status !== 'skipped' && (
                <button className="btn ghost sm danger" onClick={onSkipPhase}>
                  <Icon name="skip" size={11}/> Skip phase
                </button>
              )}
            */}
            <span style={{flex:1}}/>
          </div>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────
// PhaseTabsView — horizontal multi-tab layout for the phase list.
// Alternative to the vertical cascade (accordion). Phases become a
// scrollable tab strip; the active phase's steps / QC / actions render
// in the body below. Reuses Step + QcBlock so step UX is identical.
// ─────────────────────────────────────────────────────────────────
function phaseStatusOf(phase) {
  const total = phase.steps.length;
  const done  = phase.steps.filter(s => s.status === 'completed' || s.status === 'skipped').length;
  const running = phase.steps.some(s => s.status === 'running');
  const failed  = phase.steps.some(s => s.status === 'failed');
  let status = 'pending';
  if (failed) status = 'failed';
  else if (running) status = 'running';
  else if (done === total) status = 'completed';
  return { status, total, done };
}

function PhaseTabsView({ phases, activeId, onSelect, onStepAction, onRunPhase, onSkipPhase, onEditGate, onToggleLoop, autoloopMap, extras }) {
  const active = phases.find(p => p.id === activeId) || phases[0];
  const a = phaseStatusOf(active);
  const activeIdx = phases.findIndex(p => p.id === active.id);

  return (
    <div className="phase-tabs" data-tour="phase-list">
      {/* Tab strip — one tab per phase, horizontally scrollable */}
      <div className="phase-tabbar" role="tablist">
        {phases.map((phase, idx) => {
          const { status, total, done } = phaseStatusOf(phase);
          const isActive = phase.id === active.id;
          return (
            <React.Fragment key={phase.id}>
              {idx > 0 && <span className={'ptab-rail' + (done === total && status === 'completed' ? ' done' : '')}/>}
              <button
                role="tab"
                aria-selected={isActive}
                className={'phase-tab ' + status + (isActive ? ' active' : '')}
                onClick={() => onSelect(phase.id)}
                title={'Phase ' + phase.id + ' · ' + phase.name}>
                <span className="ptab-letter">
                  {status === 'running'
                    ? <span className="spinner"/>
                    : status === 'completed'
                      ? <Icon name="check" size={11}/>
                      : phase.id}
                </span>
                <span className="ptab-text">
                  <span className="ptab-name">{phase.name}</span>
                  <span className="ptab-meta">
                    {status === 'running' ? 'Running' :
                     status === 'completed' ? 'Done' :
                     status === 'failed' ? 'Failed' : 'Pending'} · {done}/{total}
                  </span>
                </span>
              </button>
            </React.Fragment>
          );
        })}
      </div>

      {/* Active phase body */}
      <div className={'phase-tab-panel ' + a.status} role="tabpanel" key={active.id}>
        <div className="ptab-head">
          <div className="ptab-head-row">
            <div className="ptab-title">Phase {active.id} · {active.name}</div>
            <span style={{flex:1}}/>
            {a.status === 'running' && <span className="chip run"><span className="spinner"/>RUNNING</span>}
            {a.status === 'completed' && <span className="chip ok"><Icon name="check" size={10}/>DONE</span>}
            {a.status === 'failed' && <span className="chip err"><Icon name="warn" size={10}/>FAILED</span>}
            {a.status === 'pending' && <span className="progress-chip">{a.total} step{a.total>1?'s':''}</span>}
          </div>
          <div className="ptab-sub">{active.summary}</div>
        </div>

        <div className="ptab-steps">
          {active.steps.map(step => (
            <Step key={step.id} step={step}
              onSkip={(s) => onStepAction('skip', s, active)}
              onRerun={(s) => onStepAction('rerun', s, active)}
              onAdjust={(s) => onStepAction('adjust', s, active)}
              onPreview={(o) => onStepAction('preview', o, active)}
              onDownload={(o) => onStepAction('download', o, active)}
            />
          ))}
        </div>

        <QcBlock qc={active.qc} autoloop={autoloopMap[active.id]} hasAutoloop={active.autoloop}
          onEdit={onEditGate}
          onToggleLoop={() => onToggleLoop(active.id)}/>

        {extras && extras(active, activeIdx)}

        <div className="phase-actions">
          {a.status === 'pending' && (
            <button className="btn sm" onClick={() => onRunPhase(active)}>
              <Icon name="play" size={10}/>
              {active.steps.some(s => s.status === 'completed') ? 'Resume phase ' : 'Run phase '}{active.id}
            </button>
          )}
          {a.status === 'running' && (
            <button className="btn sm" onClick={() => onRunPhase(active)}>
              <Icon name="stop" size={10}/> Stop phase
            </button>
          )}
          <span style={{flex:1}}/>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PhaseCard, PhaseTabsView, Step, QcBlock, StatusChip });
