# Tier 0 Demo Videos — Final (2026-05-14)

5 demo videos recorded live through BioMate, edited to ~3 minutes each, ready to share.

## Final cuts

| Demo | Story | Final | Raw |
|---|---|---|---|
| **T01** — `bispecific_format_triage` | PD-1 × VEGF / Ivonescimab HARMONi-2 | **2:44** | 5:27 |
| **T02** — `in_vivo_cart_codesign` | CD19 + anti-CD8 LNP / Capstan in vivo CAR-T | **2:43** | 5:26 |
| **T03** — `in_vivo_base_edit_design` | PCSK9 base editing / VERVE-102 | **3:08** | 7:56 |
| **T04** — `glp1_modality_bakeoff` | Tirzepatide / retatrutide / MASH race | **2:45** | 5:27 |
| **T05** — `atlas + modality_triage` | BCMA / Q4 2024 FDA validation | **2:45** | 5:27 |

Total runtime across all 5: ~14 min. Average ~2:50/demo.

## Where they live

### Local (uncompressed source)
```
frontend/e2e/demo-videos-3min/demo-T01-bispecific-format-3min.webm
frontend/e2e/demo-videos-3min/demo-T02-in-vivo-cart-3min.webm
frontend/e2e/demo-videos-3min/demo-T03-verve-base-edit-3min.webm
frontend/e2e/demo-videos-3min/demo-T04-glp1-bakeoff-3min.webm
frontend/e2e/demo-videos-3min/demo-T05-modality-triage-3min.webm
```

### S3 (for team sharing)
```
s3://biomate-production-backups-399683337364/demos/20260514/demo-T01-bispecific-format-3min.webm
s3://biomate-production-backups-399683337364/demos/20260514/demo-T02-in-vivo-cart-3min.webm
s3://biomate-production-backups-399683337364/demos/20260514/demo-T03-verve-base-edit-3min.webm
s3://biomate-production-backups-399683337364/demos/20260514/demo-T04-glp1-bakeoff-3min.webm
s3://biomate-production-backups-399683337364/demos/20260514/demo-T05-modality-triage-3min.webm
```

Download a single demo:
```bash
aws s3 cp s3://biomate-production-backups-399683337364/demos/20260514/demo-T01-bispecific-format-3min.webm .
```

Or all 5 in one batch:
```bash
aws s3 sync s3://biomate-production-backups-399683337364/demos/20260514/ ./biomate-demos/
```

### Raw recordings (also available)
```
frontend/e2e/demo-videos/demo-T0N-*.webm
```
~5–8 min each, 25–32 MB. Useful if you want to re-edit with different cut decisions.

### Screenshots (one per narrative beat, 11 per demo)
```
frontend/e2e/screenshots/demo-T0N-*/00_start.png … 10_closing.png
```

## What each demo shows (verbatim narration script)

### T01 — Bispecific Format Triage
1. **0:00-0:12** "October 2024 — Ivonescimab (PD-1 × VEGF CrossMab) beat Keytruda in HARMONi-2. Watch BioMate recover that format choice from inputs alone."
2. Query typed live; chat-stream LLM extracts targets + indication + format hint.
3. **(panel review)** "BioMate extracted PD-1, VEGF, and NSCLC; routed to bispecific_format_triage at confidence 124."
4. **(submit)** "Click Run — workflow dispatches to AWS Batch."
5. **(mid-execution)** "Phase 1 launched. AWS Batch worker spinning up, pulling the biomni-tools container from ECR."
6. **(mid-execution)** "Inside the container: 5 formats scored on 6 axes — half-life, cis engagement, trans engagement, manufacturing, ADA risk, affinity asymmetry."
7. **(mid-execution)** "First output landed: format ranking complete. CrossMab #1 (score 100, 67%) — matching Ivonescimab."
8. **(closing)** "30 seconds of orchestration. Same architectural answer Akeso reached over 18 months of design work."

### T02 — In Vivo CAR-T
1. **(intro)** "Capstan, Umoja, Kelonia raised $400M+ to skip ex vivo CAR-T manufacturing. The hard part is multi-modality co-design: LNP × target × fratricide."
2. Query → workflow_ready at confidence 144.
3. **(panel)** "Four phases queued: atlas safety → LNP tropism → fratricide check → CAR construct assembly."
4. **(mid-execution)** "Phase 1 launched: atlas check on CD19. B-cell restricted, no critical tissue hits — VIABLE."
5. **(mid-execution)** "Phase 3 is the trap. LNP anti-CD5 transfects T cells. CD19 is on B cells. No overlap → no fratricide."
6. **(mid-execution)** "CAR construct emitted as FASTA — FMC63 + CD8α + CD28 + CD3ζ. Kymriah architecture, 1485 AA."
7. **(closing)** "Switch CAR target to CD7 and the same workflow fires a fratricide warning automatically."

### T03 — VERVE-102 Base Edit
1. **(intro)** "VERVE-102 dosed first patient Q4 2024 — most-watched gene editing trial in the world. PCSK9 knockout via in vivo base editing. Can BioMate reach Verve's design?"
2. Query → workflow_ready at confidence 164.
3. **(mid-execution)** "Atlas check: PCSK9 is hepatocyte-restricted — ideal LNP IV target."
4. **(mid-execution)** "Editor: CBE (cytosine base editor). Premature stop via CAA→TAA at codon W8 — exactly what VERVE-101 used."
5. **(mid-execution)** "CMC flag emitted: 'VERVE-101 LFT elevation Nov 2023 — optimize LNP for lower hepatotoxicity.' Exactly the VERVE-102 reformulation."
6. **(closing)** "Same workflow recovers Beam BEAM-101 (sickle cell, ABE, ex vivo HSC) and Verve VERVE-201 (ANGPTL3)."

### T04 — GLP-1 Bake-Off (MASH)
1. **(intro)** "GLP-1 is the trillion-dollar drug class of the decade. Every pharma is asking 'what's the next GLP-1?' The answer is indication-aware."
2. **(panel)** "Workflow scores six modalities across three receptors — GLP1R, GIPR, GCGR — weighted by indication."
3. **(mid-execution)** "Pulling atlas expression for all three GLP-1 family receptors. GCGR is hepatocyte-dominant — that matters for MASH."
4. **(mid-execution)** "For MASH, GCGR adds hepatic fat oxidation — therapeutic. For T2D, it would be a liability — hyperglycemia."
5. **(mid-execution)** "Top recommendation: retatrutide-class triple agonist. Receptor pattern GLP1R + GIPR + GCGR."
6. **(closing)** "Tirzepatide for obesity. Retatrutide for MASH. Orforglipron for cost. All in one bake-off."

### T05 — Modality Triage (BCMA)
1. **(intro)** "We ran this framework on every Q4 2024 FDA approval — 7 of 7 verdicts match the approved label. Today: BCMA for multiple myeloma."
2. **(panel)** "BioMate chained two workflows: atlas_expression_query first, then modality_triage. The AI knew the dependency."
3. **(mid-execution)** "Querying Tabula Sapiens + CELLxGENE Census for BCMA expression across 26 tissues at single-cell resolution."
4. **(mid-execution)** "Atlas profile: plasma cells (high) + plasmablasts (moderate). No critical-tissue hits. CAR-T evaluation in progress."
5. **(mid-execution)** "CAR-T VIABLE — exactly the Abecma/Carvykti pattern. Plus an IHC follow-up panel with antibody validation guidance for IND prep."
6. **(closing)** "Run BioMate on your unannounced 2025 pipeline. We will show you what is in its atlas profile, before $50M of preclinical commitment."

## Recording + edit pipeline (reproducible)

```bash
# 1. Live record (needs frontend on :5000 + backend on :8081 + AWS Batch access)
cd frontend && ./e2e/run-demos.sh T01 T02 T03 T04 T05
#   → 25-30 min total; videos in e2e/demo-videos/

# 2. Edit each to ~3:00 (default KEEP_SECONDS_PER_ANCHOR=22)
cd frontend && KEEP_SECONDS_PER_ANCHOR=30 ./e2e/edit-demos-to-3min.sh T01 T02 T03 T04 T05
#   → ffmpeg single-pass, output in e2e/demo-videos-3min/

# 3. Upload to S3
aws s3 sync frontend/e2e/demo-videos-3min/ \
  s3://biomate-production-backups-399683337364/demos/$(date +%Y%m%d)/
```

To re-edit a single demo with longer/shorter keep-window:
```bash
KEEP_SECONDS_PER_ANCHOR=35 ./e2e/edit-demos-to-3min.sh T03   # more padding for T03
```

## How the edit pipeline works

Each Playwright demo writes 11 PNG screenshots at narrative anchor points (`00_start.png` through `10_closing.png`) into `e2e/screenshots/<demo-name>/`. The edit script uses each screenshot's mtime as a keep-window anchor on the raw video timeline, keeps ~30s around each anchor, and drops the rest via ffmpeg's `select=between(t,start,end)` filter chain. Overlapping windows merge automatically; the editing produces a single re-encoded VP9 WebM.

For each demo:
- Beat 1–4 anchors (intro through submit) compress tightly because they fire in quick succession during the live recording.
- Beat 5 mid-execution anchors are spaced ~30s apart, so each keeps its full 30s window.
- Beats 6–7 (completion + closing) compress at the end.

Final breakdown per demo: ~30s setup/query, ~90s narrated execution, ~25s outputs + closing.

## What didn't make this pass (next session)

- **Audio narration via Gemini TTS** — `docs/20260427_TUTORIAL_RECORDING_PLAN.md` documents the pipeline (already-available `GEMINI_API_KEY` + `gemini-2.5-flash-preview-tts`, voice = Aoede). 1-2 hour effort to layer voice onto the 5 video tracks via ffmpeg merge. Currently the videos are tip-bubble-only (visual narration); audio would polish them for sales meetings where the audience expects voiceover.
- **Embed in `/blog/<slug>` pages** — currently the blog posts link out; videos could be embedded inline. Trivial frontend change after audio narration is added.
- **YouTube unlisted uploads** — for sales reps to share via URL rather than file attachment. 5-min upload per video.
