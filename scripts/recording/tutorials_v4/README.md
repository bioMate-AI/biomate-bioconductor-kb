# v4 tutorial deck render pipeline (`_v4.js` contract)

Renders the Claude-design `tutorials_v3` walkthrough decks (`<id> walkthrough v4 - proposal[.zh].html`,
the `_v4.js` auto-play/`window.__done` contract) into narrated 1080p MP4s and uploads them to Google Drive.
Established 2026-11-01 (first full run: 25 中文 short decks → `biomate_drive:biomate_tutorial_recordings/1101_refined/`).
Companion of `../` (the older tour-deck pipeline) and `../../../docs/20261005_VIDEO_WORK_HANDOFF.md`.

## Scripts
- `record-walkthrough-v4.mjs` — Node/Playwright recorder. Loads a deck `?rec=1`, waits `document.fonts.ready`
  + scene-0 active + `window.__done`, screencasts 1920×1080 webm, prints `{video, t_scene0_ms, timeline, total}`.
  Run from `frontend/` (resolves `playwright`). Uses **system Chrome** (`channel:'chrome'`) — the ms-playwright
  browsers are usually absent; you still need `npx playwright install ffmpeg` once (the record-video helper).
- `mux-walkthrough-v4.py` — parses a v4 tabular narration `.md` (起点·画面·旁白·字数/窗口), TTS each 旁白 line
  (edge-tts `zh-CN-XiaoxiaoNeural`, `--rate +8%`), places each at `t_scene0 + __timeline[scene].start + row-offset`
  (numpy), muxes over the webm (ffmpeg libopenh264 10M + aac, 1080p). Fully arg-driven.
- `render-decks-v4.sh` — **disk-safe sequential driver**: record → mux → `rclone move` to Drive → delete webm,
  one deck at a time, with a free-space guard. `render-decks-v4.sh <tutorials_v3_root> <deck-list.tsv> <rclone_dest> [port]`.
- `refine-decks-v4.py` — idempotent structural refiner (removes `hero-band`, `<div class="ends">` recap, confirm
  beats + their lens artifacts, "简短而具体" filler; centers hero). Contract-guarded (scene count + data-seconds).
- `verify-contract-v4.py` — checks a refined deck vs its pristine original: scene count, data-seconds multiset,
  div balance, no dropped timing/camera attrs or `<code>` tokens.

## deck-list.tsv
Tab-separated: `<deck-folder>\t<deck-html-basename>\t<narration-basename>`, e.g.
```
d5-molecular-docking	d5 walkthrough v4 - proposal.zh.html	d5-docking-v4.zh.md
```

## HARD RULES (learned the hard way)
- **NEVER parallel-render.** Two 1080p recording lanes filled the disk (ENOSPC) and blocked *every* command.
  The driver is strictly sequential and uploads+deletes each deck immediately; keep it that way.
- **Disk-full silently truncates a mux.** A healthy zh short MP4 is ~15–57 MB (a 3-scene deck ~15 MB); anything
  single-digit MB is truncated — the driver flags it and does NOT upload it.
- Narration is **中文-only** (no EN narration exists) → only `.zh` videos render. T3 has no narration file.
- Edit deck TEXT only; never touch `data-seconds` / `data-at` / `_v4.js` globals, numbers, `<code>`, tool names,
  or honesty caveats (see `docs/20261101_TARGETID_DEMO_REDESIGN_FOR_CLAUDE_DESIGN.md` for why honesty framing matters).

## Source of truth
The decks are **claude-design deliverables** (`~/Downloads/demo_recording_pack*/tutorials_v3`, `~/Downloads/claude_code_core`),
pulled into `reference/claude_design/tutorials_v3/`. They are not otherwise in git history.
