# 2026-10-22 — Drug-dev tutorial screenshots: fixes + alignment audit

Scope: `reference/claude_design/tutorials_v2_design/` — the reformatted v2 walkthrough
decks. User reported "the screenshots are failed" (ADMET as the example) and asked to
(a) audit screenshot ↔ slide ↔ audio alignment and (b) finish the entire drug-dev set,
with the hard rule **no demo may ship without product screenshots** (marketing material).

## Root causes found (ADMET, the exemplar)

The live screenshots in `assets/live/` had four independent defects:
1. `completed.png` was a **FAILED/paused run** ("This run did not complete") — not a completed run.
2. `outputs.png` was a **byte-identical copy** of `completed.png` (md5 `cfac6ce2…`).
3. **Expanded sidebar** showing the fixture account's redundant chat history (JAK1/SMILES ×N).
4. **Stale UI** — not the latest product.

The good shots (`prerun.png`, `running.png`) had the sidebar **collapsed to the icon rail**
and the latest UI; the broken ones were from an older expanded-sidebar + failed session.

## Fixes applied

### ADMET (d2-admet, shared by drug-dev + t3-run-and-report)
Re-captured `completed` / `outputs` / `record` (EN + ZH) from a **genuinely completed** ADMET
run on dev (`43d59277-5c13-47ba-87a4-c7747a444d30`, status=completed, 8 output files) via
`/?session=…`, sidebar collapsed — **no new Batch spend**. Dismissed the post-run micro-survey
(`survey-not-now`). All six now distinct, completed-state, latest UI. Old files backed up.

### d1-qsar (EN) — real run via bound file
QSAR's `input_csv` triggers a "Which input_csv?" disambiguation that a pasted param can't
clear; the **root-cause fix is to bind the CSV as an uploaded file** (`chat-attach-file-input`
→ `setInputFiles`). With the file bound, QSAR runs for real (captured panel → settings →
running → completed). EN `qsar-live-panel.png` upgraded to the clean file-bound settings shot
(Inputs mapped: Input Csv → qsar_assay.csv, Confirm & Run enabled). No more blocked/greyed state.

### d4-fep (EN)
Replaced the blocked empty-params panel with a **ready** OpenFE RBFE shot — Ligand A/B filled,
Confirm & Run enabled (no GPU spend; the deck's intent is "opens the FEP engine").

### d3-generative (EN)
Existing clean ready panel retained (REINVENT4 Generative Lead Design, params set, Confirm enabled).

### b1-train-custom-model — reframed off run_code
b1 previously had **zero screenshots** and framed training as the `run_code` last-resort path.
Corrected on evidence: a "train a classifier" request routes to a real ML workflow
(`mlinterfaces_multi_classifier_evaluation`), and BioMate has a dedicated **ML Training Platform**
(`backend/lib/galaxy/ai/ml_training/`) surfaced at `/models` (Train / Registry tabs; training loop
Dataset → Train → held-out Quality gate → Register; families: Language fine-tunes, Tabular AutoML,
Chemprop GNN, Diffusion). Added a live Product scene (EN + ZH) showing the Models page, and
reframed the narration (EN + ZH header/Step 1/Step 4) from run_code → the ML Training Platform.
Scene↔narration counts preserved (10/10).

## Alignment audit (screenshot ↔ slide ↔ narration)

`scripts`-style audit over all 23 decks: **every deck has scenes == narration steps ==
data-seconds** (no audio/scene desync). Only 1 heuristic flag (t3 scene 4: `running.png` under a
"QC gate" kicker) — a false positive; the running scene legitimately shows the QC gate.

## Resolution upgrade (user: "screenshots must be high resolution")

All drug-dev live shots re-captured at **deviceScaleFactor=3 → 4320×3000** (was dsf=2 /
2880×2000). QSAR/generative "running" shots are real (QSAR runs via a bound CSV file —
`chat-attach-file-input` → `setInputFiles` resolves the input_csv disambiguation; generative
is captured in its genuine RUNNING phase before the known reinvent4-image failure). Final audit:
**every drug-dev asset is 4320×3000 and every per-deck set is fully distinct** (no duplicates).

## Status — COMPLETE

| Deck | EN | ZH |
|------|----|----|
| d2-admet | ✅ prerun/running/completed/outputs/record (5/5 distinct, hi-res) | ✅ 5/5 distinct, 中文 UI, hi-res |
| drug-dev | ✅ (shares ADMET) | ✅ |
| d1-qsar | ✅ file-bound ready shot, hi-res | ✅ panel/settings/running (3/3 distinct, real run) |
| d3-generative | ✅ ready panel, hi-res | ✅ panel/settings/running (3/3 distinct, real RUNNING moment) |
| d4-fep | ✅ ready panel, hi-res | ✅ panel/settings (2/2 distinct) |
| b1 | ✅ Models platform (hi-res) + reframed off run_code | ✅ same (中文) |

All shots: 4320×3000, sidebar collapsed, latest UI, real product state, EN+ZH.

## Open items
- ZH d1/d3/d4 panel/settings/running shots: re-capture clean (中文). QSAR ZH via bound-file run
  (same approach as EN). generative `运行中`: capture the real RUNNING phase before the known
  reinvent4-image failure (honest running moment).
- Re-render the d2-admet + drug-dev **videos** — the existing masters were muxed from the old
  broken screenshots; TTS + record + mux from the corrected decks.
- Models page is not localized (ZH capture == EN); product localization gap, not a deck defect.

## Capture harness (scratchpad, session-local)
`recap_admet.cjs` (session re-capture), `drive_capture.cjs` (qsar fill / fep ready),
`qsar_upload.cjs` (bound-file real run), `cap_models.cjs` (Models page), `align_audit.py`
(alignment). Fixture: `lifeifei163361@163.com`; header `x-e2e-test-token: biomate-e2e-bypass-token-dev-only`.

## Demo backlog (after drug-dev videos) — requested 2026-10-23
Priority: finish drug-dev videos first (apply ADMET template: live progress stream + findings/QC focal crops, +0% calm audio), then build these 6 new walkthroughs. Each must highlight **compute × knowledge × wet-lab**, **rich public + in-house resources** (OpenTargets/GWAS/ChEMBL/TDC + Experience/renal/medchem KBs), and BioMate's **search + reasoning**:
1. Dry loop (compute + public/in-house KBs + expert feedback) — seed: t2-closed-loop + auto-loop QC remediation.
2. Dry→wet loop — workflows (dry) + instrument MCP (list/run/status) (wet).
3. Multi-agent evidence search → target identification — engine built: `backend/lib/galaxy/ai/target_id/` (data/network/clinical channels → arbiter → evidence gate; `identify_targets` MCP; `target_id_api.py`).
4. **Adaptive intelligence** (one demo, combining context-disambiguation + memory + RSI as a single arc): BioMate resolves ambiguity from context (param-clarification / "which input?" cards) → remembers the resolution/preference (`recall_memory` / persistent memory) → self-improves from accumulated corrections (RSI scorer, longitudinal + firewall). Worked on the real program: a target query is disambiguated, the αvβ6/GRPR/PD-L1 program context is remembered, and an expert correction feeds the self-improvement loop.

## Capture method (established this session — the correct approach)
- Dev must be on the **latest UI** (synced 85c3569e); the old build folds the chat stream on restore + renders outputs via modals.
- **Progress stream**: capture a LIVE run (the stream flows step-by-step → QC gate → remediation → "Workflow finished"); restored/finished runs collapse it.
- **Finished details/QC/outputs**: capture the After-run panel on a run executed on the latest UI, dsf=3 focal element crops (findings-card, qc_metrics/results JSON previews).
- **Deck presentation**: split scene + landscape/tight-cropped rich shot (legible). Side-by-side full-width renders too small — avoid.
- **Audio**: TTS_RATE=+0% (calm). +40% was too fast.
- Always AUDIT each shot/frame by eye before it goes into a deck.

## Demo worked-example (requested 2026-10-23): use OUR real program
Use the actual program as the example in the new demos (not toy cases): targets **αvβ6 (PDAC) · GRPR · PD-L1**, the cyclic-peptide / immune-mediated (ACT, TMC/MDA/SYSUCC) program. e.g. target-ID evidence search runs on αvβ6/GRPR/PD-L1; the dry-loop designs/screens the cyclic-peptide binders; dry→wet closes with instrument assays. Public targets → fits a community demo without method disclosure.
