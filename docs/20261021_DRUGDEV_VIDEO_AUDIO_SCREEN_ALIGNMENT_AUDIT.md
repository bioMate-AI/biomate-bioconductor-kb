# 2026-10-21 — Drug-dev demo video audit: audio ↔ screen ↔ content alignment

Audited the drug-development demo videos (EN) for (a) screenshot/detail
correctness and (b) alignment between the narration (audio) and what's on
screen. Method: compared each video's narration script
(`reference/claude_design/tutorials_v2_final/*-narration.md`) and the mux scene
timeline against frames extracted from the actual Drive videos (ffmpeg, 1 frame
/ 8 s + full-res zooms of product scenes). Videos pulled from
`biomate_drive:biomate_tutorial_recordings/recording/output/`.

## Scope covered

| Video | Dur | Verdict |
|---|---|---|
| `d2-admet-dl-en` | 10:00 | ⚠️ one scene misaligned (Outputs "run") |
| `drug-dev-en` | 7:40 | ⚠️ one scene misaligned (Outputs "run") |
| `d1-qsar-ml-en` | 7:46 | ✅ clean |
| `d3-generative-lead-design-en` | 6:46 | ✅ clean |
| `d4-binding-free-energy-en` | 6:42 | ✅ clean |

## Finding 1 (main) — Outputs scene shows "run", contradicting its own narration

Both videos that display the generic Nextflow **Outputs** panel (step-by-file
table) show every file filed under the step **`run`**:

- **`d2-admet-dl-en`, Slide 12 / 15** — headline "Behind the summary: the raw
  files the model produced." Narration: *"grouped by the step that made them."*
  On-screen caption: *"Filed under the step that produced each file … so you
  never hunt for a result or guess which stage made it."* Yet the Step column
  reads `run` for all six files (`pk_summary.json`,
  `predict_admet_properties_output.txt`, `predict_admet_properties_results.json`,
  `qc_metrics.json`, `toxicity_report.json`, `versions.yml`).
- **`drug-dev-en`, Slide 13 / 16** — headline "Every file lands under the step
  that produced it." Subtitle: *"groups results by step … so you never hunt for
  a file or guess which stage it came from."* Same Step = `run` for all files.

The slide's entire thesis (meaningful step attribution) is contradicted by the
screen showing a meaningless `run`. These are Oct-5 recordings — **pre-fix**.

**Root cause = already fixed this session.** `predict_admet_properties/main.nf`
publishDir was `${outdir}/run` → now `${outdir}/02_predict_admet_properties`
(commit `ba7389a5`, deployed + verified empirically: a post-fix run's S3 outputs
land under `…/02_predict_admet_properties/`, which the viewer maps to step 1
"Predict Admet Properties"). So the product is correct now; **the two video
scenes need re-recording** against fixed dev to match their narration.

Only these two videos are affected — `d1`, `d3`, `d4` present domain-specific
result tables (QSAR metrics / ranked candidates / per-edge ΔΔG), not the generic
step-by-file panel, so they never show `run`.

## Checked and OK (screen matches narration)

- **ADMET-AI endpoint count** — narration "fifteen endpoints"; Slide 5 graphic
  "15 ADMET endpoints" + "trained on 2M+ … AUROC > 0.85 on 20 of 31" — match.
- **Model type** — narration "model type — MPNN"; pre-run panel "Admet Model
  Type: MPNN" — match.
- **SMILES in pre-run** — shown as a clean `Smiles List` array (aspirin,
  caffeine, ibuprofen); **no phantom `CN1C` param** (the CN1C fix holds).
- **QSAR baseline (d1 ref on Slide 4)** — narration names `Qsar Rf Model` /
  `herg_cardiac_safety_qsar`; slide shows exactly those.
- **Completed/Findings scene** — green "Completed" badge, "completed for 3
  compounds", Caveats note ("computational estimates — confirm with wet-lab"),
  Download report — all present and matching narration Steps 11–12.
- No "undefined"/"Untitled" text observed in any drug-dev frame.

## Minor / to verify

- `d2` Slide 4 bottom caption "…invisible to the mode[l]" may be clipped at the
  right frame edge (possible caption overflow) — low severity, confirm on re-cut.

## Recommended fix

Re-record the **Outputs scene only** of `d2-admet-dl` and `drug-dev` (EN + ZH)
against fixed dev, where the Step column now reads "Predict Admet Properties".
Everything else in the drug-dev set is accurate and well-aligned. ZH versions not
yet frame-audited — assume the same Outputs scene needs the same re-cut (shared
capture).
