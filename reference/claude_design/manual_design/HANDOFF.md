# /manual — design handoff log (Claude design → Claude Code)

**Date:** 2026-10-19 · **Input:** `docs/user-manual/**` (attached as `user-manual/`), brief `CLAUDE_DESIGN_REQUIREMENTS.md`
**Prototype:** `manual/BioMate Manual.html` (+ `manual.css`, `md.js`, `nav.js`, `app.js`, `content/` = verbatim copy of the manual source)

## 1. What was built (reference implementation for the `/manual` route)
- **Doc-page layout:** sticky header · left nav tree (mirrors the Index) · content pane (max 780px) · right “On this page” anchors with scroll-spy. Reflows to drawer nav < 900px; TOC hides < 1240px.
- **IA (mirrors README Index):** Part 0 Overview (4) → Part I Modules (14, incl. I14 instruments which exists on disk but is not listed in the Index) → Part II Data (5) → Part III Domains (13) → Appendices A–F (6) = **42 chapters**; plus **Tutorials** (T0–T11, M1–M2, S1, W1–W3, 14 instrument tutorials = 32) with a generated hub page.
- **Bilingual:** EN / 中文 switch (persisted, `?lang=zh` also works). Tutorials load `tutorials/zh/*.zh.md`; chapters with no ZH source render the English text under a 中文 chrome with the note “本章目前仅提供英文版。” Nav labels have hand-written ZH titles for all chapters.
- **Branding:** BioMate logo mark (cropped from `biomate-logo.png` via CSS) + typeset “BioMate” wordmark (no “AI”, no “BETA”); persistent **“Free trial: www.biomate.ai” / “免费试用：www.biomate.ai”** in header and footer, linking to https://www.biomate.ai.
- **Search:** client-side, section-level (title × heading × body scoring, highlighted snippets), `/` or ⌘K to focus, ↑↓/Enter/Esc. Results deep-link to the heading anchor.
- **Page model:**
  - Headings → slugged ids, hover `#` copies a deep link (`#/<route>~<anchor>`).
  - Tables → spec table style, horizontal scroll wrapper, dense mode ≥ 4 cols.
  - Code spans / fences → IBM Plex Mono blocks.
  - `[~] [x] [ ]` and `✅ 🔧 ⏳ 🗺️ ⚠️` → design tokens (Verified / Corrected / Pending / Roadmap / Stale), never raw brackets or emoji.
  - Blockquotes → typed callouts (Pitfall → amber rule, Tip → blue, QC gate → green, “In one sentence” → key, quoted prompts → “Ask” cards). ZH keyword equivalents handled.
  - Screenshots → figures with caption (picks up the italic line under the image), click-to-lightbox, and a **“Current build”** tag + tooltip (“captured from the current build; the interface is being refreshed”) so they are not presented as the polished reference UI.
  - Missing images / `*(Figure to add)*` → striped “Screenshot to be captured” placeholder (never a broken image).
  - Relative `.md` links and `[[…]]`-style refs → in-app routes; links that resolve outside the manual (e.g. `../../20261003_…md`, `reference/…`, `qa/…`) render as plain text (no dead affordances). External links open in a new tab with ↗.
  - HTML comments (incl. `<!-- CAPTURE … -->`) stripped.
- **Honesty gate:**
  - Per-chapter **coverage strip** parsed from `coverage-ledger.md` (counts of verified / corrected / pending / not-yet-available rows; expandable list of 🗺️ rows linking to Appendix E). The ledger’s *Evidence* column, source paths and the fixture login are **not** rendered.
  - Every “What’s not covered / Honest limits / 局限 / 尚未…” section is wrapped in a dashed, hatched **“Roadmap — not available today”** container. Appendix E gets the same treatment page-wide.
  - Chapter status chip from the Index (`[~]` → “Drafted · verifying”).
- **No cost UI** added. No pricing tables. Home page copy is navigation-only (no new product claims).
- **Content untouched:** every `.md` was copied verbatim; nothing was edited.

## 2. Requirements for Claude Code (to ship `/manual` in the app)
1. **Route:** add `/manual` and `/manual/*` (React) — e.g. `/manual/modules/I03-search-and-evidence#reading-the-answer`; prototype uses hash routes only because it is a static file. Link it from the composer’s help affordance. Do not add `/dashboard` or a runs page.
2. **Content pipeline:** bundle `docs/user-manual/**` at build time (Vite `import.meta.glob('…/*.md', { as: 'raw' })`) rather than fetching at runtime; serve `docs/user-manual/assets/*.png` as static assets.
3. **Renderer:** use a real markdown pipeline (e.g. `react-markdown` + `remark-gfm` + custom components) reproducing the rules in §1 — `md.js` documents the exact transforms (tokens, callout typing, figure+caption pairing, CJK line-join, dead-link → text, comment stripping). Note: CJK soft line-breaks must join **without** a space.
4. **Nav/IA:** port `nav.js` (routes + EN/ZH labels) as a typed constant; keep it in sync with the README Index (or generate it from the Index + H1s).
5. **Ledger parsing:** port `parseLedger()` (sections keyed by `Page:`/`Chapter:` path; status column emoji). Run it at build time and fail CI if a chapter’s route is missing from the ledger mapping, or if a 🗺️ row’s feature appears in a non-roadmap section.
6. **Design tokens:** use `reference/claude_design/data_centroid_design_v2/spec/spec.css` values (IBM Plex Sans/Mono, ink `#101828`, mut `#5a6474`, hairlines `#e3e7ee`/`#d5dae2`, accent `#1a4a9c`, tag colours). `manual.css` holds the full scale for the web.
7. **Acceptance:** all 42 chapters + 32 tutorials render in EN, the 32 tutorials in ZH; `npx tsc --noEmit` clean; link checker over every rendered `<a>`; no image 404s (placeholders only where §3 lists them).

## 3. Content issues found (for the manual authors — not changed in design)
- `tutorials/T11-drug-development-end-to-end(.zh).md` reference `../../qa/20261003-tutorial-release/panel-outputs.png` and `panel-record.png` — outside the manual folder; rendered as placeholders. Move them into `assets/`.
- `tutorials/README.md` carries a **“Release review — HOLD”** banner and internal paths; it is not rendered (a generated Tutorials hub replaces it). Confirm when tutorials are cleared for users.
- `modules/I14-instruments-and-lab-connectivity.md` exists but is **missing from the README Index**; included in Part I.
- Brief says “40 chapters”; the Index + disk give **42** (I13 + I14 counted).
- `modules/I13-billing-quotas-two-lane-cost.md` is rendered as authored, but `tutorials/README.md` lists Billing as **disabled product-wide** and the brief forbids cost UI — authors should confirm I13 belongs in the user-facing manual.
- `tutorials/README.md` flags stale chapters: I04 (owner-transfer UI now exists), I12 (Connectors dialog has 4 tabs, chapter says 2), I09 (verify format list). Not corrected here.
- All Index entries are still `[~]` (drafted, verifying) — no chapter shows “Verified” yet.
- Chapters cite source paths/line numbers inline (`ai_assistant.py:3131`); fine for power users, but consider moving them to the colophon for the default reader.
- `assets/i05-3-quality-tab.png` is marked stale in the ledger and `i00-1-runs-dashboard.png` shows a removed surface; neither is referenced by a rendered chapter today — keep it that way.
- Screenshots in `assets/` lag the design system (per brief); re-capture after the product UI catches up. The “Current build” tag can then be removed.

## 4. Screenshot slots (see `manual/SHOTLIST.md`)
- Every screenshot slot has a stable id (`<chapter-code>-NN`; added ones `-A#`; 中文 tutorials `.zh`) shown on its placeholder and carried as `data-shot-id` / `data-capture` on the `<figure>`.
- **45** authored EN placeholders (the chapters' own `*(Figure to add)*` + CAPTURE specs, now rendered instead of stripped) · **2** missing image files (T11) · **50** 中文 tutorial slots · **45** recommended additions where a chapter had no visual (all 13 domains ×2, I02/I03/I04/I06/I14, II01/II02, Appendix C, overview 03, 2 instrument tutorials) — defined in `manual/shotlist.js`, not in the markdown.
- **Claude Code:** capture per spec into `docs/user-manual/assets/<slot-id>.png`, wire into the chapter markdown (EN + ZH), remove the filled entry from `shotlist.js`; port the slot/placeholder behaviour into the React renderer so unfilled slots never show as broken images.
- Finding: 中文 tutorials T0, T5, T7, W1, W2, W3 still show `待补图` where the EN version already has an image — sync them.

## 6. Engineering details removed from the reader view (user request, 2026-10-19)
Users have no access to source code, so the manual must not show it. `manual/sanitize.js` (`mdClean`) runs on every paragraph, list item, table cell, heading, caption, search snippet and coverage-gap line:
- **Removed:** source files + line refs (`chat-interface.tsx:2138-2155`, `lane-preview.tsx`, bare `(:748)`), API endpoints (`/api/…`, `POST …`), code identifiers (React components like `CitationPanel`/`AfterRunReport`, functions `_build_search_queries()`, camelCase props `skillPackIds`, constants `COLD_MODULES[0]`, internal DB fields `user_notes`/`knowledgeType`, MCP tool names, `?checksums=1`, `available:false`), catalog DB ids (`id 1491`), verification tiers (`(C)`, `tier C`), "(dev)", and the `_Verification: …_` / "Companion technical references" colophons.
- **Method:** a parenthetical carrying such a ref is dropped whole; a sentence that still carries one is dropped; empty table columns/rows, callouts, list items and headings are dropped (TOC follows).
- **Kept:** what users see or type — routes (`/files`, `/design`), workflow/tool names (`nf-core/rnaseq`, `cryosparc_standard_spa`, DESeq2), parameter names (`max_pct_mito`, `qpcr_hkg`), file types/outputs (`.h5ad`, `umap_celltypes.png`), science terms (hERG, pLDDT), journal citations, honest caveats (e.g. weak dev e-signature).
- **Appendix F (API / connector / CLI quick reference)** removed from the user nav (file kept; developer material).
- Net effect: ~11% of rendered text removed; heaviest in II05 (~49%), I02/I04/I07/I14/II02 (~30%).
- **Requirement for Claude Code / authors:** this is a render-time safety net. Real fix is upstream: rewrite `docs/user-manual/**` in user language and keep code citations only in the coverage ledger. Port `mdClean` into the React renderer meanwhile, and add a CI check failing on `\.(py|tsx?|nf)(:\d+)?`, `/api/`, or PascalCase component names in rendered output.

## 7. 中文 chapter translations (in progress)
- Only the **tutorials** had Chinese sources upstream. The 41 user-facing chapters (Part 0–III + Appendices A–E) were English-only, so the 中文 switch showed English text.
- Added mechanism: `content/zh/<route>.zh.md` is loaded in 中文 when the route is listed in `window.MANUAL_ZH` (`nav.js`); otherwise the English chapter shows with an amber “本章中文版正在翻译中” note and the nav item carries an `EN` tag.
- **Translated so far (5):** overview 00–03, I.1 Cold start — written from the reader-clean text (no file/line refs), links and screenshots preserved (`../../assets/`).
- **Remaining (36, ~560k EN chars):** I.2–I.14, II.1–II.5, all 13 domains, Appendices A–E. Requirement for authors/Claude Code: translate into `docs/user-manual/zh/<part>/<file>.zh.md` (same headings order, same links, same screenshot refs, honesty sections intact, no code refs), then add each route to `MANUAL_ZH`. A native-speaker review pass is required before release.

## 8. Other modification this session (tutorial walkthrough decks, `tutorials_v2/`)
- All 44 decks: free-trial text changed to the spec strings “Free trial: www.biomate.ai” / “免费试用：www.biomate.ai”.
- `_v2lib.css`: header brand is now logo mark + typeset “BioMate” wordmark (CSS crop of `biomate-logo.png`; markup and `src` unchanged). Recording contract (§4 of the reformat brief) untouched.
