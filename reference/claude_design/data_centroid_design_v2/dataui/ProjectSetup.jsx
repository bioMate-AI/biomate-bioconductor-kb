/* Project instructions — standing guidance, output requirements (templates)
   and notes. One surface, because they are the same act: telling BioMate how
   work in this project should be done and what it should look like. */
function ProjectSetup({ project, onToast, onOpenData, addons, setAddon }) {
  const P = PROJECT_SETUP[project] || PROJECT_SETUP.default;
  const [edit, setEdit] = React.useState(null);
  const onCount = ACCOUNT_ADDONS.filter(n => addons[n]).length;
  return <div className="mainpane">
    <div className="objhead">
      <div className="crumb"><span>{project}</span><span className="sep">/</span><span>Instructions</span></div>
      <div className="objtitle">
        <h2 style={{ fontFamily:'var(--font-ui)' }}>Instructions</h2>
        <span className="chip acc">{P.rules.length + P.outputs.length} active</span>
        <span className="spacer"/>
        <button className="btn sm ghost" onClick={() => onToast('Applies to every session in this project, and to every run started from one.')}>Where does this apply?</button>
      </div>
    </div>
    <div className="objbody">
      <div className="card2 col" style={{ gap:'10px' }}>
        <div className="row ac"><span className="k2">Standing instructions</span><span className="spacer"/>
          <button className="btn sm" onClick={() => setEdit(edit === 'rules' ? null : 'rules')}>{edit === 'rules' ? 'Done' : 'Edit'}</button></div>
        <span className="hint">Read by the agent at the start of every session in <b>{project}</b> — the project's equivalent of the notes a new team member would be handed. They constrain how work is done, not what you ask for.</span>
        {edit === 'rules'
          ? <textarea className="instr" defaultValue={P.rules.map(r => '• ' + r).join('\n')} onBlur={() => onToast('Saved for this project. Existing runs are unaffected; new ones inherit it.')}/>
          : <div className="col" style={{ gap:'0' }}>{P.rules.map((r, i) => <div key={i} className="qline"><span className="rulen">{i + 1}</span><span>{r}</span></div>)}</div>}
      </div>

      <div className="card2 col" style={{ gap:'10px' }}>
        <div className="row ac"><span className="k2">Output requirements</span><span className="spacer"/>
          <button className="btn sm" onClick={() => onToast('Templates are versioned per project — a run records which version formatted its report.')}>Manage templates</button></div>
        <span className="hint">What a finished deliverable has to look like. The after-run report, figures and tables are generated <b>to these</b>, so a run's output arrives in your house style rather than being reformatted afterwards.</span>
        <div className="col" style={{ gap:'8px' }}>
          {P.outputs.map(([kind, name, detail, applied]) => <div key={name} className="tmplrow">
            <span className="chip">{kind}</span>
            <div className="col" style={{ gap:'3px', flex:1, minWidth:0 }}>
              <span style={{ fontSize:'13px', fontWeight:600 }}>{name}</span>
              <span className="hint">{detail}</span>
            </div>
            {applied && <span className="chip ok"><span className="dot"/>applied</span>}
            <button className="btn sm ghost" onClick={() => onToast('Preview the template with your last run\u2019s content.')}>Preview</button>
          </div>)}
          <button className="tmplrow add" onClick={() => onToast('Upload a .docx / .md template, or start from an IND, journal or internal preset.')}>
            <Icon name="plus" size={13}/><span style={{ fontSize:'12.5px', fontWeight:600 }}>Add an output requirement</span>
            <span className="hint">a report template, a figure spec, a naming convention</span>
          </button>
        </div>
      </div>

      <div className="card2 col" style={{ gap:'10px' }}>
        <div className="row ac" style={{ flexWrap:'wrap', rowGap:'6px' }}><span className="k2">Skills &amp; experts</span>
          <span className={'chip' + (onCount ? ' acc' : '')}>{onCount ? onCount + ' on' : 'none on yet'}</span>
          <span className="spacer"/>
          <button className="linkish" onClick={() => onToast('Connectors holds everything connected to the account. This page chooses which of them are on in this project.')}>add to the account →</button></div>
        <span className="hint">Connected once for the whole account, switched on per project. A chat here can still turn one on or off for a single question.</span>
        <div className="col" style={{ gap:'0' }}>
          {ACCOUNT_ADDONS.map(name => <div key={name} className="qline">
            <span className={'switch' + (addons[name] ? ' on' : '')} role="switch" aria-checked={!!addons[name]}
              onClick={() => setAddon(name, !addons[name])}/>
            <span style={{ fontSize:'12.5px', fontWeight:addons[name] ? 600 : 400, color:addons[name] ? 'var(--text)' : 'var(--text-muted)' }}>{name}</span>
          </div>)}
        </div>
      </div>

      <div className="two">
        <div className="card2 col" style={{ gap:'10px' }}>
          <div className="row ac"><span className="k2">Notes</span><span className="spacer"/>
            <button className="btn sm" onClick={() => setEdit(edit === 'notes' ? null : 'notes')}>{edit === 'notes' ? 'Done' : 'Edit'}</button></div>
          <span className="hint">Free text for humans. Not read by the agent unless you promote a line to a standing instruction — the distinction matters, so nobody is surprised by what the model acted on.</span>
          {edit === 'notes'
            ? <textarea className="instr" defaultValue={P.notes} onBlur={() => onToast('Note saved.')}/>
            : <span className="said" style={{ fontSize:'13px', whiteSpace:'pre-line' }}>{P.notes}</span>}
          <button className="btn sm ghost" style={{ alignSelf:'flex-start' }} onClick={() => onToast('Promoted to a standing instruction — from now on the agent reads it.')}>Promote a line to an instruction ↑</button>
        </div>
        <div className="card2 col" style={{ gap:'10px' }}>
          <span className="k2">What inherits this</span>
          <div className="col" style={{ gap:'0' }}>
            <div className="qline"><span className="chip">sessions</span><span className="hint">Every chat in this project starts with the instructions in context, shown as a chip in the composer.</span></div>
            <div className="qline"><span className="chip">runs</span><span className="hint">Parameters that an instruction fixes arrive pre-set, badged <b>from project instructions</b> beside “from your message”.</span></div>
            <div className="qline"><span className="chip">reports</span><span className="hint">The after-run report is written to the active template, and records which version it used.</span></div>
            <div className="qline"><span className="chip">datasets</span><span className="hint">Naming and scope rules apply at ingest, so files land consistently.</span></div>
          </div>
          <button className="btn sm" style={{ alignSelf:'flex-start' }} onClick={onOpenData}>See the project's data →</button>
        </div>
      </div>
    </div>
  </div>;
}
Object.assign(window, { ProjectSetup });
