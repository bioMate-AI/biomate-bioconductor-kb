const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "dataRail": false,
  "emptyState": "function modules",
  "laneHint": true,
  "inherit": true,
  "sidebar": "what you use",
  "chatEntry": "always in a project",
  "mlPlacement": "in project",
  "density": "regular",
  "theme": "light",
  "deepView": "full window"
}/*EDITMODE-END*/;

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [view, setView] = React.useState('chat');
  const [started, setStarted] = React.useState(false);
  const [seed, setSeed] = React.useState('');
  const [panel, setPanel] = React.useState(null);
  const [panelDs, setPanelDs] = React.useState('d1');
  const [sel, setSel] = React.useState('d1');
  const [tab, setTab] = React.useState(0);
  const [proj, setProj] = React.useState('Fibrosis target triage');
  const [open, setOpen] = React.useState({ 'Fibrosis target triage':true });
  const [sess, setSess] = React.useState('new');
  const [mlTab, setMlTab] = React.useState(0);
  const [thinLaunch, setThinLaunch] = React.useState(false);
  const [runScope, setRunScope] = React.useState(null);
  const [search, setSearch] = React.useState(null);
  const [mcase, setMcase] = React.useState(null);
  const [mOpen, setMOpen] = React.useState(null);
  /* Either side of the chat/run split can be put away, and the split gives up
     on its own when the stage is too narrow to hold both. An auto-hide is
     remembered as automatic, so widening the window gives the pane back — a
     hide the user chose is never undone by a resize. */
  const [chatHid, setChatHid] = React.useState(false);
  const autoHid = React.useRef(false);
  const stageRef = React.useRef(null);
  const hidRef = React.useRef(false);
  hidRef.current = chatHid;
  React.useEffect(() => {
    if (view !== 'chat' || !panel) return;
    const fit = () => {
      const w = stageRef.current ? stageRef.current.getBoundingClientRect().width : 0;
      if (!w) return;
      if (w < 880 && !hidRef.current) { autoHid.current = true; hidRef.current = true; setChatHid(true); }
      else if (w >= 880 && hidRef.current && autoHid.current) { autoHid.current = false; hidRef.current = false; setChatHid(false); }
    };
    fit();
    window.addEventListener('resize', fit);
    return () => window.removeEventListener('resize', fit);
  }, [view, panel]);
  /* Search is the instant lane: it answers, it does not configure. An example on
     the Search card therefore opens the answer surface directly. */
  const laneOf = s => { const h = (window.ROUTES || []).find(r => r.m.test(s || '')); return h ? h.lane : null; };
  const newChat = pname => { if (pname) { setProj(pname); setOpen(o => ({ ...o, [pname]:true })); } setSess('new'); setStarted(false); setPanel(null); setSeed(''); setThinLaunch(false); setView('chat'); };
  /* Filing is a consequence of intent, not a precondition for it. A new chat
     starts unfiled and BioMate proposes a project once there is a signal —
     attached data, or a goal that matches a project's own material. */
  const suggestProj = s => {
    if (!s || s.trim().length < 8) return null;
    const rules = [[/herg|admet|liabilit|scaffold|candidate|smiles|series 4|potenc|toxic/i, 'ADMET screen — series 4', 'its assay data and safety instructions'],
      [/fibrosis|counts|differential|treated|control|rna-?seq|expression|enrich/i, 'Fibrosis target triage', 'its counts matrix and design table'],
      [/cohort|endpoint|stratif|responder|trial/i, 'MG stratification', 'its cohort and its endpoint definition'],
      [/cryo|density|micrograph|particle|structure/i, 'Cryo-EM batch 12', 'its micrograph set']];
    const hit = rules.find(r => r[0].test(s));
    return hit ? { name:hit[1], why:hit[2] } : null;
  };
  const curProj = PROJECTS.find(p => p.name === proj) || PROJECTS[0];
  const curSess = PROJECTS.flatMap(p => p.chats).find(s => s.id === sess);
  const openSession = (s, pname) => { setSess(s.id); if (pname) setProj(pname); setStarted(!!s.run); setPanelStart(s.run ? 'report' : 'watch'); setPanel(s.run ? 'run' : null); setSeed(''); setView('chat'); };
  const [toast, setToast] = React.useState(null);
  const onToast = React.useCallback(m => { setToast(m); clearTimeout(window.__tt); window.__tt = setTimeout(() => setToast(null), 3400); }, []);

  const showAll = t.sidebar === 'every surface';
  /* Which account skills and experts are on, per project. One source: the
     Instructions selector writes it, the composer reads it. */
  const [addonsBy, setAddonsBy] = React.useState(() => Object.fromEntries(PROJECTS.map(p => {
    const cfg = (PROJECT_SETUP[p.name] || PROJECT_SETUP.default).addons || [];
    return [p.name, Object.fromEntries(cfg.map(a => [a[0], a[1]]))];
  })));
  const addons = addonsBy[proj] || {};
  const setAddon = (name, on) => { setAddonsBy(m => ({ ...m, [proj]:{ ...(m[proj] || {}), [name]:on } }));
    onToast(name + (on ? ' is on' : ' is off') + ' in ' + proj + ' — every session and run here, and it shows in the composer.'); };
  const caps = p => PROJECT_CAPS[p] || PROJECT_CAPS.default;
  /* A project earns its Models surface by running something that produces or
     calls a model. Before that it has none — and the workspace entry is how
     you find the surface at all. */
  const [earnedMl, setEarnedMl] = React.useState({});
  const [mlScope, setMlScope] = React.useState(null);
  const hasMl = p => caps(p).ml || !!earnedMl[p];
  const anyInd = PROJECTS.some(p => caps(p.name).ind);
  const experienced = PROJECTS.some(p => caps(p.name).runs.length);
  const goSeed = (s, mod) => {
    setSeedMod(mod ? MOD_WORD[mod] : null);
    if (laneOf(s) === 'Instant · search') { setSearch({ q:s }); return setView('search'); }
    /* A Models example opens its use-case page — what model, what it was given,
       what came back, and what it left behind. */
    if (laneOf(s) === 'Cloud · models' && window.modelCaseFor(s)) { setMcase({ q:s }); return setView('mcase'); }
    setSeed(s); setView('chat'); };
  /* Any artifact — a report included — is reachable in the project file list. */
  const openFile = id => {
    const owner = Object.keys(FILETREE).find(p => (FILETREE[p] || []).some(f => f.files.indexOf(id) >= 0));
    if (owner && owner !== 'default') { setProj(owner); setOpen(o => ({ ...o, [owner]:true })); }
    setSel(id); setTab(0); setView('data');
  };
  const [panelStart, setPanelStart] = React.useState('watch');
  /* The domain the router matched, so the run panel opens on that kind of run. */
  const [runDom, setRunDom] = React.useState(null);
  const [runMod, setRunMod] = React.useState(null);
  /* The modality a card was set to when its example was clicked. It outranks
     text inference — until the user edits the sentence, which makes it theirs. */
  const [seedMod, setSeedMod] = React.useState(null);
  const typeSeed = v => { setSeedMod(null); setSeed(v); };
  const send = () => {
    if (!seed.trim()) return onToast('Type something, or start from a module on the new-chat surface.');
    if (laneOf(seed) === 'Instant · search') { setSearch({ q:seed }); setSeed(''); return setView('search'); }
    const hit = (window.ROUTES || []).find(r => r.m.test(seed));
    /* The composer and a module example must reach the same surface for the same
       sentence: a model request with a worked case opens that case either way. */
    if (hit && /models/.test(hit.lane) && window.modelCaseFor(seed)) { setMcase({ q:seed }); setSeed(''); return setView('mcase'); }
    setRunDom(hit ? hit.dom : null);
    setRunMod(seedMod || modalityOf(seed));
    const isModels = hit && /models/.test(hit.lane);
    if (isModels && !hasMl(proj)) {
      setEarnedMl(e => ({ ...e, [proj]:true }));
      onToast('First model work in ' + proj + ' — a Models surface now appears under it. Nothing has run yet; the run is configured below.');
    } else {
      onToast('Nothing has run yet — the panel opens on Workflow settings, and the run starts when you confirm it.');
    }
    setStarted(true); setPanelStart('cfg'); setPanel('run'); setSeed('');
  };
  const openData = id => { setPanelDs(id); setPanel('data'); };
  const openHub = id => { setSel(id || panelDs); setTab(2); setView('data'); };

  const NAV = [
    { id:'chat', icon:'plus', label:'New chat',
      on:() => newChat('Unfiled (scratch)') },
    { id:'run', icon:'beaker', label:'Workflows', on:() => { setRunScope(null); setView('run'); } },
    { id:'models', icon:'cells', label:'Models', neu:true, on:() => { setMlScope(null); setMlTab(4); setView('models'); } },
    (showAll || anyInd) && { id:'ind', icon:'file', label:'IND Report', on:() => onToast(showAll && !anyInd ? 'Shown because the sidebar tweak is set to every surface — no project here is heading for a submission.' : 'Existing surface — reached from the project whose runs feed it.') }
  ].filter(Boolean);

  const [sideHid, setSideHid] = useCollapse('sideHid', false);
  /* A hidden panel must be recoverable: remember what was open so the reveal
     chip can put it back exactly as it was. */
  const [lastPanel, setLastPanel] = React.useState(null);
  const hidePanel = () => { setLastPanel({ mode:panel, ds:panelDs, at:panelStart }); setPanel(null); };
  const showPanel = () => { if (!lastPanel) return; setPanelDs(lastPanel.ds); setPanelStart(lastPanel.at || 'watch'); setPanel(lastPanel.mode); };
  return <div data-theme={t.theme === 'dark' ? 'dark' : 'light'} className={'app' + (t.dataRail ? ' rail' : '') + (t.density === 'tight' ? ' density-tight' : '') + (sideHid ? ' sidehid' : '')}>
    <div className="sidebar">
      <div className="sidebrand"><img className="brand-logo" src="images/biomate-logo-trim.png" alt="BioMate"/></div>
      <div className="sidescroll">
        <div className="sidecap">Workspace<span className="spacer"/><button className="zoomb panehide" title="Hide the sidebar" onClick={() => setSideHid(true)}><Icon name="chevronLeft" size={11}/></button></div>
        <div className="sidenav">
          {NAV.map(n => <button key={n.id} className={'navitem' + (view === n.id ? ' on' : '')} onClick={n.on}>
            <span className="ni"><Icon name={n.icon} size={15}/></span>
            <span style={{ minWidth:0 }}>{n.label}</span>
            {n.badge && <span className="nb">{n.badge}</span>}
            {n.hide && <span className="hidex" role="button" title="Hide this from the sidebar" onClick={e => { e.stopPropagation(); n.hide(); }}><Icon name="x" size={11}/></span>}
          </button>)}
        </div>
        <div className="sidecap"><Icon name="folder" size={11}/> Projects</div>
        <div className="projlist">
          {PROJECTS.map(pr => { const isOpen = !!open[pr.name]; return <React.Fragment key={pr.name}>
            <button className={'projitem' + (isOpen ? ' open' : '')} onClick={() => setOpen(o => ({ ...o, [pr.name]:!isOpen }))}>
              <span className={'pchev' + (isOpen ? ' on' : '')}><Icon name="chevronRight" size={12}/></span>
              <Icon name="folder" size={13}/><span className="pname2">{pr.name}</span>
            </button>
            {isOpen && <div className="projkids">
              {<button className={'kid kid-data' + (view === 'data' && proj === pr.name ? ' on' : '')}
                onClick={() => { setProj(pr.name); setView('data'); }}>
                <Icon name="table" size={12}/>Files<span className="kb">{(FILETREE[pr.name] || FILETREE.default).reduce((n, f) => n + f.files.length, 0)}</span>
              </button>}
              {(showAll || !!caps(pr.name).runs.length) && <button className={'kid kid-data' + (view === 'run' && runScope === pr.name ? ' on' : '')}
                onClick={() => { setProj(pr.name); setRunScope(pr.name); setView('run'); }}>
                <Icon name="beaker" size={11}/>Runs{!!(PROJECT_RUNS[pr.name] || []).length && <span className="kb">{(PROJECT_RUNS[pr.name] || []).length}</span>}
              </button>}
              {(showAll || hasMl(pr.name)) && <button className={'kid kid-data' + (view === 'models' && mlScope === pr.name ? ' on' : '')}
                onClick={() => { setProj(pr.name); setMlScope(pr.name); setView('models'); }}>
                <Icon name="cells" size={12}/>Models{hasMl(pr.name) && <span className="kb">{caps(pr.name).ml ? REGISTRY.length : 1}</span>}
              </button>}
              {(showAll || caps(pr.name).ind) && <button className="kid kid-data"
                onClick={() => { setProj(pr.name); onToast('The submission belongs to this project — its numbers trace to this project’s runs, so it is a project deliverable, not a workspace feature.'); }}>
                <Icon name="file" size={12}/>IND report
              </button>}
              <button className={'kid kid-data' + (view === 'setup' && proj === pr.name ? ' on' : '')}
                onClick={() => { setProj(pr.name); setView('setup'); }}>
                <Icon name="file" size={12}/>Instructions
              </button>
              {pr.chats.map(s => <button key={s.id} className={'kid' + (view === 'chat' && sess === s.id ? ' on' : '')} onClick={() => openSession(s, pr.name)}>
                <span className="cdot" style={s.run ? { background:'var(--ok)' } : null}/><span className="pname2">{s.title}</span>
                {!!s.data.length && <span className="kb kb-q">{s.data.length}</span>}
              </button>)}
              {!pr.chats.length && <span className="kid empty">No chats yet</span>}
            </div>}
          </React.Fragment>; })}
          <button className="projitem dim" onClick={() => onToast('Existing surface — unchanged by this proposal.')}><span className="pchev"/><Icon name="plus" size={13}/>New project</button>
        </div>
      </div>
      <button className="sidesettings" onClick={() => onToast('Settings & workspace connections: data sources, API keys, skills and integrations live here. They support research work; they are not a separate research flow.')}><Icon name="gear" size={14}/>Settings &amp; workspace</button>
      <div className="sidefoot"><span className="av">AD</span><span>A. Dike<br/><span className="dim">early access</span></span>
        <span className="themetog" title="Light or dark">
          <button className={t.theme !== 'dark' ? 'on' : ''} onClick={() => setTweak('theme', 'light')} title="Light"><Icon name="sun" size={12}/></button>
          <button className={t.theme === 'dark' ? 'on' : ''} onClick={() => setTweak('theme', 'dark')} title="Dark"><Icon name="moon" size={12}/></button>
        </span></div>
    </div>

    {t.dataRail && <div className="datarail">
      <span className="rcap">DATA</span>
      {DATASETS.map(d => <button key={d.id} className={'railbtn' + (panel === 'data' && panelDs === d.id ? ' on' : '')} title={d.name} onClick={() => openData(d.id)}>
        {d.init}<span className="rb" style={{ background:QUAL[d.quality].c }}/>
      </button>)}
      <button className="railbtn" style={{ borderStyle:'dashed', color:'var(--accent)' }} onClick={() => onToast('Ingest panel: files, URL, or public repository browse — with a quality card on arrival.')}>＋</button>
    </div>}

    <Grip prop="--sidebar-w" min={176} max={420} label="Sidebar width" keep={420}/>

    <div ref={stageRef} className={'stage' + (view === 'chat' && panel ? (chatHid ? ' chatrail' : ' withpanel') : '')} style={{ position:'relative' }}>
      {sideHid && <Reveal side="left" label="Sidebar" onClick={() => setSideHid(false)}/>}
      {view === 'setup' && <ProjectSetup project={proj} onToast={onToast} onOpenData={() => { setTab(0); setView('data'); }} addons={addons} setAddon={setAddon}/>}
      {view === 'data' && <DataHub sel={sel} setSel={setSel} tab={tab} setTab={setTab} onToast={onToast} showInherit={t.inherit} onSeed={goSeed}
        project={proj}
        onOpenRun={() => { setView('chat'); setStarted(true); setPanel('run'); }}/>}
      {view === 'run' && <RunHistory scope={runScope} setScope={setRunScope} onToast={onToast} onOpenData={() => { setTab(0); setView('data'); }} deepDefault={t.deepView === 'side drawer' ? 'drawer' : 'full'} onOpenFile={openFile}
        onOpenChat={() => { const c = (PROJECTS.find(p => p.name === proj) || {}).chats || []; c.length ? openSession(c[0], proj) : setView('chat'); }}
        onOpenModels={() => { setMlTab(0); setView('models'); }}/>}
      {view === 'conn' && <Connectors onToast={onToast}/>}
      {view === 'search' && search && <SearchAnswer query={search.q} track={search.track} project={proj} onToast={onToast}
        onBack={() => setView('chat')} onOpenFile={openFile} onOpenProject={() => { setTab(0); setView('data'); }}
        onSaveFile={() => onToast('Saved into ' + proj + ' as a document — with the retrieval record attached, so the answer can be re-derived rather than just re-read.')}
        onRun={c => { setStarted(true); setPanelStart('cfg'); setPanel('run'); setView('chat');
          onToast('The search stays as evidence; this is a separate run, configured below and not started yet.'); }}/>}
      {view === 'mcase' && mcase && <ModelCase query={mcase.q} track={mcase.track} project={proj} onToast={onToast}
        onBack={() => setView('chat')} onOpenFile={openFile}
        onOpenProject={() => { setTab(0); setView('data'); }}
        onOpenModels={() => { setMOpen(null); setMlTab(4); setMlScope(proj); setView('models'); }}
        onOpenModel={id => { setMOpen(id); setView('models'); }}
        onOpenRun={() => { setStarted(true); setPanelStart('cfg'); setPanel('run'); setView('chat');
          onToast('Configured below, not started — a model run is a run, with the same gates and the same audit trail.'); }}/>}
      {view === 'models' && <Models project={mlScope || 'Workspace'} onToast={onToast} tab={mlTab} setTab={setMlTab}
        scope={mlScope ? 'project' : 'workspace'}
        unused={!!mlScope && !hasMl(mlScope)} onOpenRun={() => setView('run')} onOpenData={() => { setTab(0); setView('data'); }}
        openModel={mOpen} clearOpenModel={() => setMOpen(null)}/>}
      {view === 'chat' && <>
        {(!panel || !chatHid) && <ChatView started={started} seed={seed} setSeed={typeSeed} onSend={send} onOpenData={openData} onPick={goSeed}
          session={curSess} project={proj} onOpenProjectData={() => { setTab(0); setView('data'); }}
          scoped={t.chatEntry === 'always in a project'} onPromote={() => onToast('Promote: name it, and the scratch chat, its files and any run it started move into the new project unchanged.')} instrCount={(PROJECT_SETUP[proj] || PROJECT_SETUP.default).rules.length} onOpenInstr={() => setView('setup')}
          empty={t.emptyState === 'domain tiles' ? 'tiles' : t.emptyState === 'function modules' ? 'modules' : 'chips'} laneHint={t.laneHint}
          thin={thinLaunch} setThin={setThinLaunch}
          suggest={proj === 'Unfiled (scratch)' ? suggestProj(seed) : null}
          onFile={name => { setProj(name); setOpen(o => ({ ...o, [name]:true })); onToast('Filed into ' + name + '. Its files and instructions are now in context — nothing has run.'); }}
          projectOn={addons} onDeviate={(name, on) => onToast(name + (on ? ' on' : ' off') + ' for this question only — the project default is unchanged.')} onToast={onToast}
          revealPanel={!panel && lastPanel ? showPanel : null} revealLabel={lastPanel && lastPanel.mode === 'run' ? 'Run panel' : 'Data panel'}
          onHide={panel ? () => { autoHid.current = false; setChatHid(true); } : null}/>}
        {panel && chatHid && <div className="chatstub"><Reveal side="left" label="Chat" at="static" onClick={() => {
          autoHid.current = false;
          /* Restoring the chat on a stage that cannot hold both panes swaps which
             side is put away rather than building a split that clips. */
          const w = stageRef.current ? stageRef.current.getBoundingClientRect().width : 0;
          if (w && w < 880) { setChatHid(false); return hidePanel(); }
          const room = w - 6 - 380;
          if (room > 320) writePane('--panel-w', Math.min(room, readPanes()['--panel-w'] || room));
          setChatHid(false);
        }}/></div>}
        {panel && !chatHid && <Grip prop="--panel-w" min={320} max={860} invert label={panel === 'run' ? 'Run panel width' : 'Panel width'} keep={panel === 'run' ? 320 : 340}/>}
        {panel === 'run'
          ? <RunSurface project={proj} onToast={onToast} onOpenData={() => { setTab(0); setView('data'); }}
              onOpenModels={() => { setMlTab(0); setView('models'); }} onBack={hidePanel} onOpenFile={openFile}
              startAt={panelStart} deepDefault={t.deepView === 'side drawer' ? 'drawer' : 'full'} dom={runDom} mod={runMod}/>
          : panel && <RightPanel mode={panel} setMode={setPanel} dsId={panelDs} onClose={hidePanel}
            onOpenFull={() => openHub(panelDs)} onToast={onToast} showInherit={t.inherit}/>}
      </>}
    </div>

    {toast && <div className="toast">{toast}</div>}

    <TweaksPanel>
      <TweakSection label="Part 1 — capability legibility"/>
      <TweakRadio label="New-chat surface" value={t.emptyState} options={['function modules', 'domain tiles', 'today\u2019s chips']} onChange={v => setTweak('emptyState', v)}/>
      <TweakToggle label="Composer lane preview (B1)" value={t.laneHint} onChange={v => setTweak('laneHint', v)}/>
      <TweakSection label="Part 2 — data centroid"/>
      <TweakToggle label="Persistent data rail (C2)" value={t.dataRail} onChange={v => setTweak('dataRail', v)}/>
      <TweakToggle label="Show badge inheritance" value={t.inherit} onChange={v => setTweak('inherit', v)}/>
      <TweakSection label="Part 3 — working surfaces (A2 & A3)"/>
      <TweakRadio label="New chat" value={t.chatEntry} options={['always in a project', 'free-floating']} onChange={v => setTweak('chatEntry', v)}/>
      <TweakRadio label="Sidebar shows" value={t.sidebar} options={['what you use', 'every surface']} onChange={v => setTweak('sidebar', v)}/>
      <TweakRadio label="Models surface" value={t.mlPlacement} options={['in project', 'global']} onChange={v => { setTweak('mlPlacement', v); if (view === 'models') setView('models'); }}/>
      <TweakSection label="Part 3 — step deep-view & evidence"/>
      <TweakRadio label="A step opens as" value={t.deepView} options={['full window', 'side drawer']} onChange={v => setTweak('deepView', v)}/>
      <TweakSection label="Display"/>
      <TweakRadio label="Appearance" value={t.theme} options={['light', 'dark']} onChange={v => setTweak('theme', v)}/>
      <TweakRadio label="Density" value={t.density} options={['regular', 'tight']} onChange={v => setTweak('density', v)}/>
    </TweaksPanel>
  </div>;
}
Object.assign(window, { App });
