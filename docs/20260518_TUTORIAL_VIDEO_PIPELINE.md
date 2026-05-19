# Tutorial Video Pipeline — Research Agent + IND + Website Quick-start

**Date:** 2026-05-18
**Branch:** `integration/next-phase`
**Status:** Pipeline rebuilt; videos pending narration rewrite + recording

Session goal: produce ten ~3-minute tutorial videos (five demos × {EN, EN+ZH-subs}) for the two new Claude-Design UIs (Research Agent + IND Report) and a new website quick-start (`biomate.ai` → register/login → platform first chat). Plus a watermark of `biomate.ai` on every frame.

This document captures the architecture, the bugs found and fixed along the way, and what's left.

---

## 1. Scope

| Demo ID | Tour / page | Beats | Source narration |
|---|---|---|---|
| `ra-cryo` | Research Agent UI → CryoSPARC SPA (`09d`) | 20 | `narration/ra-cryo.{en,en.short,zh,zh.subs}.md` |
| `ra-afterrun` | Research Agent UI → After-run report (`09f`) | 13 | `narration/ra-afterrun.{en,en.short,zh,zh.subs}.md` |
| `ra-drugscreen` | Research Agent UI → Drug screen auto-loop + comparison (`R02`) | 13 | `narration/ra-drugscreen.{en,en.short,zh,zh.subs}.md` |
| `ind` | IND Report (`IndTour.jsx`, no picker) | 24 | `narration/ind.{en,en.short,zh,zh.subs}.md` |
| `website-quickstart-v2` | Live `biomate.ai` → register/login → platform | 14 | `biomate/website-quickstart-v2.{en,en.short,zh.subs}.md` |

For each demo: one English-only video (`<id>-tutorial.mp4`) and one English-audio + Chinese-subtitle-burn video (`<id>-zh-tutorial.mp4`).

---

## 2. Pipeline architecture

```
narration .md  ──► edge-tts ──► per-step *.wav + timing.json
       │                                  │
       │                          ┌───────┴───────┐
       │                          ▼               │
       │                   validate-pacing        │
       │                          │               │
       │                          ▼               │
       │              compress-en-narration       │
       │              (iterates if overflow)      │
       │                                          │
       └► (zh source) ──► condense-zh-subs ──► <id>.zh.subs.md
                                                  │
                                                  ▼
                                           build-zh-srt → <id>.zh.srt
                                                  │
                                                  ▼
recording/audio/<id>/ ──┐                         │
                        ▼                         │
   playwright-record (records raw .webm,          │
   logs step_timestamps.json)                     │
                        │                         │
                        ▼                         │
   recording/video/<id>-raw.webm                  │
                        │                         │
                        ▼                         │
   merge-audio-aligned ─────────────────────────── trim raw video to
   (trim picker; place each cue at recorded       t_first_step; mux
    arrival; biomate.ai watermark; +ZH .srt       per-cue WAVs at
    burn for ZH variant)                          arrival timestamps
                        │
                        ▼
   recording/output/<id>{-zh,}-tutorial.mp4
```

### Scripts (under `scripts/recording/`)

| File | Role |
|---|---|
| `split-narratives.py` | Source: `Demo Narratives.md` (EN, 4 sections) + `Demo Narratives ZH.md` (ZH). Splits into 8 per-demo files in gemini-tts shape. |
| `compress-en-narration.py` | LLM (Gemini Flash) rewrites each step to fit a target spoken duration. Supports `--per-step-seconds` JSON for per-cue targets matching tour autoAdvance. Prompt forbids time references and forces one-line cryo phase descriptions. |
| `condense-zh-subs.py` | LLM-driven brief ZH subtitles (≤28 chars / cue, 1-2 lines). Prompt forbids time references and forces one-line cryo phase descriptions. |
| `edge-tts-gen.py` | Microsoft edge-tts (`en-US-AriaNeural`, rate +25%) — no quota, replaces Gemini TTS (100/day exhausted mid-session). Writes per-step .wav + timing.json + full-narration.wav. |
| `gemini-tts.py` / `gtts-gen.py` | Alternate TTS backends. Selected via `TTS_BACKEND=edge\|gemini\|gtts`. |
| `validate-pacing.py` | **Pre-flight**: generates TTS, compares each cue duration to target beat duration; iteratively recompresses any overflow. Exits 0 only when all cues fit. Prevents the wasted "record→see overflow→rerun" cycle. |
| `playwright-record.py` | Records the tour. Hides `.tut-btn` + `.tour-picker*` via CSS injection (so picker selection is invisible in recording). Pre-loads localStorage tweaks (both `biomate-tweaks` and `biomate-research-tweaks` keys — RA UI reads the second). Mutates `DEMO_TOURS[*].steps[*].autoAdvance × AUTOADVANCE_MULT` *before* tour starts (so step 1 is also scaled). Observes step transitions, writes `step_timestamps.json` with `t_first_step_ms` + per-step `t_visible_ms`. |
| `record-website-v2.py` | Dedicated 14-beat live `biomate.ai` walkthrough using E2E bypass token (no real credentials in recording). |
| `merge-audio-aligned.py` | Trims raw video from `t_first_step_ms` (skips picker frames). Builds aligned audio track: each cue WAV is placed at its recorded arrival time (silence padding between). ffmpeg subtitle burn for ZH variant (Noto Sans CJK SC, FontSize 14). `biomate.ai` watermark (Noto Sans CJK Regular, FontSize 22, semi-transparent black box, bottom-right). 48 kHz stereo AAC output (24 kHz mono fails on many players). |
| `build-zh-srt.py` | Generates .srt cues from ZH brief subs + EN timing.json (so subtitle timing aligns to the English audio). |
| `record-tutorial.sh` | End-to-end orchestrator: `bash record-tutorial.sh <demo-id> [voice] [en\|zh]`. Honors `TTS_BACKEND`, `REUSE_AUDIO=1` (skip TTS regen), `PANEL_WIDTH`, `AUTOADVANCE_MULT`. |
| `walk-tour.py` | **Observer mode** ground-truth tool. Walks a tour at native speed (no recording, no audio), captures 3 screenshots per beat (start/mid/end) so we can audit the design's intended state before recording. |

### Static-server

`reference/claude_design/` is served at `http://localhost:7779/` (Python `http.server`). The recorder + walk both target this URL. `record-tutorial.sh` auto-spawns the server if missing.

---

## 3. Bugs found and fixed

### 3.1 (CRITICAL) `tourFFTo` forward-only walk in `ResearchApp.jsx`

The scenario engine plays many `t: 0` chained events instantly. By the time tour beat N fires `__tourFFTo('marker_N')`, the engine has often already advanced PAST that marker. The original `tourFFTo` walked tape **forward only** from `tapeIdx.current` — when the marker was behind head, the loop walked to end-of-tape applying ALL remaining events, including `dismissCard pilotPrompt`, `dismissCard pilotPromotion`, `dismissCard comparison`. Result: at beats 3, 7, 9 the highlighted card had just been dismissed and was invisible.

**Fix** (`reference/claude_design/research_agents/src/ResearchApp.jsx:311`):

```js
// First find the marker's position in the tape.
let target = -1;
for (let k = 0; k < tape.length; k++) {
  if (tape[k].kind === 'marker' && tape[k].id === markerId) { target = k; break; }
}
if (target < 0) return;
// If marker is BEHIND current head, restart scenario state inline so we
// walk from the beginning. (Without this, forward-only walk would
// overshoot to end-of-tape applying every remaining event including
// dismissCard, wrecking visible state.)
if (target < tapeIdx.current) {
  setHead(0); tapeIdx.current = 0;
  setChatEvents([]); setPlanItems([]);
  setPlanShown(false); setPlanEditing(false); setPlanCollapsed(false);
  setPhaseStates({}); setRunState('idle');
  setDismissedCards({}); setComparePanelData(null);
}
// Then walk forward as before.
```

Verified: walk-tour now captures the pilot prompt, pilot promotion, comparison, and findings cards inside the spotlight at the matching beats.

### 3.2 Recorder pre-loaded wrong localStorage key

Research Agent UI reads `biomate-research-tweaks`; Workflow-Panel-Redesign reads `biomate-tweaks`. I had only been writing the second key for all 4 RA demos. Result: RA tours ran against the default `rnaseq` scenario regardless of which demo I picked — chat events bore no resemblance to the tour tips.

**Fix**: `playwright-record.py:add_init_script` writes BOTH keys.

### 3.3 Recorder set `speed: 900` — engine frozen

`scripts/recording/playwright-record.py` pre-loaded `tweaks_init.speed = 900`. The scenario engine multiplies event delays by `speed`, so 900× froze every chat / QC / animation event. Result: every recording showed a static UI between beats.

**Fix**: `speed: 1.0` (design default).

### 3.4 Step-1 dropped from TTS for files with a top-level `# title`

`gemini-tts.py` / `gtts-gen.py` / `condense-zh-subs.py` / `build-zh-srt.py` all used `re.match(r'## Step ...')` against each `---`-split block. The first block contains the file's `# title` header → `re.match` (anchored at start) fails → Step 1 silently dropped from every audio + subtitle output.

**Fix**: all four scripts now use `re.search` instead of `re.match`.

### 3.5 24 kHz mono AAC inaudible on many players

merge-audio-aligned's first output was 24 kHz mono AAC (TTS native format). Browsers, QuickTime, and Windows Media all play this unreliably — appeared as silent audio.

**Fix**: ffmpeg merge now adds `-ar 48000 -ac 2` so output is stereo 48 kHz AAC. Audible on every tested player.

### 3.6 Picker selection segment in recording

Even with `-ss t_first_step` trim, brief picker animation frames leaked through.

**Fix**: `playwright-record.py:start_tour` injects CSS that hides `.tut-btn` and `.tour-picker*` (`opacity:0 !important; pointer-events:auto !important`). Picker is fully invisible in the captured video while remaining clickable for the recorder.

### 3.7 Audio + video out of sync; long silence between cues

The original merge concatenated all cue WAVs into one long track with fixed 800 ms silence between, then muxed against video. Tour-advance timing didn't match cue boundaries — audio drifted past visible beats.

**Fix**: `merge-audio-aligned.py` reads `step_timestamps.json` (per-step arrival time logged by playwright-record during the actual recording). Each cue WAV is placed in the output audio at its recorded arrival time; silence pads between. Audio is now anchored to the visible tour, not to a pre-computed offset.

### 3.8 LLM-rewrite (not regex) for narration edits

User feedback: "you should use LLM, why python rules?" My initial scrub for time-references and cryo-phase verbosity used regex find/replace, which left fragmentary sentences. Switched both prompts (`compress-en-narration.py` and `condense-zh-subs.py`) to forbid time references and require one-line cryo phase descriptions, then re-ran the LLM rewrite over all source narrations.

---

## 4. Design HTML edits (in `reference/claude_design/`)

Per user request — time estimates are risky:

| File | Change |
|---|---|
| `research_agents/src/ChatCards.jsx` | `PilotPromptCard`: removed "Full run ~N min / pilot ~M min" estimate line → "Full run sweeps N samples; pilot validates QC on M first" |
| `research_agents/src/ChatCards.jsx` | `PilotPromotionCard`: removed "in 4m 38s" runtime |
| `research_agents/src/ChatCards.jsx` | `FindingsChatCard`: removed "Workflow done in 38m 12s" runtime |
| `research_agents/src/research-data.js` | Removed `Runtime` row from comparison-card metrics array |
| `research_agents/src/ResearchApp.jsx` | Rewind-aware `tourFFTo` (see §3.1) |

---

## 5. AWS scrubbing

Per user request: all `AWS Batch` / `AWS` mentions removed from narrations.

| Old | New |
|---|---|
| `AWS Batch` (EN) | `the cloud` |
| `AWS Batch` (ZH 在 AWS Batch 上) | `云端` |
| Standalone `AWS` | `cloud` / `云端` |

---

## 6. Open items (next session)

1. Re-record all 10 videos with the LLM-rewritten narrations + time-stripped design HTML.
2. Verify the rewind-aware `tourFFTo` works for IND tour (it has 24 beats vs RA UI's 13–20).
3. Record `website-quickstart-v2` (14 beats, live biomate.ai) — pipeline ready, never executed.
4. Upload final videos to `s3://biomate-production-backups-…/demos/<date>/`.

---

## 7. Files committed in this session

Commit `113e025d` on `integration/next-phase`:
- `scripts/recording/`: 13 new + 4 modified
- `reference/claude_design/research_agents/`: full vendored UI + 16 narration files + `ResearchApp.jsx` rewind fix
- `reference/claude_design/biomate/website-quickstart-v2*.md`: 3 new
- `.gitignore`: anchored `/recording/` so `scripts/recording/` is tracked

Plus this doc and the time/cryo edits (separate commit forthcoming).
