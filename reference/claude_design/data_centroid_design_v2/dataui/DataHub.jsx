/* Project → Files. The existing file system, with the dataset object attached to
   a file rather than replacing it: preview & edit, versions, and where it came
   from. Three tabs, no jargon. */
function FileTree({ project, sel, onSel, onToast, onHide }) {
  useVersionTick();
  const tree = FILETREE[project] || FILETREE.default;
  const [open, setOpen] = React.useState(() => Object.fromEntries(tree.map(f => [f.folder, true])));
  const [q, setQ] = React.useState('');
  const needle = q.trim().toLowerCase();
  const match = id => { const d = DATASETS.find(x => x.id === id); return d && (d.name + ' ' + (d.kind || '')).toLowerCase().includes(needle); };
  const shown = needle ? tree.map(f => ({ ...f, files:f.files.filter(match) })).filter(f => f.files.length) : tree;
  const hits = shown.reduce((n, f) => n + f.files.length, 0);
  return <div className="hublist">
    <div className="hlh">
      <div className="row ac" style={{ gap:'6px' }}>
        <span className="k2">Files</span><span className="spacer"/>
        {onHide && <button className="zoomb panehide" title="Hide the file list" onClick={onHide}><Icon name="chevronLeft" size={11}/></button>}
        <button className="btn sm" onClick={() => onToast('Ingest panel: drop a file, paste a URL, or pull from a database connected in Connectors — with the quality card before anything runs.')}>＋ Add</button>
      </div>
      <span className="hint">Uploads and run outputs in <b>{project}</b>. A file keeps its versions; nothing is silently overwritten.</span>
      <span className="searchbox sm">
        <Icon name="search" size={13}/>
        <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search files" aria-label="Search files"/>
        {q && <button className="clr" onClick={() => setQ('')} title="Clear">✕</button>}
      </span>
    </div>
    <div className="items">
      {shown.map(f => <React.Fragment key={f.folder}>
        <button className="folderrow" onClick={() => setOpen(o => ({ ...o, [f.folder]:!o[f.folder] }))}>
          <span className={'pchev' + (open[f.folder] || needle ? ' on' : '')}><Icon name="chevronRight" size={11}/></span>
          <Icon name="folder" size={12}/><span className="fname">{f.folder}</span><span className="fcount">{f.files.length}</span>
        </button>
        {(open[f.folder] || needle) && f.files.map(id => { const d = DATASETS.find(x => x.id === id); if (!d) return null;
          const vs = fileVersions(d.id);
          return <button key={id} className={'filerow' + (sel === id ? ' on' : '')} onClick={() => onSel(id)}>
            <span className="qd dot" style={{ background:QUAL[d.quality].c }}/>
            <span className="fname mono">{d.name}</span>
            {!!vs.length && <span className="vtag">v{vs[0].v}</span>}
          </button>; })}
      </React.Fragment>)}
      {needle && !hits && <div className="nohits">No file matches “{q}”.</div>}
    </div>
  </div>;
}

function OpenIn({ ds, onToast }) {
  const envs = ds.kind.includes('variant') ? [['Jupyter', 'Python 3.11 · pysam, pandas'], ['Terminal', 'bcftools, samtools']]
    : ds.name.endsWith('.csv') || ds.name.endsWith('.tsv') ? [['Jupyter', 'Python 3.11 · pandas, scanpy'], ['RStudio', 'R 4.3 · tidyverse, DESeq2'], ['Plot viewer', 'interactive charts']]
    : [['Jupyter', 'Python 3.11']];
  return <div className="row wrap" style={{ gap:'7px' }}>
    {envs.map(([e, sub]) => <button key={e} className="btn sm" title={sub} onClick={() => onToast('Opening ' + ds.name + ' in ' + e + ' — ' + sub + '. The session mounts this version read-write; saving writes a new version.')}>
      <Icon name="external" size={12}/>{e}</button>)}
    <button className="btn sm ghost" onClick={() => onToast('Ask in chat: code is written and run in the sandbox against this file, and the code is shown.')}>Ask in chat</button>
  </div>;
}

function DataHub({ sel, setSel, tab, setTab, onToast, onOpenRun, showInherit, onSeed, project }) {
  const ds = DATASETS.find(d => d.id === sel) || DATASETS[0];
  const prof = PROFILES[ds.id];
  useVersionTick();
  const vs = fileVersions(ds.id);
  /* Derived from the authoritative link — a run appears here only if it lists
     this file as an input, so the run list and the version chip cannot disagree. */
  const runs = Object.values(RUNS).filter(r => (r.inputs || []).some(i => i[1] === ds.id));
  const outs = runs.flatMap(r => (r.outputs || []).map(o => OUTPUTS[o]));
  const [view, setView] = React.useState('table');
  const [editing, setEditing] = React.useState(false);
  const isDoc = !!(window.DOCS && DOCS[ds.id]);
  const TABS = [isDoc ? 'Document' : 'Preview', 'Versions', 'Where it came from'];
  const [listHid, setListHid] = useCollapse('hubListHid', false);
  return <div className={'hub' + (listHid ? ' listhid' : '')}>
    <FileTree project={project} sel={ds.id} onSel={id => { setSel(id); setTab(0); setEditing(false); }} onToast={onToast} onHide={() => setListHid(true)}/>
    <Grip prop="--hub-w" min={190} max={480} label="File list width" measure=".hublist" keep={360}/>
    <div className="mainpane" style={{ position:'relative' }}>
      {listHid && <Reveal side="left" label="Files" onClick={() => setListHid(false)}/>}
      <div className="objhead">
        <div className="crumb"><span>{project}</span><span className="sep">/</span><span>Files</span></div>
        <div className="objtitle">
          <h2>{ds.name}</h2>
          {!!vs.length && <span className="chip acc">v{vs[0].v}</span>}
          <QPill q={ds.quality}/>
          <span className="spacer"/>
          {isDoc ? <DownloadMenu name={ds.name} onToast={onToast}/> : <OpenIn ds={ds} onToast={onToast}/>}
        </div>
        <div className="tabs2">{TABS.map((t, i) => <button key={t} className={'tab2' + (i === tab ? ' on' : '')} onClick={() => setTab(i)}>{t}</button>)}</div>
      </div>

      <div className="objbody">
        {tab === 0 && isDoc && <>
          <DocEditor docId={ds.id} project={project} onToast={onToast} chrome={false}
            onOpenRun={ds.derivedFrom ? () => onOpenRun(ds.derivedFrom) : null}/>
          <div className="statgrid">{ds.stats.map(([k, v]) => <div key={k} className="stat"><span className="k2">{k}</span><div className="sv">{v}</div></div>)}</div>
        </>}
        {tab === 0 && !isDoc && <>
          <div className="card2 col" style={{ gap:'11px' }}>
            <div className="row ac" style={{ gap:'7px', flexWrap:'wrap', rowGap:'6px' }}>
              {[['table', 'Table'], ['columns', 'Columns'], ['plot', 'Plot']].map(([k, l]) =>
                <button key={k} className={'btn sm' + (view === k ? ' accent' : '')} onClick={() => setView(k)}>{l}</button>)}
              <span className="spacer"/>
              {editing
                ? <><span className="chip warn"><span className="dot"/>editing</span>
                    <button className="btn sm accent" onClick={() => { setEditing(false); onToast('Saved as v' + ((vs[0] ? vs[0].v : 1) + 1) + ' — the previous version stays, and runs that used it keep pointing at it.'); }}>Save as new version</button>
                    <button className="btn sm ghost" onClick={() => setEditing(false)}>Cancel</button></>
                : <button className="btn sm" onClick={() => { setEditing(true); setView('table'); }}><Icon name="gear" size={12}/>Edit</button>}
            </div>
            {view === 'plot'
              ? (prof && (prof.libsize || prof.pca || prof.volcano)
                  ? <Visualize ds={ds} onToast={onToast} onSeed={onSeed}/>
                  : <span className="hint">Nothing numeric to plot in this file. Open it in Jupyter or RStudio, or ask in chat for a specific view.</span>)
              : !prof ? <span className="hint">No preview captured for this file yet.</span>
              : view === 'columns' ? <ColumnProfile prof={prof}/>
              : <EditableTable prof={prof} editing={editing} onToast={onToast}/>}
            {editing && <span className="hint">Edits never overwrite: saving writes <b>v{(vs[0] ? vs[0].v : 1) + 1}</b> and leaves earlier versions intact, so a completed run always keeps the exact bytes it consumed.{prof && prof.rows.some(r => r.some(v => /^Control$/.test(v) || v === '—')) ? ' Amber cells are the ones the quality check called out.' : ''}</span>}
          </div>
          <FileChatEdit dsId={ds.id} onToast={onToast} version={vs[0] ? vs[0].v : 1}/>
          <div className="statgrid">{ds.stats.map(([k, v]) => <div key={k} className="stat"><span className="k2">{k}</span><div className="sv">{v}</div></div>)}</div>
        </>}

        {tab === 1 && <div className="col" style={{ gap:'12px' }}>
          {vs.length ? <>
            <div className="card2 col" style={{ gap:'0' }}>
              {vs.map((v, i) => <div key={v.v} className={'versrow' + (i === 0 ? ' cur' : '')}>
                <span className="vnum">v{v.v}</span>
                <div className="col" style={{ gap:'3px', flex:1, minWidth:0 }}>
                  <span style={{ fontSize:'12.5px', fontWeight:600 }}>{v.what}</span>
                  <span className="hint">{v.by} · {v.when}{v.usedBy ? ' · used by ' + v.usedBy : ''}</span>
                </div>
                {i === 0 ? <span className="chip ok"><span className="dot"/>current</span>
                  : <><button className="btn sm ghost" onClick={() => onToast('Diff v' + v.v + ' → v' + vs[0].v + ': changed cells and column-level differences, side by side.')}>Compare</button>
                      <button className="btn sm" onClick={() => onToast('Restored v' + v.v + ' as a new version — history is append-only, so nothing is lost.')}>Restore</button></>}
              </div>)}
            </div>
            <div className="card2 col" style={{ gap:'8px' }}>
              <span className="k2">Why versions matter here</span>
              <span className="hint">A run records the <b>exact version</b> it consumed. Editing a file therefore cannot change what a finished run means — and if a result looks wrong, you can see whether the input moved under it.</span>
              {runs.map(r => <div key={r.id} className="qline"><StatusPill s={r.status}/><span className="hint" style={{ flex:1 }}>{r.name}</span>
                <span className="chip">read v{(r.usedVersions || {})[ds.id]}</span></div>)}
            </div>
          </> : <div className="card2"><span className="hint">Only one version of this file exists. Editing it, or a run writing to it, creates the next one.</span></div>}
        </div>}

        {tab === 2 && <div className="col" style={{ gap:'12px' }}>
          <div className="two">
            <div className="card2 col" style={{ gap:'9px' }}>
              <span className="k2">Origin</span>
              <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'5px' }}><span className="chip">{ds.origin.type}</span><span className="hint" style={{ color:'var(--text)' }}>{ds.origin.label}</span></div>
              <span className="hint">Added by <b>{ds.origin.by}</b> on {ds.origin.when}. {ds.origin.note}</span>
              {ds.derivedFrom && <button className="btn sm" style={{ alignSelf:'flex-start' }} onClick={() => onOpenRun(ds.derivedFrom)}>Open the run that produced it →</button>}
              <span className="hint dim">Content hash {ds.hash} — the same file added twice links to one entry instead of two.</span>
              <div className="row ac" style={{ gap:'8px', flexWrap:'wrap', rowGap:'6px', borderTop:'1px solid var(--border)', paddingTop:'9px' }}>
                <span className="hint" style={{ fontWeight:600, color:'var(--text)' }}>Visible to</span>
                {['this project', 'the whole account'].map((s, i) => {
                  const on = (ds.scope === 'account') === (i === 1);
                  return <button key={s} className={'btn sm' + (on ? ' accent' : '')} onClick={() => on ? null : onToast(i === 1
                    ? 'Moved to shared/ — usable in any project without re-uploading, still one file with one version history.'
                    : 'Restricted to this project. Other projects keep a read-only reference to the version they used.')}>{s}</button>;
                })}
              </div>
              <span className="hint">{ds.scopeNote}</span>
            </div>
            <div className="card2 col" style={{ gap:'8px' }}>
              <span className="k2">Quality, at ingest</span>
              {ds.qnotes.map(([q, t], i) => <div key={i} className="qline"><QPill q={q} compact/><span>{t}</span></div>)}
              {showInherit && <span className="hint" style={{ borderTop:'1px solid var(--border)', paddingTop:'8px' }}>Anything produced from an amber input stays amber until a human clears it.</span>}
            </div>
          </div>
          <div className="card2 col" style={{ gap:'10px' }}>
            <div className="row ac"><span className="k2">What used it, and what came out</span><span className="spacer"/>
              <button className="btn sm ghost" onClick={() => onToast('Export → RO-Crate for deposit: source, checksums, versions, runs, parameters, software and outputs.')}>Export for deposit</button></div>
            <div className="col" style={{ gap:'7px' }}>
              {runs.length ? runs.map(r => <div key={r.id} className="qline" style={{ gap:'10px', flexWrap:'wrap' }}>
                <StatusPill s={r.status}/><span style={{ fontSize:'12.5px', fontWeight:600, flex:1, minWidth:'140px' }}>{r.name}</span>
                <span className="chip">read v{(r.usedVersions || {})[ds.id]}</span><span className="chip">{r.gates}</span>
                <button className="btn sm ghost" onClick={() => onOpenRun(r.id)}>Open run</button>
              </div>) : <span className="hint">Nothing has used this file yet.</span>}
            </div>
            {!!outs.length && <div className="col" style={{ gap:'6px', borderTop:'1px solid var(--border)', paddingTop:'9px' }}>
              <span className="k2">Produced</span>
              {outs.map(o => <div key={o.id} className="qline" style={{ gap:'9px', flexWrap:'wrap' }}>
                <span className="chip">{o.kind}</span><span className="mono" style={{ fontSize:'12px', flex:1, minWidth:'120px' }}>{o.name}</span>
                {showInherit && ds.quality === 'watch' && <span className="chip warn"><span className="dot"/>inherited: watch</span>}
                {o.isDataset && <button className="btn sm ghost" onClick={() => { setSel(o.id); setTab(0); }}>open file →</button>}
              </div>)}
            </div>}
          </div>
        </div>}
      </div>
    </div>
  </div>;
}
Object.assign(window, { DataHub, FileTree, OpenIn });
