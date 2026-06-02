# 2026-06-02 — Website: Tutorials Page, Intro Video, Logo, Contact Form

## What was changed

### 1. Navigation — `shell.js`
- Added **Tutorials** menu item to desktop nav, mobile nav, and footer Company column
- Links to `tutorials.html`

### 2. Index page — `index.html`
- Added intro video section before the CTA banner
- YouTube embed `bpG0IWrwN5g`, muted by default (`?mute=1&rel=0`), full-width 16:9 iframe

### 3. New page — `tutorials.html`
- 2-column grid of 4 tutorial YouTube embeds:
  - `bpG0IWrwN5g` — BioMate Intro
  - `C4gQD-xbHnQ` — CryoSPARC SPA (workflow + run)
  - `F2DgmBa5gq8` — After-run report & outputs
  - `IDcICWmB0Oo` — IND Report generation
- Uses `renderShell({ active: 'tutorials' })`

### 4. Logo — `assets/logo.png`
- Auto-cropped cream background (RGB 242,236,217) with PIL
- Content bounding box: cols 152–1349, rows 30–751
- Re-scaled to fill 1380px width with 2% padding
- Logo content appears ~15% larger in the nav

### 5. Contact form — `contact.html`
- Replaced non-functional `mailto:` form action with **Formspree** JSON fetch
- Formspree endpoint: `https://formspree.io/f/xlgvqqvz`
- On success: form hides, green checkmark + "Message sent!" confirmation shown inline
- On network failure: red error banner with direct email fallback
- Button shows spinner while submitting
- HTML5 validation (name + email required) before fetch

## Tutorial video pipeline changes (reference/claude_design/tutorials-work/)

- **Removed time references** from `Tour.jsx` (tip labels, hint text) and `generate_vo.py` (voiceover steps)
- **Panel width** set to equal split: `cyro_tutorial` panelWidth → 850; prod app `chat-with-artifacts.tsx` → 840
- **Re-recorded** outputs_report and drug_screen from `cyro_tutorial/` source (plan checklist commented out, progress fold collapsed by default)
- **Branding overlay** applied to all 4 videos via `make_video.py`
- `regen_steps.py` added for incremental ElevenLabs clip regeneration without re-recording full videos

## Known issues / open items
- Formspree free tier: 50 submissions/month. Upgrade at formspree.io if volume exceeds that.
- The linter in this project aggressively reformats/reverts `contact.html` — if it reverts again, re-run the Write tool with the full file content (not Edit).
