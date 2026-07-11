# BioMate Strategic Position: Autoimmune Drug Discovery
## Evidence-Based Business Case + Internal LLM Training Roadmap

**Date:** 2026-07-01  
**Status:** Strategy draft for internal review

---

## Executive Summary

The global autoimmune drug market is **USD 80–124 billion in 2025**, growing at 5–10% CAGR across indications. Clinical attrition is catastrophic: **~70% of programs fail at the Phase 2→3 transition** (JACI 2017), with patient stratification errors the leading cause. A failed Phase 3 trial costs **$800M–$2.4B** per program (Tufts CSDD). The single most actionable intervention — multi-omic patient stratification at enrollment — remains computationally inaccessible to the wet lab immunologists who run these programs.

BioMate's position: **the only platform that takes a wet lab immunologist from a clinical observation to an IND-ready computational package**, chaining GWAS → scRNA-seq → epigenomics → ADMET → PBPK → clinical trial design in a single AI-orchestrated session. No competitor does this end-to-end today. Building an internal LLM trained on autoimmune-specific tasks creates a compounding data moat that pure-hypothesis generators (FutureHouse) and infrastructure vendors (Seven Bridges, DNAnexus) cannot replicate.

---

## Part 1: Market Landscape — Validated Numbers

### 1.1 Market Size by Indication (2024–2025)

| Indication | Market Size | CAGR | Key Products |
|---|---|---|---|
| **Rheumatoid Arthritis** | USD 25.8–33.7B | 5.56% | Humira, Enbrel, Rinvoq, Xeljanz; biologics = 88.5% share |
| **Multiple Sclerosis** | USD 27.4B | 6.1% | Ocrevus, Tysabri, Mavenclad; RRMS = 85% of market |
| **IBD** (Crohn's + UC) | USD 22.9–29.6B | 3.7–4.0% | Stelara, Entyvio, Skyrizi; Crohn's = 60.4% of segment |
| **Psoriasis** | USD 21.1B | 10.9% | Tremfya, Skyrizi, Taltz; IL-23 inhibitors = 27.5% share |
| **SLE/Lupus** | USD 2.4B (7MM) | 7.3% | Saphnelo ~$340M 2024 sales; forecast $5.9B by 2034 |
| **Total autoimmune therapeutics** | USD 80–124B | 5–7.4% | Projected USD 223–249B by 2034 |

**Sources:** Grand View Research (RA, MS, Psoriasis markets); Fortune Business Insights (IBD); GlobalData / GlobeNewswire (SLE); iHealthcareAnalyst (total market); SNS Insider (CAGR). Interleukin inhibitors as a drug class reached USD 32.5B with 17.3% CAGR — the fastest-growing mechanistic category.

### 1.2 Clinical Attrition — The Core Problem BioMate Solves

**Primary failure statistics (all validated from peer-reviewed sources):**

- **Phase 2→3 success rate in autoimmune/inflammation: 45.7%** — 54.3% of autoimmune programs that complete Phase 2 fail to advance. Phase 3→approval success: 63.7%. Overall Phase 1→approval: **15.1%** (vs. 13.8% industry-wide; oncology is just 3.4%).  
  *Source: Wong CH, Siah KW, Lo AW. "Estimation of clinical trial success rates and related parameters." Biostatistics 2019;20(2):273–286. DOI: 10.1093/biostatistics/kxx069. Dataset: 185,994 unique trials across 21,143 compounds, 2000–2015, Citeline/Informa Pharma Intelligence.*

- **Biomarker-stratified trials nearly double overall success: 10.3% vs 5.5%** (Phase 1→approval). At Phase 2→3 specifically: 38.6% vs 26.8% — a 44% improvement in transition rate.  
  *Source: Same Wong et al. 2019.*

- **Qualitative failure modes in immunologic diseases** — the most detailed published analysis of *why* programs fail identifies absence of companion biomarkers ("trials that use biomarkers in patient-selection have higher overall success probabilities"), inadequate Phase 2a proof-of-concept design, and biological heterogeneity of autoimmune diseases as the primary causes.  
  *Source: "Phase 2 to phase 3 clinical trial transitions: Reasons for success and failure in immunologic diseases," J Allergy Clin Immunol 2017;139(6):1868–1875. PMID: 28506849. [Note: qualitative framework; quantitative rates superseded by Wong et al. 2019.]*

- **30–40% of RA patients are primary non-responders** to TNFi biologics — enrolled without stratification, they dilute trial signal and drive false-negative results  
  *Source: Multiple systematic reviews; PMC5433023*

- **Cost of a failed Phase 3 trial: $800M–$2.4B per program** (direct + embedded upstream R&D costs)  
  *Source: Tufts CSDD, Clinical Leader analysis*

- **Cost of a single day of trial delay: $600K–$8M** in foregone prescription revenue  
  *Source: Tufts CSDD Day of Delay White Paper (August 2024)*

**The documented mechanistic link — patient stratification → trial failure:**

The JACI 2017 analysis explicitly identifies "absence of companion biomarkers associated with the target's pathway" as the primary failure mode. Three documented clinical examples:

1. **Anifrolumab (SLE)**: Phase 2B MUSE (2016) succeeded; Phase 3 TULIP-1 failed. Post-hoc analysis confirmed that **IFN-high patients drove all clinical benefit** — the trial enrolled IFN-low patients without restriction, diluting the effect. The IFNGS biomarker was already known; stratification was not enforced. TULIP-2 restricted the analysis to IFNGS-high and succeeded. Post-hoc pooled data (Annals of Rheumatic Diseases): anifrolumab produced ~85–90% sustained IFNGS neutralization at 52 weeks, with response correlating with baseline IFN status.

2. **Anti-TNF in Sjögren's disease**: Multiple programs failed due to "inadequate patient stratification, trial endpoints that did not capture the full burden of systemic disease" — quoted directly from review literature.

3. **RA cost of non-response**: In a matched cohort of 7,797 RA patients, total all-cause medical costs were **$5,737 higher per patient per year** for TNFi non-responders versus responders (JMCP 2021). At trial scale (300–500 patients), enrolling 35% non-responders adds ~$8.6M in direct healthcare costs alone — before accounting for statistical power degradation.

---

## Part 2: Competitive Landscape — What Competitors Actually Deliver

### 2.1 FutureHouse

**What they claim:** AI scientist platform automating end-to-end scientific discovery. Agents: Crow (literature synthesis), Finch (bioinformatics — RNA-seq DE + enrichment), Phoenix (chemistry experiment planning).

**What they have delivered:**
- Robin agent identified **ripasudil** as a candidate for dry AMD — claimed as first end-to-end AI scientific discovery (no clinical translation yet)
- November 2025: Spun off **Edison Scientific** (for-profit), raised **$70M seed at $250M valuation**
- Finch handles RNA-seq differential expression + functional enrichment — single analytical tasks, not orchestrated multi-omic pipelines

**Actual gap vs. BioMate:** FutureHouse generates hypotheses and runs single-domain analyses. It does not chain GWAS → scRNA-seq → eQTL → ADMET → PBPK. It produces no IND-ready outputs. It has no QC auto-loop or real-time pipeline execution. It is a research intelligence tool, not a translational execution platform.

### 2.2 Recursion Pharmaceuticals (post-Exscientia merger, Nov 2024, $688M)

**What they claim:** Vertically integrated AI drug discovery using phenomic imaging (Recursion) + precision chemistry (Exscientia). "More than 10 clinical and preclinical programs."

**What they have actually delivered (2024–2025):**
- **REC-994** (cerebral cavernous malformation): Phase 2 completed, **no meaningful clinical benefit**, terminated
- **REC-2282** (NF2): Terminated after data accumulation did not justify continued investment
- Deprioritized 3 clinical + 1 preclinical program in Q1 2025 restructuring
- **Net loss: $644.8M in 2025** (up from $463.7M in 2024)
- In autoimmune: Sanofi collaboration — only at **discovery stage** (small-molecule lead nomination, $7M milestone)
- Active oncology programs remain (CDK7, RBM39, MALT1) — no clinical autoimmune

**Actual gap vs. BioMate:** Recursion has no approved AI-originated drug and no Phase 2 autoimmune clinical program. Its phenomics platform generates leads that still fail in the clinic. It is a closed, vertically integrated system — pharma cannot use Recursion's platform for their own programs.

### 2.3 Valo Health

**What they claim:** Opal Computational Platform + Logica (Opal + Charles River CRO services). Novo Nordisk collaboration: ~$190M near-term + $4.6B in milestones.

**What they have delivered in autoimmune:**
- March 2025: Charles River + Valo announced identification of an **advanceable candidate for lupus** using Logica — still **pre-IND, preclinical stage**
- No clinical autoimmune programs as of mid-2026

**Actual gap vs. BioMate:** Valo's Logica is the most analogous competitor — it chains computational analysis + CRO execution. But it is a closed service offering, not a self-service platform. Wet lab scientists cannot access it directly; they buy a CRO service. BioMate is self-service.

### 2.4 Schrödinger

**What they claim:** Physics-based FEP+ molecular simulation + ML for structure-based drug design. Licensed by major pharma.

**What they have actually delivered:**
- **Zasocitinib (TAK-279)**: TYK2 inhibitor originally designed by Schrödinger for Nimbus Therapeutics; Takeda acquired Nimbus for **$6.1B** (2023); now in **Phase 3 clinical trials for psoriasis and psoriatic arthritis** — Schrödinger's strongest proof point
- Novartis collaboration: **$150M upfront** (Q1 2025)
- Software revenue: $35.4M in Q2 2024 (+21% YoY)

**Actual gap vs. BioMate:** Schrödinger is single-domain (small molecule physics + structure). It does no genomics, transcriptomics, or clinical trial design. It requires expert computational chemists. It cannot help a wet lab immunologist understand which target to design a molecule against.

### 2.5 Seven Bridges / DNAnexus

**Seven Bridges:** Cloud bioinformatics platform — CWL/WDL/Nextflow workflow runner. Data management, cloud compute. Strong for WGS/RNA-seq at scale.

**DNAnexus:** Omics data management + variant calling. Regulatory-grade provenance (FDA 21 CFR Part 11, HIPAA). $600M valuation. Strong for clinical-grade genomics + biobank-scale analysis.

**Actual gap vs. BioMate:** Both are infrastructure plays. They execute workflows that bioinformaticians write for them. They have no AI that interprets biological results, chains cross-domain workflows, or generates IND-ready reports. The user is a bioinformatics engineer, not a scientist.

### 2.6 Summary Competitive Map

```
                          HIGH SCIENTIFIC DEPTH
                                   |
         FutureHouse               |              BioMate (target)
         (hypothesis gen)          |              (orchestrated execution,
                                   |              scientist-accessible)
         Insilico Medicine         |
         (generative chemistry)    |
                                   |
CLOSED ————————————————————————————|—————————————————————————— OPEN/ACCESSIBLE
(internal platform)                |
         Recursion                 |              Schrödinger
         (phenomics+chem)          |              (structure-based chem)
                                   |
         Valo Health               |              Seven Bridges
         (CRO+compute service)     |              DNAnexus
                                   |              (bioinformatics infra)
                          LOW SCIENTIFIC DEPTH
```

**BioMate's unclaimed territory:** High scientific depth + open/accessible to wet lab scientists + multi-domain orchestration.

---

## Part 3: Challenging Use Cases — BioMate Workflow Chains

### 3.1 Use Case 1: Multi-Omic Target Prioritization (GWAS → Functional Genomics → Novel Target)

**The problem:** A GWAS on 500K+ individuals identifies 50 candidate loci for RA or SLE. Which target to pursue? Standard practice: a team of bioinformaticians spends 6–12 months manually integrating data.

**Published evidence this works:** A 2025 multi-omics study (Functional & Integrative Genomics, PMC12009781) integrated GWAS + GEO RNA-seq + scRNA-seq data across RA, MS, and T1D and identified ROMO1 as a shared genetic factor. The RNASET2 study (PMC12907157, 2026) ran the full chain: GWAS → expression QTL → protein QTL → methylation QTL → bidirectional Mendelian randomization → functional validation, across two independent cohorts. A UK Biobank + FinnGen meta-analysis spanning **933,649 individuals** found a median of **46 additional variants per disease** versus traditional GWAS — requiring computational infrastructure to process.

**BioMate workflow chain:**
1. GWAS colocalization: coloc + SMR against DICE eQTL database (13 immune cell types) and GTEx whole blood
2. scRNA-seq cluster analysis (Seurat): assign candidate genes to pathogenic cell types (Th17, plasmablasts, synovial fibroblasts)
3. ATAC-seq chromatin accessibility: confirm locus is in open regulatory region in relevant cells (ENCODE + Roadmap Epigenomics reference)
4. Mendelian randomization: causal direction test (gene → disease)
5. Druggability scoring: overlay DrugBank + ChEMBL + OpenTargets for each candidate gene
6. **Output:** Ranked target scorecard with convergent genetic + expression + druggability evidence; ready for medicinal chemistry brief

**Why BioMate wins:** 5 workflow domains, one session, automated QC between steps. This currently requires a team with GWAS, eQTL, scRNA-seq, and cheminformatics expertise — a 6-month engagement at a CRO runs $500K–$2M.

---

### 3.2 Use Case 2: Biologic Responder Signature Development (RA Anti-TNF / JAK Inhibitor)

**The problem:** 30–40% of RA patients are primary non-responders to TNFi biologics. Predicting responders before treatment saves ~$20K per patient in failed treatment costs and prevents 6 months of disease progression.

**Published evidence this is solvable:** A 2025 study (PMC12109967) predicted anti-TNF monoclonal antibody response using mRNA quantitation of CD36 + 6 Nrf2-induced genes in fresh monocytes with **93.3% accuracy**. A 2022 machine learning multi-omics study (PMC8996791) showed transcriptomic-based ML classifies non-responders with high predictive utility. For JAK inhibitors (tofacitinib), a 2025 multi-omics study (PMC12884169) identified transcriptomic, proteomic, and metabolic biomarkers of heterogeneous therapeutic response. For SLE anifrolumab: the 21-gene IFNGS is now used in clinical practice; IFNGS-high patients show ~85–90% signature neutralization vs. IFN-low patients showing minimal benefit.

**BioMate workflow chain:**
1. RNA-seq differential expression (DESeq2 / edgeR): baseline biopsies / blood, responders vs. non-responders
2. Batch correction (ComBat-seq, limma removeBatchEffect): normalize across cohorts
3. PCA / UMAP QC: identify outliers; auto-loop QC gate flags batch separation > threshold
4. Gene signature extraction: penalized regression (glmnet LASSO) on DE gene set
5. GSEA / clusterProfiler pathway enrichment: biological interpretation of signature
6. Classifier development: random forest / glmnet on signature genes; cross-validation
7. Validation: apply classifier to independent GEO cohort
8. **Output:** Clinical companion diagnostic candidate — gene panel with sensitivity/specificity/AUC, biologically interpreted mechanism, ready for clinical diagnostic development brief

**BioMate auto-loop QC gate:** If PCA shows cohort separation driven by technical batch > biological signal, the gate fires and auto-remediates by applying ComBat-seq correction before proceeding. This is the exact failure mode that invalidates most published biomarker studies.

---

### 3.3 Use Case 3: Single-Cell Immune Landscape Mapping (IBD / MS / SLE)

**The problem:** In IBD or MS, what immune cell states drive pathology? Are they targetable? Understanding this requires single-cell resolution — bulk RNA-seq masks the relevant biology.

**Published evidence:** The 2023 Geneformer paper (Nature, PMID 37258680) pretrained on 29.9M single-cell transcriptomes and demonstrated transfer learning across disease contexts — cell type classification, network centrality scoring for drug target prediction. Published large-scale scRNA-seq atlases for IBD (gut epithelium + immune cells) and MS (CSF immune cells) are in CELLxGENE Census (120M+ standardized cells total). The Human Immunology Cell Atlas spans 360K cells across 16 tissues/12 donors with VDJ sequencing.

**BioMate workflow chain:**
1. Seurat: QC → normalization → dimensionality reduction → clustering → UMAP → cell type annotation (Azimuth reference atlas)
2. Differential cell composition: compare disease vs. healthy; auto-loop flags if a cell type proportion < 1% (insufficient power for DE)
3. Pseudobulk DE analysis (DESeq2 on clusters): identify genes upregulated in pathogenic cell states
4. Trajectory analysis (Monocle / Slingshot): T cell differentiation paths toward Th17/Tfh/exhaustion states
5. Cell-cell communication (CellChat / NicheNet): cytokine-receptor networks driving inflammation; identify the signaling hub most amenable to disruption
6. Cross-disease comparison: overlap pathogenic states with public atlases (IBD vs. MS vs. RA) to identify shared targets
7. **Output:** Annotated cell atlas with pathway report, trajectory diagram, top 5 signaling hubs ranked by druggability, cross-disease target overlap table

**Clinically translatable output example:** A Th17 hub with IL-23R as the central signaling node → directly actionable for existing IL-23 inhibitors (risankizumab, guselkumab) or a novel oral candidate program.

---

### 3.4 Use Case 4: Drug Repurposing via Transcriptomic Connectivity (CMAP/L1000)

**The problem:** Can any approved drug reverse the pathogenic transcriptomic signature in lupus nephritis or MS? First-in-class drug programs take 10–15 years; repurposing a clinically validated compound de-risks dramatically.

**Published evidence:** The L1000 dataset contains ~1M+ profiles across ~20,000 compounds and ~50 human cell lines. A Royal Society Open Science study (2018; PMC6281908) demonstrated systematic polypharmacology via L1000-based CMap mining. Published application in SLE and UC: GEO-derived disease signatures queried against CMap to identify anti-inflammatory compounds with matching transcriptional programs.

**Important caveat (required for intellectual honesty):** A Briefings in Bioinformatics analysis (2021; PMC8597919) showed that when querying CMap 2 with CMap 1-derived signatures, success rate was only **17%** — different scoring methods (XCos, WTCS, GSEA-based) yield substantially different rankings. BioMate's pipeline addresses this by running multiple scoring methods in parallel and requiring concordance across ≥2 methods before reporting a candidate. CMap/L1000 is a hypothesis generator, not a definitive prediction engine.

**BioMate workflow chain:**
1. Disease signature generation (DESeq2): kidney biopsy RNA-seq, SLE nephritis vs. healthy kidney
2. Signature quality gate: require ≥200 up-regulated and ≥200 down-regulated DEGs at FDR < 0.05; auto-loop flags if signature too small
3. L1000 connectivity query: WTCS + XCos + GSEA; report candidates concordant across all three scoring methods
4. ADMET filtering: hERG safety screen + hepatotoxicity + CYP3A4 inhibition on top 20 candidates
5. PBPK simulation: renal exposure at standard therapeutic dose for top 5 ADMET-passing candidates
6. Mechanism alignment check: cross-reference candidate MOA vs. known SLE pathogenic pathways (IFN, complement, B cell activation)
7. **Output:** Ranked repurposing candidate report — connectivity score, ADMET flags, PK rationale, MOA plausibility assessment; format matches IND pre-meeting briefing structure

---

### 3.5 Use Case 5: Neoantigen / Autoantigen Discovery for Tolerization Therapy

**The problem:** In T1D (islet-reactive T cells) or MS (myelin-reactive T cells), which self-peptides drive pathogenic T cell responses? Identifying the exact autoantigen peptides enables tolerization vaccines or regulatory T cell therapies.

**Published evidence:** HLA typing from WGS (OptiType) achieves >99% accuracy for HLA-A, B, C, DRB1 4-digit typing. NetMHCpan-4.1 predicts peptide-MHC binding with AUC 0.87–0.93 across HLA alleles (validated in CAMEL benchmark). Single-cell TCR-seq (10x Genomics 5' + VDJ) identifies expanded T cell clones. The published T1D antigen literature identifies GAD65, insulin B chain, IA-2, and ZnT8 as the canonical target antigens — but patient-specific HLA alleles determine which peptides are presented.

**BioMate workflow chain:**
1. HLA typing (OptiType): from patient WGS BAM file → 4-digit HLA type for A, B, C, DRB1, DQB1
2. Islet cell proteomics (MaxQuant → protein list): expressed proteins in relevant tissue
3. Peptide-MHC binding prediction (NetMHCpan-4.1): all 8–11mer peptides from islet proteome against patient's HLA alleles; rank by predicted binding affinity (IC50 < 50 nM = strong binder)
4. Cross-reference with TCR-seq: identify expanded clones from PBMCs; match TCR specificity to peptide-MHC predictions using published TCR-pMHC databases (VDJdb, McPAS-TCR)
5. Immunogenicity score: integrate HLA binding affinity + proteasomal cleavage (NetChop) + TAP transport efficiency (TAPPred)
6. **Output:** Top 10 candidate autoantigen peptides ranked by composite immunogenicity score; patient's HLA type; tolerization construct design parameters (peptide sequence, length, MHC allele); compatible with APL (altered peptide ligand) or antigen-coupled PBMC tolerization designs

---

### 3.6 Use Case 6: IND Package Generation — Full Translational Chain

**The problem:** A pharma team has a novel IL-6 receptor modulator for RA. They need a computational IND package: mechanism validation, patient selection rationale, ADMET, PBPK, clinical trial design simulation.

**BioMate workflow chain (complete IND computational package):**
1. Target validation: scRNA-seq expression of IL6R in RA synovial cells (from public GEO datasets) → confirm pathogenic cell type relevance
2. GWAS evidence: query GWAS Catalog for IL6/IL6R-adjacent loci in RA → genetic support for target
3. Protein structure (AlphaFold / PDB): IL6R structure for binding site visualization; homology with orthologous species for PK extrapolation
4. ADMET screening (SMILES input): hERG, hepatotoxicity, Ames mutagenicity, CYP inhibition, blood-brain barrier, solubility → pass/fail with thresholds
5. PBPK modeling: allometric scaling to human PK; simulate synovial joint exposure; estimate therapeutic concentration at trough
6. Patient selection rationale: IL-6 / STAT3 gene signature scoring from published RA transcriptomics → define biomarker for enrollment
7. Clinical trial simulation: power calculation for stratified enrollment (IFNGS-analog for IL-6 pathway); dose selection based on PBPK Cmax/Cmin ratios
8. §2.6.1 LLM narrative generation: structured IND section covering mechanism, preclinical evidence, PK rationale, patient selection
9. **Output:** Full IND computational package — ADMET report, PBPK curves, patient stratification biomarker, power calculation, and §2.6 narrative in DOCX format; review-ready for FDA pre-IND meeting

**This is BioMate's highest-value demo.** A CRO charges $1.5–3M and 4–6 months for equivalent work. BioMate delivers it in a day.

---

## Part 4: Internal LLM Training Strategy — Comprehensive Roadmap

### 4.1 The Core Strategic Question: What Makes BioMate's LLM Genuinely Unique?

Before committing to training, it is worth asking whether an internal model is actually necessary, and if so, what it should do that no existing model can.

**The published landscape confirms an empty niche.** A systematic survey of existing biomedical AI tools reveals the following closest approaches to BioMate's orchestration task:

| System | What it does | What it cannot do |
|---|---|---|
| **BRAD** (arXiv:2409.02864, 2024) | LLM + RAG over bioinformatics tool docs; single tool calls via prompting | Cannot chain GWAS → scRNA → ADMET → PBPK; no QC judgment; no regulatory synthesis; uses prompting, not trained on traces |
| **BioChatter** (*Brief Bioinform*, 2023) | LLM wrapper over biological knowledge graphs | No pipeline execution; no cross-domain chaining; no parameter extraction |
| **GeneGPT** (arXiv:2304.09667, 2023) | Codex + NCBI API tool use; 0.83 on GeneTuring benchmark vs 0.12 for ChatGPT | Single-domain NCBI queries only; no orchestration of multi-step omics analysis |
| **BioAgent Bench** (arXiv:2601.21800, 2026) | Evaluation of frontier LLMs on RNA-seq, variant calling, metagenomics pipelines | Frontier LLMs work under normal conditions but fail on edge cases / corrupted inputs — exactly what fine-tuning would fix |
| **Geneformer v2** (*Nature*, 2023) | Self-supervised transformer on 104M single-cell transcriptomes; in silico perturbation | Single-cell only; no GWAS-to-ADMET chaining; no regulatory output |
| **TxGemma** (Google, 2025) | Fine-tuned on 66 TDC therapeutic datasets; ADMET + DTI prediction | No workflow orchestration; no cross-domain synthesis; no IND generation |

**Conclusion:** No published model is trained on, or designed for, the following tasks that BioMate uniquely performs:

1. **Workflow-native orchestration** — selecting which of 2,455+ workflows to run for a given biological question, sequencing them in the correct translational order, and passing results between domains with biological context
2. **Parameter extraction from scientific prose** — mapping "150-day chronic dosing study in cynomolgus monkeys at 10 mg/kg" to `{species: cyno, duration_days: 150, dose_mg_kg: 10, study_type: chronic_tox}` for the PBPK workflow
3. **Cross-domain result synthesis** — connecting a GWAS hit (PTPN22, rs2476601) to a scRNA cell type (Treg), to a druggability assessment, to an ADMET liability, to a PK exposure prediction in a single coherent inference step
4. **Autonomous QC judgment** — detecting that a PCA plot shows batch-driven separation rather than biological signal, selecting ComBat-seq as the remediation, re-running the downstream analysis, and reporting the change as a QC event
5. **IND-ready document generation** — authoring a §2.6 clinical pharmacology narrative from the combined outputs of GWAS, scRNA-seq, ADMET, and PBPK workflows

**Items 1–5 are categorically unavailable in any public model.** This is BioMate's genuine LLM moat. The model need not be a better general biomedical LLM than Med-PaLM 2 or TxGemma — it needs to be the orchestration and synthesis layer that those models cannot be by design.

---

### 4.2 Should a "Virtual Cell" Be Part of BioMate's LLM Strategy?

**The short answer: yes — as a fine-tuned component built on top of existing open-source foundation models, not built from scratch.**

#### What "Virtual Cell" means in 2025

The canonical definition comes from Bunne et al., *Cell* 187(25):7045–7063 (2024) — a 42-author roadmap paper coordinated by CZI (DOI: 10.1016/j.cell.2024.11.015). It specifies a two-layer architecture:

- **Universal Representations**: multi-modal embeddings encoding molecular, cellular, and multicellular state (scRNA-seq, ATAC-seq, proteomics, microscopy, cryo-EM)
- **Virtual Instruments**: models that operate on those embeddings to either decode them into interpretable outputs or manipulate them to simulate perturbations (genetic, chemical, environmental) never tested experimentally

The goal: given a cell's baseline transcriptomic state + a perturbation (drug compound, gene knockout), predict the resulting transcriptomic state.

**Key gap vs. what exists today:** Three open-source foundation models are the closest building blocks:

| Model | Training data | Perturbation prediction? | Autoimmune-specific? |
|---|---|---|---|
| **Geneformer v2** (Theodoris et al., *Nature* 2023; HuggingFace ctheodoris/Geneformer) | 104M single-cell transcriptomes | ✅ In silico gene silencing/overexpression | ❌ General human cells |
| **scGPT** (Cui et al., *Nature Methods* 2024; MIT license) | 33M human cells; organ-specific sub-models | ✅ Perturbation prediction (fine-tuned) | ❌ General |
| **scFoundation** (BioMap; Apache 2.0) | 50M+ human single-cell transcriptomes | ✅ Drug response prediction (cancer) | ❌ Cancer-focused |

All three are trained on general human transcriptomes. **None have been fine-tuned on autoimmune-specific cell types** (Tregs, Th17, plasmablasts, synovial fibroblasts) or disease-relevant perturbations. This is the gap BioMate can fill.

#### The perturbation data situation

For a virtual cell to predict how immune cells respond to drug perturbations, perturbation-response training data is needed. The largest publicly available datasets:

| Dataset | Scale | Cell types | Relevance |
|---|---|---|---|
| **Replogle et al. 2022** (*Cell* 185:2559; PMID 35688146) | 2.5M cells, genome-wide CRISPRi | K562 leukemia + RPE1 epithelial | Low — not immune cells |
| **Norman et al. 2019** (*Science*; combinatorial CRISPRa) | ~100K cells, paired combinations | K562 | Low — not immune |
| **Belk et al. 2022** (*Cancer Cell*; PMID 35750052) | Genome-wide CRISPR in human CD8+ T cells | CD8+ TILs (tumor context) | Medium — T cells, but exhaustion not autoimmunity |
| **NeurIPS Perturbation Benchmark** (Open Problems 2022/2023) | Human PBMCs, 144 compounds (LINCS CMap), 3 donors | PBMCs | High — immune cells, drug perturbations |
| **ImmPort clinical studies** | ~100 studies, immune functional readouts | T cells, B cells, monocytes | High — autoimmune disease context |

**The honest assessment:** No genome-wide Perturb-seq dataset in primary autoimmune-relevant cell types (Tregs, Th17, synovial fibroblasts) is publicly available as of 2026. The NeurIPS PBMC dataset + ImmPort functional studies are the best available proxy. This means BioMate's virtual cell layer will need a combination of:

1. Fine-tuning Geneformer v2 on autoimmune-specific scRNA-seq atlases (CELLxGENE immune cell filter: 120M+ cells, many autoimmune) to specialize the cell state representations
2. Using the NeurIPS PBMC drug perturbation benchmark for the drug-response prediction head
3. Generating synthetic perturbation training data via scDiffusion (Luo et al., *Bioinformatics* 2024) for cell types with no public Perturb-seq data

#### What BioMate's autoimmune virtual cell would uniquely predict

No existing model predicts all of the following simultaneously:

1. **Disease-risk variant → cell state**: given rs2476601 (PTPN22, RA risk allele) → what happens to Treg suppressive function and Th17 differentiation? Maps GWAS signal to cell biology.
2. **Drug perturbation in patient-specific immune cell context**: given a JAK1 inhibitor + the patient's baseline Th17/Treg ratio from blood scRNA-seq → predict post-treatment immune cell state redistribution
3. **Patient stratification from single-cell baseline**: given pre-treatment PBMC scRNA-seq profile → predict probability of anti-TNF response class (Treg abundance + IFN signature + B cell activation index)
4. **Synergy prediction**: given JAK inhibitor + mTOR inhibitor → predict combined effect on Th17 expansion in inflamed synovium

This is genuinely novel and creates a closed loop with BioMate's workflows: virtual cell predicts → BioMate routes to validation workflow → executes → QC → result feeds back to update the virtual cell model.

---

### 4.3 The Data Reality: Starting Without User Traces

BioMate currently has 2,455+ indexed workflows and access to all public datasets listed in Part 2 — but limited user execution trace data from real pharma programs. This is addressable via three strategies:

#### Strategy A: GEO-as-workflow-traces

Each GEO series is a de facto workflow execution record:
- **Input**: raw sequencing data (FASTQ/BAM accession)
- **Methods section of linked paper**: the workflow steps, parameters, QC decisions
- **Results/abstract**: the biological interpretation drawn from outputs

Scale: **288,000+ GEO series** × linked PubMed paper ≈ ~100,000–200,000 usable workflow description triples after filtering for papers describing computational analysis pipelines. The EBI Single Cell Expression Atlas adds documented Nextflow/Galaxy pipelines per dataset. This is a large, real (not synthetic) corpus of workflow orchestration examples.

**Key limitation**: GEO traces cover single-domain workflows. The cross-domain GWAS → scRNA → ADMET → PBPK chain does not appear in any single published paper — it is an inherently BioMate-specific training signal.

#### Strategy B: Run BioMate on Public Data at Scale

With 2,455 indexed workflows and real compute infrastructure (AWS Batch), BioMate can generate its own execution trace corpus by running workflows on public GEO datasets:

- Select ~500 autoimmune-relevant GEO datasets covering RA, SLE, IBD, MS
- Run each through the relevant BioMate workflow (DESeq2, Seurat, clusterProfiler, ATAC-seq, etc.)
- Record: input data characteristics → parameter choices → QC outcomes → biological output → summary
- Cost estimate: ~$0.50–$2 per run × 500 datasets × 5 workflows each = $1,250–$5,000 for a substantial synthetic execution corpus covering all 34 domains

This generates real execution traces without real users — and each trace is ground-truthed against published findings from the linked GEO paper.

#### Strategy C: Mine Published Methods Sections

Published omics papers contain near-complete workflow orchestration recipes. A paper abstract + methods section contains: biological context → workflow choice → parameter decisions → QC notes → biological interpretation. Parsing 100K+ methods sections into structured training examples is tractable with current LLMs used as extractors (extract-then-verify pipeline).

**GeneGPT (Jin et al. 2023)** showed that providing tool-use demonstrations in-context raised bioinformatics task performance from 0.12 to 0.83 on GeneTuring — validating that workflow-execution knowledge extracted from text is high-quality training signal.

---

### 4.4 Model Architecture: Four Layers, One System

```
┌─────────────────────────────────────────────────────────────────┐
│                    BioMate Foundation Stack                      │
├─────────────────────────────────────────────────────────────────┤
│  Layer 4: Workflow Orchestration LLM                            │
│  (Llama 3.1 70B fine-tuned on GEO traces + synthetic chains)   │
│  Tasks: workflow routing, parameter extraction, result synthesis │
│         QC judgment, IND narrative generation                    │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: Clinical Trial Design LLM                             │
│  (Llama 3.1 70B fine-tuned on AACT + FDA packages + PubMed)    │
│  Tasks: endpoint selection, stratification biomarker, §2.6 text │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Target Prioritization GNN                             │
│  (STRING GNN + transformer on GWAS Catalog + DICE + Open Targets)│
│  Tasks: GWAS → eQTL → cell type → druggability ranking         │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: Autoimmune Virtual Cell                               │
│  (Geneformer v2 fine-tuned on CELLxGENE immune + ImmPort)      │
│  Tasks: cell state prediction, drug perturbation response,      │
│         patient stratification from scRNA baseline              │
└─────────────────────────────────────────────────────────────────┘
         ↑ feeds predictions as context into Layer 4 ↑
```

Layer 1 (virtual cell) feeds biological predictions upward — when a user asks "will this JAK inhibitor work for my SLE patient?", Layer 1 predicts the immune cell state response, Layer 2 provides GWAS-grounded target confidence, Layer 3 suggests the trial design biomarker, and Layer 4 orchestrates the validation workflows and synthesizes the IND narrative. The layers are independently deployable but strongest together.

---

### 4.5 The Four Models — Detailed Specifications

#### Layer 1: Autoimmune Virtual Cell (Priority 1)

**Goal:** Given patient baseline scRNA-seq profile + drug/genetic perturbation → predict immune cell state response; stratify patient as likely responder or non-responder

**Base model:** Geneformer v2 (Apache 2.0, HuggingFace — available now)

**Fine-tuning data:**
- CELLxGENE Census immune cell filter: 120M+ total cells; immune-annotated subset covers T cells, B cells, myeloid cells, NK cells across 21 autoimmune-relevant tissues
- ImmPort: ~100 public studies in immunology, 65 clinical trials — T cell activation states, cytokine profiles, HLA types; directly autoimmune-relevant
- GEO autoimmune scRNA-seq: RA synovial fluid (GSE136459: 32K cells), SLE PBMCs (GSE142016), IBD lamina propria (GSE134809), MS CSF immune cells (GSE144744) — ~200K autoimmune-specific cells across indications
- NeurIPS 2022/2023 PBMC drug perturbation benchmark: 144 compounds × 3 donors × scRNA readout — drug-response head training
- Synthetic augmentation: scDiffusion to generate Treg and Th17 cell states for drug perturbation conditions with no public Perturb-seq data

**Tasks trained:**
- Cell state response prediction: given pre-treatment immune profile → predict post-drug cell composition (Th17/Treg ratio, plasmablast frequency, IFN signature score)
- Patient stratification: given PBMC scRNA baseline → classify as likely responder/non-responder to anti-TNF, JAK inhibitor, vedolizumab, anifrolumab
- In silico gene perturbation: given GWAS causal gene candidate → predict cell state consequences of loss-of-function (Treg suppression, Th17 expansion, B cell hyperactivation)

**Benchmark target:** >80% AUC patient stratification on held-out autoimmune GEO cohorts (RA anti-TNF: published best 93.3% monocyte-focused, genome-wide target 80%+)

---

#### Layer 2: Multi-Omic Target Prioritization Model (Priority 2)

**Base model:** Graph neural network on STRING v12 (11.5B interactions) + transformer for text

**Training data:** GWAS Catalog (7,000+ GWAS studies) + DICE (13 immune cell types, 12,254 eGenes) + GTEx v9 + Open Targets + ChEMBL 35 (21.1M bioactivity measurements) + DisGeNET (1M+ gene-disease associations)

**Tasks:** GWAS-to-eQTL colocalization, causal cell-type assignment, druggability scoring, ranked target output

**Benchmark:** Known RA/SLE/IBD validated targets in top decile on held-out GWAS studies; AUC > 0.80 on Open Targets clinical precedence labels

---

#### Layer 3: Clinical Trial Design LLM (Priority 3)

**Base model:** Llama 3.1 70B fine-tuned

**Training data:** AACT (507,584 structured trials, ~15K autoimmune) + PubMed/PMC autoimmune subset + FDA public NDA/BLA review packages for >50 approved autoimmune biologics + BioMate session preference data (as it accumulates)

**Tasks:** Endpoint selection, inclusion/exclusion criteria, stratification biomarker recommendation, §2.6 narrative generation, adverse event class prediction from MOA

**Benchmark:** >80% endpoint match vs. FDA-approved designs on held-out indication-MOA pairs; ROUGE-L > 0.55 on §2.6 narrative generation

---

#### Layer 4: Workflow Orchestration LLM (Priority 4 — highest long-term value, but needs execution traces)

**Base model:** Llama 3.1 70B fine-tuned

**Training data (bootstrapped without user data):**
- GEO-mined workflow traces: ~100K+ (input data context) → (methods workflow steps) → (biological interpretation) triples from GEO series + linked papers
- BioMate self-generated traces: 500 autoimmune GEO datasets × 5 workflows each = ~2,500 real execution records with parameter choices and QC outcomes
- Synthetic cross-domain chains: construct 200–500 hand-curated GWAS → scRNA → ADMET → PBPK chain examples from published translational studies where each step is documented
- Instruction tuning on 2,455 workflow metadata cards: what each workflow does, what inputs it requires, what outputs it produces, when to chain it with another

**Tasks:** Workflow routing (intent → correct workflow from 2,455), parameter extraction from prose, cross-domain result synthesis, QC judgment (batch effect → remediation selection), IND document generation

**Unique value:** This layer is what no competitor can build from public data. Every BioMate user session that produces an accepted output is one more training example. The model compounds in quality as the user base grows.

---

### 4.6 Concrete Development Timeline

```
Month 0–1: Data infrastructure
  ├── Download + filter CELLxGENE immune cell subset
  ├── Set up GEO API pipeline to extract methods sections from autoimmune series
  ├── Download AACT PostgreSQL dump, filter autoimmune trials
  ├── Configure TDC + ChEMBL + DICE pipelines
  └── Confirm Geneformer v2 license + set up fine-tuning environment (8× A100)

Month 1–3: Layer 1 — Autoimmune Virtual Cell
  ├── Fine-tune Geneformer v2 on CELLxGENE immune + GEO autoimmune scRNA datasets
  ├── Add drug-response head using NeurIPS PBMC perturbation benchmark
  ├── Validate: patient stratification AUC on held-out RA anti-TNF GEO cohorts
  ├── Integrate as BioMate "virtual cell" tool: chat → predicted immune response → routes to validation workflow
  └── Milestone: >75% AUC on RA anti-TNF stratification; virtual cell output visible in BioMate UI

Month 3–6: Layer 2 — Target Prioritization GNN
  ├── Build STRING-based GNN backbone
  ├── Train on GWAS Catalog + DICE + Open Targets composite labels
  ├── Validate: known RA/SLE/IBD targets in top 10% of rankings
  ├── Deploy as BioMate "target ranking" tool: GWAS summary stats + cell type → ranked target list
  └── Milestone: AUC > 0.80 on Open Targets clinical precedence holdout

Month 3–5: Layer 3 — Clinical Trial Design LLM (parallel with Layer 2)
  ├── Continued pretraining on PubMed + PMC autoimmune subset (~500M tokens; ~40 GPU-hours)
  ├── Instruction fine-tuning on AACT + FDA review packages
  ├── Validate: endpoint recommendation on held-out approved autoimmune trials
  ├── Deploy as BioMate "trial design" tool
  └── Milestone: >75% endpoint match rate; §2.6 narrative reviewed by 2 domain experts

Month 5–9: Layer 4 — Workflow Orchestration LLM (bootstrapped)
  ├── Mine 100K+ GEO workflow traces (methods section extraction pipeline)
  ├── Run BioMate on 500 public autoimmune GEO datasets to generate real execution traces
  ├── Construct 200+ hand-curated cross-domain chain examples from literature
  ├── Fine-tune Llama 3.1 70B on combined corpus
  ├── Validate: routing accuracy on held-out user intent → workflow selection test set
  └── Milestone: >85% workflow routing accuracy; parameter extraction F1 > 0.80

Month 9–18: Integration + continuous learning
  ├── Connect all four layers into unified BioMate Foundation Stack
  ├── Add real user execution traces as DPO preference data (as user base grows)
  ├── Autoimmune virtual cell: add Th17-specific Perturb-seq fine-tuning (custom experiments or ImmPort data)
  ├── Layer 4: improve cross-domain synthesis with accumulated session data
  └── Milestone: end-to-end GWAS → virtual cell → target ranking → trial design → IND narrative in one session

Month 18+: Proprietary data flywheel
  ├── Model quality compounds with each new pharma user session
  ├── Federated fine-tuning with partner cohort data (no raw data egress)
  └── Annual model release with therapeutic-area performance benchmarks
```

**Compute budget estimate:**
- Layer 1 (Geneformer fine-tune): 8× A100, ~50–100 GPU-hours per training run → ~$200–400/run on AWS
- Layer 3 (Llama 3.1 70B pretraining): 8× A100, ~150–300 GPU-hours → ~$600–1200/run
- Layer 4 (Llama 3.1 70B fine-tune): similar to Layer 3
- Total months 1–9: ~$5,000–15,000 compute (AWS spot instances); well within a seed-stage AI budget

---

### 4.7 Data Acquisition Strategy

#### Public datasets — available immediately, no licensing cost

| Dataset | Size | Autoimmune relevance | Access |
|---|---|---|---|
| CELLxGENE Census immune filter | ~20M+ cells | T/B/myeloid immune cells, multiple autoimmune tissues | CZI Census API |
| GEO autoimmune scRNA series | ~200K cells across RA, SLE, IBD, MS | Direct disease relevance | NCBI GEO API |
| ImmPort | ~100 studies, 65 trials | Immunology-specific functional + phenotypic data | ImmPort downloads |
| GWAS Catalog | 7,000+ GWAS studies | Autoimmune trait filter | GWAS Catalog REST API |
| DICE | 13 immune cell types, 12,254 eGenes | Immune eQTL — critical for cell-type assignment | dice-database.org |
| PubMed + PMC OA | 36M abstracts + 8M full text | Autoimmune MeSH filter → ~4M records | NCBI FTP |
| AACT | 507,584 studies | ~15K autoimmune completed trials | CTTI PostgreSQL dump |
| ChEMBL 35 | 21.1M bioactivity measurements | Full corpus | ChEMBL FTP |
| TDC | 66 datasets, 15M+ records | ADMET + DTI benchmarks | TDC Python API |
| Open Targets | 60K+ targets | Disease-gene-drug associations | Open Targets FTP |
| NeurIPS Perturbation Benchmark | PBMC × 144 compounds | Drug perturbation in immune cells | Public |

#### Proprietary assets — the growing moat

| Asset | Source | Unique value | When available |
|---|---|---|---|
| BioMate self-generated execution traces | Run workflows on 500 GEO datasets | Real parameter choices + QC outcomes across 34 domains | Month 1 (generate proactively) |
| User session execution traces | Real pharma user sessions | Revealed preference: accepted vs. modified outputs | Grows with user base |
| Auto-loop remediation records | BioMate QC logs | Negative examples: what failed, what fixed it | Month 1 (mine existing logs) |
| Cross-domain chain sessions | BioMate session graph | GWAS → ADMET → PBPK complete traces | Grows with user base |
| PBPK simulation outcomes | BioMate PBPK runner | Compound → clinical exposure; no public equivalent | Month 1 (existing runs) |

---

## Part 5: Go-to-Market and Moat Summary

### Target Buyer

**Title:** Director / VP of Translational Sciences at mid-size autoimmune pharma or biotech  
**Pain:** Computational bottleneck — biology team knows what they need to know, cannot execute the analysis  
**Budget holder:** Yes — controls CRO spend ($2–10M/year for computational analysis)  
**Alternative:** Hire a bioinformatics CRO (4–6 months, $500K–2M per engagement)  
**BioMate value prop:** Same output in 1 day, self-service, iterative

### Target accounts (illustrative)

- Mid-size autoimmune-focused biotechs: Prometheus Biosciences (acquired by Merck for $10.8B — stratified IBD), Alumis (TYK2 inhibitor for autoimmune), Acelyrin (izokibep for RA/uveitis), Cullinan Oncology (autoimmune pipeline)
- Large pharma autoimmune divisions: AstraZeneca/Alexion (SLE), Abbvie (RA/IBD/psoriasis), UCB (RA/Crohn's), Galapagos (RA/fibrosis)
- Academic medical centers running industry-sponsored translational studies: Mayo Clinic, UCSF, Johns Hopkins

### The Compounding Moat

```
More pharma users run pipelines
         ↓
More execution traces → proprietary training data
         ↓
Better BioMate LLM → better QC judgment + better workflow chaining
         ↓
More accurate outputs → more pharma users adopt
         ↓  (repeat)
```

A competitor starting today with only public data can build a biomedical LLM. They cannot replicate the execution trace dataset that BioMate accumulates from real translational programs. After 2 years of production use, this becomes the hardest-to-replicate asset in the company.

---

## Part 6: Key Open Questions for Team Discussion

1. **Which use case to demo first?** Recommendation: Use Case 2 (biologic responder signature) — most directly tied to a measurable clinical outcome, most validated published evidence, highest pharma budget owner willingness-to-pay.

2. **Data partnership strategy:** ImmPort and GEO data are public but require curation. Should we invest in a data engineering team now, or buy curated datasets from Novo Nordisk's TreLC platform or similar?

3. **LLM partner vs. build:** TxGemma (Google) is therapeutics-specific and commercially licensable. Fine-tuning TxGemma on autoimmune-specific data + adding BioMate execution traces may be faster than full pretraining. Evaluate vs. LLaMA 3.1 fine-tuning.

4. **Regulatory strategy:** If BioMate-generated computational packages are submitted in INDs, does that create regulatory exposure? AstraZeneca and Pfizer have precedent for AI-assisted IND sections — FDA accepted these in NDAs from 2023 onward. Early engagement with FDA on computational tool qualification may be worth exploring.

5. **Partnership anchor:** Seek one pharma partner willing to co-develop the autoimmune stratification model with their own patient cohort data (in federated architecture) in exchange for preferred pricing + co-publication rights. This generates both proprietary training data and industry validation.

---

## References (Selected, with DOI/PMID where available)

1. Wong CH, Siah KW, Lo AW. "Estimation of clinical trial success rates and related parameters." *Biostatistics* 2019;20(2):273–286. DOI: 10.1093/biostatistics/kxx069. [Primary citation for Phase 2→3 transition rates by therapeutic area and biomarker stratification impact.]
2. "Phase 2 to phase 3 clinical trial transitions: Reasons for success and failure in immunologic diseases." *J Allergy Clin Immunol* 2017;139(6):1868–1875. PMID: 28506849. [Qualitative failure mode taxonomy; quantitative rates superseded by Wong et al. 2019.]
2. Szablewski et al. "Multi-omics approach in RA, MS, and T1D." *Funct Integr Genomics* (2025). PMC12009781.
3. Mei et al. "RNASET2 as therapeutic target in autoimmune thyroiditis." PMC12907157 (2026).
4. Ling et al. "Anifrolumab efficacy by IFN gene signature and clinical subgroups." *Arthritis Rheumatol* (2022). Pooled TULIP analysis. ResearchGate.
5. Guo et al. "Anti-TNF response prediction: 93.3% accuracy in monocytes." PMC12109967 (2025).
6. Hammann et al. "ML multi-omics for anti-TNF prediction." PMC8996791 (2022).
7. Theodoris et al. "Geneformer: transfer learning using a genome-wide expression language model." *Nature* (2023). PMID: 37258680. DOI: 10.1038/s41586-023-06139-9.
8. Cui et al. "scGPT: toward building a foundation model for single-cell multi-omics." *Nature Methods* (2024).
9. Mendez et al. "ChEMBL: towards direct deposition of bioassay data." *Nucleic Acids Research* (2023). DOI: 10.1093/nar/gkac1000.
10. Tufts CSDD. "Day of Delay White Paper." August 2024.
11. Liao et al. "TxGemma: efficient and agentic LLMs for therapeutics." arXiv:2504.06196 (2025).
12. Singhal et al. "Towards expert-level medical question answering with large language models (Med-PaLM 2)." *Nature Medicine* (2024). DOI: 10.1038/s41591-024-03423-7.
13. Tran et al. "Reconciling CMap connectivity scores." *Briefings in Bioinformatics* (2021). PMC8597919.
14. UK Biobank + FinnGen meta-analysis (933,649 individuals): *Nature Genetics* (2024). DOI: 10.1038/s41588-024-01898-1.
15. DICE Database: Schmiedel et al. *Cell* (2018). DOI: 10.1016/j.cell.2018.10.022.
16. Grand View Research. Rheumatoid Arthritis Therapeutics Market (2024). Fortune Business Insights. IBD Market (2025). GlobeNewswire. SLE Market (2025).
17. Recursion Pharmaceuticals Q4 2025 Financial Results. IR press release.
18. Insilico Medicine. "AI-designed drug for IPF shows dose-dependent FVC improvement." *Nature Medicine* (2025).
19. Benchling acquires PipeBio. TechCrunch (2024).
20. Charles River + Valo Health identify lupus candidate via Logica. BusinessWire (March 2025).
