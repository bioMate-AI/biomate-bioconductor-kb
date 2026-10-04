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

### T0 — Getting started (DONE — live re-capture, not a crop)

The old T0 scenes 5/6 used near-identical **empty** cold-start dashboards that
did not depict what the narration claimed — scene 6 narrated "watch the lane
appear" but the shot had no typed goal and no lane chip. A crop could not fix a
chip that wasn't there, so this was a live re-capture:
- `capture-live-t0-focal.cjs` (committed): fixture login → cold start → element-
  clips at 3×. Scene 5 → the composer strip (attach-file + point-at-data
  controls). Scene 6 → the REAL Instant lane-preview chip, captured with the
  JAK1 evidence question ("What is the evidence linking JAK1 to rheumatoid
  arthritis…") so the lane shown ("Answer here · with sources") matches the
  evidence-question narration.
- Live lane labels are "Answer here" (Instant) / "Prepare an analysis" (Cloud) —
  NOT the words "Instant"/"Cloud". Scene-6 HTML caption + EN/ZH narration now
  name the live label ("the Instant lane, shown as 'Answer here · with sources'")
  so the voiceover matches the screenshot. (The scene-4 concept slide keeps the
  Instant/Cloud abstraction; scene 6 grounds it to the UI label.)
- Scene 6 window 26.1→30 s so the ZH lane narration fits. T0 mux 6M→10M. Imgs
  set to `object-fit:contain` (T0 default is `cover`, which would crop the wide-
  short banners). Scene 2 keeps the full cold-start overview (the whole doorway
  IS the point).
- Re-rendered EN (`t0-getting-started-en.mp4`, 19.9 MB) + ZH (21.0 MB); uploaded.

## Status: all three existing educational videos now meet the focal standard
T0, T3, and T11 (drug-dev) — EN + ZH — re-rendered and uploaded 2026-10-04
(12:57–13:33). The user's "high-res / large-font / clip-to-focus" requirement is
satisfied for every existing educational-format tutorial video.

## Remaining scale list (net-new production, not focal fixes)
- Legacy small `T1/T2/T4-tutorial.*.mp4` (~800 KB, 2026-10-01 static style) still
  need educational-format production (T0/T3 already superseded theirs).
- Instrument / sidebar / W-series videos: not yet produced.
- Each new tutorial with live UI should use the focal pattern from the start:
  `capture-live-{admet,t0}-focal.cjs` → element-clip at 3× → `assets/live/*.png`,
  `object-fit:contain` for wide-short banners, 10M mux bitrate.
- CN parity throughout (same English UI visuals + full Chinese voiceover).

## Pipeline reference (local, no AWS cost)
- TTS: `edge-tts-gen.py` via `/Users/kky/opt/anaconda3/bin/python3.9` (has
  `edge_tts`; the default py3.14 does not). `TTS_RATE=+40%`, EN `en-US-AriaNeural`
  / ZH `zh-CN-XiaoxiaoNeural`.
- Flagship record: `record-walkthrough-live.cjs` (node; bundled Chrome for
  Testing). T0/T3 record: `record-walkthrough-t{0,3}.py` (py3.9 Playwright,
  static server on 7782 rooted at `reference/claude_design`).
- Mux: `mux-walkthrough.py` (flagship, per-lang `RECORD_META`) /
  `mux-walkthrough-t{0,3}.py`. libopenh264 + AAC; MP4s are gitignored.

---

## Session 2 (2026-10-04, continued) — T1/T2/T4 produced + polish audit

### New educational videos (EN + ZH), flagship format + live focal capture
- **T1 Design & Generate** — `capture-live-t1-focal.cjs` runs one small-molecule
  generate on `/design` (aspirin seed) → form, multi-objective ranked table,
  Pareto, rejection profile. Honesty added beyond source: generator is
  **deterministic BRICS enumeration, not a trained model** (live `dg-status`
  discloses it). Render scripts port 7783.
- **T2 Models & the closed loop** — `capture-live-t2-focal.cjs` navigates
  `/models` → Registry (5 BioNeMo models), model object (Boltz-2 Evidence =
  **not_evaluated**, "a floor not a ranking"), Run-a-model form, Rounds empty
  state (closed-loop honesty rules). Port 7784.
- **T4 Bringing your own data** — `capture-live-t4-focal.cjs` uploads a demo
  `jak1_assay_demo.csv` (so the dataset object shows a real **Preview table** +
  **Good** quality) → data hub, dataset object, quality tab. Authored; NOT yet
  rendered/uploaded (pending). Port would be 7785.

### Polish audit + fix (per user request: polish / professional / clarity)
- Audited title/concept/live/closing frames of all shipped videos. Strengths:
  all live focal scenes, closing verdict tables, honesty badges. 
- **Systemic issue found + fixed:** concept-tile scenes (T0/T1/T2/T3) had a large
  dead band — the `.card.big` stretched full-height but held few tiles. Fix in
  each file's CSS: `.card.big{flex:initial; padding:30px 32px}`, `.concept{...
  justify-content:center}`, tiles enlarged (h4 16→18, p 13→14.5, padding 15→20).
  Re-recorded + re-muxed all four (narration unchanged → no re-TTS) and re-uploaded.
- Minor/low-pri: title slides have empty lower halves (fine for intros); T3
  reproducibility scene uses a full-panel shot (legible, not focal).

### Interactive Tools (RStudio / Jupyter / CellxGene) — current honest status
- `/api/interactive/available` on dev returns `{available:true, tools:{jupyter,
  rstudio,cellxgene:true}}` — buttons appear. But a live launch
  (`/api/interactive/launch`) **issues a session URL that 503s for ~60s and never
  serves** on dev → a *running* notebook is NOT demonstrable there yet.
- T5 doc (`T5-viewing-your-results.md` §8) is now **stale** on one line ("not
  provisioned on dev"); update it.
- Data flow (`interactive-launcher.tsx`): auto-selects tool by dataset format,
  mounts selected outputs at `/data/`, preloads packages (R: DESeq2/edgeR/
  tidyverse/Bioconductor; Py: pandas/scanpy/…), shows quick-start code — but does
  **not auto-load** data into the live workspace (you run one snippet). A small,
  high-value product change: auto-run the quick-start snippet / pre-seed a cell.
- Next: produce **T5** foregrounding (a) the inline viewers across data types
  (table/image/PDB-3D+pLDDT/VCF/MRC/HTML/logs) and (b) the launcher dialog —
  honestly, not pretending the workspace is pre-loaded.
