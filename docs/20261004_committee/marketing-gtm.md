# Committee review — Marketing / GTM lens: tutorial video series

**Date:** 2026-10-04 · **Reviewer:** Marketing / GTM strategist (skeptical-audit committee)
**Scope:** the six produced bilingual videos (T0, T1, T2, T3, T4, T11 drug-dev; EN + ZH) and the 70-episode production plan (`reference/claude_design/tutorials/series/catalog.json`, README).
**Method:** audited the walkthrough HTML, the EN narration end-to-end, ZH drug-dev narration (Steps 1–7), closing-verdict frames extracted from the MP4s, and held them against the GTM references: `docs/20260715_WORKFLOW_USECASE_PRIORITIZATION.xlsx` (all nine sheets), the hospital BD deck, the Guangzhou client deck, the competitive-intel note, the AI-drug comments/gaps note, the pharma-loop-pains survey, and the deck brief's hard content rules (`docs/20260922_CLAUDE_DESIGN_BRIEF_MARKETING_DECK.md` §6).
**Status of this document:** audit only. No tutorial file was edited.

---

## 1. Verdict

**The six videos are a competent, unusually honest product-onboarding series. They are not a GTM asset, and they should not be put in front of any P1 buyer in their current form.**

Three facts drive that conclusion:

1. **Budget allocation is inverted relative to the priority sheet.** Of 36.8 minutes of EN runtime, 21.6 minutes (59%) are spent on the drug-discovery modules (T1, T2, T11) whose own closing scorecards read `GAP — NOT YET BUILT`, `PARTIAL — OPTIMIZER NOT WIRED`, `LIVE GATE FIRING UNPROVEN ON DEV`, `AVAILABLE — NOT VALIDATED HERE`. Zero minutes are spent on the workflows that four of the five P1 segments buy: bulk RNA-seq, WGS cohorts, cryo-EM SPA, Foldseek/AlphaFold-Multimer, count-matrix DE, GWAS→eQTL target-ID. The only "real run" shown anywhere is three-compound ADMET on aspirin, caffeine and ibuprofen — shown twice (T3 and T11 reuse run `c40459b2` and the same focal assets).

2. **The moat is narrated, not demonstrated.** The positioning settled across the decks is *closed loop · verified execution · provenance · hosted compute replacing expensive software*. In the videos the closed loop appears as an empty Rounds view plus an explicitly fictional JAK1 anecdote (T2 Step 10), the QC gate is flagged as unproven, and hosted-compute advantage is a single clause in T0 ("instead of installing software"). The provenance story is the one pillar that actually lands (T3 Steps 5–7).

3. **The series breaches the hard client-facing content rules that already caused rework once** (deck brief §6): tool-stack disclosure (REINVENT4, graph neural nets, AWS Batch, BRICS, terfenadine-anchored power law), and repeated references to "dev" / "the development site" that a buyer will read as "the product may return fake answers".

**Recommended disposition:** classify the six as *internal onboarding / documentation videos*; apply a one-pass narration scrub (dev references, tool names) before any external use; redirect the next production budget to three "proof-of-compute" episodes on P1 workflows (§5). Do not scale the 70-episode catalog in its current order.

---

## 2. What lands / strengths

These are real and should be preserved, not diluted, by the fixes below.

- **Format discipline is credible for a senior-scientist audience.** Concept slide → focal live-UI capture → closing verdict table is a consistent, formal structure. Typography is restrained; there is no stock imagery, no music-video pacing, no superlatives. Frame checks of T11 (slides 1 and 17), T1 (slide 7), T2 (slide 11) and T3 (slide 6) confirm the focal-crop standard: UI text is legible at 1280 px wide.
- **The honesty posture is a genuine differentiator in this market.** The competitive-intel note is explicit that clinical proof is rare, biobucks are inflated, and the field is hype-saturated. A vendor whose tutorial says "we do not attach a blanket accuracy number, because a performance claim needs a named dataset, endpoint, metric, and split" (T11 Step 6) is speaking the buyer's language. No "first/only/no-competitor" absolutes anywhere — passes the deck brief rule.
- **T3 Step 5 ("findings withheld, not fabricated") is the single most persuasive moment in the series.** It demonstrates the provenance/honesty moat with a *real failure*, which is more convincing to a reviewer-minded scientist than any claim. Keep this beat in whatever replaces T3.
- **The compute-governance message is well pitched for budget holders.** "The lane tells you time and cost up front; nothing runs until you review and send" (T0 Steps 5–6) is exactly what a core-facility director or a Series-A CFO wants to hear about a metered cloud product.
- **T2 answers two of the three pharma loop pains directly.** "Your measurements stay private to your workspace and are never used to train shared models" (Pain 3 / Guangzhou Q18) and "model as an inspectable object: evidence on a held-out floor, lineage, used-by, versions, never overwritten" (Pain 2 / governance). This is the right material for the Guangzhou audience — it just needs a real round behind it.
- **ZH narration is idiomatic, not calqued.** Checked drug-dev.zh Steps 1–7: natural register, correct domain terms (骨架跃迁, 质控闸门, 可复现记录), honesty clauses preserved with equivalent force.
- **Series-wide metaphor is coherent.** "One doorway, one loop" (T0) is re-used as the closing habit of every episode; the viewer leaves with a mental model, not a feature list.

---

## 3. Messaging and positioning defects (specific)

Ordered by GTM damage, with file references.

### 3.1 Tool-stack disclosure — violates deck brief §6 (HARD rule)
The rule: "state **what** is delivered + a light credibility tag, never the **how**: no model class/architecture, no tool names (nf-core, sarek, REINVENT4, OpenFE, AWS/Nextflow, etc.)." The rule note says it "caused rework already."

| Location | Text | Problem |
|---|---|---|
| `narration/drug-dev.en.md:23` (+ zh:23) | "using the REINVENT4 lead-design workflow in four modes" | Named open-source tool; also tells a competitor-aware buyer the generator is AstraZeneca's, not in-house |
| `drug-dev.en.md:35` (+ zh:35 图神经网络) | "predicts ADMET properties with graph neural nets" | Model class |
| `drug-dev.en.md:41` | "as steps finish on AWS Batch" | Infra vendor |
| `drug-dev.en.md:65` | "derived from the model's classification probability through a terfenadine-anchored power law" | Internal estimator detail; the takeover review explicitly said to keep this in internal records |
| `t1-design-and-generate.en.md:17` | "a rule-based method called BRICS, not a trained generative model" | Method disclosure; also undercuts the Guangzhou deck's generation pitch (see 3.6) |
| `t3-run-and-report.en.md:35` | "open them in a Jupyter notebook" | Tool name; and the focal-standard doc records that the interactive launch 503s on dev, so the claim is also not currently demonstrable |

T2 Step 3 naming AlphaFold2 / OpenFold2 / Boltz-2 / Evo2 is defensible as a "credibility tag" (they are hosted community models the buyer recognises), but the asset captions showing "BioNeMo" are not.

### 3.2 "Dev" / "development site" leakage into customer-facing narration
A buyer does not know what "dev" is. To them, "on the development site a structure prediction may come back as a clearly-labelled stub" reads as *the product may return placeholder science*.

- `t1:41` "Here's the real form on dev."
- `t2:41` "Here it is on dev."
- `t2:53` "One caution on the development site: a structure prediction may come back as a clearly-labelled stub."
- `t4:41` "Here is the real Data hub on dev."
- `drug-dev:65` "have not yet been confirmed firing on the development site — so watch for that before relying on it mid-run."
- T2 closing table row: `Structure prediction on dev — MAY BE A STUB — CHECK THE LABEL`
- T11 closing table row: `Closed-loop QC gate — LIVE GATE FIRING UNPROVEN ON DEV`

The 2026-10-03 takeover review already required: "Remove internal implementation details and debug metrics from client-facing narration. Keep evidence in internal review records." It was not applied to the 2026-10-04 renders.

### 3.3 The flagship ends on a net-negative scorecard
T11 slide 17 (frame at 470 s) closes with seven rows: 2 × `DEMONSTRATED HERE`, 2 × `AVAILABLE — NOT VALIDATED HERE`, 1 × `PARTIAL — OPTIMIZER NOT WIRED`, 1 × `LIVE GATE FIRING UNPROVEN ON DEV`, 1 × `GAP — NOT YET BUILT`. The row marked *unproven* is the closed loop — the #1 moat in every deck. The row marked *gap* is the generator — the centrepiece of the Guangzhou engagement.

This is honest, and honesty is right. The defect is **subject selection**: the flagship films the least-finished part of the product. The priority sheet's own P1 flagship instruction (Roadmap sheet: "ADMET → REINVENT4 → PBPK → IND §2.6 — run live end-to-end once as a single session; record as marketing asset") was never executed, so stages 2, 4, 5 and 7 are concept slides with no product behind them.

### 3.4 Caveat density signals immaturity rather than integrity
Counts of hedging phrases vs value/cost phrases in the EN narration:

| Video | Words | Caveat hits | Value / cost hits |
|---|---|---|---|
| T0 | 852 | 14 | 6 |
| T1 | 1,417 | 20 | 5 |
| T2 | 1,469 | 32 | 2 |
| T3 | 1,001 | 15 | 3 |
| T4 | 1,414 | 20 | 2 |
| T11 | 1,806 | 36 | 7 |

A senior scientist values scoped claims. A video in which roughly every third sentence is a disclaimer, and value is almost never stated, does not read as rigorous; it reads as a product that is not ready. Honesty should be *concentrated* into one scoped-evidence slide per episode (demonstrated / available / roadmap) and the rest of the narration should teach and show. T3 and T11 already have that slide; the per-sentence hedges are redundant with it.

### 3.5 The demonstration science is commercially trivial, and repeated
Aspirin, caffeine and ibuprofen through ADMET is the only executed science in 36.8 minutes, and it appears in two of six episodes with the same assets. A med-chem viewer knows these molecules' profiles; the demo teaches nothing about their problem. The P1 "Series A/B biotech at IND crunch" row buys *compound-library ADMET (1,000s of SMILES, Batch array fan-out — implemented 2026-07)*, *PBPK*, *chemical similarity* and *IND §2.6 prose*. None is shown. The hERG gate — "the make-or-break number" per T11 Step 5 — never halts anything on screen.

The immune-mediated-disorder positioning that the public website now leads with ("AI drug discovery for immune-mediated disorders", `index.html` h1) is present only as a typed evidence question (T0 Step 7) and a labelled-fictional anecdote (T2 Step 10). No live scene is in the vertical.

### 3.6 Three incompatible stories about the generator
- T1 Step 3: "today the variations come from deterministic chemical enumeration — BRICS, not a trained generative model. A learned generator is on the roadmap."
- T11 Step 4: "the REINVENT4 lead-design workflow in four modes — de novo, scaffold decoration, linker design, scaffold hopping ... runs end to end today, but a trained, target-conditioned de-novo generator is not yet built."
- Guangzhou client deck slide 3/4: "integrated open generators; de novo + scaffold hopping; small-molecule-first" as the engagement's core deliverable.

A prospect who watches T1 after the deck will conclude the deck oversold. The product team must settle one description of generation capability and every asset must use it.

### 3.7 Hosted-compute advantage is never shown
The Excel's thesis is in its subtitle: "Where BioMate's hosted-compute advantage matters most: heavy compute (GPU / many-core), complex cross-specialty chains, and large reference-DB search." Every run shown in the series is something a laptop can do: a BRICS enumeration that "finishes in under a minute", a 3-compound ADMET, a CSV upload and profile. No GPU, no scale, no wall-clock, no per-lab isolation, no "multi-GPU on tap". The hospital deck's "No IT burden ... compute scales on demand" has no visual proof behind it.

### 3.8 Target identification is dismissed
T11 Step 3 frames Stage 1 as "a thinking step, not a workflow." The P1 autoimmune wedge *is* a target-ID chain (GWAS → scRNA → eQTL → prioritization), and the Guangzhou deck's breadth table lists Target ID as covered. The flagship tells the buyer that BioMate starts after the question they most need help with.

### 3.9 T4 narrates three product gaps that are core-facility requirements
"Data is project-scoped — no single 'all my data' view today", "lineage names the producing run as text, not yet a clickable link", "Versions is a log, not an undo" (T4 Steps 3, 6, 11). The core-facility P1 row's purchase rationale is "per-lab isolation + billing" and "reproducible, auditable record." A facility director hears: no cross-project view, lineage not navigable, no rollback. Either fix before filming, or do not foreground these in the closing recap.

### 3.10 CN edition undercuts a deck claim
The ZH videos pair Chinese narration with the English UI (acknowledged in the takeover doc). The hospital deck (line 100) promises "Full Chinese-language interface for your users." For a CN-primary audience (hospital cores, Guangzhou), one of the two must change before the videos are used in CN BD.

### 3.11 No call to action
Every episode ends on "the habit at a glance". None ends with a next step (try it on a dataset, request a pilot run, open the manual). For senior audiences a formal CTA is appropriate and expected; its absence leaves the viewer with a lecture, not a path.

### 3.12 Claims to verify before external use
- T3 Step 4: "You can pause or stop at any time" — skip-phase and watcher controls are commented out in the product (CLAUDE.md); confirm a pause control exists.
- T3 Step 6: "open them in a Jupyter notebook" — interactive launch 503s on dev per `docs/20261004_FOCAL_VIDEO_STANDARD.md`.
- T2 Step 3: "BioMate hosts them so you can use them directly" (AlphaFold2 etc.) while Step 9 says the prediction "may come back as a stub".

---

## 4. Priority / coverage mismatch

### 4.1 P1 segments (Excel "By User Segment") vs current and planned videos

| P1 segment | What they buy (Excel) | Current 6 videos | Planned catalog (70 episodes) | Gap |
|---|---|---|---|---|
| Series A/B biotech at IND crunch (immunology) — *beachhead buyer* | Compound-library ADMET fan-out, PBPK, ADMET→PBPK→IND §2.6 chain, chemical similarity, REINVENT4 | 3-compound ADMET (×2); PBPK, docking/RBFE, ranking as concept slides; IND absent (feature disabled) | `pk-pbpk`, `rbfe`, `molecular-docking`, `qsar-prediction`, `admet-evidence` (partial) — all "pending" | No library fan-out episode; no chemical-similarity episode; no IND/report-export path; no hERG gate firing; no real closed-loop round |
| Genomics / cryo-EM core facilities — *distribution flywheel* | Cryo-EM SPA, large WGS cohorts, bulk RNA-seq, sequence homology search | **None** | `basespace-sequencing`, `cryoem-reconstruction`, `wgs-analysis`, `rnaseq-analysis` — all under the **instruments** track | Entire segment at zero. The four episodes that would cover it are filed under the instrument track, which the 09-30 plan says is blocked on a missing instrument UI. Risk: P1 core workflows held hostage to a P3 framing |
| Non-computational wet-lab PhD / PI — *freemium front door* | Count-matrix DE (DESeq2/edgeR/limma), enrichment, methylation, single-compound ADMET | T0/T3/T4 are pitched at this persona in tone, but the demonstrated analysis is ADMET | `rnaseq-analysis` is FASTQ-based; no count-matrix DE, no enrichment, no methylation episode | The single highest-margin acquisition workflow (count-matrix DE, >90% margin, Tier 1) has no episode current or planned |
| Structural biology / target-ID — *autoimmune vertical wedge* | Foldseek AFDB structure search (implemented), AlphaFold-Multimer, cryptic-pocket→screen chain | T2 names AlphaFold2/Boltz-2 and warns the result "may be a stub" | **None** in 70 episodes | Zero coverage of a P1 segment whose key workflow is marked "Implemented" |
| Autoimmune / translational (IFN/STING) — *vertical wedge* | GWAS→scRNA→eQTL target-ID, single-cell atlases, variant lookups | None (JAK1/RA appears only as an evidence question and a fictional anecdote) | **None**; `database-evidence` loosely touches lookups | Zero coverage; the website's headline vertical has no video |

### 4.2 P1 workflows (across the Heavy/Medium/Small/Chains/DB-search sheets) vs coverage

| P1 workflow | Sheet | Status per Excel | Video coverage |
|---|---|---|---|
| Cryo-EM SPA | Heavy GPU | — | None (an older EN-only YouTube demo exists, not in series format, no ZH) |
| AlphaFold-Multimer / AF3 | Heavy GPU | — | None |
| Large WGS cohorts (sarek / GATK joint) | Heavy CPU | — | None |
| Compound-library ADMET fan-out | Heavy CPU | Implemented 2026-07 | None (3 compounds only) |
| Bulk RNA-seq from FASTQ | Medium | Validated | None |
| Full Bioconductor chains + IND prose | Medium | — | None (IND disabled) |
| Count-matrix DE | Small | — | None |
| Single-compound ADMET | Small | — | Covered (T3/T11) |
| ADMET → REINVENT4 → PBPK → IND §2.6 | Chains | "Curated (flagship) — run once, record as marketing asset" | Concept-only for 3 of 4 stages; never run end-to-end |
| Cryo-EM ensemble → pocket → screen → ADMET | Chains | Proposed | None |
| GWAS → scRNA → eQTL → target prioritization | Chains | Proposed | None |
| Foldseek protein-structure search | Large DB | Implemented | None |
| FPSim2 chemical similarity | Large DB | Implemented | None |
| Variant / entity annotation lookups | Large DB | Implemented | None (loosely in planned `database-evidence`) |
| MMseqs2 sequence homology | Large DB | Implemented | None |

**Fourteen of fifteen P1 workflows have no video.** Of the five P1 Large-DB-Search items marked *Implemented* — the "hosting the index is the win" argument — none appears in the current or planned set.

### 4.3 Catalog allocation (70 episodes)
Roughly 17 drug-development, 33 platform/UI, 18–20 instruments. Episodes such as `table-viewer`, `sequence-viewer`, `dataset-versions`, `project-sharing`, `sila2-devices`, `model-adaptation` are queued at the same priority as the P1 compute workflows. The catalog is organised by *product surface*, not by *buyer*. There is no column linking an episode to a segment or to the Excel priority, so there is no mechanism to notice that the beachhead buyer and the flywheel segment are both uncovered.

---

## 5. Prioritized recommendations

Ordered by expected GTM impact per unit of production effort.

### P0 — before any external use of the existing six (days)
1. **Reclassify** the six as *onboarding / product documentation*, not BD collateral. Label the Drive folder accordingly; do not attach them to the Guangzhou or hospital decks.
2. **One-pass narration scrub** of the affected scenes only (the narration-hash receipts allow partial re-TTS): remove "dev"/"development site" (3.2), remove tool and infra names (3.1), move the two "unproven on dev" scorecard rows to internal QA records. Where a capability is not demonstrable, cut the scene rather than narrate the gap.
3. **Settle one sentence on generation capability** (3.6) with the product owner, and apply it to T1, T11 and the Guangzhou deck simultaneously.
4. **Add a formal closing CTA** to every episode (3.11): one slide — what to try next, where the manual is, how to request a pilot run.

### P1 — next production budget: three "proof-of-compute" episodes (weeks)
Each: 3–4 minutes, focal-standard live capture, one scoped-evidence slide, EN + ZH, showing a run a laptop cannot do, ending on the reproducibility record.

5. **Bulk RNA-seq from a public GEO accession → DE → enrichment.** Covers the wet-lab freemium front door *and* the core-facility segment with one asset; nf-core/rnaseq is the one "validated" P1 Medium workflow. Film from the Data hub / accession path, **not** the blocked instrument track. Show wall-clock and the step-by-step outputs; let the viewer see the compute class without stating prices.
6. **Compound-library ADMET fan-out (hundreds to ~1,000 SMILES, e.g. a public JAK1 ChEMBL set) with the hERG gate actually halting.** This replaces aspirin/caffeine/ibuprofen in T3 and T11, puts the series inside the immune-mediated vertical, and is the only way to make the QC-gate moat visible. **Precondition:** confirm the gate fires live (currently `UNPROVEN`); per the review-before-testing rule, do not film until it does.
7. **Cryo-EM SPA on a public EMPIAR subset** (P1 GPU; existing EN demo refreshed to series format + ZH). This is the clearest "multi-GPU on tap" proof for the core-facility flywheel segment.

### P2 — make the moat demonstrable (weeks; product-dependent)
8. **One real closed-loop round.** A retrospective round on public assay data (date-split ChEMBL actives/inactives): round-1 model → held-out floor → ingest the "new" measurements → round-2 re-evaluation, in the Rounds view. Until this exists the moat is a fictional anecdote (T2 Step 10). This is the single asset most likely to convert a Series-A buyer, and it is also the honest answer to the pharma-loop-pains survey's own caveat ("prospective loop ... unproven").
9. **Run the flagship chain once for real** (Excel Roadmap P1 instruction). IND Report is disabled in the UI; either re-enable the generic report-export path and film ADMET → PBPK → report, or re-cut T11 to the demonstrated stages (3, 6, 8) and move stages 2/4/5/7 into a separate, clearly labelled *roadmap* short so the flagship no longer ends 4-of-7 not ready.
10. **Structural-biology / target-ID short:** Foldseek AFDB search (P1, Implemented) + AlphaFold-Multimer. Zero coverage today for a P1 segment; add to the catalog ahead of all viewer/sharing episodes.

### P3 — catalog and message hygiene
11. **Re-key the 70-episode catalog by buyer segment and Excel priority.** Add `segment` and `excel_priority` fields; demote `table-viewer`, `sequence-viewer`, `dataset-versions`, `project-sharing`, `sila2-devices`, `model-adaptation` behind every P1 workflow. Decouple the four core-facility workflow episodes from the instrument track so they are not blocked by the missing instrument UI.
12. **Add a reusable 60–90 s "why hosted" segment** (no install, GPU/many-core on demand, per-lab isolation, pay for the answer, full record) with one real wall-clock figure from the P1 episodes. Reference it from each episode's opening rather than re-explaining.
13. **Concentrate honesty into one scoped-evidence slide per episode** (demonstrated here / available / roadmap) and remove per-sentence hedges (3.4). Keep T3's "withheld, not fabricated" beat.
14. **Resolve the CN interface claim** (3.10): verify i18n on dev; if the Chinese UI is not live, amend the hospital deck before the ZH videos are used in CN BD.
15. **Fix or stop narrating the T4 gaps** (3.9) — cross-project data view, clickable lineage, version restore — before the series is shown to a core facility.

---

## Appendix — evidence index

- Runtime (ffprobe): T0 222 s · T1 399 s · T2 417 s · T3 284 s · T4 405 s · T11 479 s (EN); ZH within +4–70 s each.
- Frames inspected: T11 slides 1 and 17; T1 slide 7; T2 slide 11; T3 slide 6 (scratchpad `frames2/`).
- Narration audited: all six `*.en.md`; `drug-dev.zh.md` Steps 1–7.
- References: `docs/20260715_WORKFLOW_USECASE_PRIORITIZATION.xlsx` (Overview, By User Segment, Heavy GPU, Heavy CPU, Medium, Small, Complex Chains, Large DB Search, Hub, Roadmap); `docs/20260920_HOSPITAL_BD_DECK_EN.md`; `docs/20260921_BIOMATE_PHARMA_GUANGZHOU_CLIENT_DECK.md`; `docs/20260921_COMPETITIVE_INTEL_AI_DRUG_DISCOVERY.md`; `docs/20260922_AIDRUG_COMMENTS_DECK_GAPS_AND_BREADTH.md`; `docs/20260924_PHARMA_LOOP_PAINS_LEVERAGE_SURVEY.md`; `docs/20260922_CLAUDE_DESIGN_BRIEF_MARKETING_DECK.md` §6; `docs/20260930_MARKETING_TUTORIALS_GAP_AND_PLAN.md`; `docs/20261002_TUTORIAL_COVERAGE_MATRIX.md`; `docs/20261003_TUTORIAL_VIDEO_TAKEOVER.md`; `docs/20261004_FOCAL_VIDEO_STANDARD.md`; `reference/claude_design/tutorials/series/README.md`.
