/* Connectors — everything BioMate reaches that it does not own. Four kinds,
   one surface, because the question a user brings here is always the same:
   what is this workspace attached to, and is it working?

   Local is not a fifth kind. It is a residency property of the same kinds,
   and residency is what users need to see: does this data leave the estate? */
window.RESIDENCY = {
  cloud:['cloud', 'data leaves the estate'],
  onprem:['on-prem', 'stays inside your network'],
  mount:['mounted', 'read in place, never copied'],
  local:['this machine', 'never leaves the host'],
  prompt:['prompt only', 'instruction text — moves no data']
};
window.CONNECTORS = [
  { k:'Data sources', n:5, what:'Where data comes from, and where results can go back.',
    rows:[['Programme share', '/mnt/genomics/runs \u00b7 indexed in place', 'mount', 'indexed \u00b7 4.2 TB'],
          ['Internal LIMS', 'plate readouts \u00b7 REST', 'onprem', 'connected'],
          ['Cohort warehouse', 'Postgres \u00b7 read-only role', 'onprem', 'connected'],
          ['Benchling', 'ELN \u00b7 assay results', 'cloud', 'polled every 6 h'],
          ['Public databases', 'sequence, structure, pathway, patent', 'cloud', 'entitled']] },
  { k:'Models & LLMs', n:3, what:'The language and reasoning models this account calls.',
    rows:[['Hosted reasoning model', 'default for every lane', 'cloud', 'active'],
          ['Self-hosted model', 'your own weights, your own GPUs', 'onprem', 'active for restricted data'],
          ['Vendor prediction service', 'structure confidence', 'cloud', 'contract to Mar 2027']] },
  { k:'Skills & experts', n:12, what:'What has been added to make BioMate better at this work.',
    rows:[['Write an IND 2.6.2 section', 'produces a .docx section, to the project template', 'onprem', 'built-in'],
          ['Build a figure to spec', 'produces a figure to the project figure spec', 'onprem', 'built-in'],
          ['Assemble a deposit archive', 'produces an RO-Crate: sources, checksums, versions, parameters', 'onprem', 'built-in'],
          ['Fit dose–response curves', 'produces fitted curves and parameters, per plate, with QC flags', 'onprem', 'built-in'],
          ['Depict structures', 'produces 2D depictions and descriptors from SMILES', 'local', 'from an MCP server'],
          ['Resolve compound identity', 'produces mappings: internal ids ↔ registry ids ↔ SMILES', 'onprem', 'from an MCP server'],
          ['Pharmacology', 'produces no artifact — reads results as a pharmacologist would', 'prompt', 'on'],
          ['Regulatory', 'produces no artifact — flags what a submission would require', 'prompt', 'on'],
          ['Biostatistics · Structural biology · Clinical trials · QC', 'four more readings', 'prompt', 'available']] },
  { k:'MCP servers', n:2, what:'Tool servers that give the agent capabilities we did not build.',
    rows:[['Internal registry server', 'compound and sample identity', 'onprem', 'connected'],
          ['Chem toolkit server', 'depictions, descriptors, validity', 'local', 'connected']] }
];
/* Adding something local: three real cases, each a mode of an existing kind. */
window.ADD_CONNECTOR = [
  { kind:'Data source', k:'A directory', q:'A share, an HPC scratch path, an instrument output folder.',
    mode:'Index in place, or copy in',
    note:'Indexing reads the files where they are and creates dataset objects that point at them — a 4 TB run directory is not copied. Copying in is for small sets you want versioned inside the project. Each scan is a version, so files that change are tracked rather than silently replaced.' },
  { kind:'Data source', k:'A database', q:'Postgres, SQLite, a warehouse, an internal registry.',
    mode:'Connection + a read scope',
    note:'A read-only role and the tables it may see. A pull becomes a dataset object whose origin records the query and the time it ran — so a result can be reproduced against a moving database, or at least shown to be unreproducible.' },
  { kind:'Model', k:'A model', q:'Your own weights, a hosted endpoint, or a vendor service.',
    mode:'Endpoint + residency',
    note:'Registered like any other model: it still needs held-out evidence on data in the product before it can gate anything. Marking it on-prem is what lets restricted data be routed to it.' },
  { kind:'Skill or expert', k:'Something your team repeats', q:'A section to draft, a fit to run, a figure to build, or a reading your specialists always apply.',
    mode:'Say what it needs and what it produces',
    note:'You describe it in your own words. It cannot change a parameter — to change what runs, write it in a project\u2019s instructions.' },
  { kind:'MCP server', k:'An MCP server', q:'A tool server that gives the agent capabilities we did not build.',
    mode:'URL + auth + a capability review',
    note:'Its tools are listed before it is attached, and each one it contributes is marked with the server it came from — so an unexplained agent capability is always attributable.' }
];

function ResChip({ r }) {
  if (!r) return null;
  const [label, why] = RESIDENCY[r] || RESIDENCY.cloud;
  return <span className={'res ' + r} title={why}><Icon name={r === 'cloud' ? 'external' : 'folder'} size={9}/>{label}</span>;
}

function Connectors({ onToast }) {
  const [sel, setSel] = React.useState(0);
  const [add, setAdd] = React.useState(false);
  const c = CONNECTORS[sel];
  return <div className="mainpane">
    <div className="objhead">
      <div className="crumb"><span>Workspace</span><span className="sep">/</span><span>Connectors</span></div>
      <div className="objtitle">
        <h2 style={{ fontFamily:'var(--font-ui)' }}>Connectors</h2>
        <span className="spacer"/>
        <button className="btn sm" onClick={() => setAdd(a => !a)}>{add ? 'Close' : 'Add a connector'}</button>
      </div>
      <span className="anchor">Everything this workspace is attached to but does not own — where data comes in, which models are called, what has been added to make it better at this work, and which tool servers it can reach. Each one carries where it lives, because the question behind most of them is whether your data leaves the estate.</span>
      <div className="tabs2">{CONNECTORS.map((x, i) =>
        <button key={x.k} className={'tab2' + (i === sel ? ' on' : '')} onClick={() => { setSel(i); setAdd(false); }}>{x.k}<span className="kb">{x.n}</span></button>)}</div>
    </div>
    <div className="objbody">
      {add ? <>
        <div className="card2 col" style={{ gap:'10px' }}>
          <span className="k2">Add a connector</span>
          <span className="hint">Every kind can be added, including your own. Local is not a separate kind — a directory is a data source, your own weights are a model. What changes is where it lives and whether anything is copied.</span>
          {ADD_CONNECTOR.map(a => <div key={a.k} className="addrow">
            <span className="col" style={{ gap:'3px', minWidth:0 }}>
              <span className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'4px' }}>
                <span style={{ fontSize:'13px', fontWeight:600 }}>{a.k}</span>
                <span className="chip">{a.kind}</span>
                <span className="chip acc">{a.mode}</span>
              </span>
              <span className="hint dim">{a.q}</span>
              <span className="hint">{a.note}</span>
            </span>
            <button className="btn sm" onClick={() => onToast(a.k + ' \u2014 you give the path or endpoint, we show what was found and what it will become before anything is attached.')}>Set up</button>
          </div>)}
        </div>
        <span className="hint dim">Nothing is attached until you have seen what was found. A directory scan reports the file types and counts it detected, and what each will become, before it creates a single dataset object.</span>
      </> : <>
        <div className="card2 col" style={{ gap:'10px' }}>
          <span className="hint">{c.what}</span>
          <div className="col" style={{ gap:'0' }}>
            {c.rows.map(([name, detail, res, state]) => <div key={name} className="connrow">
              <span className="col" style={{ gap:'2px', minWidth:0 }}>
                <span style={{ fontSize:'12.5px', fontWeight:600 }}>{name}</span>
                <span className="hint dim">{detail}</span>
              </span>
              <ResChip r={res}/>
              <span className={'chip ' + (/connected|active|on$|indexed|entitled|polled/.test(state) ? 'ok' : '')}><span className="dot"/>{state}</span>
            </div>)}
          </div>
        </div>
        {sel === 0 && <span className="hint dim">A connected source lands its data as a dataset object in a project, with the system as its origin and a version per pull or per scan — never as an untracked import. A mounted path is read in place; nothing is copied.</span>}
        {sel === 1 && <span className="hint dim">Residency is what routes a request: data marked restricted goes only to models that stay inside your network, and a run records which one answered.</span>}
        {sel === 2 && <span className="hint dim">Whatever these produce is recorded on the run that used them. None of them can change a parameter — to change what runs, write it in the project's instructions.</span>}
      </>}
    </div>
  </div>;
}
Object.assign(window, { Connectors, ResChip });
