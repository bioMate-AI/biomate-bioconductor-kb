# UI contrast tuning — Gemini-driven (2026-11-10)

## Directive

Founder, on the Gemini design review (`docs/20261110_UI_DESIGN_REVIEW_GEMINI.docx`):
"I don't want to change to purple, however, the main idea is agreed. The current UI of
BioMate uses too much light grey colors, without difference among elements — boring and
hard to read … Ask Gemini to tune the appearance of the UI."

## Root cause

Every surface token sat within 1–4% lightness of white, so no region separated from another:

| Token (light) | Before | After |
|---|---|---|
| `--background` (canvas) | `206 56% 99%` | `212 20% 95%` (tinted canvas) |
| `--card`, `--sidebar`, `--popover` | `206 37% 98%` | `0 0% 100%` (white surfaces) |
| `--border` / `--card-border` | 89% / 82% | `212 15% 85%` |
| `--muted-foreground` (secondary text) | `217 6% 37%` | `212 15% 38%` |
| `--foreground` | `217 13% 11%` | `212 20% 12%` |
| `--bm-*` / `.wf-panel` surfaces | 0.985 / 0.965 / 0.945 | white / 0.97 / 0.93 on a 0.96 canvas |
| `--bm-text-muted` / `--bm-text-dim` | 0.48 / 0.62 | 0.45 / 0.55 (darker) |
| status ok/warn/err | 0.62 / 0.72 / 0.58 | 0.50 / 0.60 / 0.55 (readable on soft fills) |

Brand accent stays **cerulean `hsl(202 100% 37%)` / `#007fbd`** — the prototype's indigo was not adopted.

## Process (Gemini as the tuner, verified each round)

Loop: real dev screenshots + prototype images + real token sheets → `google/gemini-3.1-pro-preview`
returns a CSS override → injected into the live dev page with Playwright → re-screenshotted →
fed back with verified critique. Tools committed:

- `frontend/scripts/ui_tune_capture.mjs <outDir> [override.css]` — logs in as the fixture, renders
  landing / Run Manager / workspace+panel on dev, optionally with an override injected.
- `frontend/scripts/gemini_ui_tune.py <screensDir> <out.css> [prev.css]` — the Gemini call
  (env: `TOKENS`, `PROTO_IMAGES`, `EXTRA`, `SELECTORS`).

| Round | Gemini proposal | Verified on render |
|---|---|---|
| 1 | tinted canvas, white cards, darker text, `font-size:14.5px` | separation good; font bump had no effect; composer band; Run-again still black |
| 2 | back to white canvas, `html{font-size:110%}` | **regressed** — grey-on-grey back, rem layout scaled unevenly; its claims didn't match the render |
| 3 | tinted canvas (L95) + white surfaces, darker meta/status, no root scaling, type ramp as comment | accepted (with the deviations below) |

Raw responses + the round-3 override: `docs/20261110_ui_contrast_tuning/`.

### Deviations from Gemini's round 3 (deliberate)

- **Body text kept at `0.22`** — Gemini set `--bm-text`/`--text` to 0.25, lighter than today; that would cut contrast.
- **Categorical data colours kept** (`--chart-3`, `--bio-purple`, `--bm-loop`). Gemini recoloured these to navy; they are
  data-series / speaker-pill category colours, not the brand accent, and navy would collide with the existing blue series.
- **No global enforcement rules** (`body`, `[data-sidebar]`, `.wf-panel` backgrounds) — the tokens drive these already.

## Source fixes tokens could not reach

- `workflow-panel.css` `.wf-panel .btn.primary` used `background: var(--text)` (near-black) → now `var(--accent)`.
  This is why "Run again / Confirm and run" was black regardless of the accent token.
- Composer double frame: `chat-interface.tsx` wrapper (border-top + white fill) **and** `chat-input.tsx`
  (`border-t bg-background p-4`) both framed the input; on a tinted canvas this showed as an inset strip.
  Both frames removed — the input card floats on the canvas as in the prototype.

## Before / after (dev, emulated via injected CSS identical to the committed values)

Before: `before_landing.png`, `before_workspace.png` · After: `after_landing.png`, `after_workspace.png`
(in `docs/20261110_ui_contrast_tuning/`).

## Verification

- `npx tsc --noEmit -p .` — clean
- `npx vitest run` — 260 files passed, 2644 tests passed (3 files / 43 tests skipped, pre-existing)
- Dev render with the emulation CSS — three screens audited above.
- **Not yet done:** sync to dev + re-screenshot from the deployed build (pending PR checks per deploy process).

## Open — next steps

1. **Typography** (biggest remaining "hard to read" factor). Text is 11–13px and set in hundreds of inline px
   values (79 in `v2/AfterRunReport.tsx`, 74 in `nextflow-workflow-viewer.tsx`, many in `reference-design.css`),
   so it cannot be fixed by tokens or by scaling the root. Gemini's proposed ramp: page title 24/1.2 semibold ·
   section 18/1.3 · body 15/1.5 · meta 13/1.5 · micro-label 11 uppercase · mono 13. Implement as type tokens,
   then sweep the inline sizes onto them, file by file, with before/after renders.
2. Workflow-panel tab strip still sits on a faint grey band (`--bg` inside `.wf-panel`) — decide band vs. flat.
3. Run Manager cards: dense-list redesign from the Gemini review (raw hashes de-emphasised, status-coloured headers).
4. Dark mode untouched — light only this pass.
