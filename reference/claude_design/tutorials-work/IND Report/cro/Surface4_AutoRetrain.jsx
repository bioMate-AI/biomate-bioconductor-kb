// Surface 4 — Auto-Retrain Loop + Proposal Viewer

const ProposalRow = ({ p, expanded, onToggle }) => {
  const wide = p.ci_hi - p.ci_lo > 0.2;
  return (
    <>
      <tr onClick={onToggle} style={{ cursor: 'pointer' }} className={p.ad === 'out_of_domain' ? 'dim' : ''}>
        <td className="num" style={{ textAlign: 'left', paddingLeft: 10 }}>{p.rank}</td>
        <td className="mono" title={p.smiles}>
          {expanded ? p.smiles : (p.smiles.length > 25 ? p.smiles.slice(0, 25) + '…' : p.smiles)}
        </td>
        <td><ScoreBar score={p.score}/></td>
        <td className="mono" style={{ color: wide ? 'var(--warn-ink)' : 'var(--text-muted)' }}>
          {p.ci_lo.toFixed(2)}–{p.ci_hi.toFixed(2)}
        </td>
        <td><AdCell status={p.ad}/></td>
      </tr>
    </>
  );
};

const AutoRetrain = ({ loopRunning: externalLoop, hasLibrary = true, validationFailed = false, onGatedAction, onToast }) => {
  const [loopRunning, setLoopRunning] = React.useState(externalLoop !== undefined ? externalLoop : true);
  React.useEffect(() => { if (externalLoop !== undefined) setLoopRunning(externalLoop); }, [externalLoop]);

  const [secondsLeft, setSecondsLeft] = React.useState(43);
  const [expanded, setExpanded] = React.useState(null);
  const [showHistory, setShowHistory] = React.useState(false);
  const [manualRunning, setManualRunning] = React.useState(false);

  React.useEffect(() => {
    if (!loopRunning) return;
    const t = setInterval(() => setSecondsLeft(s => s <= 0 ? 60 : s - 1), 1000);
    return () => clearInterval(t);
  }, [loopRunning]);

  const triggerManual = () => {
    setManualRunning(true);
    setTimeout(() => { setManualRunning(false); onToast && onToast('Retrain complete — proposals refreshed'); }, 2200);
  };

  const copySmiles = () => {
    const text = PROPOSALS.map(p => p.smiles).join('\n');
    navigator.clipboard && navigator.clipboard.writeText(text);
    onToast && onToast(`Copied ${PROPOSALS.length} SMILES`);
  };

  if (!hasLibrary) {
    return (
      <div>
        <div className="section-hd">
          <h2 className="h2">Auto-Retrain Loop</h2>
          <div className="cite-row">
            <RegChip>DMTA · Round-based retraining</RegChip>
          </div>
        </div>
        <div className="empty">
          <div className="ic"><CroIcon name="beaker" size={20}/></div>
          <div className="title">No virtual library yet</div>
          <div className="text">Upload a library of candidate compounds (.csv or .smi) to enable auto-retrain proposals.</div>
          <button className="btn primary"><CroIcon name="upload" size={13}/> Upload Virtual Library</button>
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="section-hd">
        <h2 className="h2">Auto-Retrain Loop</h2>
        <div className="cite-row">
          <RegChip>DMTA · Round-based retraining</RegChip>
        </div>
      </div>

      <div className="info-strip" data-tour="loop-strip">
        <Chip tone={loopRunning ? 'run' : 'default'} pulse={loopRunning}>
          {loopRunning ? 'RUNNING' : 'STOPPED'}
        </Chip>
        {loopRunning ? (
          <span className="metric"><span className="k">Next check</span><span className="v">in {secondsLeft}s</span></span>
        ) : (
          <span className="metric"><span className="k">Stopped at</span><span className="v">2026-04-20 16:12 UTC</span></span>
        )}
        <span className="metric"><span className="k">Last retrain</span><span className="v">14:45 UTC</span></span>
        <span className="metric" style={{ fontSize: 12 }}>
          <span style={{ color: 'var(--text-dim)' }}>triggered by</span>
          <span style={{ color: 'var(--text-muted)' }}>new assay data</span>
        </span>
        <div className="spacer"/>
        {loopRunning
          ? <button className="btn sm" onClick={() => setLoopRunning(false)}><CroIcon name="stop" size={11}/> Stop</button>
          : <button className="btn sm primary" onClick={() => setLoopRunning(true)}><CroIcon name="play" size={11}/> Resume</button>
        }
        <button className="btn sm" onClick={triggerManual} disabled={manualRunning}>
          {manualRunning ? <><span className="spinner"/> Retraining…</> : <><CroIcon name="refresh" size={11}/> Trigger now</>}
        </button>
      </div>

      {!loopRunning && (
        <div style={{ marginTop: 10, fontSize: 12, color: 'var(--text-muted)', fontStyle: 'italic' }}>
          <CroIcon name="info" size={11}/> Loop is paused. New assay data will queue but will not retrain the model until you click Resume.
        </div>
      )}

      {validationFailed && (
        <div style={{ marginTop: 14 }}>
          <Callout
            tone="warn"
            icon={<CroIcon name="warn" size={16}/>}
            title="Proposals blocked — EMA validation failed"
            rows={[
              <>The PBPK model currently does not meet the EMA 2-fold criterion. Re-run model validation before proposing a new round to the CRO.</>,
            ]}
          />
        </div>
      )}

      <div style={{ marginTop: 18 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 10 }}>
          <div style={{ fontWeight: 600, fontSize: 13.5 }}>Latest Proposal — Round 3</div>
          <div style={{ fontSize: 12, color: 'var(--text-dim)' }}>
            2026-04-20 14:45 UTC · 10 compounds · triggered by auto_retrain
          </div>
        </div>

        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th style={{ width: 40 }}>#</th>
                <th>SMILES</th>
                <th style={{ width: 180 }}>Score</th>
                <th style={{ width: 110 }}>CI 95%</th>
                <th style={{ width: 110 }}>AD</th>
              </tr>
            </thead>
            <tbody>
              {PROPOSALS.map(p => (
                <ProposalRow
                  key={p.rank} p={p}
                  expanded={expanded === p.rank}
                  onToggle={() => setExpanded(expanded === p.rank ? null : p.rank)}
                />
              ))}
            </tbody>
          </table>
        </div>

        <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
          <button className="btn sm" onClick={copySmiles}><CroIcon name="copy" size={12}/> Copy SMILES</button>
          <button className="btn sm"><CroIcon name="download" size={12}/> Download CSV</button>
          <button
            className="btn sm primary"
            disabled={validationFailed}
            onClick={() => onGatedAction && onGatedAction('EXPORT_CRO_ORDER')}
            title={validationFailed ? 'Blocked — EMA validation must pass' : ''}
          >
            <CroIcon name="external" size={12}/> Export to CRO
          </button>
        </div>
      </div>

      <div style={{ marginTop: 18 }}>
        <Collapsible title="Proposal History" sub={`${PROPOSAL_HISTORY.length} rounds`}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {PROPOSAL_HISTORY.map(h => (
              <div key={h.round} style={{
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '10px 12px', border: '1px solid var(--border)', borderRadius: 6,
                fontSize: 13, cursor: 'pointer'
              }}>
                <span style={{ fontWeight: 600 }}>Round {h.round}</span>
                <span style={{ color: 'var(--text-dim)', fontFamily: 'var(--font-mono)', fontSize: 12 }}>{h.ts}</span>
                <span style={{ color: 'var(--text-muted)' }}>· {h.n} proposals</span>
                <span style={{ color: 'var(--text-dim)', fontSize: 12 }}>·</span>
                <Chip tone={h.trigger === 'auto_retrain' ? 'run' : 'default'}>{h.trigger}</Chip>
                <div style={{ flex: 1 }}/>
                <button className="btn xs">View</button>
              </div>
            ))}
          </div>
        </Collapsible>

        <Collapsible title="Virtual Library" sub="282 compounds cached">
          <div style={{ fontSize: 13, color: 'var(--text-muted)', marginBottom: 10 }}>
            Saved 2026-04-20 08:12 UTC · library hash <span className="mono">e1b4…88c9</span>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 12 }}>
            <div className="field">
              <label>Proposals per round</label>
              <input type="number" defaultValue={10} min={1} max={50}/>
            </div>
            <div className="field">
              <label>Diversity weight · 0.2</label>
              <input type="range" min="0" max="1" step="0.05" defaultValue="0.2"/>
              <div className="hint">Higher = more diverse proposals</div>
            </div>
          </div>
          <button className="btn sm"><CroIcon name="upload" size={12}/> Replace virtual library</button>
        </Collapsible>
      </div>
    </div>
  );
};

window.AutoRetrain = AutoRetrain;
