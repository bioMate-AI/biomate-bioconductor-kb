# Multi-Omics Integration — Methods Survey + Per-Disorder State of the Art

**Last updated:** 2026-10-08
**Maintained:** living survey; add methods/papers as they appear. Part of
[[20261008_LIVING_REFERENCES_INDEX]]. Datasets referenced live in
`20261008_MULTIOMICS_PUBLIC_DATASETS.md`.
**Integrity:** [[feedback_citation_integrity]] — citations verified against primary literature
2026-10-08; items that could not be confirmed are flagged **(verify)**.
**Confidentiality:** public literature only — safe for community / website blog use
([[feedback_website_no_internal_work]]). No internal methods or targets.
**Relation to existing BioMate docs (expand, don't duplicate):**
`20260502_VIRTUAL_CELL_MODELING_SURVEY.md`, `20260706_SLE_FOUNDATION_MODEL_SURVEY_AND_PROPOSAL.md`,
`20260706_SLE_GENEFORMER_ADAPTATION_SURVEY.md`, `20260727_HARMONIZATION_SURVEY.md`,
`20260727_MULTIOMICS_BENCHMARK_DESIGN.md`; memory [[project_multiomics_benchmark]],
[[project_alignment_qc_direction]], [[project_vcm_program]], [[project_perturbation_baseline_consensus]].

> Organized in three paradigms — (A) linear/traditional, (B) knowledge/graph, (C) foundation-model /
> "virtual cell" — then a task-fit synthesis, then per-disorder current ability.

---

## A. Linear / traditional statistical approaches
Premise: shared cross-omics signal lives in a low-dimensional linear(-latent) subspace. Interpretable, sample-efficient, default for bulk cohorts.

| Method | Omics | Approach | Problem solved | Pros | Cons | Future work |
|---|---|---|---|---|---|---|
| **MOFA / MOFA+** (Argelaguet 2018; 2020) | RNA, methylation, CNV, proteomics, metabolomics; MOFA+ sc + groups | Bayesian group factor analysis; per-factor %variance per modality | Unsupervised axes of variation + which layer drives each | Interpretable variance decomposition; handles missing modalities; scalable | Linear; unsupervised; factor sign/scale unidentifiable | MEFISTO (spatial/temporal); factor selection |
| **iCluster(+/Bayes)** (Shen 2009; Mo 2013; 2018) | CNV, mutation, methylation, mRNA (mixed dists) | Joint latent-variable model; clusters from latent | Integrative cancer subtype discovery | Principled; feature selection; mixed types | Heavy compute; tuning; scales poorly | Faster inference |
| **SNF** (Wang 2014) | Any → patient similarity | Per-modality patient networks fused via cross-diffusion; spectral cluster | Subtyping leveraging complementary signal | Nonlinear fusion; noise-robust; feature spaces need not align | Sample-level only (no biomarkers); kNN/σ sensitive | Feature attribution; sc extensions |
| **DIABLO / mixOmics** (Rohart 2017; Singh 2019) | mRNA, miRNA, CpG, protein, metabolite | Multi-block sparse PLS-DA | Supervised integration + biomarker panels | Sparse interpretable signature; classification | Needs labels; linear; selection unstable | Stability selection; sc/longitudinal |
| **JIVE** (Lock 2013) | Multiple matrices, shared samples | Joint + individual + noise decomposition | Separate shared vs modality-specific | Clean partition | Rank selection; linear; scaling | AJIVE; nonlinear/sparse |
| **CCA / sparse CCA** (Hotelling 1936 **(verify)**; Witten 2009) | 2+ feature matrices | Max cross-modality correlation (+L1/L2) | Coordinated variation between layers | Classic; sparse=interpretable | Breaks p>n w/o reg; linear; pairwise | Deep/kernel CCA |
| **WGCNA** (Langfelder & Horvath 2008) | Co-expression (+extend) | Weighted correlation modules → eigengenes → trait | Module discovery + phenotype association | Interpretable modules/hubs | Correlation not joint model; single-modality core | Multi-omics modules; causal |
| **NMF / jNMF / intNMF** (Lee & Seung 1999; Chalise 2017) | Non-negative matrices | Shared coefficient factorization | Parts-based integrative clustering | Additive/interpretable; no dist. assumptions | Non-negativity; local optima; rank | Robust init; graph-regularized |
| **scVI / totalVI / MultiVI** (Lopez 2018; Gayoso 2021; Ashuach 2023) | scRNA; +protein (CITE); +ATAC incl. missing modality | VAE, nonlinear encoder but near-linear generative latent; batch-conditioned | Probabilistic sc integration, batch correction, imputation | Strong batch integration; handles missing modalities | Needs 1000s cells; can over-smooth; A/C boundary | Richer priors |

## B. Knowledge / data-driven & network / graph approaches
Inject external structured biology (regulatory links, pathways, KGs); excel when feature spaces differ and mechanism/interpretability matter.

| Method | Omics | Approach | Problem solved | Pros | Cons | Future work |
|---|---|---|---|---|---|---|
| **GLUE / scGLUE** (Cao & Gao 2022) | sc RNA + ATAC + methylation (unpaired) | Prior regulatory graph couples per-modality VAEs; adversarial alignment | Integrate unpaired multi-omics w/ distinct features + regulatory inference | Handles distinct feature spaces; millions of cells | Depends on prior graph; adversarial instability | Richer priors; spatial/temporal |
| **PrimeKG** (Chandak, Huang & Zitnik 2023) | KG (20 resources, 17,080 diseases, ~4M relations) | Curated multimodal biomedical KG substrate | Structured prior for KG integration / precision medicine | Broad, harmonized, open; molecular→clinical | Not an algorithm; curation lag; edge noise | Continuous updates; patient-omics linking |
| **TxGNN** (Huang … Zitnik 2024) | KG (on PrimeKG) | GNN + metric learning; zero-shot indication/contraindication w/ explainable paths | Knowledge-driven repurposing incl. no-drug diseases | +49%/+35% zero-shot; interpretable paths | Bound by KG completeness; needs validation | Patient-omics coupling |
| **PARADIGM** (Vaske 2010) | CNV + expression (+mutation) on pathways | Factor graph over curated pathways; patient-specific activity | Convert omics → interpretable pathway activity | Mechanistic; patient-specific | Limited to curated pathways; compute | Updated pathways; sc |
| **ActivePathways** (Paczkowska 2020) | Per-gene p-values from multiple omics | Brown's-method p-value fusion + enrichment w/ attribution | Pathway-level integration + contributing-evidence | Simple, grounded, modality-agnostic | Discards direction/magnitude; not sample-level | Directional; sc/spatial |

## C. Foundation-model / "virtual cell" / LLM approaches
Pretrain on tens–hundreds of millions of cells; transfer/zero-shot or fine-tune for many tasks incl. integration and perturbation.

| Method | Omics | Approach | Problem solved | Pros | Cons | Future work |
|---|---|---|---|---|---|---|
| **scGPT** (Cui 2024) | scRNA; +ATAC/CITE fine-tune | Generative transformer, "cells as sentences", 33M+ cells | Transferable backbone for many sc tasks | Broad task coverage; strong fine-tuned | Fine-tune often needed; zero-shot can trail baselines; compute | More modalities; zero-shot |
| **Geneformer** (Theodoris 2023) | scRNA (rank-value) | Transformer, ~30M cells; transfer + in-silico perturbation | Context-aware network-biology predictions | Strong in low-data; in-silico perturbation | RNA-only; rank loses magnitude | Multimodal pretraining |
| **scFoundation** (Hao 2024) | scRNA (~20k genes) | 100M-param, read-depth-aware, 50M cells | General expression representation | Full gene set + depth; good transfer | RNA-centric; compute; interpretability | Multi-omic inputs |
| **UCE** (Rosen 2023, bioRxiv) | scRNA cross-species | PLM gene embeddings → transformer; zero-shot universal embedding | Shared embedding across datasets/species | True zero-shot; cross-species; label-free | Preprint; RNA-only; varies by tissue | Peer review; modality coverage |
| **Arc State + Virtual Cell Challenge** (Arc 2025 bioRxiv; Roohani 2025 Cell) | scRNA perturbation | Transition + embedding models; 100M+ perturbed / 167M observational cells; VCC benchmark | Predict unseen-perturbation responses; standardize eval | >50% better perturbation discrimination, ~2× DEG; honest benchmark | New/preprint; novel-context generalization unproven | VCC-driven iteration |
| **GEARS** (Roohani, Huang & Leskovec 2024) | Perturb-seq | DL + gene–gene (GO) graph | Predict combinatorial/unseen perturbations | +40% on GI subtypes; unseen combos | Needs perturb data; KG-bound; within-system | Broader perturbations; transfer |
| **CPA** (Lotfollahi 2023) | scRNA perturbation | Autoencoder disentangling basal vs perturbation/covariate programs | Unseen dose/combo/covariate prediction | Interpretable latent arithmetic | Linear compositionality; needs rich labels | Nonlinear; chemistry conditioning |
| **scGen** (Lotfollahi 2019) | scRNA response | VAE + latent vector arithmetic | First OOD sc perturbation prediction | Simple, effective OOD | Assumes linear latent shift; one perturbation | Multi-perturbation |

> **Cross-cutting caution (C):** Kedzierska et al. (Genome Biology 2025; bioRxiv 2023) found that in
> *zero-shot* settings Geneformer/scGPT can underperform simple baselines (HVG, scVI, mean-expression)
> for clustering/batch correction. Treat FM claims as ceilings to verify per task, not guaranteed wins
> — consistent with [[project_perturbation_baseline_consensus]].

## Synthesis — task fit and complementarity

| Task | Best category | Representative | Why |
|---|---|---|---|
| Factor / driver discovery | A | MOFA/MOFA+, JIVE, sparse CCA | explicit variance attribution |
| Patient stratification / subtyping | A (+B for mechanism) | iCluster(+), SNF, intNMF; PARADIGM | sample-efficient; KG explains subtypes |
| Batch integration (sc) | C fine-tuned & A | scVI/MultiVI, scGPT; UCE zero-shot | nonlinear + batch-conditioned (verify vs scVI) |
| Cross-modal imputation (unpaired/missing) | B & C | GLUE, MultiVI, totalVI | graph priors bridge; VAEs impute |
| Perturbation prediction | C | GEARS, CPA, scGen, Arc State (+VCC) | purpose-built generative |
| Biomarker discovery (sparse) | A & B | DIABLO, sparse CCA; WGCNA; ActivePathways | feature selection + gene-set attribution |
| Drug repurposing / mechanism | B | TxGNN, PrimeKG, PARADIGM | KGs encode drug–disease–gene, explainable |

**How they complement:** (1) interpretability↔expressivity trade-off (A transparent/sample-efficient;
C expressive/data-hungry; B supplies the biology/"why"); (2) feature-space bridging — A when samples
shared, B/C when neither samples nor features shared; (3) a realistic pipeline chains A (discover
factors/subtypes/biomarkers) → B (anchor to pathways/KG, hypothesize targets) → C (simulate
perturbations, prioritize experiments), looping back to refine A's priors and B's graphs; (4) B's
knowledge regularizes C (GEARS uses a GO graph; GLUE a regulatory prior); (5) validation discipline —
use A/B as baselines C must beat on the specific task.

**Bottom line:** A owns interpretable factor/driver discovery, bulk subtyping, sparse biomarkers;
B owns mechanism, pathway integration, feature-space bridging, knowledge-driven repurposing; C owns
atlas-scale sc integration and perturbation simulation. The "virtual cell" frontier is explicitly a
fusion: foundation models regularized by knowledge graphs, benchmarked against linear baselines.

---

## D. Per-disorder state of the art (immune-mediated / autoimmune)

Field-wide playbook: GWAS → functional genomics (eQTL, scATAC, colocalization) → single-cell/spatial
of target tissue → bulk subtyping for stratification. Maturity uneven: common, tissue-accessible,
GWAS-powered diseases (RA, SLE, IBD, MS, T1D, psoriasis, AD) have cell-resolution atlases; rarer /
tissue-inaccessible ones (SSc, Sjögren's, MG, CIDP, AS) are earlier-stage. Recurring open problems:
small N, tissue access, weak replication, association≠causality.

| Disorder | Key datasets | Approaches | Achieved | Current ability & limits | Key refs |
|---|---|---|---|---|---|
| **RA** | AMP RA/SLE synovium (79 donors, >314k cells, CITE+histology) | multimodal scRNA+protein+histology + GWAS | 6 cell-type-abundance phenotypes (CTAPs); pathogenic fibroblast & Tph states | atlas mature; CTAP→therapy not prospectively validated; blood surrogate immature | Zhang 2023 Nature; Zhang 2019 Nat Immunol |
| **SLE** | AMP LN kidney scRNA (21 subsets); CLUES mux-seq PBMC (>1.2M cells, 162/99); Banchereau peds | scRNA+genotype→cell-type eQTL; longitudinal bulk subtyping | cell-type IFN signature; variant→cell-type; flare modules | strong genetics+blood atlas; kidney access limited; subtypes not clinical | Perez 2022 Science; Arazi 2019 Nat Immunol; Banchereau 2016 Cell |
| **SSc** | skin microarray (Milano/GENISOS/PRESS); emerging skin scRNA | bulk "intrinsic subset" classification; sc fibroblast | 4 intrinsic subsets → drug-response hypotheses | subsets unstable within-patient over time; small N; skin≠visceral; low GWAS power | Milano 2008 PLoS ONE |
| **Sjögren's** | GWAS (Lessard); salivary-gland scRNA/spatial + TCR/BCR | GWAS; gland sc+spatial | innate+adaptive loci; activated epithelial/fibroblast; autoantibody strata | genetics solid; tissue sc small/single-center; subtyping nascent | Lessard 2013 Nat Genet |
| **MS** | IMSGC GWAS (~47k/68k, 200+ loci); brain/blood scRNA; eQTL | GWAS + cell-type enrichment; bulk prioritization; microglia | 551 susceptibility genes; risk in peripheral immune + microglia; ~48% heritability→immune | genetic map comprehensive; CNS post-mortem only; locus→mechanism unresolved; no response predictor | IMSGC 2019 Science |
| **IBD (CD/UC)** | UC colon atlas (Smillie 366k); CD ileal (Martin GIMATS); IIBDGC fine-mapping | mucosal scRNA; GWAS fine-mapping; anti-TNF response | IL13RA2+ inflammatory fibroblasts & GIMATS predict anti-TNF resistance; ~45 causal variants | most mature; predictors not yet clinical; functional validation partial | Smillie 2019 Cell; Martin 2019 Cell; Huang 2017 Nature |
| **Psoriasis/PsA** | Tsoi GWAS (36 loci); Reynolds skin atlas; PsA GWAS (MHC-I, IL23R) | GWAS+fine-mapping; skin scRNA/spatial | IL-23/IL-17 axis causal → successful biologics; DC/T17 states | best omics→drug story; PsA genetics less resolved; no response biomarker | Tsoi 2012 Nat Genet; Reynolds 2021 Science |
| **T1D** | T1D GWAS (520,580 samples); islet snATAC (131,554 nuclei); TEDDY/DIABIMMUNE | GWAS + snATAC cCRE; islet multi-omic; longitudinal microbiome | effector cell types incl. exocrine (CFTR ductal cCRE); environmental triggers | genetic→epigenomic strong; live islet scarce; progression prediction improving | Chiou 2021 Nature |
| **MG** | Japanese GWAS (1,434 cases, TERT; thymoma); new-onset PBMC scRNA | subtype GWAS; thymus/PBMC sc+spatial; AChR vs MuSK cytokines | TERT locus; plasmablast expansion ~ anti-AChR titer; AChR/MuSK divergence | early; small N; thymus access limited | Japanese MG GWAS 2026 Nat Commun **(verify authors)**; scRNA 2021 Cell Discov |
| **CIDP** | serum Olink proteomics; nerve/skin microarray; CSF proteome | serum proteomics; nerve/skin transcriptomics; antigen-specific T | 13→7-protein CIDP signature (TNFSF14,CD40,SIRT2,CCL3,IL8,TGFα,uPA); response candidates | weakest genomics (no large GWAS); biomarkers need prospective validation | eBioMedicine 2026 (PMID 42349252) **(verify)** |
| **AS** | IGAS Immunochip (10,619/15,145); multi-ancestry GWAS (25,645 cases) | GWAS/fine-mapping; TWAS/PWAS; PBMC scRNA | HLA-B27 + ERAP1/2 + IL-23R; 86+ associations; ~644 TWAS genes | genetics strong; entheses/SI joint inaccessible → mechanism inferred; no subtyping | IGAS/Cortes 2013 Nat Genet |
| **AD** | Paternoster GWAS (21,399 cases, 31 loci); Reynolds skin atlas (>310k); microbiome | GWAS (barrier+immune); skin scRNA/spatial; metagenomics | FLG barrier defect causal; Th2/Th22 skew; endotypes → dupilumab/JAK | barrier+Th2 actionable at pathway level; endotypes not yet therapy-selecting | Paternoster 2015 Nat Genet; Reynolds 2021 Science |

---

## References
(Methods A/B/C and per-disorder, merged. DOIs verified 2026-10-08 except **(verify)**.)

**A — Linear/Traditional:** MOFA Argelaguet 2018 Mol Syst Biol 10.15252/msb.20178124; MOFA+ 2020 Genome Biol 10.1186/s13059-020-02015-1; iCluster Shen 2009 Bioinformatics 10.1093/bioinformatics/btp543; iClusterPlus Mo 2013 PNAS 10.1073/pnas.1216676110; iClusterBayes Mo 2018 Biostatistics 10.1093/biostatistics/kxx017 **(verify)**; SNF Wang 2014 Nat Methods 10.1038/nmeth.2810; mixOmics Rohart 2017 PLoS Comput Biol 10.1371/journal.pcbi.1005752; DIABLO Singh 2019 Bioinformatics 10.1093/bioinformatics/bty1054; JIVE Lock 2013 Ann Appl Stat 10.1214/12-AOAS597; sparse CCA Witten 2009 Biostatistics 10.1093/biostatistics/kxp008; CCA Hotelling 1936 Biometrika 10.1093/biomet/28.3-4.321 **(verify)**; WGCNA Langfelder 2008 BMC Bioinformatics 10.1186/1471-2105-9-559; NMF Lee&Seung 1999 Nature 10.1038/44565; intNMF Chalise 2017 PLoS ONE 10.1371/journal.pone.0176278; scVI Lopez 2018 Nat Methods 10.1038/s41592-018-0229-2; totalVI Gayoso 2021 Nat Methods 10.1038/s41592-020-01050-x; MultiVI Ashuach 2023 Nat Methods 10.1038/s41592-023-01909-9.

**B — Knowledge/Graph:** GLUE Cao&Gao 2022 Nat Biotechnol 10.1038/s41587-022-01284-4; PrimeKG Chandak 2023 Sci Data 10.1038/s41597-023-01960-3; TxGNN Huang 2024 Nat Med 10.1038/s41591-024-03233-x; PARADIGM Vaske 2010 Bioinformatics 10.1093/bioinformatics/btq182; ActivePathways Paczkowska 2020 Nat Commun 10.1038/s41467-019-13983-9.

**C — Foundation/Virtual Cell:** scGPT Cui 2024 Nat Methods 10.1038/s41592-024-02201-0; Geneformer Theodoris 2023 Nature 10.1038/s41586-023-06139-9; scFoundation Hao 2024 Nat Methods 10.1038/s41592-024-02305-7; UCE Rosen 2023 bioRxiv 10.1101/2023.11.28.568918; Arc State 2025 bioRxiv 10.1101/2025.06.26.661135; Virtual Cell Challenge Roohani 2025 Cell 10.1016/j.cell.2025.06.008 (PMID 40578317); GEARS Roohani 2024 Nat Biotechnol 10.1038/s41587-023-01905-6; CPA Lotfollahi 2023 Mol Syst Biol 10.15252/msb.202211517; scGen Lotfollahi 2019 Nat Methods 10.1038/s41592-019-0494-8; Kedzierska 2025 Genome Biol 10.1186/s13059-025-03574-x (preprint 10.1101/2023.10.16.561085).

**Per-disorder:** Zhang 2023 Nature 10.1038/s41586-023-06708-y; Zhang 2019 Nat Immunol 10.1038/s41590-019-0378-1; Perez 2022 Science 10.1126/science.abf1970; Arazi 2019 Nat Immunol 10.1038/s41590-019-0398-x; Banchereau 2016 Cell 10.1016/j.cell.2016.03.008; Milano 2008 PLoS ONE 10.1371/journal.pone.0002696; Lessard 2013 Nat Genet 10.1038/ng.2792; IMSGC 2019 Science 10.1126/science.aav7188; Smillie 2019 Cell 10.1016/j.cell.2019.06.029; Martin 2019 Cell 10.1016/j.cell.2019.08.008; Huang 2017 Nature 10.1038/nature22969; Tsoi 2012 Nat Genet 10.1038/ng.2467; Reynolds 2021 Science 10.1126/science.aba6500; Chiou 2021 Nature 10.1038/s41586-021-03552-w; Japanese MG GWAS 2026 Nat Commun 10.1038/s41467-026-70376-5 **(verify)**; MG scRNA 2021 Cell Discov 10.1038/s41421-021-00314-w; CIDP eBioMedicine 2026 (PMID 42349252) **(verify)**; Cortes/IGAS 2013 Nat Genet 10.1038/ng.2667; Paternoster 2015 Nat Genet 10.1038/ng.3424.

## Update log
- **2026-10-08** — Survey created (3 paradigms + synthesis + 12-disorder table/detail). Spot-check
  flagged items before any external publication: iClusterBayes & Hotelling DOIs; 2026 MG-GWAS and
  CIDP-proteomics author strings; add an SSc single-cell ref (e.g. Tabib 2021) after DOI verification.
</content>
