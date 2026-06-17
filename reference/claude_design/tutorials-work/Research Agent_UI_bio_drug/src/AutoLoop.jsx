// AutoLoopCard — QC HALT card. Two modes:
//   • autoloop OFF (default): user picks Accept / Edit / Dismiss — no timer.
//   • autoloop ON: BioMate is already retrying. A 10s review window counts
//     down; if the user doesn't step in, it AUTO-PROCEEDS (applies the fix
//     and re-runs the phase). The user can cancel-and-accept-now or dismiss.
//
// Content is scenario-aware: each workflow names its own failing gates,
// proposed parameter adjustments, and the citation behind them. Falls back
// to the cryo-EM example for any scenario without a fixture.
const { useState: useStateAL, useEffect: useEffectAL, useRef: useRefAL } = React;

const HALT_FIXTURES = {
  cryosparc: {
    gates: [
      { metric: 'ctf_fit_quality', observed: '0.17', threshold: 'min 0.2' },
      { metric: 'astigmatism',     observed: '620 Å', threshold: 'max 500 Å' },
    ],
    adjustments: [
      { k: 'max_resolution', was: '3.5 Å', now: '4.5 Å' },
      { k: 'defocus_range',  was: '1.0–3.0 µm', now: '0.5–4.0 µm' },
    ],
    cite: 'Relaxing the resolution limit and widening the CTFFIND4 defocus search range restores a reliable fit when Thon rings fade past ~4 Å (Rohou & Grigorieff 2015, PMID: 26278980).',
  },
  drugscreen: {
    gates: [
      { metric: 'herg_hit_rate', observed: '0.61', threshold: 'max 0.5' },
      { metric: 'ames_positive', observed: 'positive',  threshold: 'negative' },
    ],
    adjustments: [
      { k: 'logp_max', was: '5.5', now: '4.5' },
      { k: 'mw_max',   was: '550', now: '480' },
    ],
    cite: 'Tightened physicochemical filters per internal ADMET calibration to suppress hERG / Ames liabilities.',
  },
  // ── Bioconductor scenarios ───────────────────────────────────────
  bioc_kb: {
    gates: [
      { metric: 'genes_retained', observed: '8,902', threshold: 'min 10k' },
    ],
    adjustments: [
      { k: 'min_count',   was: '10', now: '6' },
    ],
    cite: 'Relaxing edgeR::filterByExpr min_count restores low-expression genes dropped too aggressively (Chen et al. 2016).',
  },
  bioc_sc: {
    gates: [
      { metric: 'cells_retained', observed: '6,740', threshold: 'min 8k' },
    ],
    adjustments: [
      { k: 'emptyDrops_FDR', was: '0.001', now: '0.01' },
      { k: 'max_mito_pct',   was: '8%',    now: '12%' },
    ],
    cite: 'Loosening emptyDrops FDR + mito cutoff recovers viable cells over-filtered by QC (OSCA / Lun et al. 2019).',
  },
  bioc_methyl: {
    gates: [
      { metric: 'samples_read', observed: '22', threshold: 'exactly 24' },
    ],
    adjustments: [
      { k: 'force',        was: 'FALSE', now: 'TRUE' },
      { k: 'recover_idat', was: 'off',   now: 'on' },
    ],
    cite: 'Forcing minfi::read.metharray to tolerate minor manifest mismatches recovers IDAT pairs skipped on a strict read (Aryee et al. 2014).',
  },
};

function AutoLoopCard({ phase, scenario, attempt = 1, maxAttempts = 3, autoloop = false,
                       countdownSeconds = 10, onAccept, onDismiss }) {
  const fx = HALT_FIXTURES[scenario] || HALT_FIXTURES.cryosparc;
  const gateResults = fx.gates;
  const adjustments = fx.adjustments;

  // 10s review window — only runs in auto-loop mode. Reaching 0 auto-proceeds.
  const [left, setLeft] = useStateAL(countdownSeconds);
  const [paused, setPaused] = useStateAL(false);
  const firedRef = useRefAL(false);
  useEffectAL(() => {
    if (!autoloop || paused) return;
    if (left <= 0) {
      if (!firedRef.current) { firedRef.current = true; onAccept && onAccept(true); }
      return;
    }
    const t = setTimeout(() => setLeft(n => n - 1), 1000);
    return () => clearTimeout(t);
  }, [autoloop, paused, left]);
  // Reset the timer if the card re-enters auto-loop mode.
  useEffectAL(() => { if (autoloop) { setLeft(countdownSeconds); firedRef.current = false; } }, [autoloop, countdownSeconds]);

  const pct = Math.max(0, Math.min(100, (left / countdownSeconds) * 100));

  return (
    <div className="autoloop-card" data-tour="autoloop-card">
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
        <div className="al-table al-gates">
          <div className="al-row al-colhead">
            <span className="m">failing gate</span>
            <span className="obs">observed</span>
            <span className="lim">required</span>
          </div>
          {gateResults.map(g => (
            <div className="al-row" key={g.metric}>
              <span className="m">{g.metric}</span>
              <span className="obs">{g.observed}</span>
              <span className="lim">{g.threshold}</span>
            </div>
          ))}
        </div>
        <div style={{marginTop:4, fontSize:12}}>
          Proposed parameter adjustments for <strong>Phase {phase.id}</strong>:
        </div>
        <div className="al-table">
          <div className="al-row al-colhead">
            <span className="m">parameter</span>
            <span className="was">current</span>
            <span className="now">proposed</span>
          </div>
          {adjustments.map(a => (
            <div className="al-row" key={a.k}>
              <span className="m">{a.k}</span>
              <span className="was">{a.was}</span>
              <span className="now">{a.now}</span>
            </div>
          ))}
        </div>
        <div className="al-cite">{fx.cite}</div>

        {autoloop && (
          <div className={'al-countdown' + (paused ? ' paused' : '')}>
            <div className="al-countdown-bar"><span style={{width: pct + '%'}}/></div>
            <div className="al-countdown-label">
              {paused
                ? 'Review paused — apply now or dismiss'
                : <>Auto-proceeding in <b>{left}s</b> — applies the fix &amp; re-runs Phase {phase.id} unless you step in</>}
            </div>
          </div>
        )}

        <div className="al-foot">
          <button className="btn sm" onClick={() => onAccept && onAccept(false)}>
            <Icon name="refresh" size={11}/>
            {autoloop ? 'Apply now' : 'Accept & rerun phase'}
          </button>
          {autoloop && (
            <button className="btn ghost sm" onClick={() => setPaused(p => !p)}>
              {paused ? 'Resume countdown' : 'Pause 10s timer'}
            </button>
          )}
          <button className="btn ghost sm" onClick={onDismiss}>Dismiss</button>
          <span style={{flex:1}}/>
          <button className="linkish" style={{fontSize:11.5}}>Edit thresholds instead</button>
        </div>
      </div>
    </div>
  );
}

window.AutoLoopCard = AutoLoopCard;
