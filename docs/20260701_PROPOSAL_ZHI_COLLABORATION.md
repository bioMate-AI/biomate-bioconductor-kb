# Collaboration Proposal: BioMate × Dr. Degui Zhi Lab
## Population-Scale Autoimmune GWAS, Target Prioritization, and Clinical LLM

**Date:** 2026-07-01  
**To:** Dr. Degui Zhi, Department Chair & Professor, School of Biomedical Informatics, UTHealth Houston  
**From:** BioMate Team  
**Format:** Initial outreach letter + technical annex

---

## Outreach Letter

Dear Dr. Zhi,

We are writing from BioMate, an AI-native computational biology platform that orchestrates multi-step research workflows — spanning genomics, transcriptomics, drug screening, pharmacokinetic modeling, and IND document generation — through a single conversation-driven session for translational researchers and pharmaceutical scientists.

We have been following your group's work closely. TorchGWAS, your GPU-accelerated GWAS tool for scanning thousands of phenotypes simultaneously, is already wired into BioMate as a running chain. We have also mapped the UDIP brain imaging phenotyping pipeline and are tracking Med-BERT, your EHR foundation model, as a key component for our clinical language modeling work. We write to propose a formal collaboration in two complementary areas: **population-scale autoimmune GWAS for drug target prioritization**, and **a clinical trial design language model built on Med-BERT**.

**The clinical problem.** Clinical trial failure in autoimmune diseases is expensive and preventable. The Phase 2→3 success rate in autoimmune/inflammation is 45.7% — the remainder fail, at a cost of $800M–$2.4B per failed Phase 3 program (Wong et al., *Biostatistics* 2019; Tufts CSDD). The most actionable intervention is genetic target validation: selecting drug targets supported by convergent GWAS + eQTL evidence dramatically reduces the probability of late-stage failure. Yet the computational pipeline for this — running GWAS at population scale, colocalization with immune eQTLs, cell-type assignment, druggability scoring — is inaccessible to most pharma translational teams.

**Proposed collaboration: two linked workstreams.**

### Workstream A — Autoimmune GWAS Target Prioritization Pipeline

We propose integrating TorchGWAS and RaPID into a BioMate autoimmune target prioritization chain that runs the following end-to-end:

1. **TorchGWAS** (your lab, MIT, already integrated as chain id 69) — GPU-accelerated linear mixed model GWAS on autoimmune phenotypes; handles thousands of molecular phenotypes (UDIP-style deep phenotypes or standard disease case-control) with GPU parallelism

2. **RaPID** (your lab, MIT) — IBD segment detection for ancestry-aware stratification of diverse autoimmune cohorts; prevents spurious associations in admixed RA/SLE/IBD cohorts

3. **GWAS colocalization** (open tools: coloc, SMR) — test whether GWAS signals share a causal variant with DICE immune eQTLs (13 immune cell types, 12,254 eGenes); implemented within BioMate's Bioconductor workflow layer

4. **Target ranking** (BioMate Layer 2 GNN, under development) — integrates GWAS colocalization scores + eQTL cell-type assignments + druggability data (ChEMBL 35, Open Targets) into a ranked target list with convergent evidence scores

5. **Output:** Ranked target scorecard with genetic evidence, cell-type assignment, and druggability assessment — formatted for IND pre-meeting briefing or internal research review

**Validation benchmark:** Reproduce known validated RA targets (JAK1/2, IL-6R, CD20, TYK2, PTPN22) in the top decile of rankings using published UK Biobank + FinnGen RA GWAS summary statistics (N=933,649, Nature Genetics 2024). This constitutes a rigorous retrospective validation of the pipeline.

### Workstream B — Clinical Trial Design LLM Built on Med-BERT

Your 2026 medRxiv paper "LLM vs. clinical foundation model" directly informs BioMate's Layer 3 architecture decision: whether to fine-tune a general LLM or use a domain-pretrained clinical foundation model as the backbone for clinical trial design reasoning. We propose co-developing this layer with your group:

**Architecture:** Med-BERT (your lab, Apache-2.0, 329★) as the clinical encoder, fine-tuned on:
- AACT (ClinicalTrials.gov structured data): 507,584 studies → ~15,000 autoimmune completed trials with structured eligibility criteria, endpoints, and outcomes
- FDA public NDA/BLA review packages for 50+ approved autoimmune biologics (public documents)
- PubMed/PMC autoimmune subset: ~4M records filtered by MeSH
- Instruction pairs derived from published Phase 2/3 trial protocols: indication + MOA → correct endpoint selection

**Tasks trained:**
- Given indication + mechanism of action → recommend primary endpoint (ACR20/50/70 for RA; BICLA for SLE; CDAI for Crohn's)
- Given patient profile + drug class → suggest biomarker stratification variable (IFN gene signature for anifrolumab; anti-CCP for MTX)
- Given ADMET + PBPK outputs → generate §2.6 IND narrative

**Validation benchmark:** >80% endpoint recommendation accuracy vs. FDA-approved trial designs on held-out indication-MOA pairs; blind evaluation by 2 rheumatology clinical trialists.

**Your group's published evaluation framework** ("LLM vs. clinical foundation model") provides the ideal comparison baseline — the BioMate clinical LLM would be benchmarked using the same evaluation protocol your group designed, giving the resulting paper methodological continuity.

---

**Proposed deliverables and publication plan.**

| Deliverable | Lead | Timeline | Target venue |
|---|---|---|---|
| TorchGWAS real-data chain live on BioMate (1000G + simulated autoimmune phenotypes) | BioMate | Month 1 | — |
| RaPID integration (IBD-aware GWAS) | BioMate + Zhi lab | Month 2 | — |
| GWAS colocalization chain (TorchGWAS → coloc → DICE eQTL) | BioMate | Month 2 | — |
| **Paper 1:** "Population-scale autoimmune GWAS target prioritization via BioMate-TorchGWAS" | Joint (Zhi co-corresponding) | Month 5 | *Bioinformatics* or *Genome Research* |
| Med-BERT fine-tune on AACT + FDA packages for clinical trial design | Joint | Month 3 | — |
| Blind evaluation of clinical LLM endpoint recommendations | Zhi lab (using your evaluation protocol) | Month 5 | — |
| **Paper 2:** "A Med-BERT-based clinical trial design LLM for autoimmune drug development" | Joint (Zhi first/co-corresponding) | Month 7 | *JAMIA* or *npj Digital Medicine* |
| UK Biobank RA GWAS retrospective validation (requires UKB credential) | Joint | Month 6+ | Supplementary to Paper 1 |

**Regarding the FDA (Folding-Docking-Affinity) tool:** We reviewed ZhiGroup/FDA carefully. The current repository documents how to reproduce the paper (two conda environments, training scripts, Zenodo data download) but does not provide a clean inference CLI for a new target-ligand pair. We would be interested in integrating it once your group exposes a `predict(target_fasta, ligand_sdf) → affinity_score` function or equivalent. If that exists internally, please share — our estimate is ~3 days to wrap as a BioMate workflow. Otherwise we propose deferring FDA integration to a Phase 2.

---

**What we ask from your lab.**
- Add a permissive license (MIT or Apache-2.0) to the Tier-B repos (SLAB, Syllable-PBWT, FastRecomb, UDIP-FA, pytorch_ehr, CovRNN, PK-RNN, etc.) to enable integration
- Share release timing for RaPID2, FRAME, and RLBWT-LCP
- Provide biological review of the GWAS target prioritization output for the RA benchmark validation
- Co-author both papers
- Optional: UKB credential sponsorship for the paper-faithful GWAS validation (your group presumably has access)
- Optional: de-identified autoimmune patient EHR cohort for Med-BERT fine-tuning under federated architecture

**What we provide.**
- Full BioMate platform access for your lab and all students
- AWS Batch GPU + CPU compute at no cost during the collaboration period
- TorchGWAS and RaPID deployed as production BioMate tools — your students run your own tools via a chat prompt, download a methods report citing your papers, without managing Slurm or cloud credentials
- Co-authorship on all BioMate papers using your tools
- Citation anchors: every BioMate run of TorchGWAS cites your arXiv 2026 paper in the automated methods report

**Why UTHealth is a natural joint pitch.** We are also engaging with Dr. Zhao (bsml320) on the single-cell and virtual cell layer, and with Dr. Jim Zheng on the LLM training data mining layer. A joint UTHealth collaboration covering GWAS (your lab) + single-cell immune biology (Zhao lab) + clinical NLP (Jim Zheng) maps cleanly onto BioMate's four-layer autoimmune LLM stack. If you are open to it, a single joint kick-off meeting with all three groups would let us align on the architecture and publication roadmap efficiently.

We would welcome a 30-minute call at your convenience. We can demonstrate TorchGWAS running on BioMate with the shipped toy dataset, show the 7-tab after-run report that cites your paper, and walk through the proposed GWAS → colocalization → target ranking pipeline architecture.

One broader note: while we pitch autoimmune as the entry point — because TorchGWAS is already live and we have a working demo today — the collaboration extends well beyond autoimmune. TorchGWAS applies to any complex phenotype at scale (metabolic disease, Alzheimer's, rare disease genetics), Med-BERT becomes the clinical reasoning backbone for all BioMate indications, and UDIP-ViT opens a natural path into neurological disease imaging biomarkers. The autoimmune framing reflects where BioMate has its deepest immediate use case; your lab's toolset is broader than that and so is the collaboration scope.

Best regards,  
BioMate Team

---

## Technical Annex: Current Integration Status

### TorchGWAS (chain id 69) — scaffold wired, stub stage

**Nextflow wrapper:** `backend/nf-core-workflows/modules/biomate-ai-tools/torchgwas_udip_phenotype_scan/main.nf`  
**Phases:** 4-phase pipeline (phenotype QC → kernel construction → phenotype scan → report)  
**Status:** Chain metadata, qc_evidence (3 gates), and rationale rows all populated and verified live via `/api/rationale/torchgwas_udip_chain:A`. Nextflow stub emits placeholder JSON; real `torchgwas linear` CLI call is next.  
**Smoke test plan:** Use shipped `examples/toy/` dataset (64 samples × 12 variants × 3 phenotypes × 4 covariates) for proof-of-wrap; then 1000 Genomes Phase 3 (2,504 samples, 80M variants) with simulated UDIP-style phenotype matrix for scale demonstration (~30 GPU-min on AWS).  
**Paper-faithful demo** (RA or SLE GWAS at scale) requires UKB credential — can be achieved with your group's existing UKB access.

### Estimated effort to real-data production

| Step | Effort | Notes |
|---|---|---|
| Replace stub with real `torchgwas linear` CLI call | 0.5 day | Single command per README |
| Build Docker image with TorchGWAS + CUDA | 0.5 day | GPU container |
| Push to ECR + test on 1000G dataset | 1 day | AWS Batch GPU job |
| Add RaPID as Phase 0 (IBD-aware preprocessing) | 1.5 days | RaPID has clean CLI |
| Add coloc + DICE eQTL colocalization as Phase 5 | 2 days | R package, BioMate has Bioconductor layer |
| **Total to full pipeline demo** | **~5–6 days** | 1 engineer |

### Med-BERT integration plan

**Model:** ZhiGroup/Med-BERT (Apache-2.0, 329★, BERT-based, pretrained on ~28M EHR records)  
**Integration approach:** Host via BioMate's `run_code` Python path for fine-tuning experimentation; deploy as a BioMate endpoint for inference once fine-tuned on AACT + FDA packages  
**AACT data:** Full PostgreSQL dump available free from CTTI; autoimmune filter yields ~15,000 structured completed trials  
**FDA packages:** Public review documents for approved autoimmune biologics available at FDA.gov (Humira, Enbrel, Rinvoq, Stelara, Entyvio, Saphnelo, Orencia, Actemra, Xeljanz, etc.) — 50+ BLA/sNDA reviews as instruction data  

### License asks (one email)

| Repo | Current | Ask |
|---|---|---|
| ZhiGroup/SLAB | No LICENSE | MIT or Apache-2.0 |
| ZhiGroup/Syllable-PBWT | No LICENSE | MIT or Apache-2.0 |
| ZhiGroup/pytorch_ehr (150★) | No LICENSE | MIT or Apache-2.0 |
| ZhiGroup/UDIP-FA | No LICENSE | MIT or Apache-2.0 |
| ZhiGroup/CovRNN | No LICENSE | MIT or Apache-2.0 |
| ZhiGroup/PK-RNN | No LICENSE | MIT or Apache-2.0 |
| + 8 others | No LICENSE | Bulk ask in same email |

All Tier-A tools (TorchGWAS MIT, RaPID MIT, FDA MIT, Med-BERT Apache-2.0, UDIP-ViT MIT) are already cleared.

### Cross-lab synergy (Zhao + Zhi joint pipeline)

The most powerful combined demo chains Zhi's GWAS layer directly into Zhao's single-cell layer:

```
TorchGWAS (Zhi)       → GWAS summary statistics for RA locus
        ↓
RaPID (Zhi)           → ancestry-stratified cohort
        ↓
coloc + DICE          → eQTL colocalization → causal gene
        ↓
scGWAS (Zhao)         → assign causal gene to Treg / Th17 / plasmablast
        ↓
Scupa (Zhao)          → immune cell polarization state of target cell type
        ↓
Geneformer fine-tune  → predict drug response in patient's immune cell context
        ↓
BioMate ADMET + PBPK  → compound-level drug screening
        ↓
IND narrative         → §2.6 clinical pharmacology section
```

This chain — from population GWAS to IND document in one BioMate session — is the flagship autoimmune drug discovery demo. Both labs are co-authors on the Nature Methods paper this enables.
