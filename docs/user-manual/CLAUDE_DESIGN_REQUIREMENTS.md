# Claude-design requirements — the in-app `/manual`

Handoff brief for the design phase that renders the verified user-manual content as branded in-app
documentation. The writing/verification/sync is complete; this is the design step.

## Goal
Render the verified user-manual content as first-class, branded in-app docs at `/manual` — matching
the BioMate design system, not a markdown dump.

## Source of truth (read-only input)
- **Content:** `docs/user-manual/**` — the 40 chapters + `README.md` index + `assets/*.png` screenshots.
- **Honesty gate:** `docs/user-manual/coverage-ledger.md` — render only what's green; anything not
  code-verified belongs under "Roadmap" (Appendix E), styled distinctly as *not yet available*, never
  as a live feature.
- **Design system:** `reference/claude_design/data_centroid_design_v2/spec` — read it and reuse its
  tokens/typography/spacing/doc-page components. Do not invent a new visual language.

## Output target
- A `/manual` route: doc-page layout — left nav tree (the Index IA), content pane, right-hand
  on-this-page anchors, search.
- Do **not** resurrect `/dashboard` or any standalone runs page. BioMate is chat-centric; `/manual`
  is reference docs only, linkable from the composer's help affordance.

## Information architecture (mirror the Index)
Part 0 Overview → Part I Modules (13) → Part II Data (5) → Part III Domains (13) → Appendices (6).
Each chapter keeps its `_CHAPTER_TEMPLATE.md` sections (What it's for · Use cases · How to ask · Tools
behind it · QC gates · Worked example · Outputs · Pitfalls · What's not covered).

## Page-model requirements
- Headings → anchored, deep-linkable; tables → styled (many chapters are table-heavy); code/params →
  mono blocks; the `[~]/[x]` status → design tokens, not raw brackets.
- Screenshots → responsive figures with captions/lightbox.
- Cross-chapter `[[links]]` / relative links → in-app routes.
- Per-feature coverage badge (verified vs roadmap), sourced from the ledger.

## Hard constraints (non-negotiable)
1. **Honesty** — never render a roadmap/gapped item as available; keep examples generic (no real
   collaborator names/accessions).
2. **No cost/pricing UI** — do not reintroduce cost estimates or competitor price tables (just removed).
3. **No dead affordances** — every link/button in `/manual` resolves.
4. Content is authored upstream in `docs/user-manual/`; design renders it — it must not silently edit
   claims.

## Acceptance criteria
All 40 chapters render; nav mirrors the Index; ledger-red items appear only under Roadmap; screenshots
load; `npx tsc --noEmit` clean; no cost UI; every internal link resolves.

---

## Update 2026-10-06 (per user) — branding, bilingual, style fidelity, screenshot lag

**Follow the design STYLE, not the mockup's function set.** `data_centroid_design_v2` defines the target
*visual style/appearance/attractiveness* — it does NOT enumerate every product function (it shows only
the major ones). Match its typography, color, spacing, iconography, radii/shadows and overall polish;
keep every verified manual function even if the mockup doesn't depict it. Attractiveness is a first-class
requirement. (See memory `feedback_design_mockup_is_style_ref`.)

**Branding (new):**
- Header carries the **real BioMate logo + "BioMate" wordmark** (clean — not the clipped/overlapping
  "BioMate AI + DNA-leaf + BETA" currently rendered in the product; see the UI-fidelity note below).
- A persistent **"Free trial: www.biomate.ai"** call-to-action (ZH: "免费试用：www.biomate.ai"),
  unobtrusive, on every manual page (e.g. header or footer). This mirrors the video branding
  requirement in `docs/20261006_REQUIREMENT_DRUGDEV_FULL_PROCESS_TUTORIAL.md` §8 — keep them consistent.

**Bilingual (clarify):** render BOTH editions with a language switch —
EN from `docs/user-manual/tutorials/*.md` and ZH from `docs/user-manual/tutorials/zh/*.zh.md`
(e.g. the drug-dev chapter `T11-drug-development-end-to-end.zh.md`). Chinese must read idiomatically.

**Screenshot lag (important):** the `docs/user-manual/assets/*.png` are captures of the CURRENT product
UI, which lags the design system (clipped logo, double composer, duplicate project rows, verbose
sidebar — see `docs/20261006_REQUIREMENT_DRUGDEV_FULL_PROCESS_TUTORIAL.md` §9 and the in-progress
style-gap audit). Treat them as placeholders: they should be re-captured after the product UI's
*appearance* is brought up to the design system. Do not present current screenshots as the polished
reference UI.
