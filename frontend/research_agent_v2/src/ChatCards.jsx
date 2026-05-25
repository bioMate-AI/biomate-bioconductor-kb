// Surface 4 — Run-vs-Run Comparison card  (inline chat card)
// Surface 5 — Pilot Promotion card        (inline chat card)
//                Findings card             (inline chat card)
//
// All cards take an `onAction(label)` callback so the host can resume
// the scenario engine when the user clicks. They each render an
// auto-proceed countdown bar tied to a label too.

const { useState, useEffect, useRef } = React;

// ─────────────────────────────────────────────────────────────────
// Pilot Prompt card — replaces the in-panel pilot toggle.
// Posted by BioMate inline in chat when a pilot is recommended.
// ─────────────────────────────────────────────────────────────────
function PilotPromptCard({ scenario, onAction, dismissed }) {
  const [mode, setMode] = useState('pilot');
  const [strategy, setStrategy] = useState('random');
  if (dismissed) return null;
  const p = scenario.pilot;
  if (!p) return null;
  return (
    <div className="pilot-promotion" data-tour="pilot-prompt" style={{borderLeftColor: 'var(--accent)'}}>
      <div className="pp-head">
        <div className="ic" style={{background:'var(--accent-soft)', color:'var(--accent-ink)'}}>🔬</div>
        <div className="title">Worth a pilot first?</div>
        {/* Cost estimate badge — commented out, leaving for future work
        <div className="status" style={{background:'var(--accent-soft)', color:'var(--accent-ink)'}}>
          est. ${scenario.cost.full_usd.toFixed(2)} full
        </div>
        */}
      </div>
      <div className="pp-meta">
        Full run is ~{scenario.cost.full_min} min on {p.total} samples ·
        a {Math.round(p.fraction * 100)}% pilot ({p.sampled} samples) takes ~{scenario.cost.pilot_min} min.
        {/* Cost estimate — commented out, leaving for future work
        ~${scenario.cost.pilot_usd.toFixed(2)}.
        */}
      </div>
      <div className="pp-summary">
        <div className="sl">Pilot config</div>
        <div className="pilot-toggle" style={{margin: 0, padding: 0, border: 'none', background: 'transparent'}}>
          <div className="pt-options" style={{marginBottom: 6}}>
            <label className={'radio' + (mode === 'pilot' ? ' active' : '')} onClick={() => setMode('pilot')}>
              <span className="ring"/>Pilot first
            </label>
            <label className={'radio' + (mode === 'full' ? ' active' : '')} onClick={() => setMode('full')}>
              <span className="ring"/>Full run only
            </label>
          </div>
          {mode === 'pilot' && (
            <div className="strategy" style={{marginLeft: 22, marginBottom: 0}}>
              <span>{p.sampled} of {p.total},</span>
              <select value={strategy} onChange={e => setStrategy(e.target.value)}>
                <option value="random">random</option>
                <option value="stratified">stratified</option>
                <option value="first_n">first N</option>
              </select>
            </div>
          )}
        </div>
      </div>
      <div className="pp-actions">
        <div className="btn-row">
          {mode === 'pilot' ? (
            <React.Fragment>
              <button className="btn primary" onClick={() => onAction('run_pilot')}>
                <Icon name="play" size={11}/> Run pilot first
              </button>
              <button className="btn ghost" onClick={() => onAction('run_full')}>
                Skip — run full directly
              </button>
            </React.Fragment>
          ) : (
            <button className="btn primary" onClick={() => onAction('run_full')}>
              <Icon name="play" size={11}/> Confirm and run full
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────
// Reusable: ring-shaped countdown
// ─────────────────────────────────────────────────────────────────
function CountdownRing({ remaining, total, color }) {
  const r = 6, c = 2 * Math.PI * r;
  const off = c * (1 - remaining / total);
  return (
    <span className="countdown-ring" aria-hidden="true">
      <svg viewBox="0 0 14 14">
        <circle className="track" cx="7" cy="7" r={r}/>
        <circle cx="7" cy="7" r={r}
          stroke={color || 'currentColor'}
          strokeDasharray={c}
          strokeDashoffset={off}
          strokeLinecap="round"/>
      </svg>
    </span>
  );
}

// ─────────────────────────────────────────────────────────────────
// Pilot promotion card
// ─────────────────────────────────────────────────────────────────
function PilotPromotionCard({ data, onAction, countdown, dismissed }) {
  if (dismissed) return null;
  const failed = data.result !== 'pass';

  return (
    <div className={'pilot-promotion' + (failed ? ' failed' : '')} data-tour="pilot-promotion">
      <div className="pp-head">
        <div className="ic">🔬</div>
        <div className="title">Pilot done</div>
        <div className="status">
          {failed ? 'QC gates triggered' : 'all QC passed'}
        </div>
      </div>
      <div className="pp-meta">
        Pilot ran on {data.sampled} samples in {data.runtime}.
        {/* Cost estimate — commented out, leaving for future work
        · cost {data.cost}
        */}
      </div>
      <div className="pp-summary">
        <div className="sl">QC summary</div>
        {data.qc.map((q, i) => (
          <div key={i} className={'qc-row ' + q.status}>
            <span className="ic">
              {q.status === 'pass' && '✓'}
              {q.status === 'warn' && '!'}
              {q.status === 'fail' && '✕'}
            </span>
            <span className="name">{q.name}</span>
            <span className="desc">{q.desc}</span>
          </div>
        ))}
      </div>

      {data.suggestion && (
        <div className="pp-suggest">
          <span className="ic">💡</span>
          <span>
            <strong>{data.suggestion.text}: </strong>
            {data.suggestion.changes.map((c, i) => (
              <React.Fragment key={i}>
                {i > 0 && ', '}
                <code>{c[0]}={c[2]}</code>
              </React.Fragment>
            ))}
          </span>
        </div>
      )}

      {!failed && (
        <div className="pp-question">
          Ready for the full run on {data.total} samples?
          <div className="sub">Estimated: {data.full_min} min{/* · ${data.full_cost.toFixed(2)} — cost commented out, leaving for future work */}</div>
        </div>
      )}

      <div className="pp-actions">
        <div className="btn-row">
          {failed ? (
            <React.Fragment>
              <button className="btn primary" onClick={() => onAction('apply_fixes')}>
                <Icon name="wand" size={12}/> Apply fixes and re-pilot
              </button>
              <button className="btn" onClick={() => onAction('adjust_manually')}>
                Adjust manually
              </button>
              <button className="btn ghost" onClick={() => onAction('stop_here')}>
                Stop here
              </button>
            </React.Fragment>
          ) : (
            <React.Fragment>
              <button className="btn primary" onClick={() => onAction('promote_full')}>
                <Icon name="play" size={11}/> Run full pipeline
              </button>
              <button className="btn" onClick={() => onAction('adjust_params')}>
                Adjust parameters
              </button>
              <button className="btn ghost" onClick={() => onAction('stop_here')}>
                Stop here
              </button>
            </React.Fragment>
          )}
        </div>
        <div className="pp-countdown">
          {countdown && countdown.remaining > 0 ? (
            <React.Fragment>
              <CountdownRing remaining={countdown.remaining} total={countdown.total} color="var(--text-dim)"/>
              {' '}Defaults to <strong style={{color:'var(--text)'}}>Stop here</strong> in {countdown.remaining}s — full runs need explicit OK.
            </React.Fragment>
          ) : (
            <span>Defaults to Stop here — full runs need your explicit OK.</span>
          )}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────
// Comparison card (Surface 4)
// ─────────────────────────────────────────────────────────────────
function ComparisonCard({ data, onAction, countdown, dismissed, asPanel }) {
  if (dismissed) return null;
  const rec = data.recommendation;
  const confCls = rec.confidence || 'inconclusive';
  const preferred = rec.preferred; // 'A' | 'B' | 'inconclusive'
  const useBtnLabel = preferred === 'A' ? 'Use Run A' : preferred === 'B' ? 'Use Run B' : 'No clear winner';
  const useBtnAction = preferred === 'A' ? 'use_a' : preferred === 'B' ? 'use_b' : 'noop';

  const body = (
    <React.Fragment>
      <div className="cc-body">
        <table className="metric-table">
          <thead>
            <tr>
              <th style={{width: '34%'}}>Metric</th>
              <th>{data.runA.label}</th>
              <th>{data.runB.label}</th>
              <th style={{width: '15%'}}>Δ</th>
            </tr>
          </thead>
          <tbody>
            {data.metrics.map((m, i) => (
              <tr key={i}>
                <td className="name">{m.name}</td>
                <td><span className={'val' + (m.aQc === 'fail' ? ' qc-fail' : m.aQc === 'pass' ? ' qc-pass' : '')}>
                  {m.a}{m.aQc === 'fail' && ' ✕'}{m.aQc === 'pass' && ' ✓'}
                </span></td>
                <td><span className={'val' + (m.bQc === 'fail' ? ' qc-fail' : m.bQc === 'pass' ? ' qc-pass' : '')}>
                  {m.b}{m.bQc === 'fail' && ' ✕'}{m.bQc === 'pass' && ' ✓'}
                </span></td>
                <td><span className={'delta ' + (m.dir || 'neu')}>{m.delta}</span></td>
              </tr>
            ))}
          </tbody>
        </table>

        <div className="cc-section-label">Parameters that differed</div>
        {data.params.map((p, i) => (
          <div key={i} className="param-diff-row">
            <span className="pname">{p.name}</span>
            <span className="diff">
              <span className="was">{p.a}</span>
              <span className="arrow">→</span>
              <span className="now">{p.b}</span>
            </span>
            <span className={'origin ' + p.origin}>{p.origin}</span>
          </div>
        ))}

        <div className="recommendation">
          <div className={'ic ' + confCls}>💡</div>
          <div className="text">
            <strong>Recommendation</strong>
            {rec.reason}
            <div className="conf" style={{marginTop: 4}}>
              Confidence: {rec.confidence}
              {rec.pvalue && rec.test && <span> · {rec.test}, p {rec.pvalue}</span>}
            </div>
          </div>
        </div>
      </div>

      <div className="cc-foot">
        <button className="btn primary" onClick={() => onAction(useBtnAction)} disabled={preferred === 'inconclusive'}>
          {useBtnLabel}
        </button>
        <button className="btn" onClick={() => onAction(preferred === 'A' ? 'keep_b' : 'keep_a')}>
          Keep {preferred === 'A' ? 'Run B' : 'Run A'}
        </button>
        <button className="btn ghost" onClick={() => onAction('show_full_diff')}>
          Show full diff
        </button>
        {countdown && countdown.remaining > 0 && (
          <span className="countdown-note">
            <CountdownRing remaining={countdown.remaining} total={countdown.total} color="var(--text-dim)"/>
            Auto-confirming Run {preferred} in {countdown.remaining}s
          </span>
        )}
      </div>
    </React.Fragment>
  );

  if (asPanel) {
    return (
      <div className="compare-side-panel">
        <div className="csp-head">
          <span className="title">Compare runs · {data.runA.label} vs {data.runB.label}</span>
          <span className={'rec-badge ' + confCls}>
            <span className="trophy">🏆</span> Run {preferred} preferred ({rec.confidence})
          </span>
          <button className="btn ghost sm" onClick={() => onAction('close_panel')}>
            <Icon name="x" size={12}/>
          </button>
        </div>
        <div className="csp-body">{body}</div>
      </div>
    );
  }

  return (
    <div className="compare-card" data-tour="comparison-card">
      <div className="cc-head">
        <span className="title">Compare runs <span className="sub">· {data.runA.label} vs {data.runB.label}</span></span>
        <span className={'rec-badge ' + confCls}>
          <span className="trophy">🏆</span> Run {preferred} preferred ({rec.confidence})
        </span>
      </div>
      {body}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────
// Findings card (run-complete summary, inline in chat)
// ─────────────────────────────────────────────────────────────────
function FindingsChatCard({ data }) {
  return (
    <div className="findings-chat-card" data-tour="findings-chat">
      <div className="fcc-h">
        <span className="ic"><Icon name="sparkles" size={14}/></span>
        <span>{data.title}</span>
      </div>
      <div className="fcc-body">
        Workflow done in {data.runtime} · {data.samples} sample{data.samples === 1 ? '' : 's'}.
        {/* Cost estimate — commented out, leaving for future work
        · cost {data.cost}
        */}
      </div>
      <div className="fcc-table">
        {data.rows.map((r, i) => (
          <div key={i} className="fcc-row">
            <span>{r[0]}</span>
            <span style={{color:'var(--text)'}}>{r[1]}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { PilotPromptCard, PilotPromotionCard, ComparisonCard, FindingsChatCard, CountdownRing });
