# 2026-10-23 — Drug-dev tutorial videos: corruption root-cause, serial re-mux, self-audit, and fixes

## Summary

Completed the 12 drug-development tutorial videos (6 decks × EN/ZH) at hi-res,
fixed a systemic mp4-corruption bug, audited every video by eye, corrected two
real content defects, re-rendered the affected videos, and uploaded all 12 to
Drive.

Decks: `d1-qsar-classical-ml`, `d2-admet-deep-learning`, `d3-generative-lead-design`,
`d4-binding-free-energy`, `drug-dev` (omnibus), `b1-train-custom-model`.

## Root cause of the corrupt videos (the real bug)

Prior sessions produced mp4s with "moov atom not found". The webms were always
valid — the corruption was in the **mux step**. `v2_mux.py` runs
`ffmpeg ... -movflags +faststart`, a two-pass moov-atom rewrite. The old
pipeline muxed **inline during parallel render** (`xargs -P 5`), so multiple
`v2_mux.py` processes wrote overlapping mp4s. Two faststart rewrites on the same
file truncate/lose the moov atom → corrupt output.

**Fix (closes the class, not the instance):** mux **strictly serially** — one
`v2_mux.py` at a time, with a `while pgrep -f v2_mux.py; do sleep; done` guard
before each, full stderr capture, and per-file `ffprobe` validation. Recording
stays parallel (race-free); only mux is serialized. Scripts:
`scratchpad/serial_mux_all.sh`, `re_render_3.sh`, `render_b1en.sh`.

Result: **12 valid / 0 bad** on a full `-f null` decode (not just header reads).

## Self-audit (every video checked via contact sheets)

Built tiled frame grids (`ffmpeg fps=1/N,tile=RxC`) for each video and reviewed
by eye. All decks: rich product scenes present and legible (pre-run panel, live
progress stream, completed/findings, QC-metrics file preview, reproducibility
record, plus Pareto / PBPK / thermodynamic-cycle graphics where relevant), no
duplicate title / `topic-eyebrow`, hi-res.

### Two real defects found and fixed

1. **Cross-demo mention (violates "do not mention other demo in the current one").**
   `d2-admet-deep-learning` closing said **"Next: D3 — generative lead design"**
   (EN deck + narration) and **"下一讲：D3——生成式先导化合物设计"** (ZH deck).
   Removed from: `narration/d1-qsar-classical-ml.en.md` ("companion episode, D2"),
   `narration/d2-admet-deep-learning.en.md` ("Next in the track: D3…"),
   `d2-…-walkthrough.html` and `.zh.html` closing footnotes.
   The other 4 decks were already self-contained.

2. **Broken headline (EN only).** `b1-train-custom-model` slide read
   "Four plain language describe the whole task." → corrected to
   **"Four plain words describe the whole task."** (matches the ZH
   "四个简单的词…" and the chip "the whole task, in four words"). Fixed in the
   deck HTML and `narration/b1-train-custom-model.en.md`.

### Re-rendered (4 videos) and re-verified on screen
`d1-en`, `d2-en`, `d2-zh`, `b1-en`. Extracted the exact closing/headline frames:
- d2-en Slide 15/15: "…require experimental validation." — **no "Next: D3"** ✓
- d2-zh 第16/16页: "…模型估计需要实验验证。" — **no "下一讲：D3"** ✓
- b1-en slides 3–4: "Four plain words describe the whole task." ✓

## Final inventory (all valid)

| Deck | EN | ZH |
|---|---|---|
| d1-qsar-classical-ml | 10:23 | 8:44 |
| d2-admet-deep-learning | 13:08 | 11:23 |
| d3-generative-lead-design | 8:50 | 7:45 |
| d4-binding-free-energy | 8:28 | 7:26 |
| drug-dev (omnibus) | 10:35 | 8:57 |
| b1-train-custom-model | 7:27 | 6:27 |

TTS rate +0% (calm). b1 reframed onto the real **ML Training Platform**
(`backend/lib/galaxy/ai/ml_training/`, `/models`), not `run_code`.

## Delivery

Uploaded via rclone (`biomate_drive:`) to
`biomate_tutorial_recordings/recording/output/v2_drugdev_hires_1022/{EN,ZH}/`
(lang suffix stripped; folder denotes language).

## Known open / next steps

- Coverage gap (user): add **docking**, **novelty/FTO**, **stability** demos.
- Build 4 capability demos (dry loop · dry→wet loop · multi-agent target-ID
  evidence search · adaptive intelligence = disambiguation+memory+RSI) on the
  αvβ6 PDAC / GRPR / PD-L1 cyclic-peptide program, highlighting
  compute × knowledge × wet-lab and public + in-house KBs.
- ZH narrations for d3/d4/drug-dev/b1 were not frame-audited individually
  (d1-zh and d2-zh passed; decks are structurally identical to EN).
