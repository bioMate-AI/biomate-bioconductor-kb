// Sign & Freeze full-screen overlay + Audit Trail overlay + Empty state

// ── Sign & Freeze ───────────────────────────────────────────
const IndSignOverlay = ({ doc, onCancel, onSigned }) => {
  const [step, setStep] = React.useState('sign');  // 'sign' | 'success'
  const [title, setTitle] = React.useState('Director, Computational Pharmacology');
  const [creds, setCreds] = React.useState('PhD Pharmacology · 10 years IND experience');
  const [scope, setScope] = React.useState('§2.6.1–§2.6.6 nonclinical pharmacology');
  const [totp, setTotp] = React.useState(['', '', '', '', '', '']);
  const [timer, setTimer] = React.useState(22);
  const inputRefs = React.useRef([]);

  React.useEffect(() => {
    if (step !== 'sign') return;
    const t = setInterval(() => setTimer(s => s > 0 ? s - 1 : 30), 1000);
    return () => clearInterval(t);
  }, [step]);

  const allFilled = totp.every(t => t.length === 1);

  const setDigit = (i, v) => {
    const next = [...totp];
    next[i] = v.slice(-1);
    setTotp(next);
    if (v && i < 5) inputRefs.current[i + 1]?.focus();
  };

  const doSign = () => {
    if (!allFilled) return;
    setStep('success');
    setTimeout(() => onSigned && onSigned({ title, creds, scope }), 100);
  };

  if (step === 'success') {
    return (
      <div className="sign-overlay" data-tour="ind-sign-success">
        <div className="sign-card">
          <div className="sign-success">
            <div className="check"><CroIcon name="check" size={28} stroke={3}/></div>
            <h3>Signed</h3>
            <div className="summary">
              Document frozen · SHA-256 locked · version v2<br/>
              Signed by: Dr. Jane Smith<br/>
              Sig ID: 3f82a1cc…  ·  2026-05-04 18:44 UTC
            </div>
            <div className="actions">
              <button className="ind-btn primary">
                <CroIcon name="download" size={13}/> Download DOCX
              </button>
              <button className="ind-btn">
                <CroIcon name="download" size={13}/> Download Audit Trail PDF
              </button>
              <button className="ind-btn" onClick={onCancel}>Close</button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="sign-overlay" data-tour="ind-sign-overlay" onClick={onCancel}>
      <div className="sign-card" onClick={(e) => e.stopPropagation()}>
        <div className="sign-head">
          <h2>Electronic Signature</h2>
          <div className="sub">21 CFR Part 11 §11.200</div>
        </div>
        <div className="sign-body">
          <div className="sign-section">
            <h3>Document</h3>
            <div className="sign-doc-card">
              <b>BM-0042</b> · §2.6.1–§2.6.6 · v{doc.version} · {doc.characters.toLocaleString()} characters
              <br/>
              <span className="mono">SHA-256: {doc.shaPrefix}e8b4f72a…</span>
            </div>
          </div>

          <div className="sign-section">
            <h3>Meaning of this signature</h3>
            <div className="sign-meaning">
              I have reviewed and approve the <b>BM-0042</b> IND §2.6.1–§2.6.6
              nonclinical written summary package for submission to FDA/EMA/NMPA/PMDA.
              This document represents my scientific judgment and was generated using
              validated computational methods per FDA/EMA AI Guidance (January 2026).
            </div>
            <div className="note">This statement is permanently recorded and cannot be changed.</div>
          </div>

          <div className="sign-section">
            <h3>Reviewer credentials <span style={{textTransform: 'none', fontWeight: 400, color: 'var(--ind-text-dim)'}}>(recommended for IND actions)</span></h3>
            <div className="sign-creds">
              <div className="ind-field">
                <label>Title / Role</label>
                <input value={title} onChange={(e) => setTitle(e.target.value)}/>
              </div>
              <div className="ind-field">
                <label>Credentials</label>
                <input value={creds} onChange={(e) => setCreds(e.target.value)}/>
              </div>
              <div className="ind-field full">
                <label>Review scope</label>
                <input value={scope} onChange={(e) => setScope(e.target.value)}/>
              </div>
            </div>
            <div className="note">These are recorded in the frozen document.</div>
          </div>

          <div className="sign-section">
            <h3>6-digit authenticator code</h3>
            <div className="sign-totp">
              <div className="totp-input">
                {totp.map((d, i) => (
                  <input
                    key={i}
                    ref={el => inputRefs.current[i] = el}
                    inputMode="numeric"
                    maxLength={1}
                    value={d}
                    onChange={(e) => setDigit(i, e.target.value.replace(/\D/g, ''))}
                    onKeyDown={(e) => {
                      if (e.key === 'Backspace' && !d && i > 0) inputRefs.current[i-1]?.focus();
                    }}
                  />
                ))}
              </div>
              <div className="totp-timer">refreshes in {timer}s</div>
            </div>
          </div>
        </div>
        <div className="sign-foot">
          <button className="ind-btn" onClick={onCancel}>Cancel</button>
          <button className="ind-btn primary" onClick={doSign} disabled={!allFilled}>
            Sign and freeze →
          </button>
        </div>
      </div>
    </div>
  );
};

// ── Audit Trail Overlay ────────────────────────────────────
const IndAuditOverlay = ({ audit, onClose, onJumpTo }) => {
  const [dismissingId, setDismissingId] = React.useState(null);
  const [reason, setReason] = React.useState(null);
  const [filter, setFilter] = React.useState('all');

  const filtered = filter === 'all'
    ? audit.findings
    : audit.findings.filter(f => f.severity === filter);

  const sevSummary = ['CRITICAL', 'MAJOR', 'MINOR', 'INFO'].map(sev => ({
    sev,
    count: audit.findings.filter(f => f.severity === sev && !f.addressed).length,
  }));

  return (
    <div className="ind-audit-overlay" data-tour="ind-audit-overlay">
      <header className="ind-audit-head">
        <h3>Regulatory Audit</h3>
        <button className="ind-btn sm" onClick={onClose}>
          <CroIcon name="x" size={12}/> Close
        </button>
      </header>
      <div className="ind-audit-meta">
        {sevSummary.map(s => (
          <span key={s.sev} className={`audit-chip ${s.sev.toLowerCase()}`} style={{opacity: s.count ? 1 : 0.5}}>
            {s.count > 0 ? '⚠ ' : '○ '}{s.count} {s.sev}
          </span>
        ))}
        <span style={{flex: 1}}/>
        <select value={filter} onChange={(e) => setFilter(e.target.value)}
          style={{padding: '3px 6px', fontSize: 11.5, borderRadius: 4,
            border: '1px solid var(--ind-border)', fontFamily: 'inherit', background: 'white'}}>
          <option value="all">All findings</option>
          <option value="CRITICAL">CRITICAL</option>
          <option value="MAJOR">MAJOR</option>
          <option value="MINOR">MINOR</option>
          <option value="INFO">INFO</option>
        </select>
      </div>
      <div className="ind-audit-list">
        {filtered.map((f, i) => (
          <div key={i} className={`ind-audit-finding ${f.severity.toLowerCase()}${f.addressed ? ' addressed' : ''}`}>
            <div className="ind-audit-finding-head">
              <span className="sec">{f.section}</span>
              <span className={`audit-chip ${f.severity.toLowerCase()}`}>{f.severity}</span>
              {f.addressed && <span style={{fontSize: 11, color: 'var(--ind-ok)', fontWeight: 600}}>✓ Addressed</span>}
            </div>
            <div className="title">{f.title}</div>
            <div className="desc">{f.desc}</div>
            <div className="acts">
              <button className="ind-link" onClick={() => onJumpTo(f.section)}>
                → Jump to section
              </button>
              {!f.addressed && (
                <button className="ind-link" onClick={() => { setDismissingId(i); setReason(null); }}>
                  Dismiss
                </button>
              )}
            </div>
            {dismissingId === i && (
              <div className="ind-dismiss-picker" data-tour="ind-dismiss-picker">
                <h4>Dismiss this finding because…</h4>
                {[
                  ['na',     'Not applicable to this product (e.g. topical → no hERG required)'],
                  ['done',   'Already addressed elsewhere in the document'],
                  ['accept', 'Acceptable risk — documented in Discussion'],
                  ['disag',  'Disagree with the rule (regulatory judgment)'],
                ].map(([k, lbl]) => (
                  <label key={k}>
                    <input type="radio" name="dismiss" value={k}
                      checked={reason === k} onChange={() => setReason(k)}/>
                    {lbl}
                  </label>
                ))}
                <div style={{display: 'flex', gap: 6, marginTop: 10}}>
                  <button className="ind-btn sm" onClick={() => setDismissingId(null)}>Cancel</button>
                  <button className="ind-btn sm primary" disabled={!reason}
                    onClick={() => setDismissingId(null)}>
                    Dismiss with reason
                  </button>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
      <footer className="ind-audit-foot">
        <span>Chain integrity: <b style={{color: 'var(--ind-ok)'}}>✓ Valid</b> ({audit.chainRecords} records · last verified {audit.lastVerified})</span>
        <span style={{flex: 1}}/>
        <button className="ind-link">View full audit log →</button>
        <button className="ind-btn sm">
          <CroIcon name="download" size={12}/> Export PDF
        </button>
      </footer>
    </div>
  );
};

// ── Empty / onboarding ────────────────────────────────────
const IndEmptyState = ({ onStart, onPickReference }) => (
  <div className="ind-empty" data-tour="ind-empty">
    <div className="ind-empty-card">
      <h1>BioMate IND Report</h1>
      <p className="lede">
        Generate a complete ICH M4 CTD Module 2.6 nonclinical written summary
        in under 10 minutes.
      </p>
      <div className="ind-empty-bullets">
        <div className="b"><span className="check">✓</span>§2.6.1–§2.6.6 · FDA · EMA · NMPA · PMDA</div>
        <div className="b"><span className="check">✓</span>ADMET · PBPK · Lead ranking · Validated models</div>
        <div className="b"><span className="check">✓</span>21 CFR Part 11 eSig · SHA-256 audit trail · DOCX</div>
      </div>
      <button className="ind-empty-start" onClick={onStart}>
        Start with a compound <CroIcon name="chevronRight" size={14}/>
      </button>

      <div className="ind-empty-divider"><span>Or try a reference compound:</span></div>

      <div className="ind-ref-row">
        {window.IND_REFERENCE_COMPOUNDS.map(c => (
          <button key={c.id} className="ind-ref-chip" onClick={() => onPickReference(c.id)}>
            <span className="nm">{c.name}</span>
            <span className="tag">{c.tag}</span>
            <span className="desc">{c.desc}</span>
          </button>
        ))}
      </div>
    </div>
  </div>
);

Object.assign(window, { IndSignOverlay, IndAuditOverlay, IndEmptyState });
