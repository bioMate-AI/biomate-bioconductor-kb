# BioMate — Capability Whitepaper (Translational & Biomarker Science)

**Date:** 2026-07-27 · **Audience:** translational/biomarker leaders and their partners · **Status:** honest capability map — maturity levels are stated plainly, not inflated.

---

## What BioMate is
BioMate is a **virtual AI research workforce** — a Bioconductor-native orchestration layer that runs the full translational stack (multi-omics, single-cell, integration/endotyping, target discovery, patient stratification, biomarker evaluation, antigen resolution) **end-to-end from natural language, without the client standing up a bioinformatics team.** Every result is **closed-system, human-in-the-loop, and citable** — no open/generative black box, no fabricated data. We sell **capability to drug developers** (trial enrichment, responder/biomarker stratification, target and epitope selection, trial design) — **not a per-test clinical product.**

---

## Capability map (honest maturity)
Legend: 🟢 validated on real data · 🟡 method + plumbing verified on idealized/known-answer inputs · 🟠 available in the 4,000+ workflow catalog, not integrated/validated for this use · 🔴 gap.

| UCB target-discovery stage / addition | Workflow | Maturity |
|---|---|---|
| **2. Multi-omics profiling** | genomics/transcriptomics/proteomics/metabolomics, single-cell, CyTOF | 🟠 |
| **3. Integration & AI prioritisation** | `MOFA+` integration · `GMRP` causal MR · pathway enrichment · **`target_scorecard_ranker`** (OT two-layer, transparent weighted harmonic-sum ranking) | 🟡 (scorecard); 🟠 (rest) |
| **3/4. Evidence acquisition** | **`query_opentarget`** (live Open Targets → genetic/tractability/safety) | 🟡 |
| **4. Target ID & prioritisation** | **`target_scorecard_ranker`** + prioritisation panel | 🟡 |
| **5. Validation** | perturbation (`Perturb-seq`, `GEARS`) | 🟠 |
| **6. Biomarker / patient selection** | **`autoantibody_isotype_stratification`** (isotype→FcRn/BAFF-APRIL) · **`gate3_interaction_test`** (predictive-vs-prognostic) | 🟡 |
| **6/7. Trial design** | **`virtual_trial_gate3`** (in-silico power/sizing for the gate-3 test) | 🟡 |
| **AI-wheel: repurposing** | **`repurposing_signature_reversal`** (Connectivity-Map) | 🟡 |
| **Harmonization (Stage 1 substrate)** | **`integration_benchmark`** (scIB two-objective, over-correction detection) · **`metadata_harmonizer`** (grounded ontology mapping, no ID hallucination) · **`cohort_qc_triage`** (batch-confounding gate) | 🟡 |
| **Antigen resolution (moat lane)** | **`antigen_resolution`** (TCR↔HLA↔peptide, class-II DP/DQ) | 🟡 |
| **Downstream chemistry** | `target_to_lead_full`, ADMET/hERG, PBPK | 🟠 |

**Read this honestly:** most of the newly built components are **🟡 — the math and orchestration are verified on idealized/known-answer inputs (Open Targets data, synthetic-realistic serology, planted-answer fixtures), not yet validated on real, noisy patient cohorts.** They are credible capability demonstrations and real, tested software — not a solved end-to-end workflow. Moving 🟡→🟢 on real cohort data is the current priority.

---

## Three differentiators (stated honestly)

**1. Gate-3 discipline — predictive, not just prognostic.**
Most published stratification stops at "this subgroup does worse" (prognostic, commercially worthless). BioMate is built around the **biomarker × treatment interaction** (`gate3_interaction_test`) and reports the number the field hides — the **fraction of treatment decisions the biomarker changes** — plus an in-silico **power/sizing simulation** (`virtual_trial_gate3`) to design the enriched trial before spending on it. We help developers run a *smaller, better-powered* real trial and hand them the pre-trial evidence package.

**2. Harmonization — the field's unsolved bottleneck, operationalised.**
There is no universal-best integration method, and over-correction (erasing biology while mixing batches) is a real failure. BioMate's **select-and-evaluate** loop (`integration_benchmark`, scIB two-objective) selects the method that removes batch *without* erasing biology and **flags over-correction**. Metadata harmonization is **grounded + human-in-the-loop** (`metadata_harmonizer`) — deterministic ontology mapping that **never invents a term or ID** and flags low-confidence values for curation, countering the known failure of LLM-only mapping.

**3. Antigen resolution + per-client models — where the moat is.**
The **TCR↔HLA↔peptide** lane (`antigen_resolution`, emphasising the under-served class-II DP/DQ space) and **per-client model adaptation** (fine-tuned only on a client's private data, served privately) are where deep learning genuinely beats rules and where the data isn't public — the two places a defensible advantage exists.

---

## What we do NOT claim
- **No in-silico substitution for the pivotal RCT.** Virtual trials de-risk, design, enrich and power — they do not replace the interaction-test trial for approval (consistent with EMA/FDA and ICH M15 MIDD).
- **We have not "solved" endotyping.** Reproducible multi-omic subtyping is genuinely hard (the field disagrees on 3 vs 5 vs 8 endotypes); we provide the reproducibility framework, not a settled answer.
- **Metadata harmonization is not fully automated** — it is human-gated by design.
- **Wet-lab work (ex-vivo, organoids) is a partner**, not a BioMate build.

---

## How this is monetised
Capability sold to **drug development**, not a per-test product. The per-test/product route has a demonstrated low ceiling (a decade of work capping ~$100M); recurring **gate-3-enabler engagements** ($15–40M-class, stackable) and **per-client model adaptation** compound past it. BioMate is the reproducible, closed, citable orchestration layer that makes a client's stratification/target work faster and trial-ready — without adding their headcount.

---

## Grounding
Every scoring and evaluation choice is **peer-reviewed and citable** (Open Targets, Nelson 2015/Minikel 2024, scIB/Luecken 2022, CMap/Subramanian 2017, FDA-NIH BEST, NetMHCIIpan, etc.) — the full source list is the resource registry (`docs/20260727_RESOURCE_REGISTRY.md`). Transparency at the decision layer is deliberate: it is the trust that *is* the product.
