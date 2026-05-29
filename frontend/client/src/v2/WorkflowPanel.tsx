// @ts-nocheck
import React from "react";
// WorkflowPanel — main right-side panel
const { useState: useStateW, useEffect: useEffectW, useRef: useRefW, useMemo } = React;

function WorkflowPanel({ scenario, runState, setRunState, onOpenModal, tweaks, watcherAttached, setWatcherAttached, onClosePanel, onResize }) {
  const base = window.SCENARIOS[scenario];
  const showQcHalt = tweaks.qcHalt;
  const showLicenseGate = tweaks.licenseGate;
  const showBlocked = tweaks.blocked;
  const [phases, setPhases] = useStateW(() => base.phases.map(p => ({...p, steps: p.steps.map(s => ({...s, runCount: 1}))})));
  const [openPhaseId, setOpenPhaseId] = useStateW(() => {
    // Running phase or first phase open by default
    const running = base.phases.find(p => p.steps.some(s => s.status === 'running'));
    return running ? running.id : base.phases[0].id;
  });
  const [settingsOpen, setSettingsOpen] = useStateW(false);
  const [autoloopMap, setAutoloopMap] = useStateW(() => {
    const m = {};
    base.phases.forEach(p => m[p.id] = p.autoloop);
    return m;
  });

  // Reset when scenario changes
  useEffectW(() => {
    setPhases(base.phases.map(p => ({...p, steps: p.steps.map(s => ({...s, runCount: 1}))})));
    const running = base.phases.find(p => p.steps.some(s => s.status === 'running'));
    setOpenPhaseId(running ? running.id : base.phases[0].id);
  }, [scenario]);

  // When runState flips to 'completed' externally (via Tweaks / Tour), force
  // every step to completed and seed any missing outputs so the After-Run
  // section + per-step file viewers have something to show.
  useEffectW(() => {
    if (runState !== 'completed') return;
    setPhases(prev => prev.map(p => ({
      ...p,
      steps: p.steps.map(s => {
        const baseOuts = (base.phases.find(bp => bp.id === p.id)?.steps.find(bs => bs.id === s.id)?.outputs) || [];
        const seeded = (baseOuts.length > 0)
          ? baseOuts
          : [{ name: `${s.id}_summary.txt`, type: 'table' }];
        return {
          ...s,
          status: s.status === 'skipped' ? 'skipped' : 'completed',
          outputs: (s.outputs && s.outputs.length > 0) ? s.outputs : seeded,
        };
      }),
    })));
  }, [runState, scenario]);

  // Simulated SSE run
  const tickRef = useRefW(null);
  useEffectW(() => {
    if (runState !== 'running') { if (tickRef.current) clearInterval(tickRef.current); return; }
    tickRef.current = setInterval(() => {
      setPhases(prev => {
        const next = prev.map(p => ({...p, steps: p.steps.map(s => ({...s}))}));
        // find next running step
        let didAdvance = false;
        for (const p of next) {
          for (let i = 0; i < p.steps.length; i++) {
            const s = p.steps[i];
            if (s.status === 'running') {
              s.status = 'completed';
              // seed fake outputs if none
              if (!s.outputs || s.outputs.length === 0) {
                s.outputs = [{ name: s.id + '_output.star', type: 'table' }];
              }
              didAdvance = true;
              // start next step
              if (p.steps[i+1]) { p.steps[i+1].status = 'running'; }
              else {
                // phase complete — start next phase
                const pIdx = next.findIndex(x => x.id === p.id);
                const nextPhase = next[pIdx + 1];
                if (nextPhase) { nextPhase.steps[0].status = 'running'; setOpenPhaseId(nextPhase.id); }
              }
              break;
            }
          }
          if (didAdvance) break;
        }
        if (!didAdvance) {
          // no running step — start first pending
          const firstPhase = next.find(p => p.steps.some(s => s.status === 'pending'));
          if (firstPhase) {
            const firstStep = firstPhase.steps.find(s => s.status === 'pending');
            if (firstStep) { firstStep.status = 'running'; setOpenPhaseId(firstPhase.id); }
          } else {
            setRunState('completed');
          }
        }
        return next;
      });
    }, tweaks.speed || 900);
    return () => { if (tickRef.current) clearInterval(tickRef.current); };
  }, [runState, tweaks.speed]);

  const totalSteps = useMemo(() => phases.reduce((n,p)=>n+p.steps.length, 0), [phases]);
  const doneSteps  = useMemo(() => phases.reduce((n,p)=>n+p.steps.filter(s=>s.status==='completed'||s.status==='skipped').length, 0), [phases]);
  const pct = Math.round(100 * doneSteps / Math.max(1, totalSteps));

  const overallStatus = runState;

  const togglePhase = (id) => setOpenPhaseId(cur => cur === id ? null : id);

  // Tiny toast for non-blocking link actions (download / edit / suggest)
  const [toast, setToast] = useStateW(null);
  useEffectW(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 2400);
    return () => clearTimeout(t);
  }, [toast]);
  const flash = (msg) => setToast({ msg, id: Date.now() });

  const handleStepAction = (action, arg, phase) => {
    if (action === 'skip') {
      const downstream = phases.slice(phases.findIndex(p => p.id === phase.id) + 1).map(p => `Phase ${p.id}`);
      onOpenModal('skip', { targetKind: 'step', name: arg.name, phaseId: phase.id, stepId: arg.id, downstream,
        confirm: () => setPhases(prev => prev.map(p => p.id !== phase.id ? p : ({
          ...p, steps: p.steps.map(s => s.id === arg.id ? {...s, status: 'skipped'} : s)
        }))) });
    } else if (action === 'rerun') {
      setPhases(prev => prev.map(p => p.id !== phase.id ? p : ({
        ...p, steps: p.steps.map(s => s.id === arg.id ? {...s, status: 'running', runCount: (s.runCount||1)+1} : s)
      })));
      if (runState !== 'running') setRunState('running');
    } else if (action === 'adjust') {
      onOpenModal('adjust', { step: arg });
    } else if (action === 'preview') {
      onOpenModal('preview', { file: arg });
    } else if (action === 'download') {
      flash(`Download queued — ${arg.name}`);
    }
  };
  const handleSkipPhase = (phase) => {
    const downstream = phases.slice(phases.findIndex(p => p.id === phase.id) + 1).map(p => `Phase ${p.id}`);
    onOpenModal('skip', { targetKind: 'phase', name: `Phase ${phase.id} · ${phase.name}`, phaseId: phase.id, downstream,
      confirm: () => setPhases(prev => prev.map(p => p.id !== phase.id ? p : ({
        ...p, steps: p.steps.map(s => ({...s, status: 'skipped'}))
      }))) });
  };
  const handleRunPhase = (phase) => {
    setPhases(prev => prev.map(p => p.id !== phase.id ? p : ({
      ...p, steps: p.steps.map((s, i) => i === 0 && s.status === 'pending' ? {...s, status: 'running'} : s)
    })));
    if (runState !== 'running') setRunState('running');
    setOpenPhaseId(phase.id);
  };

  const handleRun = () => {
    if (runState === 'idle' || runState === 'completed' || runState === 'failed') {
      // reset and run
      setPhases(base.phases.map(p => ({...p, steps: p.steps.map((s, i) => ({
        ...s,
        runCount: 1,
        status: (p.id === base.phases[0].id && i === 0) ? 'running' : 'pending',
        outputs: [],
      }))})));
      setOpenPhaseId(base.phases[0].id);
      setRunState('running');
    } else if (runState === 'running') {
      setRunState('idle');
    }
  };

  const hasAnyQc = phases.some(p => p.qc && p.qc.length > 0);
  const isSingleStep = base.phases.length === 1 && base.phases[0].steps.length === 1;

  return (
    <aside className="panel">
      {/* Drag handle on the left edge — lets users resize the panel width
          directly. Calls back to the host with the new width in px. */}
      <div className="panel-resizer"
        onMouseDown={(e) => {
          if (!onResize) return;
          e.preventDefault();
          const startX = e.clientX;
          const panelEl = e.currentTarget.parentElement;
          const startW = panelEl ? panelEl.getBoundingClientRect().width : 500;
          const onMove = (ev) => {
            const dx = startX - ev.clientX;       // dragging left grows width
            const next = Math.max(380, Math.min(800, startW + dx));
            onResize(Math.round(next));
          };
          const onUp = () => {
            window.removeEventListener('mousemove', onMove);
            window.removeEventListener('mouseup', onUp);
            document.body.style.cursor = '';
          };
          document.body.style.cursor = 'ew-resize';
          window.addEventListener('mousemove', onMove);
          window.addEventListener('mouseup', onUp);
        }}
        title="Drag to resize"
      />
      <div className="panel-head" data-tour="panel-header">
        <div className="top-row">
          <div>
            <div className="kicker">{base.domain} · Workflow</div>
            <div className="name">{base.name}</div>
            <div className="sub">{base.subtitle}</div>
          </div>
          <div style={{display:'flex', gap:2}}>
            <button className="iconbtn" title="Workflow docs"><Icon name="book" size={16}/></button>
            <button className="iconbtn" title="Close panel" onClick={onClosePanel}><Icon name="x" size={16}/></button>
          </div>
        </div>

        {(runState === 'running' || runState === 'completed' || pct > 0) && (
          <div className="run-bar">
            <span className="meta">
              {runState === 'running' ? 'Running' :
               runState === 'completed' ? 'Completed' :
               runState === 'failed' ? 'Failed' : 'Ready'}
            </span>
            <div className="progress"><div className="fill" style={{width: pct + '%'}}/></div>
            <span className="pct">{pct}%</span>
            <span className="meta">{doneSteps}/{totalSteps}</span>
          </div>
        )}
      </div>

      <div className="panel-body" data-tour="panel-body">
        {/* Workflow settings strip — sits at the top of the panel body
            so global params frame the run before the phase list. */}
        <div className={'strip' + (settingsOpen ? ' open' : '')} onClick={() => setSettingsOpen(o => !o)}>
          <span className="caret"><Icon name="chevronRight" size={13}/></span>
          <span className="label">Workflow settings</span>
          <span className="hint">{base.globalParams.length} params</span>
        </div>
        {settingsOpen && (
          <div className="strip-body">
            {base.globalParams.map(p => (
              <div className="param-row" key={p.key}>
                <div className="k">{p.label}</div>
                <div className="v" title={p.value}>{p.value}</div>
                <button className="linkish edit" style={{fontSize:11}}
                  onClick={() => flash(`Edit “${p.label}” in workflow settings`)}>edit</button>
              </div>
            ))}
          </div>
        )}

        {!isSingleStep && (
          <div style={{padding:'10px 18px 4px', fontSize:11, color:'var(--text-dim)',
            textTransform:'uppercase', letterSpacing:'0.05em', fontWeight:600}}>
            Phases · {phases.length}
          </div>
        )}
        {isSingleStep && (
          <div style={{padding:'10px 18px 4px', fontSize:11, color:'var(--text-dim)',
            textTransform:'uppercase', letterSpacing:'0.05em', fontWeight:600}}>
            Single step
          </div>
        )}
        {showLicenseGate && (
          <div className="alert warn">
            <span className="ic"><Icon name="warn" size={14}/></span>
            <div className="body">
              <strong>Credential required</strong> — AlphaFold database access needs a licensed UniProt mirror.
              <div className="act">
                <button className="btn sm">Configure credentials</button>
                <button className="linkish">Learn more</button>
              </div>
            </div>
          </div>
        )}
        {showBlocked && (
          <div className="alert err">
            <span className="ic"><Icon name="warn" size={14}/></span>
            <div className="body">
              <strong>Execution blocked</strong> — required parameter <span className="mono">input</span> is missing.
              <div className="act">
                <button className="btn sm">Fix now</button>
                <button className="linkish">Confirm anyway</button>
              </div>
            </div>
          </div>
        )}

        <div className="phase-list" data-tour="phase-list">
          {phases.map((phase, idx) => (
            <React.Fragment key={phase.id}>
              <PhaseCard phase={phase}
                open={openPhaseId === phase.id}
                onToggle={() => togglePhase(phase.id)}
                onRunPhase={() => handleRunPhase(phase)}
                onSkipPhase={() => handleSkipPhase(phase)}
                onStepAction={handleStepAction}
                autoloopOn={autoloopMap[phase.id]}
                onEditGate={(g) => flash(`Edit QC gate — ${g.metric} (threshold panel)`)}
                onToggleLoop={() => setAutoloopMap(m => ({...m, [phase.id]: !m[phase.id]}))}
              />
              {showQcHalt && idx === 0 && (
                <AutoLoopCard phase={phase} attempt={2} maxAttempts={3}
                  autoloop={autoloopMap[phase.id]}
                  onAccept={() => { flash(autoloopMap[phase.id] ? 'Auto-loop cancelled — applying now' : 'Applied — Phase A rerunning with new params'); }}
                  onDismiss={() => flash('QC halt dismissed — proceeding as-is')}/>
              )}
            </React.Fragment>
          ))}
        </div>

        <div className="suggest-step-row">
          <button className="linkish" onClick={() => {
            const chatInput = document.querySelector('.chat-input textarea');
            if (chatInput) {
              chatInput.focus();
              chatInput.value = 'Suggest an additional step to add before ';
              chatInput.dispatchEvent(new Event('input', { bubbles: true }));
            }
            flash('Describe the step you want to add — then press send');
          }}><Icon name="plus" size={11}/> Suggest a new step via chat</button>
        </div>

        <div className="cap-hint">
          Tip — you can edit parameters, adjust QC thresholds, or preview outputs at any point.
        </div>

        {/* Workflow settings — moved to the TOP of the panel body. Old
            placement here is intentionally removed to avoid duplication. */}

        {/* After-run report — inline tabbed view replacing the modal stack */}
        {runState === 'completed' && (
          <AfterRunReport base={base} phases={phases} flash={flash}/>
        )}
      </div>

      <div className="panel-foot" data-tour="run-footer">
        <div className="run-primary">
          {runState !== 'running' && (
            <button className="btn primary" onClick={handleRun}>
              <Icon name="play" size={11}/>
              {runState === 'completed' ? 'Run again' : runState === 'failed' ? 'Restart' : 'Confirm and run workflow'}
            </button>
          )}
          {runState === 'running' && (
            <button className="btn" onClick={() => setRunState('idle')}
              style={{flex:1, height:38, fontSize:13.5, fontWeight:600, borderRadius:'var(--r-md)'}}>
              <Icon name="stop" size={10}/> Cancel run
            </button>
          )}
        </div>
        {/*
          Watcher attached / detached row — held back for this release.
          The detach/reconnect flow needs the live SSE work to land first;
          showing the affordance without it confuses things. Restore by
          uncommenting and re-wiring `watcherAttached` from the host.

          <div className="run-foot-meta" data-tour="watcher">
            <span className={'watcher-bar' + (watcherAttached ? '' : ' detached')}>
              <span className="dot"/>
              {watcherAttached ? 'Watcher attached · live SSE' : 'Watcher detached · job on AWS Batch'}
            </span>
            <button className="linkish" onClick={() => setWatcherAttached(a => !a)}>
              {watcherAttached ? 'Detach watcher' : 'Reconnect watcher'} <Icon name="external" size={10}/>
            </button>
          </div>
        */}
      </div>
      {toast && (
        <div className="wp-toast" key={toast.id}>{toast.msg}</div>
      )}
    </aside>
  );
}

window.WorkflowPanel = WorkflowPanel;

// ─────────────────────────────────────────────────────────────────
// AfterRunReport — inline tabbed report shown in the panel after run.
// Tabs: Findings · Outputs · Methods · Parameters · Software · Citations · QC audit
// Replaces the old findings-card + report/QC modal stack.
//
// Sub-component bodies (ReportFindings, ReportOutputs, ...) and the
// QcAuditPanel are defined in Modals.jsx and exposed on window.
// ─────────────────────────────────────────────────────────────────
function AfterRunReport({ base, phases, flash }) {
  const [tab, setTab] = useStateW('findings');

  // Per-scenario headline copy — mirrors the structure the Report modal used.
  // When this ships, the text should come from the actual run manifest.
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
        ['PASS variants',      '3,840,217'],
        ['Ts/Tv ratio',        '2.07'],
        ['ClinVar pathogenic', '142'],
        ['Runtime',            '34m 18s'],
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
        ['Ro5 violations',      '0'],
        ['hERG flag',           'moderate'],
        ['Runtime',             '8s'],
      ],
    },
    nfcore: {
      headline: '93.4% reads passed Q30. No adapter contamination.',
      bullets: [
        '2 accessions analyzed in parallel.',
        'Mean Phred score 36.2 across both runs.',
      ],
      table: [
        ['Reads passing Q30',      '93.4%'],
        ['Adapter contamination',  'none'],
        ['Mean Phred',             '36.2'],
        ['Runtime',                '6m 04s'],
      ],
    },
    drugscreen: {
      headline: '47 BBB-penetrant candidates after all QC gates.',
      bullets: [
        'Run B parameters retained (auto-loop tuned).',
        'QC pass-rate 99.2% — 53 compounds dropped.',
        'Mean predicted logBB 0.41 ± 0.18.',
      ],
      table: [
        ['Final candidates',     '47'],
        ['Mean predicted logBB', '0.41 ± 0.18'],
        ['QC pass-rate',         '99.2%'],
        ['Runtime',              '58m 04s'],
      ],
    },
  }[base.id] || {
    headline: 'Run complete.',
    bullets: ['Outputs are listed in the Outputs tab.'],
    table: [['Runtime', '—']],
  };

  // Flatten outputs across every completed step
  const outputs = [];
  phases.forEach(p => {
    (p.steps || []).forEach(s => {
      (s.outputs || []).forEach(o => {
        outputs.push({ phase: p.id + ' · ' + p.name, step: s.name, file: o.name, type: o.type });
      });
    });
  });

  const hasAnyQc = (base.phases || []).some(p => (p.qc || []).length > 0);

  // Tabs — legacy data-tour aliases (link-view-results / link-report / link-qc)
  // keep the older tour scripts pointing at the right element. New tutorials
  // use after-tab-<id> selectors.
  const tabs = [
    ['findings', 'Findings', 'link-report'],
    ['outputs',  'Outputs',  'link-view-results'],
    ['imrad',    'Methods',  null],
    ['params',   'Parameters', null],
    ['software', 'Software', null],
    ['cite',     'Citations', null],
  ];
  if (hasAnyQc) tabs.push(['qc', 'QC audit', 'link-qc']);

  return (
    <div data-tour="after-run" className="after-run-report">
      <div className="after-run-head" data-tour="after-run-header">
        <span className="kicker">After run</span>
        <span style={{flex:1}}/>
        <button className="linkish"
          style={{fontSize:11.5, display:'inline-flex', alignItems:'center', gap:5}}
          onClick={() => flash && flash('Building structured report — DOCX bundle will appear in Downloads')}
          title="Download a structured document covering every tab below">
          <Icon name="download" size={11}/> Download report
        </button>
      </div>
      <div className="after-run-tabs" data-tour="results-links">
        {tabs.map(([k, lbl, alias]) => (
          <button key={k}
            data-tour={alias || ('after-tab-' + k)}
            className={'after-run-tab' + (tab === k ? ' active' : '')}
            onClick={() => setTab(k)}>{lbl}</button>
        ))}
      </div>
      <div className="after-run-body" data-tour="after-run-body">
        {tab === 'findings' && (
          <div data-tour="findings-card">
            {window.ReportFindings && <window.ReportFindings findings={findings}/>}
          </div>
        )}
        {tab === 'outputs' && window.ReportOutputs && (
          <window.ReportOutputs outputs={outputs} scenario={base}
            onDownloadAll={() => flash && flash('Download bundle queued')}/>
        )}
        {tab === 'imrad'    && window.ReportMethodsImrad && <window.ReportMethodsImrad/>}
        {tab === 'params'   && window.ReportParams       && <window.ReportParams/>}
        {tab === 'software' && window.ReportSoftware     && <window.ReportSoftware/>}
        {tab === 'cite'     && window.ReportCitations    && <window.ReportCitations/>}
        {tab === 'qc'       && window.QcAuditPanel       && <window.QcAuditPanel scenario={base} phases={phases}/>}
      </div>
    </div>
  );
}

window.AfterRunReport = AfterRunReport;
