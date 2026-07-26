# Target Identification (UCB "Modern Target Discovery") — Capability Gap Evaluation

**Date:** 2026-07-23
**Source material:** `reference/claude_design/target_identification_design/`
— Jessica VanBaaren (UCB) talk *"Reinventing Target Discovery"* (PDF transcript + Q&A) and two workflow diagrams (`designflow1.jpg` = 7-stage pipeline, `design_flow2.jpg` = 6-spoke AI wheel with human-in-the-loop center).

---

## 1. What the client is actually asking for

UCB's "modern target discovery workflow" is an **upstream, disease-biology → ranked-target pipeline**. It is *not* the "given a target, find a lead compound" problem BioMate already solves well. Seven stages:

| # | Stage | UCB sub-capabilities |
|---|-------|----------------------|
| 1 | Cohort Design & Patient Stratification | deep phenotyping, disease subtypes, longitudinal sampling, clinical metadata |
| 2 | Multi-omics Profiling | genomics, transcriptomics, proteomics, metabolomics |
| 3 | **Data Integration & AI Prioritization** | causal inference, feature ranking, pathway analysis, subtype detection |
| 4 | **Target Identification & Prioritization** | genetic support, cell specificity, biological relevance, tractability |
| 5 | Validation in Disease-Relevant Models | patient-derived models, perturbation assays |
| 6 | Biomarker Development | target-engagement + PD biomarkers, patient-selection strategies |
| 7 | Translational Readiness | clinical endpoints, safety, go/no-go |

The **AI wheel** (stage 3 expanded): Multimodal Integration · Subtype Clustering · Feature Ranking · Risk Triage · Biomarker Mapping · Repurposing Hypotheses — **humans at the center making the go/no-go call.**

**Cross-cutting buying criteria from the Q&A (these are the real deal-makers):**
- **Closed AI system** — no ChatGPT/open models; IP protection + hallucination control ("molecules that defy physics", "biological pathways that make no sense").
- **Data harmonization + metadata QC** — heterogeneous, decades-old datasets; triage/filter low-quality data; missing donor metadata is the #1 practical blocker.
- **Human-in-the-loop governance** — AI ranks, humans decide; documented decisions.
- **Bridge the data-scientist ↔ bench-scientist gap** — a recurring, explicit pain point.
- **Clinical translation / regulatory acceptance of AI findings** — acknowledged by UCB itself as unsolved industry-wide.

---

## 2. Stage-by-stage: what BioMate HAS vs. NOT

Grounded in `backend/database/galaxy_ai_tools.db` (this DB: 386 workflows + 9 curated chains; production DB: ~2,455).

| UCB stage | Status | Evidence in BioMate | Gap |
|---|---|---|---|
| **1. Cohort / stratification** | 🔴 **Missing** | No cohort object, no clinical-metadata model, no longitudinal sample tracking | No front-end for "which patients, which criteria, what metadata" |
| **2. Multi-omics profiling** | 🟢 **Strong** | Genomics (`nf-core/sarek`, 37 wf), transcriptomics/scRNA (`nf-core/rnaseq`, `nf-core/scrnaseq`, 18 single-cell + spatial wf incl. Visium/MERFISH/multiome), proteomics + metabolomics (`multi_omics/lc_ms_proteomics_metabolomics`) | Each modality runs standalone; no shared sample/patient key across runs |
| **3. Data integration & AI prioritization** | 🟠 **Partial / core gap** | Pathway/enrichment (14 enrich wf, clusterProfiler/enrichGO); LC-MS chain does protein–metabolite correlation network + joint ORA | **causal inference = 0; cross-omic subtype clustering = 0; target feature-ranking = 0.** This is the heart of the ask and mostly absent |
| **4. Target ID & prioritization** | 🟠 **Partial** | `Target Tractability Scorer` (TDL + pocket druggability + ChEMBL density, OpenTargets framework), `Target Engagement Kinetics`, `Sirna Offtarget Analysis` | No **aggregate target scorecard** fusing genetic support + cell specificity + biological relevance + tractability into one ranked list |
| **5. Validation in disease models** | 🟢 **Strong (computational)** | `Perturb Seq Analysis` (MAGeCK+scVI), `GEARS Perturbation` (GPU), `State Perturbation Prediction`, metabolic-network perturbation | No wet-lab/patient-derived-model integration (expected — BioMate is compute) |
| **6. Biomarker development** | 🟠 **Weak** | 2 biomarker-tagged wf; DE/outlier surfaces exist | No dedicated biomarker-discovery → patient-selection pipeline |
| **7. Translational readiness** | 🟠 **Partial** | ADMET/hERG safety, QC go/no-go gates, IND report generation, PBPK | Safety strong; **clinical-endpoint linkage weak**; regulatory-acceptance unsolved (industry-wide) |

**AI wheel mapping:** Multimodal Integration 🟠 · Subtype Clustering 🔴 · Feature Ranking 🔴 · Risk Triage 🟠 (QC gates/ADMET) · Biomarker Mapping 🔴 · Repurposing Hypotheses 🔴 · **Human-in-the-loop 🟢 (BioMate's QC-loop philosophy is a native match).**

**Cross-cutting fit:**
- Closed AI / IP / no-hallucination → 🟢 **strong native fit** (controlled LLM routing, schema-validated extraction, workflow-grounded answers). *This is the single best-aligned selling point.*
- Chat → workflow (bench↔data-science bridge) → 🟢 **strong native fit** (natural-language-to-pipeline is exactly BioMate's UX).
- Human-in-the-loop governance / audited decisions → 🟢 fit (QC auto-loop + audit).
- Metadata harmonization / low-quality-data triage → 🔴 **missing** (no cross-cohort metadata QC layer).

---

## 3. The honest headline

**BioMate already owns the "hands" (per-modality execution) and the "downstream" (target→lead: `target_to_lead_full` = pocket→pharmacophore→ADMET→docking→MM-GBSA→REINVENT4). It does NOT yet own the "brain" that UCB's talk is centered on: the layer that fuses multi-omic evidence across a patient cohort into a *ranked, tractable, causally-supported target list.***

Two existing chains prove the *mechanism* is there:
- `rare_disease_multimodal_workup` — genomics + transcriptomics → **unified case report** (a mini multi-omic integration).
- `target_to_lead_full` — the downstream half, fully chained with data-passing between steps.

So this is **extension, not greenfield.** The `workflow_chains` table (with `steps` + `connections` + typed I/O) is the vehicle.

---

## 4. Gaps ranked by (client value × feasibility)

| Gap | Value to UCB | Feasibility | Notes |
|---|---|---|---|
| **G1. Target scorecard / ranking engine** (stage 4 + wheel "Feature Ranking") | ★★★★★ | ★★★★ Medium | Aggregate: genetic support (GWAS/OpenTargets API) + cell specificity (from scRNA) + expression/pathway evidence + existing Tractability Scorer → single ranked table with per-axis provenance. Mostly integration of pieces we already have. |
| **G2. Multi-omics integration layer** (stage 3, wheel "Multimodal Integration" + "Subtype Clustering") | ★★★★★ | ★★★ Medium | MOFA+/DIABLO/WGCNA-style factor + cross-omic clustering across a shared sample key. New workflow(s); well-established open methods, R/Bioconductor available on Batch. |
| **G3. Cohort + metadata layer** (stage 1 + harmonization pain point) | ★★★★ | ★★★ Medium | A cohort/sample object carrying clinical metadata + a metadata-QC/triage step ("is this data good enough to integrate?"). Directly answers the loudest Q&A complaint. Product/data-model work. |
| **G4. `target_discovery_full` curated chain** | ★★★★ | ★★★★★ High | Wire stages 2→3→4 into one chain (analog of `target_to_lead_full`), so a user goes cohort+omics → ranked targets → hand off to `target_to_lead_full`. Cheap once G1/G2 exist; a demo-able skeleton is possible *now* with stubs. |
| **G5. Causal inference** (wheel) | ★★★ | ★★ Lower | MR / causal-network methods. Scientifically hard, easy to over-promise. Scope narrowly (e.g. eQTL/MR genetic-support signal feeding G1) rather than general causal discovery. |
| **G6. Biomarker development pipeline** (stage 6) | ★★★ | ★★★ Medium | DE + target-engagement → candidate biomarker + patient-selection panel. Partially composable from existing DE/enrichment. |
| **G7. Repurposing hypotheses** (wheel) | ★★ | ★★★ Medium | Signature-reversal (LINCS/CMap-style) on the disease signature. Discrete, demo-friendly, but lower on UCB's stated priority. |

---

## 5. Feasibility summary

- **Nothing here requires abandoning the architecture.** It's new workflows + one product-level cohort object + curated chains — all on the existing Nextflow/Batch + `workflow_chains` rails.
- **The hard, credibility-sensitive piece is G1+G2** (the ranking brain). It is buildable from established methods (OpenTargets tractability we already cite, MOFA/DIABLO, WGCNA, MAGeCK/scVI we already run) — the work is *integration + a defensible scoring rubric*, not inventing ML.
- **The differentiator we can lead with today** costs almost nothing: **closed-system, IP-safe, hallucination-controlled, human-in-the-loop, natural-language-driven** — every one of UCB's stated buying criteria is already a BioMate design principle. The demo risk is over-claiming causal/clinical; the demo *strength* is "watch a bench scientist go from omics files to a ranked, provenance-backed target list without a data-science team."
- **Do NOT promise:** general causal discovery, clinical-endpoint validation, or regulatory acceptance of AI findings — UCB themselves flagged these as unsolved. Frame stages 5–7 as "supported, human-gated," not automated.

---

## 6. Action items

**Phase 0 — Alignment & demo skeleton (days, no new science)**
1. Build a `target_discovery_full` **curated chain stub** (stages 2→3→4) mirroring `target_to_lead_full`, chaining existing scRNA + DE + enrichment + Tractability Scorer, with a placeholder ranking step. Makes the vision demo-able immediately.
2. Assemble a one-page **capability map** (this table) for the UCB conversation: green = live, amber = composable, red = roadmap — honest, no over-claim.

**Phase 1 — The ranking brain (the actual value)**
3. **G1 Target Scorecard workflow**: fuse genetic support (OpenTargets/GWAS) + cell specificity (scRNA) + pathway/expression evidence + Tractability Scorer → ranked table with per-axis provenance + human-review UI (align with QC-loop pattern).
4. **G2 Multi-omics integration workflow**: MOFA+/DIABLO factor analysis + cross-omic subtype clustering over a shared sample key; output shared factors → feed G1.

**Phase 2 — Cohort + trust layer**
5. **G3 Cohort/metadata object** + **metadata-QC/triage step** ("is this data integratable?") — directly answers the harmonization pain point.
6. Package the **closed-AI / human-in-the-loop / audit** story as an explicit product surface (governance log on target decisions) — cheap, high trust value.

**Phase 3 — Fill remaining wheel spokes (as pulled by client)**
7. G6 biomarker pipeline · G7 repurposing (signature reversal) · G5 narrowly-scoped genetic causal signal (MR/eQTL) feeding G1.

**Guardrails**
- Every new workflow must run through BioMate execution (Batch / `run_code`), not local hacks (per CLAUDE.md).
- Scorecard axes must be provenance-backed and human-reviewable — no black-box target ranking (matches UCB's anti-hallucination requirement).
- Frame clinical/regulatory readiness as human-gated, never automated.

---

## 7. One-line verdict

**We have the execution engine and the downstream target→lead pipeline; UCB is buying the upstream "multi-omic evidence → ranked target" brain plus a trustworthy closed-AI, human-in-the-loop wrapper. The wrapper is already our DNA; the brain (G1+G2) is a well-scoped, feasible build on rails we already have. This is an extension play, not a rebuild — and the closed-system/human-in-the-loop story lets us lead the conversation today.**
