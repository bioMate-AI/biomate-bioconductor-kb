# Tier-0 Tutorial Demos — Detailed Requirement for Claude Design

**Date:** 2026-06-15
**For:** Claude design / engineering handoff
**Builds on:**
- `reference/claude_design/tutorials-work/Demo Narratives.md` (cryo-EM tutorial template — step-by-step VO with timestamps + scene annotations)
- `reference/claude_design/tutorials-work/Bioconductor Tutorial Scenarios.md` (scenario design pattern — plan checklist + tape events + findings card)
- `docs/20260513_tier0_demo_narratives_v2.md` (industry-hook marketing demos for the same 5 cases — different audience, but reusable beats)
- `frontend/e2e/demo-T01-bispecific-format.demo.ts` (canonical Playwright `.demo.ts` shape: setup → tip → pause → shot → ... → close)

## Goal

Five **3-minute tutorial demos**, one per tier-0 design pipeline, that teach a new user how BioMate routes a therapeutic-design request into an executable workflow and reads the result. Unlike the v2 narratives (which were industry-hook marketing), these are instructional — every beat answers "where am I, what should I look at, what did the system just do for me." The output of this requirement is:

- 5 voice-over scripts with timestamps (≤3:00 strict, no exceptions)
- 5 `.demo.ts` Playwright recorder scripts under `frontend/e2e/`
- 5 sets of post-edited MP4 + WebM at 1920×1080 30fps
- 5 reusable still-frames per demo (intro card + outcome card)
- 1 master playlist page with chapter markers for the BioMate marketing site

The 5 demos must share a single visual grammar and tip-card style. Differences are only in **what the workflow does**, not in **how the tutorial is shot**.

---

## Shared visual grammar (applies to all 5 demos)

### 1. The 8-beat structure

Every demo follows the same beat sequence so users learn the pattern once. Total budget is 180s strict (Beat-time numbers below are wall-clock; trim Beat-5 narration if real LLM/Batch time runs long).

| # | Beat | Target | On-screen | VO purpose |
|---|---|---|---|---|
| 1 | Cold open — what BioMate will do | 0:00–0:14 | Empty chat, BioMate logo | Tease the problem + the 1-sentence outcome |
| 2 | User types the design query | 0:14–0:30 | Chat input fills letter-by-letter, then sends | Show the exact phrasing — this is the input contract |
| 3 | AI routes the intent | 0:30–0:55 | SSE delta events render assistant prose; intent kicker visible | Narrate "BioMate reads target + indication + modality → picks the right pipeline" |
| 4 | Workflow panel opens with prefilled params | 0:55–1:18 | Panel right rail, PARAMETERS line visible, first phase expanded | Point at the canonical-keyed params + provenance hint badges |
| 5 | Click Confirm & Run | 1:18–1:28 | Submit + dispatch confirmation | Beat to set up the live execution |
| 6 | Live phase-by-phase narration | 1:28–2:35 | Phase cards flip pending → running → completed; step rows tick | Tip on what each phase computes (4–5 tips total) |
| 7 | Outputs + findings card | 2:35–2:50 | File chips inline; AI findings card materializes | Show how the user reads the result |
| 8 | Closing 1-liner + outcome card | 2:50–3:00 | Status badge "Completed"; outcome graphic | Tie back to the cold-open promise |

### 2. Tip-card design

All voice-over lines are paired with a **tip-card overlay** in the upper-left of the recording, mirroring the cryo-EM tutorial template:

- 480×120px translucent card, 16px round corners, BioMate brand-bg-2
- Two-line max, 18pt Inter Medium
- Renders for 3.5–5s (long enough to read aloud, short enough to not block the panel)
- Fade in 200ms, fade out 200ms
- One tip per beat-fragment; tips never overlap

Pattern: each tip text in the per-demo spec below is what the recorder script calls `tip(page, '<text>', <duration_ms>)`. The VO actor reads the tip text verbatim — no improvisation. This keeps the demos translatable.

### 3. Screenshot ladder

Every demo emits 9 screenshots at fixed names (used both for the post-edit cutaways and for the marketing chapter thumbnails):

| Slug | When captured | Use in marketing |
|---|---|---|
| `00_start` | Beat 1 start | Chapter cover |
| `01_intro_tip` | Beat 1 tip mid-render | Cold-open frame |
| `02_query_sent` | Beat 2 end | "User just typed" frame |
| `03_workflow_ready` | Beat 3 end | "AI just routed" frame |
| `04_panel_review` | Beat 4 mid (tip on params) | **Hero shot** for case-study pages |
| `05_submitted` | Beat 5 end | "Run dispatched" frame |
| `06_phase_running` | Beat 6 mid (peak liveness) | Animated GIF source |
| `07_outputs` | Beat 7 mid (findings just rendered) | Outcome screenshot |
| `08_closing` | Beat 8 end | Chapter outro |

### 4. The mandatory UI affordances

Every demo MUST demonstrate, even if only on-screen for 2s:

- **The intent kicker** above the assistant reply — proves the system understood the user's task type
- **The PARAMETERS (N CONFIGURED) summary line** — proves prefill worked (this is the schema-grounded extraction value-prop; recently auto-expanded for first phase per PR #8)
- **Per-param "from your message" hint badges** — proves provenance is visible
- **The data-status attribute flips** on phase + overall badge — proves the SSE pipeline works
- **The findings card** at the end — proves the result is human-readable

If a recording fails to capture any of these five, the demo is rejected at audit and re-recorded.

### 5. Voice + tone

- Single male/female voice, US English, conversational pace ~140 wpm
- No jargon unless the tip-card defines it on first use
- Present tense; second person ("you'll see…"); never "the system" — always "BioMate"
- Each VO line in the spec below is also the literal tip-card text

### 6. Cross-demo continuity

The 8 beats use identical opening/closing music stings and identical tip-card transitions. Only the content of Beats 3, 4, 6, 7 varies per case. This lets a viewer who watches T01 + T03 immediately recognize the pattern in T05.

---

## Demo T01 — Bispecific antibody design (PD-1 × VEGF for NSCLC)

### Audience hook (Beat-1 tip)

> "Designing a bispecific antibody normally takes 18 months of format trials. BioMate scores every format in 30 seconds — watch."

### Query (typed letter-by-letter in Beat 2, ~16s real time)

```
Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC
```

### Expected routing

- Intent: `workflow_generation`
- Workflow: `bispecific_format_triage`
- Canonical params (must appear in Beat 4 panel summary):
  - `target_a: PD-1`
  - `target_b: VEGF`
  - `indication: NSCLC`
  - `mechanism: auto`

### Plan checklist (Beat 3 surfaces this in chat)

```
1. Parse targets + indication       (~2s)
2. Route to bispecific_format_triage (~3s)
3. Score 5 architectures            (~25s on Batch)
4. Rank + emit recommendation       (~5s)
```

### Beat 6 phase narration (live, 4 tips total)

| Sub-beat | Timing | Tip |
|---|---|---|
| 6a | 1:28–1:50 | "Phase A — Mechanism Inference. BioMate looks up published PD-1 × VEGF cis/trans data and the cell types where both targets co-express." |
| 6b | 1:50–2:10 | "Phase B — Format Scoring Matrix. Five formats — CrossMab, KiH, BiTE, DVD-Ig, knob-in-hole tetravalent — scored on half-life, ADA risk, manufacturing, affinity asymmetry, cis vs trans engagement, and clinical precedent." |
| 6c | 2:10–2:25 | "Phase C — Composite Ranking. Mechanism + format weighted together. CrossMab leads — same architecture as ivonescimab, which beat Keytruda in HARMONi-2." |
| 6d | 2:25–2:35 | "Phase D — Report Synthesis. Methods section + ranked CSV emitted." |

### Beat 7 expected outputs (file chips)

- `bispecific_format_report.json`
- `format_ranking.csv`

### Beat 8 closing

> "30 seconds. Five formats scored, ivonescimab's architecture recovered from inputs alone."

### Outcome card

- Hero ranking table with CrossMab at #1
- Subtitle: *"Same format Akeso/Summit landed on after 18 months."*

---

## Demo T02 — In-vivo CAR-T co-design (CD19 for DLBCL with LNP delivery)

### Audience hook (Beat-1 tip)

> "Ex-vivo CAR-T costs $400K-500K per patient. The new wave — Capstan, Umoja, Kelonia — delivers the CAR mRNA in vivo. Let's design one."

### Query

```
Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to T cells, transient persistence
```

### Expected routing

- Workflow: `in_vivo_cart_codesign`
- Canonical params:
  - `car_target: CD19`
  - `indication: DLBCL`
  - `delivery_cell: T_cell` (normalized from "T cells" — **call this out explicitly**)
  - `lnp_targeting: auto`
  - `persistence: transient`

### Plan checklist

```
1. Atlas safety check (CD19 expression map)   (~3s)
2. LNP tropism analysis (anti-CD8/CD5/CD7)    (~5s)
3. Fratricide check (LNP target vs CAR target) (~3s)
4. CAR construct assembly (scFv→CD3ζ)         (~30s on Batch)
5. CMC + safety flag emission                 (~5s)
```

### Beat 4 panel review — **special prefill callout**

Tip-card text:

> "Notice 'T cells' from your message was normalized to T_cell — that's the workflow's allowed value. BioMate did this automatically."

This is the single most important teaching moment of T02 — it shows the enum-normalization value of schema-grounded extraction.

### Beat 6 phase narration

| Sub-beat | Timing | Tip |
|---|---|---|
| 6a | 1:28–1:48 | "Phase A — Atlas Safety. CD19 is B-cell-restricted. No critical-tissue hits. Green to proceed." |
| 6b | 1:48–2:08 | "Phase B — LNP Tropism. anti-CD5, anti-CD7, and untargeted MC3 LNPs scored for T-cell delivery efficiency. Anti-CD5 wins for transient CD19 mRNA." |
| 6c | 2:08–2:25 | "Phase C — Fratricide Check. Critical trap: if the LNP transfects the same cell type that expresses the CAR target, the CAR-T kills the LNP-transfected pool. Anti-CD5 LNP delivers to T cells; CD19 is on B cells → no overlap → green." |
| 6d | 2:25–2:35 | "Phase D — CAR Construct. FMC63 scFv + CD8α hinge + 4-1BB costim + CD3ζ. 1485 amino acids. The Kymriah architecture." |

### Beat 7 outputs

- `cart_construct.fasta`
- `fratricide_check.json`
- `lnp_formulation_recommendation.json`
- `cmc_flag.json` (transient-persistence note)

### Beat 8 closing

> "Switch the CAR target to CD7 and the same workflow would fire a fratricide warning — automatically."

### Outcome card

- CAR construct schematic (scFv → CD3ζ chain) with annotations
- Subtitle: *"Anti-CD5 LNP + CD19 mRNA — the Capstan CPTX-2309 architecture."*

---

## Demo T03 — In-vivo base-edit knockout (PCSK9 for hypercholesterolemia)

### Audience hook (Beat-1 tip)

> "VERVE-102 — first patient dosed Q4 2024 — knocks out PCSK9 in the liver via in-vivo base editing. BioMate reaches their design choices in a minute."

### Query

```
Design an in-vivo base-edit knockout of PCSK9 for hypercholesterolemia
```

### Expected routing

- Workflow: `in_vivo_base_edit_design`
- Canonical params:
  - `target_gene: PCSK9`
  - `edit_goal: loss_of_function`
  - `indication: hypercholesterolemia`
  - `delivery: auto`
  - `editor_preference: auto`

### Plan checklist

```
1. Tissue restriction check                     (~3s)
2. Editor class selection (CBE / ABE / Prime)   (~5s)
3. Guide RNA design                             (~25s on Batch)
4. LNP hepatotoxicity flag (VERVE-101 precedent) (~5s)
5. IND-readiness checklist                      (~5s)
```

### Beat 6 phase narration

| Sub-beat | Timing | Tip |
|---|---|---|
| 6a | 1:28–1:48 | "Phase A — Tissue Restriction. PCSK9 is hepatocyte-restricted. Ideal target for IV-LNP because the liver naturally absorbs LNPs." |
| 6b | 1:48–2:08 | "Phase B — Editor Selection. CBE — cytosine base editor — picked. Mechanism: introduce a premature stop at codon W8 via a CAA → TAA edit. Exactly what VERVE-101 used." |
| 6c | 2:08–2:25 | "Phase C — Guide RNA Design. Off-target check against the whole genome; specificity score > 95% for the top guide." |
| 6d | 2:25–2:35 | "Phase D — CMC Flag. VERVE-101 had LFT elevation in Nov 2023. BioMate surfaces that precedent and recommends the LNP reformulation Verve applied for VERVE-102." |

### Beat 7 outputs

- `editor_choice.json`
- `guide_rna.csv` (top 5 candidates with specificity scores)
- `cmc_flag.md` (VERVE-101 LFT precedent)
- `ind_readiness_checklist.csv`

### Beat 8 closing

> "Verve-102's clinical-precedent-aware design choices — recovered from a single sentence."

### Outcome card

- Mechanism diagram: CAA → TAA edit at PCSK9 W8
- Subtitle: *"Premature stop = loss-of-function. VERVE-102's exact approach."*

---

## Demo T04 — GLP-1 modality bake-off (MASH)

### Audience hook (Beat-1 tip)

> "The next billion-dollar GLP-1 question isn't dosing — it's modality. Peptide injection? Oral? mRNA? Gene therapy? Watch BioMate score them side by side for MASH."

### Query

```
Compare GLP-1 modalities for MASH — peptide vs mRNA vs gene therapy
```

### Expected routing

- Workflow: `glp1_modality_bakeoff`
- Canonical params:
  - `indication: mash` (lowercase per enum)
  - `modalities: peptide,mrna,gene_therapy`
  - `delivery_pref: auto`

### Beat 3 special note for VO actor

This query also tests the **cross-intent ambiguity card path** (the LLM occasionally routes "Compare" as `tool_search`). If the IntentClarificationCard appears, the VO actor reads:

> "BioMate isn't sure whether you want to run a design workflow or just search for tools. Click 'Run a design workflow' to proceed."

…then clicks the primary chip and resumes the normal Beat-4 narration. Recording script must handle both paths.

### Plan checklist

```
1. Parse modality list                         (~2s)
2. Score each modality on 6 axes               (~30s on Batch)
3. Bake-off ranking + recommendation           (~5s)
```

### Beat 6 phase narration

| Sub-beat | Timing | Tip |
|---|---|---|
| 6a | 1:28–1:55 | "Phase A — Modality scoring across 6 axes: half-life (semaglutide weekly vs tirzepatide weekly vs survodutide), oral bioavailability (orforglipron only), CV outcomes precedent, MASH-specific liver evidence, manufacturing complexity, dosing burden." |
| 6b | 1:55–2:20 | "Phase B — Peptide injection leads on safety + CV outcomes. mRNA is still preclinical for GLP-1. Gene therapy is single-dose but has unresolved durability questions. Ranking emitted." |
| 6c | 2:20–2:35 | "Phase C — Recommendation. Peptide injection (#1), oral peptide (#2), mRNA (#3), gene therapy (#4) for current MASH indications." |

### Beat 7 outputs

- `modality_scoring.csv`
- `glp1_bakeoff_recommendation.json`

### Beat 8 closing

> "Same ranking the field converged on — recovered in 30 seconds."

### Outcome card

- 4×6 modality-scoring heatmap
- Subtitle: *"Peptide injection #1. Same place semaglutide-MASH trials landed."*

---

## Demo T05 — Modality triage for an oncology target (BCMA)

### Audience hook (Beat-1 tip)

> "You picked BCMA for oncology — now which modality? CAR-T? Bispecific? ADC? mRNA? BioMate scores all of them against the literature."

### Query

```
Triage modalities for a BCMA oncology target — try all options
```

### Expected routing

- Workflow: `modality_triage`
- Canonical params:
  - `target_gene: BCMA`
  - `indication: oncology`
  - `modalities: all`
  - `atlas_expression: null`

### Plan checklist

```
1. Atlas expression check (BCMA in plasma cells) (~3s)
2. Score across all modalities                  (~30s on Batch)
3. Composite ranking + indication-fit weighting (~5s)
4. IHC follow-up + final report                 (~5s)
```

### Beat 6 phase narration

| Sub-beat | Timing | Tip |
|---|---|---|
| 6a | 1:28–1:48 | "Phase A — Atlas Profile. BCMA is restricted to plasma cells and a fraction of mature B cells. No critical-tissue hits. Multiple myeloma is the obvious indication." |
| 6b | 1:48–2:08 | "Phase B — CAR-T Viability. Plasma-cell restriction → low off-tumor risk → CAR-T scores #1. Ide-cel and cilta-cel both validated this." |
| 6c | 2:08–2:25 | "Phase C — ADC + Bispecific TCE evaluation. Belantamab mafodotin (ADC) was withdrawn for ocular tox. Teclistamab (bispecific TCE) approved. Bispecific scores #2, ADC #3 with payload-tolerability caveat." |
| 6d | 2:25–2:35 | "Phase D — Modality Ranking. CAR-T #1, bispecific TCE #2, ADC #3, mRNA-CAR #4 (in-vivo, earlier-stage). IHC follow-up panel recommended for any pre-clinical work." |

### Beat 7 outputs

- `modality_ranking.csv`
- `ihc_followup_panel.json`
- `composite_ranking.json`

### Beat 8 closing

> "Five modalities scored, the entire BCMA competitive landscape — in a single sentence."

### Outcome card

- Modality ranking bar chart with citation badges per row
- Subtitle: *"CAR-T #1 — same place ide-cel and cilta-cel landed."*

---

## Recording infrastructure requirements

### 1. Server setup

- Local dev server on `:5001` with `SCHEMA_GROUNDED_EXTRACTION=1`, `CORS_ORIGINS=http://localhost:5001`, `E2E_TEST_TOKEN=<from env>`
- Galaxy backend on `:8081` healthy (same as audit env)
- Fixture user `lifeifei163361@163.com` pre-provisioned and logged in via cookie before recording starts

### 2. Per-demo Playwright shape

One file per demo at `frontend/e2e/demo-T0N-<slug>.demo.ts`. Each conforms to:

```ts
test('Demo T0N — <human title>', async ({ page }) => {
  test.setTimeout(900_000);
  await setupDemoUser(page, EMAIL, PASSWORD, '<workspace name>');
  await pause(page, 1000);
  await shot(page, DEMO, '00_start');

  // Beat 1 — tip + shot
  await tip(page, '<beat-1 tip text>', 5000);
  await pause(page, 5000);
  await shot(page, DEMO, '01_intro_tip');

  // Beat 2 — query (real LLM time)
  await sendAndWait(page, QUERY, 180_000);
  await shot(page, DEMO, '02_query_sent');

  // Beat 3 — intent kicker tip
  await tip(page, '<beat-3 tip text>', 4500);
  await pause(page, 4500);
  await shot(page, DEMO, '03_workflow_ready');

  // Beat 4 — panel review (mandatory PARAMETERS line callout)
  await tip(page, '<beat-4 prefill provenance tip>', 5000);
  await pause(page, 5000);
  await shot(page, DEMO, '04_panel_review');

  // Beat 5 — click Run
  await tip(page, 'Click Confirm and Run — workflow dispatches to AWS Batch.', 3500);
  const runId = await clickRunOnly(page);
  await shot(page, DEMO, '05_submitted');

  // Beat 6 — live narration loop with timed tips
  // Tip cadence: every ~22s, 4 tips total. Real wait fills the gaps.
  await tip(page, '<6a>', 4500); await pause(page, 22_000);
  await tip(page, '<6b>', 4500); await pause(page, 22_000);
  await tip(page, '<6c>', 4500); await pause(page, 22_000);
  await tip(page, '<6d>', 4500); await pause(page, 10_000);
  await shot(page, DEMO, '06_phase_running');

  // Wait for completion (real Batch run)
  await waitForCompletion(page, runId, 600_000);
  await tip(page, '<beat-7 outputs tip>', 4500);
  await pause(page, 5000);
  await shot(page, DEMO, '07_outputs');

  // Beat 8 — closing
  await tip(page, '<beat-8 closing>', 4500);
  await pause(page, 5500);
  await shot(page, DEMO, '08_closing');
});
```

### 3. Helper additions to `frontend/e2e/demo-helpers.ts`

Existing helpers cover the cryo-EM tutorial. For tier-0 we additionally need:

- `waitForCompletion(page, runId, timeoutMs)` — polls `/api/workflows/runs/:id` until status terminal
- `expectParamsLineVisible(page, expectedKeys: Record<string, RegExp>)` — asserts the PARAMETERS summary contains each key with matching value (used by the in-script audit)
- `handleIntentClarification(page, primaryType: 'workflow_generation')` — if the IntentClarificationCard appears, clicks the primary chip; returns whether it fired. Used by T04 path.

### 4. Recording cadence

Each demo records `live` at full duration (~5–6 min for cold-start Batch runs). Post-edit trims dead air between tips down to the strict 3:00 budget. The tip cards are the anchor points — every cut happens between tips, never during.

### 5. Acceptance checklist (per demo)

| Check | Pass criterion |
|---|---|
| All 9 screenshots captured | files exist with non-zero size |
| Video duration | between 175 and 200 seconds |
| Audio level | -20 LUFS ±2 |
| Tip cards visible | exactly 8–10 cards rendered (Beat-1, 3, 4, 5, 6a–6d, 7, 8 = max 10) |
| PARAMETERS summary visible | `04_panel_review.png` shows the line with all expected canonical keys |
| Enum-normalization callout (T02 only) | `04_panel_review.png` shows `T_cell`, NOT `T cells` |
| `data-status` transition captured | `06_phase_running.png` shows at least one phase with `data-status="running"` |
| Findings card present | `07_outputs.png` shows a non-empty findings card |
| Closing outcome card | `08_closing.png` shows the outcome graphic + "Completed" badge |

If ANY check fails, re-record (don't ship partial demos).

### 6. Post-production handoff

- Source MP4 (1920×1080, 30fps, H.264, 8 Mbps) and WebM (VP9, 6 Mbps) → `reference/claude_design/tutorials-work/tier0/<demo>/`
- Edited 3-min MP4 → same folder, suffix `_final.mp4`
- Hero shot `04_panel_review.png` → `reference/claude_design/tutorials-work/tier0/<demo>/hero.png`
- Master playlist HTML page generated from the 5 demos for the marketing site

---

## Out of scope (intentionally)

- Multi-language dubs (English only for v1)
- Mobile-format vertical 9:16 cuts
- Animated branded intro/outro stings (use the cryo-EM tutorial intro card unchanged)
- Showing failure / error states (separate tutorial series — "When BioMate asks for help")

---

## Open questions for the design lead

1. **Voice talent** — same voice as cryo-EM tutorial, or new voice for the design-pipeline series? Recommend same for continuity.
2. **Tip-card position** — upper-left works for the cryo-EM panel layout but T04 (chain workflow) has different panel chrome; should the tip-card flow to upper-right when the panel is missing the right rail? Recommend yes.
3. **Beat-5 ambiguity-card path on T04** — record once and use both versions, or only record the non-ambiguity path? Recommend recording BOTH (the ambiguity-card recording becomes a bonus "What if BioMate isn't sure?" mini-tutorial).
4. **Outcome-card graphics** — design-team to create per the per-demo spec above, or use a generic template? Recommend custom for the 5 hero shots; placeholder template for everything else.

---

## Sign-off

This requirement is the contract for the recording session. Any change to the 8-beat structure, the screenshot ladder, or the tip-card style across the 5 demos requires explicit approval — otherwise the post-edited videos won't compose as a consistent playlist.

Approval needed from:
- [ ] Product (final query phrasing per demo)
- [ ] Design (tip-card style + outcome-card mocks)
- [ ] Engineering (test-only flags + recording infrastructure)
- [ ] Marketing (chapter titles + playlist page layout)
