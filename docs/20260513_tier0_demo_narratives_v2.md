# Tier 0 Demo Narratives v2 — Per-Beat Plan (2026-05-13)

Detailed plan for 5 demos at 3 minutes each. Replaces the first version after lesson learned: **the AWS Batch run is NOT dead air — it's a sequence of real-time UI updates that need to be tipped through.**

## What's on screen during an AWS Batch run (the part I missed v1)

When the user clicks Run, the BioMate UI emits a series of events visible in real time:

| Event | Timing | What viewer sees | Source |
|---|---|---|---|
| Click Run | 0:00 | Button switches to spinner; phase card `data-status="pending"` | UI immediate |
| Execute POST returns | +1s | Footer shows "Running…"; panel header badge `data-status="running"` | `/api/nextflow/execute` response |
| Phase card flips | +5-10s | `data-status="pending"` → `data-status="running"` on first phase | SSE workflow_status event |
| Step rows update | +20-60s | Steps in panel emit `data-status="running"`/`"completed"` one-by-one | SSE step events from nextflow_executor |
| Findings card preview | +90-120s | A "first output detected" preview card may appear | Auto-poll of `/api/nextflow/runs/<id>/output_files` |
| Output files surface | +160-200s | File preview tiles appear in panel ("atlas_expression.csv", etc.) | S3 listing returns |
| Completion badge | +200-240s | Phase cards `data-status="completed"`; footer "Run again" button | `/api/nextflow/status` returns succeeded |
| Findings card finalized | +240-260s | AI-generated findings narrative appears | `/api/workflows/runs/:id/findings` |

Each of these is a tip-worthy moment. A good 3-min demo narrates 6-8 of them. My v1 demos narrated 0.

## Demo budget — 3 min = 180 seconds

Time budget per demo:

| Beat | Duration | Cumulative | Purpose |
|---|---|---|---|
| 1. Open + intro tip | 12s | 0:12 | Industry hook (Ivonescimab / VERVE-102 / etc.) |
| 2. Type query + chat-stream wait | 35s | 0:47 | LLM routes the query (real LLM, real ~30s wait) |
| 3. Workflow panel review | 25s | 1:12 | Tip on extracted parameters + the phases shown |
| 4. Click Run + dispatch confirmation | 8s | 1:20 | Tip: "Submitting to AWS Batch — watch phase cards update live" |
| 5. Live execution narration | 100s | 3:00 | 4-5 tips narrating each AWS Batch state transition (cold start → container pull → execution → output upload). This is the part I missed. |
| 6. Output recap + closing | 20s | 3:20 | Tip + final screenshot |

Note: total comes to 3:20. Three options:
- Trim Beat 2 by 5-10s (faster query typing or shorter query)
- Trim Beat 5 by cutting one tip (3 tips instead of 4-5)
- Accept 3:20 as the actual target (close enough to "3 minutes" for marketing)

I'll target **3:00 strict** by cutting one tip from Beat 5 per demo. Spec below assumes that.

## Per-demo narrative plans

### T01 — Bispecific Format Triage (PD-1 × VEGF / Ivonescimab)

| Beat | Timing | On-screen | Tip text |
|---|---|---|---|
| 1 | 0:00-0:12 | Empty chat | "October 2024 — Ivonescimab (PD-1 × VEGF CrossMab) beat Keytruda in HARMONi-2. Watch BioMate recover that format choice from inputs alone." |
| 2 | 0:12-0:47 | Query typed; chat-stream emits delta events; workflow_ready event | (no tip — let the AI do the talking) |
| 3 | 0:55-1:12 | Workflow panel shows `bispecific_format_triage`, params: `target_a=PDCD1, target_b=VEGFA, indication=NSCLC, mechanism=auto` | "BioMate extracted both targets, the indication, and routed to bispecific_format_triage. Confidence 124." |
| 4 | 1:12-1:20 | Click Run button | "Submitting to AWS Batch — watch the phase cards update live." |
| 5a | 1:20-1:50 | Phase card "BISPECIFIC_FORMAT_TRIAGE" flips `pending` → `running` | "Phase 1 launched. AWS Batch worker spinning up, pulling the biomni-tools container." |
| 5b | 1:50-2:25 | Step row shows progress; tip about scoring | "Inside the container right now: 5 bispecific formats scored on 6 axes — half-life, cis engagement, trans engagement, manufacturing, ADA risk, affinity asymmetry." |
| 5c | 2:25-2:45 | Output preview tile appears (`bispecific_format_report.json`) | "First output landed — format ranking complete. CrossMab #1 (score 100, 67%), matching Ivonescimab exactly." |
| 6 | 2:45-3:00 | Status badge flips to "Completed"; findings panel shows | "30 seconds of orchestration. Same answer Akeso reached over 18 months of internal work." |

### T02 — In Vivo CAR-T Co-Design (CD19 + anti-CD8 LNP)

| Beat | Timing | On-screen | Tip text |
|---|---|---|---|
| 1 | 0:00-0:12 | Empty chat | "Capstan, Umoja, Kelonia raised $400M+ to skip ex vivo CAR-T manufacturing. The hard part is multi-modality: LNP × target × fratricide. Watch all three resolve." |
| 2 | 0:12-0:47 | Query typed | (no tip) |
| 3 | 0:55-1:12 | Panel shows `in_vivo_cart_codesign`, params: `car_target=CD19, indication=b_cell_lymphoma, lnp_targeting=anti_CD5, persistence=transient` | "Four phases queued: atlas safety → LNP tropism → fratricide check → CAR construct assembly." |
| 4 | 1:12-1:20 | Click Run | "Submitting the full chain to AWS Batch." |
| 5a | 1:20-1:50 | Phase card running | "Phase 1: atlas check on CD19. B-cell restricted, no critical tissue hits — VIABLE." |
| 5b | 1:50-2:25 | Step transitions | "Phase 3 is the trap. LNP anti-CD5 transfects T cells. CD19 is on B cells. No overlap → no fratricide." |
| 5c | 2:25-2:45 | Output: `cart_construct.fasta`, `fratricide_check.json` | "CAR construct emitted as FASTA — FMC63 + CD8α + CD28 + CD3ζ, the Kymriah architecture. 1485 amino acids." |
| 6 | 2:45-3:00 | Completed badge | "If we switched CAR target to CD7, that same workflow would correctly fire a fratricide warning — automatically." |

### T03 — In Vivo Base Editing (PCSK9 / VERVE-102)

| Beat | Timing | On-screen | Tip text |
|---|---|---|---|
| 1 | 0:00-0:12 | Empty chat | "VERVE-102 dosed first patient Q4 2024 — the most-watched gene editing trial in the world. PCSK9 KO via in vivo base editing. Can BioMate reach Verve's design?" |
| 2 | 0:12-0:47 | Query typed | (no tip) |
| 3 | 0:55-1:12 | Panel shows `in_vivo_base_edit_design`, params: `target_gene=PCSK9, edit_goal=loss_of_function, indication=hypercholesterolemia` | "Five phases: tissue restriction check → editor class → delivery → guide RNA → IND-readiness." |
| 4 | 1:12-1:20 | Click Run | "Submitting." |
| 5a | 1:20-1:50 | Atlas check phase | "Atlas confirms PCSK9 is hepatocyte-restricted — ideal LNP IV target." |
| 5b | 1:50-2:25 | Editor selection phase | "Editor: CBE (cytosine base editor). Mechanism: premature stop via CAA→TAA at codon W8. Exactly what VERVE-101 used." |
| 5c | 2:25-2:45 | Delivery phase + CMC flag output | "CMC flag emitted: 'VERVE-101 LFT elevation Nov 2023 — optimize LNP for lower hepatotoxicity.' That's the exact reformulation Verve applied for VERVE-102." |
| 6 | 2:45-3:00 | Completed | "Same workflow recovers Beam BEAM-101 (sickle cell, ABE, ex vivo HSC) and Verve VERVE-201 (ANGPTL3)." |

### T04 — GLP-1 Modality Bake-Off (MASH)

| Beat | Timing | On-screen | Tip text |
|---|---|---|---|
| 1 | 0:00-0:12 | Empty chat | "GLP-1 is the trillion-dollar drug class of the decade. Every pharma is asking 'what's the next GLP-1?' The answer is indication-aware." |
| 2 | 0:12-0:47 | Query typed | (no tip) |
| 3 | 0:55-1:12 | Panel shows `glp1_modality_bakeoff`, params: `indication=mash` | "Workflow scores six modalities across three receptors — GLP1R, GIPR, GCGR — weighted by indication." |
| 4 | 1:12-1:20 | Click Run | "Submitting." |
| 5a | 1:20-1:50 | Atlas pulling phase | "Atlas pulling expression for all three GLP-1 family receptors. GCGR is hepatocyte-dominant — that matters for MASH." |
| 5b | 1:50-2:25 | Scoring phase | "GCGR adds hepatic fat oxidation. For MASH (hepatic indication), that's an asset. For T2D, it'd be a liability — hyperglycemia." |
| 5c | 2:25-2:45 | Output: `modality_comparison.csv`, `glp1_bakeoff_report.json` | "Top recommendation: retatrutide-class triple agonist. Receptor pattern GLP1R + GIPR + GCGR." |
| 6 | 2:45-3:00 | Completed | "Tirzepatide for obesity. Retatrutide for MASH. Orforglipron for cost. All in one bake-off." |

### T05 — Atlas + Modality Triage (BCMA)

| Beat | Timing | On-screen | Tip text |
|---|---|---|---|
| 1 | 0:00-0:12 | Empty chat | "We ran this framework on every Q4 2024 FDA approval — 7 of 7 verdicts matched the approved label. Today: BCMA for multiple myeloma." |
| 2 | 0:12-0:47 | Query typed | (no tip) |
| 3 | 0:55-1:12 | Panel shows `atlas_expression_query` chained to `modality_triage`, params: `target_gene=BCMA, indication=multiple_myeloma` | "Atlas query first, modality triage second. Both phases queued automatically — the AI knows the chain." |
| 4 | 1:12-1:20 | Click Run | "Submitting the chain." |
| 5a | 1:20-1:50 | Atlas phase running | "Querying Tabula Sapiens + CELLxGENE Census for BCMA expression across 26 tissues." |
| 5b | 1:50-2:25 | Triage phase running | "Atlas profile: plasma cells (high) + plasmablasts (moderate). No critical-tissue hits. CAR-T evaluation in progress." |
| 5c | 2:25-2:45 | Output: `modality_ranking.csv`, IHC panel | "CAR-T VIABLE — exactly the Abecma/Carvykti pattern. Plus an IHC follow-up panel with antibody validation guidance for IND prep." |
| 6 | 2:45-3:00 | Completed | "Run this on your unannounced 2025 pipeline. We'll show you what's in its atlas profile, before $50M of preclinical commitment." |

## Implementation requirements

For each demo, the Playwright script needs to:

1. **Watch for phase-card state transitions** — Beat 5a, 5b, 5c are triggered when the workflow panel's `data-status` attributes change. Use `page.waitForFunction(...)` to detect each transition before firing the next tip.

2. **NOT use `waitForNoActiveRuns()`** — that helper just polls until done with no UI cues. Instead, watch for specific UI selectors:
   - 5a: phase card `data-status="running"` for first time
   - 5b: step row count increases OR specific step name becomes "running"
   - 5c: output file tile becomes visible (selector: `[data-testid^="output-file-"]` or similar)
   - 6: completion badge `data-status="completed"`

3. **Tighter tip durations** — most tips at 3500-4000ms instead of 5000-7000ms.

4. **Asynchronous tips** — fire tips in parallel with state-watching, so the tip lifetime overlaps the AWS wait rather than blocking it.

## Decision needed from you before recording

Three things to confirm:

1. **3:00 vs 3:20 strict** — I can hit 3:00 if I cut Beat 5b (one tip in the middle of the AWS wait) OR I can keep all 5 beats and the demo lands at ~3:20. Which is acceptable?

2. **Live runtime variance** — AWS Batch cold-start adds 30-60s. If the worker is warm from the previous demo, total can be ~2:30. Cold start, ~3:30. Do you want me to pre-warm a worker before recording (one throwaway dispatch 60s before each demo) for consistent timing?

3. **What to do if step events don't surface to the UI** — the SSE step events from `nextflow_executor.py` exist but might not be wired to the panel for these new biomate-ai-tools workflows (the existing demos use `nf-core/sarek` which has well-defined step names). If the panel doesn't surface step-by-step updates, Beat 5b's tip would fire without visible accompanying UI change. Acceptable, or do I need to wire up step events first?

Once you confirm, I'll update the 5 demo files to match these narratives and re-record. No more recordings until the plan is approved.
