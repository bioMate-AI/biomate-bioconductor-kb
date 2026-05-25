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

function QcBlock({ qc, autoloop, onEdit, onToggleLoop, hasAutoloop }) {
  if (!qc || qc.length === 0) return null;
  return (
    <div className="qc-block">
      <div className="qc-head">
        <Icon name="beaker" size={11}/> QC Gates — evaluated after phase
      </div>
      {qc.map(g => (
        <div className="qc-gate" key={g.metric}>
          <span className="metric">{g.metric}</span>
          <span className="op">{g.op}</span>
          <span className="thr">{g.threshold}</span>
          <button className="linkish edit" onClick={() => onEdit && onEdit(g)}>edit</button>
        </div>
      ))}
      {hasAutoloop && (
        <div className="qc-autoloop">
          <span className={'switch' + (autoloop ? ' on' : '')}
            onClick={onToggleLoop} role="switch" aria-checked={autoloop}/>
          <span>Auto-loop this phase on fail <span className="mono" style={{color:'var(--text-dim)'}}>(max 3×)</span></span>
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
            {status === 'completed' && (
              <button className="linkish" style={{fontSize:12}}>View phase outputs</button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

Object.assign(window, { PhaseCard, Step, QcBlock, StatusChip });
