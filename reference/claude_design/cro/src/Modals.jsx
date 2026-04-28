// Modals: Skip-phase confirm, Adjust & Rerun, Output preview
const { useState: useStateM } = React;

function SkipConfirmModal({ target, onCancel, onConfirm }) {
  if (!target) return null;
  const { targetKind: kind, name, downstream } = target;
  return (
    <div className="modal-backdrop" onClick={onCancel}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div className="body">
          <div className="confirm-icon"><Icon name="warn" size={18}/></div>
          <h3>Skip {kind} "{name}"?</h3>
          <p style={{color:'var(--text-muted)', lineHeight:1.55, margin:'6px 0 14px'}}>
            Skipping {kind === 'phase' ? 'a phase' : 'a step'} removes its output files.
            {downstream && downstream.length > 0 && (
              <> Downstream {downstream.length === 1 ? 'phase' : 'phases'}{' '}
                <span className="mono" style={{color:'var(--text)'}}>
                  {downstream.join(', ')}
                </span>{' '}
                depend on these outputs and may fail.
              </>
            )}
          </p>
          <div style={{
            border:'1px dashed var(--border-strong)', borderRadius:'var(--r-sm)',
            padding:'9px 12px', fontSize:12, color:'var(--text-muted)',
            background:'var(--surface)'
          }}>
            You can rerun the skipped {kind} at any time from its card.
          </div>
        </div>
        <div className="foot">
          <button className="btn ghost" onClick={onCancel}>Cancel</button>
          <button className="btn" style={{color:'var(--err)', borderColor:'var(--err)'}}
            onClick={onConfirm}>
            Skip {kind} anyway
          </button>
        </div>
      </div>
    </div>
  );
}

function AdjustModal({ step, onCancel, onRerun }) {
  if (!step) return null;
  return (
    <div className="modal-backdrop" onClick={onCancel}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div className="body">
          <h3>Adjust &amp; rerun — {step.name}</h3>
          <p style={{color:'var(--text-muted)', fontSize:12.5, margin:'4px 0 16px'}}>
            Parameters below apply to this step only. Downstream steps will rerun
            automatically from this point. A new <span className="mono">runId</span> will be created.
          </p>
          {step.params && step.params.map(p => (
            <div className="field" key={p.k}>
              <label>{p.k}</label>
              <input defaultValue={p.v}/>
            </div>
          ))}
          {(!step.params || step.params.length === 0) && (
            <div className="field">
              <label>No step-level parameters</label>
              <input placeholder="This step has no overridable parameters" disabled/>
            </div>
          )}
        </div>
        <div className="foot">
          <button className="btn ghost" onClick={onCancel}>Cancel</button>
          <button className="btn primary" onClick={onRerun}>
            <Icon name="refresh" size={12}/> Rerun from here
          </button>
        </div>
      </div>
    </div>
  );
}

function PreviewModal({ file, onClose }) {
  if (!file) return null;
  const previews = {
    'motion_trace.star':
`# motion_trace.star
data_general
_rlnMicrographName   micrograph_001.mrc
_rlnMicrographMovieName  movie_001.mrc
loop_
_rlnFrameNumber  _rlnShiftX  _rlnShiftY
  1      0.00     0.00
  2      0.42    -0.18
  3      0.78    -0.41
  4      1.06    -0.72
  …    (248 frames)`,
    'ctf_estimates.star':
`# Gctf estimates — 842 micrographs
_rlnMicrographName     _rlnDefocusU    _rlnDefocusV    _rlnFitQuality
micrograph_001.mrc     14820           14550           0.31
micrograph_002.mrc     12210           11990           0.28
micrograph_003.mrc     18040           17750           0.23
micrograph_004.mrc     15770           15510           0.34
…`,
    'ctf_diagnostic.png': '[ image preview — CTF power spectrum ]',
  };
  const content = previews[file.name] || `[ preview for ${file.name} ]`;
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal preview-modal" onClick={e => e.stopPropagation()}>
        <div className="body" style={{paddingBottom:0}}>
          <div style={{display:'flex', alignItems:'center', justifyContent:'space-between'}}>
            <div>
              <h3 className="mono" style={{fontSize:13}}>{file.name}</h3>
              <div style={{fontSize:11, color:'var(--text-dim)'}}>
                Step output · preview truncated to first 1,000 lines
              </div>
            </div>
            <button className="btn ghost sm" onClick={onClose}><Icon name="x" size={14}/></button>
          </div>
        </div>
        <div className="preview-body">{content}</div>
        <div className="foot">
          <button className="btn sm"><Icon name="download" size={12}/> Download</button>
          <button className="btn sm"><Icon name="external" size={12}/> Open in viewer</button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { SkipConfirmModal, AdjustModal, PreviewModal });
