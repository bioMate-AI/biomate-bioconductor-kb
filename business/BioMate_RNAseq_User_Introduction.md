# BioMate for RNA-seq & mRNA Analysis
### A Researcher's Introduction
*What BioMate can do for your transcriptomics work — and questions to help us tailor it to your lab*

---

## What BioMate Does for RNA-seq

BioMate lets you run the entire RNA-seq analysis pipeline — from raw FASTQ files to
differential expression results, pathway enrichment, and publication-ready figures —
by describing your experiment in plain language. No code. No queue. No specialist required.

You describe the problem. BioMate selects the right tools, sets the parameters to community
best practices, runs the pipeline, and returns the results in the same conversation window.

---

## Workflow Coverage

### Bulk RNA-seq

| What you want to do | BioMate workflow | Input you provide |
|---|---|---|
| Go from raw FASTQ files to gene counts | nf-core/rnaseq (STAR or Salmon) | FASTQ files + genome alias (e.g. GRCh38) |
| Find differentially expressed genes between conditions | DESeq2, edgeR, or limma-voom | Count matrix + sample metadata |
| Identify enriched biological pathways | clusterProfiler (GO + KEGG) | DE gene list |
| Visualise results | Volcano plot, heatmap, MA plot | DE results |
| Detect gene fusions in tumour samples | nf-core/rnafusion | FASTQ files |
| QC your alignment and coverage | Qualimap, Picard CollectRnaSeqMetrics | BAM file |
| Remove rRNA reads before quantification | SortMeRNA | FASTQ files |

### Single-Cell RNA-seq

| What you want to do | BioMate workflow | Input you provide |
|---|---|---|
| Process 10x Genomics FASTQ → count matrix | nf-core/scrnaseq | FASTQ + genome + barcode whitelist |
| Normalise, cluster, and embed cells | scran + UMAP | Cell Ranger output directory |
| Annotate cell types automatically | SingleR | Normalised count object |
| Test differential cell abundance between conditions | miloR | Annotated single-cell object |
| Correct batch effects across datasets | Harmony or scVI | Processed h5ad |
| Infer RNA velocity (future cell states) | Velocyto | 10x BAM + barcodes |

### Clinical & Translational RNA-seq

| What you want to do | BioMate workflow | Input you provide |
|---|---|---|
| Discover molecular subtypes in a patient cohort | ConsensusClusterPlus | Expression matrix + sample metadata |
| Connect subtypes to patient survival | Kaplan-Meier + Cox regression | Cluster assignments + clinical data |
| Score gene set activity per sample | GSVA / ssGSEA (MSigDB Hallmarks) | Expression matrix |
| Build a transcriptomic biomarker signature | limma-voom + GSVA | Count matrix + condition labels |
| Deconvolve bulk RNA-seq into cell type fractions | DeconRNASeq | Bulk counts + cell type reference |

### Small RNA & miRNA

| What you want to do | BioMate workflow | Input you provide |
|---|---|---|
| Quantify miRNA from small RNA-seq | nf-core/smrnaseq | FASTQ + species code |
| Find miRNA–mRNA co-regulatory pairs | mirTarRnaSeq | Paired miRNA + mRNA counts |
| Look up validated miRNA targets | miRTarBase data lake | miRNA name or gene list |

### mRNA Structure & Synthetic Biology

| What you want to do | BioMate workflow | Input you provide |
|---|---|---|
| Predict secondary structure of a sequence | ViennaRNA RNAfold | RNA sequence |
| Compute structural features (stem count, pairing fraction) | RNA structure feature analysis | Dot-bracket + sequence |
| Optimise codons for human expression (mRNA therapeutics) | Codon optimisation pipeline | Coding sequence + host codon table |

### Reference & Expression Databases

| What you want to do | BioMate tool | Input |
|---|---|---|
| Look up tissue expression of any gene | ARCHS4 query (>800K RNA-seq samples) | Gene name |
| Find GO / KEGG enrichment for a gene list | GOseq | DE gene list + gene lengths |

---

## QC Profiles Available for RNA-seq

BioMate applies quality thresholds automatically based on your sample type.
You can select a profile when submitting your query, or let BioMate recommend one.

| Profile name | Best for | Key thresholds enforced |
|---|---|---|
| `rnaseq_polya_standard` | Standard polyA-selected bulk RNA-seq | Mapping rate ≥ 70%, assigned reads ≥ 60%, duplicate rate ≤ 60% |
| `rnaseq_ribo_depleted` | Ribo-depleted / total RNA libraries | Relaxed duplicate threshold; rRNA fraction monitored |
| `rnaseq_ffpe` | FFPE tumour biobank samples | Adjusted for degraded RNA: lower mapping floor (≥ 50%), DV200 advisory |
| `rnaseq_single_nucleus` | snRNA-seq from frozen tissue | Ambient RNA fraction checked; intron/exon ratio monitored |
| `rnaseq_non_model` | Non-model organism without reference | Custom genome + GTF required; BUSCO completeness check |

When a sample fails a threshold, BioMate shows you which metric failed, the measured
value versus the threshold, the evidence source for the threshold, and a remediation suggestion —
before asking whether you want to proceed.

---

## Example Queries You Can Send Right Now

These are real messages you can paste into the BioMate chat to try the platform.
Replace the bracketed values with your own parameters.

**Basic differential expression**
```
I have paired-end bulk RNA-seq from [5 tumour and 5 normal] samples.
FASTQ files are aligned to [GRCh38]. I want to find differentially
expressed genes between tumour and normal, then run GO enrichment on
the top hits. Use DESeq2 and a padj threshold of 0.05.
```

**FFPE clinical cohort**
```
I have RNA-seq from [40 FFPE breast cancer] specimens with matching
clinical outcome data. Apply the FFPE QC profile and run DESeq2
differential expression between [responders and non-responders].
Then give me a gene signature and pathway enrichment summary.
```

**Single-cell from 10x**
```
I have 10x Genomics single-cell RNA-seq from a [lung tumour biopsy].
The Cell Ranger output is ready. Run dimensionality reduction,
cluster the cells, annotate cell types using SingleR against the
[HumanPrimaryCellAtlasData] reference, and show me the cell type
proportions.
```

**Patient stratification**
```
I have a bulk RNA-seq expression matrix from [120 AML patients] with
overall survival data. Find unsupervised molecular subtypes using
consensus clustering, then run Kaplan-Meier survival analysis to
see if the subtypes have different outcomes.
```

**Fusion gene detection**
```
I have RNA-seq from a [paediatric leukaemia] patient. Run the
rnafusion pipeline to detect gene fusions. Use GENCODE [GRCh38].
```

**Tissue expression lookup**
```
What tissues express [BRCA2] most highly? I want to understand
potential on-target toxicity for a therapeutic that targets this gene.
```

**mRNA codon optimisation**
```
I have a coding sequence for a [CAR-T] therapeutic mRNA.
Optimise the codons for expression in human cells and report
the Codon Adaptation Index before and after.
```

---

## What BioMate Does Automatically (You Do Not Need to Configure These)

- Selects the aligner (STAR vs Salmon) based on your stated goal and data type
- Applies trimming (fastp) before alignment
- Sets the correct strand specificity based on library prep protocol
- Generates MultiQC summary reports across all samples
- Filters low-count genes before DE testing
- Applies multiple-testing correction (BH/FDR) by default
- Annotates DE results with gene symbols and Entrez IDs
- Scales analysis to your sample size (parallelised on cloud infrastructure)

---

## What BioMate Asks You to Provide

The minimum you need to get started:

| For bulk RNA-seq | For scRNA-seq |
|---|---|
| Raw FASTQ files (or already-aligned BAMs, or Salmon quant directories) | Cell Ranger output directory (or FASTQ for re-processing) |
| Reference genome alias (GRCh38, mm10, etc.) or custom FASTA + GTF | Reference genome alias or custom FASTA + GTF |
| Sample metadata: which samples belong to which condition | Experimental metadata: condition, batch |
| Your comparison: what vs. what | Your question: cell types? Differential abundance? |

Optional but helpful:
- Library prep kit (polyA selection, ribo-depletion, FFPE, 10x Flex, etc.)
- Known batch variables to correct for
- Any specific tools you want or have published with previously

---

## Questions for You

To help us understand your work and make sure BioMate is set up correctly
for your specific needs, we would appreciate your answers to the following.
There are no right or wrong answers — this is about your lab's actual situation.

**Section 1 — About your data**

1. What type of RNA-seq data do you currently work with most?
   - [ ] Bulk RNA-seq (standard polyA or ribo-depleted)
   - [ ] FFPE tumour samples from a biobank or clinical trial
   - [ ] Single-cell RNA-seq (10x Genomics or similar)
   - [ ] Single-nucleus RNA-seq (from frozen tissue)
   - [ ] Small RNA-seq / miRNA-seq
   - [ ] Spatial transcriptomics
   - [ ] Other: _______________

2. What organism(s) do you study? (e.g. human, mouse, zebrafish, non-model organism)

3. Roughly how many samples does a typical project involve for you?
   - [ ] Fewer than 10
   - [ ] 10–50
   - [ ] 50–200
   - [ ] More than 200 (cohort-scale)

4. Do you typically work with clinical samples (patient biopsies, blood, tumour specimens)?
   - [ ] Yes, exclusively
   - [ ] Yes, alongside cell line or animal data
   - [ ] No, primarily cell lines or animal models

5. Do you currently have RNA-seq data that is sitting unanalysed (or partially analysed) because of bandwidth or computational access constraints?
   - [ ] Yes — approximately how much data / how many samples? _______________
   - [ ] No

---

**Section 2 — About your current analysis process**

6. How do you currently run RNA-seq analyses?
   - [ ] I write my own scripts (R / Python / Bash)
   - [ ] I use a pipeline (nf-core, Snakemake, Galaxy, etc.)
   - [ ] I hand off to a bioinformatician or core facility
   - [ ] I use a cloud platform (DNAnexus, Terra, Seven Bridges, etc.)
   - [ ] I do not currently analyse RNA-seq myself

7. What is the biggest bottleneck in your current workflow?
   - [ ] Getting raw FASTQ files processed (alignment, QC)
   - [ ] Running differential expression analysis
   - [ ] Interpreting results biologically (pathway enrichment, literature)
   - [ ] Generating figures for papers or presentations
   - [ ] Maintaining reproducibility across projects
   - [ ] Keeping up with new tools and best practices
   - [ ] Other: _______________

8. How long does it typically take from receiving raw data to having a DE result you can act on?
   - [ ] Less than 1 day
   - [ ] 1–3 days
   - [ ] 1–2 weeks
   - [ ] More than 2 weeks

9. Do you currently apply QC thresholds before interpreting RNA-seq results?
   - [ ] Yes, with a defined set of metrics and thresholds
   - [ ] Yes, informally (I look at MultiQC reports)
   - [ ] Sometimes, depending on the project
   - [ ] No systematic QC step at present

---

**Section 3 — About your scientific goals**

10. Which of the following best describes what you want to do with RNA-seq results?
    (Select all that apply)
    - [ ] Find differentially expressed genes between conditions
    - [ ] Understand which biological pathways are active
    - [ ] Discover patient subtypes or disease stratifications
    - [ ] Connect gene expression to clinical outcomes (survival, response)
    - [ ] Identify cell types and their proportions in tissue
    - [ ] Find biomarker signatures for a diagnostic or therapeutic target
    - [ ] Detect gene fusions or structural rearrangements
    - [ ] Understand miRNA–mRNA regulatory relationships
    - [ ] Design or optimise a synthetic mRNA (vaccine, CAR-T, gene therapy)
    - [ ] Other: _______________

11. Do you work with matched multi-omics data alongside RNA-seq?
    (e.g. proteomics, ATAC-seq, WES/WGS, metabolomics)
    - [ ] Yes — which modalities? _______________
    - [ ] No, RNA-seq only

12. Is reproducibility or auditability of your analysis important for your work?
    (e.g. for publication, regulatory submission, clinical validation, multi-site study)
    - [ ] Yes — please describe the context briefly: _______________
    - [ ] Not a current priority

---

**Section 4 — About your computing setup**

13. Where does your computation currently happen?
    - [ ] My own laptop or desktop
    - [ ] A shared HPC cluster at my institution
    - [ ] Cloud compute (AWS, Google Cloud, Azure)
    - [ ] A combination

14. Do you have access to a cloud compute account for large analyses, or would you
    need BioMate to provide that infrastructure?
    - [ ] I have my own cloud account
    - [ ] My institution has a cloud allocation
    - [ ] I would need BioMate to provide it
    - [ ] I am not sure

15. Is there a specific storage or data residency requirement for your samples?
    (e.g. patient data must stay within a specific country or institutional boundary)
    - [ ] Yes — please describe: _______________
    - [ ] No

---

**Section 5 — Open questions**

16. What would a successful first session with BioMate look like for you?
    (What would you need to see to know BioMate is useful for your lab?)

17. Is there a specific dataset, comparison, or scientific question you would want
    to run as your first real test?

18. Is there anything about your current RNA-seq workflow that you would *not* want
    a platform to change or automate?

19. What tool or result format do your collaborators or journals expect?
    (e.g. DESeq2 specifically, specific figure styles, specific report format)

20. Any other questions, concerns, or things you want us to know before you try BioMate?

---

## What Happens After You Answer

Once we have your answers, we will:

1. **Pre-configure your environment** — set the right QC profile, reference genome,
   and default tools for your sample type before your first session.

2. **Prepare a worked example** — take one of your existing analyses (or a public
   dataset matching your sample type) and walk through it with you in BioMate,
   step by step, so you can see exactly what the platform does.

3. **Identify any gaps** — if a workflow you need is not yet in BioMate,
   we will tell you honestly, give you a timeline, and in some cases build it
   before your session.

4. **Follow up** — after your first session, we will ask for specific feedback on
   what worked, what didn't, and what you would need before you could use BioMate
   routinely in your lab.

---

*BioMate AI · biomate.ai · Confidential beta programme document*
