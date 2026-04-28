// Surface 7 — Campaign Creation Wizard

const CampaignWizard = ({ onDone, onToast }) => {
  const [step, setStep] = React.useState(1);
  const [id, setId] = React.useState('cmp-' + Math.random().toString(16).slice(2, 10));
  const [mol, setMol] = React.useState('');
  const [target, setTarget] = React.useState('');
  const [indication, setIndication] = React.useState('');
  const [objective, setObjective] = React.useState('balance');
  const [parsed, setParsed] = React.useState(null);
  const [validationProgress, setValidationProgress] = React.useState(0);

  React.useEffect(() => {
    if (step !== 3) return;
    const t = setInterval(() => setValidationProgress(p => Math.min(100, p + 10)), 300);
    return () => clearInterval(t);
  }, [step]);

  const simulateUpload = () => {
    setParsed({ n: 282, invalid: 0 });
  };

  const step1Ok = mol.trim() && target.trim() && indication.trim();

  return (
    <div>
      <div className="section-hd">
        <h2 className="h2">New Drug Discovery Campaign</h2>
        <div style={{ flex: 1 }}/>
        <span className="steps-indicator">Step {step}/3</span>
      </div>

      {step === 1 && (
        <div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <div className="field">
              <label>Campaign ID</label>
              <div className="suffix">
                <input value={id} onChange={(e) => setId(e.target.value)} />
                <span className="label">auto ✓</span>
              </div>
            </div>
            <div className="field">
              <label>Compound name</label>
              <input value={mol} onChange={(e) => setMol(e.target.value)} placeholder="e.g. BMT-4451"/>
            </div>
            <div className="field">
              <label>Target</label>
              <input value={target} onChange={(e) => setTarget(e.target.value)} placeholder="e.g. EGFR L858R"/>
            </div>
            <div className="field">
              <label>Indication</label>
              <input value={indication} onChange={(e) => setIndication(e.target.value)} placeholder="e.g. NSCLC"/>
            </div>
          </div>

          <div className="field">
            <label>Objective</label>
            <div className="radios">
              {[
                { k: 'potency',  l: 'Maximize potency', d: 'Weight IC50 ~0.6; ADMET ~0.2; novelty ~0.2' },
                { k: 'admet',    l: 'Optimize ADMET profile', d: 'Weight IC50 ~0.3; ADMET ~0.5; novelty ~0.2' },
                { k: 'balance',  l: 'Balance potency + ADMET', d: 'Even weighting across all three objectives' },
              ].map(o => (
                <label key={o.k} className={objective === o.k ? 'checked' : ''}>
                  <input type="radio" checked={objective === o.k} onChange={() => setObjective(o.k)}/>
                  <span style={{ flex: 1 }}>
                    <div style={{ fontWeight: 500 }}>{o.l}</div>
                    <div style={{ fontSize: 11.5, color: 'var(--text-dim)', marginTop: 2 }}>{o.d}</div>
                  </span>
                </label>
              ))}
            </div>
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 18 }}>
            <button className="btn ghost" onClick={onDone}>Cancel</button>
            <button className="btn primary" disabled={!step1Ok} onClick={() => setStep(2)}>
              Next <CroIcon name="chevronRight" size={13}/>
            </button>
          </div>
        </div>
      )}

      {step === 2 && (
        <div>
          <div style={{ fontSize: 13.5, color: 'var(--text-muted)', marginBottom: 14 }}>
            Upload your initial compound set (SMILES format). This library will be used as the virtual library for auto-retrain proposals.
          </div>

          <div className={`dropzone ${parsed ? 'populated' : ''}`} onClick={simulateUpload}>
            {parsed ? (
              <>
                <div style={{ fontWeight: 600, marginBottom: 4 }}>
                  <CroIcon name="check" size={16}/> library-seed.csv parsed
                </div>
                <div style={{ fontSize: 12.5 }}>
                  {parsed.n} compounds parsed · {parsed.invalid} invalid SMILES
                </div>
              </>
            ) : (
              <>
                <div style={{ marginBottom: 6 }}><CroIcon name="upload" size={20}/></div>
                <div style={{ fontWeight: 500, color: 'var(--text)' }}>Drag and drop .csv, .smi, or .txt</div>
                <div style={{ marginTop: 4 }}>or <span className="linkish">browse files</span></div>
                <div style={{ fontSize: 11.5, marginTop: 8 }}>
                  Format: one SMILES per line, or CSV with SMILES in the first column.
                </div>
              </>
            )}
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 18 }}>
            <button className="btn" onClick={() => setStep(1)}>
              <CroIcon name="chevronLeft" size={13}/> Back
            </button>
            <button className="btn primary" disabled={!parsed} onClick={() => setStep(3)}>
              Next <CroIcon name="chevronRight" size={13}/>
            </button>
          </div>
        </div>
      )}

      {step === 3 && (
        <div>
          <div style={{
            border: '1px solid var(--border)', borderRadius: 8,
            padding: 14, background: 'var(--surface)', marginBottom: 14
          }}>
            {[
              ['Campaign ID', <span className="mono">{id}</span>],
              ['Compound', mol],
              ['Target', target],
              ['Indication', indication],
              ['Virtual library', `${parsed?.n || 0} compounds`],
              ['Auto-retrain', <span><Chip tone="run" pulse>Enabled</Chip> <span style={{ marginLeft: 6, color: 'var(--text-dim)', fontSize: 12 }}>check every 60 min</span></span>],
              ['21 CFR Part 11', <Chip tone="ok"><CroIcon name="check" size={11}/> Audit trail active</Chip>],
            ].map(([k, v], i) => (
              <div key={i} style={{
                display: 'flex', gap: 10,
                padding: '6px 0',
                borderBottom: i < 6 ? '1px dashed var(--border)' : 'none',
                fontSize: 13
              }}>
                <span style={{ width: 140, color: 'var(--text-muted)' }}>{k}</span>
                <span style={{ flex: 1 }}>{v}</span>
              </div>
            ))}
            <div style={{ display: 'flex', gap: 10, padding: '10px 0 4px', fontSize: 13 }}>
              <span style={{ width: 140, color: 'var(--text-muted)' }}>Model validation</span>
              <span style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8 }}>
                {validationProgress < 100 ? (
                  <>
                    <span style={{ color: 'var(--text-muted)' }}>Running…</span>
                    <div className="progress" style={{ maxWidth: 180 }}><div className="fill" style={{ width: `${validationProgress}%` }}/></div>
                    <span className="mono" style={{ fontSize: 11.5, color: 'var(--text-dim)' }}>{validationProgress}%</span>
                  </>
                ) : (
                  <Chip tone="ok"><CroIcon name="check" size={11}/> EMA criterion met</Chip>
                )}
              </span>
            </div>
          </div>

          <div style={{ fontSize: 12.5, color: 'var(--text-muted)', lineHeight: 1.6, marginBottom: 12 }}>
            Once launched, BioMate will: (1) run PBPK model validation against 31 reference drugs,
            (2) start the audit trail, (3) activate the auto-retrain loop, and
            (4) enable CRO order export and IND assembly.
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 18 }}>
            <button className="btn" onClick={() => setStep(2)}>
              <CroIcon name="chevronLeft" size={13}/> Back
            </button>
            <button className="btn primary" onClick={() => { onToast && onToast('Campaign launched'); onDone && onDone(); }}>
              Launch Campaign <CroIcon name="chevronRight" size={13}/>
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

window.CampaignWizard = CampaignWizard;
