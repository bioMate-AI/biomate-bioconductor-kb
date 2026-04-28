// Surface 1 — Campaign Dashboard (enhanced)

const DmtaStepper = () => {
  const nodes = [
    { key: 'design', label: 'Design', ...DMTA_STATE.design },
    { key: 'make',   label: 'Make',   ...DMTA_STATE.make },
    { key: 'test',   label: 'Test',   ...DMTA_STATE.test },
    { key: 'analyse',label: 'Analyse',...DMTA_STATE.analyse },
  ];
  return (
    <div className="dmta">
      {nodes.map((n, i) => (
        <React.Fragment key={n.key}>
          <div className={`node ${n.status === 'done' ? 'done' : n.status === 'active' ? 'active' : ''}`}>
            <div className="dot">
              {n.status === 'done' ? <CroIcon name="check" size={14}/>
                : n.status === 'active' ? <CroIcon name="dot" size={10}/>
                : <span style={{ width: 8, height: 8, borderRadius: 999, border: '1.5px solid currentColor' }}/>
              }
            </div>
            <div className="label">{n.label}</div>
            <div className="sublabel">{n.status === 'done' ? 'completed' : n.status === 'active' ? 'running' : 'pending'}</div>
          </div>
          {i < nodes.length - 1 && <div className={`line ${n.status === 'done' ? 'done' : ''}`}/>}
        </React.Fragment>
      ))}
    </div>
  );
};

const CampaignDashboard = ({ onToast, onNav, onGatedAction, validationFailed = false }) => {
  const [showAll, setShowAll] = React.useState(false);
  const visible = showAll ? TOP_COMPOUNDS : TOP_COMPOUNDS.slice(0, 10);

  return (
    <div>
      <div className="section-hd" data-tour="dashboard-header">
        <h2 className="h2">Campaign: <span className="mono" style={{ fontWeight: 500 }}>{MOCK_CAMPAIGN.campaign_id}</span></h2>
        <Chip tone="ok" pulse>ACTIVE</Chip>
        <div className="cite-row">
          <RegChip>{MOCK_CAMPAIGN.target}</RegChip>
          <RegChip>{MOCK_CAMPAIGN.indication}</RegChip>
        </div>
      </div>

      <div className="meta-line">
        <span>Round {MOCK_CAMPAIGN.round}</span>
        <span className="sep">·</span>
        <span>{MOCK_CAMPAIGN.total_compounds} compounds ranked</span>
        <span className="sep">·</span>
        <span>Last update: {MOCK_CAMPAIGN.last_updated}</span>
        <div style={{ flex: 1 }}/>
        <button className="btn sm"><CroIcon name="refresh" size={12}/> Refresh</button>
      </div>

      <div style={{
        border: '1px solid var(--border)', borderRadius: 8,
        background: 'var(--surface)', padding: '6px 14px',
        marginBottom: 18
      }} data-tour="dmta-stepper">
        <div style={{ fontSize: 11, textTransform: 'uppercase', letterSpacing: '.05em',
          color: 'var(--text-dim)', fontWeight: 600, marginTop: 8 }}>
          DMTA Loop Progress
        </div>
        <DmtaStepper />
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
        <div style={{ fontWeight: 600, fontSize: 13.5 }}>Top Compounds</div>
        <div style={{ fontSize: 12, color: 'var(--text-dim)' }}>
          Showing {visible.length} of {MOCK_CAMPAIGN.total_compounds}
        </div>
        <div style={{ flex: 1 }}/>
        <button className="linkish" onClick={() => setShowAll(!showAll)}>
          {showAll ? 'Show top 10' : `See all ${MOCK_CAMPAIGN.total_compounds} →`}
        </button>
      </div>

      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr>
              <th style={{ width: 40 }}>#</th>
              <th>Compound ID</th>
              <th style={{ width: 200 }}>Score</th>
              <th style={{ width: 140 }}>AD Status</th>
              <th style={{ width: 130 }}>Round proposed</th>
            </tr>
          </thead>
          <tbody>
            {visible.map(c => (
              <tr key={c.id} className={c.ad === 'out_of_domain' ? 'dim' : ''}>
                <td className="num" style={{ textAlign: 'left', paddingLeft: 10 }}>{c.rank}</td>
                <td className="mono">{c.id}</td>
                <td><ScoreBar score={c.score}/></td>
                <td><AdCell status={c.ad}/></td>
                <td className="mono" style={{ color: 'var(--text-muted)' }}>Round {c.round}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div style={{ display: 'flex', gap: 8, marginTop: 14 }} data-tour="dashboard-actions">
        <button className="btn" onClick={() => onGatedAction && onGatedAction('INGEST_ASSAY')}>
          <CroIcon name="upload" size={13}/> Ingest New Assay Results
        </button>
        <button
          className="btn primary"
          disabled={validationFailed}
          onClick={() => onGatedAction && onGatedAction('EXPORT_CRO_ORDER')}
          title={validationFailed ? 'Blocked — EMA validation must pass before CRO export' : ''}
        >
          <CroIcon name="external" size={13}/> Export CRO Order
        </button>
        {validationFailed && (
          <span style={{ fontSize: 11.5, color: 'var(--err)', alignSelf: 'center' }}>
            <CroIcon name="warn" size={11}/> blocked by EMA validation failure
          </span>
        )}
      </div>
    </div>
  );
};

window.CampaignDashboard = CampaignDashboard;
