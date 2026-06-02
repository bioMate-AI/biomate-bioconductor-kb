// Surface 5 — eSig Modal (enrollment + signing)

const OtpInput = ({ state, onComplete }) => {
  const [vals, setVals] = React.useState(['', '', '', '', '', '']);
  const refs = React.useRef([]);

  const onChange = (i, v) => {
    if (!/^\d?$/.test(v)) return;
    const next = [...vals]; next[i] = v; setVals(next);
    if (v && i < 5) refs.current[i + 1]?.focus();
    if (next.every(x => x !== '')) onComplete && onComplete(next.join(''));
  };
  const onKey = (i, e) => {
    if (e.key === 'Backspace' && !vals[i] && i > 0) refs.current[i - 1]?.focus();
  };
  React.useEffect(() => { refs.current[0]?.focus(); }, []);

  return (
    <div className={`otp ${state === 'error' ? 'error' : ''} ${state === 'success' ? 'success' : ''}`}>
      {vals.map((v, i) => (
        <input
          key={i}
          ref={el => refs.current[i] = el}
          value={v}
          onChange={(e) => onChange(i, e.target.value)}
          onKeyDown={(e) => onKey(i, e)}
          disabled={state === 'checking' || state === 'success'}
          maxLength={1}
        />
      ))}
    </div>
  );
};

const EsigSignModal = ({ onClose, onToast, action = 'EXPORT_CRO_ORDER', meaning, target = 'WuXi AppTec · 10 compounds', onSigned }) => {
  const [state, setState] = React.useState('idle');
  const [countdown, setCountdown] = React.useState(23);
  const [attempts, setAttempts] = React.useState(0);

  const defaultMeaning = {
    EXPORT_CRO_ORDER: 'I approve the synthesis order for campaign cmp-a4f3b2c1 and confirm I have reviewed the compound selection.',
    INGEST_ASSAY: 'I confirm this assay data is accurate and authorize it to update the PBPK model for campaign cmp-a4f3b2c1.',
    GENERATE_IND: 'I approve the IND §2.6.1 package for campaign cmp-a4f3b2c1 and confirm the content is accurate for regulatory submission.',
  };
  const meaningText = meaning || defaultMeaning[action] || defaultMeaning.EXPORT_CRO_ORDER;

  React.useEffect(() => {
    if (state === 'success') return;
    const t = setInterval(() => setCountdown(c => c <= 0 ? 30 : c - 1), 1000);
    return () => clearInterval(t);
  }, [state]);

  const onComplete = (code) => {
    setState('checking');
    setTimeout(() => {
      if (code === '123456' || attempts > 0) {
        setState('success');
        setTimeout(() => {
          onToast && onToast(`Signed · ${action} recorded to audit trail`);
          onClose();
          onSigned && onSigned();
        }, 700);
      } else {
        setState('error');
        setAttempts(a => a + 1);
        setTimeout(() => setState('idle'), 1500);
      }
    }, 700);
  };

  return (
    <Modal
      title="Electronic Signature Required"
      sub="21 CFR Part 11 §11.200(a)(1)"
      onClose={onClose}
      footer={
        <>
          <button className="btn ghost" onClick={onClose}>Cancel</button>
          <div className="spacer"/>
          <button className="btn primary" disabled={state !== 'idle' && state !== 'error'}>
            {state === 'checking' ? <><span className="spinner"/> Verifying…</>
              : state === 'success' ? <><CroIcon name="check" size={13}/> Signed</>
              : <>Sign and Continue <CroIcon name="chevronRight" size={13}/></>}
          </button>
        </>
      }
    >
      <div style={{ border: '1px solid var(--border)', borderRadius: 6, padding: '10px 12px',
        background: 'var(--surface)', marginBottom: 14, fontSize: 13, display: 'flex', flexDirection: 'column', gap: 4 }}>
        <div><span style={{ color: 'var(--text-muted)' }}>Action:</span> <span className="mono">{action}</span></div>
        <div><span style={{ color: 'var(--text-muted)' }}>Campaign:</span> <span className="mono">cmp-a4f3b2c1</span></div>
        <div><span style={{ color: 'var(--text-muted)' }}>Target:</span> {target}</div>
      </div>

      <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 4, fontWeight: 500 }}>
        Meaning of signature
      </div>
      <div style={{ border: '1px solid var(--border)', borderRadius: 6, padding: '10px 12px',
        background: 'var(--reg-soft)', fontSize: 12.5, color: 'var(--reg-ink)', lineHeight: 1.5, marginBottom: 14 }}>
        {meaningText}
      </div>
      <div style={{ fontSize: 11, color: 'var(--text-dim)', fontStyle: 'italic', marginBottom: 10 }}>
        This meaning is permanently recorded in the audit trail.
      </div>

      <div style={{ fontSize: 12.5, color: 'var(--text-muted)', textAlign: 'center', marginTop: 18 }}>
        Enter your 6-digit authenticator code
      </div>
      <OtpInput state={state} onComplete={onComplete}/>
      <div className={`otp-meta ${state === 'error' ? 'err' : ''}`}>
        {state === 'error' ? 'Invalid code. Try again.' : `Code refreshes in ${countdown}s`}
      </div>

      <div style={{ fontSize: 11, color: 'var(--text-dim)', marginTop: 14, lineHeight: 1.5 }}>
        <CroIcon name="shield" size={11}/> This signature is uniquely linked to your identity and cannot be reused.
        The audit record will include your user ID, the meaning above, and a SHA-256 hash of this action's payload.
      </div>
    </Modal>
  );
};

const EsigEnrollModal = ({ onClose, onToast, onEnrolled }) => {
  const [state, setState] = React.useState('idle');

  const onComplete = (code) => {
    setState('checking');
    setTimeout(() => {
      setState('success');
      setTimeout(() => {
        onToast && onToast('Enrollment complete');
        onEnrolled ? onEnrolled() : onClose();
      }, 700);
    }, 700);
  };

  return (
    <Modal
      title="Set Up Electronic Signature"
      sub="21 CFR Part 11 §11.200 — one-time enrollment"
      onClose={onClose}
      footer={
        <>
          <button className="btn ghost" onClick={onClose}>Cancel</button>
          <div className="spacer"/>
          <button className="btn primary" disabled={state !== 'idle'}>
            {state === 'checking' ? <><span className="spinner"/> Verifying…</>
              : state === 'success' ? <><CroIcon name="check" size={13}/> Enrolled</>
              : <>Verify and Enable</>}
          </button>
        </>
      }
    >
      <div style={{ fontSize: 12.5, color: 'var(--text-muted)', lineHeight: 1.55, marginBottom: 14 }}>
        BioMate uses time-based one-time passwords (TOTP) for electronic signatures. These are cryptographically
        linked to your identity and cannot be reused, as required by 21 CFR Part 11 §11.200(a)(1).
      </div>

      <QrMock/>
      <div style={{ textAlign: 'center', fontSize: 11, color: 'var(--text-dim)', marginTop: 8, fontFamily: 'var(--font-mono)' }}>
        otpauth://totp/BioMate:alice@biotech.com?secret=J…
      </div>

      <ol style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: 16, paddingLeft: 22, lineHeight: 1.8 }}>
        <li>Install an authenticator app (Google Authenticator, Authy, 1Password).</li>
        <li>Scan the QR code above.</li>
        <li>Enter the 6-digit code from your app:</li>
      </ol>
      <OtpInput state={state} onComplete={onComplete}/>

      <div style={{ fontSize: 11, color: 'var(--warn-ink)', background: 'var(--warn-soft)',
        padding: '8px 10px', borderRadius: 4, marginTop: 12, lineHeight: 1.5 }}>
        ⚠ If you lose access to your authenticator, contact your system administrator to reset enrollment.
      </div>
    </Modal>
  );
};

window.EsigSignModal = EsigSignModal;
window.EsigEnrollModal = EsigEnrollModal;
