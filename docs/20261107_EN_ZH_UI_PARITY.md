# English / Chinese UI alignment and explicit language control

## Evidence

- Public dev `build-info.json` returned `20f159a1cb794b8222ad2f923ae192270d9ee64c` on 2026-11-07.
- The local `integration/next-phase` reference was stale (`18bea0c79`, October 24). After fetching, `origin/integration/next-phase` was `79c0421d9`, November 7.
- Dev and refreshed next-phase had diverged by 47 / 36 commits. Twenty frontend client files differed. The missing newer UI included richer file previews, dataset columns, dataset versions/restore and open-in tools, URL import, output-to-dataset links, and custom skill creation. This was branch divergence, not an independent Chinese layout.
- Both locales use the same App, sidebar, routes, styles, and panel components. Locale selection changes translation bundles, not the component tree.

## Changes

Merged the deployed dev lineage into `codex/zh-en-ui-parity`, based on refreshed next-phase. Kept next-phase's on-premises changes, including `local_path` and Galaxy-proxied `download_url` handling in AfterRunReport. The merge also brings supporting server endpoints alongside the client features; copying just JSX would leave new controls disconnected.

Added a visible `Language / 语言` selector inside the Settings dialog header, visible across Settings tabs on desktop and mobile. Selectable choices are English and 简体中文. One disabled Others — Pending translation / 其他语言 — 待翻译 option represents additional languages; it cannot save an unsupported locale. It uses the existing language preference mechanism: save `biomate-user-settings.language`, then reload the current URL. It preserves other saved settings. No backend records or connector configuration are changed. Set the document language to match the active locale for accessibility.

Detection order remains: explicit saved choice, browser language, then fallback. Preference is per browser. Both choices load the same UI implementation. Existing English phrase fallback and Chinese-only translation entries remain intact.

## Validation

- TypeScript: passed.
- Browser with fixture API responses: English → Chinese → English passed; persisted choice checked; desktop and 390px mobile checked; no horizontal document overflow. Screenshots `/tmp/biomate-parity-english.png`, `/tmp/biomate-parity-chinese.png`, `/tmp/biomate-parity-chinese-390.png`. This is a UI check, not a live scientific workflow or on-premises integration test.
- Locale regression tests cover explicit preferences overriding browser language, browser fallback, all English bundle keys having Chinese translations, and selector choices invoking the existing persistence function. The selector belongs inside Settings; no separate sidebar language entry is rendered.
- Full frontend suite/build results are recorded in the final review response and `/tmp/biomate-zh-parity-*.log`.

## Limits / release state

Not deployed by this change. The branch must be integrated and deployed from the same source revision for both locales. Older hard-coded English explanatory text still exists in some panels; locale feature/layout parity does not assert complete translation of every legacy sentence. Connector content, scientific names, user-authored text, and saved run data are preserved rather than translated or replaced.
