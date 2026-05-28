# Google Analytics 4 — Setup, Issues Encountered, and Optimal Pattern

**Date:** 2026-05-27
**File:** `frontend/client/index.html`
**Two source folders, two GA4 properties, three behaviors:**

| URL | Property | Source folder | Behavior |
|---|---|---|---|
| `biomate.ai`, `www.biomate.ai` (marketing) | `G-65JDDPEDQ5` (prod) | `reference/claude_design/webpage_design_v2/` | static snippet, no hostname gate |
| `app.biomate.ai`, `www.app.biomate.ai`, `*.app.biomate.ai` (React app prod) | `G-65JDDPEDQ5` (prod) | `frontend/client/index.html` | hostname-gated `config` |
| `dev-public.biomate.ai`, `*.dev-public.biomate.ai` (React app dev) | `G-8YG54DFHQG` (dev) | `frontend/client/index.html` | hostname-gated `config` |
| `localhost`, `127.0.0.1`, E2E hosts | — | `frontend/client/index.html` | no `config` → no hits |

**Why two source folders?** biomate.ai is a separate static deploy (the marketing site, 31 HTML pages) from the React app at `app.biomate.ai` / `dev-public.biomate.ai`. They're tagged separately:

- Marketing site uses the canonical single-property snippet (no hostname gate needed — that folder only ever serves from biomate.ai).
- React app uses the hostname-gated pattern (one bundle, three behaviors).

**Watch out:** there is also a `webpage_design/` folder at the repo root that looks deceptively similar to `reference/claude_design/webpage_design_v2/`. It is NOT the deployed source. The live HTML at biomate.ai was byte-compared to confirm v2 is canonical. If you see gtag changes touching `webpage_design/` and not v2, the commit is in the wrong folder.

This doc captures (1) the problems we hit while wiring GA, (2) the alternatives we considered, and (3) the rationale for the final pattern, so the next person to touch this file doesn't repeat the loop.

## Issues encountered (in order)

### Issue 1 — Dev traffic polluting prod metrics

**Symptom:** Considering a single property for both prod and dev meant our E2E runs, manual smokes, and developer testing would mix with real-user data. That destroys bounce-rate, session-duration, retention, and any funnel built from those signals.

**Resolution:** Create a second GA4 property (`G-8YG54DFHQG`) for `dev-public.biomate.ai`. Same account, separate property, separate data stream. Real users land on prod, everything else lands on dev.

### Issue 2 — Tag Assistant reporting "not tagged" despite working code

**Symptom:** After deploying the first version, Tag Assistant / Google's "Site Tag Detected" check reported the site as **not tagged**, even though `gtag.js` was loading and `dataLayer.push` was firing at runtime.

**Root cause:** The first version was dynamically injecting the loader:
```js
var s = document.createElement('script');
s.async = true;
s.src = 'https://www.googletagmanager.com/gtag/js?id=' + measurementId;
document.head.appendChild(s);
```

That works for actual data flow — `gtag.js` runs, events queue, hits fire — but the GA Tag Detection tooling scrapes the **static HTML** before any JS runs. It searches for a literal `<script src="...googletagmanager.com/gtag/js?id=...">`. A dynamically-created tag is invisible to that scrape. So Google's tooling reports "not tagged" even when telemetry is flowing.

**Resolution:** Static `<script async src="...">` loader in the HTML head. The loader tag now lives in source where Tag Assistant can see it.

### Issue 3 — Buggy skip-guard left over from incremental edits

**Symptom:** During the back-and-forth a Python find-and-replace ran in the wrong order, leaving the file with:
```js
if (!measurementId || measurementId === 'G-8YG54DFHQG') return;
```
which causes GA to **skip exactly when the dev ID is selected** — the opposite of intent.

**Resolution:** Removed the guard entirely. The `config()` call is gated by hostname in a different code path; no separate "skip" check is needed.

### Issue 4 — Localhost / E2E noise (avoided proactively)

**Concern:** Without a guard, every `npm run dev` page load and every Playwright test would fire a GA hit. That re-introduces the noise problem we just solved with two properties.

**Resolution:** The `config()` call is wrapped in an `if (host === '…')` that only matches the two real hostnames. On `localhost` / `127.0.0.1` / `e2e_…@biomate.test` / anything else, the loader fetches `gtag.js` (≈ 50 KB cached) but never receives a `config` call, so no hits are dispatched.

## Alternatives considered, and why they lost

### Alt A — Two static loader tags, conditional rendering at build time
Different `index.html` per environment with the right loader src baked in.

**Why rejected:** Requires the build to produce environment-specific bundles. Our deploy pipeline currently ships one `dist/` to all environments. Adding environment-conditional builds is a bigger change than the bug warrants, and brings its own confusion (which build went where).

### Alt B — Two static loader tags in one HTML, both always present
Just include `<script src="…id=G-65…">` AND `<script src="…id=G-8YG…">` and let GA's runtime pick.

**Why rejected:** Both loaders would fire a page_view on initial config, sending the same hit to both properties. We'd be back to mixing the data streams. We'd have to call `config()` with `{ send_page_view: false }` on one of them to keep them quiet, at which point we've reinvented the current pattern with more moving parts.

### Alt C — Dynamic loader injection (the original failed attempt)
Decide the loader src at runtime by hostname, then `document.head.appendChild` the right one.

**Why rejected:** Tag Assistant + GA's automated "Site Tag Detected" check don't see dynamically-injected script tags. This caused the **"not tagged"** false negative that started this whole loop.

### Alt D — Server-side measurement via GA4 Measurement Protocol
Drop the client-side gtag entirely; fire events from `frontend/server/routes.ts` directly to GA's MP endpoint.

**Why rejected:** Optimal for some workflow events but the *wrong* tool for page_views and engagement. Client-side tag captures session, screen, referrer, UTMs out of the box. MP is best as a *supplement* — see "Future work" below.

## The optimal pattern (current implementation)

```html
<!-- Static loader: Tag Assistant friendly. Sends no hits by itself. -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-65JDDPEDQ5"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){ dataLayer.push(arguments); }
  window.gtag = gtag;
  gtag('js', new Date());
  (function() {
    var host = window.location.hostname;
    if (host === 'biomate.ai' || host === 'www.biomate.ai') {
      gtag('config', 'G-65JDDPEDQ5', { anonymize_ip: true });
    } else if (host === 'dev-public.biomate.ai' || host.indexOf('.dev-public.biomate.ai') !== -1) {
      gtag('config', 'G-8YG54DFHQG', { anonymize_ip: true });
    }
  })();
</script>
```

**Why this is optimal:**

| Requirement | How the pattern satisfies it |
|---|---|
| Tag Assistant detects the site as tagged | Static `<script src="…">` in the HTML head |
| Single build artifact ships to all envs | Loader is identical; only the runtime config differs |
| Prod and dev properties stay separate | `gtag('config', …)` chooses the property by hostname |
| Localhost / E2E produce no hits | Hostname checks fail → no `config` call → no events |
| EU privacy basics | `anonymize_ip: true` on both configs |
| Reversible if we add a third env | One more `else if` block |
| Cheap to debug | Open DevTools → Network → filter `collect` to see hits in real time |

**Key non-obvious detail:** The `?id=G-65JDDPEDQ5` in the loader URL is *just* the URL it fetches `gtag.js` from. The fetched JS is the same generic loader regardless of the ID. The page is bound to a property only when `gtag('config', ID)` is called. So a single loader URL serves all environments; the binding is per-config-call, not per-loader-tag.

## Verification checklist

After a deploy, on each environment:

1. **View Source** — confirm the `<script src="…googletagmanager.com/gtag/js?id=G-65JDDPEDQ5">` tag exists in the HTML
2. **DevTools → Network** — refresh; filter to `googletagmanager` and `google-analytics`. You should see:
   - `gtag/js?id=G-65JDDPEDQ5` 200 (always)
   - `g/collect?…` or `j/collect?…` with `tid=G-65JDDPEDQ5` on prod, or `tid=G-8YG54DFHQG` on dev (one per page view)
3. **GA4 Real-time dashboard** for the matching property — your visit appears within ~10s
4. **Tag Assistant** (Chrome extension or `tagassistant.google.com`) — should say "Tag detected" with the loader's ID
5. **Adblock test** — open in incognito with no extensions; the requests above must succeed (uBlock Origin / Brave will block them, which is a separate "tag not firing" symptom unrelated to our code)

## Future work

- **MP supplement.** Server-side events from `frontend/server/routes.ts` for workflow lifecycle: `run_started`, `run_completed`, `gap2_edit_applied`. These don't have a browser page to attach to and the MP endpoint accepts them directly. Wire one event when we want our first funnel metric.
- **Consent gate.** If we onboard EU users, add a cookie banner that defers the `config()` calls until consent. Google's recommended `gtag('consent', 'default', { … })` block goes between the loader tag and our config IIFE.
- **Custom dimensions.** When we want per-user-segment analysis (free vs paid plan, biotech vs academic vs CRO), add `gtag('set', 'user_properties', { … })` after login and read in GA4 Explore.
- **Event taxonomy.** Document our standard event names (`workflow_run_started`, `panel_param_edited`, `run_again_clicked`, etc.) before they sprawl. One doc, one decision per name.

## Quick reference

| Task | Where |
|---|---|
| Change a measurement ID | `frontend/client/index.html` lines 21/30/32 |
| Add a new tracked environment | One more `else if` in the IIFE |
| Disable analytics globally for an emergency | Comment out the IIFE block (loader can stay) |
| Add a new event | Inside any React component: `window.gtag?.('event', 'name', { … })` — guarded `?.` so it's a no-op on localhost |
| See live hits | GA4 → Reports → Realtime, OR DevTools → Network → `collect` |
