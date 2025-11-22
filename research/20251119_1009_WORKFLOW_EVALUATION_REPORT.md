# Galaxy Workflow Quality Evaluation Report
**Date:** 2025-11-19 10:09
**Total Workflows Evaluated:** 951
**Kept:** 928 (97.6%)
**Rejected:** 23 (2.4%)
**Keep Threshold:** 50/100

---
## Score Distribution
- **Min:** -5
- **Max:** 165
- **Mean:** 152.1
- **Median:** 165

## Kept Workflows by Domain
- **genomics:** 516
- **epigenomics:** 437
- **alignment:** 404
- **quality_control:** 364
- **long_read:** 169
- **assembly:** 156
- **transcriptomics:** 64
- **metagenomics:** 33
- **annotation:** 27
- **proteomics:** 21
- **single_cell:** 20
- **phylogenetics:** 16

---
## Top 50 Highest Quality Workflows
These are the best workflows that should definitely be included.

### 1. ChIPseq_PE (release v0.8)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 13
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow takes as input a collection of paired fastqs. Remove adapters with cutadapt, map pairs with bowtie2. Keep MAPQ30 and concordant pairs. MACS2 for paired bam.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (170 chars)
  [+20] Complex workflow (13 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 9 labeled outputs
  [+10] Well-connected pipeline (14 connections)
  [+5] Appears to be versioned release

### 2. CUTandRUN (release v0.11)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 15
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow take as input a collection of paired fastq. Remove adapters with cutadapt, map pairs with bowtie2 allowing dovetail. Keep MAPQ30 and concordant pairs. BAM to BED. MACS2 with "ATAC" param...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (206 chars)
  [+20] Complex workflow (15 steps)
  [+10] Has tags: ['CUTnRUN']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 10 labeled outputs
  [+10] Well-connected pipeline (17 connections)
  [+5] Appears to be versioned release

### 3. CUTandRUN (release v0.13)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 15
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow take as input a collection of paired fastq. Remove adapters with cutadapt, map pairs with bowtie2 allowing dovetail. Keep MAPQ30 and concordant pairs. BAM to BED. MACS2 with "ATAC" param...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (206 chars)
  [+20] Complex workflow (15 steps)
  [+10] Has tags: ['CUTnRUN']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 10 labeled outputs
  [+10] Well-connected pipeline (17 connections)
  [+5] Appears to be versioned release

### 4. bacterial_genome_annotation (release v1.1.11)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 10
- **Domains:** genomics, annotation
- **Description:** Annotation of an assembled bacterial genomes to detect genes, potential plasmids, integrons and Insertion sequence (IS) elements.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (129 chars)
  [+20] Complex workflow (10 steps)
  [+10] Has tags: ['Genomics', 'fasta', 'ABRomics', 'bacterial-genomics', 'Annotation', 'genome-annotation']
  [+15] Has creator attribution: ['ABRomics', 'abromics-consortium', 'Pierre Marin', 'Clea Siguret']
  [+10] Has license: GPL-3.0-or-later
  [+10] Has 29 labeled outputs
  [+10] Well-connected pipeline (34 connections)
  [+5] Appears to be versioned release

### 5. ATACseq (release v0.14)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 30
- **Domains:** epigenomics, alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It will remove bad quality and adapters with cutadapt. Map with Bowtie2 end-to-end. Will remove reads on MT and unconcordant pairs and pairs ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (555 chars)
  [+20] Complex workflow (30 steps)
  [+10] Has tags: ['ATACseq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (41 connections)
  [+5] Appears to be versioned release

### 6. Purge duplicate contigs from a diploid assembly VGP6 (release v0.10.2)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 61
- **Domains:** assembly, long_read
- **Description:** Purge contigs marked as duplicates by purge_dups (could be haplotypic duplication or overlap duplication). The contigs are purged from the first assembly (hap1, pri...), added to the second assembly (...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (469 chars)
  [+20] Complex workflow (61 steps)
  [+10] Has tags: ['VGP_curated']
  [+15] Has creator attribution: ['Galaxy', 'VGP']
  [+10] Has license: CC-BY-4.0
  [+10] Has 36 labeled outputs
  [+10] Well-connected pipeline (82 connections)
  [+5] Appears to be versioned release

### 7. ChIPseq_PE (release v0.9)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 13
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow takes as input a collection of paired fastqs. Remove adapters with cutadapt, map pairs with bowtie2. Keep MAPQ30 and concordant pairs. MACS2 for paired bam.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (170 chars)
  [+20] Complex workflow (13 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 9 labeled outputs
  [+10] Well-connected pipeline (14 connections)
  [+5] Appears to be versioned release

### 8. Genome Assembly from Hifi reads with HiC phasing - VGP4 (release v0.3.0)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 64
- **Domains:** genomics, assembly, long_read
- **Description:** Assemble Genome using PacBio HiFi and HiC data for phasing. Prerequisite: Run k-mer profiling workflow (VGP1). 

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (111 chars)
  [+20] Complex workflow (64 steps)
  [+10] Has tags: ['VGP', 'Reviewed']
  [+15] Has creator attribution: ['Galaxy', 'VGP', 'Delphine Lariviere']
  [+10] Has license: CC-BY-4.0
  [+10] Has 31 labeled outputs
  [+10] Well-connected pipeline (73 connections)
  [+5] Appears to be versioned release

### 9. ATACseq (release v0.13)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 30
- **Domains:** epigenomics, alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It will remove bad quality and adapters with cutadapt. Map with Bowtie2 end-to-end. Will remove reads on MT and unconcordant pairs and pairs ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (555 chars)
  [+20] Complex workflow (30 steps)
  [+10] Has tags: ['ATACseq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (41 connections)
  [+5] Appears to be versioned release

### 10. Get Confident Peaks From ChIP_PE replicates (release v1.0)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 26
- **Domains:** genomics, epigenomics, quality_control
- **Description:** This workflow takes as input PE BAM from ChIP-seq. It calls peaks on each replicate and intersect them. In parallel, each BAM is subsetted to smallest number of reads. Peaks are called using all subse...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (353 chars)
  [+20] Complex workflow (26 steps)
  [+10] Has tags: ['ATAC-seq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 5 labeled outputs
  [+10] Well-connected pipeline (30 connections)
  [+5] Appears to be versioned release

### 11. Influenza A isolate subtyping and consensus sequence generation (release v0.1)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 43
- **Domains:** General
- **Description:** This workflow performs subtyping and consensus sequence generation for batches of Illumina PE sequenced Influenza A isolates.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (125 chars)
  [+20] Complex workflow (43 steps)
  [+10] Has tags: ['AIV', 'virology']
  [+15] Has creator attribution: ['Wolfgang Maier', 'Viktoria Isabel Schwarz']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (53 connections)
  [+5] Appears to be versioned release

### 12. CUTandRUN (release v0.11)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 15
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow take as input a collection of paired fastq. Remove adapters with cutadapt, map pairs with bowtie2 allowing dovetail. Keep MAPQ30 and concordant pairs. BAM to BED. MACS2 with "ATAC" param...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (206 chars)
  [+20] Complex workflow (15 steps)
  [+10] Has tags: ['CUTnRUN']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 10 labeled outputs
  [+10] Well-connected pipeline (17 connections)
  [+5] Appears to be versioned release

### 13. Quality and Contamination Control For Genome Assembly (release v1.1)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 10
- **Domains:** genomics, metagenomics, assembly, quality_control, long_read
- **Description:** Short paired-end read analysis to provide quality analysis, read cleaning and taxonomy assignation

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (98 chars)
  [+20] Complex workflow (10 steps)
  [+10] Has tags: ['Genomics', 'fastq', 'bacterial-genomics', 'taxonomy-assignment', 'paired-end', 'quality', 'ABRomics', 'trimming']
  [+15] Has creator attribution: ['ABRomics', 'abromics-consortium', 'Pierre Marin', 'Clea Siguret']
  [+10] Has license: GPL-3.0-or-later
  [+10] Has 14 labeled outputs
  [+10] Well-connected pipeline (24 connections)
  [+5] Appears to be versioned release

### 14. Get Confident Peaks From ChIP_SR replicates (release v1.0)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 26
- **Domains:** genomics, epigenomics, quality_control
- **Description:** This workflow takes as input SR BAM from ChIP-seq. It calls peaks on each replicate and intersect them. In parallel, each BAM is subsetted to smallest number of reads. Peaks are called using all subse...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (353 chars)
  [+20] Complex workflow (26 steps)
  [+10] Has tags: ['ATAC-seq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 5 labeled outputs
  [+10] Well-connected pipeline (30 connections)
  [+5] Appears to be versioned release

### 15. ATACseq (release v0.16)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 30
- **Domains:** epigenomics, alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It will remove bad quality and adapters with cutadapt. Map with Bowtie2 end-to-end. Will remove reads on MT and unconcordant pairs and pairs ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (555 chars)
  [+20] Complex workflow (30 steps)
  [+10] Has tags: ['ATACseq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (41 connections)
  [+5] Appears to be versioned release

### 16. Purge duplicate contigs from a diploid assembly VGP6 (release v0.10)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 61
- **Domains:** assembly, long_read
- **Description:** Purge contigs marked as duplicates by purge_dups (could be haplotypic duplication or overlap duplication). The contigs are purged from the first assembly (hap1, pri...), added to the second assembly (...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (469 chars)
  [+20] Complex workflow (61 steps)
  [+10] Has tags: ['VGP_curated']
  [+15] Has creator attribution: ['Galaxy', 'VGP']
  [+10] Has license: CC-BY-4.0
  [+10] Has 36 labeled outputs
  [+10] Well-connected pipeline (82 connections)
  [+5] Appears to be versioned release

### 17. COVID-19: variation analysis on WGS SE (release v0.1.3)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 11
- **Domains:** genomics, alignment
- **Description:** This workflows performs single end read mapping with bowtie2 followed by sensitive variant calling across a wide range of AFs with lofreq

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (137 chars)
  [+20] Complex workflow (11 steps)
  [+10] Has tags: ['COVID-19', 'covid19.galaxyproject.org']
  [+15] Has creator attribution: ['Wolfgang Maier']
  [+10] Has license: MIT
  [+10] Has 12 labeled outputs
  [+10] Well-connected pipeline (15 connections)
  [+5] Appears to be versioned release

### 18. ChIPseq_PE (release v0.11)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 13
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow takes as input a collection of paired fastqs. Remove adapters with cutadapt, map pairs with bowtie2. Keep MAPQ30 and concordant pairs. MACS2 for paired bam.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (170 chars)
  [+20] Complex workflow (13 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 9 labeled outputs
  [+10] Well-connected pipeline (14 connections)
  [+5] Appears to be versioned release

### 19. ATACseq (release v0.16)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 30
- **Domains:** epigenomics, alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It will remove bad quality and adapters with cutadapt. Map with Bowtie2 end-to-end. Will remove reads on MT and unconcordant pairs and pairs ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (555 chars)
  [+20] Complex workflow (30 steps)
  [+10] Has tags: ['ATACseq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (41 connections)
  [+5] Appears to be versioned release

### 20. COVID-19: variation analysis on ARTIC PE (release v0.1)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 23
- **Domains:** genomics, transcriptomics, alignment, quality_control
- **Description:** The workflow for Illumina-sequenced ARTIC data builds on the RNASeq workflow for paired-end data using the same steps for mapping and variant calling, but adds extra logic for trimming ARTIC primer se...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (462 chars)
  [+20] Complex workflow (23 steps)
  [+10] Has tags: ['COVID-19', 'ARTIC', 'covid19.galaxyproject.org']
  [+15] Has creator attribution: ['Wolfgang Maier']
  [+10] Has license: MIT
  [+10] Has 23 labeled outputs
  [+10] Well-connected pipeline (34 connections)
  [+5] Appears to be versioned release

### 21. MGnify's amplicon pipeline v5.0 (release v0.1)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 41
- **Domains:** transcriptomics, metagenomics, quality_control, long_read
- **Description:** MGnify's amplicon pipeline v5.0. Including the Quality control for single-end and paired-end reads, rRNA-prediction, and ITS sub-WFs.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (133 chars)
  [+20] Complex workflow (41 steps)
  [+10] Has tags: ['MGnify_Amplicon', 'metagenomics', 'amplicon', 'name:microgalaxy']
  [+15] Has creator attribution: [" EMBL's European Bioinformatics Institute", 'Rand Zoabi', 'Paul Zierep']
  [+10] Has license: Apache-2.0
  [+10] Has 38 labeled outputs
  [+10] Well-connected pipeline (53 connections)
  [+5] Appears to be versioned release

### 22. ChIPseq_SR (release v0.2)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 11
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow takes as input a collection of fastqs (single reads). Remove adapters with cutadapt, map with bowtie2. Keep MAPQ30. MACS2 for bam with fixed extension or model.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (174 chars)
  [+20] Complex workflow (11 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 9 labeled outputs
  [+10] Well-connected pipeline (12 connections)
  [+5] Appears to be versioned release

### 23. Purge-duplicate-contigs-VGP6 (release v0.3.0)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 43
- **Domains:** long_read
- **Description:** Purge contigs marked as duplicates by purge_dups (could be haplotypic duplication or overlap duplication). This workflow is the 6th workflow of the VGP pipeline. It is meant to be run after one of the...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (239 chars)
  [+20] Complex workflow (43 steps)
  [+10] Has tags: ['VGP_curated']
  [+15] Has creator attribution: ['Galaxy', 'VGP']
  [+10] Has license: CC-BY-4.0
  [+10] Has 16 labeled outputs
  [+10] Well-connected pipeline (59 connections)
  [+5] Appears to be versioned release

### 24. cHi-C_fastqToCool_hicup_c (release v0.1)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 17
- **Domains:** alignment, quality_control
- **Description:** This workflow take as input a collection of paired fastq. It uses HiCUP to go from fastq to validPair file. The pairs are filtered for MAPQ and for the region captured. Then, they are sorted by cooler...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (304 chars)
  [+20] Complex workflow (17 steps)
  [+10] Has tags: ['Hi-C']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 8 labeled outputs
  [+10] Well-connected pipeline (24 connections)
  [+5] Appears to be versioned release

### 25. ChIPseq_SR (release v0.10)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 12
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow takes as input a collection of fastqs (single reads). Remove adapters with cutadapt, map with bowtie2. Keep MAPQ30. MACS2 for bam with fixed extension or model.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (174 chars)
  [+20] Complex workflow (12 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 9 labeled outputs
  [+10] Well-connected pipeline (13 connections)
  [+5] Appears to be versioned release

### 26. ChIPseq_SR (release v0.8)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 12
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow takes as input a collection of fastqs (single reads). Remove adapters with cutadapt, map with bowtie2. Keep MAPQ30. MACS2 for bam with fixed extension or model.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (174 chars)
  [+20] Complex workflow (12 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 9 labeled outputs
  [+10] Well-connected pipeline (13 connections)
  [+5] Appears to be versioned release

### 27. ChIPseq_PE (release v0.8)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 13
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow takes as input a collection of paired fastqs. Remove adapters with cutadapt, map pairs with bowtie2. Keep MAPQ30 and concordant pairs. MACS2 for paired bam.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (170 chars)
  [+20] Complex workflow (13 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 9 labeled outputs
  [+10] Well-connected pipeline (14 connections)
  [+5] Appears to be versioned release

### 28. scRNA-seq_preprocessing_10X_cellPlex (release v0.2)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 14
- **Domains:** transcriptomics, alignment, quality_control, single_cell
- **Description:** This workflow processes the CMO fastqs with CITE-seq-Count and include the translation step required for cellPlex processing. In parallel it processes the Gene Expresion fastqs with STARsolo, filter c...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (304 chars)
  [+20] Complex workflow (14 steps)
  [+10] Has tags: ['name:single-cell']
  [+15] Has creator attribution: ['Lucille Delisle', 'Mehmet Tekman', 'Hans-Rudolf Hotz', 'Daniel Blankenberg', 'Wendi Bacon']
  [+10] Has license: MIT
  [+10] Has 6 labeled outputs
  [+10] Well-connected pipeline (15 connections)
  [+5] Appears to be versioned release

### 29. Get Confident Peaks From ChIP_PE replicates (release v1.0)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 26
- **Domains:** genomics, epigenomics, quality_control
- **Description:** This workflow takes as input PE BAM from ChIP-seq. It calls peaks on each replicate and intersect them. In parallel, each BAM is subsetted to smallest number of reads. Peaks are called using all subse...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (353 chars)
  [+20] Complex workflow (26 steps)
  [+10] Has tags: ['ATAC-seq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 5 labeled outputs
  [+10] Well-connected pipeline (30 connections)
  [+5] Appears to be versioned release

### 30. Get Confident Peaks From ChIP_PE duplicates (release v0.7)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 20
- **Domains:** genomics, epigenomics, quality_control
- **Description:** This workflow takes as input PE BAM from ChIP-seq. It calls peaks on each replicate and intersect them. In parallel, each BAM is subsetted to smallest number of reads. Peaks are called using both subs...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (349 chars)
  [+20] Complex workflow (20 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 6 labeled outputs
  [+10] Well-connected pipeline (24 connections)
  [+5] Appears to be versioned release

### 31. K-mer profiling and reads statistics VGP1 (release v0.2)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 19
- **Domains:** genomics, assembly, quality_control, long_read
- **Description:** Evaluation of Pacbio Hifi Reads and genome profiling. Create Meryl Database used for the estimation of assembly parameters and quality control with Merqury. Part of the VGP pipeline.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (182 chars)
  [+20] Complex workflow (19 steps)
  [+10] Has tags: ['Reviewed', 'VGP']
  [+15] Has creator attribution: ['VGP', 'Galaxy']
  [+10] Has license: CC-BY-4.0
  [+10] Has 14 labeled outputs
  [+10] Well-connected pipeline (18 connections)
  [+5] Appears to be versioned release

### 32. Get Confident Peaks From ATAC or CUTandRUN duplicates (release v0.7)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 20
- **Domains:** genomics, epigenomics, quality_control
- **Description:** This workflow takes as input BED from ATAC-seq or CUT&amp;RUN. It calls peaks on each replicate and intersect them. In parallel, each BAM is subsetted to smallest number of reads. Peaks are called usi...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (361 chars)
  [+20] Complex workflow (20 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 6 labeled outputs
  [+10] Well-connected pipeline (24 connections)
  [+5] Appears to be versioned release

### 33. CUTandRUN (release v0.11)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 15
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow take as input a collection of paired fastq. Remove adapters with cutadapt, map pairs with bowtie2 allowing dovetail. Keep MAPQ30 and concordant pairs. BAM to BED. MACS2 with "ATAC" param...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (206 chars)
  [+20] Complex workflow (15 steps)
  [+10] Has tags: ['CUTnRUN']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 10 labeled outputs
  [+10] Well-connected pipeline (17 connections)
  [+5] Appears to be versioned release

### 34. ATACseq (release v0.16)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 30
- **Domains:** epigenomics, alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It will remove bad quality and adapters with cutadapt. Map with Bowtie2 end-to-end. Will remove reads on MT and unconcordant pairs and pairs ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (555 chars)
  [+20] Complex workflow (30 steps)
  [+10] Has tags: ['ATACseq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (41 connections)
  [+5] Appears to be versioned release

### 35. CUTandRUN (release v0.11)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 15
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow take as input a collection of paired fastq. Remove adapters with cutadapt, map pairs with bowtie2 allowing dovetail. Keep MAPQ30 and concordant pairs. BAM to BED. MACS2 with "ATAC" param...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (206 chars)
  [+20] Complex workflow (15 steps)
  [+10] Has tags: ['CUTnRUN']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 10 labeled outputs
  [+10] Well-connected pipeline (17 connections)
  [+5] Appears to be versioned release

### 36. CUTandRUN (release v0.11)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 15
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow take as input a collection of paired fastq. Remove adapters with cutadapt, map pairs with bowtie2 allowing dovetail. Keep MAPQ30 and concordant pairs. BAM to BED. MACS2 with "ATAC" param...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (206 chars)
  [+20] Complex workflow (15 steps)
  [+10] Has tags: ['CUTnRUN']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 10 labeled outputs
  [+10] Well-connected pipeline (17 connections)
  [+5] Appears to be versioned release

### 37. Purge-duplicate-contigs-VGP6 (release v0.3.3)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 43
- **Domains:** long_read
- **Description:** Purge contigs marked as duplicates by purge_dups (could be haplotypic duplication or overlap duplication). This workflow is the 6th workflow of the VGP pipeline. It is meant to be run after one of the...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (239 chars)
  [+20] Complex workflow (43 steps)
  [+10] Has tags: ['VGP_curated']
  [+15] Has creator attribution: ['Galaxy', 'VGP']
  [+10] Has license: CC-BY-4.0
  [+10] Has 16 labeled outputs
  [+10] Well-connected pipeline (59 connections)
  [+5] Appears to be versioned release

### 38. ATACseq (release v0.13)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 30
- **Domains:** epigenomics, alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It will remove bad quality and adapters with cutadapt. Map with Bowtie2 end-to-end. Will remove reads on MT and unconcordant pairs and pairs ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (555 chars)
  [+20] Complex workflow (30 steps)
  [+10] Has tags: ['ATACseq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (41 connections)
  [+5] Appears to be versioned release

### 39. ATACseq (release v0.16)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 30
- **Domains:** epigenomics, alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It will remove bad quality and adapters with cutadapt. Map with Bowtie2 end-to-end. Will remove reads on MT and unconcordant pairs and pairs ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (555 chars)
  [+20] Complex workflow (30 steps)
  [+10] Has tags: ['ATACseq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (41 connections)
  [+5] Appears to be versioned release

### 40. ATACseq (release v0.14)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 30
- **Domains:** epigenomics, alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It will remove bad quality and adapters with cutadapt. Map with Bowtie2 end-to-end. Will remove reads on MT and unconcordant pairs and pairs ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (555 chars)
  [+20] Complex workflow (30 steps)
  [+10] Has tags: ['ATACseq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (41 connections)
  [+5] Appears to be versioned release

### 41. Hi-C_fastqToCool_hicup_c (release v0.3)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 12
- **Domains:** alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It uses HiCUP to go from fastq to validPair file using the middle of the fragment as coordinates. The pairs are filtered for MAPQ and sorted ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (313 chars)
  [+20] Complex workflow (12 steps)
  [+10] Has tags: ['Hi-C']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 8 labeled outputs
  [+10] Well-connected pipeline (13 connections)
  [+5] Appears to be versioned release

### 42. ChIPseq_SR (release v0.8)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 12
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow takes as input a collection of fastqs (single reads). Remove adapters with cutadapt, map with bowtie2. Keep MAPQ30. MACS2 for bam with fixed extension or model.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (174 chars)
  [+20] Complex workflow (12 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 9 labeled outputs
  [+10] Well-connected pipeline (13 connections)
  [+5] Appears to be versioned release

### 43. ATACseq (release v0.16)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 30
- **Domains:** epigenomics, alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It will remove bad quality and adapters with cutadapt. Map with Bowtie2 end-to-end. Will remove reads on MT and unconcordant pairs and pairs ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (555 chars)
  [+20] Complex workflow (30 steps)
  [+10] Has tags: ['ATACseq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (41 connections)
  [+5] Appears to be versioned release

### 44. Get Confident Peaks From ChIP_SR replicates (release v1.0)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 26
- **Domains:** genomics, epigenomics, quality_control
- **Description:** This workflow takes as input SR BAM from ChIP-seq. It calls peaks on each replicate and intersect them. In parallel, each BAM is subsetted to smallest number of reads. Peaks are called using all subse...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (353 chars)
  [+20] Complex workflow (26 steps)
  [+10] Has tags: ['ATAC-seq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 5 labeled outputs
  [+10] Well-connected pipeline (30 connections)
  [+5] Appears to be versioned release

### 45. ChIPseq_PE (release v0.9)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 13
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow takes as input a collection of paired fastqs. Remove adapters with cutadapt, map pairs with bowtie2. Keep MAPQ30 and concordant pairs. MACS2 for paired bam.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (170 chars)
  [+20] Complex workflow (13 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 9 labeled outputs
  [+10] Well-connected pipeline (14 connections)
  [+5] Appears to be versioned release

### 46. CUTandRUN (release v0.4)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 15
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow take as input a collection of paired fastq. Remove adapters with cutadapt, map pairs with bowtie2 allowing dovetail. Keep MAPQ30 and concordant pairs. BAM to BED. MACS2 with "ATAC" param...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (206 chars)
  [+20] Complex workflow (15 steps)
  [+10] Has tags: ['CUTnRUN']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 10 labeled outputs
  [+10] Well-connected pipeline (17 connections)
  [+5] Appears to be versioned release

### 47. ATACseq (release v0.13)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 30
- **Domains:** epigenomics, alignment, quality_control
- **Description:** This workflow takes as input a collection of paired fastq. It will remove bad quality and adapters with cutadapt. Map with Bowtie2 end-to-end. Will remove reads on MT and unconcordant pairs and pairs ...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (555 chars)
  [+20] Complex workflow (30 steps)
  [+10] Has tags: ['ATACseq']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 13 labeled outputs
  [+10] Well-connected pipeline (41 connections)
  [+5] Appears to be versioned release

### 48. ChIPseq_PE (release v0.10)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 13
- **Domains:** genomics, epigenomics, alignment
- **Description:** This workflow takes as input a collection of paired fastqs. Remove adapters with cutadapt, map pairs with bowtie2. Keep MAPQ30 and concordant pairs. MACS2 for paired bam.

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (170 chars)
  [+20] Complex workflow (13 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 9 labeled outputs
  [+10] Well-connected pipeline (14 connections)
  [+5] Appears to be versioned release

### 49. Purge duplicate contigs (WF6 (release v0.1.1)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 43
- **Domains:** long_read
- **Description:** Purge contigs marked as duplicates by purge_dups (could be haplotypic duplication or overlap duplication). This workflow is the 6th workflow of the VGP pipeline. It is meant to be run after one of the...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (239 chars)
  [+20] Complex workflow (43 steps)
  [+10] Has tags: ['VGP_curated']
  [+15] Has creator attribution: ['Galaxy', 'VGP']
  [+10] Has license: CC-BY-4.0
  [+10] Has 16 labeled outputs
  [+10] Well-connected pipeline (59 connections)
  [+5] Appears to be versioned release

### 50. Get Confident Peaks From ChIP_PE duplicates (release v0.3)
- **Score:** 165/100
- **Owner:** iwc
- **Steps:** 20
- **Domains:** genomics, epigenomics, quality_control
- **Description:** This workflow takes as input PE BAM from ChIP-seq. It calls peaks on each replicate and intersect them. In parallel, each BAM is subsetted to smallest number of reads. Peaks are called using both subs...

**Evaluation:**
  [+40] Base score for valid workflow
  [+25] Trusted owner: iwc
  [+20] Has meaningful annotation (349 chars)
  [+20] Complex workflow (20 steps)
  [+10] Has tags: ['ChIP']
  [+15] Has creator attribution: ['Lucille Delisle']
  [+10] Has license: MIT
  [+10] Has 6 labeled outputs
  [+10] Well-connected pipeline (24 connections)
  [+5] Appears to be versioned release

---
## All Kept Workflows Summary

| Score | Name | Owner | Steps | Domains |
|-------|------|-------|-------|----------|
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.13) | iwc | 15 | genomics, epigenomics |
| 165 | bacterial_genome_annotation (release v1.... | iwc | 10 | genomics, annotation |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Purge duplicate contigs from a diploid a... | iwc | 61 | assembly, long_read |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | Genome Assembly from Hifi reads with HiC... | iwc | 64 | genomics, assembly |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | Influenza A isolate subtyping and consen... | iwc | 43 | - |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | Quality and Contamination Control For Ge... | iwc | 10 | genomics, metagenomics |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | ATACseq (release v0.16) | iwc | 30 | epigenomics, alignment |
| 165 | Purge duplicate contigs from a diploid a... | iwc | 61 | assembly, long_read |
| 165 | COVID-19: variation analysis on WGS SE (... | iwc | 11 | genomics, alignment |
| 165 | ChIPseq_PE (release v0.11) | iwc | 13 | genomics, epigenomics |
| 165 | ATACseq (release v0.16) | iwc | 30 | epigenomics, alignment |
| 165 | COVID-19: variation analysis on ARTIC PE... | iwc | 23 | genomics, transcriptomics |
| 165 | MGnify's amplicon pipeline v5.0 (release... | iwc | 41 | transcriptomics, metagenomics |
| 165 | ChIPseq_SR (release v0.2) | iwc | 11 | genomics, epigenomics |
| 165 | Purge-duplicate-contigs-VGP6 (release v0... | iwc | 43 | long_read |
| 165 | cHi-C_fastqToCool_hicup_c (release v0.1) | iwc | 17 | alignment, quality_control |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | scRNA-seq_preprocessing_10X_cellPlex (re... | iwc | 14 | transcriptomics, alignment |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | K-mer profiling and reads statistics VGP... | iwc | 19 | genomics, assembly |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | ATACseq (release v0.16) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | Purge-duplicate-contigs-VGP6 (release v0... | iwc | 43 | long_read |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.16) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Hi-C_fastqToCool_hicup_c (release v0.3) | iwc | 12 | alignment, quality_control |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ATACseq (release v0.16) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.4) | iwc | 15 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | Purge duplicate contigs (WF6 (release v0... | iwc | 43 | long_read |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | scRNA-seq_preprocessing_10X_cellPlex (re... | iwc | 14 | transcriptomics, alignment |
| 165 | CUTandRUN (release v0.12) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | RNA-seq for Paired-end fastqs (release v... | iwc | 27 | transcriptomics, alignment |
| 165 | ATACseq (release v0.4) | iwc | 22 | epigenomics, alignment |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.2) | iwc | 12 | genomics, epigenomics |
| 165 | ATACseq (release v0.9) | iwc | 30 | epigenomics, alignment |
| 165 | scRNA-seq_preprocessing_10X_cellPlex (re... | iwc | 14 | transcriptomics, alignment |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | Scaffolding with Hi-C data VGP8 (release... | iwc | 44 | genomics, assembly |
| 165 | MGnify's amplicon pipeline v5.0 (release... | iwc | 41 | transcriptomics, metagenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | Single-Cell RNA-seq Preprocessing: 10X G... | iwc | 14 | genomics, transcriptomics |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | bacterial_genome_annotation (release v1.... | iwc | 10 | genomics, annotation |
| 165 | RNA-seq for Single-read fastqs (release ... | iwc | 25 | transcriptomics, alignment |
| 165 | Pox Virus Illumina Amplicon Workflow fro... | iwc | 47 | genomics, quality_control |
| 165 | MGnify's amplicon pipeline v5.0 - Qualit... | iwc | 29 | metagenomics, quality_control |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | COVID-19: consensus construction (releas... | iwc | 23 | genomics, quality_control |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.13) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | ChIP-seq Analysis: Single-End Read Proce... | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.11) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | RNAseq_SR (release v0.4) | iwc | 25 | transcriptomics, alignment |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | Scaffolding with Hi-C data VGP8 (release... | iwc | 60 | genomics, assembly |
| 165 | Purging duplicates in one haplotype VGP6... | iwc | 44 | long_read |
| 165 | CUTandRUN (release v0.12) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.11) | iwc | 13 | genomics, epigenomics |
| 165 | Genome Assembly from Hifi reads with HiC... | iwc | 64 | genomics, assembly |
| 165 | Scaffolding with Hi-C data VGP8 (release... | iwc | 38 | genomics, assembly |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | RNAseq_SR (release v0.4.1) | iwc | 25 | transcriptomics, alignment |
| 165 | Generic variation analysis on WGS PE (re... | iwc | 15 | genomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | COVID-19: variation analysis on ARTIC PE... | iwc | 27 | genomics, transcriptomics |
| 165 | ATACseq (release v0.1) | iwc | 22 | epigenomics, alignment |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.11) | iwc | 12 | genomics, epigenomics |
| 165 | COVID-19: variation analysis reporting (... | iwc | 36 | genomics, quality_control |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.11) | iwc | 12 | genomics, epigenomics |
| 165 | Purge duplicate contigs from a diploid a... | iwc | 54 | assembly, long_read |
| 165 | RNAseq_SR (release v0.7) | iwc | 20 | transcriptomics, alignment |
| 165 | ATACseq (release v0.2) | iwc | 22 | epigenomics, alignment |
| 165 | dada2 amplicon analysis pipeline - for p... | iwc | 19 | genomics, metagenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | COVID-19: variation analysis on WGS PE (... | iwc | 13 | genomics, alignment |
| 165 | SARS-CoV-2 Illumina Amplicon pipeline - ... | iwc | 21 | genomics, annotation |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Purging duplicates in one haplotype VGP6... | iwc | 44 | long_read |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.12) | iwc | 12 | genomics, epigenomics |
| 165 | RNA-seq for Single-read fastqs (release ... | iwc | 25 | transcriptomics, alignment |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ATACseq (release v0.8) | iwc | 30 | epigenomics, alignment |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.6) | iwc | 15 | genomics, epigenomics |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | kmer-profiling-hifi-trio-VGP2 (release v... | iwc | 16 | assembly, quality_control |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | RNA-seq for Paired-end fastqs (release v... | iwc | 27 | transcriptomics, alignment |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | COVID-19: consensus construction (releas... | iwc | 28 | genomics, quality_control |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | Allele-based Pathogen Identification (re... | iwc | 26 | genomics, metagenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | RNAseq_DE_filtering_plotting (release v0... | iwc | 25 | transcriptomics, quality_control |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ATACseq (release v0.16) | iwc | 30 | epigenomics, alignment |
| 165 | ChIPseq_PE (release v0.13) | iwc | 13 | genomics, epigenomics |
| 165 | kmer-profiling-hifi-trio-VGP2 (release v... | iwc | 15 | assembly, quality_control |
| 165 | Purging duplicates in one haplotype VGP6... | iwc | 44 | long_read |
| 165 | COVID-19: variation analysis on WGS PE (... | iwc | 13 | genomics, alignment |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | Paired end variant calling in haploid sy... | iwc | 16 | genomics |
| 165 | Quality and Contamination Control For Ge... | iwc | 10 | genomics, metagenomics |
| 165 | RNAseq_PE (release v0.4.1) | iwc | 27 | transcriptomics, alignment |
| 165 | ChIPseq_SR (release v0.3) | iwc | 11 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.11) | iwc | 13 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | MGnify's amplicon pipeline v5.0 - Qualit... | iwc | 29 | metagenomics, quality_control |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | RNAseq_PE (release v0.9) | iwc | 21 | transcriptomics, alignment |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | Genome annotation with Helix (release v0... | iwc | 10 | genomics, proteomics |
| 165 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 62 | genomics, assembly |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | COVID-19: variation analysis of ARTIC ON... | iwc | 19 | genomics, alignment |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | COVID-19: variation analysis reporting (... | iwc | 36 | genomics, quality_control |
| 165 | Assembly-Hifi-only-VGP3 (release v0.3.0) | iwc | 55 | genomics, assembly |
| 165 | Genome Assembly from Hifi reads with HiC... | iwc | 66 | genomics, assembly |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | kmer-profiling-hifi-trio-VGP2 (release v... | iwc | 15 | assembly, quality_control |
| 165 | CUTandRUN (release v0.12) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | COVID-19: consensus construction (releas... | iwc | 23 | genomics, quality_control |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | COVID-19: variation analysis of ARTIC ON... | iwc | 19 | genomics, alignment |
| 165 | COVID-19: variation analysis reporting (... | iwc | 39 | genomics, quality_control |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.6.1) | iwc | 15 | genomics, epigenomics |
| 165 | Scaffolding with Hi-C data VGP8 (release... | iwc | 38 | genomics, assembly |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | kmer-profiling-hifi-trio-VGP2 (release v... | iwc | 15 | assembly, quality_control |
| 165 | Assembly-decontamination-VGP9 (release v... | iwc | 12 | genomics, metagenomics |
| 165 | COVID-19: variation analysis on WGS SE (... | iwc | 11 | genomics, alignment |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | Scaffolding with Hi-C data VGP8 (release... | iwc | 38 | genomics, assembly |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Purge-duplicate-contigs-VGP6 (release v0... | iwc | 43 | long_read |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | Genome Assembly from Hifi reads with HiC... | iwc | 69 | genomics, assembly |
| 165 | COVID-19: consensus construction (releas... | iwc | 28 | genomics, quality_control |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | COVID-19: consensus construction (releas... | iwc | 28 | genomics, quality_control |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | Hi-C_fastqToCool_hicup_c (release v0.2.1... | iwc | 12 | alignment, quality_control |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | COVID-19: variation analysis on ARTIC PE... | iwc | 33 | genomics, transcriptomics |
| 165 | ChIPseq_PE (release v0.5) | iwc | 13 | genomics, epigenomics |
| 165 | scRNA-seq_preprocessing_10X_cellPlex (re... | iwc | 14 | transcriptomics, alignment |
| 165 | CUTandRUN (release v0.12) | iwc | 15 | genomics, epigenomics |
| 165 | COVID-19: variation analysis on ARTIC PE... | iwc | 27 | genomics, transcriptomics |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | Clinical Metaproteomics Data Interpretat... | iwc | 11 | proteomics, annotation |
| 165 | ATACseq (release v0.16) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | Scaffolding with Hi-C data VGP8 (release... | iwc | 42 | genomics, assembly |
| 165 | ATACseq (release v0.5) | iwc | 29 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | Purge-duplicate-contigs-VGP6 (release v0... | iwc | 43 | long_read |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | Allele-based Pathogen Identification (re... | iwc | 26 | genomics, metagenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | Purge-duplicate-contigs-VGP6 (release v0... | iwc | 43 | long_read |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | bacterial_genome_annotation (release v1.... | iwc | 10 | genomics, annotation |
| 165 | CUTandRUN (release v0.5) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | Quality and Contamination Control For Ge... | iwc | 10 | genomics, metagenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.4) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | Purge-duplicate-contigs-VGP6 (release v0... | iwc | 43 | long_read |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | COVID-19: variation analysis reporting (... | iwc | 36 | genomics, quality_control |
| 165 | Pox Virus Illumina Amplicon Workflow fro... | iwc | 47 | genomics, quality_control |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 62 | genomics, assembly |
| 165 | Purge duplicate contigs from a diploid a... | iwc | 54 | assembly, long_read |
| 165 | COVID-19: variation analysis on WGS SE (... | iwc | 11 | genomics, alignment |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | Genome Assembly with Pacbio Hifi reads a... | iwc | 64 | genomics, assembly |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | cHi-C_fastqToCool_hicup_c (release v0.3) | iwc | 17 | alignment, quality_control |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | bacterial_genome_annotation (release v1.... | iwc | 10 | genomics, annotation |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.14) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | COVID-19: variation analysis on ARTIC PE... | iwc | 33 | genomics, transcriptomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | RNA-seq for Single-read fastqs (release ... | iwc | 25 | transcriptomics, alignment |
| 165 | Bacterial Genome Assembly using Shov (re... | iwc | 11 | genomics, assembly |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | RNA-seq for Paired-end fastqs (release v... | iwc | 27 | transcriptomics, alignment |
| 165 | COVID-19: variation analysis of ARTIC ON... | iwc | 27 | genomics, alignment |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Purging duplicates in one haplotype VGP6... | iwc | 52 | long_read |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.12) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.2) | iwc | 14 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | ChIPseq_PE (release v0.3) | iwc | 12 | genomics, epigenomics |
| 165 | Purge duplicate contigs from a diploid a... | iwc | 60 | assembly, long_read |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 62 | genomics, assembly |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.4) | iwc | 12 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.11) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.11) | iwc | 13 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.11) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.11) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | Genome Assembly with Pacbio Hifi reads a... | iwc | 62 | genomics, assembly |
| 165 | kmer-profiling-hifi-trio-VGP2 (release v... | iwc | 16 | assembly, quality_control |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.11) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.12) | iwc | 15 | genomics, epigenomics |
| 165 | K-mer profiling and reads statistics VGP... | iwc | 19 | genomics, assembly |
| 165 | COVID-19: consensus construction (releas... | iwc | 28 | genomics, quality_control |
| 165 | Bacterial Genome Assembly using Shov (re... | iwc | 11 | genomics, assembly |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Genome Assembly with Pacbio Hifi reads a... | iwc | 64 | genomics, assembly |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | Purging duplicates in one haplotype VGP6... | iwc | 52 | long_read |
| 165 | CUTandRUN (release v0.12) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.5) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | ATACseq (release v0.3) | iwc | 22 | epigenomics, alignment |
| 165 | RNAseq_SR (release v0.8) | iwc | 20 | transcriptomics, alignment |
| 165 | RNAseq_PE (release v0.7) | iwc | 21 | transcriptomics, alignment |
| 165 | Purge duplicate contigs from a diploid a... | iwc | 54 | assembly, long_read |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.11) | iwc | 12 | genomics, epigenomics |
| 165 | Genome Assembly from Hifi reads with HiC... | iwc | 69 | genomics, assembly |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | COVID-19: variation analysis of ARTIC ON... | iwc | 27 | genomics, alignment |
| 165 | ATACseq (release v0.7) | iwc | 30 | epigenomics, alignment |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | Purging duplicates in one haplotype VGP6... | iwc | 44 | long_read |
| 165 | CUTandRUN (release v0.12) | iwc | 15 | genomics, epigenomics |
| 165 | RNAseq_PE (release v0.4) | iwc | 27 | transcriptomics, alignment |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | Influenza A isolate subtyping and consen... | iwc | 70 | quality_control |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Genome Assembly from Hifi reads with HiC... | iwc | 68 | genomics, assembly |
| 165 | COVID-19: variation analysis reporting (... | iwc | 36 | genomics, quality_control |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | ATACseq (release v0.16) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | COVID-19: variation analysis on ARTIC PE... | iwc | 24 | genomics, transcriptomics |
| 165 | Assembly-Hifi-only-VGP3 (release v0.2.10... | iwc | 54 | genomics, assembly |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | ATACseq (release v0.16) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | SARS-CoV-2 Illumina Amplicon pipeline - ... | iwc | 21 | genomics, annotation |
| 165 | Assembly-Hifi-only-VGP3 (release v0.2.9) | iwc | 48 | genomics, assembly |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | COVID-19: variation analysis reporting (... | iwc | 36 | genomics, quality_control |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | Genome Assembly with Pacbio Hifi reads a... | iwc | 64 | genomics, assembly |
| 165 | RNAseq_SR (release v0.2) | iwc | 25 | transcriptomics, alignment |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | COVID-19: variation analysis on WGS PE (... | iwc | 13 | genomics, alignment |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | Purge-duplicate-contigs-VGP6 (release v0... | iwc | 43 | long_read |
| 165 | COVID-19: variation analysis on WGS PE (... | iwc | 13 | genomics, alignment |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.12) | iwc | 15 | genomics, epigenomics |
| 165 | COVID-19: variation analysis on ARTIC PE... | iwc | 33 | genomics, transcriptomics |
| 165 | COVID-19: variation analysis reporting (... | iwc | 36 | genomics, quality_control |
| 165 | RNAseq_PE (release v0.8) | iwc | 21 | transcriptomics, alignment |
| 165 | bacterial_genome_annotation (release v1.... | iwc | 10 | genomics, annotation |
| 165 | Purge-duplicate-contigs-VGP6 (release v0... | iwc | 54 | long_read |
| 165 | COVID-19: variation analysis on ARTIC PE... | iwc | 27 | genomics, transcriptomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | bacterial_genome_annotation (release v1.... | iwc | 10 | genomics, annotation |
| 165 | ATACseq (release v0.17) | iwc | 31 | epigenomics, alignment |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | RNA-Seq Differential Expression Analysis... | iwc | 25 | transcriptomics, alignment |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | Preprocessing and Clustering of single-c... | iwc | 68 | transcriptomics, quality_control |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | Genome Assembly with Pacbio Hifi reads a... | iwc | 57 | genomics, assembly |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | ChIP-seq Analysis: Paired-End Read Proce... | iwc | 13 | genomics, epigenomics |
| 165 | RNA-seq for Paired-end fastqs (release v... | iwc | 27 | transcriptomics, alignment |
| 165 | COVID-19: variation analysis on WGS SE (... | iwc | 11 | genomics, alignment |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | RNAseq_SR (release v0.5) | iwc | 20 | transcriptomics, alignment |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | cHi-C_fastqToCool_hicup_c (release v0.2.... | iwc | 17 | alignment, quality_control |
| 165 | ChIPseq_PE (release v0.11) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.11) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | scRNA-seq_preprocessing_10X_cellPlex (re... | iwc | 14 | transcriptomics, alignment |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | RNAseq_PE (release v0.5) | iwc | 21 | transcriptomics, alignment |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.1) | iwc | 11 | genomics, epigenomics |
| 165 | Hi-C_fastqToCool_hicup_c (release v0.2) | iwc | 12 | alignment, quality_control |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR replica... | iwc | 26 | genomics, epigenomics |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | ChIPseq_SR (release v0.11) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | SARS-CoV-2 Illumina Amplicon pipeline - ... | iwc | 21 | genomics, annotation |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.11) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | bacterial_genome_annotation (release v1.... | iwc | 10 | genomics, annotation |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | ATACseq (release v0.6) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | RNAseq_SR (release v0.9) | iwc | 20 | transcriptomics, alignment |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Genome Assembly from Hifi reads with HiC... | iwc | 68 | genomics, assembly |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.12) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | Quality and Contamination Control For Ge... | iwc | 12 | genomics, metagenomics |
| 165 | Quality and Contamination Control For Ge... | iwc | 12 | genomics, metagenomics |
| 165 | Scaffolding with Hi-C data VGP8 (release... | iwc | 46 | genomics, assembly |
| 165 | Allele-based Pathogen Identification (re... | iwc | 26 | genomics, metagenomics |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | RNAseq_DE_filtering_plotting (release v0... | iwc | 25 | transcriptomics, quality_control |
| 165 | RNAseq_DE_filtering_plotting (release v0... | iwc | 25 | transcriptomics, quality_control |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | cHi-C_fastqToCool_hicup_c (release v0.2) | iwc | 17 | alignment, quality_control |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.9) | iwc | 13 | genomics, epigenomics |
| 165 | Purge duplicate contigs (WF6 (release v0... | iwc | 43 | long_read |
| 165 | Gene-based Pathogen Identification (rele... | iwc | 16 | phylogenetics, long_read |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | Quality and Contamination Control For Ge... | iwc | 10 | genomics, metagenomics |
| 165 | ATACseq (release v1.0) | iwc | 31 | epigenomics, alignment |
| 165 | ChIPseq_SR (release v0.11) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | Scaffolding with Hi-C data VGP8 (release... | iwc | 36 | genomics, assembly |
| 165 | Purging duplicates in one haplotype VGP6... | iwc | 44 | long_read |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | SARS-CoV-2 Illumina Amplicon pipeline - ... | iwc | 21 | genomics, annotation |
| 165 | COVID-19: consensus construction (releas... | iwc | 23 | genomics, quality_control |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | ChIP-seq Analysis: Paired-End Read Proce... | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.3) | iwc | 14 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | Clinical Metaproteomics Discovery Workfl... | iwc | 27 | proteomics, quality_control |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | Purge duplicate contigs from a diploid a... | iwc | 61 | assembly, long_read |
| 165 | Scaffolding with Hi-C data VGP8 (release... | iwc | 38 | genomics, assembly |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | Purging duplicates in one haplotype VGP6... | iwc | 51 | long_read |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | SARS-CoV-2 Illumina Amplicon pipeline - ... | iwc | 21 | genomics, annotation |
| 165 | dada2 amplicon analysis pipeline - for p... | iwc | 19 | genomics, metagenomics |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 28 | genomics, epigenomics |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.5.1) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.16) | iwc | 30 | epigenomics, alignment |
| 165 | Purge-duplicate-contigs-VGP6 (release v0... | iwc | 43 | long_read |
| 165 | Assembly-decontamination-VGP9 (release v... | iwc | 12 | genomics, metagenomics |
| 165 | Purge duplicate contigs from a diploid a... | iwc | 54 | assembly, long_read |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | Generic variation analysis reporting (re... | iwc | 35 | genomics, quality_control |
| 165 | Genome Assembly from Hifi reads with HiC... | iwc | 64 | genomics, assembly |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | COVID-19: variation analysis on WGS PE (... | iwc | 13 | genomics, alignment |
| 165 | Genome Assembly from Hifi reads with HiC... | iwc | 69 | genomics, assembly |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.10) | iwc | 12 | genomics, epigenomics |
| 165 | bacterial_genome_annotation (release v1.... | iwc | 10 | genomics, annotation |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.10) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | RNAseq_PE (release v0.3) | iwc | 27 | transcriptomics, alignment |
| 165 | Quality and Contamination Control For Ge... | iwc | 10 | genomics, metagenomics |
| 165 | ChIP-seq Analysis: Single-End Read Proce... | iwc | 12 | genomics, epigenomics |
| 165 | Genome Assembly from Hifi reads - VGP3 (... | iwc | 55 | genomics, assembly |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.9) | iwc | 15 | genomics, epigenomics |
| 165 | RNAseq_PE (release v0.1) | iwc | 27 | transcriptomics, alignment |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | Purging duplicates in one haplotype VGP6... | iwc | 52 | long_read |
| 165 | ChIPseq_PE (release v0.8) | iwc | 13 | genomics, epigenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | Get Confident Peaks From ChIP_SR duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | Allele-based Pathogen Identification (re... | iwc | 26 | genomics, metagenomics |
| 165 | COVID-19: variation analysis on ARTIC PE... | iwc | 27 | genomics, transcriptomics |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | COVID-19: variation analysis of ARTIC ON... | iwc | 19 | genomics, alignment |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | COVID-19: variation analysis on WGS SE (... | iwc | 11 | genomics, alignment |
| 165 | ChIPseq_SR (release v0.11) | iwc | 12 | genomics, epigenomics |
| 165 | Quality and Contamination Control For Ge... | iwc | 10 | genomics, metagenomics |
| 165 | Bacterial Genome Assembly using Shov (re... | iwc | 11 | genomics, assembly |
| 165 | RNAseq_PE (release v0.2) | iwc | 27 | transcriptomics, alignment |
| 165 | ATACseq (release v0.13) | iwc | 30 | epigenomics, alignment |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | Hi-C_fastqToCool_hicup_c (release v0.1) | iwc | 12 | alignment, quality_control |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | ChIPseq_PE (release v0.11) | iwc | 13 | genomics, epigenomics |
| 165 | CUTandRUN (release v0.10) | iwc | 15 | genomics, epigenomics |
| 165 | COVID-19: variation analysis reporting (... | iwc | 36 | genomics, quality_control |
| 165 | COVID-19: consensus construction (releas... | iwc | 23 | genomics, quality_control |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | Scaffolding with Hi-C data VGP8 (release... | iwc | 36 | genomics, assembly |
| 165 | ChIPseq_PE (release v0.12) | iwc | 13 | genomics, epigenomics |
| 165 | ChIPseq_SR (release v0.8) | iwc | 12 | genomics, epigenomics |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | ATACseq (release v0.14) | iwc | 30 | epigenomics, alignment |
| 165 | ChIPseq_SR (release v0.9) | iwc | 12 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | Quality and Contamination Control For Ge... | iwc | 10 | genomics, metagenomics |
| 165 | Get Confident Peaks From ChIP_PE replica... | iwc | 26 | genomics, epigenomics |
| 165 | Genome Assembly from Hifi reads - VGP3 (... | iwc | 55 | genomics, assembly |
| 165 | Clinical Metaproteomics Verification Wor... | iwc | 23 | proteomics, quality_control |
| 165 | dada2 amplicon analysis pipeline - for p... | iwc | 19 | genomics, metagenomics |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ATAC or CUTandR... | iwc | 20 | genomics, epigenomics |
| 165 | ATACseq (release v0.15) | iwc | 30 | epigenomics, alignment |
| 165 | CUTandRUN (release v0.11) | iwc | 15 | genomics, epigenomics |
| 165 | Get Confident Peaks From ChIP_PE duplica... | iwc | 20 | genomics, epigenomics |
| 165 | Quality and Contamination Control For Ge... | iwc | 12 | genomics, metagenomics |
| 165 | Genome Assembly from Hifi reads with HiC... | iwc | 64 | genomics, assembly |
| 165 | kmer-profiling-hifi-trio-VGP2 (release v... | iwc | 15 | assembly, quality_control |
| 165 | ChIPseq_PE (release v0.11) | iwc | 13 | genomics, epigenomics |
| 160 | Mass spectrometry: LC-MS preprocessing w... | iwc | 13 | proteomics, alignment |
| 160 | Mass spectrometry: LC-MS preprocessing w... | iwc | 14 | proteomics, alignment |
| 155 | MAPseq to ampvis2 (release v0.1) | iwc | 11 | alignment |
| 155 | Scaffolding-HiC-VGP8 (release v0.2.3) | iwc | 35 | assembly |
| 155 | amr_gene_detection (release v1.1.3) | iwc | 9 | genomics |
| 155 | Hi-C_fastqToPairs_hic (release v0.2) | iwc | 9 | transcriptomics, alignment |
| 155 | Scaffolding-HiC-VGP8 (release v0.2) | iwc | 35 | assembly |
| 155 | MGnify's amplicon pipeline v5.0 - Qualit... | iwc | 22 | metagenomics, quality_control |
| 155 | amr_gene_detection (release v1.1.2) | iwc | 9 | genomics |
| 155 | Scaffolding-HiC-VGP8 (release v0.2.5) | iwc | 36 | assembly |
| 155 | baredSC_2d_logN (release v0.2) | iwc | 10 | - |
| 155 | Mass spectrometry: GCMS with metaMS (rel... | iwc | 9 | proteomics |
| 155 | Bacterial Genome Assembly using Shov (re... | iwc | 9 | genomics, assembly |
| 155 | Scaffolding with Hi-C data VGP8 (release... | iwc | 48 | assembly |
| 155 | Scaffolding-HiC-VGP8 (release v0.1) | iwc | 34 | assembly |
| 155 | QIIME2 IIb: Denoising (sequence quality ... | iwc | 10 | quality_control, long_read |
| 155 | Goseq GO-KEGG Enrichment Analysis (relea... | iwc | 10 | - |
| 155 | Mitogenome Assembly VGP0 (release v0.2) | iwc | 6 | genomics, assembly |
| 155 | MAPseq to ampvis2 (release v0.2) | iwc | 11 | alignment |
| 155 | QIIME2 IIb: Denoising (sequence quality ... | iwc | 10 | quality_control, long_read |
| 155 | Scaffolding-HiC-VGP8 (release v0.1.2) | iwc | 35 | assembly |
| 155 | Mass spectrometry: GCMS with metaMS (rel... | iwc | 9 | proteomics |
| 155 | baredSC_2d_logN (release v0.3) | iwc | 10 | - |
| 155 | MGnify's amplicon pipeline v5.0 - ITS (r... | iwc | 32 | metagenomics, quality_control |
| 155 | Bacterial Genome Assembly using Shov (re... | iwc | 9 | genomics, assembly |
| 155 | Bacterial Genome Assembly using Shov (re... | iwc | 9 | genomics, assembly |
| 155 | QIIME2 VI: Diversity metrics and estimat... | iwc | 17 | genomics |
| 155 | Scaffolding with Hi-C data VGP8 (release... | iwc | 40 | assembly |
| 155 | Single-Cell Mixture Analysis: baredSC 2D... | iwc | 10 | transcriptomics |
| 155 | dcTMD calculations with GROMACS (release... | iwc | 36 | epigenomics |
| 155 | Hi-C_fastqToPairs_hic (release v0.2.1) | iwc | 9 | transcriptomics, alignment |
| 155 | baredSC_2d_logN (release v0.4) | iwc | 10 | - |
| 155 | Generate a Clinical Metaproteomics Datab... | iwc | 7 | proteomics |
| 155 | Hi-C_fastqToPairs_hic (release v0.1) | iwc | 9 | transcriptomics, alignment |
| 155 | Single-Cell RNA-seq Preprocessing: 10X G... | iwc | 9 | transcriptomics, alignment |
| 155 | Scaffolding-HiC-VGP8 (release v0.1.1) | iwc | 35 | assembly |
| 155 | Scaffolding-HiC-VGP8 (release v0.2.7) | iwc | 37 | assembly |
| 155 | Bacterial Genome Assembly using Shov (re... | iwc | 9 | genomics, assembly |
| 155 | MGnify's amplicon pipeline v5.0 - ITS (r... | iwc | 32 | metagenomics, quality_control |
| 155 | Scaffolding-HiC-VGP8 (release v0.2.4) | iwc | 35 | assembly |
| 155 | dcTMD calculations with GROMACS (release... | iwc | 36 | epigenomics |
| 155 | MGnify's amplicon pipeline v5.0 - Qualit... | iwc | 22 | metagenomics, quality_control |
| 155 | QIIME2-III-V-Phylogeny-Rarefaction-Taxon... | iwc | 10 | phylogenetics |
| 155 | amr_gene_detection (release v1.1.4) | iwc | 9 | genomics |
| 155 | Bacterial Genome Assembly using Shov (re... | iwc | 9 | genomics, assembly |
| 155 | Hi-C_fastqToPairs_hic (release v0.3) | iwc | 9 | transcriptomics, alignment |
| 155 | Bacterial Genome Assembly using Shov (re... | iwc | 9 | genomics, assembly |
| 155 | amr_gene_detection (release v1.1) | iwc | 9 | genomics |
| 155 | Mitogenome Assembly VGP0 (release v0.2.1... | iwc | 9 | genomics, assembly |
| 155 | Pathogen Detection PathoGFAIR Samples Ag... | iwc | 70 | genomics, quality_control |
| 155 | QIIME2-III-V-Phylogeny-Rarefaction-Taxon... | iwc | 10 | phylogenetics |
| 155 | QIIME2 VI: Diversity metrics and estimat... | iwc | 17 | genomics |
| 155 | dcTMD calculations with GROMACS (release... | iwc | 36 | epigenomics |
| 155 | Bacterial Genome Assembly using Shov (re... | iwc | 9 | genomics, assembly |
| 155 | Scaffolding-HiC-VGP8 (release v0.2.1) | iwc | 35 | assembly |
| 155 | amr_gene_detection (release v1.1.5) | iwc | 9 | genomics |
| 155 | amr_gene_detection (release v1.1.1) | iwc | 9 | genomics |
| 155 | Nanopore Preprocessing (release v0.1) | iwc | 28 | metagenomics, quality_control |
| 155 | Scaffolding-HiC-VGP8 (release v0.2.6) | iwc | 36 | assembly |
| 155 | Differential gene expression for single-... | iwc | 21 | transcriptomics, annotation |
| 155 | MGnify's amplicon pipeline v5.0 - Qualit... | iwc | 22 | metagenomics, quality_control |
| 155 | baredSC_2d_logN (release v0.5) | iwc | 10 | - |
| 150 | QIIME2 Ib: multiplexed data (paired-en (... | iwc | 10 | - |
| 150 | scRNA-seq_preprocessing_10X_v3_Bun (rele... | iwc | 9 | transcriptomics, alignment |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | MetaProSIP OpenMS 2.8 (release v0.2) | iwc | 14 | proteomics |
| 150 | scRNA-seq_preprocessing_10X_v3_Bun (rele... | iwc | 9 | transcriptomics, alignment |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | Hi-C_juicermediumtabixToCool_c (release ... | iwc | 7 | genomics |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | MetaProSIP OpenMS 2.8 (release v0.1) | iwc | 14 | proteomics |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | Clinical Metaproteomics Quantitation (re... | iwc | 10 | proteomics |
| 150 | scRNA-seq_preprocessing_10X_v3_Bun (rele... | iwc | 9 | transcriptomics, alignment |
| 150 | MetaProSIP OpenMS 2.8 (release v0.2) | iwc | 14 | proteomics |
| 150 | QIIME2 Ib: multiplexed data (paired-en (... | iwc | 10 | - |
| 150 | scRNA-seq_preprocessing_10X_v3_Bun (rele... | iwc | 9 | transcriptomics, alignment |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | Hi-C_juicermediumtabixToCool_c (release ... | iwc | 7 | genomics |
| 150 | Hi-C_juicermediumtabixToCool_c (release ... | iwc | 7 | genomics |
| 150 | scRNA-seq_preprocessing_10X_v3_Bun (rele... | iwc | 9 | transcriptomics, alignment |
| 150 | scRNA-seq_preprocessing_10X_v3_Bun (rele... | iwc | 9 | transcriptomics, alignment |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | Velocyto-on10X-from-bun (release v0.2) | iwc | 5 | single_cell |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | Velocyto-on10X-from-bun (release v0.1) | iwc | 5 | single_cell |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 150 | Hi-C_juicermediumtabixToCool_c (release ... | iwc | 7 | genomics |
| 150 | BREW3R (release v0.2) | iwc | 10 | genomics, alignment |
| 150 | BREW3R (release v0.1) | iwc | 10 | genomics, alignment |
| 150 | sra_manifest_to_concatenated_fastqs_ (re... | iwc | 16 | - |
| 145 | baredSC_1d_logN (release v0.5) | iwc | 7 | - |
| 145 | QIIME2 IIa: Denoising (sequence quality ... | iwc | 8 | quality_control, long_read |
| 145 | Taxonomy Profiling and Visualization wit... | iwc | 5 | metagenomics |
| 145 | MMGBSA calculations with GROMACS (releas... | iwc | 28 | epigenomics |
| 145 | Segmentation and counting of cell nuclei... | iwc | 8 | - |
| 145 | baredSC_2d_logN (release v0.1) | iwc | 9 | - |
| 145 | baredSC_1d_logN (release v0.2) | iwc | 7 | - |
| 145 | Segmentation and counting of cell nuclei... | iwc | 8 | - |
| 145 | Single-Cell Mixture Analysis: baredSC 1D... | iwc | 7 | transcriptomics |
| 145 | baredSC_1d_logN (release v0.1) | iwc | 7 | - |
| 145 | Bacterial Genome Assembly using Shov (re... | iwc | 7 | genomics, assembly |
| 145 | Generate Nx and Size plots for multiple ... | iwc | 15 | genomics, assembly |
| 145 | Genome assembly with Fly (release v0.3) | iwc | 5 | genomics, assembly |
| 145 | Quality Evaluation (release v0.1) | iwc | 7 | assembly, quality_control |
| 145 | baredSC_1d_logN (release v0.3) | iwc | 7 | - |
| 145 | Genome assembly with Fly (release v0.1) | iwc | 5 | genomics, assembly |
| 145 | QIIME2 IIa: Denoising (sequence quality ... | iwc | 8 | quality_control, long_read |
| 145 | MMGBSA calculations with GROMACS (releas... | iwc | 28 | epigenomics |
| 145 | Genome assembly with Fly (release v0.2) | iwc | 5 | genomics, assembly |
| 145 | Genome annotation with Helix (release v0... | iwc | 8 | genomics, proteomics |
| 145 | Genome annotation with Helix (release v0... | iwc | 8 | genomics, proteomics |
| 145 | MMGBSA calculations with GROMACS (releas... | iwc | 28 | epigenomics |
| 145 | MMGBSA calculations with GROMACS (releas... | iwc | 28 | epigenomics |
| 145 | Generate Nx and Size plots for multiple ... | iwc | 15 | genomics, assembly |
| 145 | baredSC_1d_logN (release v0.4) | iwc | 7 | - |
| 145 | Generate Nx and Size plots for multiple ... | iwc | 15 | genomics, assembly |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | QIIME2 Ia: multiplexed data (single-en (... | iwc | 9 | - |
| 140 | Parallel Accession Down (release v0.1.5) | iwc | 6 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Assembly polishing with long reads (rele... | iwc | 11 | assembly, long_read |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.6) | iwc | 6 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.11... | iwc | 6 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.12... | iwc | 5 | - |
| 140 | Velocyto-on10X-filtered-barcodes (releas... | iwc | 4 | quality_control, single_cell |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.3) | iwc | 6 | - |
| 140 | Velocyto-on10X-filtered-barcodes (releas... | iwc | 4 | quality_control, single_cell |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.10... | iwc | 6 | - |
| 140 | QIIME2 Ia: multiplexed data (single-en (... | iwc | 9 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.9) | iwc | 6 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.1) | iwc | 6 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.7) | iwc | 6 | - |
| 140 | Parallel Accession Down (release v0.1.2) | iwc | 6 | - |
| 140 | Parallel Accession Down (release v0.1.4) | iwc | 6 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.8) | iwc | 6 | - |
| 140 | Parallel Accession Down (release v0.1.13... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 140 | Parallel Accession Down (release v0.1.14... | iwc | 5 | - |
| 135 | Simple Methylation QC | adrian_reich | 22 | epigenomics, alignment |
| 135 | Clustering 3k PBMCs with Seurat - Workfl... | jen-galaxyproject | 43 | single_cell |
| 135 | Functional annotation of protein sequenc... | iwc | 3 | proteomics, alignment |
| 130 | Assembly-decontamination-VGP9 (release v... | iwc | 12 | assembly, quality_control |
| 130 | Scaffolding-BioNano-VGP7 (release v0.1.4... | iwc | 17 | assembly |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 56 | assembly, long_read |
| 130 | Assembly-Hifi-only-VGP3 (release v0.2.8) | iwc | 48 | assembly, long_read |
| 130 | Assembly-decontamination-VGP9 (release v... | iwc | 14 | assembly, long_read |
| 130 | Assembly-Hifi-only-VGP3 (release v0.1.6) | iwc | 39 | assembly, long_read |
| 130 | Assembly-decontamination-VGP9 (release v... | iwc | 12 | assembly, quality_control |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 56 | assembly, long_read |
| 130 | Assembly-decontamination-VGP9 (release v... | iwc | 14 | assembly, long_read |
| 130 | Genome Assembly with Pacbio Hifi reads a... | iwc | 57 | genomics, assembly |
| 130 | Assembly-Hifi-only-VGP3 (release v0.1.1) | iwc | 32 | assembly, long_read |
| 130 | Genome Assembly with Pacbio Hifi reads a... | iwc | 57 | genomics, assembly |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 45 | assembly, long_read |
| 130 | Assembly-Hifi-only-VGP3 (release v0.1) | iwc | 32 | assembly, long_read |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 54 | assembly, long_read |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 56 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 43 | assembly, long_read |
| 130 | Scaffolding-BioNano-VGP7 (release v0.1.1... | iwc | 16 | assembly |
| 130 | Purging-duplicates-one-haplotype-VGP6b (... | iwc | 42 | - |
| 130 | Purging-duplicates-one-haplotype-VGP6b (... | iwc | 44 | - |
| 130 | Genome Assembly of MRSA using Oxford Nan... | marcela.nunes | 14 | genomics, assembly |
| 130 | Assembly-Hifi-only-VGP3 (release v0.1.2) | iwc | 32 | assembly, long_read |
| 130 | Assembly-decontamination-VGP9 (release v... | iwc | 14 | assembly, long_read |
| 130 | Assembly-Hifi-only-VGP3 (release v0.1.7) | iwc | 39 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 45 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 42 | assembly, long_read |
| 130 | Assembly-Hifi-only-VGP3 (release v0.2.5) | iwc | 48 | assembly, long_read |
| 130 | Average Bigwig between replicates (relea... | iwc | 4 | genomics |
| 130 | QIIME2 Id: Demultiplexed data (paired-en... | iwc | 6 | - |
| 130 | Assembly-decontamination-VGP9 (release v... | iwc | 16 | assembly, quality_control |
| 130 | Assembly-Hifi-only-VGP3 (release v0.2.6) | iwc | 48 | assembly, long_read |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 36 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 43 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 45 | assembly, long_read |
| 130 | Assembly-Hifi-only-VGP3 (release v0.2.7) | iwc | 48 | assembly, long_read |
| 130 | Assembly-Hifi-only-VGP3 (release v0.2.4) | iwc | 48 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 42 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 53 | assembly, long_read |
| 130 | Scaffolding-BioNano-VGP7 (release v0.1.3... | iwc | 16 | assembly |
| 130 | Assembly-Hifi-only-VGP3 (release v0.2.1) | iwc | 48 | assembly, long_read |
| 130 | Assembly-Hifi-only-VGP3 (release v0.1.8) | iwc | 39 | assembly, long_read |
| 130 | QIIME2 Ic: Demultiplexed data (single-en... | iwc | 6 | - |
| 130 | Assembly-Hifi-only-VGP3 (release v0.2.2) | iwc | 48 | assembly, long_read |
| 130 | Scaffolding-BioNano-VGP7 (release v0.1.2... | iwc | 16 | assembly |
| 130 | Purging-duplicates-one-haplotype-VGP6b (... | iwc | 34 | - |
| 130 | Assembly-decontamination-VGP9 (release v... | iwc | 14 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 43 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 52 | assembly, long_read |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 56 | assembly, long_read |
| 130 | Assembly-Hifi-only-VGP3 (release v0.2.3) | iwc | 48 | assembly, long_read |
| 130 | QIIME2 Id: Demultiplexed data (paired-en... | iwc | 6 | - |
| 130 | Average Bigwig between replicates (relea... | iwc | 4 | genomics |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 52 | assembly, long_read |
| 130 | Assembly-decontamination-VGP9 (release v... | iwc | 12 | assembly, quality_control |
| 130 | Assembly-decontamination-VGP9 (release v... | iwc | 14 | assembly, long_read |
| 130 | Genome Assembly with Pacbio Hifi reads a... | iwc | 57 | genomics, assembly |
| 130 | Assembly-decontamination-VGP9 (release v... | iwc | 14 | assembly, long_read |
| 130 | QIIME2 Ic: Demultiplexed data (single-en... | iwc | 6 | - |
| 130 | Purging-duplicates-one-haplotype-VGP6b (... | iwc | 34 | - |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 36 | assembly, long_read |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 36 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 45 | assembly, long_read |
| 130 | Assembly-Hifi-HiC-phasing-VGP4 (release ... | iwc | 43 | assembly, long_read |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 45 | assembly, long_read |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 56 | assembly, long_read |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 56 | assembly, long_read |
| 130 | Assembly-Hifi-Trio-phasing-VGP5 (release... | iwc | 45 | assembly, long_read |
| 130 | Scaffolding-BioNano-VGP7 (release v0.1) | iwc | 16 | assembly |
| 130 | Assembly-Hifi-only-VGP3 (release v0.2) | iwc | 47 | assembly, long_read |
| 130 | Purging-duplicates-one-haplotype-VGP6b (... | iwc | 34 | - |
| 120 | kmer-profiling-hifi-VGP1 (release v0.1.2... | iwc | 7 | long_read |
| 120 | WGS2Protein v3.0.0 | crist_john_m._pastor | 12 | genomics, proteomics |
| 120 | Mitogenome-Assembly-VGP0 (release v0.1) | iwc | 6 | genomics, assembly |
| 120 | kmer-profiling-hifi-VGP1 (release v0.1.4... | iwc | 7 | long_read |
| 120 | Create GRO and TOP complex files (releas... | iwc | 14 | - |
| 120 | kmer-profiling-hifi-VGP1 (release v0.1.1... | iwc | 7 | long_read |
| 120 | kmer-profiling-hifi-VGP1 (release v0.1.7... | iwc | 7 | long_read |
| 120 | Create GRO and TOP complex files (releas... | iwc | 14 | - |
| 120 | Create GRO and TOP complex files (releas... | iwc | 14 | - |
| 120 | kmer-profiling-hifi-VGP1 (release v0.1.6... | iwc | 7 | long_read |
| 120 | kmer-profiling-hifi-VGP1 (release v0.1.5... | iwc | 7 | long_read |
| 120 | kmer-profiling-hifi-VGP1 (release v0.1.8... | iwc | 8 | long_read |
| 120 | kmer-profiling-hifi-VGP1 (release v0.1.3... | iwc | 7 | long_read |
| 120 | Comparative Gene Analysis v3 | cartman | 30 | genomics, quality_control |
| 110 | Generate Nx and Size plots for multiple ... | iwc | 15 | - |
| 110 | Workflow_Metagenomic_Virus_Oxford Nanopo... | p.manc | 15 | genomics, metagenomics |
| 110 | Generate Nx and Size plots for multiple ... | iwc | 15 | - |
| 110 | Generate Nx and Size plots for multiple ... | iwc | 15 | - |
| 110 | Generate Nx and Size plots for multiple ... | iwc | 15 | - |
| 110 | Generate Nx and Size plots for multiple ... | iwc | 15 | - |
| 105 | FASTQ-2-VCF-WORKFLOW! | varshitha | 9 | genomics |
| 100 | Repeat masking with RepeatModeler and Re... | iwc | 3 | - |
| 95 | Nanopore KO Read Alignment | jakelmer | 19 | genomics, alignment |
| 95 | Ref-guided WPS processing_segmented data | vinita_sharma | 10 | genomics, assembly |
| 95 | RNAseq: Reference-based shared by olaf | olaf_b | 9 | transcriptomics |
| 95 | Ref-guided WPS processing_whole data | vinita_sharma | 10 | genomics, assembly |
| 85 | Copy of Taxonomy Profiling and Visualiza... | alexander._. | 5 | metagenomics |
| 75 | WGS Analysis (Bacteria) | diptachandrapal | 5 | genomics |
| 75 | Metagenomic Análisys | ademiguelgr | 31 | metagenomics |
| 70 | Promoter Sequence Extraction and Motif S... | abhishek_s_r | 10 | - |
| 70 | RNA Seq 分析流程_NTHU_2025_0425 | sean.chang | 16 | transcriptomics |
| 65 | T-DNA detect(map to TDNA,then map to pla... | xpb2005 | 18 | genomics, alignment |
| 65 | hg19 | vikramadhithya_bioinfo | 13 | - |
| 65 | Case 2 | jglopez22 | 11 | - |
| 65 | NGS Analysis | mohharus7 | 16 | - |
| 55 | RNA-Seq Workflow | deya | 27 | genomics, transcriptomics |
| 55 | (tutorial) Regression in Machine Learnin... | hujambo-dunia | 14 | - |
| 55 | RNAseq cuantitativo GENOMICA | cocoyo | 22 | transcriptomics, quality_control |
| 55 | Vnat_WorkFlow_Basic | fatimahsajid786 | 16 | - |
| 55 | Case 1 | jglopez22 | 6 | - |
| 55 | Bioinformatics workflow-Ava Kuey | akuey | 16 | - |
| 55 | Cortar | enrique_ant | 13 | - |
| 55 | Bioinformatics Pipeline for Nanopore Seq... | sally1130 | 16 | long_read |
| 55 | Workflow without bowtie quality=10 | sungyeon_park | 19 | alignment, quality_control |
| 55 | from peaks to genes' | dyy11 | 5 | epigenomics |
| 55 | RNA-seq (Sue-ob, K.) | siwakorn | 15 | transcriptomics |
| 55 | del hisat al string | enrique_ant | 32 | alignment |
| 50 | fastq to bam to feature count matrix | yhstatong | 6 | genomics |
| 50 | Sort the unmapped bam | yhstatong | 7 | genomics, alignment |

---
## Rejected Workflows Analysis

### Top Rejection Reasons
- **No meaningful annotation/description:** 17 workflows
- **Ad-hoc workflow pattern detected: 'constructed from history':** 5 workflows
- **Ad-hoc workflow pattern detected: 'imported:':** 1 workflows

### Sample Rejected Workflows (20 examples)

####  Katies History
- **Score:** 45/100 (below 50 threshold)
- **Owner:** katieblinn04
- **Steps:** 7
**Why Rejected:**
  [-15] No meaningful annotation/description

#### Workflow constructed for 'BioProject Final - Option B.1'
- **Score:** 45/100 (below 50 threshold)
- **Owner:** anthony.jbal48
- **Steps:** 8
**Why Rejected:**
  [-15] No meaningful annotation/description

#### leshmaina detector 
- **Score:** 45/100 (below 50 threshold)
- **Owner:** marah_qunbar
- **Steps:** 6
**Why Rejected:**
  [-15] No meaningful annotation/description

#### Workflow-Olympics-db-AliKiani
- **Score:** 45/100 (below 50 threshold)
- **Owner:** aliprg0
- **Steps:** 18
**Why Rejected:**
  [-15] No meaningful annotation/description

#### Find exons with the highest number of features
- **Score:** 45/100 (below 50 threshold)
- **Owner:** katieblinn04
- **Steps:** 7
**Why Rejected:**
  [-15] No meaningful annotation/description

#### EMS mutagenesis
- **Score:** 45/100 (below 50 threshold)
- **Owner:** colafish
- **Steps:** 4
**Why Rejected:**
  [-15] No meaningful annotation/description

#### LAB 5
- **Score:** 45/100 (below 50 threshold)
- **Owner:** juliadomaszewska
- **Steps:** 35
**Why Rejected:**
  [-15] No meaningful annotation/description

#### tomato species
- **Score:** 45/100 (below 50 threshold)
- **Owner:** marah_qunbar
- **Steps:** 6
**Why Rejected:**
  [-15] No meaningful annotation/description

#### Feature 2 con samtool view
- **Score:** 45/100 (below 50 threshold)
- **Owner:** enrique_ant
- **Steps:** 15
**Why Rejected:**
  [-15] No meaningful annotation/description

#### WF Construccion de AF con Logo
- **Score:** 45/100 (below 50 threshold)
- **Owner:** mbreglia
- **Steps:** 6
**Why Rejected:**
  [-15] No meaningful annotation/description

#### Pre-procesing (imported from uploaded file)
- **Score:** 40/100 (below 50 threshold)
- **Owner:** tociepaaa
- **Steps:** 2
**Why Rejected:**
  [-15] No meaningful annotation/description

#### Phylogeny Workflow
- **Score:** 40/100 (below 50 threshold)
- **Owner:** kt
- **Steps:** 2
**Why Rejected:**
  [-15] No meaningful annotation/description

#### Sort the mapped bam
- **Score:** 40/100 (below 50 threshold)
- **Owner:** yhstatong
- **Steps:** 4
**Why Rejected:**
  [-15] No meaningful annotation/description

#### third(从peak到基因成果版)
- **Score:** 35/100 (below 50 threshold)
- **Owner:** zhuli71
- **Steps:** 4
**Why Rejected:**
  [-15] No meaningful annotation/description

#### trimmomatic
- **Score:** 35/100 (below 50 threshold)
- **Owner:** enrique_ant
- **Steps:** 9
**Why Rejected:**
  [-15] No meaningful annotation/description

#### Gene Count by Chromosome (No Pseudogenes)
- **Score:** 35/100 (below 50 threshold)
- **Owner:** samjusto11
- **Steps:** 3
**Why Rejected:**
  [-15] No meaningful annotation/description

#### Workflow constructed from history 'Análisis Clavel(casos)'
- **Score:** 25/100 (below 50 threshold)
- **Owner:** yairreja
- **Steps:** 11
**Why Rejected:**
  [-30] Ad-hoc workflow pattern detected: 'constructed from history'
  [-15] No meaningful annotation/description

#### imported: Vnat_20250721
- **Score:** 25/100 (below 50 threshold)
- **Owner:** dmartynova
- **Steps:** 16
**Why Rejected:**
  [-30] Ad-hoc workflow pattern detected: 'imported:'
  [-15] No meaningful annotation/description

####  'first class'
- **Score:** 25/100 (below 50 threshold)
- **Owner:** dyy11
- **Steps:** 3
**Why Rejected:**
  [-15] No meaningful annotation/description
  [-10] Hardcoded sample filename: 'mutant_R1.fastq'

#### Copy of Workflow constructed from history 'NGS'
- **Score:** 25/100 (below 50 threshold)
- **Owner:** 13261811174
- **Steps:** 18
**Why Rejected:**
  [-30] Ad-hoc workflow pattern detected: 'constructed from history'
  [-15] No meaningful annotation/description

---
## Evaluation Criteria

### Positive Criteria (Score Additions)
- **+40** Base score for valid workflow
- **+25** Trusted owner (iwc, iuc, devteam, etc.)
- **+20** Has meaningful annotation (50+ chars)
- **+20** Complex workflow (10+ steps)
- **+15** Has creator attribution with ORCID
- **+15** Uses multiple standard bioinformatics tools
- **+10** Has tags
- **+10** Has license
- **+10** Well-connected pipeline
- **+10** Multiple labeled outputs
- **+5** Appears to be versioned release

### Negative Criteria (Score Deductions)
- **-30** Ad-hoc workflow pattern (e.g., 'constructed from history')
- **-20** Too few steps (< 5)
- **-15** No meaningful annotation
- **-15** Too few tools (< 3)
- **-10** Hardcoded sample filenames
- **-5** Workflow not published

### Threshold
Workflows with score >= 50 are kept.
