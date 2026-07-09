# Faculty Survey: Computational Biology Collaborators for BioMate Autoimmune + LLM Initiative

**Date:** 2026-07-01  
**Purpose:** Survey of four UTHealth Houston / BCM faculty candidates assessed for strategic collaboration on BioMate's autoimmune drug discovery platform and internal LLM training program  
**Surveyed by:** BioMate team (detailed technical due diligence completed 2026-06-17)

---

## Overview

BioMate is building a four-layer internal LLM stack for autoimmune drug discovery (detailed in `20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.md`). The four layers require distinct academic expertise that no single lab covers:

| LLM Layer | Capability needed | Best faculty match |
|---|---|---|
| L1: Autoimmune Virtual Cell | Single-cell immune foundation models, scGWAS, immune cell state prediction | **Dr. Zhao** |
| L2: Target Prioritization GNN | GPU-accelerated GWAS, eQTL colocalization, population genetics | **Dr. Zhi** |
| L3: Clinical Trial Design LLM | EHR foundation models, clinical NLP, structured clinical data | **Dr. Zhi + Dr. Jim Zheng** |
| L4: Workflow Orchestration LLM | Biomedical literature mining, LLM knowledge extraction, GEO trace mining | **Dr. Jim Zheng** |

All four faculty are at UTHealth Houston SBMI or BCM — a joint institutional collaboration is administratively simpler than four separate agreements.

---

## Faculty 1: Dr. Zhongming Zhao

**Institution:** UTHealth Houston, School of Biomedical Informatics  
**Lab:** Bioinformatics and Systems Medicine Lab (bsml320)  
**Lab page:** https://www.uth.edu/bioinfo/  
**Google Scholar:** h-index 90, i10 435, 35,600+ citations, 492 articles  
**GitHub:** https://github.com/bsml320 (25+ public repos)

### Research clusters (last 3 years)

| Cluster | Key papers | Methods |
|---|---|---|
| Single-cell + immune-oncology | turep (bioRxiv 2026), Scupa, scGWAS (Genome Biol 2022), ImmuneApp, DeepTR | Atlas-scale scRNA-seq + spatial transcriptomics |
| Multi-omics QTL + AD | PRISM-xQTL (Alz & Dem 2026), MethConvTransformer (arXiv 2026), BrainGeneBot | Genome × transcriptome × methylome integration |
| Deep-learning frameworks | NetRNApan (Brief Bioinform 2025), NetBCE, VAEN, fadvi | Sequence/image → property prediction |

### Tools verified and integrated into BioMate (as of 2026-06-17)

| Tool | License | BioMate status | Autoimmune relevance |
|---|---|---|---|
| **scGWAS** (Jia et al., Genome Biol 2022) | GPL-3.0 | ✅ Real container built + smoke-tested (chain id 72) | Bridges GWAS → single-cell immune cell types; directly maps RA/SLE GWAS signals to Treg/Th17 |
| **turep** | MIT | ⚠️ Chain id 71, stub — awaiting real-data wrap | Cross-cancer tumor-reactive T cell classifier; transferable to autoimmune-reactive T cells |
| **ImmuneApp** | MIT | ⚠️ Chain id 71 step 3, stub | HLA-I epitide binding — directly maps to Use Case 5 (autoantigen discovery for tolerization) |
| **NetBCE** | MIT | ❌ Not yet integrated | B-cell epitope prediction — relevant to anti-dsDNA, anti-citrullinated protein antibodies in RA/SLE |
| **Scupa** | NOASSERTION | ❌ Blocked on license | Immune cell polarization scoring (Th17/Treg/macrophage) — Layer 1 virtual cell cell-state representation |
| **VAEN** | No LICENSE | ❌ Blocked on license | Drug response imputation in single-cell — drug perturbation head for virtual cell |
| **fadvi** | MIT | ❌ Not yet integrated | Single-cell factor disentanglement — separates biological from technical variation |

### Fit for autoimmune + LLM initiative

**Layer 1 (Autoimmune Virtual Cell): primary fit**
- scGWAS is the exact tool needed to assign GWAS autoimmune loci (RA, SLE, IBD) to specific immune cell types (Tregs, Th17, plasmablasts, synovial fibroblasts) — the foundational step of the virtual cell pipeline
- Scupa provides immune cell polarization states that form the cell-state representation space the virtual cell operates in
- turep + ImmuneApp provide the antigen-specific T/B cell layer
- VAEN provides drug response prediction — the perturbation head

**What BioMate already has:** scGWAS running end-to-end in BioMate; demonstrated on Crohn's disease × Tregs association (reproducing published result). Container at `biomate/scgwas:v1`; needs ECR push to go live on dev.

**Publication angle:** Co-develop "Autoimmune Immune Cell Virtual Cell" as a joint paper: BioMate provides execution infrastructure + AWS Batch compute + ADMET/PBPK integration layers; Zhao lab provides scGWAS + Scupa + domain expertise + biological validation. Target journal: *Nature Methods* or *Genome Biology*.

---

## Faculty 2: Dr. Degui Zhi

**Institution:** UTHealth Houston, School of Biomedical Informatics  
**Role:** Department Chair, Professor  
**GitHub:** https://github.com/ZhiGroup (32 public repos)  
**Google Scholar:** https://scholar.google.com/citations?user=9dmZ3lkAAAAJ

### Research clusters (last 3 years)

| Cluster | Key papers | Methods |
|---|---|---|
| Population genetics / GWAS | TorchGWAS (arXiv 2026), RaPID2, HiFiMAP, SLAB, FRAME | GPU GWAS, IBD detection, ancestry, pangenome |
| Brain imaging × genetics | UDIP on FA maps (Nat Commun 2026), UDIP-ViT, contrastive multimodal brain rep | Deep image phenotyping → GWAS on embeddings |
| EHR clinical ML | Med-BERT (329★), Vancomycin PK-RL (JMIR AI 2026), LLM-vs-clinical-model (medRxiv 2026), PK-RNN, CovRNN | EHR foundation models + RL + PK modeling |

### Tools verified and integrated into BioMate (as of 2026-06-17)

| Tool | License | BioMate status | Autoimmune relevance |
|---|---|---|---|
| **TorchGWAS** | MIT | ⚠️ Chain id 69, stub — real-data wrap in progress | GPU-accelerated GWAS for thousands of phenotypes; runs autoimmune GWAS at population scale |
| **RaPID** | MIT | ❌ Not yet integrated | IBD-aware GWAS; identity-by-descent for ancestry-stratified RA/SLE cohorts |
| **Med-BERT** | Apache-2.0 (329★) | ❌ Not yet integrated | EHR foundation model; backbone for Layer 3 clinical trial design LLM |
| **UDIP-ViT** | MIT | ❌ Not yet integrated | Vision transformer for deep image phenotyping; applicable to histopathology in autoimmune |
| **FDA** (Folding-Docking-Affinity) | MIT | ❌ Deferred — paper-reproduction repo, needs inference wrapper | ESMFold → docking → affinity; relevant to small-molecule programs in RA/IBD |

**Note on FDA tool:** The ZhiGroup/FDA repo documents how to reproduce the paper, not how to run inference on a new target-ligand pair (two conda environments, no inference CLI). Deferred pending a clean `predict(target_fasta, ligand_sdf) → affinity` entry point from the lab.

### Fit for autoimmune + LLM initiative

**Layer 2 (Target Prioritization): primary fit**
- TorchGWAS provides GPU-scale GWAS for the target prioritization pipeline. Running autoimmune GWAS summary statistics (RA: 58K cases, SLE: 26K cases, IBD: 86K cases) through TorchGWAS → feeding results into DICE eQTL colocalization → Layer 2 GNN → ranked target list
- RaPID provides IBD-aware stratification for ancestry-diverse autoimmune cohorts

**Layer 3 (Clinical Trial Design LLM): strong fit**
- Med-BERT (329★, Apache-2.0) is the most mature clinical EHR foundation model in the group and a natural backbone for the Layer 3 clinical NLP component
- His 2026 medRxiv paper "LLM vs. clinical foundation model" directly addresses the training strategy question BioMate faces for Layer 3 — his group has already benchmarked the relevant approaches

**What BioMate already has:** TorchGWAS chain wired (id 69); qc_evidence + rationale rows populated and verified live. Toy dataset smoke test passes. Real-scale test planned with 1000 Genomes + simulated phenotypes.

**Publication angle:** Co-develop "Population-Scale GWAS for Autoimmune Target Prioritization via BioMate" — TorchGWAS + RaPID running on UK Biobank autoimmune cohorts routed through BioMate's target ranking pipeline. Zhi lab provides GWAS methodology + UKB credential; BioMate provides orchestration + ADMET/PBPK integration. Target: *Nature Genetics* methods paper or *Bioinformatics*.

---

## Faculty 3: Dr. Zhandong Liu

**Institution:** Baylor College of Medicine (BCM)  
**Focus:** Rare neurological disease, multi-modal workup (WGS + RNA-seq + splicing analysis)

### BioMate integration status

The complete Liu lab pipeline is already wired into BioMate as chain id 1 (`rare_disease_multimodal_workup`), matching his RareCollab paper (arXiv 2602.04058) verbatim:
nf-core/sarek → vcf_annotate_ensemblvep → nf-core/rnaseq → nf-core/drop (OUTRIDER + FRASER) → case_report_aggregation

All upstream tools (sarek, VEP, rnaseq, DROP, OUTRIDER, FRASER) already indexed in BioMate.

### Fit for autoimmune + LLM initiative

**Low direct relevance.** Liu's focus is rare variant interpretation for neurological disease — orthogonal to autoimmune drug discovery. His pipeline is excellent for rare autoimmune patients with suspected monogenic causes (IPEX, CGD, WAS), but this is a niche within the autoimmune indication.

**Recommendation:** Continue the existing rare disease collaboration (chain id 1, L01 demo). Do not include Liu in the autoimmune + LLM proposal — the scope mismatch would dilute the pitch.

---

## Faculty 4: Dr. W. Jim Zheng

**Institution:** UTHealth Houston, School of Biomedical Informatics (Professor since 2013)  
**ORCID:** 0000-0001-7411-6047

### Key publications

| Paper | Journal | Year | Relevance |
|---|---|---|---|
| "Ensemble pretrained language models to extract biomedical knowledge from literature" | JAMA | 2024 | Direct: LLM for biomedical knowledge extraction from text — the exact methodology for GEO trace mining |
| "Deep representation learning of patient data from EHR: A systematic review" | J Biomed Informatics | 2021 | EHR AI review; complements Zhi's Med-BERT work |
| "HiCPlus: enhancing Hi-C data resolution with deep CNN" | Nature Communications | 2018 | 3D chromatin — relevant to epigenomics layer (ATAC-seq) |
| "A guide to the BRAIN Initiative Cell Census Network data ecosystem" | PLoS Biology | 2023 | Data ecosystem design; relevant to BioMate's workflow data architecture |

### Fit for autoimmune + LLM initiative

**Layer 4 (Workflow Orchestration LLM): strongest fit of the four faculty for this specific layer**
- His 2024 JAMA paper on ensemble LLMs for biomedical knowledge extraction is precisely the methodology BioMate needs to mine 100K+ GEO methods sections into structured workflow traces — the bootstrapping strategy for Layer 4 before user execution traces accumulate
- No single-cell, no GWAS, no drug discovery — he is a pure informatics + NLP researcher; his value is the LLM training data pipeline, not the biological layers

**Recommendation:** Invite as a third PI on the joint UTHealth proposal, scoped to the LLM training data curation workstream. Natural sub-project: "Mining GEO and PubMed methods sections as workflow orchestration training data for biomedical AI."

---

## Collaboration Structure Recommendation

### Proposed joint UTHealth Houston collaboration (3-PI)

```
BioMate (industry partner)
    │
    ├── Dr. Zhongming Zhao ── Virtual Cell + Immune Biology Layer
    │      scGWAS, Scupa, turep, ImmuneApp, VAEN
    │      Publication target: Nature Methods / Genome Biology
    │
    ├── Dr. Degui Zhi ─────── GWAS + Clinical LLM Layer
    │      TorchGWAS, RaPID, Med-BERT
    │      Publication target: Nature Genetics / Bioinformatics
    │
    └── Dr. W. Jim Zheng ─── LLM Training Data Layer
           GEO mining, biomedical NLP, knowledge extraction
           Publication target: JAMA / JAMIA
```

**BioMate contribution to all three:** AWS Batch compute (GPU + CPU), execution infrastructure, ADMET/PBPK downstream integration, IND-ready report generation, co-authorship on all resulting papers, platform access for students and collaborators.

**What BioMate asks in return:** Non-exclusive right to deploy integrated tools on the BioMate platform; access to any de-identified cohort data for model training under a federated architecture (no raw data egress); acknowledgment in BioMate marketing materials.

### Sequencing

1. **First contact: Dr. Zhao** — scGWAS already running in BioMate gives the strongest opening demo. Propose a 30-min call to show the live scGWAS chain on Crohn's × Tregs, then pitch the autoimmune virtual cell co-development.
2. **Second contact: Dr. Zhi** — can reference the Zhao conversation; pitch the GWAS + Med-BERT layer as the complementary component. Same campus, likely knows Zhao.
3. **Third contact: Dr. Jim Zheng** — pitch as LLM training data workstream once the biological layers are committed. Lower-touch engagement, well-defined deliverable.
4. **Joint kick-off** — once all three are interested, propose a single 60-min UTHealth joint meeting to align on the overall architecture and publication roadmap.
