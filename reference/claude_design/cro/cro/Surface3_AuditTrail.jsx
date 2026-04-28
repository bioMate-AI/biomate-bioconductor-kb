// Surface 3 — Audit Trail Viewer

const AuditRow = ({ rec, expanded, onToggle, tampered }) => {
  const klass = tampered ? 'tampered' : rec.kind === 'esig' ? 'esig' : rec.kind === 'system' ? 'system' : '';
  const WhoIcon = rec.kind === 'system' ? 'robot' : rec.kind === 'esig' ? 'signature' : 'user';
  return (
    <div className={`audit-row ${klass}`} onClick={onToggle}>
      <div className="r1">{rec.ts}</div>
      <div className="r2">
        <CroIcon name={WhoIcon} size={13}/>
        <span className="who">{rec.who}</span>
        <span className="action">{rec.action}</span>
        <span style={{ color: 'var(--text-dim)' }}>·</span>
        <span className="resource">{rec.resource}</span>
        {rec.detail && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>· {rec.detail}</span>}
      </div>
      {rec.meaning && <div className="meaning">"{rec.meaning}"</div>}
      <div className="r3">
        <span>payload: <span style={{ color: 'var(--text-muted)' }}>{expanded ? rec.payload : rec.payload.slice(0,8)+'…'}</span></span>
        <span>·</span>
        <span>hash: <span style={{ color: 'var(--text-muted)' }}>{expanded ? rec.hash : rec.hash.slice(0,8)+'…'}</span></span>
        <span className="arrow">←</span>
        <span className="prev">prev: {rec.prev === '0000000000000000' ? 'genesis' : (expanded ? rec.prev : rec.prev.slice(0,8)+'…')}</span>
        {rec.sig_id && <><span>·</span><span>sig: {rec.sig_id}</span></>}
      </div>
    </div>
  );
};

const AuditTrail = ({ tampered = false, empty = false }) => {
  const [expanded, setExpanded] = React.useState(null);
  const [userFilter, setUserFilter] = React.useState('all');
  const [actionFilter, setActionFilter] = React.useState('all');
  const [shown, setShown] = React.useState(10);

  if (empty) {
    return (
      <div>
        <div className="section-hd">
          <h2 className="h2">Audit Trail</h2>
          <div className="cite-row">
            <RegChip>21 CFR §11.10(e)</RegChip>
            <RegChip>SHA-256 hash chain</RegChip>
          </div>
        </div>
        <div className="empty">
          <div className="ic"><CroIcon name="shield" size={20}/></div>
          <div className="title">No audit records yet</div>
          <div className="text">
            Records are created automatically when you ingest assay data, export CRO orders,
            or generate proposals for this campaign.
          </div>
          <button className="btn primary">Ingest Assay Data</button>
        </div>
      </div>
    );
  }

  const filtered = AUDIT_RECORDS.filter(r =>
    (userFilter === 'all' || r.who === userFilter) &&
    (actionFilter === 'all' || r.action === actionFilter)
  );
  const visible = filtered.slice(0, shown);
  const tamperedId = tampered ? 6 : null;

  return (
    <div>
      <div className="section-hd">
        <h2 className="h2">Audit Trail</h2>
        <Chip tone={tampered ? 'err' : 'ok'}>
          {tampered ? <><CroIcon name="unlock" size={12}/> TAMPERED — record #{tamperedId}</> : <><CroIcon name="lock" size={12}/> Chain: VALID</>}
        </Chip>
        <div className="cite-row">
          <RegChip>21 CFR §11.10(e)</RegChip>
          <RegChip>SHA-256 hash chain</RegChip>
        </div>
      </div>

      <div className="meta-line">
        <span>Every regulated action is recorded immutably. Each record references the previous record's hash, forming a tamper-evident chain.</span>
      </div>

      <div className="filter-bar">
        <div className="select">
          <select value={userFilter} onChange={(e) => setUserFilter(e.target.value)}>
            {AUDIT_USERS.map(u => <option key={u} value={u}>{u === 'all' ? 'All users' : u}</option>)}
          </select>
        </div>
        <div className="select">
          <select value={actionFilter} onChange={(e) => setActionFilter(e.target.value)}>
            {AUDIT_ACTIONS.map(a => <option key={a} value={a}>{a === 'all' ? 'All actions' : a}</option>)}
          </select>
        </div>
        <div className="select">
          <select defaultValue="7d">
            <option value="24h">Last 24h</option>
            <option value="7d">Last 7 days</option>
            <option value="30d">Last 30 days</option>
            <option value="all">All time</option>
          </select>
        </div>
        <div className="spacer"/>
        <button className="btn sm"><CroIcon name="download" size={12}/> Export</button>
      </div>

      <div className="audit-list" data-tour="audit-list">
        {visible.map(rec => (
          <AuditRow
            key={rec.id}
            rec={rec}
            tampered={rec.id === tamperedId}
            expanded={expanded === rec.id}
            onToggle={() => setExpanded(expanded === rec.id ? null : rec.id)}
          />
        ))}
      </div>

      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 10, fontSize: 12.5, color: 'var(--text-dim)' }}>
        <span>Showing {visible.length} of {AUDIT_TOTAL} records</span>
        {visible.length < filtered.length && (
          <button className="btn sm" onClick={() => setShown(s => s + 10)}>Load 10 more</button>
        )}
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 14, paddingTop: 12, borderTop: '1px solid var(--border)' }}>
        <div style={{ flex: 1, fontSize: 12.5, color: 'var(--text-muted)' }}>
          {tampered
            ? <span style={{ color: 'var(--err)', fontWeight: 500 }}>⚠ Chain verification failed at record #{tamperedId}. Contact your administrator immediately.</span>
            : <>Chain: {AUDIT_TOTAL} records verified ✅ · Last verified: just now</>
          }
        </div>
        <button className="btn sm"><CroIcon name="search" size={12}/> Re-verify chain</button>
      </div>
    </div>
  );
};

window.AuditTrail = AuditTrail;
