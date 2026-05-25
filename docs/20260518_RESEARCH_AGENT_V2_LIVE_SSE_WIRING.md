# Research-Agent v2 — Live SSE wiring (sandbox)

Date: 2026-05-18
Scope: `frontend/research_agent_v2/` sandbox only. **Not** integrated into production.

## Goal

Drive the Claude-Design research-agent UI (sandbox copy) from a BioMate-shaped
SSE event stream so we can validate the event vocabulary (`workflow.*`,
`plan.shown`, `findings.*`, `deepagent.*`) before promoting any surface into
the production `frontend/client/src/` tree.

## What landed

### `src/sse-adapter.js` (pre-existing, kept)
Bridge module exposing `window.SseAdapter`:
- `createMockBiomateStream(scenarioId)` — synthesizes a tape of realistic
  BioMate `chat_progress` events plus internal `__planUpdate` / `__showCard` /
  `__await` / `__startCountdown` shaping events for scenario choreography.
- `connectRealBiomateStream(invocationId)` — opens an `EventSource` against
  `/api/workflows/{inv}/events`; drop-in for the mock.
- Both: `start(onEvent, {speed}) → {close()}`.
- Tapes: `drugscreen` (50 events, pilot → 2 QC fails → autoloop → comparison
  → findings) and `cryoem` (33 events, 5 phases A-E with CTF gate trip).

### `src/ResearchApp.jsx` (live-mode wiring)
- `translateBiomateEvent(ev)` — pure mapper from BioMate event shape to the
  engine's internal vocabulary. Handles `__planUpdate`, `__planFail`,
  `__showCard`, `__await`, `__startCountdown`, `plan.shown`, and the
  generic `chatLine` fallback (using `ev.speaker` + `ev.friendly_message`).
- URL params now honored on mount:
  - `?live=mock|real` — enables SSE mode and **disables the tape walker**.
  - `?scenario=drugscreen|cryosparc|rnaseq|variant` — selects the mock tape
    or, in real mode, just labels the UI.
  - `?speed=0.5|1|2|5` — slider equivalent.
  - `?inv=<invocation_id>` — required when `?live=real`.
- `applyEvent` `'planShow'` case extended: items come from the event in live
  mode, fall back to `scenario.initialPlan` in tape mode.
- New `useEffect` (deps: `[liveMode, liveInvId, scenarioId]`) opens the
  stream, pipes each event through `translateBiomateEvent`, dispatches
  through `applyEventRef`, and closes the stream on cleanup.

### `index.html`
- Loads `sse-adapter.js` **before** `ResearchApp.jsx` so the factory exists
  when the component mounts.
- Bumped cache-busting `?v=` on `ResearchApp.jsx`.

### `live.html`
- Minimal harness that mounts `PlanChecklist + ChatStream + ChatCards`
  directly on the SSE adapter (no `ResearchApp` engine). Used to verify the
  raw event shape renders cleanly before involving the full engine.

## Bugs caught + fixed in this session

1. **`?scenario=` URL param ignored** — `scenarioId` was initialized from
   `init.scenarioId` (localStorage default `rnaseq`); the live SSE effect
   then logged `no mock tape for scenarioId=rnaseq` and bailed out, leaving
   the engine silent. **Fix:** initialize `scenarioId` from URL when it
   matches a known `RESEARCH_SCENARIOS` key.
2. **`?speed=` URL param ignored** — `speedRef.current` was always `1.0`,
   so headless smoke tests waiting 8s only saw ~18/50 events. **Fix:**
   initialize `speed` from URL.
3. **(earlier in session)** `delayMs * speed` had reversed semantics in the
   mock player — fixed to `delayMs / speed`.
4. **(earlier in session)** `index.html` missed the `sse-adapter.js`
   `<script>` tag — added before `ResearchApp.jsx`.

## Smoke test (final)

```
cd frontend/research_agent_v2 && python3 -m http.server 8765 &

node -e "
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch();
  for (const url of [
    'http://127.0.0.1:8765/index.html?live=mock&scenario=drugscreen&speed=5',
    'http://127.0.0.1:8765/index.html?live=mock&scenario=cryosparc&speed=5',
  ]) {
    const page = await browser.newPage();
    const errs = []; page.on('pageerror', e => errs.push(String(e)));
    await page.goto(url, { waitUntil: 'networkidle' });
    await page.waitForTimeout(15000);
    const r = await page.evaluate(() => {
      const t = document.body.innerText;
      return {
        plan: document.querySelectorAll('[class*=plan-item]').length,
        cmp: /Run A.*Run B|Compare runs/i.test(t),
        find: /BBB-penetrant|Validated map|Particles in final/i.test(t),
        completed: /finished|completed/i.test(t),
      };
    });
    console.log(url.split('scenario=')[1].split('&')[0], r, 'errs:', errs.length);
    await page.close();
  }
  await browser.close();
})();"
```

Result:
```
drugscreen {plan:5, cmp:true,  find:true, completed:true} errs: 0
cryosparc  {plan:5, cmp:false, find:true, completed:true} errs: 0
```

`cmp:false` for cryo is **expected** — the cryo tape has no Run A/Run B
comparison card.

## Not done / next step

- Real-backend verification: run a small drug-screen invocation on dev EC2
  and open `index.html?live=real&inv=<id>` to confirm the BioMate backend
  narrator emits a `chat_progress` event shape that
  `translateBiomateEvent` already handles. Any new `kind`s found there
  go either into the narrator templates or the translator's default
  branch.
- Add bulk RNA-seq + variants tapes (so all four sidebar scenarios have a
  mock).
- After the real-SSE smoke passes, plan a single-surface promotion into
  `frontend/client/src/` behind a feature flag, starting with speaker pills
  (Surface 2 — lowest risk, highest visual win, per the existing
  `02_INTEGRATION_PLAN.md`).
