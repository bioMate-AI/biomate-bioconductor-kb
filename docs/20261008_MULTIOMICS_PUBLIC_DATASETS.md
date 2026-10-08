# Multi-Omics Public Datasets — Living Catalog

**Last updated:** 2026-10-08
**Maintained:** add new resources as they appear; keep scales/URLs current; never remove a verified
entry without noting why in the Update log. Part of [[20261008_LIVING_REFERENCES_INDEX]].
**Integrity:** [[feedback_citation_integrity]] — all entries verified against cited sources on the
date noted; figures that could not be freshly confirmed are flagged "approx — verify".
**Confidentiality:** public datasets only — safe for community / website use
([[feedback_website_no_internal_work]]).
**Relation to existing BioMate docs (expand, don't duplicate):**
`20260712_MULTIOMICS_SYSTEMSBIO_SHOWCASE_GOLD_STANDARDS.md`,
`20260719_MULTIOMICS_GOLDSTANDARD_BENCHMARK.md`, `20260727_MULTIOMICS_BENCHMARK_DESIGN.md`,
`20260401_DATASET_INTEGRATION_IMPLEMENTATION.md`; memory [[project_multiomics_benchmark]],
[[project_test_data_datasets]]. This catalog is the consolidated public-dataset registry those
benchmark docs draw from.

> Immune/autoimmune-relevant resources are flagged **[IMMUNE]**. Scales/URLs confirmed via web
> search 2026-10-08 except TCGA/ICGC headline counts (canonical) and items marked "verify".

---

## 1. Cancer multi-omics

| Dataset | Omics types | Source / consortium | Access portal | Scale (verified) | Disease / tissue | Access | Why useful |
|---|---|---|---|---|---|---|---|
| **TCGA** | WGS/WES, RNA-seq, miRNA, methylation (450K), CNV, RPPA protein | NCI/NHGRI | GDC `portal.gdc.cancer.gov` | ~11,000 patients, 33 cancer types (canonical) | 33 adult cancers | Open (L3) + controlled (dbGaP) | Reference pan-cancer matched multi-omics cohort |
| **CPTAC** | Proteome + phosphoproteome (MS) + matched WGS/WES, RNA-seq, methylation | NCI | PDC `pdc.cancer.gov`; GDC | >1,000 tumors, 10 harmonized cohorts; PDC ~2,400 samples, 20+ types | Breast, colon, ovarian, UCEC, ccRCC, LUAD, LSCC, GBM, HNSCC, PDAC | Open + controlled | Reference proteogenomic resource |
| **ICGC / PCAWG** | Whole genomes (+normal), transcriptome, some methylation | ICGC / ICGC-TCGA PanCancer | ICGC portal; UCSC Xena | PCAWG 2,658 whole genomes + normals, 38 tumour types; ICGC ~25,000 donors | Pan-cancer | Open (somatic) + controlled (germline, EGA) | Gold-standard WGS somatic + non-coding drivers |
| **HTAN** | scRNA, snRNA, scATAC, spatial (MIBI, CyCIF, CODEX), bulk, imaging | NCI Moonshot | `humantumoratlas.org`; CELLxGENE; cBioPortal | Phase 1: 8,425 biospecimens, 2,042 participants, ≥11 atlases, 17 sites | Tumor evolution | Open + controlled | 3D single-cell + spatial tumor atlases |

## 2. Autoimmune / Immune **[IMMUNE]**

| Dataset | Omics types | Source | Portal | Scale | Disease/tissue | Access | Why useful |
|---|---|---|---|---|---|---|---|
| **ImmPort** | Flow, CyTOF, ELISA/ELISPOT, expression, clinical | NIH/NIAID | `immport.org` | >58,000 subjects, >5M results; ~422 studies + 164 trials (counts drift) | Vaccines, infection, autoimmunity, allergy, transplant | Open (registration) | Largest open human-immunology repository w/ clinical metadata |
| **TEDDY** | Genotype/HLA, transcriptomics, proteomics, metabolomics, microbiome + clinical | NIDDK | NIDDK-CR; dbGaP | >8,600 at-risk children, 12 centres, 15-yr prospective | T1D / islet autoimmunity | Controlled | Premier longitudinal multi-omic birth cohort |
| **DICE** | RNA-seq + genotype (eQTL) + epigenomics, sorted immune cells | La Jolla Institute | `dice-database.org` | 1,544 RNA-seq, 91 donors, 13 cell types; eQTLs 12,254 genes (portal expanded — verify) | Healthy immune (PBMC-sorted) | Open | Immune-cell transcriptome + eQTL map for GWAS interpretation |
| **OneK1K** | scRNA + genotype (sc-eQTL) | Garvan (Powell) | GEO GSE196830; CELLxGENE; `onek1k.org` | 1.27M PBMCs, 982 donors, 14 cell types; 26,597 cis-eQTLs | Peripheral immune (healthy) | Open (processed) | Largest population single-cell eQTL resource |
| **CLL multi-omics (MOFA ref)** | Mutations, RNA, methylation, ex-vivo drug response (63 drugs) | EMBL (Dietrich/Huber/Stegle) | Bioconductor `MOFAdata` | 200 CLL samples, 4 matched modalities | CLL | Open | Canonical MOFA worked example |

## 3. Single-cell & spatial multiome / reference atlases

| Dataset | Omics | Source | Portal | Scale | Tissue | Access | Why useful |
|---|---|---|---|---|---|---|---|
| **Human Cell Atlas** | scRNA, snRNA, scATAC, spatial (incl. immune atlases **[IMMUNE]**) | HCA | `data.humancellatlas.org` | ~62M cells, ~9,100 donors, 18 networks (Jan 2025) | Healthy, all organs | Open (tiered) | Master reference atlas |
| **CZ CELLxGENE Discover** | scRNA/snRNA standardized, some multiome | CZI | `cellxgene.cziscience.com`; Census API | Census LTS 2025-11: ~217M total / ~125M unique cells, 1,845 datasets | Pan-tissue/disease | Open | One-click + Census API for programmatic integration |
| **HuBMAP** | scRNA/snRNA, scATAC, CODEX, Visium, MALDI, imaging (22 types) | NIH Common Fund | `portal.hubmapconsortium.org` | 5,032 datasets, 22 types, 27 organs, 310 donors (Oct 2025) | Healthy tissues | Open (+protected) | Multi-modal spatial + single-cell healthy-tissue atlas |
| **scNMT-seq (mouse gastrulation)** | RNA + methylation + accessibility (triple-omic single cell) | Babraham/EMBL | GEO GSE121708 | 1,105 single cells | Mouse embryo | Open | Canonical single-cell triple-omics testbed |
| **10x public Multiome** | Paired scRNA + scATAC; CITE-seq demos | 10x Genomics | `10xgenomics.com/datasets` | Many demos (PBMC ~10k nuclei, brain, lymph node) | PBMC, brain, lymphoid | Open | Clean paired-multiome references |
| **Human Protein Atlas** | Antibody IHC/IF (spatial proteomics) + RNA-seq | KTH/SciLifeLab | `proteinatlas.org` | >27,300 antibodies, ~17,200 genes, 44 tissues, >13M images | Normal, cancer, blood **[IMMUNE]** | Open (CC BY-SA) | Spatial/subcellular protein + transcriptomics |

## 4. Population / biobank multi-omics

| Dataset | Omics | Source | Portal | Scale | Focus | Access | Why useful |
|---|---|---|---|---|---|---|---|
| **UK Biobank** | WGS (500k), WES, SNP-array, Olink proteomics, NMR metabolomics, imaging, EHR | UK Biobank | AMS `ukbiobank.ac.uk` | WGS ~500,000 (Nov 2023); Olink ~50k+ → scaling to 500k (~5,400 proteins); NMR 250 biomarkers on ~500k | Population (autoimmune incl. **[IMMUNE]**) | Controlled (application+fee) | Largest deeply-phenotyped multi-omic population cohort |
| **GTEx v8** | RNA-seq (multi-tissue) + WGS genotype (eQTL/sQTL) + histology | NIH Common Fund | `gtexportal.org`; dbGaP phs000424 | 17,382 RNA-seq, 948 donors, 54 tissues | Normal human tissues | Open (eQTL) + controlled (raw) | Reference multi-tissue expression+genotype |
| **Open Targets Platform** | Integrated genetics (GWAS, eQTL/pQTL/sQTL), transcriptomics, somatic, drugs, literature | Open Targets (EBI/Sanger) | `platform.opentargets.org` | R25.09: 78,726 targets, 39,530 diseases, ~30.4M evidence, ~11.0M associations | Target-disease (incl. immune **[IMMUNE]**) | Open (CC0; GraphQL/BigQuery) | Harmonized multi-evidence target-disease prioritization |

## 5. Registries & portals

| Registry | Type | URL | Scope | Access |
|---|---|---|---|---|
| **GEO** | Functional genomics repo | `ncbi.nlm.nih.gov/geo` | >240,000 series; multi-omic super-series | Open |
| **ArrayExpress / BioStudies** | Study repo | `ebi.ac.uk/biostudies/arrayexpress` | EBI umbrella; links multi-component datasets | Open |
| **EGA** | Controlled human data | `ega-archive.org` | Thousands of genomic+phenotypic studies | Controlled (DAC) |
| **dbGaP** | Controlled genotype-phenotype | `ncbi.nlm.nih.gov/gap` | Hosts TCGA raw, GTEx, TEDDY | Controlled (DAR) |
| **Synapse** | Collaborative platform (Sage) | `synapse.org` | HTAN DCC, DREAM, AMP | Mixed |
| **Zenodo / Figshare** | General data repos | `zenodo.org` / `figshare.com` | DOI-minted processed datasets | Mostly open |

## Caveats
- TCGA (~11,000 pts/33 types), ICGC (~25,000 donors): canonical, not re-queried. PCAWG 2,658/38 verified.
- DICE: 91 donors/1,544 samples/13 types at publication; live portal expanded — verify current.
- ImmPort study/trial counts drift per release; subject count (>58,000) stable.
- UK Biobank Olink mid-scale-up (50k delivered → 500k in progress).
- HCA / CELLxGENE Census / HuBMAP counts grow each release; figures dated.

## Sources (verified 2026-10-08)
CELLxGENE Census https://cellxgene-census.readthedocs.io/ , https://academic.oup.com/nar/article/53/D1/D886/7912032 ·
OneK1K https://www.cgfi.unsw.edu.au/our-research/onek-1k , https://arxiv.org/pdf/2302.11662 ·
GTEx v8 https://pmc.ncbi.nlm.nih.gov/articles/PMC7737656 , https://gtexportal.org ·
DICE https://dice-database.org/ , https://pmc.ncbi.nlm.nih.gov/articles/PMC9035271 ·
CPTAC https://pdc.cancer.gov , https://gdc.cancer.gov/node/1179/ ·
HuBMAP https://portal.hubmapconsortium.org , https://arxiv.org/abs/2511.05708v1 ·
HTAN https://humantumoratlas.org , https://www.cancer.gov/about-nci/organization/dcb/research-programs/htan ·
CLL/MOFA Mol Syst Biol 2018 (MOFAdata, Bioconductor) ·
TEDDY https://teddy.epi.usf.edu/TEDDY/ , https://www.niddk.nih.gov ·
PCAWG https://pmc.ncbi.nlm.nih.gov/articles/PMC7340791 (Nature 2020) ·
UK Biobank https://www.ukbiobank.ac.uk/enable-your-research/about-our-data/biomarker-data/ ·
HCA https://data.humancellatlas.org ·
HPA https://www.proteinatlas.org , https://pubmed.ncbi.nlm.nih.gov/33146890/ ·
ImmPort https://www.immport.org , https://www.niaid.nih.gov/node/21218 ·
scNMT-seq https://pmc.ncbi.nlm.nih.gov/articles/PMC6924995 ·
Open Targets https://platform-docs.opentargets.org/release-notes ·
Registries: GEO, BioStudies/ArrayExpress, EGA, dbGaP, Synapse, Zenodo, Figshare, 10x Genomics datasets (official sites).

## Update log
- **2026-10-08** — Catalog created from verified research pass (5 categories + registries).
  Next: add AMP RA/SLE, DIABIMMUNE, IMSGC, and per-disorder cohorts from the per-disorder survey;
  refresh CELLxGENE/HuBMAP counts next release.
</content>
