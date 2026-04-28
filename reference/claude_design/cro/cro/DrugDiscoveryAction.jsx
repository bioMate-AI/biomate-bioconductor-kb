// DrugDiscoveryAction — tabbed host that switches between surfaces
// Matches the spec: mode = dashboard | validation | audit | auto-retrain | ind-assembly | new-campaign

const TABS = [
  { key: 'dashboard',    label: 'Dashboard',   icon: 'target' },
  { key: 'validation',   label: 'Validation',  icon: 'beaker' },
  { key: 'audit',        label: 'Audit',       icon: 'shield', count: 47 },
  { key: 'auto-retrain', label: 'Auto-Retrain',icon: 'refresh', pulseWhenRunning: true },
  { key: 'ind-assembly', label: 'IND',         icon: 'file' },
];

const DrugDiscoveryAction = ({ knobs, setKnobs, onToast, onGatedAction }) => {
  const tab = knobs.tab;
  const setTab = (t) => setKnobs({ ...knobs, tab: t });

  const tamperedAudit = knobs.auditState === 'tampered';
  const emptyAudit = knobs.auditState === 'empty';
  const loopRunning = knobs.loopState === 'running';
  const hasLibrary = knobs.loopState !== 'no-library';
  const emaFail = knobs.validationState === 'fail';
  const pandocAvailable = knobs.indState !== 'no-pandoc';
  const indGenerated = knobs.indState === 'generated' || knobs.indState === 'no-pandoc';

  return (
    <div className="dd-card">
      <div className="dd-card-head">
        <div className="row1">
          <div className="icon-wrap"><CroIcon name="dna" size={17}/></div>
          <div className="title-col">
            <div className="title">Drug Discovery · {MOCK_CAMPAIGN.molecule_name}</div>
            <div className="sub">
              <span className="mono">{MOCK_CAMPAIGN.campaign_id}</span> · {MOCK_CAMPAIGN.target} · {MOCK_CAMPAIGN.indication}
            </div>
          </div>
          {knobs.show === 'new-campaign' ? null : (
            <button className="btn sm" onClick={() => setKnobs({ ...knobs, show: 'new-campaign' })} data-tour="new-campaign-btn">
              <CroIcon name="plus" size={12}/> New campaign
            </button>
          )}
          <button className="btn sm ghost" data-tour="esig-btn" onClick={() => {
            if (!knobs.esigEnrolled) setKnobs({ ...knobs, modal: 'esig-enroll' });
            else setKnobs({ ...knobs, modal: 'esig-sign' });
          }}>
            <CroIcon name="signature" size={12}/> {knobs.esigEnrolled ? 'Sign action' : 'Enroll eSig'}
          </button>
        </div>

        {knobs.show !== 'new-campaign' && (
          <div className="dd-tabs" data-tour="tabs-bar">
            {TABS.map(t => (
              <button
                key={t.key}
                className={`dd-tab ${tab === t.key ? 'active' : ''}`}
                onClick={() => setTab(t.key)}
              >
                <CroIcon name={t.icon} size={13}/>
                {t.label}
                {t.count && <span className="tab-count">{t.count}</span>}
                {t.pulseWhenRunning && loopRunning && <span className="pulse-dot pulse"/>}
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="dd-body">
        {knobs.show === 'new-campaign'
          ? <CampaignWizard onDone={() => setKnobs({ ...knobs, show: 'tabs' })} onToast={onToast}/>
          : tab === 'dashboard'    ? <CampaignDashboard onToast={onToast} onGatedAction={onGatedAction} validationFailed={emaFail}/>
          : tab === 'validation'   ? <ValidationPanel emaFail={emaFail}/>
          : tab === 'audit'        ? <AuditTrail tampered={tamperedAudit} empty={emptyAudit}/>
          : tab === 'auto-retrain' ? <AutoRetrain loopRunning={loopRunning} hasLibrary={hasLibrary} validationFailed={emaFail} onGatedAction={onGatedAction} onToast={onToast}/>
          : tab === 'ind-assembly' ? <IndAssembly pandocAvailable={pandocAvailable} generated={indGenerated} validationFailed={emaFail} onGatedAction={onGatedAction} onToast={onToast}/>
          : null
        }
      </div>
    </div>
  );
};

window.DrugDiscoveryAction = DrugDiscoveryAction;
