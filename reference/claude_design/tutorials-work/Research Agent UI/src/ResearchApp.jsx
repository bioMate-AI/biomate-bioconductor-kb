// ResearchApp — top-level state + scenario engine + Tweaks panel.
//
// The engine walks `scenario.tape` event-by-event:
//   • Non-await events apply their state mutation and schedule the next
//     event after `t * speedFactor` ms.
//   • `await` events halt the tape until a matching user action (or a
//     countdown that owns its label) is dispatched.
//
// Countdowns started via `startCountdown` tick once per second and
// dispatch their `label` when they hit zero. Any user click on the
// chat card clears the countdown.

const { useState, useEffect, useRef, useCallback } = React;

// ── Defaults persisted via the Tweaks host ──────────────────────
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "scenarioId": "rnaseq",
  "speed": 1.0,
  "theme": "light",
  "density": "comfortable",
  "panelWidth": 530,
  "sidebarMode": "auto",
  "panelOpen": true,
  "pillPlacement": "after-marker",
  "collapseThreshold": 3,
  "showTs": false,
  "planEditDefault": true,
  "phaseExpandMode": "inline",
  "comparePlacement": "inline",
  "pilotDefaultOn": true,
  "countdownSeconds": 10,
  "autoProceedRequiresHighConf": true,
  "autoStartScenario": false
}/*EDITMODE-END*/;

// Maps each `await` label to the user-action labels that satisfy it.
// Actions that are NOT in this list trigger a toast (the prototype
// always continues the happy path; halting branches are out of scope).
const AWAIT_ACCEPTS = {
  'pilot_started':    ['run_pilot'],
  'promote_or_stop':  ['promote_full', 'pilot_promote_auto'],
  'apply_fixes':      ['apply_fixes'],
  'compare_decision': ['use_b', 'use_a', 'compare_use_b_auto'],
  'retry_or_skip':    ['retry'],
  'plan_locked':      ['plan_lock_user', 'plan_auto_lock'],
};

// Maps `action` label → label dispatched into the engine's await pipeline.
// (Buttons in cards emit a granular label; we normalize for await matching.)
function dispatchEquivalent(action) { return action; }

// Map research-scenario id → v1 SCENARIOS id, so the v1 WorkflowPanel
// renders the closest matching pipeline alongside our research chat.
// Identity for the 4 v1 ids — they are their own panel scenario.
const V1_SCENARIO_MAP = {
  rnaseq:     'nfcore',
  drugscreen: 'drugscreen',
  variant:    'gatk',
  cryosparc:  'cryosparc',
  gatk:       'gatk',
  admet:      'admet',
  nfcore:     'nfcore',
};

// ───────────────────────────────────────────────────────────────
// App
// ───────────────────────────────────────────────────────────────
function ResearchApp() {
  // Load persisted tweaks
  const saved = (() => { try { return JSON.parse(localStorage.getItem('biomate-research-tweaks') || 'null'); } catch { return null; } })();
  const init = { ...TWEAK_DEFAULTS, ...(saved || {}) };

  // Tweak / config state
  const [scenarioId, setScenarioId]       = useState(init.scenarioId);
  const [speed, setSpeed]                 = useState(init.speed);
  const [theme, setTheme]                 = useState(init.theme);
  const [density, setDensity]             = useState(init.density);
  const [panelWidth, setPanelWidth]       = useState(init.panelWidth);
  const [sidebarMode, setSidebarMode]     = useState(init.sidebarMode);
  const [panelOpen, setPanelOpen]         = useState(init.panelOpen);
  const [pillPlacement, setPillPlacement] = useState(init.pillPlacement);
  const [collapseThreshold, setCollapseThreshold] = useState(init.collapseThreshold);
  const [showTs, setShowTs]               = useState(init.showTs);
  const [planEditDefault, setPlanEditDefault] = useState(init.planEditDefault);
  const [phaseExpandMode, setPhaseExpandMode] = useState(init.phaseExpandMode);
  const [comparePlacement, setComparePlacement] = useState(init.comparePlacement);
  const [pilotDefaultOn, setPilotDefaultOn] = useState(init.pilotDefaultOn);
  const [countdownSeconds, setCountdownSeconds] = useState(init.countdownSeconds);
  const [tweaksVisible, setTweaksVisible] = useState(false);

  // Engine state
  const scenario = window.RESEARCH_SCENARIOS[scenarioId];
  const [head, setHead] = useState(0);
  const [chatEvents, setChatEvents] = useState([]);  // [{kind:'line'|'card', ...}]
  const [planItems, setPlanItems] = useState([]);    // current rendered plan
  const [planShown, setPlanShown] = useState(false);
  const [planEditing, setPlanEditing] = useState(false);
  const [planCollapsed, setPlanCollapsed] = useState(false);
  const [phaseStates, setPhaseStates] = useState({});
  const [runState, setRunState] = useState('idle');
  const [awaitingLabel, setAwaitingLabel] = useState(null);
  const [countdowns, setCountdowns] = useState({});  // label → {remaining, total}
  const [openPhaseId, setOpenPhaseId] = useState(null);
  const [dismissedCards, setDismissedCards] = useState({});
  const [comparePanelData, setComparePanelData] = useState(null); // Surface 4 panel variant
  const [modal, setModal] = useState(null);  // {kind:'phaseTrace', ...}
  const [toast, setToast] = useState(null);

  // ── State the v1 panel + the Tour expect to drive ─────────────
  // The Tour scripts in Tour.jsx are written against v1 scenario ids
  // (cryosparc / gatk / admet / nfcore) and v1 toggles (qcHalt etc.).
  // We keep a small mirror of that state so tutorials work unchanged.
  const [v1Scenario, setV1Scenario] = useState(V1_SCENARIO_MAP[init.scenarioId] || 'nfcore');
  const [v1RunState, setV1RunState] = useState('idle');
  const [qcHalt, setQcHalt] = useState(false);
  const [licenseGate, setLicenseGate] = useState(false);
  const [blocked, setBlocked] = useState(false);
  const [disambig, setDisambig] = useState(false);
  const [watcherAttached, setWatcherAttached] = useState(true);

  // Tour-style refs for engine internals
  const tapeIdx = useRef(0);
  const stepTimer = useRef(null);
  const countdownTimers = useRef({});

  // ── Persist tweaks ─────────────────────────────────────────────
  useEffect(() => {
    const t = {
      scenarioId, speed, theme, density, panelWidth, sidebarMode, panelOpen,
      pillPlacement, collapseThreshold, showTs, planEditDefault, phaseExpandMode,
      comparePlacement, pilotDefaultOn, countdownSeconds,
    };
    localStorage.setItem('biomate-research-tweaks', JSON.stringify(t));
  }, [scenarioId, speed, theme, density, panelWidth, sidebarMode, panelOpen,
      pillPlacement, collapseThreshold, showTs, planEditDefault, phaseExpandMode,
      comparePlacement, pilotDefaultOn, countdownSeconds]);

  useEffect(() => { document.documentElement.style.setProperty('--panel-w', panelWidth + 'px'); }, [panelWidth]);
  useEffect(() => { document.documentElement.className = theme === 'dark' ? 'theme-dark' : ''; }, [theme]);
  useEffect(() => { document.body.classList.toggle('density-compact', density === 'compact'); }, [density]);

  // ── Expose modal opener + scenario controls for the Tour ──────
  // Tour steps use these in setup() to drive the scenario directly so the
  // user never has to click in-app buttons mid-tour and timing always matches.
  useEffect(() => {
    window.__openTourModal = (kind, payload) => setModal({ ...(payload || {}), kind });
    window.__closeTourModal = () => setModal(null);
    window.__tourAction = (label) => userAction(label);
    window.__tourSetScenario = (id) => setScenarioId(id);
    window.__tourFFTo = (markerId) => tourFFTo(markerId);
    window.__tourReset = () => restartScenario();
    return () => {
      delete window.__openTourModal;
      delete window.__closeTourModal;
      delete window.__tourAction;
      delete window.__tourSetScenario;
      delete window.__tourFFTo;
      delete window.__tourReset;
    };
  }, [userAction, tourFFTo, restartScenario]);

  // ── Edit-mode handshake with host toolbar ─────────────────────
  useEffect(() => {
    const onMsg = (e) => {
      if (!e.data || typeof e.data !== 'object') return;
      if (e.data.type === '__activate_edit_mode')   setTweaksVisible(true);
      if (e.data.type === '__deactivate_edit_mode') setTweaksVisible(false);
    };
    window.addEventListener('message', onMsg);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', onMsg);
  }, []);
  // When the panel's own close button hides Tweaks, notify the host so the
  // toolbar toggle flips off in lockstep — otherwise the user can't easily
  // find their way back to reopening it.
  const closeTweaks = useCallback(() => {
    setTweaksVisible(false);
    window.parent.postMessage({ type: '__edit_mode_dismissed' }, '*');
  }, []);
  const setTweak = (patch) => {
    if ('scenarioId' in patch) setScenarioId(patch.scenarioId);
    if ('speed' in patch) setSpeed(patch.speed);
    if ('theme' in patch) setTheme(patch.theme);
    if ('density' in patch) setDensity(patch.density);
    if ('panelWidth' in patch) setPanelWidth(patch.panelWidth);
    if ('sidebarMode' in patch) setSidebarMode(patch.sidebarMode);
    if ('pillPlacement' in patch) setPillPlacement(patch.pillPlacement);
    if ('collapseThreshold' in patch) setCollapseThreshold(patch.collapseThreshold);
    if ('showTs' in patch) setShowTs(patch.showTs);
    if ('planEditDefault' in patch) setPlanEditDefault(patch.planEditDefault);
    if ('phaseExpandMode' in patch) setPhaseExpandMode(patch.phaseExpandMode);
    if ('comparePlacement' in patch) setComparePlacement(patch.comparePlacement);
    if ('pilotDefaultOn' in patch) setPilotDefaultOn(patch.pilotDefaultOn);
    if ('countdownSeconds' in patch) setCountdownSeconds(patch.countdownSeconds);
    window.parent.postMessage({ type: '__edit_mode_set_keys', edits: patch }, '*');
  };

  // ── Toast helper ──────────────────────────────────────────────
  const showToast = (msg) => {
    setToast({ msg, id: Date.now() });
    setTimeout(() => setToast(null), 2600);
  };

  // ── Reset everything when scenario changes ────────────────────
  const restartScenario = useCallback(() => {
    // Clear all timers
    if (stepTimer.current) { clearTimeout(stepTimer.current); stepTimer.current = null; }
    Object.values(countdownTimers.current).forEach(clearInterval);
    countdownTimers.current = {};

    setHead(0); tapeIdx.current = 0;
    setChatEvents([]);
    setPlanItems([]);
    setPlanShown(false);
    setPlanEditing(false);
    setPlanCollapsed(false);
    setPhaseStates({});
    setRunState('idle');
    setAwaitingLabel(null);
    setCountdowns({});
    setOpenPhaseId(null);
    setDismissedCards({});
    setComparePanelData(null);
    setModal(null);
  }, [scenario, pilotDefaultOn]);

  useEffect(() => {
    restartScenario();
    setV1Scenario(V1_SCENARIO_MAP[scenarioId] || 'nfcore');
  }, [scenarioId]);

  // ── Engine: process one event ─────────────────────────────────
  const applyEvent = useCallback((ev) => {
    switch (ev.kind) {
      case 'planShow':
        setPlanShown(true);
        setPlanItems(scenario.initialPlan.map(it => ({ ...it })));
        if (ev.editing && planEditDefault) {
          setPlanEditing(true);
          startCountdown('plan_auto_lock', countdownSeconds);
        }
        break;
      case 'planUpdate':
        setPlanItems(items => items.map(it =>
          it.id === ev.id ? { ...it, status: ev.status, meta: ev.meta || it.meta } : it
        ));
        break;
      case 'planFail':
        setPlanItems(items => items.map(it =>
          it.id === ev.id ? { ...it, status: 'failed', failReason: ev.reason } : it
        ));
        break;
      case 'planUnfail':
        setPlanItems(items => items.map(it =>
          it.id === ev.id ? { ...it, status: ev.status, failReason: null } : it
        ));
        break;
      case 'planLock':
        setPlanEditing(false);
        clearCountdown('plan_auto_lock');
        break;
      case 'chatLine':
        setChatEvents(evs => [...evs, {
          kind: 'line', s: ev.s, m: ev.m, k: ev.k || null,
          rationaleId: ev.rationaleId || null,
          ts: ev.ts || fmtClock(),
          entering: true,
        }]);
        break;
      case 'collapseLines':
        // marker handled in ChatStream's collapse logic; no engine action needed
        break;
      case 'phaseUpdate':
        setPhaseStates(ps => ({ ...ps, [ev.id]: ev.status }));
        if (ev.status === 'running') setOpenPhaseId(ev.id);
        break;
      case 'runState':
        setRunState(ev.value);
        break;
      case 'showCard':
        if (ev.card === 'comparison' && comparePlacement === 'panel') {
          setComparePanelData(ev.data);
        } else {
          setChatEvents(evs => [...evs, {
            kind: 'card', card: ev.card, data: ev.data, _id: Date.now() + '_' + Math.random(),
          }]);
        }
        break;
      case 'dismissCard':
        setDismissedCards(d => ({ ...d, [ev.card]: true }));
        break;
      case 'startCountdown':
        startCountdown(ev.label, ev.seconds || countdownSeconds);
        break;
      case 'await':
        setAwaitingLabel(ev.label);
        break;
      case 'marker':
        // No-op during normal play. Tours use markers as fast-forward targets.
        break;
      default:
        break;
    }
  }, [scenario, comparePlacement, pilotDefaultOn, planEditDefault, countdownSeconds]);

  // ── Tour fast-forward: jump engine state to a named marker ────
  // Walks the tape from the current head forward, applying each event
  // synchronously (no delays), until it hits `{kind:'marker', id:X}`.
  // Awaits are skipped during fast-forward so the user doesn't need to
  // press any in-app decision buttons — the tour drives everything.
  const tourFFTo = useCallback((markerId) => {
    const tape = scenario.tape;
    if (stepTimer.current) { clearTimeout(stepTimer.current); stepTimer.current = null; }
    // Clear any active countdowns (we're jumping past them)
    Object.keys(countdownTimers.current).forEach(l => clearInterval(countdownTimers.current[l]));
    countdownTimers.current = {};
    setCountdowns({});
    setAwaitingLabel(null);
    // Walk tape applying events instantly
    let i = tapeIdx.current;
    const limit = tape.length;
    while (i < limit) {
      const ev = tape[i];
      if (ev.kind === 'marker' && ev.id === markerId) { i++; break; }
      if (ev.kind === 'await') { i++; continue; } // skip await pauses
      if (ev.kind === 'startCountdown') { i++; continue; } // skip countdowns
      applyEventRef.current(ev);
      i++;
    }
    tapeIdx.current = i;
    setHead(i);
  }, [scenario]);

  // ── Engine: walk the tape ─────────────────────────────────────
  const speedRef = useRef(speed);
  useEffect(() => { speedRef.current = speed; }, [speed]);
  const applyEventRef = useRef(applyEvent);
  useEffect(() => { applyEventRef.current = applyEvent; }, [applyEvent]);

  const runStep = useCallback(() => {
    const tape = scenario.tape;
    const idx = tapeIdx.current;
    if (idx >= tape.length) return;
    const ev = tape[idx];

    if (ev.kind === 'await') {
      applyEventRef.current(ev);
      return; // halt; resumed by userAction
    }

    const delay = Math.max(0, (ev.t || 0) * speedRef.current);
    stepTimer.current = setTimeout(() => {
      applyEventRef.current(ev);
      tapeIdx.current = idx + 1;
      setHead(idx + 1);
      runStep();
    }, delay);
  }, [scenario]);

  // Kick off the engine on scenario change
  useEffect(() => {
    if (stepTimer.current) { clearTimeout(stepTimer.current); stepTimer.current = null; }
    // Slight delay so initial render finishes
    const t = setTimeout(() => { runStep(); }, 200);
    return () => { clearTimeout(t); if (stepTimer.current) clearTimeout(stepTimer.current); };
  }, [scenarioId, runStep]);

  // ── Countdowns ────────────────────────────────────────────────
  const startCountdown = useCallback((label, seconds) => {
    setCountdowns(cd => ({ ...cd, [label]: { remaining: seconds, total: seconds }}));
    if (countdownTimers.current[label]) clearInterval(countdownTimers.current[label]);
    countdownTimers.current[label] = setInterval(() => {
      setCountdowns(cd => {
        const c = cd[label]; if (!c) return cd;
        const r = c.remaining - 1;
        if (r <= 0) {
          clearInterval(countdownTimers.current[label]);
          delete countdownTimers.current[label];
          // dispatch the label as a user action next tick
          setTimeout(() => userAction(label, { auto: true }), 0);
          const next = { ...cd }; delete next[label]; return next;
        }
        return { ...cd, [label]: { ...c, remaining: r }};
      });
    }, 1000);
  }, []);

  const clearCountdown = useCallback((label) => {
    if (countdownTimers.current[label]) {
      clearInterval(countdownTimers.current[label]);
      delete countdownTimers.current[label];
    }
    setCountdowns(cd => { const n = { ...cd }; delete n[label]; return n; });
  }, []);
  const clearAllCountdowns = useCallback(() => {
    Object.keys(countdownTimers.current).forEach(l => clearInterval(countdownTimers.current[l]));
    countdownTimers.current = {};
    setCountdowns({});
  }, []);

  // ── User action dispatch ──────────────────────────────────────
  const advance = useCallback(() => {
    setAwaitingLabel(null);
    tapeIdx.current = tapeIdx.current + 1;
    setHead(tapeIdx.current);
    runStep();
  }, [runStep]);

  const userAction = useCallback((label, opts = {}) => {
    // Clear all countdowns when user explicitly clicks (but allow auto-fires)
    if (!opts.auto) clearAllCountdowns();
    else if (countdownTimers.current[label]) clearCountdown(label);

    // Dismiss any inline chat cards tied to this decision
    const dismissCard = () => {
      setDismissedCards(d => ({ ...d, [label]: true }));
    };

    // If the engine is awaiting and this label is accepted, advance
    if (awaitingLabel) {
      const accepted = AWAIT_ACCEPTS[awaitingLabel] || [];
      if (accepted.includes(label)) {
        advance();
        return;
      }
      // Non-accepted action (e.g. "Stop here"): show toast, do nothing else
      // EXCEPT for some side-effects:
      if (label === 'stop_here') {
        setRunState('idle');
        showToast('In a real run, this halts execution. Prototype continues happy path on the primary action.');
      } else if (label === 'adjust_params' || label === 'adjust_manually') {
        showToast('Adjust parameters — would open the global-params editor.');
      } else if (label === 'show_full_diff') {
        showToast('Show full diff — would expand all metrics + params.');
      } else if (label === 'close_panel') {
        setComparePanelData(null);
      } else if (label === 'use_a' || label === 'keep_a' || label === 'keep_b') {
        showToast(`Selected ${label.includes('a') ? 'Run A' : 'Run B'} — proceeding.`);
        advance();
      } else {
        showToast(`Action: ${label}`);
      }
      return;
    }

    // No await — just run side effects
    if (label === 'restart') { restartScenario(); return; }
    if (label === 'close_panel') { setComparePanelData(null); return; }
    showToast(`Action: ${label}`);
  }, [awaitingLabel, advance, clearAllCountdowns, clearCountdown, restartScenario]);

  // ── Plan item handlers ────────────────────────────────────────
  const planAddItem = () => showToast('Add step — would open a step picker.');
  const planRemoveItem = (id) => setPlanItems(items => items.filter(it => it.id !== id));
  const planItemAction = (id, action) => {
    if (action === 'retry')     { userAction('retry'); return; }
    if (action === 'skip')      {
      setPlanItems(items => items.map(it => it.id === id ? { ...it, status: 'skipped', failReason: null } : it));
      userAction('skip_step');
      return;
    }
    if (action === 'ask_agent') {
      showToast('Ask DeepAgent — would open a focused chat in the DeepAnalysisAgent panel.');
      return;
    }
  };

  // ── Pilot toggle handlers ─────────────────────────────────────
  const onConfirmRun = (mode) => {
    if (mode === 'pilot') userAction('run_pilot');
    else                  userAction('run_full');
  };

  // ── Tutorial tour — uses v1 scripts unchanged, driven by mirrored state ──
  // Every scenarioId is now valid for both the research engine (chat) and
  // the v1 panel — the engine has tape data for all 7. The tour reads
  // `tweaks.scenario` to know what to highlight, and we route a tour-set
  // `scenario` into the active id so chat + panel + tour stay in sync.
  const tourTweaks = {
    scenario: scenarioId,
    runState: v1RunState,
    qcHalt, licenseGate, blocked, disambig,
    watcherAttached, sidebarMode,
  };
  const setTourTweak = (patch) => {
    if ('scenario' in patch) {
      // Switching scenario from inside a tour — the engine and v1 panel
      // both follow `scenarioId`.
      setScenarioId(patch.scenario);
    }
    if ('runState'    in patch) setV1RunState(patch.runState);
    if ('qcHalt'      in patch) setQcHalt(patch.qcHalt);
    if ('licenseGate' in patch) setLicenseGate(patch.licenseGate);
    if ('blocked'     in patch) setBlocked(patch.blocked);
    if ('disambig'    in patch) setDisambig(patch.disambig);
    if ('watcherAttached' in patch) setWatcherAttached(patch.watcherAttached);
    if ('sidebarMode' in patch) setSidebarMode(patch.sidebarMode);
    if ('panelOpen'   in patch) setPanelOpen(patch.panelOpen);
  };
  const tour = (typeof window !== 'undefined' && window.useWFTour)
    ? window.useWFTour(tourTweaks, setTourTweak)
    : { active: false, start: () => {}, node: null };
  // When tour starts, make sure the panel is open so targets exist
  useEffect(() => { if (tour.active && !panelOpen) setPanelOpen(true); }, [tour.active]);

  // ── Sidebar wiring ────────────────────────────────────────────
  const onScenarioChange = (id) => setScenarioId(id);

  // ── Render ────────────────────────────────────────────────────
  const sidebarClass =
    sidebarMode === 'hidden'   ? 'sidebar-hidden' :
    sidebarMode === 'expanded' ? '' :
    panelOpen                  ? 'sidebar-rail' : '';
  const appClass = 'app' + (sidebarClass ? ' ' + sidebarClass : '') + (panelOpen ? '' : ' panel-closed');

  // Build chat events — augment with rendered cards
  const enrichedChatEvents = chatEvents.map((ev, i) => {
    if (ev.kind === 'line') return ev;
    if (ev.kind === 'card') {
      let node = null;
      if (ev.card === 'pilotPrompt') {
        node = (
          <PilotPromptCard
            scenario={scenario}
            onAction={userAction}
            dismissed={dismissedCards['pilotPrompt']}
          />
        );
      } else if (ev.card === 'pilotPromotion') {
        const cdLabel = 'pilot_promote_auto';
        const cd = countdowns[cdLabel];
        node = (
          <PilotPromotionCard
            data={ev.data}
            onAction={userAction}
            countdown={cd}
            dismissed={dismissedCards['pilotPromotion']}
          />
        );
      } else if (ev.card === 'comparison') {
        const cdLabel = 'compare_use_b_auto';
        const cd = countdowns[cdLabel];
        node = (
          <ComparisonCard
            data={ev.data}
            onAction={userAction}
            countdown={cd}
            dismissed={dismissedCards['comparison']}
            asPanel={false}
          />
        );
      } else if (ev.card === 'findings') {
        node = <FindingsChatCard data={ev.data}/>;
      }
      return { ...ev, kind: 'card', node };
    }
    return ev;
  });

  // Plan progress (for run-bar)
  const planTotal = planItems.length || 1;
  const planDone  = planItems.filter(i => i.status === 'done' || i.status === 'skipped').length;
  const planProgress = planDone / planTotal;

  // Plan edit-lock countdown chip
  const planEditCountdown = planEditing && countdowns['plan_auto_lock']
    ? { ...countdowns['plan_auto_lock'], label: 'plan_auto_lock' }
    : null;

  return (
    <div className={appClass}>
      {sidebarMode !== 'hidden' && (
        <Sidebar
          scenario={scenarioId}
          onScenarioChange={setScenarioId}
          rail={sidebarClass === 'sidebar-rail'}
        />
      )}
      {sidebarMode === 'hidden' && (
        <button className="sidebar-reopen" onClick={() => setSidebarMode('auto')} title="Show sidebar">
          <Icon name="chevronRight" size={14}/>
        </button>
      )}

      <div className="chat-col" data-screen-label="Research chat">
        <div className="chat-top">
          <div style={{display:'flex', alignItems:'center', gap:10}}>
            {!panelOpen && (
              <button className="btn ghost sm" onClick={() => setPanelOpen(true)}>
                <Icon name="flask" size={13}/> Panel
              </button>
            )}
            <div className="title">
              New thread <span className="domain">· {scenario.domain}</span>
            </div>
          </div>
          <div className="actions">
            <button className="tut-btn" onClick={tour.start} title="Replay the tutorial">
              <span style={{ fontSize: 10 }}>▶</span> Tutorial
            </button>
            <button className="btn ghost sm" onClick={restartScenario}>
              <Icon name="refresh" size={13}/> Replay
            </button>
            <button className="btn ghost sm"><Icon name="more" size={14}/></button>
          </div>
        </div>

        {/* Scenario picker removed from top of chat — switching now
            happens via the sidebar's "Current" list (the v1 pattern). */}

        <div className="thread">
          {planShown && (
            <PlanChecklist
              items={planItems}
              editing={planEditing}
              collapsed={planCollapsed}
              onToggleCollapsed={() => setPlanCollapsed(c => !c)}
              onEditDone={() => userAction('plan_lock_user')}
              onEditCancel={() => setPlanEditing(true)}
              onRemoveItem={planRemoveItem}
              onAddItem={planAddItem}
              onItemAction={planItemAction}
              editLockCountdown={planEditCountdown}
            />
          )}

          <ChatStream
            userQuery={scenario.query}
            userName={scenario.user}
            userTs="3:40 pm"
            workflowName={scenario.name}
            workflowSub={scenario.oneLiner + ' · ' + scenario.domain}
            panelOpen={panelOpen}
            onReopenPanel={() => setPanelOpen(true)}
            events={enrichedChatEvents}
            placement={pillPlacement}
            collapseThreshold={collapseThreshold}
            showTs={showTs}
          />
        </div>

        <div className="chat-input-wrap">
          <div className="chat-input">
            <textarea placeholder="Ask Biomate to extend the pipeline, adjust parameters, or run another comparison…" rows={1}/>
            <div className="row">
              <div className="tools">
                <button className="btn ghost sm" title="Attach"><Icon name="paperclip" size={14}/></button>
                <button className="btn ghost sm"><Icon name="sparkles" size={13}/> Suggest</button>
              </div>
              <button className="send" disabled>
                <Icon name="send" size={13}/>
              </button>
            </div>
          </div>
        </div>
      </div>

      {panelOpen && (
        <WorkflowPanel
          scenario={v1Scenario}
          runState={v1RunState}
          setRunState={setV1RunState}
          onOpenModal={(kind, payload) => setModal({ ...payload, kind })}
          onClosePanel={() => setPanelOpen(false)}
          onResize={(w) => setTweak({ panelWidth: w })}
          watcherAttached={watcherAttached}
          setWatcherAttached={setWatcherAttached}
          tweaks={{ speed: 900, qcHalt, licenseGate, blocked }}
        />
      )}

      {comparePanelData && (
        <ComparisonCard
          data={comparePanelData}
          onAction={(label) => {
            if (label === 'close_panel') setComparePanelData(null);
            else userAction(label);
          }}
          countdown={countdowns['compare_use_b_auto']}
          dismissed={false}
          asPanel={true}
        />
      )}

      {modal?.kind === 'skip' && (
        <SkipConfirmModal target={modal} onCancel={() => setModal(null)}
          onConfirm={() => { modal.confirm && modal.confirm(); setModal(null); }}/>
      )}
      {modal?.kind === 'adjust'  && <AdjustModal  step={modal.step} onCancel={() => setModal(null)} onRerun={() => setModal(null)}/>}
      {modal?.kind === 'preview' && <PreviewModal file={modal.file} onClose={() => setModal(null)}/>}
      {modal?.kind === 'methods' && <ReportModal scenario={modal.scenario} onClose={() => setModal(null)}/>}
      {modal?.kind === 'report'  && <ReportModal scenario={modal.scenario} onClose={() => setModal(null)}/>}
      {modal?.kind === 'qcaudit' && <QcAuditModal scenario={modal.scenario} phases={modal.phases} onClose={() => setModal(null)}/>}

      {toast && <div className="wp-toast" key={toast.id}>{toast.msg}</div>}

      {tour.node}

      {!tweaksVisible && (
        <button className="tweaks-reopen" onClick={() => setTweaksVisible(true)}
          title="Reopen Tweaks">
          <Icon name="settings" size={13}/> Tweaks
        </button>
      )}

      {tweaksVisible && (
        <ResearchTweaks
          scenarioId={scenarioId} setTweak={setTweak} setScenarioId={setScenarioId}
          speed={speed}
          theme={theme} density={density}
          panelWidth={panelWidth} sidebarMode={sidebarMode}
          pillPlacement={pillPlacement} collapseThreshold={collapseThreshold} showTs={showTs}
          planEditDefault={planEditDefault} phaseExpandMode={phaseExpandMode}
          comparePlacement={comparePlacement} pilotDefaultOn={pilotDefaultOn}
          countdownSeconds={countdownSeconds}
          onClose={closeTweaks}
          onRestart={restartScenario}
        />
      )}
    </div>
  );
}

// ── Helpers ─────────────────────────────────────────────────────
function fmtClock() {
  const d = new Date();
  return d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }).toLowerCase();
}

Object.assign(window, { ResearchApp, fmtClock });
