# A Comprehensive Survey of Drug Target Identification Approaches

*Compiled 2026-08-17. Every citation below traces to a real paper (publisher / PubMed / PMC / regulatory record). Items not independently re-fetched, vendor self-claims, and prompt/source corrections are explicitly flagged. No DOIs are fabricated.*

**Scope.** This document is a mechanistic, honestly-caveated overview of **all major current approaches to drug target identification** — not limited to any one modality. It is organized by **approach family**: (Part A) human genetics & functional genomics; (Part B) omics-driven & network/systems biology; (Part C) AI / knowledge-graph methods and the industry platforms that operationalize them. For each family: *what it is → how it nominates a target → key tools/databases → evidence it works → strengths → limitations*, closing with an honest read on **what is actually winning now**.

**The one-sentence thesis that organizes the whole field.** Drug mechanisms with **human genetic support succeed in the clinic at ~2–2.6× the base rate** — the single best-quantified predictor of clinical success — so every method below is ultimately a strategy to do two things well: **name the causal gene, and pin the direction of effect** (gain-of-function disease → inhibitor; loss-of-function-protective → inhibitor; loss-of-function disease → activator/replacement). Everything that credentials a target against human genetics is ascendant; everything that cannot is treated as hypothesis-generating.

---

# Part A — Human Genetics & Functional Genomics

*The most direct and most clinically-validated route: use natural human variation and deliberate genetic perturbation to name a gene and its direction.*

## A0. The organizing evidence: genetic support ≈ 2–2.6× approval success

- **Nelson et al. 2015** (*Nat Genet* 47:856, [10.1038/ng.3314](https://doi.org/10.1038/ng.3314)) — the proportion of drug mechanisms with direct genetic support rises across the pipeline from **2.0% (preclinical) → 8.2% (approved)**; genetically-supported targets are **~2×** more likely to be approved. Method: mapped OMIM + GWAS gene–disease pairs onto drug target–indication pairs by MeSH similarity.
- **King, Davis & Degner 2019** (*PLoS Genet* 15:e1008489, [10.1371/journal.pgen.1008489](https://doi.org/10.1371/journal.pgen.1008489)) — independent replication; confirms the ~2× effect from Phase I to approval.
- **Minikel et al. 2024** (*Nature* 629:624, [10.1038/s41586-024-07316-0](https://doi.org/10.1038/s41586-024-07316-0), PMID 38632401) — current state of the art: **relative success 2.6×**; the effect **grows with confidence in the causal gene**, varies by therapy area/phase, but is **largely independent of effect size, allele frequency, and year of discovery**. Conclusion: the field is "far from peak genetic insight."

This is why "which gene is causal, and how sure am I" — the output of L2G/coloc/MR/burden below — is the currency of modern target discovery.

## A1. GWAS → gene mapping (the core problem)

**Mechanism.** A GWAS returns an *associated locus* (an LD block of correlated SNPs), not a target. ~90% of trait-associated variants are **non-coding**, acting through *cis*-regulatory DNA to change expression, not protein sequence (**Maurano et al. 2012**, *Science* 337:1190, [10.1126/science.1222794](https://doi.org/10.1126/science.1222794)). Two hard sub-problems: **fine-mapping** (LD means the lead SNP is rarely causal → statistical fine-mapping with SuSiE/FINEMAP/CAVIAR reduces a locus to a **credible set** with posterior inclusion probabilities) and the **nearest-gene problem** (enhancers skip nearby genes, act over >1 Mb, hit multiple genes, are cell-type-specific — distance is a prior, not proof). Closing the gap requires integrating distance + coding consequence (VEP) + molecular-QTL colocalization + chromatin contact + causal-direction (MR). Reviewed in **Cano-Gamez & Trynka 2020** (*Front Genet* 11:424, [10.3389/fgene.2020.00424](https://doi.org/10.3389/fgene.2020.00424)).

**Limits.** Causal-variant resolution is LD-bound; regulatory effects are context-specific; QTL catalogs miss the right cell state; no single evidence line is decisive.

## A2. Locus-to-Gene (L2G) — ML prioritization

**Paper.** **Mountjoy et al. 2021**, *Nat Genet* 53:1527, [10.1038/s41588-021-00945-5](https://doi.org/10.1038/s41588-021-00945-5). *(Correction: the actual title is "An open approach to systematically prioritize causal variants and genes at all published human GWAS trait-associated loci," not the commonly-miscited "annotating and prioritizing… at scale" string.)*

**Mechanism.** A **gradient-boosting classifier** scores each gene near a fine-mapped credible set for probability of being the causal effector → an **L2G score 0–1**. Features (weighted by variant posterior probability): TSS distance (absolute + relative to neighbors), molecular-QTL colocalization (eQTL/pQTL/sQTL summarized as CLPP/H4), VEP consequence severity, enhancer–promoter chromatin contact, local gene density, credible-set confidence. Trained on gold-standard positives (curated causal loci + ChEMBL Phase III/IV drug targets + high-confidence ClinVar/UniProt/Gene2Phenotype/PanelApp/ClinGen). Now runs in the open-source **Gentropy** pipeline with **Shapley values** exposed per prediction.

**Strengths/limits.** Recovers held-out ChEMBL Ph III/IV targets; genome-scale, calibrated, open. But only as good as its QTL/chromatin inputs (tissue gaps), trained on known biology (may under-rank novel mechanisms), and distance remains a dominant feature (inherits nearest-gene bias where functional data are sparse).

## A3. Colocalization (eQTL/pQTL coloc) and SMR

- **coloc** — **Giambartolomei et al. 2014**, *PLoS Genet* 10:e1004383, [10.1371/journal.pgen.1004383](https://doi.org/10.1371/journal.pgen.1004383). Bayesian test over 5 hypotheses; **PP.H4** = one shared causal variant drives both the GWAS signal and a molecular QTL (the effector-gene nomination); **PP.H3** = two distinct LD variants (the false positive it guards against). **pQTL coloc is one step closer to the druggable entity** than eQTL; **cis-pQTLs** are strongest.
- **SMR + HEIDI** — **Zhu et al. 2016**, *Nat Genet* 48:481, [10.1038/ng.3538](https://doi.org/10.1038/ng.3538). Treats the top eQTL as an MR instrument for expression→trait; HEIDI separates a single shared causal variant (causality) from linkage. Prioritized e.g. TRAF1/ANKRD55 (RA), SNX19/NMRAL1 (schizophrenia).

**Tools/DBs.** `coloc`, SMR/HEIDI; GTEx & eQTLGen (eQTL); deCODE / UKB-Olink / SomaScan (pQTL); embedded as L2G features in Open Targets. **Limits:** classic coloc assumes one causal variant per locus (fixed by SuSiE-coloc/conditioning); needs large QTL samples in the *right* tissue; gives a shared variant but not causal direction (MR adds that).

## A4. Mendelian Randomization (drug-target / cis-MR)

**Framework.** **Schmidt et al. 2020**, *Nat Commun* 11:3255, [10.1038/s41467-020-16969-0](https://doi.org/10.1038/s41467-020-16969-0); practical guide **Gill, Burgess et al. 2021**, *Wellcome Open Res* 6:16, [10.12688/wellcomeopenres.16544.2](https://doi.org/10.12688/wellcomeopenres.16544.2).

**Mechanism.** Germline variants randomized at conception act as **instrumental variables** for an exposure (protein/expression level) — a lifelong natural RCT free of reverse causation/confounding. **Drug-target cis-MR** instruments the exposure with variants **in/near the target's gene**, so the genetic perturbation mimics drugging that protein → predicts **direction + magnitude** of the disease effect (efficacy *and* on-target safety) before a trial. *Cis* restriction anchors the no-horizontal-pleiotropy assumption.

**Canonical proofs.** **PCSK9/HMGCR** (cis-LDL-lowering variants → lower CHD, mirroring statins & anti-PCSK9 mAbs; foundation **Cohen et al. 2006**, *NEJM* 354:1264, [10.1056/NEJMoa054013](https://doi.org/10.1056/NEJMoa054013) — PCSK9 LoF → ~88% CHD reduction; MR also flagged the on-target T2D liability); **IL6R** (Asp358Ala mimics tocilizumab; **IL6R MR Consortium 2012**, *Lancet* 379:1214, [10.1016/S0140-6736(12)60110-X](https://doi.org/10.1016/S0140-6736(12)60110-X)); **IL23R** (protective LoF R381Q validated ustekinumab; **Di Meglio et al. 2011**, *PLoS ONE* 6:e17160, [10.1371/journal.pone.0017160](https://doi.org/10.1371/journal.pone.0017160)).

**Limits.** Three IV assumptions; horizontal pleiotropy is the main threat (cis reduces but doesn't eliminate; run coloc alongside); estimates a *lifelong average* effect (≠ a drug's dose/timing).

## A5. Rare-variant burden / exome association (names the gene directly)

**Mechanism.** Single rare variants are too infrequent for GWAS; gene-based tests **collapse all rare variants in a gene** into one unit, naming the **gene = the target**: burden/collapsing (CMC), variance-component **SKAT**, and the data-driven optimal mixture **SKAT-O**. **LoF variants = "natural knockouts"** — a lifelong human analog of pharmacological inhibition; if LoF carriers show a *desirable* phenotype, inhibition is a de-risked hypothesis: **PCSK9** (low LDL, CAD protection), **ANGPTL3** (familial hypolipidemia → evinacumab, [10.1056/NEJMoa2004215](https://doi.org/10.1056/NEJMoa2004215)), **SLC30A8** (LoF *protects* from T2D → direction is inhibition).

**Strengths/limits.** Names the gene + gives direction + a human tolerability read in one shot; needs 100k+ exomes; the "qualifying variant" definition (LoF-only vs +missense) strongly drives results; loses power under mixed-direction effects.

## A6. Mendelian disease genes (OMIM)

**Mechanism.** A gene that *causes* a monogenic disease proves perturbing it moves human physiology. Match the **direction** (GoF disease → inhibitor; LoF → activator/replacement; dominant-negative → caution). An **allelic series** (mild→severe variants → graded phenotypes) is a **human dose-response curve**. OMIM: **Amberger et al. 2019**, *NAR* [10.1093/nar/gky1151](https://doi.org/10.1093/nar/gky1151); direction-of-effect systematized in **npj Drug Discovery 2025** ([10.1038/s44386-025-00027-0](https://doi.org/10.1038/s44386-025-00027-0)). **Limits:** monogenic biology may not translate to common-disease dosing.

## A7. The substrate & integration layer (biobanks + platforms)

**Biobanks:**

| Biobank | Scale | Value for target ID |
|---|---|---|
| **UK Biobank** | ~500k; 454,787 exomes (**Backman 2021**, [10.1038/s41586-021-04103-z](https://doi.org/10.1038/s41586-021-04103-z)); ~490k WGS | deep phenotyping + EHR; substrate for Genebass/AZ PheWAS |
| **FinnGen** | ~520k (DF12); 224,737 in Nature 2023 (**Kurki 2023**, [10.1038/s41586-022-05473-8](https://doi.org/10.1038/s41586-022-05473-8)) | **founder/bottleneck population** → deleterious alleles enriched → rare-variant power |
| **Regeneron/Geisinger (DiscovEHR/MyCode)** | 50,726 exomes (2016); ~355k consented | exome + linked EHR; PCSK9-lowering heritage |
| **All of Us** | 245,388 WGS (2024, [10.1038/s41586-023-06957-x](https://doi.org/10.1038/s41586-023-06957-x)); goal ≥1M | **diversity** (77% under-represented) → cross-ancestry replication |

**Exome/phenome portals.** **Genebass** (**Karczewski et al. 2022**, *Cell Genomics* [10.1016/j.xgen.2022.100168](https://doi.org/10.1016/j.xgen.2022.100168), PMID 36778668) — SAIGE-GENE across 4,529 phenotypes × 394,841 UKB exomes; **AZ PheWAS Portal** (**Wang et al. 2021**, *Nature* [10.1038/s41586-021-03855-y](https://doi.org/10.1038/s41586-021-03855-y)) — collapsing analysis, 281,104 exomes, **1,703 gene–phenotype hits (median OR 12.4), 83% invisible to single-variant tests** (the headline argument for gene-based tests).

**Integration layer.** **Open Targets Platform** aggregates GWAS + rare-variant + Mendelian + functional + literature into scored target–disease associations (**Ochoa 2023** *NAR* [10.1093/nar/gkac1046](https://doi.org/10.1093/nar/gkac1046); 2025 update [10.1093/nar/gkae1064](https://doi.org/10.1093/nar/gkae1064)). **Key 2024 change: Open Targets Genetics was deprecated and merged into the unified Platform**, which now natively carries GWAS credible sets, the L2G model, direction-of-effect, PROTACtability, and AlphaFold structures. **GWAS Catalog** (**Sollis 2023** *NAR* [10.1093/nar/gkac1010](https://doi.org/10.1093/nar/gkac1010)) feeds L2G/coloc; **PheWAS** inverts GWAS (fix a gene, scan all phenotypes) to reveal pleiotropy = on-target side-effect prediction.

## A8. Functional genomics — perturbation screens (deliberate genetic KO/KD/activation)

- **Genome-wide CRISPR-KO** — pooled sgRNA library into Cas9+ cells; dropout = essential/required, enrichment = resistance. Foundational: **Shalem 2014** (*Science* 343:84, [10.1126/science.1247005](https://doi.org/10.1126/science.1247005), GeCKO); **Wang 2014** (*Science* 343:80, [10.1126/science.1246981](https://doi.org/10.1126/science.1246981)); sgRNA design **Doench 2016 Rule Set 2** ([10.1038/nbt.3437](https://doi.org/10.1038/nbt.3437)); hit-calling **MAGeCK, Li 2014** ([10.1186/s13059-014-0554-4](https://doi.org/10.1186/s13059-014-0554-4)). **Limit:** cutting at high-copy loci causes a DNA-damage **copy-number artifact** (false essentiality), corrected by CERES/Chronos.
- **CRISPRi / CRISPRa** — catalytically-dead dCas9; **dCas9-KRAB** (tunable knockdown, models drug inhibition better than a full null and avoids the cutting artifact), **dCas9-activators** (uniquely nominate gain-of-function/overexpression targets). **Qi 2013** ([10.1016/j.cell.2013.02.022](https://doi.org/10.1016/j.cell.2013.02.022)); **Gilbert 2014** ([10.1016/j.cell.2014.09.029](https://doi.org/10.1016/j.cell.2014.09.029)); **Horlbeck 2016** (*eLife*, [10.7554/eLife.19760](https://doi.org/10.7554/eLife.19760)).
- **Perturb-seq** — CRISPR perturbation with single-cell-transcriptome readout: turns "does KO kill?" into "what pathway is this gene in?" **Dixit 2016** ([10.1016/j.cell.2016.11.038](https://doi.org/10.1016/j.cell.2016.11.038)); **Adamson 2016** ([10.1016/j.cell.2016.11.048](https://doi.org/10.1016/j.cell.2016.11.048)); genome-scale **Replogle 2022** (*Cell* 185:2559, [10.1016/j.cell.2022.05.013](https://doi.org/10.1016/j.cell.2022.05.013), PMID 35688146, >2.5M cells).
- **RNAi** — the CRISPR predecessor; seed-region off-target silencing (**Jackson 2003**, [10.1038/nbt831](https://doi.org/10.1038/nbt831)) drove the field to CRISPR after 2014; legacy datasets remain minable.
- **In vivo CRISPR screens** — capture microenvironment/immune selection; **Manguso 2017** (*Nature* 547:413, [10.1038/nature23270](https://doi.org/10.1038/nature23270)) nominated **PTPN2** as a checkpoint-immunotherapy target.
- **Base-/prime-editing screens (variant-to-function)** — ask "what does *this nucleotide* do," classifying VUS and saturation-mutagenizing residues. **Hanna 2021** (*Cell* 184:1064, [10.1016/j.cell.2021.01.012](https://doi.org/10.1016/j.cell.2021.01.012)) *(correction: Cell, not Science)*; benchmark **Findlay 2018** BRCA1 saturation genome editing (*Nature* 562:217, [10.1038/s41586-018-0461-z](https://doi.org/10.1038/s41586-018-0461-z)).

## A9. Genetic-perturbation → target logic (turning screens into nominations)

- **DepMap / Project Achilles** — genome-scale CRISPR-KO across 1,000+ cancer lines; each gene×line gets a **gene-effect score**. The nomination logic: **pan-essential** genes (ribosome/proteasome) are *bad* targets (toxic, no window); **selective dependencies** (essential only in a biomarker-defined subset) are *the* nominations. Defining paper **Tsherniak 2017** (*Cell* 170:564, [10.1016/j.cell.2017.06.010](https://doi.org/10.1016/j.cell.2017.06.010)); scoring **CERES, Meyers 2017** ([10.1038/ng.3984](https://doi.org/10.1038/ng.3984)) → **Chronos, Dempster 2021** ([10.1186/s13059-021-02540-7](https://doi.org/10.1186/s13059-021-02540-7)). Sanger counterpart **Project Score, Behan 2019** (*Nature* 568:511, [10.1038/s41586-019-1103-9](https://doi.org/10.1038/s41586-019-1103-9)). Toxicity logic formalized in **Chang et al. 2020** (*Cancer Cell* 38:171, [10.1016/j.ccell.2020.12.017](https://doi.org/10.1016/j.ccell.2020.12.017)).
- **Synthetic lethality** — drug the SL partner of an undruggable tumor loss → selective kill. **PARP/BRCA** is the validated paradigm: **Bryant 2005** ([10.1038/nature03443](https://doi.org/10.1038/nature03443)) + **Farmer 2005** ([10.1038/nature03445](https://doi.org/10.1038/nature03445)) → **olaparib FDA-approved Dec 2014** with companion Dx. **WRN–MSI**: two screens ranked **WRN** the top dependency in MSI cancers (**Chan 2019**, *Nature* 568:551, [10.1038/s41586-019-1102-x](https://doi.org/10.1038/s41586-019-1102-x); Behan 2019) → WRN inhibitors now clinical.
- **Dependency / co-dependency mapping** — correlate a gene's dependency profile with genomic features (→ biomarker) or with another gene (→ paralog buffering): **MAGOH/MAGOHB** (**Viswanathan 2018**, [10.1038/s41588-018-0155-3](https://doi.org/10.1038/s41588-018-0155-3)), **VPS4A/VPS4B** (**Neggers 2020**, [10.1016/j.celrep.2020.108493](https://doi.org/10.1016/j.celrep.2020.108493)) — exploiting collateral lethality from passenger deletions.
- **Cell-context specificity** — **oncogene addiction** (**Weinstein 2002**, [10.1126/science.1073096](https://doi.org/10.1126/science.1073096); BCR-ABL→imatinib, BRAF-V600E→vemurafenib — highest-confidence class) and **lineage dependency** (**Garraway & Sellers 2006**, [10.1038/nrc1947](https://doi.org/10.1038/nrc1947); SOX10/MITF in melanoma).

---

# Part B — Omics-Driven & Network / Systems-Biology Approaches

*Nominate candidates from the molecular readouts of disease, then consolidate scattered hits into modules and mechanisms. Strongest when the output is credentialed against genetics (Part A).*

## B1. Transcriptomics

- **Differential expression (DE)** — negative-binomial GLMs with empirical-Bayes shrinkage: **DESeq2** ([10.1186/s13059-014-0550-8](https://doi.org/10.1186/s13059-014-0550-8)), **edgeR** ([10.1093/bioinformatics/btp616](https://doi.org/10.1093/bioinformatics/btp616)), **limma-voom** ([10.1186/gb-2014-15-2-r29](https://doi.org/10.1186/gb-2014-15-2-r29)). First-pass shortlist; **limit:** bulk DE averages over cell types, significance ≠ causal ≠ druggable, mRNA ≠ protein.
- **WGCNA / co-expression modules** — soft-threshold → TOM → modules (eigengenes); targets via module–trait correlation, **hub genes** (kME), module preservation (Zsummary). **Langfelder & Horvath 2008** ([10.1186/1471-2105-9-559](https://doi.org/10.1186/1471-2105-9-559)). **Limit:** correlation ≠ causation; composition-confounded.
- **Connectivity / reverse-signature (CMap & LINCS L1000)** — a perturbagen whose signature **anti-correlates** with the disease signature is predicted to revert it (nominating drug + genetic MOA). **Lamb 2006** (*Science* [10.1126/science.1132939](https://doi.org/10.1126/science.1132939)); **Subramanian 2017** (*Cell* [10.1016/j.cell.2017.10.049](https://doi.org/10.1016/j.cell.2017.10.049)); query via Broad CLUE. **Limit:** cell-line ≠ disease tissue; correlational.
- **Master-regulator / driver activity (ARACNe · MARINa · VIPER)** — infers a regulator's *activity* from its regulon's collective differential expression, surfacing drivers whose *own mRNA is unchanged*. **ARACNe** ([10.1186/1471-2105-7-S1-S7](https://doi.org/10.1186/1471-2105-7-S1-S7)); **VIPER, Alvarez 2016** (*Nat Genet* [10.1038/ng.3593](https://doi.org/10.1038/ng.3593)). Per-sample (VIPER/OncoTarget/OncoTreat) → patient-level prioritization.

## B2. Proteomics & other omics (closer to the druggable layer)

- **Mass-spec proteomics (DDA/DIA/TMT)** — quantifies the actual druggable molecule; **DIA** (Orbitrap Astral/timsTOF + DIA-NN) is now the default, near-transcriptome depth. **Limit:** dynamic range; abundance ≠ activity.
- **Phosphoproteomics / kinase-activity inference** — substrate-based inference (KSEA; **Wiredja 2017** [10.1093/bioinformatics/btx415](https://doi.org/10.1093/bioinformatics/btx415); PhosX 2024) flags hyperactivated/bypass kinases.
- **Proteogenomics (CPTAC)** — matched genomics + transcriptomics + (phospho)proteomics filters genomic hits for protein-level over-expression/hyperactivation; **Savage et al. 2024** (*Cell* 187:4389, [S0092-8674(24)00583-X](https://www.cell.com/cell/fulltext/S0092-8674(24)00583-X), PMID 38917788) — the leading rigorous multi-omic nomination framework (beats transcript-only).
- **Chemoproteomics / target deconvolution (TPP-CETSA, ABPP)** — identify the *direct* target of a small molecule in native proteomes: **TPP** (**Savitski 2014**, *Science* 346:1255784, [10.1126/science.1255784](https://www.science.org/doi/10.1126/science.1255784), PMID 25278616 — staurosporine engaged >50 kinases; ferrochelatase off-target explained vemurafenib phototoxicity); **ABPP** (Cravatt). The go-to for deconvolving phenotypic-screen hits, covalent ligands, PROTAC/molecular-glue programs.
- **Metabolomics** — perturbed metabolite pools → responsible enzymes/transporters. **Limit:** metabolite→enzyme mapping is ambiguous.
- **Epigenomics (ATAC/ChIP/methylation; super-enhancers)** — nominate epigenetic readers/writers/erasers (BRD4, EZH2) and **super-enhancer**-addicted oncogenes/master TFs (BET/BRD4 inhibitors).

## B3. Single-cell & spatial

- **Cell-type-specific target ID (scRNA-seq)** — is a gene cell-type-specific in healthy tissue (cleaner target) and over-expressed in a disease cell type; doubles as a **safety filter** (expression in a vital cell type → predicted on-target toxicity). scRNA-supported genes enrich for clinical success (Open Targets scRNA framework).
- **Disease-associated cell states** — a pathogenic state's up-regulated surface/secreted/TF genes become candidates; state abundance is a built-in PD marker (DAM → **TREM2**, now an active CNS target; **Keren-Shaul 2017**, [10.1016/j.cell.2017.05.018 / S0092-8674(17)30578-0]). Differential abundance via **Milo** ([10.1038/s41587-021-01033-z](https://www.nature.com/articles/s41587-021-01033-z)).
- **Cell–cell interaction / ligand–receptor** — CellPhoneDB, **NicheNet** ([10.1038/s41592-019-0667-5](https://www.nature.com/articles/s41592-019-0667-5), links sender ligands to receiver target genes → causal ranking), CellChat. **Limit:** co-expression ≠ physical binding; needs spatial confirmation.
- **Spatial transcriptomics** — *where* a target is expressed, which niches form; validates L-R adjacency. Visium/Slide-seq (coverage) vs MERFISH/Xenium/CosMx (single-cell). **Limit:** resolution-vs-coverage tradeoff; correlative.

## B4. Multi-omics integration

Taxonomy: **early** (concatenate), **intermediate/joint** (shared latent space — dominant for target-ID), **late**. Core methods: **MOFA/MOFA+** (Bayesian PCA-generalization; factors → drivers; **Argelaguet 2018/2020**, [10.15252/msb.20178124](https://doi.org/10.15252/msb.20178124), [10.1186/s13059-020-02015-1](https://doi.org/10.1186/s13059-020-02015-1)); **SNF** (fuse patient-similarity networks; **Wang 2014**, *Nat Methods* [10.1038/nmeth.2810](https://www.nature.com/articles/nmeth.2810)); **iCluster/iClusterBayes** (joint latent-variable with feature selection; **Shen 2009**, **Mo 2018**); **MOGONET** (per-omic GCNs + view-correlation; **Wang 2021**, [10.1038/s41467-021-23774-w](https://www.nature.com/articles/s41467-021-23774-w)). *(These same methods recur in the stratification survey — there they define patient subtypes; here their sparse loadings/selected features name driver targets.)*

## B5. Network & systems biology

- **PPI networks** — disease proteins cluster in interactome neighborhoods; rank by degree/betweenness/centrality. STRING ([10.1093/nar/gkac1000-class], 2025 release adds regulation directionality), BioGRID, IntAct, HuRI. **Limit:** interactome is incomplete/study-biased (well-studied proteins look like hubs).
- **Network propagation / RWR** — seed signal (GWAS/DE/mutation) diffuses over edges; genes near many seeds score high (HotNet2, DIAMOnD). Unifying review **Cowen et al. 2017** (*Nat Rev Genet* 18:551, [10.1038/nrg.2017.38](https://doi.org/10.1038/nrg.2017.38)). **Limit:** inherits interactome bias; needs degree correction.
- **Key Driver Analysis (KDA)** — overlay disease genes on data-driven networks; genes whose neighborhood is disease-enriched are candidate master regulators (Mergeomics; **Shu 2016** [10.1186/s12864-016-3198-9](https://link.springer.com/article/10.1186/s12864-016-3198-9)).
- **Pathway/GO enrichment (GSEA)** — MOA context for candidates (**Subramanian 2005**, *PNAS* [10.1073/pnas.0506580102](https://www.pnas.org/doi/10.1073/pnas.0506580102)).
- **GRN inference (GENIE3 · SCENIC · VIPER)** — reconstruct TF→target edges; single-cell SCENIC/VIPER shift target-ID to "which gene, in which cell state."
- **Network medicine (Barabási)** — disease-module hypothesis + **drug-target–module proximity** for repurposing/nomination (**Barabási 2011**, [10.1038/nrg2918](https://www.nature.com/articles/nrg2918); **Guney 2016**, [10.1038/ncomms10331](https://www.nature.com/articles/ncomms10331)).

---

# Part C — AI / Knowledge-Graph Methods & the Industry Platforms

*How computational-first companies operationalize the above — and, honestly, how little of it has yet produced a validated novel target with human efficacy.*

## C1. Method families (how AI/KG nominates targets)

- **Biomedical knowledge graphs** — ingest genes/proteins/diseases/drugs/trials/literature as typed nodes+edges; query graph patterns + embeddings to surface mechanistic hypotheses. Operationalized by **BenevolentAI** (below).
- **Literature-based discovery / LLMs over text** — mine publications/patents/trials for latent gene–disease links and novelty scoring (Insilico's NLP layer; emerging LLM agents).
- **Deep target-prediction & structure/druggability** — protein language models (BioMap's xTrimoPGLM), AlphaFold-family structure prediction (Isomorphic), cofolding/pose models (Genesis Pearl, Iambic NeuralPLexer) — mostly *target-adjacent* (how to drug a chosen target), not de-novo target ID.
- **Phenomics / perturbation-at-scale** — Recursion's image-based maps of biology; Cellarity's cell-state models; hypothesis-free gene–gene/gene–compound nomination.
- **Federated multi-omics** — Owkin's TargetMATCH across hospital pathology+omics without pooling data.
- **Causal ML + functional genomics** — Relation's "Lab-in-the-Loop" causal graph models validated by CRISPR.

## C2. Verified industry scorecard (as of 2026-08-17)

**Genuine target-ID engines:** Insilico/PandaOmics, BenevolentAI, Recursion, Verge, Owkin, Relation, Cellarity, BioMap (partial). **Molecule-design/structure companies that work *known* targets (not target-ID):** Genesis, Iambic, Isomorphic, Nimbus.

| Company | True target-ID? | What it really is | Most-validated evidence | Furthest clinical stage |
|---|---|---|---|---|
| **Insilico / PandaOmics** | **Yes** | multi-omics causal + literature NLP → target, + generative chemistry | **Novel target (TNIK) → peer-reviewed +Ph2 → Ph3** | **Phase 3** |
| **BenevolentAI** | **Yes** | biomedical knowledge graph | baricitinib COVID repurposing (NEJM/FDA EUA); AZ partner targets | (repurposed drug) |
| **Recursion (+Exscientia)** | **Yes** (phenomics) | image-based maps of biology | early REC-4881/REC-617 signals; 3 Ph2 discontinued 2025 | Phase 1/2 |
| **BioMap** | Partial | protein foundation models (xTrimoPGLM) | *Nature Methods* 2025 (tech, no drug); Sanofi deal | Preclinical |
| **Cellarity** | **Yes** (cell-state) | cell-state-transition models | *Science* 2025 (hit-recovery benchmark); Novo deal; CLY-124 Ph1 | Phase 1 (no efficacy) |
| **Verge** | **Yes** (human tissue) | human-CNS-tissue multi-omics | PIKfyve→VRG50635 ALS; positive Ph1 safety | Phase 1b |
| **Valo** | Yes (claimed) | end-to-end "Opal" human-data platform | OPL-0401 **Phase 2 FAILED (Dec 2024)**, shelved; SPAC collapsed 2021 | (Ph2 miss) |
| **Owkin** | **Yes** (federated) | federated pathology+omics; diagnostics | **peer-reviewed + CE-IVD** MSIntuit dx; no named clinical target | Diagnostic (dx spun out to Waiv 2026) |
| **Genesis** | **No** | generative molecule design (GEMS) | Pearl structure benchmark (preprint); no clinical asset | none |
| **Iambic** | **No** | molecule design + structure ML | NeuralPLexer (*Nat Mach Intell* 2024); IAM1363 Ph1 (HER2) | Phase 1 |
| **Isomorphic** | **No** (structure-enabling) | AlphaFold-based design | AlphaFold 3 (*Nature* 2024); ~$3B Lilly/Novartis deals | **none (no dosed patients)** |
| **Relation** | **Yes** (causal ML) | Lab-in-the-Loop causal + functional genomics | GSK (2-stage) & Novartis deals; MORGAN FM | Preclinical |
| **Nimbus** | **No** (known targets) | FEP+/Schrödinger structure-based design | **zasocitinib Ph3 head-to-head win (2026)**; Takeda $4B | **Phase 3** |

**Verified corrections carried through (do not repeat these common errors):**
1. **Insilico's TNIK/rentosertib** is the *only* AI-nominated *novel* target with a positive peer-reviewed Phase 2 — and even there, FVC efficacy was a *secondary* endpoint in a small China-only trial (*Nat Biotechnol* 2024 [10.1038/s41587-024-02143-0](https://www.nature.com/articles/s41587-024-02143-0); *Nat Med* 2025 [10.1038/s41591-025-03743-2](https://www.nature.com/articles/s41591-025-03743-2), PMID 40461817); **Phase 3 initiated Jul 2026**.
2. **BioMap–BMS deal is unverifiable** — the widely-cited "BMS AI-protein deal (~$400M, Dec 2024)" was with **AI Proteins, Inc.**, a different company.
3. **"GS-100" is Grace Science's NGLY1 gene therapy, not Genesis Therapeutics'** — Genesis has no named clinical asset.
4. **Verge's ALS co-development partner is Ferrer** (Mar 2024), *not* Eli Lilly.
5. **Cellarity's lead is CLY-124** (DCN1 inhibitor, SCD; Ph1 dosed Jun 2025), *not* "CLTY-2003."
6. **Firsocostat IS the Nimbus/Gilead ACC molecule** (correcting a common misattribution); **Iambic "IAM-H1"** is not a distinct program (a HER2 database entry, likely = IAM1363).

**The honest bottom line for Part C:** *No AI platform has yet demonstrated human **efficacy** from an AI-nominated **novel** target.* Insilico's TNIK is the cleanest arc (novel target → +Ph2 → Ph3, pending the real Ph3 test); Nimbus's zasocitinib and Iambic's IAM1363 are the strongest *clinical* results but validate **molecule design on established targets**, not target discovery; Owkin's best evidence is a **diagnostic**; Recursion, despite the largest dataset, has **no Phase-2 efficacy win** from a self-nominated target. Platform-productivity claims across all companies remain `[vendor claim]` pending mature clinical outcomes.

*(Full per-company detail — mechanism, deal terms, trial IDs, and ~40 verified reference URLs — is in the source dossiers under `docs/`/the VCC repo; the two independent industry surveys used here [14-company and 6-company] cross-checked every load-bearing figure against a primary source and flagged all bot-blocked pages.)*

---

# Cross-Cutting: The Winning Integrated Workflow (2024–2026)

Across all three parts the same meta-pattern recurs — no single method wins; the strongest programs chain them:

1. **Human genetics is the anchor** (best single predictor of clinical success; ~2/3 of approvals genetically supported). *Name the causal gene, pin the direction.*
2. **Single-cell / spatial adds "which cell type / state"** — now expected, not optional; doubles as a safety filter.
3. **Omics (transcript → protein → metabolite → epigenome)** nominate candidates; **protein/activity-level** evidence (proteogenomics, VIPER, phospho, chemoproteomics) outranks transcript-only.
4. **Networks add mechanism/context** (propagation, KDA, module proximity) and turn scattered hits into modules + repurposing hypotheses.
5. **Perturbation (CRISPR screens, Perturb-seq, DepMap, TPP-CETSA)** converts markers into *tested dependencies* and deconvolves direct targets.
6. **Direction-of-effect + modality + structure** (Open Targets, AlphaFold, PROTACtability) decide what is actually actionable.

**Integration platforms — Open Targets above all — rather than any single method are what practitioners actually deploy.** AI/KG platforms are a fast-moving frontier that so far augments, not replaces, this genetics-anchored pipeline; the field's honest state is that **topology narrows the list, but genetics + structure + modality decide what's actionable** — and human efficacy from a purely AI-discovered novel target is still pending.

---

## Verification & honesty notes

- **Independently verified this session:** the genetic-support literature (Nelson/King/Minikel), L2G/coloc/SMR/cis-MR primary papers, Genebass/AZ-PheWAS/FinnGen, DepMap/Project-Score/CERES/Chronos, PARP-BRCA & WRN-MSI synthetic lethality, base-editing variant-to-function, the core omics/network tool papers (DESeq2/edgeR/voom, WGCNA, CMap/L1000, VIPER, MOFA/SNF/iCluster/MOGONET, STRING, Cowen, GSEA, Barabási/Guney), and the industry-platform facts + corrections above (each load-bearing figure cross-checked against a primary source).
- **Prompt/source corrections surfaced:** Mountjoy L2G title; Hanna 2021 = *Cell* not *Science*; BioMap–BMS (→ AI Proteins); GS-100 (→ Grace Science); Verge partner (→ Ferrer); Cellarity lead (→ CLY-124); firsocostat = Nimbus ACC molecule; IAM-H1 ≈ IAM1363.
- **Flagged lower-confidence (confirm exact DOI before formal manuscript use):** SKAT/SKAT-O primary DOIs (Wu 2011, Lee 2012); SLC30A8 (Flannick 2014); some deconvolution/compositional tool DOIs; a few exact STRING/HuRI/iClusterPlus paginations; all `[vendor claim]` platform metrics. Publisher bot-blocks (Science/Cell/AACR/FDA) were cross-verified via PMC/PubMed. **No DOIs were fabricated.**

*Companion document: `docs/20260817_PATIENT_STRATIFICATION_SURVEY.md`.*
