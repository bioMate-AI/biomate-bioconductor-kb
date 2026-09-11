/* A report is a file, not a screen. This is the object that makes that true:
   downloadable in the formats people actually hand over, editable by hand,
   editable by asking, and versioned so an edit can never quietly rewrite what a
   finished run said. The same chat-edit affordance sits under data files. */

function DownloadMenu({ name, onToast, label, primary }) {
  const [open, setOpen] = React.useState(false);
  React.useEffect(() => { if (!open) return; const f = () => setOpen(false);
    window.addEventListener('click', f); return () => window.removeEventListener('click', f); }, [open]);
  return <span className="dlwrap" onClick={e => e.stopPropagation()}>
    <button className={'btn sm' + (primary ? ' accent' : '')} onClick={() => setOpen(o => !o)}>
      <Icon name="download" size={12}/>{label || 'Download'}<span className="dlchev"><Icon name="chevronDown" size={10}/></span></button>
    {open && <div className="dlmenu">
      {DOC_FORMATS.map(([k, l, sub]) => <button key={k} className="dlitem" onClick={() => { setOpen(false);
        onToast('Downloading ' + name.replace(/\.[a-z]+$/, '') + '.' + (k === 'zip' ? 'zip' : k) + ' — ' + sub + '.'); }}>
        <span className="dll">{l}</span><span className="hint">{sub}</span></button>)}
      <div className="dlfoot"><span className="hint">Every format carries the run id and the version you are looking at.</span></div>
    </div>}
  </span>;
}

/* Ask for a change, read exactly what it would do, accept or refuse it. */
function ChatEdit({ proposals, onApply, onToast, placeholder, render }) {
  const [q, setQ] = React.useState('');
  const [prop, setProp] = React.useState(null);
  const [used, setUsed] = React.useState([]);
  const [busy, setBusy] = React.useState(false);
  const pick = ask => {
    const pool = proposals.filter(p => used.indexOf(p.id) < 0);
    const hit = proposals.find(p => p.ask === ask) || pool[0] || proposals[0];
    setBusy(true); setProp(null);
    setTimeout(() => { setBusy(false); setProp({ ...hit, ask:ask || hit.ask }); }, 700);
  };
  return <div className="chatedit">
    <div className="row ac" style={{ gap:'7px' }}><Icon name="sparkles" size={13}/><span className="k2">Ask BioMate to edit this</span>
      <span className="spacer"/><span className="hint dim">nothing changes until you accept</span></div>
    <div className="ceask">
      <input value={q} onChange={e => setQ(e.target.value)} placeholder={placeholder}
        onKeyDown={e => { if (e.key === 'Enter' && q.trim()) { pick(q.trim()); setQ(''); } }}/>
      <button className="btn sm accent" disabled={!q.trim()} onClick={() => { pick(q.trim()); setQ(''); }}><Icon name="send" size={11}/></button>
    </div>
    <div className="row wrap" style={{ gap:'6px', rowGap:'6px' }}>
      {proposals.map(p => <button key={p.id} className={'exchip' + (used.indexOf(p.id) >= 0 ? ' done' : '')} onClick={() => pick(p.ask)}>
        {used.indexOf(p.id) >= 0 && <Icon name="check" size={10}/>}{p.ask}</button>)}
    </div>
    {busy && <span className="hint dim">Reading the document and drafting the change…</span>}
    {prop && <div className="propcard">
      <div className="row ac wrap" style={{ gap:'7px', rowGap:'5px' }}>
        <span className="chip acc">proposed edit</span>
        <span className="hint dim">“{prop.ask}”</span>
      </div>
      {render(prop)}
      <span className="hint"><b>Why:</b> {prop.why}</span>
      <div className="row wrap" style={{ gap:'7px', rowGap:'6px' }}>
        <button className="btn sm accent" onClick={() => { onApply(prop); setUsed(u => u.concat(prop.id)); setProp(null); }}>Accept — save as a new version</button>
        <button className="btn sm ghost" onClick={() => { setProp(null); onToast('Discarded. Nothing was written; the document is unchanged.'); }}>Reject</button>
        <button className="btn sm ghost" onClick={() => onToast('Ask again with a correction — “keep the number but drop the statistic”, “shorter”, “more cautious”.')}>Ask for a different version</button>
      </div>
    </div>}
  </div>;
}

function DocEditor({ docId, project, onToast, onOpenFile, onOpenRun, framed, chrome = true }) {
  const base = DOCS[docId];
  const key = 'bm-doc-' + docId;
  const [doc, setDoc] = React.useState(() => { try { const s = localStorage.getItem(key); if (s) return JSON.parse(s); } catch (e) {} return base; });
  const [vers, setVers] = React.useState(() => window.fileVersions(docId));
  const [editing, setEditing] = React.useState(false);
  const [dirty, setDirty] = React.useState(false);
  const bodyRef = React.useRef(null);
  React.useEffect(() => { setDoc(() => { try { const s = localStorage.getItem(key); if (s) return JSON.parse(s); } catch (e) {} return base; }); setVers(window.fileVersions(docId)); setEditing(false); setDirty(false); }, [docId]);
  const persist = (next, entry) => {
    setDoc(next);
    const nv = [{ v:vers[0].v + 1, what:entry, by:'A. Dike', when:'just now' }].concat(vers);
    setVers(nv);
    try { localStorage.setItem(key, JSON.stringify(next)); localStorage.setItem(key + '-v', JSON.stringify(nv)); } catch (e) {}
    notifyVersions();
  };
  const setPara = (sid, pi, text) => {
    setDoc(d => ({ ...d, sections:d.sections.map(s => s.id !== sid ? s : { ...s, p:s.p.map((p, i) => i === pi ? text : p) }) }));
    setDirty(true);
  };
  const apply = prop => {
    const next = { ...doc, sections:doc.sections.map(s => s.id !== prop.sec ? s : { ...s, p:s.p.map((p, i) => i === prop.pi ? prop.after : p) }) };
    persist(next, prop.ask);
    onToast('Applied and saved as v' + (vers[0].v + 1) + '. The previous version stays — the run’s original report is never overwritten.');
  };
  const revert = () => { try { localStorage.removeItem(key); localStorage.removeItem(key + '-v'); } catch (e) {}
    setDoc(base); setVers((window.VERSIONS || {})[docId] || []); notifyVersions();
    onToast('Back to v1 — the report exactly as the run wrote it.'); };

  return <div className={'doc' + (framed ? ' framed' : '')}>
    <div className="dochead">
      <div className="col" style={{ gap:'3px', minWidth:0 }}>
        <span className="doctitle">{doc.title}</span>
        <span className="hint dim">{doc.kicker} · {doc.by}</span>
      </div>
      <span className="spacer"/>
      {chrome && <span className="chip acc">v{vers[0].v}</span>}
      {vers.length > 1 && <button className="btn sm ghost" onClick={revert}>Revert to v1</button>}
      {editing
        ? <><button className="btn sm accent" onClick={() => { setEditing(false); if (dirty) { persist(doc, 'edited by hand'); setDirty(false);
              onToast('Saved as v' + (vers[0].v + 1) + '. Earlier versions stay readable, and the run still points at the one it produced.'); } }}>Save as new version</button>
            <button className="btn sm ghost" onClick={() => { setEditing(false); setDirty(false); }}>Done</button></>
        : <button className="btn sm" onClick={() => setEditing(true)}><Icon name="settings" size={11}/>Edit</button>}
      {chrome && <DownloadMenu name={doc.name} onToast={onToast} primary/>}
      {chrome && onOpenFile && <button className="btn sm ghost" title="This document in the project file list" onClick={() => onOpenFile(docId)}><Icon name="file" size={11}/>In Files</button>}
    </div>

    <div className="docsplit">
      <div className={'docpage' + (editing ? ' editing' : '')} ref={bodyRef}>
        {doc.sections.map(s => <section key={s.id} className="docsec">
          <h3>{s.h}</h3>
          {s.p.map((p, i) => <p key={i} contentEditable={editing} suppressContentEditableWarning
            onBlur={e => editing && setPara(s.id, i, e.target.innerText)}>{p}</p>)}
        </section>)}
        {editing && <span className="hint dim">Saving writes a new version — it does not overwrite what the run produced.</span>}
      </div>

      <div className="docside">
        <ChatEdit proposals={DOC_EDITS[docId] || []} onApply={apply} onToast={onToast}
          placeholder="e.g. shorten the methods, make the caveat harder to miss…"
          render={p => { const before = (doc.sections.find(s => s.id === p.sec) || { p:[] }).p[p.pi] || '';
            return <div className="diff">
              <div className="dline del"><span className="dtag">now · {(doc.sections.find(s => s.id === p.sec) || {}).h}</span>{before}</div>
              <div className="dline ins"><span className="dtag">proposed</span>{p.after}</div>
            </div>; }}/>
        <div className="card2 col" style={{ gap:'7px' }}>
          <span className="k2">Versions</span>
          {vers.map((v, i) => <div key={v.v} className="qline">
            <span className="chip">{i === 0 ? 'current' : 'v' + v.v}</span>
            <span className="col" style={{ gap:'2px', minWidth:0 }}><span style={{ fontSize:'12px' }}>{v.what}</span>
              <span className="hint dim">{v.by} · {v.when}</span></span>
          </div>)}
          {onOpenRun && <button className="btn sm ghost" style={{ alignSelf:'flex-start' }} onClick={onOpenRun}>Open the run that produced it →</button>}
        </div>
      </div>
    </div>
  </div>;
}

/* The same thing for a data file: ask, read the cell-level diff, accept. */
function FileChatEdit({ dsId, onToast, version }) {
  const props = FILE_EDITS[dsId] || [];
  if (!props.length) return null;
  return <ChatEdit proposals={props} onToast={onToast}
    placeholder="e.g. fill the missing batch values, drop the low-depth samples…"
    onApply={p => onToast('Applied and saved as v' + ((version || 1) + 1) + ' — ' + p.rows.length + ' change' + (p.rows.length > 1 ? 's' : '') + ' written. The previous version stays, and runs that read it keep pointing at it.')}
    render={p => <div className="diff celldiff">
      <div className="cdrow cdhd"><span>Row</span><span>Field</span><span>Now</span><span>Proposed</span></div>
      {p.rows.map((r, i) => <div key={i} className="cdrow">
        <span className="mono">{r[0]}</span><span className="mono">{r[1]}</span>
        <span className="del">{r[2]}</span><span className="ins">{r[3]}</span></div>)}
    </div>}/>;
}
Object.assign(window, { DocEditor, DownloadMenu, ChatEdit, FileChatEdit });
