// Tweaks panel for CRO Compliance prototype
const CroTweaks = ({ knobs, setKnobs }) => {
  const [open, setOpen] = React.useState(true);
  const set = (k, v) => setKnobs({ ...knobs, [k]: v });
  const Opt = ({ group, value, label, current }) => (
    <button className={`opt ${current === value ? 'active' : ''}`} onClick={() => set(group, value)}>{label}</button>
  );
  if (!open) {
    return (
      <div className="tweaks" style={{ width: 'auto' }}>
        <button className="tweaks-head" style={{ border: 'none', width: '100%', cursor: 'pointer' }} onClick={() => setOpen(true)}>
          ⚙ Tweaks
        </button>
      </div>
    );
  }
  return (
    <div className="tweaks">
      <div className="tweaks-head">
        <span>Tweaks</span>
        <button className="btn xs ghost" onClick={() => setOpen(false)}>×</button>
      </div>
      <div className="tweaks-body">
        <div className="group">
          <div className="label">Surface (Tab)</div>
          <div className="options">
            <Opt group="tab" value="dashboard"    label="Dashboard"  current={knobs.tab}/>
            <Opt group="tab" value="validation"   label="Validation" current={knobs.tab}/>
            <Opt group="tab" value="audit"        label="Audit"      current={knobs.tab}/>
            <Opt group="tab" value="auto-retrain" label="Retrain"    current={knobs.tab}/>
            <Opt group="tab" value="ind-assembly" label="IND"        current={knobs.tab}/>
          </div>
        </div>

        <div className="group">
          <div className="label">View mode</div>
          <div className="options">
            <Opt group="show" value="tabs" label="Tabs" current={knobs.show}/>
            <Opt group="show" value="new-campaign" label="New campaign wizard" current={knobs.show}/>
          </div>
        </div>

        <div className="group">
          <div className="label">Audit state</div>
          <div className="options">
            <Opt group="auditState" value="valid" label="Valid chain" current={knobs.auditState}/>
            <Opt group="auditState" value="tampered" label="Tampered" current={knobs.auditState}/>
            <Opt group="auditState" value="empty" label="Empty" current={knobs.auditState}/>
          </div>
        </div>

        <div className="group">
          <div className="label">Auto-retrain</div>
          <div className="options">
            <Opt group="loopState" value="running" label="Running" current={knobs.loopState}/>
            <Opt group="loopState" value="stopped" label="Stopped" current={knobs.loopState}/>
            <Opt group="loopState" value="no-library" label="No library" current={knobs.loopState}/>
          </div>
        </div>

        <div className="group">
          <div className="label">Validation outcome</div>
          <div className="options">
            <Opt group="validationState" value="pass" label="EMA ✓" current={knobs.validationState}/>
            <Opt group="validationState" value="fail" label="EMA ✗" current={knobs.validationState}/>
          </div>
        </div>

        <div className="group">
          <div className="label">IND assembly</div>
          <div className="options">
            <Opt group="indState" value="generated" label="Generated" current={knobs.indState}/>
            <Opt group="indState" value="no-pandoc" label="No pandoc" current={knobs.indState}/>
            <Opt group="indState" value="fresh" label="Fresh" current={knobs.indState}/>
          </div>
        </div>

        <div className="group">
          <div className="label">eSig</div>
          <div className="options">
            <Opt group="esigEnrolled" value={true}  label="Enrolled" current={knobs.esigEnrolled}/>
            <Opt group="esigEnrolled" value={false} label="Not enrolled" current={knobs.esigEnrolled}/>
          </div>
          <div className="options">
            <button className="opt" onClick={() => set('modal', 'esig-sign')}>Show sign modal</button>
            <button className="opt" onClick={() => set('modal', 'esig-enroll')}>Show enroll modal</button>
          </div>
        </div>
      </div>
    </div>
  );
};

window.CroTweaks = CroTweaks;
