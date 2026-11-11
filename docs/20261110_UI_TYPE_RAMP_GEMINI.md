# UI type ramp — Gemini-authored, codemod-migrated (2026-11-10)

Follow-up to `docs/20261110_UI_CONTRAST_TUNING_GEMINI.md` (PR #347, colour/surfaces). The founder
approved the next step: the text-size pass, with Gemini tuning the appearance.

## Problem

~3,000 font-size declarations, ~25 distinct ad-hoc values, mostly 10–12px
(`size_distribution_before.txt`): `text-xs` (12px) ×1515, `text-sm` (14px) ×711, `text-[10px]` ×250,
inline `fontSize` 10–13px ×~600, CSS-file px ×~200. No hierarchy; reading text tiny.

## Ramp (Gemini round 3, accepted)

| Token | Size / line-height | Use |
|---|---|---|
| `--fs-xs` | 12 / 1.4 | micro labels, chips, breadcrumbs, run meta (floor) |
| `--fs-sm` | 13 / 1.4 | secondary UI, dense content |
| `--fs-base` | 14 / 1.5 | body, tables, sidebar nav |
| `--fs-lg` | 16 / 1.4 | card titles, subsection headings |
| `--fs-xl` | 20 / 1.3 | section headers |
| `--fs-2xl` | 24 / 1.2 | page titles, hero |
| `--fs-3xl` | 36 / 1.1 | display (legacy ≥26px) |
| `--fs-mono` | 13 / 1.4 | ids, hashes, code |

Legacy mapping (`docs/20261110_ui_type_ramp/type_ramp_plan.json`): 7–11px → xs(12) · 11.5–12 → sm(13) ·
12.5–14 → base(14) · 14.5–16 → lg(16) · 17–20 → xl(20) · 22–24 → 2xl(24) · 26–36 → 3xl(36).
Tailwind: `xs`→13 · `sm`→14 · `base`→16 · `lg`/`xl`→20 · `2xl`→24. **No legacy value shrinks.**

## Process — Gemini proposes, render verifies

| Round | Gemini plan | Verdict |
|---|---|---|
| 1 | 7 steps, `text-sm`→12px | **Rejected before rendering** — shrank body text (14→12) and left the dominant 12px text unchanged |
| 2 | floor 11, `xs`→13, `sm`→15 | Rendered: much more readable; but 15px body made panel tables wrap to 5 lines, sidebar still 13px, chips/buttons/breadcrumb still 11px |
| 3 | floor 12, `sm`→14, 13px→14 | Rendered: balanced, sidebar 14, meta 12, no overflow — **accepted** |

Rendering before deploy: `type_ramp_codemod.py --preview` emits CSS that makes the current dev build
render as if migrated (token block + Tailwind class overrides + `[style*="font-size: Npx"]` overrides
+ codemodded copies of the panel/reference sheets), injected via `ui_tune_capture.mjs`.

## Migration

`frontend/scripts/type_ramp_codemod.py <plan.json> --apply` (idempotent; re-run after editing the plan):
- token block written into `reference-design.css :root` between `type-ramp:start/end` markers;
- `tailwind.config.js` `theme.extend.fontSize`: named sizes and new `text-fs-*` utilities → tokens;
- `text-[Npx]` → `text-fs-*`; React style `fontSize: N` → `'var(--fs-*)'`; CSS `font-size: Npx` → `var(--fs-*)`.

Deliberately **not** migrated:
- Recharts / SVG props (`tick=`, `label={{…}}`, `fontSize=`) — presentation attributes don't resolve `var()`.
- `styles/ind-report.css` — styling of the printed IND document, not the app UI.
- rem-based sizes on the auth pages (own scale, already ≥12px).

Safety checks: no migrated value is used in arithmetic; the one changed file with canvas code
(`density-map-viewer.tsx`) only had a DOM `<span>` class changed.

105 files changed. To retune sizes later: edit the plan JSON token sizes, re-run `--apply`
(or just edit the token block values — every site references the tokens).

## Verification

- `tsc --noEmit` clean · Tailwind compiles (`.text-xs { font-size: var(--fs-sm) }`) ·
  vitest 245 files / 2513 tests passed (42 skipped).
- Render of the exact plan on live dev (before/after images in `docs/20261110_ui_type_ramp/`).
- Pending: sync to dev after PR checks + re-screenshot of the deployed build.

## Open

- Panel Key-Results table still wraps the Interpretation column — column widths, not size.
- Workflow-panel tab strip band. (Run Manager redesign: declined by founder 2026-11-10 — out of scope.)
- Dark mode not reviewed.
