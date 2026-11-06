# Tutorial Walkthrough HTML — Design Reformat Brief

**Date:** 2026-10-19
**For:** a Claude design pass to reformat the tutorial walkthrough decks.
**After the reformat:** screenshots and narration are re-applied/updated on top (the
reformat must leave clean slots for both).

---

## 1. Files to reformat

**Directory:** `reference/claude_design/tutorials_v2/`

**44 walkthrough decks** (22 tutorials × EN + 中文) — each `<name>-walkthrough.html`
and `<name>-walkthrough.zh.html`:

```
t0-getting-started      t1-design-and-generate   t2-models-and-the-closed-loop
t3-run-and-report       t4-bringing-your-own-data
m1-search-and-evidence  m2-rnaseq-differential-expression  m3-accession-to-workflow
d1-qsar-classical-ml    d2-admet-deep-learning   d3-generative-lead-design
d4-binding-free-energy  s1-noncompartmental-pk   s2-pbpk-simulation  s4-survival-analysis
rb-routing  rb-param-prefill  rb-protocol-qc  rb-boin
qpcr-ddcq   b1-train-custom-model   drug-dev
```

**Shared stylesheet:** `reference/claude_design/tutorials_v2/_v2lib.css` (138 lines)
**Assets (keep paths):** `reference/claude_design/tutorials_v2/assets/` (incl. `assets/live/`)

> Start with **t0–t4** (these are the shipped video series); the m/d/s/rb/qpcr/b1/
> drug-dev decks follow the same template, so the same reformat applies.

---

## 2. What these are

Each file is a **16:9 auto-playing slide deck** used to **record a narrated tutorial
video**. Structure today:
- a brand header (`assets/biomate-logo.png`),
- an ordered list of `<section class="scene" data-seconds="N">` slides,
- each scene has a `.caption` (on-screen prose, ~70ch) and a `.scene-body` (the visual
  area: product **screenshots** `<img src="assets/…">`, concept tiles, or data viz),
- an inline `<script>` that auto-advances scenes and publishes a timeline for the
  recorder.

A separate narration script (`narration/<name>.{en,zh}.md`, one `## Step N` per scene)
is read by TTS and muxed onto the recording. **Scene N ↔ narration Step N ↔ audio clip
N** — this mapping is load-bearing.

---

## 3. Design goal

Make the decks look **professional, consistent, and crisp on video** — a single,
polished visual system across all 44 files, aligned with BioMate's product design.
Priorities: clarity and legibility at 1080p, consistent typographic rhythm, generous
whitespace, calm/credible (scientific, not "salesy"), and a screenshot that always
reads cleanly as the hero of its slide.

### Visual system (align to BioMate product design)
- **Palette:** BioMate's `--bm-*` oklch tokens (see `frontend/client/src/styles/
  reference-design.css` / the data-centroid design v2). Light theme (videos are light).
  Neutral surfaces, one accent for emphasis; high contrast for projection/compression.
- **Typography:** the product's sans stack (Google Fonts allowed); a clear scale —
  slide heading, caption (body ~18px/1.5, max ~70ch), sub-caption/muted, mono for
  code/IDs. 中文 must use a CJK-appropriate face and line-height.
- **Layout grid:** fixed 1920×1080 stage, consistent safe margins, brand header top,
  a predictable split between caption and `.scene-body`, an unobtrusive scene/progress
  indicator. Screenshots framed consistently (subtle border/shadow, rounded to the
  product's radius), never stretched.
- **Motion:** keep transitions minimal and recording-safe (short opacity/transform on
  `.scene.active`, as today) — no long animations that fight the fixed scene timing.

---

## 4. MUST PRESERVE — the recording/mux contract (do not break)

The video pipeline (`scripts/recording/record-walkthrough-*.py`, `fit-scene-slots.py`,
`mux-walkthrough-*.py`) depends on these. **A reformat that changes them desyncs every
video.**

1. **One `<section class="scene" …>` per scene, same count and same order** as today.
   Narration/audio map to scenes positionally — adding, removing, or reordering a scene
   breaks the audio alignment.
2. **`data-seconds="N"` on every scene** (per-scene duration; the fitter rewrites these
   to match narration — keep the attribute present and one-per-scene).
3. **`data-kind` and `data-added` attributes** on scenes that have them (these mark the
   中文-only live-product scenes) — keep them on the same scenes.
4. **The auto-play script must keep publishing** `window.__timeline` (array of scene
   start seconds), `window.__done`, and toggling the `.scene.active` class, and must
   keep honoring `data-seconds` / an injected `window.__sceneDurations`. The recorder
   reads exactly these.
5. **Screenshot slots:** keep each scene's `<img src="assets/…">` (and `assets/live/…`)
   references intact and clearly placed, so updated screenshots drop in without layout
   surgery. Where a scene shows a concept tile instead of a screenshot, keep an obvious
   titled container.
6. **`.caption` text stays per scene** (it is the on-screen reading line that pairs with
   the narration). This is a visual reformat, **not** a copy rewrite — keep the existing
   caption/scene text and asset references; only restyle and re-lay-out.
7. **EN and 中文 parity:** the two files of a tutorial keep identical scene structure
   (same count/order/kinds); only the language of captions differs.
8. **Fixed 1920×1080 stage** that renders correctly in **headless Chromium** (the
   recorder) with local assets + Google Fonts only — no external runtime JS/CDN beyond
   fonts, fully self-contained.

---

## 5. Deliverable from the design pass
- Restyled `*-walkthrough.html` / `*.zh.html` (same filenames) + a consolidated
  `_v2lib.css` (prefer shared CSS over per-file inline `<style>` for consistency).
- Every item in §4 preserved and verifiable (scene count unchanged; `window.__timeline`
  still published; images still slotted).
- Renders cleanly at 1920×1080 in headless Chromium with no broken images.

> After the reformat lands, this session re-applies: (a) **updated screenshots**
> (captured from the current dev UI into `assets/`), and (b) **corrected narration**
> (already fixed in `narration/`), then re-records + re-muxes the videos.
