# How to run the sandbox

Two-command local serve. No build step (React 18 + Babel inline).

```
cd frontend/research_agent_v2
python3 -m http.server 8765
```

Then open `http://127.0.0.1:8765/index.html` in a browser.

The page mounts `<ResearchApp/>` which today plays the **tape engine** —
a synthetic event stream defined in `src/research-data.js`. The default
scenario is Bulk RNA-seq happy path; switch via the left-sidebar "Chat"
list (rnaseq / drugscreen / variant / cryosparc).

## What's different from the original Claude-Design handoff

1. **No `ResearchTweaks` panel** — replaced with a stub that just shows
   "Tweaks panel removed for the BioMate port". The original was a
   design-time preview tool, not a product feature. `ResearchApp.jsx`
   is unmodified.
2. **Logo path** — copied `biomate-logo.png` into `images/` from the
   v1 design reference.
3. **No other modifications** — `ResearchApp`, `ChatStream`,
   `ChatCards`, `PlanChecklist`, `WorkflowPanel`, `PhaseCard`,
   `AutoLoop`, `Modals`, `Chrome`, `Tour`, `Icon`, all CSS files, and
   both data files are byte-identical to the Claude-Design handoff.

## What this is for

The tape engine in `research-data.js` is the synthetic input that
drives the demo. **Next step** (per the integration plan) is to
replace that engine with a real `EventSource` against BioMate's
existing workflow SSE stream, plus a few new endpoints. The sandbox
exists so we can iterate on that wiring without touching production.

## Smoke-test commands

```
# Headless render check (Playwright must be installed in ../frontend)
cd /home/yzhang/biomate/frontend/research_agent_v2 \
  && python3 -m http.server 8765 >/tmp/sb.log 2>&1 &

cd /home/yzhang/biomate/frontend && timeout 30 node -e "
  const { chromium } = require('playwright');
  (async () => {
    const browser = await chromium.launch();
    const page = await browser.newPage();
    let err = 0; page.on('pageerror', () => err++);
    await page.goto('http://127.0.0.1:8765/index.html', { waitUntil: 'networkidle' });
    await page.waitForTimeout(4000);
    console.log('JS errors:', err);
    await page.screenshot({ path: '/tmp/sandbox.png' });
    await browser.close();
  })();"
```

Expected: 0 JS errors. Screenshot shows Plan / chat / Pilot card /
workflow panel populated.
