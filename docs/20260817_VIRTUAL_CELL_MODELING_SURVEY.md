# The State of the Art in Virtual Cell Modeling: A Verified-Citation Survey

*Survey date: 2026-08-17 · Every citation verified by fetching the source (Crossref / PubMed / publisher). DOIs, PMIDs, and arXiv IDs are given where they resolve. Anything not machine-verifiable is marked **UNVERIFIED**. No DOIs are fabricated.*

## Introduction

A "virtual cell" is a computational model that predicts a cell's state and its response to interventions — genetic perturbations, drugs, or environmental changes — without running the wet-lab experiment. The field spans two historically separate lineages that are now converging: **mechanistic simulation** (ODE/SBML kinetics, flux-balance metabolism, agent-based tissue models, and the whole-cell simulations pioneered by Karr et al.), and **data-driven machine learning** (single-cell foundation models pretrained on tens to hundreds of millions of cells, and perturbation-response predictors). A 2024 *Cell* roadmap by Bunne, Roohani, Leskovec, Quake, Regev and 30+ others crystallized this into the "AI Virtual Cell" (AIVC) vision. Crucially, the most important recent development is not a new model but a **credibility correction**: multiple 2025 benchmarks (Kedzierska et al.; Ahlmann-Eltze et al.) show that today's large foundation models, used zero-shot or for perturbation prediction, do **not yet reliably beat simple linear or mean baselines** — and the Arc Institute's Virtual Cell Challenge was created in part to force honest, held-out evaluation. This survey organizes the field by approach family, giving mechanism, key tools, evidence, strengths, limits, and verified citations for each.

---

## Family 1 — Single-Cell Foundation Models (SCFMs)

**What it is.** Transformer models pretrained self-supervised on massive unlabeled single-cell transcriptomes, producing a general-purpose "cell embedding" that can be fine-tuned or used zero-shot for downstream tasks (cell-type annotation, batch integration, perturbation, gene-network inference).

**How it models/predicts (mechanism).** A cell (~20,000 gene counts) is tokenized and fed to a transformer with a masked-prediction pretraining objective, but the tokenization differs by model:
- **scGPT** (Cui et al. 2024) — value-binning tokens; a generative masked-attention objective; ~33M cells. The reference "GPT-style" SCFM. *Nat Methods* 2024;21(8):1470–1480. DOI **10.1038/s41592-024-02201-0**.
- **Geneformer** (Theodoris et al. 2023) — **rank-value encoding** (genes ordered by expression rank, no absolute values); pretrained on ~30M cells ("Genecorpus-30M"). Pitch: *transfer learning for network biology*. *Nature* 2023;618:616–624. DOI **10.1038/s41586-023-06139-9**.
- **scFoundation / xTrimoGene** (Hao et al. 2024) — **continuous value embedding** (no lossy binning), an **asymmetric encoder–decoder** processing only non-zero genes, and **Read-Depth-Aware (RDA)** pretraining; ~100M params, >50M human cells, 19,264 genes. *Nat Methods* 2024;21(8):1481–1491. DOI **10.1038/s41592-024-02305-7**. (The backbone BioMap adapted to win VCC 2025.)
- **scBERT** (Yang et al. 2022) — early BERT-style SCFM for cell-type annotation. *Nat Mach Intell* 2022;4:852–866. DOI **10.1038/s42256-022-00534-z**.
- **UCE (Universal Cell Embeddings)** (Rosen, Roohani et al. 2023) — 33-layer, ~650M-param model on >36M cells across 300+ CELLxGENE datasets, using **ESM2 protein embeddings** so genes from any species map into one universal space. bioRxiv 10.1101/2023.11.28.568918.
- **TranscriptFormer** (CZI, 2025) — cross-species generative SCFM (~112M cells, 12 species); Apache-2.0 licensed. bioRxiv 10.1101/2025.04.25.650731 (**UNVERIFIED DOI** — confirm on click).

**Evidence / strengths.** Strong when **fine-tuned** on a labeled downstream task; competitive cell-type annotation, batch integration, useful embeddings; enable transfer to data-scarce settings. UCE/TranscriptFormer add cross-species generalization.

**Limitations (load-bearing).** In **zero-shot** use, Kedzierska et al. 2025 (*Genome Biology* 26:101; DOI **10.1186/s13059-025-03574-x**; PMID 40251685) showed scGPT and Geneformer perform **inconsistently and often worse** than plain highly-variable-gene selection, scVI, or Harmony for cell-type clustering across five datasets. Recurring lesson: single-cell data is dominated by technical noise (dropout, batch), the biological signal is near-linear, and huge models overfit that noise — so **curation + statistical structure often beats raw scale**.

---

## Family 2 — Perturbation-Response Prediction

**What it is.** Models that predict the transcriptome-wide response to a specific perturbation (silence gene X, apply drug Y at dose Z), including generalization to **unseen** single or combinatorial perturbations.

**Mechanism.**
- **scGen** (Lotfollahi et al. 2019) — VAE doing **latent-space vector arithmetic** (learn a "perturbation direction," add to unseen contexts). *Nat Methods* 2019;16:715–721. DOI **10.1038/s41592-019-0494-8**.
- **CPA (Compositional Perturbation Autoencoder)** (Lotfollahi et al. 2023) — **adversarially disentangles** basal state, perturbation, dose, covariates into composable latent factors → drug-combination and dose-response prediction. *Mol Syst Biol* 2023;19:e11517. DOI **10.15252/msb.202211517**.
- **chemCPA** (Hetzel et al. 2022) — extends CPA to **unseen drugs** via molecular-structure encoding. NeurIPS 2022; arXiv:2204.13545.
- **GEARS** (Roohani et al.) — **GNN over a GO / co-expression knowledge graph**, predicting effects of **multigene (combinatorial)** perturbations including genes never perturbed alone. *Nat Biotechnol* 2024;42:927–935. DOI **10.1038/s41587-023-01905-6**.
- **STATE** (Arc Institute; Adduri et al. 2025) — **set-attention state-transition model** on >100M perturbed cells across 70 contexts + a cell-embedding model on 167M cells; reports **>50% improvement** in perturbation-effect discrimination. bioRxiv 10.1101/2025.06.26.661135 (**non-commercial license**).
- **BioMap xTrimoSCPerturb** — the **VCC 2025 grand-prize winner**; fused the scFoundation backbone with explicit statistical baseline features and a metric-aligned (PDS+DES+MAE) loss. Documented via the Arc VCC 2025 wrap-up + BioMap's post; **no peer-reviewed methods paper verified yet — internal recipe details are vendor-claimed / UNVERIFIED**.

**Key datasets & benchmark.** Genome-scale Perturb-seq — **Replogle et al. 2022**, *Cell* 185:2559–2575.e28, DOI **10.1016/j.cell.2022.05.013** — is the foundational training/transfer resource (K562/RPE1, ~8K genes). Norman et al. 2019 (combinatorial CRISPRa, GSE133344) is the standard combinatorial testbed. The **Arc Virtual Cell Challenge** (2025; H1-hESC, 300 CRISPRi perturbations split 150/50/100) is the flagship held-out evaluation, scored on PDS (perturbation-discrimination), DES (differential-expression), and MAE.

**Strengths.** GEARS and STATE genuinely push combinatorial and cross-context generalization.

**Limitations.** See Family 5 — for **unseen** and **combinatorial** perturbations, deep predictors have **not yet beaten additive / mean baselines** in controlled benchmarks. The winning VCC recipes were **hybrids** (statistics + curation + selective DL), not pure end-to-end nets.

---

## Family 3 — The "AI Virtual Cell" (AIVC) Vision

**What it is.** A field-defining roadmap: **Bunne, Roohani, Rosen, … Regev, Lundberg, Leskovec, Quake et al. 2024**, "How to build the virtual cell with artificial intelligence: Priorities and opportunities," *Cell* 2024;187:7045–7063, DOI **10.1016/j.cell.2024.11.015**.

**How it frames the problem.** Proposes the AIVC as a multi-scale, multi-modal system of "universal representations" of molecules, cells, and tissues, learned from large atlases, that can be **queried and simulated** — predict unmeasured states and responses (virtual instruments / virtual perturbations) and be validated against real experiments.

**Operationalization.** Arc Institute turned the vision into a measurable target with the **Virtual Cell Challenge** — "Virtual Cell Challenge: Toward a Turing test for the virtual cell," *Cell*, June 26, 2025, PII **S0092-8674(25)00675-0** (**numeric DOI UNVERIFIED** — cited by verified publisher URL). Supporting infrastructure: the **Arc Virtual Cell Atlas** and **Tahoe-100M** (100M cells, ~1,100 drugs × 50 cancer lines), CZI's **CELLxGENE Census** and **cz-benchmarks/cell-eval** harness.

**Strengths.** Aligns a fragmented field on shared objectives, metrics, and open data; catalyzed the honest-evaluation movement.

**Limitations.** Aspirational — no current system is a true virtual cell; the gap between vision and demonstrated accuracy (Family 5) is large.

---

## Family 4 — Whole-Cell & Mechanistic Models

**What it is.** Bottom-up simulations grounded in molecular mechanism: ODE/SBML kinetics, flux-balance metabolism (FBA), agent-based/spatial tissue models, integrative whole-cell models.

**Mechanism.**
- **Whole-cell model** — **Karr et al. 2012**, "A Whole-Cell Computational Model Predicts Phenotype from Genotype," *Cell* 150:389–401, DOI **10.1016/j.cell.2012.05.044**. Simulates every characterized gene function of *Mycoplasma genitalium* via ~28 integrated submodels, predicting phenotype from genotype. The landmark proof-of-concept.
- **Flux-balance analysis (FBA)** — genome-scale metabolic models (Recon3D, Human-GEM) solved by linear programming under stoichiometric/steady-state constraints; tool COBRApy. (Orth et al. 2010, *Nat Biotechnol* 28:245–248.)
- **ODE/SBML kinetic simulation** — mass-action / Michaelis-Menten networks (Tellurium, AMICI, COPASI); used for signaling and cardiac safety (CiPA O'Hara-Rudy action-potential model).
- **Agent-based / spatial** — PhysiCell, Chaste, CompuCell3D, Morpheus, FLAME-GPU2 for tumor microenvironment, morphogenesis, drug penetration.
- **Hybrid mechanistic + ML** — SBML-to-JAX, adjoint-sensitivity fitting (AMICI + pyPESTO), composable multi-scale frameworks (Vivarium).

**Strengths.** Interpretable, causal, extrapolate to unseen conditions in principle, and are the **regulatorily-accepted** end of the spectrum (PBPK, CiPA/QSP appear in real FDA/EMA submissions).

**Limitations.** Require extensive prior knowledge and parameterization; do not scale to whole human-cell transcriptomic response; the Karr-style approach remains confined to minimal organisms and is computationally heavy.

---

## Family 5 — Honest Negative Results, Benchmarks & the Evaluation Debate

**What it is.** Rigorous benchmark studies whose central finding is that the hype has outrun the evidence — the field's most important recent contribution.

- **Ahlmann-Eltze, Huber & Anders 2025** — "Deep-learning-based gene perturbation effect prediction does not yet outperform simple linear baselines," *Nature Methods* 22:1657–1661, DOI **10.1038/s41592-025-02772-6**, PMID 40759747. For **combinatorial** perturbations DL did **not beat a simple additive model**; for **unseen** genes DL did **not beat predicting the training mean**.
- **Kedzierska, Crawford, Amini & Lu 2025** — "Zero-shot evaluation reveals limitations of single-cell foundation models," *Genome Biology* 26:101, DOI **10.1186/s13059-025-03574-x**, PMID 40251685.
- **PerturBench** (Wu et al. 2024) — arXiv:2408.10609 — ~27 perturbation methods across ~29 datasets with rank-based specificity metrics; strong non-DL baselines.
- **The VCC as a benchmark.** The Arc wrap-up reports a trivial **cell-mean baseline beat most deep models on MAE**, and that "pure end-to-end neural networks have yet to outperform hybrid models" — which is why the challenge weights **PDS** (perturbation-specificity) as the deciding metric (a constant prediction scores chance = 0.5).

**The debate.** Cross-paper score comparisons are usually invalid (different tasks/data/metrics). The defensible recipe the community is converging on: **your own task + your own metric + a permuted null + a simple baseline + an oracle/ceiling**, all on the same held-out split.

---

## What's Winning / The Honest State

- **Mechanistic models win where they're accepted:** PBPK, CiPA/QSP, and FBA are the only virtual-cell approaches with real regulatory standing today.
- **For perturbation-response, hybrids win — not pure deep learning.** All three VCC 2025 winners (BioMap xTrimoSCPerturb; Altos flow-matching; Team Outlier's TransPert) beat brute-force scale by combining **curated data + explicit statistical priors + metric-aligned loss**. TransPert (3rd overall, #1 on PDS) used **no neural net at all**.
- **Foundation models are useful but oversold.** Fine-tuned they help; zero-shot they frequently lose to HVG/scVI (Kedzierska 2025). For unseen/combinatorial perturbation they don't yet beat linear baselines (Ahlmann-Eltze 2025).
- **The honest gap:** no system today is a true "virtual cell." STATE and the AIVC roadmap point the direction; the near-term frontier is **cross-context / cross-cell-type transfer** with rigorous held-out evaluation, where statistics-first hybrids currently lead.

---

## BioMate Positioning

*(Accurate, from BioMate's internal docs; several items are plans/experiments, not shipped capabilities.)*

- **Mechanistic virtual-cell infrastructure (built).** Four Phase-1 workflows run on BioMate's AWS-Batch engine: CiPA cardiac-safety ODE (hERG mechanistic confirmation), ODE signaling simulation, metabolic-flux FBA, and LINCS-L1000 transcriptomic MoA — integrated with existing ADMET/PBPK/RNA-seq workflows.
- **Perturbation-prediction infrastructure (staged).** GEARS, CPA, scGen, scFoundation/TranscriptFormer catalogued with licenses/GPU sizing/Docker recipes; several are **planned Phase-2 GPU workflows**.
- **VCC 2026 participation (active).** BioMate registered a team for the Arc Virtual Cell Challenge (starts Aug 20, 2026), with a validated scoring harness (cell-mean / additive / oracle-NN baselines) and a statistics-first plan: pseudobulk per perturbation, test-time features (baseline expression, MSigDB-C7 pathway membership, Open Targets genetics priors), **similarity-weighted cross-line transfer**, and **global PDS scale-calibration** — mirroring the TransPert recipe, adding DL only if it beats the statistical floor.
- **Cross-line transfer + PDS calibration (validated at baseline level).** BioMate independently reproduced the key VCC scoring behavior (constant predictions → chance PDS 0.5; nearest-neighbor borrowing → PDS ≈ 0.81 calibrated), confirming that perturbation-*specific* prediction and distance calibration are the high-leverage levers.
- **Honest scope.** BioMate does **not** claim a trained perturbation model beating SOTA, nor a whole-cell simulator; its differentiators are the **execution engine** (mechanistic + ML workflows on managed AWS Batch), a **rigorous baseline/eval harness**, and a **statistics-first VCC strategy** aligned with what actually won in 2025.

---

## References (verified via Crossref/PubMed unless flagged)

1. Cui H, et al. **scGPT**. *Nat Methods* 2024;21(8):1470–1480. DOI 10.1038/s41592-024-02201-0.
2. Theodoris CV, et al. **Geneformer**. *Nature* 2023;618:616–624. DOI 10.1038/s41586-023-06139-9.
3. Hao M, et al. **scFoundation/xTrimoGene**. *Nat Methods* 2024;21(8):1481–1491. DOI 10.1038/s41592-024-02305-7.
4. Yang F, et al. **scBERT**. *Nat Mach Intell* 2022;4:852–866. DOI 10.1038/s42256-022-00534-z.
5. Rosen Y, Roohani Y, et al. **UCE**. bioRxiv 2023. DOI 10.1101/2023.11.28.568918.
6. CZI. **TranscriptFormer**. bioRxiv 2025. DOI 10.1101/2025.04.25.650731. **[UNVERIFIED]**
7. Lotfollahi M, et al. **scGen**. *Nat Methods* 2019;16:715–721. DOI 10.1038/s41592-019-0494-8.
8. Lotfollahi M, et al. **CPA**. *Mol Syst Biol* 2023;19:e11517. DOI 10.15252/msb.202211517.
9. Hetzel L, et al. **chemCPA**. NeurIPS 2022. arXiv:2204.13545.
10. Roohani Y, et al. **GEARS**. *Nat Biotechnol* 2024;42:927–935. DOI 10.1038/s41587-023-01905-6.
11. Replogle JM, et al. Genome-scale **Perturb-seq**. *Cell* 2022;185:2559–2575.e28. DOI 10.1016/j.cell.2022.05.013.
12. Adduri AK, et al. **State** (Arc). bioRxiv 2025. DOI 10.1101/2025.06.26.661135. [Non-commercial.]
13. Bunne C, Roohani Y, … Quake SR. How to build the virtual cell with AI. *Cell* 2024;187:7045–7063. DOI 10.1016/j.cell.2024.11.015.
14. Arc Institute. Virtual Cell Challenge: Toward a Turing test for the virtual cell. *Cell*, Jun 26, 2025. https://www.cell.com/cell/fulltext/S0092-8674(25)00675-0 **[numeric DOI UNVERIFIED]**
15. Karr JR, et al. A Whole-Cell Computational Model Predicts Phenotype from Genotype. *Cell* 2012;150:389–401. DOI 10.1016/j.cell.2012.05.044.
16. Ahlmann-Eltze C, Huber W, Anders S. Deep-learning perturbation prediction does not yet outperform linear baselines. *Nat Methods* 2025;22:1657–1661. DOI 10.1038/s41592-025-02772-6. PMID 40759747.
17. Kedzierska KZ, et al. Zero-shot evaluation reveals limitations of single-cell foundation models. *Genome Biology* 2025;26:101. DOI 10.1186/s13059-025-03574-x. PMID 40251685.
18. Wu Y, et al. **PerturBench**. arXiv:2408.10609 (2024).
19. Lopez R, et al. **scVI**. *Nat Methods* 2018;15:1053–1058. DOI 10.1038/s41592-018-0229-2.
20. Lotfollahi M, et al. **scArches**. *Nat Biotechnol* 2022;40:121–130. DOI 10.1038/s41587-021-01001-7.

*Supporting resources: Arc VCC 2025 wrap-up (arcinstitute.org); Tahoe-100M / Virtual Cell Atlas; CELLxGENE Census; scPerturb (Peidli et al. 2024) Zenodo 10.5281/zenodo.13350497.*

*Companion showcase: `blog-virtual-cell.html`. Related BioMate surveys: target identification, patient stratification, multi-omics integration, protein conformation.*
