// Surface 6 — IND Section Assembly

const IndAssembly = ({ pandocAvailable = true, generated = true, validationFailed = false, onGatedAction, onToast }) => {
  const [mol, setMol] = React.useState('BMT-4451');
  const [target, setTarget] = React.useState('EGFR L858R');
  const [indication, setIndication] = React.useState('NSCLC — 2nd line');
  const [sponsor, setSponsor] = React.useState('BioMate Technologies');
  const [generating, setGenerating] = React.useState(false);
  const [hasOutput, setHasOutput] = React.useState(generated);
  const [confirming, setConfirming] = React.useState(false);

  // Sync `generated` prop changes so Tweaks Fresh/Generated actually flip state
  React.useEffect(() => { setHasOutput(generated); }, [generated]);

  const canGenerate = mol.trim() && target.trim() && indication.trim() && !generating && !validationFailed;

  const generate = () => {
    if (onGatedAction) {
      // run gated flow — on success call actualGenerate
      onGatedAction('GENERATE_IND', () => actualGenerate());
      return;
    }
    actualGenerate();
  };

  const actualGenerate = () => {
    setGenerating(true);
    setTimeout(() => {
      setGenerating(false);
      setHasOutput(true);
      onToast && onToast('IND package generated');
    }, 1800);
  };

  return (
    <div>
      <div className="section-hd">
        <h2 className="h2">IND Section Assembly</h2>
        <div className="cite-row">
          <RegChip variant="indigo">ICH M4 — CTD §2.6.1</RegChip>
          <RegChip>Nonclinical Overview — Pharmacology</RegChip>
        </div>
      </div>

      <Collapsible title="Campaign Details" sub="required" defaultOpen>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <div className="field">
            <label>Investigational compound</label>
            <input value={mol} onChange={(e) => setMol(e.target.value)} />
          </div>
          <div className="field">
            <label>Biological target</label>
            <input value={target} onChange={(e) => setTarget(e.target.value)} />
          </div>
          <div className="field">
            <label>Therapeutic indication</label>
            <input value={indication} onChange={(e) => setIndication(e.target.value)} />
          </div>
          <div className="field">
            <label>Sponsor organization</label>
            <input value={sponsor} onChange={(e) => setSponsor(e.target.value)} />
          </div>
        </div>
      </Collapsible>

      <Collapsible title="Contents Preview" sub="6 sections" defaultOpen>
        <div className="contents-preview">
          {IND_SECTIONS.map(s => (
            <div key={s.id} className="cp-row">
              <div className={`ic ${s.status}`}>
                {s.status === 'ok' && <CroIcon name="checkCircle" size={16}/>}
                {s.status === 'warn' && <CroIcon name="warn" size={16}/>}
                {s.status === 'err' && <CroIcon name="xCircle" size={16}/>}
              </div>
              <span className="num">{s.id}</span>
              <span className="name">{s.title}</span>
              <span className="meta">({s.meta})</span>
            </div>
          ))}
        </div>
      </Collapsible>

      {validationFailed && (
        <div style={{ marginTop: 14 }}>
          <Callout
            tone="err"
            icon={<CroIcon name="xCircle" size={16}/>}
            title="IND assembly blocked — PBPK validation failed"
            rows={[
              <>Section §2.6.1.2 (PBPK Model Qualification) requires a passing EMA 2-fold criterion report. Go to the <b>Validation</b> tab and re-run after model updates.</>,
            ]}
          />
        </div>
      )}

      {!hasOutput && !generating && !validationFailed && (
        <div style={{
          marginTop: 14, padding: '12px 14px',
          border: '1px dashed var(--border)', borderRadius: 6,
          background: 'var(--surface)', fontSize: 12.5, color: 'var(--text-muted)'
        }}>
          <b style={{ color: 'var(--text)' }}>No package generated yet.</b> Fill in the compound details above
          and click <b>Generate IND Package</b> below. Generation typically takes 20–40s.
        </div>
      )}

      {!pandocAvailable && (
        <div style={{ marginTop: 14 }}>
          <Callout
            tone="warn"
            icon={<CroIcon name="warn" size={16}/>}
            title="Pandoc not found — DOCX output unavailable"
            rows={[
              <>Markdown report will still be generated. Install pandoc (<span className="mono">brew install pandoc</span>) to enable DOCX.</>,
            ]}
          />
        </div>
      )}

      <div style={{ marginTop: 16, display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 12 }} data-tour="ind-generate">
        <button
          className="btn primary"
          style={{ height: 40, fontSize: 13.5, fontWeight: 600, padding: '0 20px' }}
          disabled={!canGenerate}
          onClick={generate}
        >
          {generating ? <><span className="spinner"/> Generating…</> : <>Generate IND Package <CroIcon name="chevronRight" size={13}/></>}
        </button>
      </div>

      {generating && (
        <div style={{ marginTop: 14 }}>
          <div className="progress"><div className="fill" style={{ width: '60%' }}/></div>
          <div style={{ textAlign: 'center', fontSize: 12, color: 'var(--text-dim)', marginTop: 6 }}>
            Assembling sections · rendering tables · validating citations
          </div>
        </div>
      )}

      {hasOutput && !generating && (
        <div style={{ marginTop: 20, paddingTop: 16, borderTop: '1px solid var(--border)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
            <div style={{ fontWeight: 600, fontSize: 13 }}>Last generated</div>
            <div style={{ fontSize: 12, color: 'var(--text-dim)', fontFamily: 'var(--font-mono)' }}>
              2026-04-20 14:58 UTC · Round 3
            </div>
          </div>

          <div className="download-row">
            <span className="ft">MD</span>
            <span className="fname">cmp-a4f3b2c1_CTD_2.6.1.md</span>
            <span className="sz">42 KB</span>
            <button className="btn sm"><CroIcon name="download" size={12}/> Download</button>
          </div>
          {pandocAvailable && (
            <div className="download-row">
              <span className="ft">DOCX</span>
              <span className="fname">cmp-a4f3b2c1_CTD_2.6.1.docx</span>
              <span className="sz">186 KB</span>
              <button className="btn sm"><CroIcon name="download" size={12}/> Download</button>
            </div>
          )}

          <div style={{ marginTop: 10, display: 'flex', gap: 8 }}>
            {!confirming ? (
              <button className="btn sm" onClick={() => setConfirming(true)}>
                <CroIcon name="refresh" size={12}/> Regenerate
              </button>
            ) : (
              <>
                <button className="btn sm danger" onClick={() => { setConfirming(false); generate(); }}>
                  Confirm overwrite
                </button>
                <button className="btn sm ghost" onClick={() => setConfirming(false)}>Cancel</button>
              </>
            )}
            <span style={{ fontSize: 11.5, color: 'var(--text-dim)', alignSelf: 'center', marginLeft: 4 }}>
              Regenerating overwrites the previous files.
            </span>
          </div>
        </div>
      )}
    </div>
  );
};

window.IndAssembly = IndAssembly;
