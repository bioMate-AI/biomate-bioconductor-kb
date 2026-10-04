# Tutorial-video focal-crop standard — session 2026-10-04

## What changed and why

User requirement (verbatim): *"make sure the screenshot of UI is high resolution,
with large fonts, if the full screen is not highlighting the main point, clip to
the focused views to make sure the highlight standing out."*

The tutorial videos embed live-UI screenshots. When a full chat+panel screenshot
(1440-wide / 2880×2000 at 2×) is shrunk into a slide, the product UI text becomes
small. The **focal standard**: every live-UI scene shows a crop zoomed to the one
element that makes the scene's point, so the text is large and sharp. Only the
right-hand workflow panel is in frame — the chat column (and any transient
"exit 1" line) is cropped out.

## Done this session (shipped to Drive marketing folder)

Drive: `biomate_drive:biomate_growth/marketing/data_centroid_tutorial/`

### T11 — Drug-development, end-to-end (flagship)
- 5 live scenes re-captured at deviceScaleFactor=3 and element-clipped
  (`capture-live-admet-focal.cjs` + `build-live-focal.sh`) → `assets/live/*.png`:
  prerun (Smiles+MPNN+Confirm&Run), running (RUNNING card + QC GATES),
  completed (Completed badge + Findings Summary values), outputs (6-file list),
  record (reproducibility fields + SHA-256 table).
- Scene-7 narration/slide fix: the completed clip is panel-only, so
  "the chat **and** the right-hand panel tell the same story" →
  "the workflow panel tells the whole story" (EN + ZH narration + HTML heading/
  kicker/caption). Commit `fix(t11)`.
- Re-rendered EN (`drug-dev-en.mp4`, 32.5 MB) + ZH (`drug-dev-zh.mp4`, 38.0 MB)
  at libopenh264 10 Mbit; uploaded.

### T3 — Running a workflow & reading the report
- Scenes 2/3/5 (prerun/running/outputs) reuse the flagship focal assets — the UI
  is content-identical, shows no run id, and the crop avoids the spurious "CN1C"
  param artifact present in the old full-panel `r1`.
- Scene 4 (completed) keeps T3's **findings-withheld** honesty story (real run
  `c40459b2`, outputs unreadable) — it CANNOT reuse the flagship's populated-
  findings asset, so it gets its own focal crop of the tracked `r8`
  (`crop=1680:690:1200:190`, reproducible step added to `build-live-focal.sh` →
  `assets/live/t3-completed-withheld.png`). Bullet "the chat and the panel agree"
  → "the title and state are exactly right, no undefined, no stuck spinner".
- Scene 6 (reproducibility record) unchanged — `r6` is already a focused, legible
  crop with the correct run id `c40459b2`.
- Bumped `mux-walkthrough-t3.py` bitrate 6M→10M. Commit `feat(t3)`.
- Re-recorded shared webm + re-muxed EN (`t3-run-and-report-en.mp4`, 23.6 MB) + ZH
  (25.1 MB); uploaded.

## Open finding — T0 needs a LIVE re-capture, not a crop

The three T0 screenshots (`i01-1-cold-start.png`, `m0-1-intent-bar.png`,
`s1-1-sidebar.png`) are near-identical **empty** cold-start dashboards. They do
NOT depict what the narration claims:
- Scene 5 ("the cards and the intent bar only seed your message — they never
  send") points at "attach-file and point-at-data controls" — the composer is
  present but small at the foot; needs a focal crop of the composer strip.
- Scene 6 ("Type a real goal — and watch the lane appear before you send") — the
  intent bar is EMPTY (placeholder only); there is **no typed goal and no lane-
  preview chip** in the image. A focal crop cannot add a chip that isn't there.

Proper fix (root cause): a live dev-UI capture (fixture login → New Chat cold
start → type a goal → capture the lane-preview state + a focal composer clip),
same pattern as `capture-live-admet-focal.cjs`. Scene 2 (cold-start overview) is
intentionally a full view and only needs a high-DPI recapture, not a crop.

## Remaining scale list (educational + live-UI + focal, EN + ZH)
- T0 — live re-capture (above) then re-render.
- The legacy small `T0/T1/T2/T4-tutorial.*.mp4` (~800 KB, 2026-10-01 static
  style) are superseded for T0/T3 by the educational versions; T1/T2/T4 still
  need educational-format production.
- Instrument / sidebar / W-series videos: not yet produced.
- CN parity is maintained throughout (same English UI visuals + full Chinese
  voiceover).

## Pipeline reference (local, no AWS cost)
- TTS: `edge-tts-gen.py` via `/Users/kky/opt/anaconda3/bin/python3.9` (has
  `edge_tts`; the default py3.14 does not). `TTS_RATE=+40%`, EN `en-US-AriaNeural`
  / ZH `zh-CN-XiaoxiaoNeural`.
- Flagship record: `record-walkthrough-live.cjs` (node; bundled Chrome for
  Testing). T0/T3 record: `record-walkthrough-t{0,3}.py` (py3.9 Playwright,
  static server on 7782 rooted at `reference/claude_design`).
- Mux: `mux-walkthrough.py` (flagship, per-lang `RECORD_META`) /
  `mux-walkthrough-t{0,3}.py`. libopenh264 + AAC; MP4s are gitignored.
