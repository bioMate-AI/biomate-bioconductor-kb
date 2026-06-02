// AutoLoopCard — QC HALT card. Two modes:
//   • autoloop OFF (default): user picks Accept / Edit / Dismiss
//   • autoloop ON: BioMate is already retrying; card is informational
function AutoLoopCard({ phase, attempt = 1, maxAttempts = 3, autoloop = false, onAccept, onDismiss }) {
  // Show a realistic example set of gate fails + proposed param adjustments
  const gateResults = [
    { metric: 'ctf_fit_quality', observed: '0.17', threshold: '> 0.2', status: 'HALT' },
    { metric: 'astigmatism',     observed: '620 Å', threshold: '< 500 Å', status: 'HALT' },
  ];
  const adjustments = [
    { k: 'max_resolution', was: '3.5 Å', now: '2.7 Å' },
    { k: 'defocus_range',  was: '0.5–4.0 µm', now: '1.0–3.0 µm' },
  ];
  return (
    <div className="autoloop-card">
      <div className="al-head">
        <Icon name="warn" size={14}/>
        {autoloop
          ? 'QC gate halted — auto-loop attempting remediation'
          : 'QC gate halted — review the proposed fix'}
        <span className="chip warn"><span className="dot"/>
          {autoloop ? `attempt ${attempt}/${maxAttempts}` : 'awaiting decision'}
        </span>
      </div>
      <div className="al-body">
        <div className="al-table">
          {gateResults.map(g => (
            <div className="al-row" key={g.metric}>
              <span className="m">{g.metric}</span>
              <span className="was">{g.observed}</span>
              <span className="now">{g.threshold}</span>
            </div>
          ))}
        </div>
        <div style={{marginTop:4, fontSize:12}}>
          Proposed parameter adjustments for <strong>Phase {phase.id}</strong>:
        </div>
        <div className="al-table">
          {adjustments.map(a => (
            <div className="al-row" key={a.k}>
              <span className="m">{a.k}</span>
              <span className="was">{a.was}</span>
              <span className="now">{a.now}</span>
            </div>
          ))}
        </div>
        <div className="al-cite">
          Based on Zivanov et al. 2018 (PMID: 30412051) and internal priors for sub-3 Å reconstructions.
        </div>
        <div className="al-foot">
          <button className="btn sm" onClick={onAccept}>
            <Icon name="refresh" size={11}/>
            {autoloop ? 'Cancel auto-loop & accept now' : 'Accept & rerun phase'}
          </button>
          <button className="btn ghost sm" onClick={onDismiss}>Dismiss</button>
          <span style={{flex:1}}/>
          <button className="linkish" style={{fontSize:11.5}}>Edit thresholds instead</button>
        </div>
      </div>
    </div>
  );
}

window.AutoLoopCard = AutoLoopCard;
