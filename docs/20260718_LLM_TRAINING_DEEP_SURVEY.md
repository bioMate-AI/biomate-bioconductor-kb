# BioMate LLM-Training Strategy — 2026 Deep Survey, Innovation Assessment & Base-Model Recommendations

**Date:** 2026-07-18 · Prepared for the "start LLM training ASAP" decision
**Scope:** Adversarial validation of the 4-layer plan in `docs/20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.md` (Part 4), via four web-research surveys. Every recommendation is grounded in cited 2024–2026 literature; unverifiable items are flagged.

---

## 0. Bottom line

The plan's **capabilities are largely no longer unique**, and **3 of its 4 base-model / method choices are outdated or behind current SOTA**. But the plan has a genuine, defensible core that the surveys *confirm*: the **execution-trace fine-tuning flywheel** (Layer 4), the **end-to-end cross-domain integration** (GWAS→scRNA→ADMET→PBPK→IND), and **autoimmune data specialization**. 

**Recommendation: proceed — but re-base and re-scope.** Swap Llama 3.1 70B → **Qwen3** family; stop treating Geneformer-for-perturbation and a STRING-GNN as novel/SOTA; adopt existing backbones (Open Targets L2G, Panacea, a STATE-style perturbation model) and concentrate original effort on the flywheel + integration + CTD §2.6, each behind a **mandatory baseline gate**.

Critically: the **2026-07-02/03 validation sessions already produced real cross-domain execution traces** (Tests 1-A GWAS→target, 1-B DESeq2, 1-F IND, 4-A §2.6, 5-A ADMET, 7-A routing) — i.e., Layer 4's training signal already exists in-house. That is the fastest, most defensible place to start.

---

## 1. Per-layer assessment

### Layer 1 — Autoimmune Virtual Cell
**Proposed:** fine-tune **Geneformer v2** for perturbation-response + patient stratification.

**2026 SOTA / adversarial finding:**
- **Geneformer for *perturbation* is contested and the best current evidence is negative.** Ahlmann-Eltze, Huber & Anders, *Nature Methods* 22(8):1657–1661 (2025) — deep models (GEARS, scGPT, scFoundation, **Geneformer**, scBERT, UCE) **fail to beat additive / mean / ridge-linear baselines** on perturbation prediction. Corroborated by Kedzierska et al. *Genome Biology* (2025) and Bendidi et al. arXiv:2410.13956 (2024, "one PCA still rules them all").
- **Arc STATE** (bioRxiv 2025.06.26.661135, Jun 2025) is the purpose-built momentum leader — but **non-commercial license**, and its *own* paper concedes it loses to linear baselines on **genetic**-perturbation metrics (−20% DE-overlap, −12% fold-change), winning mainly on *chemical* perturbation.
- **Patient stratification** (supervised, fine-tuned) is on **firmer ground** — the skeptical literature targets zero-shot and perturbation, not supervised classification.

**Verdict — innovation/significance:** stratification defensible; perturbation prediction **over-claimed**. The real differentiator is **autoimmune data**, not the base model.

**Recommendation:**
- Use **Geneformer V2 (Apache-2.0)** or scGPT (MIT) for **representation + stratification only**.
- For the **perturbation head, do NOT fine-tune Geneformer** — use a dedicated STATE-style / GEARS / CPA model, trained on the **Dec-2025 genome-scale CD4⁺ T-cell Perturb-seq** (~22M cells, MIT — the single most autoimmune-relevant perturbation dataset) + Tahoe-100M (CC0, chemical). Ground cell types on **AMP RA/SLE synovium** (Zhang et al. *Nature* 2023) + SLECA.
- **Mandatory gate:** beat additive/mean/ridge baselines before shipping (cite Ahlmann-Eltze 2025).

### Layer 2 — Multi-Omic Target Prioritization
**Proposed:** GNN on **STRING v12** + text transformer (GWAS Catalog + DICE + Open Targets + ChEMBL).

**2026 SOTA / adversarial finding:**
- The drug-approval-validated backbones are **gradient-boosted feature models, not GNNs**: **Open Targets Locus-to-Gene (L2G)** (Mountjoy et al. *Nat Genet* 2021; Gentropy rewrite adds ENCODE rE2G + trans-pQTL features) and **PoPS** (Weeks et al. *Nat Genet* 2023, already encodes PPI as features).
- **eQTL colocalization alone does NOT predict drug approval** (benchmark OR 1.61, 95% CI 0.92–2.83, n.s.; L2G OR 3.14 ≈ nearest-gene OR 3.08) — a red flag for the plan's DICE-eQTL-centric design. *(Numbers from a 403-gated medRxiv 2025 benchmark via search summaries — directional, verify before citing.)*
- Where deep learning genuinely wins: **context-specificity** — **PINNACLE** (Li, Huang, Zitnik, *Nature Methods* 2024; 394,760 context-specific protein embeddings) — and **richer functional KGs** — **KGWAS** (snap-stanford, 2024 preprint; 11M interactions, 55 relation types). A static STRING graph is dominated by both.

**Verdict:** the STRING-GNN as-specced is a **2020-era design, behind SOTA, not novel**.

**Recommendation:** **UPGRADE** — consume the **L2G/Gentropy score** as the backbone; if you want a learned network component, replace static STRING with **PINNACLE** or **KGWAS** (STRING becomes one edge type, not the whole graph); demote eQTL to a feature; **validate on drug-approval labels**, beating nearest-gene + L2G.

### Layer 3 — Clinical Trial Design LLM
**Proposed:** fine-tune **Llama 3.1 70B** on AACT + FDA packages + PubMed for endpoints, eligibility, stratification biomarkers, §2.6 narratives.

**2026 SOTA / adversarial finding:**
- **Panacea** (Lin/Wang et al., arXiv:2407.11007, 2024; Mistral-7B; TrialAlign 793K docs + 1.1M papers) **already does endpoint / eligibility / study-arm design** and is benchmarked on **TrialPanorama**. Endpoint/eligibility/arm design is **not novel**. Benchmark to beat: **CTBench** (arXiv:2406.17888).
- **Stratification-biomarker selection is the wrong tool-fit** for an LLM fine-tune — it's a multimodal clinicogenomic ML problem (*Cancer Cell* 2025; *npj Digital Medicine* 2025).
- **CTD §2.6 generation is genuinely under-served** (no academic benchmark) — the differentiated piece — but **AutoIND** (arXiv:2509.09738, 2025) already drafts IND nonclinical summaries (eCTD 2.6.2/2.6.4/2.6.6, ~97% time reduction). "IND-ready without expert editing" is **unverifiable** and high-risk.

**Verdict:** design tasks **not novel**; §2.6 is the differentiator but **unbenchmarked / safety-critical**.

**Recommendation:** **RESCOPE** — start from **Panacea** or benchmark frontier models on CTBench+TrialPanorama before any fine-tune; **cut stratification biomarkers** to a dedicated model; concentrate on **retrieval-grounded, citation-faithful §2.6 generation with a self-built faithfulness eval**. Base model (if fine-tuning long §2.6): **Qwen3-235B-A22B-Instruct-2507** (256K ctx, Apache) or **DeepSeek-R1** (MIT, reasoning) — not Llama 3.1 70B.

### Layer 4 — Workflow Orchestration LLM (the real moat)
**Proposed:** fine-tune **Llama 3.1 70B** on GEO-mined traces + self-generated traces + synthetic cross-domain chains.

**2026 SOTA / adversarial finding:**
- Orchestration *capability* is now crowded: **BioMaster** (18 omics modalities, 102 tools, dual-RAG parameterization), **BioMedAgent** (*Nat BME* 2026, "chains tools into executable workflows," 77%), **FlowAgent**, and open-LLM-orchestration studies (bioRxiv 2026.05.13.724985 — free open models hit frontier accuracy executing pipelines). Prose→param extraction is done by **BioWorkflow** (*Brief Bioinform* 2025).
- **BUT** every competitor is *prompt/RAG over a frontier base*; **none is a weights-level fine-tune on real workflow execution traces.** That trace corpus + the **cross-domain synthesis chain** (still the one strongly-defensible moat claim) is the genuine, hard-to-replicate asset — and it directly attacks the failure mode BioAgent Bench (arXiv:2601.21800) surfaced (agents build correct pipelines but fail step-level under perturbation).
- **Threat:** generic pipeline orchestration (RNA-seq, variant calling) is being commoditized by open models — the fine-tune must earn its keep on the **long tail + robustness + cross-domain**, not common pipelines.

**Verdict:** the **training-data recipe is the moat, not the capability list**. Genuinely novel and defensible.

**Recommendation:** **BUILD FIRST.** Base model: **Qwen3-32B (dense, Apache-2.0)** — top-tier open function-calling (BFCL), clean license, best LoRA/QLoRA support, lower serving cost than 70B; escalate to **GLM-4.5-Air (MIT)** only if 32B routing accuracy is insufficient after fine-tune. **Do not build on a bio-specialized base** (GOEDEL-PROVER-V2 saw tool-use collapse 89.4%→~0% after domain SFT). Use LoRA to limit forgetting.

---

## 2. Base-model recommendation summary

| Layer | Proposed (2024-era) | 2026 recommendation | License | Why change |
|---|---|---|---|---|
| L1 representation | Geneformer v2 | **Geneformer V2** (rep/stratification only) | Apache-2.0 | keep — but not for perturbation |
| L1 perturbation | (Geneformer fine-tune) | **STATE-style / GEARS / CPA** on CD4⁺ T Perturb-seq | STATE non-comm ⚠ | Geneformer fails vs linear baselines |
| L2 target-ID | STRING v12 GNN | **Open Targets L2G/Gentropy** backbone + (PINNACLE / KGWAS) | open | static GNN behind SOTA; eQTL-alone n.s. |
| L3 trial design | Llama 3.1 70B | **Panacea** start; **Qwen3-235B-2507** / DeepSeek-R1 for §2.6 | Apache / MIT | design already solved; base stale |
| L4 orchestration | Llama 3.1 70B | **Qwen3-32B** (primary) / GLM-4.5-Air | Apache-2.0 / MIT | Llama not in BFCL top tier; license friction |

**Cross-cutting:** prefer **Apache/MIT** (Qwen3, GLM, DeepSeek) over Llama Community licensing for a commercial product (no 700M-MAU clause, no "no-competitor-training"); prefer **strong general base + LoRA** over bio-specialized bases for anything tool-use-shaped; MoE (235B/355B) gives frontier quality but is materially harder/pricier to fine-tune (bf16 LoRA, no clean 4-bit) — dense **Qwen3-32B** is the pragmatic default.

---

## 3. The moat, reframed (from the adversarial verification)

Of the plan's 5 "categorically unavailable" claims:
- **#3 cross-domain GWAS→scRNA→ADMET→PBPK synthesis — strongly defensible** (no published equivalent).
- **#1 workflow orchestration & #4 autonomous QC** — **partially eroded** (BioMaster/BioMedAgent; NEXUS does closed-loop QC-judge-with-remediation). BioMate's edge is *scale* + *regulatory/ADMET application*, not the capability.
- **#2 prose→param (BioWorkflow) & #5 IND generation (AutoIND)** — **contradicted as novelty**; defensible only as integration/engineering.

**Reframe external moat language** away from "no one does X" toward the **execution-trace flywheel** (real runs → traces → tuning → better runs) and the **end-to-end omics→ADMET→PBPK→IND integration**. Flag as unverifiable in any external claim: the "2,455-workflow" count, "IND-ready" without expert editing, and the unbenchmarked *quality* of the cross-domain synthesis.

---

## 4. Go-forward: what to start ASAP (priority order)

1. **Layer 4 orchestration on Qwen3-32B + the trace flywheel — start now.** It's the real moat, and the 2026-07 validation sessions already produced real cross-domain traces to seed it. Add BioMate self-generated traces (Strategy B, ~$1–5K compute) + GEO-mined traces. Differentiate on long-tail/robustness. **Gate:** routing accuracy vs frontier-zero-shot on held-out intents.
2. **Layer 1 patient stratification (Geneformer V2) — second.** Firm ground; autoimmune atlases (AMP RA/SLE, SLECA) are the differentiator. Keep perturbation as a separate, baseline-gated STATE-style effort.
3. **Layer 2 — re-plan to consume L2G** rather than build a STRING-GNN. Cheapest correction; biggest SOTA gap closed.
4. **Layer 3 — rescope to §2.6 faithfulness** (build the eval first); benchmark Panacea before any fine-tune.

**Mandatory baseline gates (non-negotiable):** perturbation → beat additive/mean/ridge (Ahlmann-Eltze 2025); target-ID → beat nearest-gene + L2G on approval labels; trial design → beat CTBench/Panacea; orchestration → beat open-model zero-shot on the long tail.

---

## 5. Consolidated citations

**Single-cell FM / virtual cell:** Geneformer — Theodoris et al. *Nature* 618 (2023) + V2 model card (HF ctheodoris/Geneformer, Dec 2024). scGPT — Cui et al. *Nat Methods* 21 (2024). scFoundation — Hao et al. *Nat Methods* (2024). UCE — Rosen et al. *Nature* 2026. Nicheformer — Schaar et al. *Nat Methods* 2025. scPRINT — Kalfon et al. *Nat Commun* 16:3607 (2025). CellFM — Zeng et al. *Nat Commun* (2025). TranscriptFormer — CZI bioRxiv 2025.04.25.650731. AIDO.Cell — GenBio (2024/25). STATE — Arc bioRxiv 2025.06.26.661135. GEARS — Roohani et al. *Nat Biotech* 41 (2023). CPA — Lotfollahi et al. *Mol Syst Biol* 19 (2023). **Ahlmann-Eltze et al. *Nature Methods* 22:1657 (2025)** [central negative result]. Kedzierska et al. *Genome Biology* (2025). Bendidi et al. arXiv:2410.13956. Boiarsky et al. bioRxiv 2023.10.19.563100.
**Datasets:** CD4⁺ T Perturb-seq — bioRxiv 2025.12.23.696273. Tahoe-100M — HF tahoebio/Tahoe-100M (2025). Virtual Cell Challenge — *Cell* 2025 S0092-8674(25)00675-0. scBaseCount — Arc bioRxiv 2025.02.27.640494. CELLxGENE Census — *NAR* 53:D886 (2025). AMP RA/SLE — Zhang et al. *Nature* 2023. SLECA — bioRxiv 2026.02.11.705246.
**Base LLMs:** Llama 3.3 70B (HF, Dec 2024); Llama 4 (Meta, Apr 2025); Qwen3 (qwenlm.github.io/blog/qwen3, Apr 2025) + Qwen3-235B-2507 (HF, Jul 2025); DeepSeek-V3 (arXiv:2412.19437) / R1 (Jan 2025); Mistral Small 3/3.1 (Jan/Mar 2025); Gemma 3 (Mar 2025); GLM-4.5/4.6 (Zhipu, Jul/Sep 2025); TxGemma (arXiv:2504.06196); MedGemma (May 2025); BFCL v3/v4 (Gorilla leaderboard); GOEDEL-PROVER-V2 tool-use collapse (arXiv:2604.08388); PEFT/forgetting (arXiv:2501.13669).
**Orchestration landscape:** Biomni (bioRxiv 2025.05.30.656746); STELLA (arXiv:2507.02004); BioMedAgent (*Nat BME* s41551-026-01634-6, 2026); BioMaster (bioRxiv 2025.01.23.634608); NEXUS (arXiv:2605.09366, 2026); CRISPR-GPT (arXiv:2404.18021); BioWorkflow (*Brief Bioinform* bbaf571, 2025); FlowAgent (bioRxiv 2025.03.06.641728); AutoIND (arXiv:2509.09738, 2025); BioAgent Bench (arXiv:2601.21800, 2026); open-LLM lab orchestration (bioRxiv 2026.05.13.724985); From Prompt to Pipeline (arXiv:2507.20122).
**Target-ID / trial design:** L2G — Mountjoy et al. *Nat Genet* (2021) + Gentropy docs; Open Targets 2025 platform — Buniello et al. *NAR* 53:D1467. PoPS — Weeks et al. *Nat Genet* (2023). cS2G — Gazal et al. *Nat Genet* (2022). PINNACLE — Li et al. *Nat Methods* (2024). KGWAS — snap-stanford medRxiv 2024. GWAS→approval benchmark — medRxiv 2025.09.23.25336370 ⚠ + arXiv:2606.14823 (2026). TrialGPT — Jin et al. *Nat Commun* (2024). Panacea — arXiv:2407.11007 (2024). AutoTrial — EMNLP 2023. CTBench — arXiv:2406.17888 (2024). TOP/TrialDura — arXiv:2406.10292 / 2404.13235.

**Flagged unverifiable:** several 2026-dated model releases (Gemma 4, GLM-5, MedGemma 1.5, Mistral Large 3, DeepSeek-V3.2) are secondary-sourced; the GWAS→approval OR numbers are from a gated preprint; NeurIPS-2023 perturbation-competition baseline ranking; STATE parameter count; code/weight licenses for scFoundation/Nicheformer/CellFM. Verify before external use.
