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
