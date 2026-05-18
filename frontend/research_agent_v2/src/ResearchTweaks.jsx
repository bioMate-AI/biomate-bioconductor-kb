// ResearchTweaks STUB — the real component is a Claude-Design dev tool, not
// part of the BioMate product. The button still shows but the panel is empty
// so ResearchApp.jsx renders without modification.
function ResearchTweaks(props) {
  return (
    <div className="tweaks research-tweaks" style={{padding:12}}>
      <div className="tweaks-head">
        <span>Tweaks (disabled in BioMate)</span>
        <button className="btn ghost sm" onClick={props.onClose}>×</button>
      </div>
      <div className="tweaks-body">
        <p style={{margin:'12px 0', fontSize:12, color:'var(--text-dim)'}}>
          Tweaks panel removed for the BioMate port — the live controls live in
          the user's chat session, not in a sandbox panel.
        </p>
      </div>
    </div>
  );
}
Object.assign(window, { ResearchTweaks });
