# Codon-optimized mRNA construct design for ANDV glycoprotein expression (Plan B track)

**Manuscript version 1.1** (methods/results excerpt)  
**Evidence run:** `research/anti-virus/runs/publication_20260528T223525Z/`

---

## Abstract

Messenger RNA vaccines against Andes virus require expression constructs that balance codon adaptation to the production host with RNA secondary structure constraints and formulation considerations. Here we report in silico execution of the Plan B workflow ladder on **full-length ANDV glycoprotein** (UniProt **Q9E006**, 1138 aa; reverse-translated CDS **3414 nt**) via BioMate on AWS Batch: codon optimization (**10813**), RNA secondary structure prediction on the 5′ window (**10721**), lipid nanoparticle formulation ranking (**12869**), ANDV-specific P0-style construct QC, and nanoparticle PK modeling (**12867**).

---

## Methods

### Antigen and inputs

- **Protein:** UniProt Q9E006 (ANDV GP envelope polyprotein), 1138 residues.  
- **CDS:** Reverse-translated with a simplified human codon table (`assets/andv_gp_cds_reverse_translated.fasta`).  
- **S3 campaign prefix:** `s3://biomate-nextflow-work/inputs/andv_campaign/publication_20260528/`

### Codon optimization (workflow 10813)

`optimize_codons_for_heterologous_expression` with `profile: aws`, executor `awsbatch`.  
Run ID: `839ff0f7-5146-4e25-8ba8-01e202401a6d`; outdir: `s3://biomate-nextflow-work/nextflow/outputs/plan_b_andv_gp/20260528T223525Z/codon/`.

### RNA secondary structure (workflow 10721)

ViennaRNA RNAfold on the **first 500 nt** of the CDS (T→U), output prefix `andv_gp_5prime`. Retry run after RNA alphabet fix: MFE **−182.7 kcal/mol**.

### LNP optimization (workflow 12869)

`lnp_formulation_optimization` with `cargo_type: mRNA`, `target_tissue: liver`. Run ID: `d065b268-51be-4b78-8b5e-63be4bc7459b`.

### P0 mRNA validation

- **ANDV construct QC (local):** `scripts/launch_plan_b_remaining.py` writes `plan_b_p0/andv_p0_mrna_validation_report.json` — CAI, premature stop scan, 5′ MFE gate (−150 kcal/mol).  
- **Platform gold standard (12819):** Spike GenBank MN908947.3 protocol (2P stabilisation) launched on Batch for workflow regression; not the ANDV antigen itself.

### Nanoparticle PK (workflow 12867)

`nanoparticle_pk_biodistribution` with particle diameter **80 nm** (from LNP recommendation), PEG surface chemistry, liver-targeted scenario. Launched via `launch_plan_b_remaining.py`.

---

## Results

### Codon optimization (real ANDV GP)

| Metric | Value |
|--------|-------|
| Input length | **3414 nt** (1138 codons) |
| Codons modified | **737 / 1138 (64.76%)** |
| Artifact | `plan_b_codon/optimize_codons_for_heterologous_expression_results.json` |

*Contrast:* An earlier infrastructure smoke test on a **171-nt** fragment reported 25/57 codons (43.86%) — that run used a short demo sequence, not Q9E006.

### RNA secondary structure (5′ window)

Minimum free energy: **−182.7 kcal/mol** (500-nt 5′ window; passes the −150 kcal/mol P0-style threshold used in workflow 12819).

### LNP formulation (in silico)

| Metric | Value |
|--------|-------|
| Endosomal escape score | **0.202** |
| Liver tissue targeting | **0.85** |
| Predicted encapsulation efficiency | **20%** |
| Ionizable lipid pKa | 9.5 (flagged suboptimal for endosomal ionization) |

Artifact: `plan_b_lnp/lnp_results.json`.

### Construct QC summary

See `plan_b_p0/andv_p0_mrna_validation_report.json` for CAI, stop-codon scan, and combined pass/fail against P0-style gates.

---

## Discussion

These Plan B executions establish that the mRNA/LNP workflow ladder runs on **antigen-faithful ANDV sequence data** on the same BioMate + AWS Batch infrastructure as the epitope and inhibitor tracks. Metrics support a Methods supplement on construct engineering; they do not demonstrate expression yield, immunogenicity, or GMP-ready formulations. The suboptimal ionizable-lipid pKa flag motivates formulation iteration before any translational claims.

---

## Data availability

Publication run bundle: `research/anti-virus/runs/publication_20260528T223525Z/`  
Figures: `python3 research/anti-virus/scripts/generate_manuscript_plan_b_figures.py` → `runs/manuscript_figures_v1/plan_b/`

---

**Version:** 1.1 (2026-05-29) — supersedes v1.0 (`plan_b_exec_20260512T184230Z` smoke numbers).
