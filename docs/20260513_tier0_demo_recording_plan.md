# Tier 0 Demo Video Recording Plan (2026-05-13)

5 demo videos, **3 minutes each**, recorded through the live BioMate chat UI using the existing Playwright + `TutorialTipOverlay` + `run-demos.sh` infrastructure. Each demo records the same user journey: type a natural-language query → AI routes to a Tier 0 workflow → user reviews parameters → click Run → AWS Batch executes → outputs surface in the UI.

## Existing infrastructure being leveraged

| Asset | Path | Role |
|---|---|---|
| Playwright demo config | `frontend/playwright.demo.config.ts` | 2560×1440 @2x recording, 7200s timeout, video-on |
| Run script | `frontend/e2e/run-demos.sh` | Batch invocation with stable named output files |
| Helpers | `frontend/e2e/demo-helpers.ts` | `setupDemoUser`, `sendAndWait`, `clickRunAndWait`, `shot`, `tip`, `pause`, `waitForNoActiveRuns`, billing capture |
| Tip overlay component | `frontend/client/src/components/tutorial-tip-overlay.tsx` | Floating callout bubble triggered by `window.__biomate_tip(text, ms)` |
| Reference design v2 | `webpage_design_new/` (HTML) | Visual guide for tip-bubble style — already matched by `tutorial-tip-overlay.tsx` |
| Previous demo precedent | `frontend/e2e/demo-01-drug-discovery.demo.ts`, `demo-05-autoloop-qc.demo.ts`, `demo-11-ind-assembly.demo.ts` | Pattern to match |
| TTS recording plan (deferred) | `docs/20260427_TUTORIAL_RECORDING_PLAN.md` | Gemini TTS + ffmpeg pipeline for narration overlay (post-recording polish) |

**Nothing new required for the recording.** The 5 new demos are additive — they slot into the existing pipeline as `demo-T01.demo.ts` ... `demo-T05.demo.ts`.

## Five demos to record

Each maps to a Tier 0 workflow that is production-validated end-to-end on AWS Batch (see `20260513_e2e_audit_final.md`).

### T01 — Bispecific format triage (Ivonescimab story)
- **Query**: "Design a PD-1 × VEGF bispecific in CrossMab format for NSCLC"
- **Workflow**: `bispecific_format_triage`
- **Story arc** (3 min):
  - 0:00-0:20 — Tip: "Ivonescimab beat Keytruda in HARMONi-2 — the format choice was CrossMab. Watch BioMate recover it from atlas data alone."
  - 0:20-1:00 — Type query, wait for `workflow_ready`, show extracted inline params
  - 1:00-1:40 — Tip: "Six format candidates scored on cis vs trans engagement, half-life, manufacturing"
  - 1:40-2:20 — Click Run, watch AWS Batch executor card animate
  - 2:20-2:50 — Output: CrossMab #1 (score 100, 67%), Ivonescimab precedent cited
  - 2:50-3:00 — Closing tip: "30 seconds. Same answer Akeso took 18 months to reach."

### T02 — In vivo CAR-T co-design (Capstan / fratricide demo)
- **Query**: "Design an in vivo CAR-T for CD19 using anti-CD8 LNP delivery for B-cell lymphoma"
- **Workflow**: `in_vivo_cart_codesign`
- **Story arc**:
  - 0:00-0:20 — Tip: "Capstan, Kelonia, and Umoja raised $400M to skip ex vivo CAR-T manufacturing. The design problem is multi-modality."
  - 0:20-1:20 — Type query, show atlas safety + LNP tropism + fratricide check
  - 1:20-2:00 — Tip: "Fratricide check: LNP transfects T cells; CD19 is on B cells; no overlap → GO"
  - 2:00-2:40 — Click Run, show 5 output files
  - 2:40-3:00 — Closing tip: "Switch the CAR target to CD7 and the same workflow flags fratricide automatically."

### T03 — VERVE-102 base editing
- **Query**: "Design an in vivo base edit for PCSK9 like VERVE-102 for hypercholesterolemia"
- **Workflow**: `in_vivo_base_edit_design`
- **Story arc**:
  - 0:00-0:20 — Tip: "VERVE-102 is the most-watched gene editing trial in the world. Watch BioMate reach the same design from inputs alone."
  - 0:20-1:10 — Type query, show editor selection (CBE) + delivery (LNP-IV hepatocyte)
  - 1:10-1:50 — Tip: "The framework flags the VERVE-101 LFT lesson and recommends the LNP reformulation Verve actually applied"
  - 1:50-2:30 — Click Run, show 6 outputs including IND-readiness checklist
  - 2:30-3:00 — Closing tip: "Same workflow recovers Beam BEAM-101 (sickle cell, ex vivo HSC, ABE) and Verve VERVE-201 (ANGPTL3)."

### T04 — GLP-1 modality bake-off (MASH story)
- **Query**: "What's the best GLP-1 modality for MASH? Compare semaglutide, tirzepatide, retatrutide"
- **Workflow**: `glp1_modality_bakeoff`
- **Story arc**:
  - 0:00-0:20 — Tip: "Every pharma is asking 'what's the next GLP-1?' The answer is indication-aware."
  - 0:20-1:10 — Type query, show receptor atlas (GLP1R / GIPR / GCGR)
  - 1:10-1:50 — Tip: "For MASH, GCGR adds hepatic fat oxidation — triple agonist wins (retatrutide-class)"
  - 1:50-2:30 — Click Run, show modality comparison CSV
  - 2:30-3:00 — Closing tip: "Switch indication to T2D and the workflow correctly downgrades triple agonist (GCGR causes hyperglycemia)."

### T05 — Q4 2024 FDA validation panel
- **Query**: "Score every therapeutic modality for BCMA based on single-cell atlas expression for multiple myeloma"
- **Workflow**: `atlas_expression_query` → `modality_triage`
- **Story arc**:
  - 0:00-0:20 — Tip: "We ran this framework on every Q4 2024 FDA approval. 7/7 verdicts match the approved label."
  - 0:20-1:10 — Type query, show atlas → triage chain
  - 1:10-1:50 — Tip: "Plasma-cell-restricted target → CAR-T VIABLE (matches Abecma/Carvykti). ADC also viable, bispecific viable."
  - 1:50-2:30 — Click Run, show triage report + IHC follow-up panel
  - 2:30-3:00 — Closing tip: "Apply to your unannounced 2025 pipeline. We will show you what's in its atlas profile."

## Implementation plan

1. Create one `.demo.ts` file per tutorial, copying the structure of `demo-01-drug-discovery.demo.ts` (the cleanest template).
2. Use the `tip()` helper for every callout — duration tuned so total demo lands at ~180s.
3. Use `pause()` between actions to give the UI time to render before the next callout.
4. Use `shot()` at key moments for static frames (post-execution thumbnails).
5. Add each demo file to `run-demos.sh` (the `DEMOS=()` default list).
6. Run with: `cd frontend && ./e2e/run-demos.sh T01 T02 T03 T04 T05` (or omit args for the default set).

## Timing budget per demo

Total target: 180 seconds. Breakdown:

| Phase | Time | Action |
|---|---|---|
| Setup + welcome | 5s | Page load, opening tip |
| Type query | 15-30s | Character-by-character type with pauses (mimics human) |
| AI routing | 20-40s | Real chat-stream LLM response — varies by query |
| Workflow panel review | 30s | Tip + screenshot showing extracted params |
| Run → execute | 90-150s | AWS Batch run time (workflow-dependent: 2.5-4.5 min) |
| Output review | 20s | Tip pointing at output files |
| Closing | 5s | Final tip + last screenshot |

Reality: AWS Batch runs vary from 2:30 to 4:30, so total demo runtime is 3-5 minutes. To hit a strict 3-minute target, two options:

- **Option A**: Pre-compute the run (have an existing successful run_id in S3), and the demo replays "show results" without waiting for execution. Acceptable for sales demos where the time-to-output is not the message.
- **Option B**: Use ffmpeg in post-production to speed up the execution wait phase 4× while keeping audio in real-time. Standard demo-video practice.

Recommendation: **Option A** for the first cut (cleaner edits, more predictable runtime), with Option B as an alternative for the live "watch it run" feel.

## Post-recording polish (post-MVP)

Once the 5 raw recordings exist, the Gemini TTS pipeline documented in `20260427_TUTORIAL_RECORDING_PLAN.md` can layer professional narration on top. Voice option: `Aoede` (best clarity for technical content). Audio + video merge via ffmpeg. This is a polish pass, not a blocker for shipping the raw recordings to the marketing team.

## Deliverables after this work

- `frontend/e2e/demo-T01-bispecific-format.demo.ts` through `demo-T05-modality-triage.demo.ts` — 5 Playwright demo scripts
- 5 × `.webm` videos in `frontend/e2e/demo-videos/`
- Updated `run-demos.sh` with T01-T05 in the default DEMOS list
- This doc (`20260513_tier0_demo_recording_plan.md`)
- Optional: 5 × `.mp4` with narration after TTS polish pass

The recordings go to `https://biomate.ai/blog/...` (embedded in the existing blog posts) and to a `/demos` route or YouTube channel for direct sales sharing.
