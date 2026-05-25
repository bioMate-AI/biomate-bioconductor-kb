# Tutorial Video Pipeline — Final Delivery & Polish

**Date:** 2026-05-19
**Branch:** `integration/next-phase`
**Predecessor:** `docs/20260518_TUTORIAL_VIDEO_PIPELINE.md`
**Status:** 10 videos delivered with polish, design HTML fully cleaned

This doc captures the bugs hit + fixes shipped during the final delivery pass after `20260518` documented the v1 pipeline.

---

## 1. Final delivery table

| Demo | EN duration | ZH duration | Title overlay |
|---|---|---|---|
| `ra-cryo` | 2:40 | 2:40 | Cryo-EM Single-Particle Analysis |
| `ra-afterrun` | 2:46 | 2:46 | Run Report — Outputs, Methods, Citations, QC Audit |
| `ra-drugscreen` | 3:23 | 3:23 | Drug Screen · Auto-Loop & Run-vs-Run Comparison |
| `ind` | 3:21 | 3:21 | Expert · AI Collaboration · IND §2.6 Document |
| `website-quickstart-v2` | 3:03 | 3:03 | BioMate Quick Start · From Signup to First Analysis |

Each EN video has English narration only; the ZH variant burns natural-Chinese subtitles on top of the same English audio + identical visual content.

Every video:
- **Title overlay** at top-center (white text on dark box, 28 pt Noto Sans CJK Bold)
- **Bottom-right watermark** `biomate.ai · contact@biomate.ai` in bright yellow on dark box
- **48 kHz stereo AAC** audio (audible on every standard player)
- **moov atom at file start** (`+faststart`) so browsers/QuickTime play immediately
- **No AWS / Amazon mentions**
- **No time estimates** in narration or in design UI cards
- **Cryo phase B/C/D/E** beats describe each phase in one sentence (no enumeration of tools)

---

## 2. Bugs hit in this delivery pass

### 2.1 ffmpeg drawtext drops the trailing glyph
**Symptom:** watermark "biomate.ai · contact@biomate.ai" rendered as "biomate.ai · contact@biomate.a" — last `i` clipped. Reproducible regardless of font, escape style, or `box=` setting.
**Cause:** ffmpeg drawtext's Pango glyph-advance calculation truncates the last character's advance width, causing the rightmost glyph to render outside the computed text-width box.
**Fix:** write watermark text to a sidecar file with trailing spaces, use `textfile=` (not inline `text='...'`). Confirmed full text now renders. Applied in `merge-audio-aligned.py` and `record-tutorial.sh`. Same trick applied to the title overlay.

### 2.2 Cryo tour's cartoon SVG ring made every click hang ~30 s
**Symptom:** ra-cryo + ra-afterrun videos came in at 11:25 and 8:46 instead of ~3 minutes. Each step gap was ~37 s where audio was ~10 s.
**Cause:** Cryo tour uses `cartoon: true` which renders an animated `<rect class="tour-ring-dash" stroke-dasharray="6 5">` element. Playwright's `.click()` waits for the element to be "stable" (no motion); the dashed-stroke animation never stabilises, so each click stalled for Playwright's full 30 s timeout.
**Fix:** `click_next` now uses `click(force=True, timeout=2000)` — skips stability check.

### 2.3 ZH subtitles read as "electric telegram"
**Symptom:** ZH subs like "管线不崩溃, auto-loop 提" or "hERG/Ames 警示触发 war" — staccato fragments with words clipped mid-character.
**Cause:** my LLM prompt's hard 16-char/line cap forced Gemini to drop connecting words and the post-LLM regex hard-cap at 18 chars cut the rest mid-glyph.
**Fix:** prompt rewritten to explicitly demand "正常的中文句子,保留必要的连接词、助词、标点; 不要让句子像电报"; soft cap raised to 24 chars/line; subtitle box gets `MarginL=120 MarginR=120` so text has horizontal breathing room. ZH subs regenerated; all natural-reading now.

### 2.4 website-quickstart-v2 stuck on login page
**Symptom:** video shows login form for steps 10-14 while audio talks about platform actions. Steps 11-13 failed silently (`Locator.wait_for: Timeout`).
**Cause:** I had assumed the `E2E_TEST_TOKEN` header would bypass authentication. Investigation showed the token only bypasses *rate limiting* — there is no real auth bypass mechanism. The recorder posted with the token, received 401, kept going, never reached an authenticated state.
**Fix:** new `authenticate_via_api()` in `record-website-v2.py` that POSTs real email + password (provided via `BIOMATE_DEMO_EMAIL` / `BIOMATE_DEMO_PASS` env vars), stores the returned JWT in three localStorage keys the SPA reads, then `page.goto(PLATFORM_URL)` to land on the authenticated UI. Hybrid flow:
- steps 1-7: live `https://biomate.ai/` (marketing)
- steps 8-9: live register page → live login page
- steps 10-14: `http://localhost:5000/` (local dev) with JWT-authenticated session
A fresh demo user is registered at the start of the recording session via `POST /api/auth/register` (also with the rate-limit-bypass token). Credentials never appear typed on screen because the login is done via API call, then the platform is loaded with the JWT already in storage.

### 2.5 MP4s wouldn't open in some players
**Symptom:** ra-cryo / ra-afterrun MP4s opened by some players but refused by browsers / QuickTime preview.
**Cause:** moov atom at end of file (`-movflags +faststart` not applied).
**Fix:** every ffmpeg output now includes `-movflags +faststart`. Existing files re-muxed to move moov to front. Verified each output's first 2 KB contains `moov` literal.

---

## 3. Design HTML edits (in `reference/claude_design/`)

In addition to the §3.1/3.2/3.3 edits from the 2026-05-18 doc:

| File | Change |
|---|---|
| `research_agents/src/ResearchApp.jsx` | Rewind-aware `tourFFTo` (predecessor doc §3.1). Verified to fix beats 3 / 7 / 9 / 12 across drug-screen tour. |
| `research_agents/src/ChatCards.jsx` | Time references stripped from PilotPromptCard, PilotPromotionCard, FindingsChatCard. |
| `research_agents/src/research-data.js` | Runtime row removed from comparison-card metrics. |

---

## 4. Pipeline knobs

```bash
# Standard EN+ZH pair (any demo)
TTS_BACKEND=edge PANEL_WIDTH=760 \
  bash scripts/recording/record-tutorial.sh ra-drugscreen Aoede en
TTS_BACKEND=edge PANEL_WIDTH=760 REUSE_AUDIO=1 \
  bash scripts/recording/record-tutorial.sh ra-drugscreen Aoede zh

# Drug-screen needs autoAdvance stretch so beats span ~3 minutes
AUTOADVANCE_MULT=2.3 TTS_BACKEND=edge PANEL_WIDTH=760 \
  bash scripts/recording/record-tutorial.sh ra-drugscreen Aoede en

# website-quickstart-v2 needs real auth
BIOMATE_DEMO_EMAIL=… BIOMATE_DEMO_PASS=… TTS_BACKEND=edge \
  bash scripts/recording/record-tutorial.sh website-quickstart-v2 Aoede en
```

Recurring env vars:
- `TTS_BACKEND=edge|gemini|gtts` — TTS engine (default edge; no quota)
- `PANEL_WIDTH=760` — wider Research-Agent right panel
- `AUTOADVANCE_MULT=2.3` — stretch tour autoAdvance × N for narration-paced length
- `REUSE_AUDIO=1` — skip TTS regen, reuse existing per-step WAVs

---

## 5. Files committed in this delivery pass

Commits on `integration/next-phase`:
- `113e025d` — pipeline scripts, vendored UI, initial `tourFFTo` rewind patch (predecessor doc)
- `464dc59c` — LLM-rewritten narrations (no time, no AWS), design-card edits, predecessor doc
- *this commit* — drawtext truncation workaround, cartoon-ring click-stability fix, hybrid auth in record-website-v2, per-video title overlay, ZH prompt rewrite for natural Chinese, +faststart everywhere, this doc

Total scripts under `scripts/recording/` (15 files):
`build-zh-srt.py`, `compress-en-narration.py`, `condense-zh-subs.py`, `edge-tts-gen.py`, `gemini-tts.py`, `gtts-gen.py`, `merge-audio-aligned.py`, `playwright-record.py`, `record-tutorial.sh`, `record-website-demo.py`, `record-website-v2.py`, `split-narratives.py`, `validate-pacing.py`, `walk-tour.py`.

Narration sources under `reference/claude_design/`:
- `research_agents/narration/{ra-cryo,ra-afterrun,ra-drugscreen,ind}.{en,en.short,zh,zh.subs}.md` (16 files)
- `biomate/website-quickstart-v2.{en,en.short,zh.subs}.md`

Final MP4s (all in `recording/output/`, gitignored): 10 files at the durations in §1.
