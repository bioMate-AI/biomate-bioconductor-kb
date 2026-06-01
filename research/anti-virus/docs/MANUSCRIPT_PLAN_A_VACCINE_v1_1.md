# MHC class I epitope landscape of the full-length Andes virus glycoprotein reveals binder candidates and cross-species conservation for vaccine design

**Manuscript version 1.1** (research article draft — publication campaign `20260528T223525Z`)  
**Revision note:** Replaces the ninety-residue smoke-fragment negative baseline (v1.0) with full-length UniProt **Q9E006** (1138 aa), an expanded eight-allele HLA panel, and cross-species conservation analysis (ANDV / SNV / PUUV).

---

## Authors

[Author A], [Author B], [Author C]  

[Institution], [City, Country]  

**Correspondence:** [email]

---

## Abstract

Andes virus (ANDV) causes hantavirus pulmonary syndrome with high case fatality in South America, and no licensed vaccine exists. CD8⁺ T-cell responses against the viral surface glycoprotein (GP) may contribute to control, but systematic class I epitope maps for the full-length ANDV GP remain sparse. In response to the May 2026 ANDV outbreak (eight confirmed cases, cruise ship cluster), we applied the nf-core epitopeprediction workflow with MHCnuggets to the **complete reviewed ANDV GP sequence** (UniProt Q9E006; 1138 amino acids) across an expanded panel of eight common HLA class I alleles (A\*02:01, A\*01:01, A\*03:01, A\*24:02, B\*07:02, B\*08:01, B\*27:05, B\*35:01), evaluating eight- to twelve-residue peptides against GRCh37.

The analysis yielded **45,160** peptide–allele predictions. Under default MHCnuggets thresholds, **113** entries (**0.25%**) were classified as binders, spanning five alleles (predominantly HLA-B\*08:01, B\*07:02, and B\*27:05). Top-ranked binders included **MPKTIYEL** (HLA-B\*08:01; rank 0.0007; binding affinity 0.727) and **YRTLGVFRY** (HLA-B\*27:05; rank 0.0011; BA 0.660). In parallel, k-mer conservation analysis across ANDV, Sin Nombre virus, and Puumala virus identified **54** fully conserved 9-mers and **195** cross-species peptides on the full GP; notably, **no** conserved 9-mer overlapped the in silico binder set, indicating that **breadth** and **allele-specific binding** map to distinct GP regions.

These results do not establish immunogenicity or vaccine efficacy. They provide a reproducible, full-length in silico resource that supersedes the prior ninety-residue negative screen and defines a dual wet-lab strategy: (1) synthesize top MHC-validated peptides for binding confirmation, and (2) test triple-species conserved epitopes (e.g. **ESSCNFDLH**, GP position 61) for cross-reactive T-cell recognition. The archived tables, MultiQC reports, and Nextflow manifests support allele expansion and orthogonal predictor comparison.

---

## Introduction

Hantaviruses including Andes virus establish zoonotic cycles and periodically cause severe human disease. The ANDV surface glycoprotein is a focal antigen for subunit and mRNA vaccine design because it mediates entry and is displayed during infection. Rational prioritization of CD8⁺ T-cell epitopes requires knowing which peptide segments may bind diverse HLA class I alleles—yet experimental epitope maps for ANDV remain limited by biocontainment and HLA diversity.

Prior work in our campaign applied MHCnuggets to a **ninety-residue N-terminal smoke fragment** with only two alleles (HLA-A\*02:01 and B\*07:02), yielding **810** predictions and **zero** binder calls. That negative baseline was scientifically honest but strategically incomplete: it used a partial sequence and narrow allele coverage unrepresentative of a full GP immunogen or global HLA diversity.

Here we extend the analysis to the **full-length reviewed GP** (Q9E006) with eight alleles, executed on cloud compute via nf-core epitopeprediction through BioMate. We integrate cross-species conservation (ANDV / SNV / PUUV) to nominate peptides for pan-hantavirus breadth independent of MHC binding scores. We interpret findings in the context of the May 2026 outbreak and propose a dual-track experimental validation plan.

---

## Outbreak Response Context

Concurrent with this study, the World Health Organization reported eight confirmed ANDV infections associated with a cruise ship outbreak, including limited human-to-human transmission. Rapid, reproducible immunoinformatics on the **complete** GP sequence is a prerequisite for mRNA or protein vaccine design during such events.

Our prior ninety-residue screen suggested that linear prediction on a short fragment could yield entirely negative binder calls. The full-length analysis reported here demonstrates that **allele panel and sequence coverage strongly influence outcomes**: the same predictor on the complete GP identifies **113** binder classifications, while conservation analysis independently nominates **54** triple-species 9-mers. Together these tracks give outbreak-response teams both **allele-ranked candidates** and **conserved probes** for experimental triage without claiming clinical efficacy.

---

## Methods

### Study design and scope

Retrospective computational study on one protein sequence (full ANDV GP). No human participants. Objective: enumerate class I peptide binding predictions for eight- to twelve-residue windows across eight alleles and summarize cross-species conservation.

### Input sequence and HLA panel

**Protein:** UniProt **Q9E006** (ANDV envelopment polyprotein; 1138 aa; reviewed). FASTA archived at `s3://biomate-nextflow-work/inputs/andv_campaign/publication_20260528/andv_gp_full_Q9E006.fasta`.

**HLA class I alleles:** A\*02:01; A\*01:01; A\*03:01; A\*24:02; B\*07:02; B\*08:01; B\*27:05; B\*35:01 (semicolon-separated in samplesheet).

### Epitope prediction workflow

nf-core epitopeprediction via BioMate Nextflow API (`run_id` **5eda51b4-70b5-4405-9083-f4ab1746da14**), profile `docker`, AWS Batch executor, tool **MHCnuggets**, `genome_reference` **grch37**. Output prefix: `s3://biomate-nextflow-work/nextflow/outputs/plan_a_full_gp/20260528T223525Z`.

### Cross-species conservation

Reviewed GP sequences for ANDV (Q9E006), SNV (Q89905), and PUUV (P27312) were fetched from UniProt REST. BioPython pairwise alignment and k-mer presence mapping (`track_plan_a_cross_species.py`) identified peptides conserved across all three species on the full GP (8–11 mer enumeration; **54** unique 9-mers).

### Outputs and quality control

Merged prediction table (`PLAN_A_FULL_GP.tsv`), MultiQC HTML, Nextflow `pipeline_info`. Binder rate from MultiQC: **113 / 45,160 (0.25%)**.

### Reproducibility

Local mirror: `research/anti-virus/runs/publication_20260528T223525Z/plan_a_epitope/`. Wet-lab priority list: `wet_lab_package/WET_LAB_CANDIDATES.md`.

---

## Results

### Full-length MHC class I predictions

The merged table contains **45,160** peptide–allele rows for sample **PLAN_A_FULL_GP**. MHCnuggets classified **113** rows as binders (**110** unique peptide sequences). Binder counts by allele:

| Allele | Binder calls |
|--------|----------------|
| HLA-B\*08:01 | 54 |
| HLA-B\*07:02 | 30 |
| HLA-B\*27:05 | 27 |
| HLA-A\*01:01 | 1 |
| HLA-A\*03:01 | 1 |
| HLA-A\*02:01, A\*24:02, B\*35:01 | 0 |

Representative top binders (Table 1) include **MPKTIYEL** on HLA-B\*08:01 (rank 0.0007; BA 0.727) and **YRTLGVFRY** on HLA-B\*27:05 (rank 0.0011; BA 0.660). Several top hits exceed ten residues (e.g. **IRSCMASVFTSR**, 12-mer), reflecting the configured eight- to twelve-residue window.

Compared with the archived ninety-residue smoke run (**810** rows; **0** binders), the full-length panel shows that negative baseline was **not** invariant for ANDV GP under MHCnuggets—it was contingent on fragment choice and allele coverage.

### Cross-species conservation (ANDV / SNV / PUUV)

Pairwise alignment of full GPC sequences gave **78.0%** identity (ANDV vs SNV) and **66.9%** (ANDV vs PUUV). K-mer mapping identified **195** cross-species peptides (8–11 mer) and **54** unique conserved 9-mers. The N-proximal epitope **ESSCNFDLH** (GP position 61), conserved across all three species, did **not** receive a positive binder call on any of the eight alleles (best rank 0.29 on B\*35:01), illustrating decoupling of **conservation** and **predicted MHC binding**.

### Dual-track wet-lab nomination

**Track A (MHC binders):** fifteen peptides ranked by best allele-specific rank (MB-01–MB-15 in wet-lab package).  
**Track B (conservation):** fifteen triple-species 9-mers including **ESSCNFDLH** (XSP-01–XSP-15).

---

## Table 1

Top binder-classified peptide–allele rows from `PLAN_A_FULL_GP.tsv` (publication campaign).

| Peptide | Allele | Rank | BA | Binder (MHCnuggets) |
| --- | --- | --- | --- | --- |
| KTFEGILTK | HLA-A\*03:01 | 0.0 | 0.426 | True |
| ATESALQAHY | HLA-A\*01:01 | 0.0002 | 0.451 | True |
| MPKTIYEL | HLA-B\*08:01 | 0.0007 | 0.727 | True |
| YRTLGVFRY | HLA-B\*27:05 | 0.0011 | 0.660 | True |
| IRSCMASVFTSR | HLA-B\*27:05 | 0.0012 | 0.655 | True |
| YRTLGVFRYK | HLA-B\*27:05 | 0.0013 | 0.651 | True |

**Table 1.** Exemplar binder rows from the full-length GP run. Complete table: 45,160 rows in `plan_a_epitope/PLAN_A_FULL_GP.tsv`.

---

## Discussion

The central finding is that **full-length ANDV GP immunoinformatics yields actionable in silico binder calls** when allele coverage and sequence extent are expanded, overturning the smoke-fragment negative baseline. The **0.25%** binder rate is low in absolute terms—consistent with large viral glycoproteins and stringent thresholds—but **113** positive classifications provide concrete peptides for experimental MHC binding assays.

Cross-species conservation nominates a complementary set enriched for pan-hantavirus breadth (e.g. **ESSCNFDLH**). Zero overlap between conserved 9-mers and binder calls suggests vaccine strategies may need **multivalent** designs combining allele-optimized T-cell epitopes and conserved regions for cross-reactivity testing.

Limitations remain: MHCnuggets alone; no proteasomal processing or TAP modeling in this run; no structural exposure filtering; glycosylation not modeled. NetMHCpan and structure-guided epitope mapping are priority extensions (see `FEEDBACK_CROSSWALK.md`).

---

## Conclusions

We present a completed nf-core epitopeprediction run on the **full-length** ANDV GP (Q9E006) across **eight** HLA class I alleles, yielding **45,160** predictions and **113** binder classifications, plus **54** triple-species conserved 9-mers. The work transforms a fragment-limited negative baseline into a dual-track wet-lab package (MHC binders + conserved peptides). No immunogenicity or efficacy claims are made; the contribution is a reproducible, outbreak-responsive immunoinformatics resource for ANDV vaccine design.

---

## Data availability

| Artifact | Location |
|----------|----------|
| Full GP predictions | `research/anti-virus/runs/publication_20260528T223525Z/plan_a_epitope/PLAN_A_FULL_GP.tsv` |
| S3 outputs | `s3://biomate-nextflow-work/nextflow/outputs/plan_a_full_gp/20260528T223525Z/` |
| Cross-species JSON | `research/anti-virus/runs/publication_20260528T223525Z/cross_species_conservation_full_gp.json` |
| Wet-lab package | `research/anti-virus/runs/publication_20260528T223525Z/wet_lab_package/` |
| Run manifest | `research/anti-virus/runs/publication_20260528T223525Z/campaign_manifest.json` |
| Smoke baseline (comparator) | `research/anti-virus/runs/plan_a_epitope_a44876b7_s3_mirror/` |

---

## References

1. Shaffer J, Alvarez KS, Norret M, et al. MHCnuggets: open-source class I MHC binding predictions. *Bioinformatics*. 2018;34(21):3651–3654.  
2. nf-core community. nf-core/epitopeprediction. [Insert version DOI.]  
3. Ewels PA, et al. MultiQC. *Bioinformatics*. 2016;32(19):3047–3048.  
4. [Insert ANDV epidemiology / Guo et al. cryo-EM GP structure citation.]  
5. [Insert WHO May 2026 outbreak situation report if citable.]
