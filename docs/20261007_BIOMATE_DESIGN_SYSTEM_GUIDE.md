# BioMate Design Style Guide

Canonical visual spec for making the product's appearance match the
`data_centroid_design_v2` reference. Extracted from the design-system sources:

- `reference/claude_design/data_centroid_design_v2/BioMate Prototype (standalone).html` — the live prototype; **source of truth for product tokens** (`:root` custom properties + component CSS).
- `reference/claude_design/data_centroid_design_v2/spec/*.html` + `spec.css` — the written spec documents (narrative + element tables). NOTE: `spec.css` styles the *spec documents themselves* (they use IBM Plex); it is **not** the product theme. The product theme is Inter, defined in the prototype.
- `reference/claude_design/data_centroid_design_v2/SIMPLIFICATION_DECISIONS.md` — accepted product direction / aesthetic principles.

Colors in the prototype are authored in **OKLCH** (with light + dark themes). OKLCH values below are **canonical — implement these**. Hex values are **approximate sRGB conversions** for quick reference only; do not treat them as exact.

---

## 1. Color palette (light theme — canonical OKLCH)

All tokens are CSS custom properties on `:root`. The product ships a dark theme too (same token names, redefined under the dark scope).

### Neutrals (cool-leaning, low saturation)
| Token | OKLCH (canonical) | ~hex (approx) | Use |
|---|---|---|---|
| `--bg` | `oklch(0.99 0.003 240)` | ~#fcfcfd | App background (behind everything) |
| `--bg-elev` | `#ffffff` (literal) | #ffffff | Elevated surfaces: cards, composer, active nav item, buttons |
| `--surface` | `oklch(0.985 0.003 240)` | ~#fafbfc | Sidebar, module cards (closed), stages |
| `--surface-2` | `oklch(0.965 0.004 240)` | ~#f4f5f7 | Hover fills, secondary-button hover, user chat bubble |
| `--surface-3` | `oklch(0.945 0.005 240)` | ~#edeef1 | Deepest neutral fill (icon tiles, letter chips) |
| `--border` | `oklch(0.915 0.006 240)` | ~#e3e5e9 | Default hairline borders, table row dividers |
| `--border-strong` | `oklch(0.86 0.008 240)` | ~#d2d5db | Emphasized borders: composer, open card, intent bar |
| `--text` | `oklch(0.22 0.01 260)` | ~#1f2430 | Primary text / headings |
| `--text-muted` | `oklch(0.48 0.012 260)` | ~#5f6672 | Secondary text, nav labels, chip text |
| `--text-dim` | `oklch(0.62 0.010 260)` | ~#868c97 | Tertiary: placeholders, captions, sub-labels |

### Accent — single cool blue, used sparingly
| Token | OKLCH | ~hex | Use |
|---|---|---|---|
| `--accent` | `oklch(0.55 0.14 245)` | ~#1f6fd4 | Primary blue: active icons, focus rings, accent button, send button, active tab underline |
| `--accent-soft` | `oklch(0.96 0.03 245)` | ~#e8f0fb | Tinted accent backgrounds, focus glow, active-phase halo |
| `--accent-ink` | `oklch(0.38 0.12 245)` | ~#1a4a9c | Dark-blue text/ink on soft-accent fills, links (matches spec link `#1a4a9c`) |

### Semantic / status
Each status has a strong color + a soft tint pair (`-soft`). Status is **never color-only** — always pair with a word (see §9).
| Token | OKLCH | ~hex | Token (soft) | OKLCH |
|---|---|---|---|---|
| `--ok` | `oklch(0.62 0.13 150)` | ~#2f9e5f | `--ok-soft` | `oklch(0.96 0.04 150)` ~#e6f6ec |
| `--warn` | `oklch(0.72 0.14 75)` | ~#c58a1a | `--warn-soft` | `oklch(0.96 0.05 75)` ~#fbf1dd |
| `--err` | `oklch(0.58 0.18 25)` | ~#d23b2e | `--err-soft` | `oklch(0.96 0.05 25)` ~#fbe8e5 |
| `--run` | `oklch(0.55 0.14 245)` | (= accent blue) | `--run-soft` | `oklch(0.96 0.03 245)` |
| `--neutral-badge` | `oklch(0.92 0.006 260)` | ~#e6e8eb | — | (badge / count-pill background) |

### Table structural colors (color does structural work — spec §0.10.2)
| Token | OKLCH | Use |
|---|---|---|
| `--head` | `oklch(0.935 0.035 245)` | Tinted **uppercase header band** on data tables |
| `--head-ink` | `oklch(0.42 0.09 250)` | Header-band text |
| `--band` | `oklch(0.975 0.012 245)` | Zebra banding (first-of-group row `.r1`) |
| `--band-2` | `oklch(0.962 0.020 245)` | Secondary zebra band |
| `--rail` | `oklch(0.72 0.11 250)` | Left accent rail on first row of a group |
| `--tint-ok` | `oklch(0.972 0.032 150)` | Pass-cell tint |
| `--tint-warn` | `oklch(0.972 0.040 78)` | **Flagged cell** tint (amber + outline = visible evidence behind a verdict) |

---

## 2. Typography

**Font families (canonical):**
- `--font-ui: 'Inter', system-ui, -apple-system, sans-serif`
- `--font-mono: 'JetBrains Mono', 'SF Mono', Menlo, Consolas, monospace`

### ⚠️ Headings are SANS, not serif
The design uses **Inter for every heading and title** — there is **no serif anywhere** in the prototype (grep for serif/Georgia/Fraunces/etc. returns nothing; all `font-family` references are `--font-ui`, `--font-mono`, or system sans). **The product currently uses a serif panel heading; that is a deviation from the design and should be changed to Inter (sans, weight 600).**

### Mono is for identity/precision, not prose
Mono (`--font-mono`) is used for: file chips, parameter values/inputs, numeric/findings tables, badges & count-pills, section eyebrow labels (uppercase, letter-spaced), progress chips, phase-letter tiles. Tabular numerals for numeric columns.

### Scale (observed in prototype)
| Role | Size / weight / line-height | Notes |
|---|---|---|
| Cold-start question ("What are you trying to do?") | **18px / 600** | spec §0.4.2; a question, centered |
| Panel / doc title | 14–14.5px / 600 (`.doctitle` 14.5/1.35) | sans, NOT serif |
| Section / card title (`.thead .tk`) | 12.5px / 600 | |
| Topbar `.title` | 13.5–14px / 600, letter-spacing −0.005em | |
| Body / chat bubble | 13.5px / 1.6 | `.bubble` |
| Default content body | **12.5px / 1.55** | most common in prototype |
| Nav item label | 13px / (600 when active) | |
| Nav sub-label (`.nsub`) | 11px / 400, `--text-dim` | |
| Chip / badge | 11–11.5px / 500 | |
| Small mono labels / eyebrows (`.barlab`) | 10px / 600, letter-spacing .09em, UPPERCASE, mono | e.g. "DESCRIBE THE GOAL" |
| Count pill (`.nb`) | 10px / 600 mono | |
| Micro tags (`.vtag`, `.expbadge`) | 9–9.5px / 600 mono | |

**Density note / discrepancy:** The written spec (§0.10.1) *aspires* to a 14px base ("was 12.5px → now 14px"). The actual prototype CSS still runs denser — base content is predominantly **12.5–13.5px**. Implement the prototype values for fidelity to the rendered reference; if the team wants the spec's roomier density, bump the base to 14px globally, but that is a documented aspiration, not what the reference image shows.

---

## 3. Spacing

No single `--space-*` scale token exists; spacing is applied per-component but follows a consistent rhythm (multiples of ~2–4px). Observed values:

- **Component gaps:** 6, 7, 8, 9, 10, 11px (small UI); **grid/section gaps:** 14, 20px
- **Card padding:** `.card2` = **16px 18px** (older variant 14px; tight-density 11px)
- **Composer padding:** `.composer2` = 10px 12px; `.composerwrap` = 14px 24px 18px
- **Cold-start container:** `.colddash` padding `56px 24px 32px`, `gap: 20px`, `max-width: 840px`, centered
- **Nav item padding:** 6px 10px; **button padding:** 0 12px (height-based)
- **Table cell padding:** 9px 12px
- Spec §0.10.1 target: card padding 16/18, page padding 20/22

**Layout widths:** `--sidebar-w: 220px` (responsive steps: 224/206/184/168), `--panel-w: 500px` (right panel; responsive 480/400/360). Shell is CSS grid: `sidebar-w | 6px grip | 1fr`. Panes are drag-resizable (6px grip, double-click resets) and collapsible — collapse by zeroing width, never `display:none` (spec §0.11).

---

## 4. Border radius

| Token | Value | Typical use |
|---|---|---|
| `--r-xs` | **4px** | Small buttons (`.btn.sm`), letter tiles, inline inputs |
| `--r-sm` | **6px** | Buttons, nav items, inputs, stages, route box |
| `--r-md` | **8px** | Cards (`.card2`, `.modcard`), composer rows, intent bar, phase tabs |
| `--r-lg` | **12px** | Composer (`.composer2`) |
| `--r-xl` | **16px** | Largest containers |
| pill | **999px** | Chips, badges, domain pills, count pills |

(One card variant uses literal `border-radius: 10px`.)

---

## 5. Shadows / elevation

Soft, low, cool-shadow (slate-tinted) elevation — understated.
| Token | Value |
|---|---|
| `--shadow-sm` | `0 1px 2px rgba(15,23,42,0.04)` |
| `--shadow-md` | `0 1px 3px rgba(15,23,42,0.06), 0 4px 12px rgba(15,23,42,0.04)` |
| `--shadow-lg` | `0 4px 12px rgba(15,23,42,0.08), 0 16px 40px rgba(15,23,42,0.06)` |

Usage: `-sm` on active nav item, composer, open card; `-md`/`-lg` for popovers/panels. Elevation is subtle — the UI leans on borders + surface tints more than shadow.
**Focus ring:** `box-shadow: 0 0 0 2px var(--accent-soft)` on inputs; `0 0 0 3px oklch(0.96 0.03 245)` halo on active phase tab (green/red variants swap the hue).

---

## 6. Iconography

- **Custom inline SVG**, monochrome, drawn with `currentColor` — **not** a named icon library (no lucide/feather/heroicons/phosphor class hooks found). Icons inherit the text color of their context.
- **Line/outline style**, thin single-weight strokes (no explicit `stroke-width` override found → relies on path geometry / default). Visually consistent with lucide/feather line icons.
- **Sizing:** nav icons ~16px, rendered at `opacity: .7` by default (`.navitem .ni`), becoming full-opacity `--accent` blue when the item is active. Icon tiles in module cards are rounded squares filled with `--surface-3`/`--accent-soft`.
- Status "dots" are 6–7px `border-radius:999px` filled with `currentColor` (chip) or a status color.
- If replacing with a library, use **lucide** (thin line, currentColor) for the closest match.

---

## 7. Core component patterns

### Sidebar item (`.navitem`)
```
display:flex; gap:9px; padding:6px 10px; border:1px solid transparent;
border-radius:6px; background:none; color:var(--text-muted); font-size:13px;
icon (.ni): opacity:.7
:hover  → background:var(--surface-2); color:var(--text)
.on     → background:var(--bg-elev); border-color:var(--border); color:var(--text);
          font-weight:600; box-shadow:var(--shadow-sm); icon → color:var(--accent), opacity:1
.nsub   → 11px/400, --text-dim (optional second line)
.nb     → right-aligned count pill: mono 10px/600, bg --neutral-badge, radius 999px
```
Section eyebrows (e.g. "WORKSPACE", "PROJECTS") are mono uppercase, `--text-muted`, small + letter-spaced.

### Card (`.card2` / module card `.modcard`)
```
.card2  : border:1px solid var(--border); border-radius:8px; background:var(--bg-elev); padding:16px 18px
.modcard: border:1px solid var(--border); border-radius:8px; background:var(--surface); overflow:hidden
.modcard.open: border-color:var(--border-strong); background:var(--bg-elev);
               grid-column:1/-1 (spans row); box-shadow:var(--shadow-sm)
.modhd  : grid [icon | title/desc | chevron]; padding:13px 14px
```
Module cards: icon tile + name (bold) + lane label + one-line description + chevron. Only one open at a time.

### Buttons (`.btn`)
```
base    : height:32px; padding:0 12px; radius:6px; border:1px solid var(--border);
          background:var(--bg-elev); color:var(--text); font-size:13px/500;
          transition:background .12s, border-color .12s, transform .06s
:hover   → background:var(--surface-2)
:active  → transform:translateY(0.5px)
:disabled→ opacity:.5; cursor:not-allowed
```
Variants:
- **`.primary`** (dark/neutral solid): `background:var(--text); color:var(--bg-elev); border-color:var(--text)`; hover → `oklch(0.32 0.012 260)`. This is the default high-emphasis button — **solid near-black, not blue.**
- **`.accent`** (blue solid): `background:var(--accent); color:#fff`; hover `filter:brightness(.96)`. Used for the **send/submit** affordance.
- **`.ghost`**: transparent border + bg; hover → `surface-2`.
- **`.danger`**: `color:var(--err)`; hover → `err-soft`.
- **`.sm`**: height 26px, padding 0 8px, 12px, radius 4px.
- **`.wide`**: full-width primary (used for "New chat"): solid `--text`, white text, 600, padding 9px.

### Input / composer (`.composer2`, `.intentbar`, `.searchbox`)
```
.composer2: max-width:660px; border:1px solid var(--border-strong); border-radius:12px;
            padding:10px 12px; background:var(--bg-elev); box-shadow:var(--shadow-sm);
            flex-column; gap:9px
.crow     : toolbar row under the textarea; border-top:1px solid var(--border); padding-top:9px
.sendgrp  : right-aligned send cluster (accent send button)
.intentbar: cold-start search: border:1px solid var(--border-strong); border-radius:8px;
            background:var(--bg-elev); padding:11px 12px; box-shadow:var(--shadow-sm);
            leading sparkles glyph in --accent; send disabled while empty
input     : border:none; background:transparent; font-size:14.5px; color:var(--text)
            ::placeholder → --text-dim
inline param input: border:1px solid var(--border); radius:3px; mono 11.5px;
                    :focus → border-color:var(--accent)
```

### Tabs (`.after-run-tab`, `.phase-tab`)
```
.after-run-tab: text tab, underline style. padding:8px 12px; font 12.5px; color:--text-muted;
                border-bottom:2px solid transparent
   :hover  → color:--text
   .active → color:--text; border-bottom-color:var(--accent); font-weight:600
.phase-tab: pill/box tab. border:1px solid var(--border); radius:8px; bg:--bg-elev;
            leading 22px letter-tile (.ptab-letter, mono, bg surface-3)
   .active          → border-color:--accent + 3px accent halo; letter-tile → bg accent/#fff
   .completed.active→ green border + green halo
   .failed.active   → red border + red halo
```
After-run tabs are exactly three: **Summary · Outputs · Reproducibility record** (spec).

### Badge / chip (`.chip`, `.tag`, `.file-chip`, `.dompill`)
```
.chip     : inline-flex; gap:6px; padding:2px 8px; radius:999px; font 11.5px/500;
            background:var(--neutral-badge); color:var(--text-muted)
   .ok/.run/.warn/.err → swap to the matching -soft bg + strong color
   .dot → 6px currentColor circle
.file-chip: padding:4px 8px; radius:6px; border:1px solid var(--border); bg:--bg-elev;
            mono 11.5px; has a 7px quality dot (.fc-q) + ellipsized name
   .auto / :hover(is-dataset) → accent border + --accent-soft bg
.dompill  : domain pill, radius:999px, padding:6px 13px, 12.5px; hover → accent border + soft bg
.vtag     : version micro-tag, mono 9px/600, --accent-soft bg, --accent-ink text
```

### Table (data table `.dtable`)
```
.dtable    : CSS grid; border:1px solid var(--border); radius:6px; font-size:12px; overflow:auto
.dth (head): background:var(--head); color:var(--head-ink); mono-ish 10.5px/650 UPPERCASE,
             letter-spacing .06em; padding:9px 12px; position:sticky top:0
.dtd (cell): padding:9px 12px; 12.5px; first column → font-weight:600
.dtd.r1    → background:var(--band)   (zebra / first-of-group)
.dtd.flag  → background:var(--tint-warn); inset 0 0 0 1px var(--warn)  (flagged cell)
```
Every row family gets: tinted uppercase header band, zebra banding, hover state, left accent rail on group's first row, tabular numerals, amber-outlined flagged cells (spec §0.10.2).

---

## 8. Overall aesthetic principles (from SIMPLIFICATION_DECISIONS.md + spec)

- **All-day desktop professional tool, not a compact web app.** Roomier type and spacing than a typical SaaS; calm, dense-but-legible.
- **Quiet neutral canvas, one cool-blue accent used sparingly.** Near-white cool-gray surfaces; blue reserved for active/interactive state and the send action. High-emphasis primary button is solid near-black, not blue — blue doesn't get spent on generic CTAs.
- **Borders + surface tints over shadows.** Elevation is subtle; structure is drawn with hairlines and tint steps (surface → surface-2 → surface-3).
- **Color does structural work in tables** — header bands, zebra, rails, amber flag cells — so dense data stays followable.
- **Legibility & honesty of state:** status is always a word + color (never color alone); numbers are traceable links; parameters shown as *resolved* with origin; disabled-not-hidden for permissions.
- **Make the normal path small:** state goal → supply missing inputs → run → read Summary → inspect Outputs → open Reproducibility record when needed. Advanced choices (lane switching) are tucked away.
- **Four equal entry points** (Search & evidence, Data analysis, Models, Design & generate) as a 2×2 grid of equal cards — each one practical scientific job.
- **No inventory, no self-explanation in UI copy.** No catalog of workflow names/counts; the UI never argues for its own design in body text. Nav items are a label only; explanation lives on the surface.
- **Cold start is a question** ("What are you trying to do?"), centered, max-width 840px, not an empty box.
- **Mono = precision/identity** (files, params, ids, numbers, eyebrow labels); **Inter sans = everything human-readable, including all headings.**

---

## 9. Status vocabulary (spec §0.12)

| State | Word | Color token |
|---|---|---|
| Pending | PENDING | neutral (`--neutral-badge`) |
| Running | RUNNING + spinner | accent (`--run`/`--accent`) |
| Completed | DONE | `--ok` (green) |
| Failed | FAILED | `--err` (red) |
| Skipped | SKIPPED | neutral, dashed (never red) |
| Halted (QC gate) | gate chip + panel | `--warn` (amber) |

---

## 10. Key deviations the frontend team must fix

1. **Serif panel heading → Inter (sans, 600).** The design has zero serif; current product serif headings are off-spec.
2. **Confirm Inter + JetBrains Mono are loaded** (not IBM Plex — that's only the spec-document font).
3. **Primary (high-emphasis) button is solid near-black (`--text`), not blue.** Blue (`--accent`) is reserved for the send/submit action and active state.
4. **Adopt OKLCH tokens** (the hex column here is approximate). Define the full `:root` token set incl. the dark theme redefinitions.
5. **Data tables need the structural color system** (header band, zebra, flag cells), not flat single-tint tables.
