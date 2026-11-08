# TRAIN task: workflow_generation  (365 instances)

## [0] source=multitask_sft_big

**USER:** I need to set up and solve mixed model equations for an animal model using pedigree and phenotype data in genetics. How can this workflow be configured?

**ASSISTANT:** You can use the `geneticsped` workflow:
- Domain: genetics
- Input: `pedigree_data.csv` (data frame with `individual`, `sire`, `dam`, `sex`, and `phenotype` columns)
- Underlying tool: `bioconductor/geneticsped`
- Outputs: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [1] source=multitask_sft_big

**USER:** I need to parse NCI pathways stored as graphNEL objects into gene-level representations and visualize them. What tools are used in this workflow and what outputs will it generate?

**ASSISTANT:** You can deploy the `ncigraph` workflow from the systems biology domain.

- **Input**: `NCI.demo.cyList` (RDS file of raw graphNEL pathway objects)
- **Tools Used**: `bioconductor/ncigraph` (to parse raw NCI pathways into gene-level graphNEL networks) and `bioconductor/rgraphviz` (for network layout and rendering)
- **Outputs**: `de_table` (differential expression / pathway statistics table) and `visualizations` (network visual plots).

---

## [2] source=multitask_sft_big

**USER:** I want to perform a supervised transcriptomics analysis associating gene expression profiles with clinical traits using mutual information. Which workflow should I run and what outputs should I expect?

**ASSISTANT:** You should run the `bus_supervised_gene_trait_association` workflow. Provide your `expression_matrix.csv` and matching `trait_matrix.csv`. The workflow will produce outputs in three formats: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [3] source=multitask_sft_big

**USER:** How can I run a differential expression analysis for an RNA-seq experiment that involves multiple groups with biological replicates using TCC?

**ASSISTANT:** You can use the `tcc_multi_group_replicates` workflow. It performs robust differential expression analysis specifically tailored for multi-group RNA-seq count data containing biological replicates.

Required inputs:
- `hypoData_mg`: A matrix of raw integer counts across your multi-group samples.
- `group`: A numeric vector indicating group membership for each sample.

---

## [4] source=multitask_sft_big

**USER:** What are the expected inputs and outputs for the panomir_custom_pathway_table_from_gmt workflow?

**ASSISTANT:** For `panomir_custom_pathway_table_from_gmt`:
- Input: `pathways.gmt` (external pathway definitions in GMT format)
- Outputs: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [5] source=multitask_sft_big

**USER:** I am conducting exploratory data analysis on flow cytometry FCS files and need 1D density visualization. What outputs can I expect from the 'Generate 1D density plots' tool?

**ASSISTANT:** The tool generates a series of 1D density plots using ggcyto and outputs a PNG file. Additionally, a PDF file can optionally be generated if required.

---

## [6] source=multitask_sft_big

**USER:** I need to construct a metagenomic classification workflow where raw fastq reads are converted into a consolidated multi-sample abundance profile table using MetaPhlAn3. What are the key stages?

**ASSISTANT:** A standard workflow consists of:
1. Generating taxonomic profiles for each sample individually using `MetaPhlAn3`.
2. Merging the individual sample profile tables into a single consolidated abundance matrix using `Metaphlan3 Mergemetaphlantables`.

---

## [7] source=multitask_sft_big

**USER:** How should I structure the sequence preprocessing step for a BLAST database construction workflow in Galaxy?

**ASSISTANT:** You should structure the preprocessing workflow by passing your genomic or metagenomic FASTA files through 'fastaGroomerForMakeBlastdb' prior to feeding them into makeblastdb. This step standardizes the FASTA formatting to ensure that makeblastdb does not fail due to warnings being handled as errors.

---

## [8] source=multitask_sft_big

**USER:** What outputs should I expect after executing the `banksy_multi_sample_joint_clustering` workflow on my `spe_list` dataset?

**ASSISTANT:** Running `banksy_multi_sample_joint_clustering` produces three types of outputs: a tabular summary (`table/csv`), visual plots (`plot/pdf`), and an R object file (`object/rds`).

---

## [9] source=multitask_sft_big

**USER:** I am outlining an in silico immunology experimental pipeline that begins with mock tissue processing. Which tool handles the initial cell separation step?

**ASSISTANT:** You can use 'Biomni: Isolate Purify Immune Cells' at the start of your pipeline to simulate the isolation and purification of immune cells from tissue samples.

---

## [10] source=multitask_sft_big

**USER:** Can you configure a workflow plan using scanvis to generate junction visualizations from my splice junction table, VCF, and GTF annotation?

**ASSISTANT:** Here is the workflow plan using `scanvis`:

- **Workflow**: `scanvis`
- **Domain**: Genomics
- **Tool**: `bioconductor/scanvis`
- **Inputs Required**:
  - `sj_table.txt` (splice junction coordinates and unique read counts)
  - `variants.vcf` (genomic coordinates and mutation details)
  - `gtf_annotation.gtf` (gene annotations)
- **Outputs**:
  - `visualizations` (sashimi plots and junction analysis visual outputs)

---

## [11] source=multitask_sft_big

**USER:** I need a transcriptomics workflow to detect differentially expressed features using a kernel-based score test and visualize them with heatmaps. Which workflow can I use?

**ASSISTANT:** You can use the `cytokernel` workflow. It executes a kernel-based score test to identify differentially expressed features in high-dimensional abundance data using `bioconductor/cytokernel`, filters the dataset, and generates visualizations of top hits using `bioconductor/complexheatmap`. It produces a differential expression table (`de_table`) and visualization outputs (`visualizations`).

---

## [12] source=multitask_sft_big

**USER:** Can you outline the final stages of a prokaryote MAG quality evaluation pipeline that utilizes GUNC and CheckM?

**ASSISTANT:** 1. Run CheckM on your prokaryotic genome assemblies to estimate completeness and contamination.
2. Run GUNC to detect potential chimeric contigs and contamination across taxonomic lineages.
3. Run Gunc Mergecheckm to combine the CheckM metrics and GUNC results into one comprehensive summary table for downstream genome filtering.

---

## [13] source=multitask_sft_big

**USER:** Can you outline a basic workflow to generate a combined phylogenetic tree and multiple sequence alignment plot using ggmsa?

**ASSISTANT:** Here is an outline for combining MSA with phylogenetic visualization:

1. **Multiple Sequence Alignment**: Generate your DNA, RNA, or protein sequence alignment.
2. **Phylogenetic Reconstruction**: Build a phylogenetic tree from the alignment data.
3. **MSA Plotting**: Generate the alignment visualization using `ggmsa`.
4. **Plot Integration**: Combine the `ggmsa` alignment visualization with the phylogenetic tree plot within the `ggplot2` ecosystem.

---

## [14] source=multitask_sft_big

**USER:** What Bioconductor packages make up the rcistarget workflow, and what output does it produce?

**ASSISTANT:** The `rcistarget` workflow incorporates the following tools:
- `bioconductor/rcistarget`
- `bioconductor/dt`
- `bioconductor/reshape2`
- `bioconductor/visnetwork`

It processes a gene list and motif rankings database to generate `normalized_data` representing enriched transcription factor binding motifs and predicted candidate target genes.

---

## [15] source=multitask_sft_big

**USER:** What are the expected outputs when running the `hdtd` workflow on `user_data.csv`?

**ASSISTANT:** The `hdtd` workflow produces three outputs:
1. `table/csv` (tabular results)
2. `plot/pdf` (graphical representation)
3. `object/rds` (serialized R data object)

---

## [16] source=multitask_sft_big

**USER:** How do I configure Fastqc Site to search for non-default adapters in my Fastq manipulation workflow?

**ASSISTANT:** To configure Fastqc Site for explicit adapter detection:
1. Create a text file where each adapter is defined on its own line using the syntax `name\tsequence` (e.g., `Illumina_Universal\tAGATCGGAAGAGC`).
2. Optional: Add comments or metadata by prefixing lines with `#`.
3. Provide this file as the non-default adapter file parameter to Fastqc Site to run explicit searches across your sequencing library.

---

## [17] source=multitask_sft_big

**USER:** Can you summarize the tools and outputs involved in the despace transcriptomics workflow?

**ASSISTANT:** The despace workflow utilizes the Bioconductor packages `despace` and `spatialexperiment`, alongside `ggplot2` and `ggforce` for plotting. It takes a prepared `spe_data.rds` object and yields differential expression results in a `de_table` as well as spatial `visualizations`.

---

## [18] source=multitask_sft_big

**USER:** Can you provide the tool and output specifications for setting up a findips pipeline?

**ASSISTANT:** For the `findips` workflow:
- **Tool**: `bioconductor/findips`
- **Inputs**: `expression_matrix.csv` (samples as rows, genes as columns) and `phenotype_labels.csv` (binary or continuous labels)
- **Outputs**: `feature_selection` results along with diagnostic `visualizations`.

---

## [19] source=multitask_sft_big

**USER:** I want to perform supervised classification of metagenomic microbiome profiles into phenotypic cohorts using Dirichlet-Multinomial modeling. How can I structure this workflow?

**ASSISTANT:** You can employ the `dirichletmultinomial_generative_classification` workflow in the metagenomics domain:
- **Inputs**: Provide the taxa count matrix (`Twins.csv`) and sample phenotype labels (`TwinStudy.t`).
- **Model**: It fits supervised Dirichlet-Multinomial group models to classify samples into phenotypic groups.
- **Outputs**: Generates `cluster_assignments` and diagnostic `visualizations`.

---

## [20] source=multitask_sft_big

**USER:** I need to design gRNAs and pegRNAs for a prime editing experiment from a set of target sequences. What workflow should I run and what inputs does it take?

**ASSISTANT:** You should use the workflow `crisprseek_prime_editing_grna_design`. It accepts target sequences as either a FASTA file (`inputseq.fa`) or a `DNAStringSet` object, and it produces guide design results as a CSV table, PDF plots, and an RDS object.

---

## [21] source=multitask_sft_big

**USER:** Are there any configuration requirements I need to be aware of when adding nf-core/bed_scatter_bedtools to my pipeline?

**ASSISTANT:** Yes. The configuration specified in nextflow.config must be added to your modules.config for the nf-core/bed_scatter_bedtools subworkflow to work properly.

---

## [22] source=multitask_sft_big

**USER:** I need to run the rfastp_umi_preprocessing workflow for paired-end sequencing quality control. Which inputs should I map my FASTQ files to?

**ASSISTANT:** You can assign your forward FASTQ file to the 'pe_read1' input slot and your reverse FASTQ file to the 'pe_read2' input slot.

---

## [23] source=multitask_sft_big

**USER:** How do I set up the inputs and expected outputs for the gmoviz_feature_diagram workflow?

**ASSISTANT:** To configure 'gmoviz_feature_diagram':
- Supply the sequence scaffolding via `ideogram_data.gff` (or a GRanges/data.frame with sequence names and lengths).
- Supply the structural annotations via `features.gff3`.
- Optionally provide `coverage.bam` for depth coverage.
- The workflow produces circular genomic 'visualizations' as its output.

---

## [24] source=multitask_sft_big

**USER:** I have a PDB structure of a target antigen and want to design single-chain variable fragment (scFv) sequences and validate their structures computationally. How can I set this up?

**ASSISTANT:** You can use the **scfv-pmpnn** workflow. This pipeline takes your target antigen PDB structure, generates candidate scFv antibody sequences scored by ProteinMPNN log-likelihood, and then optionally runs AlphaFold2 to predict the 3D structures and structural confidence of the top-ranked designs.

---

## [25] source=multitask_sft_big

**USER:** How do hicTrainTADClassifier and hicTADClassifier interact in a 3D genomics workflow?

**ASSISTANT:** In a TAD boundary prediction workflow:
1. Run `hicTrainTADClassifier` on Hi-C datasets with known TAD boundaries to train a classification model (utilizing an ensemble approach like EasyEnsembleClassifier).
2. Feed the resulting trained classifier model into `hicTADClassifier` to call TAD boundaries on new or unannotated Hi-C contact datasets.

---

## [26] source=multitask_sft_big

**USER:** Can you outline the input files, output files, and underlying tools used in the 'rvs' genomics workflow?

**ASSISTANT:** The 'rvs' workflow requires two mandatory data inputs: 'pedigree_data.txt' (pedigree structure and affection status) and 'genotype_data.ped' (genotypes in LINKAGE format). It utilizes the tools 'bioconductor/rvs', 'bioconductor/kinship2', and 'bioconductor/snpstats', and produces 'burden_test_results' as output.

---

## [27] source=multitask_sft_big

**USER:** I have collected Thermo Orbitrap raw files from a quantitative proteomics experiment. How can I set up the initial data processing and QC step?

**ASSISTANT:** You can integrate Raw Tools at the first step of your pipeline. Point Raw Tools to your Thermo Orbitrap raw files to parse the scan data, perform feature quantification, and generate QC metrics to evaluate mass spectrometry performance prior to protein identification and statistical analysis.

---

## [28] source=multitask_sft_big

**USER:** Can you summarize the tools involved and the expected output for running the metaboannotation pipeline?

**ASSISTANT:** The `metaboannotation` workflow utilizes the following Bioconductor packages:
- `bioconductor/metaboannotation`
- `bioconductor/annotationhub`
- `bioconductor/qfeatures`
- `bioconductor/spectra`
- `bioconductor/summarizedexperiment`
- `bioconductor/microbenchmark`

The primary output produced by this workflow is a `summarizedexperiment` object.

---

## [29] source=multitask_sft_big

**USER:** I need an end-to-end workflow to simulate paired single-cell RNA-seq and ATAC-seq data while accounting for gene regulatory networks and chromatin accessibility. What workflow exists for this?

**ASSISTANT:** You can use the 'scMultiSim' workflow. It requires 'count_data' as input files (declared as the input slot 'input_files') and integrates Bioconductor tools ('bioconductor/scmultisim', 'bioconductor/ggplot2', and 'bioconductor/knitr') to simulate paired scRNA-seq, scATAC-seq, and RNA velocity data incorporating gene regulatory networks, chromatin accessibility, and cell-cell interactions.

---

## [30] source=multitask_sft_big

**USER:** How do I integrate pairix into an nf-core 3D genomics workflow for processing contact pairs?

**ASSISTANT:** In your pipeline, after generating paired genomic coordinates (e.g., Hi-C contact pairs), compress the text files using `bgzip`, then pass the bgzipped paired-coordinate files to `pairix` to generate the 2D spatial index files required for fast regional queries.

---

## [31] source=multitask_sft_big

**USER:** Can you outline the execution steps and outputs for running the `metagene2` workflow on ChIP-seq alignments?

**ASSISTANT:** The `metagene2` workflow proceeds as follows:
1. Load ChIP-seq alignments from indexed `bam_files`.
2. Ingest region coordinates from `regions` (BED files or GRanges/GRangesList) and incorporate region metadata.
3. Utilize `bioconductor/metagene2` and `bioconductor/genomicfeatures` to calculate coverage profiles across the regions according to experimental design.
4. Produce reporting and metagene profile plots (`visualizations`) rendered via `bioconductor/knitr`.

---

## [32] source=multitask_sft_big

**USER:** I have spatial transcriptomics data saved as an RDS file containing a SpatialExperiment object. I need to identify and cluster spatially variable genes. Which workflow should I run and what input is needed?

**ASSISTANT:** You should execute the `spatialde_spatial_experiment_workflow`. 

- **Input required**: `spe` (a mandatory `.rds` file containing a SpatialExperiment object with spatial coordinates and raw count assays).
- **Output generated**: `visualizations` along with identified, classified, and clustered spatially variable genes.

---

## [33] source=multitask_sft_big

**USER:** I am configuring an upstream chromatin profiling pipeline starting with an unindexed FASTA genome file. What is the initial indexing step?

**ASSISTANT:** The initial step is to run Chromap Index with your FASTA reference genome file as input to generate the required index for chromatin profiling.

---

## [34] source=multitask_sft_big

**USER:** Can you outline how the allometric_scaling workflow computes human parameters and first-in-human doses from animal PK data?

**ASSISTANT:** The `allometric_scaling` workflow proceeds through these steps:
1. **Input Processing**: Ingests a JSON array containing preclinical PK data for rat, dog, and monkey.
2. **Regression & Corrections**: Uses SciPy, RDKit, power-law allometric regression, the Rule of Exponents (Mahmood 2003), and MLP/brain-weight correction factors to scale CL, Vd, and t½ to human estimates.
3. **Dose Prediction**: Predicts first-in-human dose limits (MABEL and MRSD) in compliance with FDA 2005 Guidance.
4. **Output Generation**: Exports the resulting PK predictions and dose estimations in `json` and `csv` formats.

---

## [35] source=multitask_sft_big

**USER:** How can I set up an unsupervised workflow to discover robust disease subgroups from a cohort's clinical parameter matrix using ClustAll?

**ASSISTANT:** You can set up the workflow as follows:
1. **Data Preprocessing**: Format the patient cohort clinical data matrix, handling variable scaling and missing clinical entries.
2. **Unsupervised Stratification with ClustAll**: Run `ClustAll` on the clinical data to perform dimensionality reduction and robust unsupervised clustering across patients.
3. **Stratification Assessment**: Evaluate the resulting hidden patient groups against clinical outcomes, biomarkers, or longitudinal trajectories to validate the stratifications.

---

## [36] source=multitask_sft_big

**USER:** Which underlying Bioconductor packages and tools are integrated into the 'flowtime' workflow?

**ASSISTANT:** The 'flowtime' workflow utilizes the following tools: bioconductor/flowtime, bioconductor/biocmanager, bioconductor/dplyr, bioconductor/flowclust, bioconductor/flowcore, and bioconductor/flowstats.

---

## [37] source=multitask_sft_big

**USER:** I finished running DADA2 on my 16S amplicon data. How can I transform the tabular outputs into standard ASV tables, taxonomy tables, and sequence files?

**ASSISTANT:** Feed your DADA2 sequence count and taxonomy output files into the `Classical ASV Table Generator`. It will process these inputs to generate a unified ASV table, a taxonomy table, and the ASV sequences in FASTA format.

---

## [38] source=multitask_sft_big

**USER:** I want to perform qualitative biclustering on my yeast expression dataset. How is the rqubic workflow configured?

**ASSISTANT:** The `rqubic` transcriptomics workflow is configured as follows:
- **Inputs**: 
  - `BicatYeast` (expression matrix of yeast gene expression data)
  - `demo.exprs` (ExpressionSet object containing the expression matrix and sample metadata)
- **Tools**: `bioconductor/rqubic`, `bioconductor/biobase`, and `bioconductor/biclust`
- **Outputs**: `cluster_assignments` and `visualizations`

---

## [39] source=multitask_sft_big

**USER:** I want to perform differential expression analysis on single-cell RNA-seq counts without clustering the cells first. Which workflow should I set up?

**ASSISTANT:** You should use the 'meb_scmeb_single_cell' workflow. It identifies differentially expressed genes in single-cell RNA-seq data without prior cell clustering. It takes an 'sce' object and 'stable_idx', producing 'de_table', 'cluster_assignments', and 'normalized_data'.

---

## [40] source=multitask_sft_big

**USER:** I need to take an existing BAM alignment and extract the original raw FASTQ sequences. How does Samtools Bam2Fq fit into this step?

**ASSISTANT:** You can provide your BAM file directly as input to `Samtools Bam2Fq`. The tool invokes `samtools bam2fq` to parse the alignment records and output the reads in FASTQ format, ready for downstream quality control, re-alignment, or de novo assembly.

---

## [41] source=multitask_sft_big

**USER:** Can you outline the inputs, tools, and outputs for the `dose` systems biology workflow?

**ASSISTANT:** Here is the structure for the `dose` workflow:
- **Input**: `gene_list.txt` (a vector of Entrez gene IDs)
- **Tool**: `bioconductor/dose`
- **Outputs**: `enrichment_results` and `visualizations`.

---

## [42] source=multitask_sft_big

**USER:** I have a target DNA sequence in FASTA format and a raw position frequency matrix (PFM) file. I want to identify putative transcription factor binding sites using PWM scanning and get empirical p-values and GFF export. Which workflow should I run and what tools does it use?

**ASSISTANT:** You should run the `tfbstools` genomics workflow. 

- **Inputs:** `sequence.fasta` (DNA sequence of interest as a DNAString subject) and `pfm_data.txt` (raw position frequency matrix or JASPAR ID).
- **Underlying tools:** `bioconductor/tfbstools`, `bioconductor/biostrings`, `bioconductor/cner`, `bioconductor/jaspar2014`, and `bioconductor/rtracklayer`.
- **Outputs:** `table/csv`, `plot/pdf`, and `object/rds` containing the putative TFBS locations and empirical p-values exported to GFF format.

---

## [43] source=multitask_sft_big

**USER:** I have a normalized gene expression matrix and sample clinical annotations with multiple clinical covariates. I need to evaluate the sequential or Type III effects of these factors on gene expression and perform pairwise comparisons. What workflow should I use and what outputs will it generate?

**ASSISTANT:** You should use the workflow `globalancova_sum_of_squares_decomposition`. 

- **Inputs required:** `expression_matrix.csv` (normalized gene expression matrix) and `phenotype_data.csv` (sample clinical annotations with multi-level factors).
- **Function:** Decomposes the model sum of squares to evaluate sequential or Type III effects of multiple clinical factors on gene expression and performs pairwise comparisons between factor levels.
- **Outputs:** `de_table` and `visualizations`.

---

## [44] source=multitask_sft_big

**USER:** What input does the alevinqc_custom_plotting_and_data_extraction workflow take, and what does it output?

**ASSISTANT:** The workflow takes `baseDir` (the Alevin output directory containing `alevin/`, `aux_info/`, and `cmd_info.json`) as input, and outputs `visualizations` (the generated diagnostic plots and QC inspections).

---

## [45] source=multitask_sft_big

**USER:** How do I use the decipher workflow to classify query DNA or Amino Acid sequences against reference sequences, and what outputs will it generate?

**ASSISTANT:** The `decipher` workflow utilizes `bioconductor/decipher` to train a taxonomic classifier on reference sequences and classify your query sequences.

**Inputs Required:**
1. `seqs_path`: FASTA file containing reference training sequences.
2. `fas`: FASTA file containing query sequences (DNA or Amino Acids) to classify.
3. `rank_path` (optional): Taxid text file specifying taxonomic ranks.

**Outputs Generated:**
- `table/csv`: Tabular classification results.
- `plot/pdf`: Graphical summary/plot of the classification.
- `object/rds`: Serialized R data object of the trained classifier/results.

---

## [46] source=multitask_sft_big

**USER:** I have single-cell RNA-seq UMI count data and want an end-to-end Bioconductor pipeline to perform feature selection, hierarchical clustering, dimension reduction, and differential expression. Which workflow matches this?

**ASSISTANT:** The `hippo` workflow (using the `bioconductor/hippo` tool) is designed for this exact purpose. It takes `counts_matrix.rds` (and optionally `gene_annotation.rds`) and generates `cluster_assignments`, `de_table`, and `feature_selection`.

---

## [47] source=multitask_sft_big

**USER:** What inputs are required to run the BioMate proteomics workflow profam_fitness_prediction, and what tools does it execute?

**ASSISTANT:** The `profam_fitness_prediction` workflow requires four inputs:
1. `input_fasta`
2. `variants_csv`
3. `wildtype`
4. `scoring_mode`

It orchestrates two tools:
- `PROFAM_PREDICT`
- `FITNESS_REPORT`

---

## [48] source=multitask_sft_big

**USER:** I need to configure a workflow to jointly analyze methylation coverage and SNP genotypes to produce GWAS summary statistics. What are the expected inputs and outputs?

**ASSISTANT:** You can use the `ramwas_cpg_snp_joint_analysis` workflow. It requires four inputs:
- `Coverage` (filematrix of normalized coverage scores)
- `CpG_locations` (filematrix of CpG genomic coordinates)
- `SNPs` (filematrix of genotype dosages/counts matching the coverage matrix)
- `covariates` (R data.frame with phenotypes and covariates)

The workflow yields `gwas_summary_statistics` as its output.

---

## [49] source=multitask_sft_big

**USER:** What is the structure of the Fastq Decontaminate Deacon workflow in terms of inputs, tools, and output files?

**ASSISTANT:** Here is the structure for `Fastq Decontaminate Deacon`:
- **Input**: Reference genome `fasta` file (along with the target FastQ sequencing reads)
- **Tools**: `deacon/index` (creates reference genome index) and `deacon/filter` (screens and filters matching reads)
- **Outputs**:
  - `index`: Generated Deacon genome index
  - `fastq`: Decontaminated FastQ reads
  - `log`: Execution and filtering logs
  - `versions`: Tool version manifest
  - `yml`: Execution configuration / parameter metadata

---

## [50] source=multitask_sft_big

**USER:** I have multi-sequence FASTA files and need to set up a standardized gene phylogenetics run using nf-core. Which workflow should I configure?

**ASSISTANT:** You should configure the 'nf-core/genephylo' pipeline. Provide your sequence records via the 'fasta' input, and specify the destination for generated phylogenetic analyses via the 'results_dir' output parameter.

---

## [51] source=multitask_sft_big

**USER:** How can I generate a retention-time-normalized SWATH/DIA spectral library from my BiblioSpec SQLite files and export it for Spectronaut?

**ASSISTANT:** You can utilize the 'specl' workflow in the proteomics domain. It takes:
- `BLIB_FILTERED_FILE.sqlite` (filtered non-redundant PSMs)
- `BLIB_REDUNDANT_FILE.sqlite` (all PSMs with iRT peptides)
- `FASTA_FILE.fasta.gz` (protein annotations)

The workflow executes `bioconductor/specl` (supported by `bioconductor/biocstyle`, `bioconductor/knitr`, and `bioconductor/rmarkdown`) to produce retention-time-normalized, non-redundant spectral library data (`normalized_data`) exported to a Spectronaut-compatible text file.

---

## [52] source=multitask_sft_big

**USER:** I need to run the CLI tool for Isotope Correction for mass spectrometry labeling experiments (`isocorcli`). Can you generate the command template showing the required and common optional flags?

**ASSISTANT:** Here is the command template for `isocorcli`:

```bash
isocorcli -t TRACER [-r RESOLUTION] [-m MZ_OF_RESOLUTION] [-f {orbitrap,ft-icr,constant,datafile}] [-p TRACER_PURITY] [-M M] [-D D] [-I I] [-n] [-v] inputdata
```

At minimum, you must specify the tracer using `-t TRACER` alongside the positional argument `inputdata`.

---

## [53] source=multitask_sft_big

**USER:** I am putting together a variant annotation pipeline and need a step to flag homopolymer run contexts directly in my VCF calls. How should I incorporate Jvarkit Vcfpolyx?

**ASSISTANT:** You can insert `Jvarkit Vcfpolyx` into your post-variant-calling annotation stage. Feed your indexed VCF or BCF file into `Jvarkit Vcfpolyx` alongside the reference genome sequence; it will compute poly-x repeat lengths flanking the variant sites and output an annotated VCF/BCF file for downstream filtering.

---

## [54] source=multitask_sft_big

**USER:** I am reconstructing a metabolic model from a reaction table and need to generate an SBML model where all reactions reside in a single default compartment rather than compartmentalizing by metabolite suffixes. How should I set up Tab2Sbml?

**ASSISTANT:** To reconstruct your network into SBML with a single default compartment, pass your tabulated reaction data into Tab2Sbml and ensure the 'Create compartment from metabolite suffixes' setting is deactivated.

---

## [55] source=multitask_sft_big

**USER:** Which Bioconductor packages are integrated into the scry workflow, and what outputs does it generate?

**ASSISTANT:** The `scry` workflow utilizes the following Bioconductor packages:
- `bioconductor/scry`
- `bioconductor/duoclustering2018`
- `bioconductor/singlecellexperiment`
- `bioconductor/tenxpbmcdata`
- `bioconductor/ggplot2`

It generates three primary outputs: `singlecellexperiment`, `feature_selection`, and `visualizations`.

---

## [56] source=multitask_sft_big

**USER:** Can you summarize the steps and expected outputs of the 'skewr' epigenomics workflow?

**ASSISTANT:** The 'skewr' workflow proceeds through the following steps:
1. Loads raw Illumina 450k IDAT files from the directory specified by 'baseDir' or takes an existing 'melon.raw' MethyLumiSet object.
2. Preprocesses and normalizes the methylation data using tools from bioconductor/skewr and bioconductor/minfidata.
3. Fits skew-normal mixture models to intensity distributions.
4. Generates outputs consisting of 'normalized_data' and 'visualizations' (diagnostic panel plots or single frame plots for QC).

---

## [57] source=multitask_sft_big

**USER:** I have a multiple sequence alignment and query sequences from tumor samples. I want to build a profile HMM and compute sequence likelihoods. Which workflow should I use and what are its inputs?

**ASSISTANT:** You should use the `methtargetedngs_profile_hmm_analysis` workflow. Its required input files are:
- `msa.fasta`: FASTA file containing the multiple sequence alignment used to build the Profile HMM.
- `Tumor.fasta`: FASTA file containing the query sequences for likelihood calculation.

---

## [58] source=multitask_sft_big

**USER:** I want to run an analysis linking gene expression and cancer mutations to drug response data using a CCLE PharmacoSet. How can I structure this using the `pharmacogx_gene_drug_association` workflow?

**ASSISTANT:** To run the `pharmacogx_gene_drug_association` workflow:

1. **Input Requirements**:
   - Provide `CCLEsmall`, a mandatory `.rds` file containing the `PharmacoSet` object (transcriptomics/genomics and drug sensitivity data).
2. **Execution**:
   - The workflow models the statistical association between molecular features (e.g., gene expression, mutations) and drug sensitivity profiles.
3. **Outputs Generated**:
   - Association statistics summary (`table/csv`).
   - Visual association plots (`plot/pdf`).
   - Processed R data objects (`object/rds`).

---

## [59] source=multitask_sft_big

**USER:** Can you provide the structure, tools, and outputs of the `spktools` workflow for analyzing spike-in microarray data?

**ASSISTANT:** The `spktools` workflow operates as follows:
- **Domain:** Transcriptomics
- **Required Input:** `SpikeInExpressionSet.RData` (an R object of class `SpikeInExpressionSet` containing the expression matrix and nominal concentrations)
- **Tools Used:** `bioconductor/spktools` and `bioconductor/xtable`
- **Outputs:** `de_table`, `normalized_data`, and `visualizations`

---

## [60] source=multitask_sft_big

**USER:** What steps does the 'khmer: Sequence partition all-in-one' tool execute during sequence assembly workflows?

**ASSISTANT:** The 'khmer: Sequence partition all-in-one' tool executes the following steps in sequence: 1) load a set of sequences, 2) partition them, 3) merge the partitions, and 4) annotate the original sequence files with the resulting partition information.

---

## [61] source=multitask_sft_big

**USER:** I want to deconvolute multiple spatial transcriptomics datasets using a single-cell RNA-seq reference without retraining the NMF model every time. Which workflow should I use and what inputs are required?

**ASSISTANT:** You should use the `spotlight_two_step_deconvolution` workflow. It trains the NMF model on your single-cell reference first and separates deconvolution so the model can be reused across spatial datasets.

Required inputs:
- `sce`: SingleCellExperiment object containing the single-cell reference data (RDS format).
- `spe`: SpatialExperiment object containing the spatial transcriptomics data.

---

## [62] source=multitask_sft_big

**USER:** I am drafting an epigenetics processing pipeline. Where should 'Create Assay Object' typically fit?

**ASSISTANT:** In standard epigenetics pipelines, 'Create Assay Object' typically sits at the ingestion stage, packaging raw matrix data, genomic ranges, or feature counts into a structured assay object prior to downstream normalization, differential analysis, or visualization.

---

## [63] source=multitask_sft_big

**USER:** I have massively parallel reporter assay data consisting of paired DNA and RNA count matrices across multiple cell types. How can I analyze differential activity between these cell types?

**ASSISTANT:** You can deploy the `mpra` workflow. Provide your DNA counts (`dna.txt`), RNA counts (`rna.txt`), and element identifiers (`eid.txt`)—along with optional element sequences (`eseq.txt`). The workflow uses `bioconductor/mpra` to fit differential activity models across your conditions, yielding CSV summary tables, PDF visualization plots, and RDS objects.

---

## [64] source=multitask_sft_big

**USER:** How can I assess if I have sufficient biological replicates in my transcriptomic experiment using the erssa workflow?

**ASSISTANT:** You can run the 'erssa' transcriptomics workflow using the underlying Bioconductor tools `bioconductor/erssa` and `bioconductor/ggplot2`. Provide your raw RNA-seq `count_table` (genes as rows, sample IDs as columns) and `condition_table` (column 1: sample IDs, column 2: conditions). The workflow performs empirical subsampling and differential expression to evaluate replicate sufficiency, producing a differential expression table (`de_table`) and graphical evaluation plots (`visualizations`).

---

## [65] source=multitask_sft_big

**USER:** What tool components make up the boltz_structure_prediction structural biology workflow?

**ASSISTANT:** The boltz_structure_prediction workflow comprises three tools executed in sequence: PREPARE_INPUT, BOLTZ_PREDICT, and BOLTZ_SUMMARISE_RESULTS.

---

## [66] source=multitask_sft_big

**USER:** Please outline the inputs, tools, and outputs involved in setting up the undo workflow.

**ASSISTANT:** The `undo` workflow setup is as follows:
- **Tool**: `bioconductor/undo`
- **Mandatory Input**: `mixed_expression.csv` (an n-by-m gene expression matrix or ExpressionSet object, normalized but not log-transformed)
- **Optional Inputs**: `true_mixing_matrix.csv` (real mixing matrix for validation) and `pure_expressions.csv` (pure expression profiles for validation)
- **Output**: `visualizations`

---

## [67] source=multitask_sft_big

**USER:** I need to align two separate LC-MS metabolomics datasets by matching retention times with non-linear splines and resolving alignment conflicts. Which workflow should I execute?

**ASSISTANT:** You should use the `metabcombiner` workflow. It aligns two LC-MS metabolomics datasets by grouping features, mapping retention times using non-linear splines, scoring alignments, and resolving conflicting feature assignments, ultimately producing alignment visualizations.

---

## [68] source=multitask_sft_big

**USER:** How can I identify differentially abundant proteins from MaxQuant LFQ data without performing missing-value imputation?

**ASSISTANT:** You can use the proda workflow. It takes 'proteinGroups.txt' (MaxQuant output containing protein IDs and LFQ intensity columns) and fits a probabilistic dropout model without imputation using bioconductor/proda and bioconductor/dep, yielding normalized data and differential abundance results.

---

## [69] source=multitask_sft_big

**USER:** Can you design a synthetic biology workflow step to prepare a target sequence for heterologous expression?

**ASSISTANT:** You can configure a step using `Biomni: Optimize Codons For Heterologous Expression`:
1. Input: Target DNA or RNA coding sequence along with the intended heterologous host organism.
2. Process: The tool analyzes codon usage and optimizes the sequence for host expression.
3. Output: Optimized sequence ready for downstream gene synthesis and cloning.

---

## [70] source=multitask_sft_big

**USER:** What tools and output files are involved in the quantro workflow?

**ASSISTANT:** The `quantro` workflow utilizes three Bioconductor packages:
- `bioconductor/quantro`
- `bioconductor/doparallel`
- `bioconductor/minfi`

Upon completion, it produces two outputs:
- `normalized_data`
- `visualizations`

---

## [71] source=multitask_sft_big

**USER:** I need to calculate the total binding affinity and occupancy of transcription factors on a specific DNA sequence using JASPAR position frequency matrices. Which workflow should I run?

**ASSISTANT:** You should run the `matrixrider` workflow. It calculates the total binding affinity or occupancy of single or multiple transcription factors on a target DNA sequence using `bioconductor/matrixrider`, `bioconductor/biostrings`, `bioconductor/jaspar2014`, and `bioconductor/tfbstools`. It requires a target DNA sequence (`sequence.fasta`) and JASPAR motifs (`jaspar_db`), generating results in `table/csv`, `plot/pdf`, and `object/rds` formats.

---

## [72] source=multitask_sft_big

**USER:** What outputs does `nempi_prior_guided_perturbation_inference` generate upon completion?

**ASSISTANT:** The workflow generates three output items:
1. `de_table`
2. `pathway_results`
3. `normalized_data`

---

## [73] source=multitask_sft_big

**USER:** Generate a workflow call or execution specification to estimate expected rare variants per MAC bin with ancestry-specific defaults using my file `mac_bins.csv`.

**ASSISTANT:** Here is the workflow specification for `raresim_estimate_expected_variants_with_defaults`:

- **Workflow**: `raresim_estimate_expected_variants_with_defaults`
- **Domain**: `variant_calling`
- **Data Inputs**:
  - `mac_bins.csv`: Path to CSV file defining the lower and upper boundaries of the MAC bins (required)
- **Parameters**: Uses default ancestry-specific parameters
- **Outputs**:
  - `burden_test_results`: Expected number of rare variants per MAC bin formatted for downstream burden analysis

---

## [74] source=multitask_sft_big

**USER:** Could you outline the steps and tools used in the `dep` workflow for analyzing mass spectrometry intensity data?

**ASSISTANT:** The `dep` workflow processes mass spectrometry intensity data through robust filtering, normalization, imputation, and linear modeling. It utilizes Bioconductor and tidyverse packages including `bioconductor/dep`, `bioconductor/biocstyle`, `bioconductor/summarizedexperiment`, `bioconductor/dplyr`, `bioconductor/ggplot2`, and `bioconductor/purrr`, yielding differential expression tables (`de_table`), a `summarizedexperiment` object, and `normalized_data`.

---

## [75] source=multitask_sft_big

**USER:** What tools are utilized in the kissde workflow and what outputs does it yield?

**ASSISTANT:** The workflow uses the `bioconductor/kissde` package to analyze the alternative splicing data. It produces three types of outputs:
- `table/csv`: Tabular results of differential splicing tests
- `plot/pdf`: Graphical visualizations of the splicing events
- `object/rds`: Serialized R data objects containing the results.

---

## [76] source=multitask_sft_big

**USER:** I want to visualize genomic scores and microarray signals using Bioconductor track visualization tools from a GRanges object and a bedGraph file. What workflow should I run?

**ASSISTANT:** You should use the 'gviz' workflow from the genomics domain. It accepts a `twoGroups` GRanges object with numeric metadata and a `bgFile.bedGraph` file to generate genomic visualizations using Bioconductor packages including Gviz, GenomicRanges, GenomicFeatures, biomaRt, ensembldb, and knitr.

---

## [77] source=multitask_sft_big

**USER:** Can you describe the sequence of processing steps performed by msnid_handling_and_mapping_modifications?

**ASSISTANT:** The workflow performs the following steps:
1. Reads modified peptide search results from mzIdentML data.
2. Encodes modification masses using symbols.
3. Maps modification sites to corresponding protein sequences using the provided FASTA file.
4. Remaps protein accessions to gene symbols, exporting results as CSV tables, PDF plots, and RDS objects.

---

## [78] source=multitask_sft_big

**USER:** Can you define the standard input and output channels for the nf-core/archive_extract pipeline?

**ASSISTANT:** For `nf-core/archive_extract`, the required input is:
- `archive`: The archive file(s) to be extracted (e.g., `.gz`, `.tar.gz`, `.zip`).

The produced outputs are:
- `extracted`: The successfully decompressed files.
- `not_extracted`: Any archives that could not be extracted.

---

## [79] source=multitask_sft_big

**USER:** I need an epigenomics pipeline to perform absolute quantification and bias adjustment on cfMeDIP-seq BAM files. Is there a workflow for this?

**ASSISTANT:** Yes, you can run the **spiky** workflow (utilizing `bioconductor/spiky`). It performs absolute quantification and bias adjustment on cfMeDIP-seq data from paired genomic and spike-in BAM files.

---

## [80] source=multitask_sft_big

**USER:** How can I set up an analysis pipeline to generate coverage visualizations from my genomic feature BED files (TSSs.bed, conv_transcription_loci.bed) and BigWig tracks (Scc1.bw, RNA.fwd.bw, RNA.rev.bw, PolII.bw, MNase.bw)?

**ASSISTANT:** You can configure the `tidycoverage_aggregated_coverage_multiple_features` workflow. Feed your genomic feature sets (`TSSs.bed`, `conv_transcription_loci.bed`) and signal tracks (`Scc1.bw`, `RNA.fwd.bw`, `RNA.rev.bw`, `PolII.bw`, `MNase.bw`) as inputs. The workflow will extract and aggregate coverage data to produce your output `visualizations`.

---

## [81] source=multitask_sft_big

**USER:** Can you outline the standard data processing flow when using `specL` based on its documented workflow?

**ASSISTANT:** The typical `specL` workflow proceeds as follows:
1. Load peptide spectrum matches using the built-in BiblioSpec reader.
2. Annotate the spectra with protein information using an amino acid FASTA reference file.
3. Generate and export the compiled spectral library for downstream MRM/SRM targeted proteomics assays.

---

## [82] source=multitask_sft_big

**USER:** Can you provide the execution setup for the sigfuge workflow to cluster RNA-seq locus coverage?

**ASSISTANT:** The `sigfuge` workflow is configured as follows:
- **Domain:** Transcriptomics
- **Objective:** Cluster RNA-seq coverage data and test statistical significance of the clusters
- **Required Inputs:**
  1. `coverage_data.RData` (matrix of locus-level RNA-seq read coverage across samples)
  2. `clusters.csv` (pre-defined or computed sample cluster assignments)
- **Underlying Tools:** `bioconductor/sigfuge`, `bioconductor/rsamtools`, `bioconductor/prebsdata`
- **Outputs:** `cluster_assignments`, `visualizations`

---

## [83] source=multitask_sft_big

**USER:** I have a massive genomic dataset in SeqArray GDS format and need to process variant calls in memory-efficient chunks. Which workflow can I use and what iterators does it support?

**ASSISTANT:** You can use the `seqvartools_iterative_variant_processing` workflow. It enables processing large genomic datasets in memory-efficient chunks using block, range, window, or list iterators.

---

## [84] source=multitask_sft_big

**USER:** I am designing a bioimaging pipeline that requires a registration setup stage. Which component should I incorporate to set up the registration method?

**ASSISTANT:** You should include the bioimaging helper tool `setup_registration_method` to handle the configuration of your registration method.

---

## [85] source=multitask_sft_big

**USER:** How does Gatherbqsrreports fit into a distributed GATK4 preprocessing pipeline?

**ASSISTANT:** In a distributed GATK4 pipeline: 1) Run BaseRecalibrator independently on scattered genomic intervals to generate multiple partial BQSR tables. 2) Run Gatk4 Gatherbqsrreports to merge the scattered reports into a single recalibration report. 3) Pass the unified report to ApplyBQSR to recalibrate the reads.

---

## [86] source=multitask_sft_big

**USER:** I have multiplexed metabarcoding sequencing data processed with UCLUST. I need to quantify cluster representation across samples and extract seeds. What workflow step processes this UC output?

**ASSISTANT:** Use `uclust_composition` to parse the UCLUST output. It will structure your multiplexed amplicon data into a table of cluster IDs and member counts per barcode/sample, and generate a UC file containing only the seed sequences, which you can subsequently convert to FASTA using `uc2fastax`.

---

## [87] source=multitask_sft_big

**USER:** I want to calculate species-specific codon relative adaptiveness values (w) using transcriptomic reference sequences of highly expressed genes. Can you suggest a workflow for this?

**ASSISTANT:** You can use the `genega_custom_w_table_computation` workflow from the transcriptomics domain. By supplying a FASTA file of highly expressed gene sequences, it computes the custom codon relative adaptiveness (w) table and outputs a CSV table, a PDF plot, and an RDS object.

---

## [88] source=multitask_sft_big

**USER:** Can you provide a basic invocation outline for running nf-core/meerpipe?

**ASSISTANT:** You can launch nf-core/meerpipe by supplying the pipeline input and defining the output directory structure:

```bash
nextflow run nf-core/meerpipe \
    --input <path_to_input> \
    --outdir <path_to_results_dir>
```
This workflow coordinates modules such as pulsar, ephemeris, utcs, and utce to generate the final results_dir.

---

## [89] source=multitask_sft_big

**USER:** I want to assess the impact of several continuous clinical markers and categorical stages on patient overall survival using a semi-parametric model. Which workflow should I configure?

**ASSISTANT:** You should configure the `survival_cox_proportional_hazards_regression` workflow. It fits a semi-parametric Cox proportional hazards model evaluating continuous and categorical covariates from `patient_clinical_data.csv` and outputs survival visualizations.

---

## [90] source=multitask_sft_big

**USER:** What tools and software packages are executed within the `sctgif` workflow, and what outputs does it yield?

**ASSISTANT:** The `sctgif` workflow utilizes the following Bioconductor packages:
- `bioconductor/sctgif`
- `bioconductor/gseabase`
- `bioconductor/singlecellexperiment`
- `bioconductor/msigdbr`

It produces three primary outputs:
- `cluster_assignments`
- `singlecellexperiment`
- `expression_matrix`

---

## [91] source=multitask_sft_big

**USER:** I have unaligned query FASTA sequences, a reference alignment, and a Newick reference phylogeny. I want to perform phylogenetic placement using EPA-ng and downstream analysis with GAPPA. How should the pipeline steps be structured?

**ASSISTANT:** You can follow the 'Fasta Newick Epang Gappa' workflow design from nf-core/phyloplace:
1. **Alignment / Profile Construction:** Use HMMER (`hmmbuild`, `hmmalign`, `eslalimask`, `eslreformat`) or alignment tools (`mafft/align`, `clustalo/align`) depending on your `alignmethod`.
2. **Placement:** Run `epang/place` using your `queryseqfile`, `refseqfile`, `refphylogeny`, and evolutionary `model` (followed by `epang/split` if needed).
3. **Post-Placement & Visualization:** Process placement trees via GAPPA using `gappa/examinegraft`, `gappa/examineassign`, and `gappa/examineheattree` to generate tree outputs and taxonomy assignments.

---

## [92] source=multitask_sft_big

**USER:** Generate a workflow configuration to run large-scale parallel processing on count data in R without duplicating memory across child processes.

**ASSISTANT:** You can use the `SharedObject` Nextflow workflow:

- Workflow: `SharedObject`
- Tools involved: `bioconductor/sharedobject`, `bioconductor/parallel`
- Inputs: `count_data` (optional count matrix/dataset)
- Mechanism: Creates the R object in shared memory space so parallel child worker processes read from a single shared instance without duplicating objects or incurring inter-process transfer overhead.

---

## [93] source=multitask_sft_big

**USER:** How do I set up reference preparation before running bbmap.sh mapping?

**ASSISTANT:** To prepare your reference, pass your FASTA file to 'Bbmap Index'. Once Bbmap Index finishes generating the index from the FASTA file, you can provide the resulting index directly to bbmap.sh to perform mapping.

---

## [94] source=multitask_sft_big

**USER:** I want to assemble an epitranscriptomics resource tracking m6A sites and their corresponding writers. How does EpiTxDb fit into such a workflow?

**ASSISTANT:** You can use `EpiTxDb` under the 'EpiTxDb-creation' design pattern to construct an epitranscriptomic database. The workflow ingests RNA modification sites, annotates each entry with the modification identity (e.g., m6A), maps the specific RNA coordinates, links the responsible enzyme (writer), includes position-determining specifiers, and records the literature citations for unified tracking.

---

## [95] source=multitask_sft_big

**USER:** I want to perform guided biclustering on transcriptomics data by incorporating protein-protein interaction weights. What workflow should I run and what outputs will it generate?

**ASSISTANT:** You should run the `qubic_query_based_biclustering` workflow. 

- **Inputs:** `expression_matrix.csv` (gene expression matrix) and `weight_matrix.csv` (gene interaction/adjacency weights).
- **Outputs:** `cluster_assignments` and `network_graph`.

---

## [96] source=multitask_sft_big

**USER:** I want to set up an automated variant processing step that partitions variant call sets into N chunks. What tool should be integrated?

**ASSISTANT:** Integrate `Rbt Vcfsplit`. It will partition your VCF/BCF variant call sets into N equal chunks with full support for BND records.

---

## [97] source=multitask_sft_big

**USER:** I have query sequences in a FASTA file ('RNA_example.fasta') and a compressed NCBI BLAST database archive ('16S_ribosomal_RNA.tar.gz'). Can you provide a workflow to run a local BLAST search on them?

**ASSISTANT:** You can use the **rblast** workflow (based on `bioconductor/rblast`). It accepts your compressed database archive `16S_ribosomal_RNA.tar.gz` and query FASTA file `RNA_example.fasta`, extracts the database, executes the local BLAST query, and generates results as a CSV table (`table/csv`), a visualization (`plot/pdf`), and an R data object (`object/rds`).

---

## [98] source=multitask_sft_big

**USER:** I want to align multiple mutant DNA sequences against a wild-type reference sequence and produce plots highlighting mismatches, insertions, and deletions. How can I run this workflow?

**ASSISTANT:** You can use the `ggseqalign` workflow. Provide the following inputs:
- `query_sequences.fa`: FASTA file containing your query DNA or amino acid sequences.
- `subject_sequence`: The reference DNA or amino acid sequence (as a string or FASTA file).

The workflow uses `bioconductor/biostrings`, `bioconductor/ggseqalign`, and `bioconductor/ggplot2` to perform the alignment and output visualizations of mismatches, insertions, and deletions.

---

## [99] source=multitask_sft_big

**USER:** What are the main analytical steps performed in the `sctensor` pipeline for single-cell RNA-seq cell-cell interaction analysis?

**ASSISTANT:** The `sctensor` pipeline carries out four sequential steps:
1. Cell-cell interaction tensor construction from single-cell RNA-Seq data.
2. Rank estimation for the tensor.
3. Tensor decomposition.
4. HTML report generation, producing `singlecellexperiment` data and `visualizations`.

---

## [100] source=multitask_sft_big

**USER:** Which tool does the `rgenometracks` workflow utilize, and what is its output?

**ASSISTANT:** The `rgenometracks` workflow is powered by the `bioconductor/rgenometracks` tool and generates multi-track genomic `visualizations` as its output.

---

## [101] source=multitask_sft_big

**USER:** Can you configure the inputs for the rTRMui workflow for my transcriptomic count data?

**ASSISTANT:** To run the rTRMui workflow, assign your dataset to the required input:

```json
{
  "workflow": "rTRMui",
  "inputs": {
    "input_files": "path/to/count_data.tsv"
  }
}
```
This passes your count data to the underlying bioconductor/rtrmui tool to identify transcriptional regulatory modules.

---

## [102] source=multitask_sft_big

**USER:** I want to analyze ribosome profiling data from `HEK293_ingolia.ribo`. How can I process this and what outputs can I expect?

**ASSISTANT:** You can process your data using the `ribor` workflow. Provide your ribosome profiling file (`HEK293_ingolia.ribo`) as the input. The workflow will use `bioconductor/ribor` and `bioconductor/devtools` to generate three output types:
- `table/csv`: Tables containing region-specific ribosome profiling counts.
- `plot/pdf`: Quality control plots displaying read length distributions and metagene analysis.
- `object/rds`: Serialized R data objects for downstream exploration.

---

## [103] source=multitask_sft_big

**USER:** What is the recommended procedure to produce the alignment file required by GFF align starting from raw genome alignments?

**ASSISTANT:** The suggested procedure is:
1. Run Last to generate genome alignments in MAF format.
2. Convert the MAF output to TAB format using maf-convert.
3. Provide the resulting TAB alignment file to GFF align.

---

## [104] source=multitask_sft_big

**USER:** I need to run a fast structural similarity search of my protein structure against a Foldseek database. How can I structure this step using Foldseek?

**ASSISTANT:** You can structure the workflow step using Foldseek's streamlined search interface:
1. Input: Your query protein structure file (e.g., PDB/mmCIF format) and the target Foldseek structure database.
2. Tool: Execute `foldseek easy-search <query_structure> <target_database> <alignment_output> <tmp_dir>`.
3. Output: An alignment result file reporting the structural hits matching your query.

---

## [105] source=multitask_sft_big

**USER:** I have an RNA-Seq dataset without any replicates, consisting of a raw count matrix with one column per condition. How can I run differential expression analysis?

**ASSISTANT:** You can use the `absseq_single_replicate_de_analysis` workflow in the transcriptomics domain. Provide your data as `counts_no_replicates.tsv` (a matrix of raw integer counts containing exactly two columns, one for each condition). The workflow will produce two outputs: `de_table` and `counts_matrix`.

---

## [106] source=multitask_sft_big

**USER:** How can I set up a step in my regulatory genomics pipeline to find nearest genomic features flanking a set of target loci?

**ASSISTANT:** Provide your target loci as the first set of genomic intervals and your candidate feature regions as the second set, then process them through `get flanking` to extract the nearest flanking elements.

---

## [107] source=multitask_sft_big

**USER:** Can you outline the inputs and expected outputs for musicatk_predict_known_signatures?

**ASSISTANT:** For **musicatk_predict_known_signatures**:
- **Inputs**: `public_TCGA.LUSC.maf (Mutation Annotation Format file)` and `public_LUAD_TCGA-97-7938.vcf (Variant Call Format file)`
- **Output**: `mutational_signatures` representing predicted exposures of known signatures.

---

## [108] source=multitask_sft_big

**USER:** I need to set up the "Mmseqs Fasta Cluster" subworkflow for amino acid clustering. What inputs does it accept, and which internal tools are executed?

**ASSISTANT:** The "Mmseqs Fasta Cluster" subworkflow takes an input amino acid sequence file in FASTA format (`fasta`). It chains the following tools: `mmseqs/createdb`, `mmseqs/cluster`, `mmseqs/linclust`, and `mmseqs/createtsv`.

---

## [109] source=multitask_sft_big

**USER:** What does jackhmmer do after completing the initial search iteration to prepare for the next round?

**ASSISTANT:** For the next iteration, jackhmmer constructs a multiple sequence alignment containing the query sequence together with all target sequences from <seqdb> that satisfied the search criteria in the previous iteration.

---

## [110] source=multitask_sft_big

**USER:** Can you outline how to set up the chipsim_transcription_factor_binding_simulation workflow for an epigenomics experiment?

**ASSISTANT:** To set up the 'chipsim_transcription_factor_binding_simulation' workflow:
1. Provide the mandatory reference genome sequence as 'genome.fasta'.
2. Specify any additional required input files via 'input_files'.
3. Configure simulation parameters for custom feature generation, transition probabilities, and strand-specific read densities.
4. Execute the workflow to generate simulated ChIP-seq results as CSV tables, PDF plots, and RDS objects.

---

## [111] source=multitask_sft_big

**USER:** When running the semdist workflow, what output formats should I expect to receive?

**ASSISTANT:** The `semdist` workflow generates three primary outputs:
- `table/csv`: Tabular results containing calculated metrics.
- `plot/pdf`: PDF figures visualising information accretion or semantic distance.
- `object/rds`: A serialized R data object containing the underlying analysis structures.

---

## [112] source=multitask_sft_big

**USER:** How does the drawProteins workflow generate protein schematics from UniProt data?

**ASSISTANT:** The `drawProteins` workflow processes UniProt API output (JSON obtained via GET requests), converts it into a structured dataframe using the UniProt Features API, and uses Bioconductor tools alongside ggplot2 and base R geoms to render protein schematics. It integrates tools including `bioconductor/drawproteins`, `bioconductor/biocstyle`, `bioconductor/ggplot2`, `bioconductor/httr`, and `bioconductor/knitr`.

---

## [113] source=multitask_sft_big

**USER:** I have a reference FASTA file and want to prepare the necessary coordinate reference files for creating ribosome profiles. How do I start?

**ASSISTANT:** To prepare your coordinate reference files, initiate the pipeline with the **Get Chromosome Sizes** tool:

1. **Input**: Reference genome in FASTA format.
2. **Tool Execution**: Run `Get Chromosome Sizes` to extract sequence lengths for each chromosome/contig.
3. **Output**: A chromosome sizes file, ready for downstream ribosome profiling alignment and profile generation.

---

## [114] source=multitask_sft_big

**USER:** How do I use AEGeAn LocusPocus to organize gene annotations for comparative genomics?

**ASSISTANT:** You provide your set of gene annotations to `AEGeAn LocusPocus`. The program will compute interval loci (iLoci), delineating single genes, overlapping gene clusters, and intergenic regions to generate a standardized, locus-based genomic organization suitable for comparative genomics.

---

## [115] source=multitask_sft_big

**USER:** I have a list of pathway genes stored in a local text file called path_genes.txt. How should I format the PAPAA execution argument?

**ASSISTANT:** In your PAPAA execution command, reference your gene list using the `--path_genes` argument:

```bash
--path_genes path_genes.txt
```
PAPAA accepts either this text file or a comma-separated list of HUGO symbols.

---

## [116] source=multitask_sft_big

**USER:** I have multiple 10X Genomics Chromium sample runs and want to load them all into Scater without barcode collisions. How can I achieve this?

**ASSISTANT:** Provide a named vector of directory paths containing your `matrix.mtx`, `genes.txt`, and `barcodes.txt` files to Scater's read 10x data function. When a named vector is used, Scater automatically prefixes each cell barcode with the corresponding sample name to ensure uniqueness.

---

## [117] source=multitask_sft_big

**USER:** I have unaligned FASTA sequences from several viral strains and want to build a multiple sequence alignment. What is the tool invocation step for this?

**ASSISTANT:** Feed your multi-sequence FASTA file into **Clustalo Align**. It will run Clustal Omega to compute the multiple sequence alignment (MSA) and output the aligned sequences.

---

## [118] source=multitask_sft_big

**USER:** I have short-read FASTQ files and a reference genome index. How can I align them using the bwa aln algorithm and generate alignment quality reports?

**ASSISTANT:** You can deploy the `Fastq Align Bwaaln` workflow. It takes `reads` and a reference `index` as inputs, executes alignment via `bwa/aln` paired with `bwa/sampe` (for paired-end) or `bwa/samse` (for single-end), indexes the resulting sorted BAM files with `samtools/index`, and generates outputs including processed fastq files and a `multiqc_report`.

---

## [119] source=multitask_sft_big

**USER:** I have completed a genome-wide association study and have a summary statistics TSV file. I want to perform functional mapping, identify genomic risk loci, and run MAGMA gene and gene-set enrichment analyses. What pipeline should I run?

**ASSISTANT:** You should run the 'fuma_functional_annotation' workflow. It submits your GWAS summary statistics (TSV/TXT) to the FUMA SNP2GENE web endpoint, monitors execution until completion, and downloads and parses the results—including genomic risk loci, MAGMA gene-based test statistics, and MAGMA gene-set enrichment analysis (GSA) into JSON and Markdown reports.

---

## [120] source=multitask_sft_big

**USER:** What underlying tools are utilized by the ntw workflow, and what output does it produce?

**ASSISTANT:** The 'ntw' workflow utilizes 'bioconductor/ntw' and 'bioconductor/mvtnorm' to generate a 'network_graph' as its output.

---

## [121] source=multitask_sft_big

**USER:** What does the transcriptomics workflow scry_sce_null_residuals_pca do, and what outputs does it yield?

**ASSISTANT:** The workflow performs fast dimension reduction approximation by computing null residuals on raw counts and running standard PCA. It outputs an updated 'singlecellexperiment' object and 'feature_selection' results.

---

## [122] source=multitask_sft_big

**USER:** Can you provide the input and output specifications for the readqpcr pipeline?

**ASSISTANT:** The `readqpcr` workflow specifications are:
- **Domain**: Transcriptomics
- **Underlying Tool**: `bioconductor/readqpcr`
- **Inputs**: `LC480_Example.txt` (raw LC480 exported text file) and `LC480_Example_SampleInfo.txt` (sample information text file)
- **Outputs**: `normalized_data` and `de_table`

---

## [123] source=multitask_sft_big

**USER:** I have MiXCR output from a TCR sequencing experiment and want to fit a discrete gamma-GPD spliced threshold model to estimate diversity and cluster clones. What workflow should I run?

**ASSISTANT:** You should run the `powertcr` workflow (domain: immunology). It takes your TCR sequencing file (`sample_tcr_repertoire.txt`, compatible with MiXCR, MiTCR, MiGEC, VDJtools, ImmunoSEQ, IMSEQ, or clone size vectors) and utilizes `bioconductor/powertcr`, `bioconductor/magrittr`, `bioconductor/purrr`, and `bioconductor/vegan` to fit the discrete gamma-GPD model, perform comparative clustering, compute diversity estimates, and generate `cluster_assignments` and `visualizations`.

---

## [124] source=multitask_sft_big

**USER:** Can Sparse Matrix Functions be used to combine feature matrices both across samples (adding rows) and across feature spaces (adding columns)?

**ASSISTANT:** Yes. `Sparse Matrix Functions` supports both horizontal (column-wise) stacking to combine features and vertical (row-wise) stacking to combine observations/samples.

---

## [125] source=multitask_sft_big

**USER:** I am putting together a pipeline that aligns protein sequences against a genome using miniprot. How should the initial genome preparation step be configured?

**ASSISTANT:** Before running miniprot alignment, pass your reference genome FASTA file through Miniprot Index. The resulting index is required as input for the subsequent miniprot alignment step.

---

## [126] source=multitask_sft_big

**USER:** Can you design an epigenomics peak-calling process using gcapc and describe its input/output setup?

**ASSISTANT:** You can run the `gcapc` workflow with the following structure:
- **Domain**: Epigenomics
- **Input**: `chipseq.bam` (ChIP-seq alignment BAM file) or `input_files`
- **Tool**: `bioconductor/gcapc`
- **Processing**: Executes GC-bias-corrected peak calling and refines peak significance from the aligned reads.
- **Outputs**: Peak tables (`table/csv`), QC/diagnostic plots (`plot/pdf`), and serialized R objects (`object/rds`).

---

## [127] source=multitask_sft_big

**USER:** Which tools are executed in the ngsreports workflow and what are its final outputs?

**ASSISTANT:** The ngsreports workflow integrates the following Bioconductor tools:
- `bioconductor/ngsreports`
- `bioconductor/dplyr`
- `bioconductor/pander`

It generates two primary outputs:
- `qc_report`
- `visualizations`

---

## [128] source=multitask_sft_big

**USER:** I need to classify samples from a test transcriptomics matrix using a KTSP classifier trained on a labeled reference matrix. Can you configure the switchbox workflow for this?

**ASSISTANT:** You can deploy the 'switchbox' transcriptomics workflow using the tool 'bioconductor/switchbox'. Configure it with your data inputs: set 'matTraining' to your reference numeric matrix (features as rows, samples as columns), provide the class labels as the factor 'trainingGroup', and set 'matTesting' to your new test expression matrix to perform KTSP classification and produce the output.

---

## [129] source=multitask_sft_big

**USER:** What components, packages, and outputs are involved if I run the 'msa' sequence alignment workflow?

**ASSISTANT:** The 'msa' workflow takes unaligned sequences (such as an amino acid FASTA file) and utilizes Bioconductor packages including `bioconductor/msa`, `bioconductor/seqinr`, `bioconductor/pwalign`, and `bioconductor/ape`. It outputs `consensus_score` and `visualizations` (customizable PDF alignments).

---

## [130] source=multitask_sft_big

**USER:** I have an unindexed reference genome in FASTA format and paired FASTQ reads. How do I prepare the reference so it can be used by Bowtie?

**ASSISTANT:** To prepare your reference genome for Bowtie, the first required step is indexing:
1. Run 'Bowtie2 Build' using your reference genome FASTA file as input to build the Bowtie reference index.
Once the index files are generated, they can be utilized for downstream read alignment.

---

## [131] source=multitask_sft_big

**USER:** I have normalized microarray query expression data and a normalized reference matrix. I need to classify the query samples and generate visual outputs. How is the 'sampleclassifier' workflow structured?

**ASSISTANT:** The 'sampleclassifier' workflow is structured as follows:
- Domain: Transcriptomics
- Inputs:
  - `micro_refmat`: Normalized microarray reference matrix (probe sets as rows, samples as columns)
  - `micro_testmat`: Normalized microarray query matrix to be classified
- Underlying Tools: `bioconductor/sampleclassifier` and `bioconductor/sampleclassifierdata`
- Output: `visualizations` classifying the query microarray profiles against the reference.

---

## [132] source=multitask_sft_big

**USER:** I have a distorted proteomics intensity matrix and want to detect rank-invariant features while applying mean/median-balanced quantile normalization. Which workflow should I use and what outputs will it provide?

**ASSISTANT:** You should use the 'mbqn' workflow. It takes your distorted intensity matrix via the 'mtx' input and utilizes the 'bioconductor/mbqn' tool to produce two outputs: 'normalized_data' and 'visualizations'.

---

## [133] source=multitask_sft_big

**USER:** I need to infer a global synteny network across multiple proteomes, cluster it, perform phylogenomic profiling, and build a microsynteny-based phylogenetic tree. Which workflow should I use?

**ASSISTANT:** You should use the `syntenet` workflow in the genomics domain. It uses `bioconductor/syntenet` and `bioconductor/ggtree` to infer a global synteny network from multiple species' proteomes, perform clustering and phylogenomic profiling, and reconstruct a `phylogenetic_tree`.

---

## [134] source=multitask_sft_big

**USER:** I need to run a linear mixed model analysis on quantitative mouse phenotype measurements to test for genotype effects while controlling for batch and sex. How should this workflow be constructed?

**ASSISTANT:** You can construct the `phenstat` workflow as follows:
- **Input**: `phenotypic_data.csv` (CSV file with columns for Genotype, Sex, Batch, and the quantitative dependent variable).
- **Tool**: `bioconductor/phenstat` (executes the linear mixed model to evaluate genotype effects while controlling for batch and sex).
- **Output**: `visualizations` (diagnostic and effect plots generated from the statistical analysis).

---

## [135] source=multitask_sft_big

**USER:** What tools and output formats are involved if I run the flagme workflow?

**ASSISTANT:** The `flagme` workflow utilizes the Bioconductor tools `bioconductor/flagme` and `bioconductor/gcspikelite`. It generates three outputs: a table in CSV format (`table/csv`), a plot in PDF format (`plot/pdf`), and an R data object (`object/rds`).

---

## [136] source=multitask_sft_big

**USER:** In a Sentieon-based variant calling pipeline, where does Sentieon Qualcal fit and what are its primary steps?

**ASSISTANT:** Sentieon Qualcal is placed after alignment/duplicate marking to handle base quality score recalibration (BQSR). Its execution involves generating the recalibration table from the aligned reads and optionally applying those recalibrated scores before downstream variant calling.

---

## [137] source=multitask_sft_big

**USER:** Can you design a genomics workflow to predict the disruptiveness of single nucleotide polymorphisms on transcription factor binding sites?

**ASSISTANT:** You can run the `motifbreakr` workflow. It integrates `bioconductor/motifbreakr`, `bioconductor/bsgenome`, and `bioconductor/motifdb`. Providing your `variants.vcf` along with the appropriate `genome_assembly` (e.g., `BSgenome.Hsapiens.UCSC.hg19`) will generate disruption predictions in `table/csv`, `plot/pdf`, and `object/rds` formats.

---

## [138] source=multitask_sft_big

**USER:** I need to design a pipeline for SNP discovery from multi-sample sequence alignments in a phylogenomics study. How should I set this up?

**ASSISTANT:** You can construct a workflow as follows:
1. Prepare your aligned multi-sample sequence dataset in multi-FASTA format.
2. Run 'Finds SNP sites' on the multi-FASTA alignment to extract the polymorphic positions using minimal memory overhead.
3. Output the identified SNP sites into your desired downstream format for phylogenetic reconstruction or population genetics analysis.

---

## [139] source=multitask_sft_big

**USER:** I need an interactive workflow in the epigenomics domain to assess array quality controls and inspect bad samples using Shiny. What workflow is available?

**ASSISTANT:** You can use the `MethylAid` workflow. It is an epigenomics workflow utilizing an RStudio Shiny interface to detect bad quality samples via array controls and user-adjustable thresholds, enabling in-depth exploration through interactive diagnostic plots.

---

## [140] source=multitask_sft_big

**USER:** What tools and output types are involved in running the escher spatial transcriptomics pipeline?

**ASSISTANT:** The `escher` workflow utilizes Bioconductor tools including `bioconductor/escher`, `bioconductor/devtools`, `bioconductor/ggpubr`, `bioconductor/stexampledata`, `bioconductor/scater`, and `bioconductor/scran`. It processes `spe.rds` to produce `singlecellexperiment` data structures and `visualizations`.

---

## [141] source=multitask_sft_big

**USER:** What standard analysis and benchmarking workflows are supported by the `muscat` package for single-cell transcriptomics?

**ASSISTANT:** `muscat` supports workflows for: 1. Differential State (DS) analysis across multi-sample and multi-cell subpopulation scRNA-seq data, 2. Data simulation, and 3. Differential detection and visualization.

---

## [142] source=multitask_sft_big

**USER:** I need a workflow that performs multivariate GLS regression with GGM-based covariance estimation, scales coefficients back to the original scale, and optimizes parameters using AIC/BIC or minimal variance. What workflow should I run?

**ASSISTANT:** You should use the `sparsenetgls` workflow. It performs multivariate generalized least squares (GLS) regression using Gaussian Graphical Model (GGM)-based covariance estimation, transforms coefficients back to their original scale, and selects optimal tuning parameters based on minimal variance or AIC/BIC criteria.

---

## [143] source=multitask_sft_big

**USER:** How can I set up a workflow to identify differentially coexpressed genes between two conditions?

**ASSISTANT:** You can run the `diffcoexp` transcriptomics workflow:
1. Provide `exprs.1` containing the normalized gene expression data for condition 1.
2. Provide `exprs.2` containing the normalized gene expression data for condition 2.
3. Run the workflow using `bioconductor/diffcoexp` to identify differentially coexpressed gene pairs (DCLs) and genes (DCGs), which will output expression matrices, normalized data, and visualizations.

---

## [144] source=multitask_sft_big

**USER:** I need a transcriptomics workflow to detect tissue- or cell-type-specific marker genes from my normalized RNA-seq data. What workflow is available?

**ASSISTANT:** You can use the 'mgfr' workflow. It utilizes `bioconductor/mgfr` to detect tissue- or cell-type-specific marker genes from a normalized RNA-seq expression matrix paired with sample class labels, returning marker genes as an R list alongside the expression and normalized data.

---

## [145] source=multitask_sft_big

**USER:** I need a transcriptomics workflow to normalize scRNA-seq data formatted as a SingleCellExperiment object using Dino.

**ASSISTANT:** You can use the `dino_single_cell_experiment_normalization` workflow. It accepts raw scRNA-seq UMI counts (e.g., `pbmcSmall`) and outputs normalized single-cell data, the updated `counts_matrix`, and the resulting `singlecellexperiment` object.

---

## [146] source=multitask_sft_big

**USER:** Can you summarize the inputs, outputs, and underlying tools used in the complete rgsepd transcriptomics pipeline?

**ASSISTANT:** The `rgsepd` workflow takes two required inputs: `finalCounts` (matrix of RNA-Seq read counts with RefSeq NM/NR transcript IDs as rows and sample IDs as columns) and `sampleMeta` (data frame or CSV mapping sample IDs to conditions and short names). It utilizes `bioconductor/rgsepd` and `bioconductor/xtable` to generate three outputs: `de_table` (differential expression results), `enrichment_results` (GO enrichment), and `visualizations` (multidimensional projection displays).

---

## [147] source=multitask_sft_big

**USER:** What outputs and Bioconductor tools are involved when executing genetclassifier?

**ASSISTANT:** The `genetclassifier` workflow integrates the Bioconductor tools `bioconductor/genetclassifier` and `bioconductor/leukemiaseset`. Upon execution, it generates two primary outputs: `network_graph` and `visualizations`.

---

## [148] source=multitask_sft_big

**USER:** I need a workflow to evaluate the reliability of my bioinformatics metrics, check clustering stability and classification goodness over various values of k, and pick the optimal k. What would that pipeline look like?

**ASSISTANT:** You can use the 'evaluomer' workflow. It takes a SummarizedExperiment containing an assay (where rows correspond to instances and columns are metric measurements) and executes evaluomer, summarizedexperiment, magrittr, and kableextra tools to analyze correlation, clustering stability, and classification goodness across cluster numbers (k), ultimately outputting 'cluster_assignments' alongside the optimal k.

---

## [149] source=multitask_sft_big

**USER:** I need an analysis pipeline to discover Total RNA Expression Genes (TREGs) by filtering out sparse or low-expression genes and computing rank invariance from my single-nucleus RNA-seq data. What workflow and tools should I use?

**ASSISTANT:** You should use the `treg` workflow. It executes candidate TREG identification by filtering low-expression and sparse genes and calculating rank invariance on a SingleCellExperiment object. The pipeline integrates Bioconductor packages including `bioconductor/treg`, `bioconductor/singlecellexperiment`, `bioconductor/dplyr`, `bioconductor/ggplot2`, `bioconductor/biocstyle`, and `bioconductor/refmanager` to produce an updated `singlecellexperiment` object.

---

## [150] source=multitask_sft_big

**USER:** What are the structural steps and tools invoked inside the Et Full Pipeline (cryo_et domain)?

**ASSISTANT:** The `Et Full Pipeline` consists of 5 sequential stages:
1. Import Tilt Series using `IMPORT_TILTSERIES`
2. Tilt Alignment using `TILT_ALIGNMENT` (supporting AreTomo2 or IMOD, processed in parallel)
3. Tomogram Reconstruction using `TOMOGRAM_RECONSTRUCTION` (supporting WBP or SIRT, processed in parallel)
4. Subtomogram Averaging using `SUBTOMOGRAM_AVERAGING`
5. Pipeline Summary using `ET_PIPELINE_SUMMARY`
The final output is provided in JSON format.

---

## [151] source=multitask_sft_big

**USER:** I have sequenced bacterial isolate genomes with both Illumina short reads and Oxford Nanopore long reads. Can nf-core/bacass handle hybrid assembly and annotation?

**ASSISTANT:** Yes, nf-core/bacass is specifically designed for bacterial assembly and annotation, supporting short reads, long reads, or a mixture of both for hybrid assembly. Executing the pipeline will yield an assembled genome (`fasta_assembly`) and quality control metrics (`multiqc_report`).

---

## [152] source=multitask_sft_big

**USER:** Can you describe the components and tools involved in the gsealm workflow?

**ASSISTANT:** The 'gsealm' transcriptomics workflow incorporates Bioconductor tools including bioconductor/gsealm, bioconductor/all, bioconductor/gostats, bioconductor/rcolorbrewer, bioconductor/rgraphviz, and bioconductor/annotate. It takes an ExpressionSet ('workingEset') and gene-set incidence matrix ('AmatChr3') to output 'enrichment_results' and 'visualizations'.

---

## [153] source=multitask_sft_big

**USER:** I have mapped RNA-seq reads and a GTF annotation file. How can I generate feature-level read count tables for downstream analysis?

**ASSISTANT:** You can route your mapped reads and GTF annotation into `Htseq Count`. It will iterate through the alignments and count how many reads map to each feature defined in your GTF.

---

## [154] source=multitask_sft_big

**USER:** How do I prepare a newly sorted VCF file for random coordinate retrieval using Tabix Bgziptabix?

**ASSISTANT:** To prepare the file, run Tabix Bgziptabix by providing your sorted tab-delimited VCF file as input. The tool will first compress the file with bgzip and then generate the tabix index.

---

## [155] source=multitask_sft_big

**USER:** Can you generate a standard step-by-step workflow using the 'Calculate flux distribution' tool for my metabolic network?

**ASSISTANT:** Here is the workflow using 'Calculate flux distribution':
1. Input a metabolic model formatted in SBML.
2. Set and apply user-specified substrate/metabolite uptake constraints.
3. Run Flux Balance Analysis (FBA) to calculate the optimal steady-state flux distribution.
4. Export the resulting calculated flux distributions to a CSV file.

---

## [156] source=multitask_sft_big

**USER:** I have RDP fixed taxonomy output and Mothur groups/names files for my metagenomic samples and need to generate a taxonomic abundance table, estimate richness, and cluster samples. What workflow should I run and what outputs should I expect?

**ASSISTANT:** You should use the workflow `otubase_taxonomy_based_analysis`. 

Provide your Mothur groups file (`sogin.groups`), names file (`sogin.names`), RDP taxonomy file (`sogin.unique.fix.tax`), sample metadata (`sample_metadata.txt`), and optional FASTA (`sogin.fasta`). The workflow will produce outputs in `table/csv`, `plot/pdf`, and `object/rds` formats.

---

## [157] source=multitask_sft_big

**USER:** I am designing an RNA-seq quantification workflow using RSEM. How should I prepare my GTF annotation to prevent multichromosome coordinate errors?

**ASSISTANT:** Prior to running RSEM, pass your GTF annotation through 'Purge GTF'. This step cleans the annotation by removing genes that span multiple chromosomes, ensuring RSEM can process the feature coordinates without errors.

---

## [158] source=multitask_sft_big

**USER:** How can I set up an annotation preparation workflow to extract gene-level coordinates and flag mitochondrial genes from an Ensembl GTF file?

**ASSISTANT:** You can generate a workflow utilizing GTF2GeneList:
1. Input: Provide your Ensembl GTF annotation file.
2. Configuration: Specify the target feature level (e.g., gene) and enable flagging for mitochondrial features.
3. Execution: Run GTF2GeneList to parse chromosome names, genomic coordinates, and attribute metadata into a structured gene list.

---

## [159] source=multitask_sft_big

**USER:** I am designing a pharmacology workflow to assess novel candidate molecules in cartilage differentiation. How does Biomni: Run 3D Chondrogenic Aggregate Assay fit in?

**ASSISTANT:** You can incorporate `Biomni: Run 3D Chondrogenic Aggregate Assay` at the protocol design phase of your workflow. It generates the step-by-step procedural guidelines required to culture cells in 3D aggregates and apply compound treatments, establishing the experimental foundation before downstream molecular or histological chondrogenesis assays.

---

## [160] source=multitask_sft_big

**USER:** Can you outline the execution steps and final output for extracting core genes using the phyloprofile workflow?

**ASSISTANT:** To extract core genes using `phyloprofile_core_gene_identification`:
1. Load the required input dataset: `processed_profile.RData`.
2. Execute taxon sorting via `sortInputTaxa`.
3. Count supertaxon presence across the selected phylogenetic profile.
4. Call `getCoreGene` to filter and extract genes present across the specified taxa.
5. Output: a list of core gene IDs.

---

## [161] source=multitask_sft_big

**USER:** Can you outline the components and tools involved in the mcbiclust workflow for analyzing gene sets?

**ASSISTANT:** The `mcbiclust` workflow finds and analyzes a single bicluster from an input gene expression matrix (`CCLE_small`) using a specified gene set (`Mitochondrial_genes`). It employs the following tools:
- `bioconductor/mcbiclust`
- `bioconductor/gsva`
- `bioconductor/mass`
- `bioconductor/devtools`
- `bioconductor/dplyr`
- `bioconductor/gprofiler`

The workflow outputs an `expression_matrix` and `enrichment_results`.

---

## [162] source=multitask_sft_big

**USER:** I need a genomics workflow to assess FASTQ files across quality scores, sequence content, overrepresented sequences, and Kmers. What workflow performs this?

**ASSISTANT:** The `qckitfastq` workflow performs this assessment. It takes your FASTQ data via the `input_files` input slot and computes multiple quality metrics, including quality score, sequence content, overrepresented sequences, and K-mer distributions using bioconductor/qckitfastq, seqtools, shortread, and rbenchmark.

---

## [163] source=multitask_sft_big

**USER:** I have two-colour microarray count data and want to run the dyebias workflow. What input slot needs to be defined?

**ASSISTANT:** To execute the `dyebias` workflow, provide your count data to the mandatory input slot `input_files` (type: data).

---

## [164] source=multitask_sft_big

**USER:** Can you summarize the inputs and outputs of the `miaviz_tree_plotting` workflow for my metagenomics pipeline documentation?

**ASSISTANT:** The `miaviz_tree_plotting` workflow is structured as follows:
- **Domain:** Metagenomics
- **Input:** `GlobalPatterns` (format: `rds_se`), a `TreeSummarizedExperiment` object containing a `rowTree` slot.
- **Outputs:** 
  1. `cluster_assignments`
  2. `phylogenetic_tree`
  3. `visualizations`
It visualizes phylogenetic trees decorated with taxonomic, abundance, and prevalence metadata.

---

## [165] source=multitask_sft_big

**USER:** I need an epigenomics pipeline to build an SVM model from positive and negative genomic regions, incorporate transcription factor PSSMs and NGS signal tracks, and score unknown sequences. What workflow is available?

**ASSISTANT:** You can use the 'ledpred_all_in_one_svm_prediction' workflow. It uses the LedPred all-in-one wrapper function to train an SVM model using positive.bed, negative.bed, background.freq, TF.matrices, and ngs.files, and then scores unknown regions provided in prediction_small.bed. It generates outputs in table/csv, plot/pdf, and object/rds formats.

---

## [166] source=multitask_sft_big

**USER:** I need a workflow to identify functional genetic drivers (CNVs) of a cellular phenotype by combining gene expression, copy number alterations, and regulatory networks. What workflow and tools should I use?

**ASSISTANT:** You can use the **diggit** workflow from the transcriptomics domain. It integrates gene expression data, CNV data (tumor and normal matrices), transcriptional regulons (`gbmTFregulon`), and post-translational regulons (`gbmMindy`). Under the hood, it executes `bioconductor/diggit` and `bioconductor/parallel`, producing `copy_number_segments`, a `network_graph`, and relevant `visualizations`.

---

## [167] source=multitask_sft_big

**USER:** How can I set up a step to convert a Cooler matrix into tabular text for custom downstream Python scripting?

**ASSISTANT:** You can add `Cooler Dump` immediately following your cooler file generation or processing step. Route your `.cool` file into `Cooler Dump` to dump the contact records into a plain text stream, which can then be ingested by your downstream text-parsing or Python scripts.

---

## [168] source=multitask_sft_big

**USER:** I need an end-to-end workflow to analyze UMI-4C data between two experimental conditions, identify differential contacts, and visualize the profiles. What workflow is available?

**ASSISTANT:** You should use the `umi4cats` workflow. Utilizing `bioconductor/umi4cats` and `bioconductor/tidyr`, it processes paired-end FASTQ files with bait/UMI sequences, aligns them to a digested reference genome, calls interactions, runs differential tests between conditions, and outputs differential tables (`de_table`) along with visualizations.

---

## [169] source=multitask_sft_big

**USER:** I need to visualize ChIP-seq coverage signals centered around merged peak regions, binned and sorted by peak scores. Can you specify the workflow and required inputs?

**ASSISTANT:** You can use the **epistack** workflow. It takes two primary inputs:
1. `path_peaks`: BED files containing ChIP-seq peaks for replicates.
2. `path_reads`: Aligned ChIP-seq reads and input control in BED, BAM, or BigWig format.

The workflow uses tools such as `bioconductor/epistack`, `bioconductor/enrichedheatmap`, `bioconductor/genomicranges`, `bioconductor/summarizedexperiment`, and `bioconductor/rtracklayer` to produce coverage visualizations centered on merged peaks sorted and binned by peak scores.

---

## [170] source=multitask_sft_big

**USER:** I want to perform a comprehensive isoform switch analysis using IsoformSwitchAnalyzeR with external functional annotations. What inputs should I prepare?

**ASSISTANT:** To execute the `isoformswitchanalyzer` workflow, you should prepare the following input files:
- `salmon_quant_dir`: Directory containing Salmon quantification subdirectories.
- `annotation.gtf`: Transcript structure annotation file.
- `transcript_sequences.fasta`: Isoform nucleotide FASTA sequences.
- `cpc2_result.txt`: Coding potential assessment from CPC2.
- `pfam_results.txt`: Protein domain predictions from Pfam.
- `iupred2a_result.txt.gz`: Disordered region predictions from IUPred2A.
- `signalP_results.txt`: Signal peptide predictions from SignalP.

The workflow uses high-level wrapper functions from `bioconductor/isoformswitchanalyzer` and `bioconductor/venndiagram` to integrate these predictions and output switch analysis visualizations.

---

## [171] source=multitask_sft_big

**USER:** I have finished running MAGeCK RRA on my CRISPR screen and obtained gene and sgRNA summary tables. Which workflow can I run for quality control, visualization, and pathway enrichment, and what tools does it use?

**ASSISTANT:** You can use the `mageckflute` workflow. It processes `gene_summary.txt` and `sgrna_summary.txt` to generate quality control visualizations and functional enrichment results. The underlying pipeline utilizes `bioconductor/mageckflute`, `bioconductor/clusterprofiler`, `bioconductor/enrichplot`, and `bioconductor/ggplot2`.

---

## [172] source=multitask_sft_big

**USER:** I have an RDS file containing a preprocessed CNSet object generated with crlmm. How can I perform wave correction and HMM-based CNV segmentation?

**ASSISTANT:** You can run the workflow `vanillaice_cnv_calling_from_crlmm_cnset`. It takes your `cnSetExample` (a required `.rds` input containing the preprocessed CNSet with copy number and B allele frequency data), coerces it into a `SnpArrayExperiment`, applies genomic wave correction, fits the Hidden Markov Model (HMM), and outputs the resulting `copy_number_segments`.

---

## [173] source=multitask_sft_big

**USER:** Can you configure the miaviz workflow to process my taxonomic counts and generate prevalence visualizations?

**ASSISTANT:** Here is the workflow setup for miaviz:
- Domain: Metagenomics
- Input: `GlobalPatterns` (TreeSummarizedExperiment RDS containing taxonomic counts)
- Core Tools: `bioconductor/miaviz`, `bioconductor/mia`, `bioconductor/scater`, `bioconductor/miatime`, `bioconductor/dplyr`
- Outputs: `visualizations` (taxonomic abundance plotted by rank and subset by prevalence combined with metadata), `cluster_assignments`, and `phylogenetic_tree`.

---

## [174] source=multitask_sft_big

**USER:** I am setting up a structural multiple sequence alignment pipeline using Foldmason. What is the initial database preparation step?

**ASSISTANT:** The first step is to generate the required database using 'Foldmason Createdb', which formats and indexes your input structural data for downstream Foldmason alignment workflows.

---

## [175] source=multitask_sft_big

**USER:** Can you give me a simple step-by-step workflow to inspect read depth across samples starting from post-alignment BAM files using Fastcov?

**ASSISTANT:** 1. **Input Preparation**: Ensure your aligned reads are in sorted and indexed BAM format.
2. **Coverage Generation**: Run `Fastcov`, passing your one or more BAM files as input to compute coverage across the target regions.
3. **Visualization**: Inspect the resulting coverage plot output generated by Fastcov to evaluate depth of coverage across your samples.

---

## [176] source=multitask_sft_big

**USER:** Can you summarize the inputs, parameters, and tools used by the seq_hotspot workflow?

**ASSISTANT:** The `seq_hotspot` workflow uses the tool `bioconductor/seq_hotspot`. It accepts mandatory `count_data` through the `input_files` input channel, has no additional configurable parameter slots, and generates sequencing panel design outputs to assist with mutation detection.

---

## [177] source=multitask_sft_big

**USER:** I have hyperstack microscopy images hosted on OMERO and an ilastik segmentation project. I want to detect gastruloids and quantify their elongation. How should I set up this workflow?

**ASSISTANT:** You can configure the 'Omero hyperstack to Gastruloid measurements' tool to execute this workflow:
1. Connect the tool to your OMERO instance to fetch the hyperstack images.
2. Provide your ilastik project file to generate probability maps and create masks.
3. The tool will run Analyze Particles to locate gastruloids.
4. It will automatically compute and report the elongation index for each segmented gastruloid ROI.

---

## [178] source=multitask_sft_big

**USER:** I need a proteomics workflow to assign custom quality control metrics to tabular data and generate visual QC reports. What workflow is available?

**ASSISTANT:** You can use the 'qcmetrics' proteomics workflow. It accepts 'user_data.csv' (any tabular or numeric data to be evaluated) and produces QC 'visualizations'. It utilizes Bioconductor tools including 'bioconductor/qcmetrics', 'bioconductor/msnbase', 'bioconductor/rforproteomics', 'bioconductor/ggplot2', and 'bioconductor/mzr'.

---

## [179] source=multitask_sft_big

**USER:** Can you outline the tools utilized by the fastseg workflow and what outputs it produces?

**ASSISTANT:** The `fastseg` workflow uses the following Bioconductor packages:
- `bioconductor/fastseg`
- `bioconductor/dnacopy`
- `bioconductor/genomicranges`
- `bioconductor/oligo`

It generates two outputs:
1. `copy_number_segments`: The identified genomic copy number segment calls.
2. `visualizations`: Plots showing the segmented genomic data.

---

## [180] source=multitask_sft_big

**USER:** Can you configure a workflow execution plan to parse transcript abundance tables from StringTie and generate a differential expression table?

**ASSISTANT:** You can configure the `tximport_stringtie_import` workflow as follows:

- **Workflow**: `tximport_stringtie_import`
- **Domain**: Transcriptomics
- **Input Data**: StringTie transcript abundance files (`t_data.ctab` / `input_files`)
- **Output Data**: `de_table`

This workflow reads the transcript coverage and abundance estimates directly from the specified `t_data.ctab` files to construct the differential expression table.

---

## [181] source=multitask_sft_big

**USER:** I want to analyze transcript isoform diversity between conditions from transcriptomics data. Which tools comprise the splicingfactory workflow?

**ASSISTANT:** To execute the splicingfactory workflow, use bioconductor/splicingfactory, bioconductor/tidyr, and bioconductor/ggplot2. Given transcript_expression.tsv, gene_vector.tsv, and sample_metadata.tsv, this pipeline computes Laplace entropy and Gini index values to identify diversity shifts, outputting a SummarizedExperiment and visualizations.

---

## [182] source=multitask_sft_big

**USER:** Can you provide the tool stack and generated output formats for the mosaics peak-calling pipeline?

**ASSISTANT:** The 'mosaics' workflow uses Bioconductor packages 'bioconductor/mosaics' and 'bioconductor/mosaicsexample'. When executed on ChIP and control BAM files, it generates peak results in tabular format ('table/csv'), diagnostic or visualization plots ('plot/pdf'), and serialized R objects ('object/rds').

---

## [183] source=multitask_sft_big

**USER:** I have radiation dose values in Gy and corresponding cell viability measurements. Which workflow can fit dose-response models and what files must I provide?

**ASSISTANT:** You can use the 'radiogx' genomics workflow. It requires two non-optional input files: 'radiation_doses.csv' (containing radiation dose values in Gy) and 'survival_fractions.csv' (containing cell viability/survival fraction measurements). It will fit linear-quadratic models, compute radio-sensitivity metrics (SF2, D10, AUC), and generate dose-response visualizations and copy number segments.

---

## [184] source=multitask_sft_big

**USER:** Which tools are chained inside nf-core/vcf_extract_relate_somalier to calculate relatedness metrics from VCFs?

**ASSISTANT:** The `nf-core/vcf_extract_relate_somalier` workflow utilizes the following tools:
1. `tabix/tabix` (indexing VCF files)
2. `somalier/extract` (extracting genotype information at specific sites)
3. `somalier_relate` (computing relatedness statistics across samples)

---

## [185] source=multitask_sft_big

**USER:** How does the gdr workflow process pharmacological drug response data, and what outputs does it generate?

**ASSISTANT:** The gdr workflow processes drug response data by manually aggregating, normalizing, averaging, and fitting the data step-by-step using tools from 'bioconductor/gdr' and 'bioconductor/kableextra'. This maintains granular control over intermediate objects and produces two primary outputs: 'summarizedexperiment' and 'normalized_data'.

---

## [186] source=multitask_sft_big

**USER:** I need to remove human contamination (taxid 9606) from a paired-end FASTQ dataset using kraken_filter. How should I structure the command?

**ASSISTANT:** You can structure the command using the Trim contaminated reads tool syntax:
```bash
kraken_filter [--p] <ETE3 taxonomy database> <kraken report> 9606 <fastq> <fastq_reverse>
```
Replace `<ETE3 taxonomy database>`, `<kraken report>`, `<fastq>`, and `<fastq_reverse>` with your respective database path, Kraken report file, and input forward/reverse FASTQ files.

---

## [187] source=multitask_sft_big

**USER:** What are the inputs and outputs generated by the scbn workflow?

**ASSISTANT:** The `scbn` workflow takes `orthologous_genes_data.csv` (a table containing gene lengths and read counts across two species) as input and outputs two files: `de_table` (differentially expressed orthologs) and `normalized_data`.

---

## [188] source=multitask_sft_big

**USER:** Can you summarize the end-to-end data processing stages carried out by the protgear proteomics workflow?

**ASSISTANT:** The **protgear** workflow carries out raw protein microarray data pre-processing through the following sequential steps:
1. Background correction of raw intensity files (.gpr/.txt),
2. Replicate coefficient of variation (CV) filtering,
3. Tag subtraction (utilizing antigen tag specifications if provided),
4. Normalization across samples.

It generates tabular files (.csv), plots (.pdf), R objects (.rds), and output files.

---

## [189] source=multitask_sft_big

**USER:** I want to detect aberrantly spliced genes in tumor tissue compared to normal tissue using public TCGA data. How can I carry this out with OutSplice?

**ASSISTANT:** You can carry this out using the following workflow with **OutSplice**:
1. **Input Data**: Supply RNA-seq splicing data directly from The Cancer Genome Atlas (TCGA), or provide your own user-generated matrix comparing tumor and normal tissue samples.
2. **Execution**: Run OutSplice to evaluate splicing events between the normal and tumor cohorts.
3. **Result**: OutSplice outputs a matrix of splicing outliers indicating splicing events that are significantly over- or under-represented in tumor samples.

---

## [190] source=multitask_sft_big

**USER:** I have raw metagenomic FASTA reads that need pre-filtering before assembly. Where does 'Filter fasta' fit into this workflow?

**ASSISTANT:** In a metagenomic assembly workflow, `Filter fasta` serves as an early quality-control/filtering step: raw FASTA/FASTQ reads are passed to `Filter fasta` to discard sequences meeting removal criteria (e.g., unwanted lengths or sequences), and the resulting filtered FASTA/FASTQ is then passed downstream to assembly or taxonomic profiling tools.

---

## [191] source=multitask_sft_big

**USER:** I am designing a sequence analysis intake workflow and need a component to systematically discover accessions across SRA and ENA. Where does pysradb search fit?

**ASSISTANT:** You should place `pysradb search` at the start of your sequence analysis workflow. It takes your query criteria, searches SRA and ENA, and outputs the retrieved metadata and run accession numbers to feed downstream sequence acquisition tools.

---

## [192] source=multitask_sft_big

**USER:** What specific outputs will be generated when I run the `reactomepa` pipeline on my gene list?

**ASSISTANT:** The `reactomepa` pipeline generates three main outputs:
1. `enrichment_results`: The statistical results of the Reactome pathway over-representation analysis.
2. `de_table`: The differential expression/gene table associated with the analysis.
3. `visualizations`: Visual representations and plots illustrating the enriched Reactome pathways.

---

## [193] source=multitask_sft_big

**USER:** I need to process peptide array data in proteomics to reduce noise across adjacent probes. Which workflow handles this, and what outputs does it yield?

**ASSISTANT:** Use the `heron_smoothed_probe_level_analysis` workflow. It reduces high variability in peptide array data by smoothing signal across consecutive probes prior to p-value calculation and calling. It outputs results across three formats: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [194] source=multitask_sft_big

**USER:** I have raw LC-MS expression data and an experimental design file. I need to benchmark several normalization methods and obtain performance plots. Which workflow should I run?

**ASSISTANT:** You can run the `normalyzerde` workflow. It executes `bioconductor/normalyzerde` on your raw expression matrix (`tiny_data.tsv`) and design file (`tiny_design.tsv`) to evaluate multiple normalization methods, generate performance comparison plots, and output the `normalized_data`.

---

## [195] source=multitask_sft_big

**USER:** Can you describe the internal stages and tools used by the Schrodinger Glide Docking pipeline for virtual screening?

**ASSISTANT:** The Schrodinger Glide Docking pipeline consists of the following sequential steps:
1. LigPrep (ligprep): Prepares ligands by adjusting protonation states (optionally with Epik), generating tautomers, and defining stereochemistry.
2. Protein Preparation Wizard (prepwizard): Optimizes the receptor through hydrogen-bond network assignment and restrained minimization.
3. Grid Generation: Defines the active site search space using specified grid center, inner box, outer box, and van der Waals scaling parameters.
4. Glide Docking (glide): Performs flexible docking at the selected precision (HTVS, SP, or XP) and scores poses using GlideScore and E_model, outputting results in formats such as maegz, sdf, csv, json, zip, and html.

---

## [196] source=multitask_sft_big

**USER:** How do I incorporate QC report into a quality control pipeline for a comparative metagenomics sequencing project?

**ASSISTANT:** You can feed your generated metagenomic count tables across samples directly into the QC report tool. The tool will process the input count tables and output a unified summary table describing differences in sequence counts to verify sequencing depth consistency across samples.

---

## [197] source=multitask_sft_big

**USER:** How does the twoddpcr pipeline process raw droplet amplitude data and what tools does it chain together?

**ASSISTANT:** The twoddpcr workflow carries out the following steps:
1. Loads raw droplet amplitude data from QuantaSoft export CSVs.
2. Classifies droplets using k-means clustering.
3. Applies Mahalanobis distance-based rain filtering.
4. Generates a Poisson concentration summary and outputs cluster assignments.

It utilizes the tools `bioconductor/twoddpcr`, `bioconductor/ggplot2`, and `bioconductor/reshape2`.

---

## [198] source=multitask_sft_big

**USER:** Can you design a transcriptomics pipeline to assess whether my RNA-seq BAM files contain genomic DNA contamination?

**ASSISTANT:** You can use the `gdnax` workflow (leveraging `bioconductor/gdnax` and `bioconductor/gdnainrnaseqdata`):
1. Provide RNA-seq alignments via `bamfiles` (character vector of paths to BAM files).
2. Provide transcript annotations via `txdb` (TxDb annotation object or package name).
3. Execute the workflow to diagnose gDNA contamination and filter out potential gDNA-origin reads, yielding output diagnostic visualizations.

---

## [199] source=multitask_sft_big

**USER:** I have strand-specific paired-end RNA-seq alignment files (such as SZP.bam and TLC.bam) and an existing gene annotation GTF file (in.gtf). I want to predict intergenic transcript models. How can I set this up?

**ASSISTANT:** You can use the `pram` workflow (`bioconductor/pram`). It runs the wrapper function `runPRAM`, taking `in.gtf` (GTF file of existing gene annotations) and strand-specific paired-end alignment BAM files (like `SZP.bam` and `TLC.bam`) to generate `annotated_genes` containing predicted intergenic transcript models.

---

## [200] source=multitask_sft_big

**USER:** I need an automated workflow to process raw LC/MS CDF files through to metabolite identification. What does the mait workflow offer?

**ASSISTANT:** The mait workflow executes an end-to-end analysis using the bioconductor/mait and bioconductor/faahko tools. It takes class-organized raw LC/MS directories (such as CDF files via cdfFiles) and generates output tables (CSV), visualization plots (PDF), and R data objects (RDS).

---

## [201] source=multitask_sft_big

**USER:** Please outline the analysis steps and underlying tools utilized by the metagenomeseq workflow.

**ASSISTANT:** The `metagenomeseq` workflow processes your marker-gene/metagenomic count data through the following steps:
1. **Data Import**: Load the OTU count matrix, taxonomy mapping, and sample clinical metadata using `bioconductor/biomformat` and `bioconductor/metagenomeseq`.
2. **Normalization**: Apply normalization algorithms such as Cumulative Sum Scaling (CSS) or Wrench.
3. **Differential Abundance Testing**: Fit zero-inflated models (supported by `bioconductor/gss`) to test for differentially abundant features.
4. **Interactive Exploration & Reporting**: Utilize `bioconductor/interactivedisplay` to output `normalized_data`, `differential_abundance`, and the final `de_table`.

---

## [202] source=multitask_sft_big

**USER:** I am working in transcriptomics and want an automated way to generate ComplexHeatmap visualizations directly using rowData and colData annotations from my SummarizedExperiment count matrices. Which workflow should I use?

**ASSISTANT:** You can deploy the `sechm` transcriptomics workflow. It takes your count data via `input_files`, links `SummarizedExperiment` containers to `ComplexHeatmap`, and leverages `rowData` and `colData` annotations for heatmap rendering.

---

## [203] source=multitask_sft_big

**USER:** I am designing a synthetic biology workflow and need a step that turns a biochemical network into an SBML mathematical representation. How should I configure this step?

**ASSISTANT:** Include 'Biomni: Create Biochemical Network Sbml Model' in your synthetic biology workflow to take your biochemical network specifications and generate the corresponding SBML mathematical model.

---

## [204] source=multitask_sft_big

**USER:** Generate a workflow call for Lnp Formulation Optimization where I want to deliver siRNA to the liver using MC3-like lipid 'CCC(CC)CCN(C)C' and helper lipid 'CCCCCCCCCCCCCCCC(=O)O' without running a ratio sweep.

**ASSISTANT:** Here is the workflow execution configuration:

```json
{
  "workflow": "drug_discovery/lnp_formulation_optimization",
  "inputs": {
    "ionizable_lipid_SMILES": "CCC(CC)CCN(C)C",
    "helper_lipid_SMILES": "CCCCCCCCCCCCCCCC(=O)O",
    "cargo_type": "siRNA",
    "target_tissue": "liver",
    "run_ratio_sweep": false
  }
}
```
This initiates `LNP_FORMULATION_OPTIMIZATION` to calculate ionizable lipid pKa, the endosomal escape score via Henderson-Hasselbalch, and tissue targeting predictions.

---

## [205] source=multitask_sft_big

**USER:** Can you provide the input-output specification for configuring the methylimp2 workflow in my pipeline?

**ASSISTANT:** Here is the specification for `methylimp2`:
- **Domain:** Epigenomics
- **Tool:** `bioconductor/methylimp2`
- **Required Input:** `beta_SE` (RDS file containing a SummarizedExperiment of DNA methylation beta values with missing values)
- **Outputs Generated:** `table/csv`, `plot/pdf`, and `object/rds`

---

## [206] source=multitask_sft_big

**USER:** What are the inputs and outputs of the genestructuretools_leafcutter_analysis workflow?

**ASSISTANT:** For `genestructuretools_leafcutter_analysis`:
- **Inputs:** `per_intron_results.tab` (Leafcutter intron results table), `example_gtf.gtf` (GTF annotation file), and `BSgenome.Mmusculus.UCSC.mm10` (BSgenome package/object).
- **Outputs:** `visualizations`.

---

## [207] source=multitask_sft_big

**USER:** I am building a custom Kraken2 taxonomic database from a set of novel bacterial genome FASTA files. Where does 'Kraken2 Add' fit into the pipeline?

**ASSISTANT:** In a custom Kraken2 database workflow:
1. Initialize or specify the database directory structure.
2. Use 'Kraken2 Add' to incorporate your FASTA sequence files into the target Kraken2 database library.
3. Run the Kraken2 build step to construct the taxonomy and k-mer index for downstream metagenomic classification.

---

## [208] source=multitask_sft_big

**USER:** How can I integrate ggtreeSpace into a phylogenetic comparative analysis pipeline in R?

**ASSISTANT:** You can integrate ggtreeSpace by taking your reconstructed phylogenetic tree alongside continuous trait data, computing or structuring the morphospace coordinates, and then employing ggtreeSpace to generate the phylomorphospace plot while leveraging its grammar-of-graphics layering to add custom annotations and graphical elements.

---

## [209] source=multitask_sft_big

**USER:** Write a Nextflow run command for nf-core/isoseq using an input samplesheet, reference GTF, primers file, and specified output directory.

**ASSISTANT:** You can launch the nf-core/isoseq pipeline using the following command:

```bash
nextflow run nf-core/isoseq \
    --input samplesheet.csv \
    --outdir results_dir \
    --gtf annotation.gtf \
    --primers primers.fasta
```

---

## [210] source=multitask_sft_big

**USER:** Can you outline the recommended workflow when using the CLC assembler for de novo genome assembly from short reads?

**ASSISTANT:** A standard workflow begins by running the 'CLC assembler' tool on your short reads, which generates a FASTA assembly output file. Following this, you typically map the original set of reads back onto this generated FASTA assembly using 'cls_mapper' to perform downstream analyses on the mapped reads.

---

## [211] source=multitask_sft_big

**USER:** Can you define the workflow structure for epiregulon to infer transcription factor activity from paired scRNA-seq and scATAC-seq data?

**ASSISTANT:** The `epiregulon` workflow is defined as follows:
- **Domain**: Transcriptomics
- **Objective**: Construct gene regulatory networks and infer single-cell transcription factor activity by integrating scRNA-seq and scATAC-seq data.
- **Inputs**:
  - `PeakMatrix` (SingleCellExperiment of chromatin accessibility peak matrix)
  - `GeneExpressionMatrix` (SingleCellExperiment of gene expression matrix)
  - `reducedDimMatrix` (Dimensionality reduction matrix from scATAC-seq or joint profiling)
- **Underlying Tool**: `bioconductor/epiregulon`
- **Output**: `network_graph`

---

## [212] source=multitask_sft_big

**USER:** How can I set up an interactive track-based genomic visualization workflow in R?

**ASSISTANT:** You can deploy the TnT workflow. It wraps `bioconductor/tnt` to interface with the TnT JavaScript library, enabling flexible and interactive track-based genomic data visualizations.

---

## [213] source=multitask_sft_big

**USER:** I want to infer a consensus metabolic network topology combining structural transformations, retention times, spectral similarity, and statistical associations. Which workflow and inputs should I prepare?

**ASSISTANT:** You should run the 'metnet' workflow. You must provide 'user_features.csv' (a matrix of m/z, retention time, and intensity values across samples) and 'user_transformations.csv' (a data frame of biochemical transformations with mass, formula, group, and expected rt shift). Optionally, you can also provide 'user_ms2_similarity.rds' (a spectral similarity matrix).

---

## [214] source=multitask_sft_big

**USER:** I have multiple lane-level BAM files for a patient and need to prepare a single BAM file for downstream QC with Samtools Flagstat. What is the workflow?

**ASSISTANT:** The workflow is:
1. Run Picard Mergesamfiles on the individual lane-level BAM files to merge them into a single combined BAM file.
2. Run Samtools Flagstat on the resulting merged BAM file to compute alignment counts across FLAG types.

---

## [215] source=multitask_sft_big

**USER:** Please specify the inputs, tools, and outputs for the `teqc` workflow.

**ASSISTANT:** For the `teqc` workflow:
- **Inputs:** `ExampleSet_Targets.bed` (genomic targets BED file) and `ExampleSet_Reads.bed` (aligned reads BED or BAM file)
- **Tool:** `bioconductor/teqc`
- **Output:** `qc_report` (single-sample and multi-sample HTML quality control reports)

---

## [216] source=multitask_sft_big

**USER:** Can you configure a workflow to estimate essential genes and predict future knockout yields from transposon mutagenesis data?

**ASSISTANT:** You can use the `occugene` workflow (domain: genomics). It utilizes the `bioconductor/occugene` tool and requires two input files:
1. `annotation.csv`: a table containing ORF start and end coordinates.
2. `insertions.csv`: a table containing genomic positions of transposon insertions.

The workflow outputs results in `table/csv`, `plot/pdf`, and `object/rds` formats.

---

## [217] source=multitask_sft_big

**USER:** I have normalized signal intensity data for transcriptome and translatome levels. How can I identify DEGs at both levels and compare their enriched biological themes?

**ASSISTANT:** You can run the 'translatome' workflow. It takes an `expressionMatrix` (normalized signal intensity matrix with genes in rows and samples in columns), uses `bioconductor/translatome` to identify differentially expressed genes across both transcriptome and translatome levels, carries out GO enrichment on the DEGs, and outputs `de_table` and `enrichment_results`.

---

## [218] source=multitask_sft_big

**USER:** I need to visualize alignment coverage across a specific contig from my targeted exome sequencing experiment. How do I construct this workflow with BAM Coverage Plotter?

**ASSISTANT:** To visualize alignment coverage with BAM Coverage Plotter (WGSCoveragePlotter):
1. Provide your alignment file (BAM) from the targeted sequencing run.
2. Provide the reference sequence for the target genomic contig in FASTA format.
3. Run WGSCoveragePlotter specifying your preferred output format (PNG or SVG) to generate the coverage depth plot across the specified contig.

---

## [219] source=multitask_sft_big

**USER:** How do I configure the crisprscore_cas13d_on_target_scoring workflow to evaluate Cas13d guide efficiencies against a target transcript set?

**ASSISTANT:** To configure the `crisprscore_cas13d_on_target_scoring` workflow:
1. Specify the domain as transcriptomics.
2. Provide the input FASTA file under `data_inputs` with `name: transcripts.fasta` containing the mRNA sequences targeted by your gRNAs.
3. Run the workflow to invoke the R-based Cas13d on-target scoring methods.

---

## [220] source=multitask_sft_big

**USER:** I have paired tumor and normal mRNA expression matrices (exprTumIsof.csv and exprNmlIsof.csv). I want to identify and visualize oncogene candidates using Gaussian mixture models. How can I structure this workflow?

**ASSISTANT:** You can deploy the 'oncomix' transcriptomics workflow:
- **Inputs**: `exprNmlIsof.csv` (adjacent normal mRNA expression matrix) and `exprTumIsof.csv` (tumor mRNA expression matrix).
- **Underlying Tools**: `bioconductor/oncomix`, `bioconductor/rcolorbrewer`, `bioconductor/rmysql`, and `bioconductor/ggplot2`.
- **Method**: Fits 2-component Gaussian mixture models to tumor-normal expression.
- **Output**: Gene candidate visualizations.

---

## [221] source=multitask_sft_big

**USER:** I need to prepare a reference genome for DRAGEN alignment. What step do I need to run first?

**ASSISTANT:** You need to run the Dragmap Hashtable tool to generate the DRAGEN hashtable index from your reference genome FASTA file before proceeding with alignment.

---

## [222] source=multitask_sft_big

**USER:** Could you provide an overview of the `rcm` metagenomics workflow, including its underlying tools, execution goals, and outputs?

**ASSISTANT:** The `rcm` workflow performs exploratory unconstrained ordination of microbiome read count data, visualizes samples and taxa, assesses goodness of fit, and evaluates cluster significance.

- **Tools utilized**: `bioconductor/rcm`, `bioconductor/biocmanager`, and `bioconductor/phyloseq`
- **Required input**: `Zeller` (an `.rds` phyloseq object with microbiome read counts and metadata)
- **Generated outputs**: `cluster_assignments` and `visualizations`

---

## [223] source=multitask_sft_big

**USER:** Can you outline the workflow steps for tvtb using my VCF and sample phenotype files?

**ASSISTANT:** The `tvtb` workflow consists of the following steps:
1. Import the VCF data (`chr15.phase3_integrated.vcf.gz`) and sample phenotypes (`integrated_samples.txt`).
2. Calculate overall and phenotype-level allele frequencies.
3. Apply multi-slot filter rules using `bioconductor/tvtb`.
4. Generate and compile visualizations using `bioconductor/knitr`.

---

## [224] source=multitask_sft_big

**USER:** How can I set up a genome annotation workflow to visualize genomic feature density across chromosomes using Calculate Density?

**ASSISTANT:** You can structure the workflow as follows:
1. Prepare your input feature file in BED or GFF format.
2. Run the 'Calculate Density' tool, defining your desired window size to calculate coverage density across the genome.
3. Collect the resulting BigWig file for downstream visualization in a genome browser.

---

## [225] source=multitask_sft_big

**USER:** I have a FASTA file of DNA sequences and a transcription factor position frequency matrix. I need a workflow to estimate a background model, normalize the motif, and test for motif enrichment. What does the motifcounter workflow entail?

**ASSISTANT:** The motifcounter workflow accomplishes this through the following components:
- Inputs: `seq.fasta` (DNA sequences of interest in FASTA format) and `motif` (a position frequency matrix representing transcription factor binding affinity).
- Execution tools: `bioconductor/motifcounter`, `bioconductor/motifdb`, `bioconductor/knitr`, and `bioconductor/seqlogo`.
- Tasks: Estimates a background model, normalizes the motif, identifies individual and average motif hits/scores, and tests for motif enrichment.
- Output: `normalized_data`.

---

## [226] source=multitask_sft_big

**USER:** I need an end-to-end sample quality control pipeline in genomics that runs in a single step and produces reports. What workflow and tool should I run, and what will it output?

**ASSISTANT:** You can run the 'seqsqc' workflow, which utilizes the bioconductor/seqsqc tool to execute the entire sample QC pipeline in a single step. It takes a genotype VCF, sample annotation file, and capture region BED file, and produces outputs in table/csv, plot/pdf, and object/rds formats.

---

## [227] source=multitask_sft_big

**USER:** I have HiCUP-filtered BAM files and need a pipeline to call significant chromatin interactions. What workflow can I use?

**ASSISTANT:** You can use the `gothic_hicup_gothic_pipeline`. It uses GOTHiChicup to identify significant genomic interactions from HiCUP preprocessed and filtered BAM/SAM files.

---

## [228] source=multitask_sft_big

**USER:** I want to perform differential expression on my RNA-seq raw counts using DESeq2 combined with HTSFilter, while turning off DESeq2's native independent filtering. Which pipeline should I use, and what outputs will it produce?

**ASSISTANT:** You should use the `htsfilter_deseq2_pipeline`. It filters your DESeqDataSet using HTSFilter within the DESeq2 framework with DESeq2 independent filtering disabled. It takes `counts_matrix.csv` and `sample_metadata.csv` as inputs, and produces `de_table` (differential expression results table) and `counts_matrix` as outputs.

---

## [229] source=multitask_sft_big

**USER:** I have transcriptomics reads and a reference fasta file. How can I align them with HISAT2 and obtain sorted BAM files with quality metrics?

**ASSISTANT:** You can use the 'Fastq Align Hisat2' workflow. It takes 'reads' and 'fasta' as inputs, aligns the reads using hisat2/align, and processes/sorts them using samtools tools (bam_sort_stats_samtools, samtools/stats, samtools/idxstats, samtools/flagstat).

---

## [230] source=multitask_sft_big

**USER:** What outputs and Bioconductor tools are involved when executing the regionreport workflow?

**ASSISTANT:** The 'regionreport' workflow outputs differential expression tables ('de_table') and exploratory plots ('visualizations'). Under the hood, it utilizes Bioconductor packages including `bioconductor/regionreport`, `bioconductor/genomicranges`, `bioconductor/refmanager`, `bioconductor/bumphunter`, `bioconductor/derfinder`, and `bioconductor/sessioninfo`.

---

## [231] source=multitask_sft_big

**USER:** Which R/Bioconductor packages are integrated into the geomxtools workflow to process and coerce GeoMx RNA data into single-cell/spatial structures?

**ASSISTANT:** The `geomxtools` workflow utilizes the following tools and packages: `bioconductor/geomxtools`, `bioconductor/envstats`, `bioconductor/nanostringnctools`, `bioconductor/seurat`, `bioconductor/spatialdecon`, and `bioconductor/spatialexperiment` to read, QC, normalize, and coerce GeoMx data into Seurat or SpatialExperiment objects.

---

## [232] source=multitask_sft_big

**USER:** What is the prerequisite workflow to prepare count inputs for running DEXSeq on a multi-factor RNA-Seq study comparing differential exon usage?

**ASSISTANT:** To prepare data for DEXSeq:
1. Process your RNA-Seq reads through `dexseq_count` separately for each individual sample to generate individual exon count tables.
2. Supply these sample-level count tables to DEXSeq.
3. Formulate your design model specifying your variables, ensuring the primary condition of interest is supplied as the first factor.

---

## [233] source=multitask_sft_big

**USER:** How can I run supervised classification on transcriptomic expression data with cross-validation and embedded feature selection to avoid selection bias?

**ASSISTANT:** You can use the `mlinterfaces` workflow in the transcriptomics domain. 
- Input: `fus` (an ExpressionSet containing gene expression data and phenotype labels)
- Underlying tools: `bioconductor/mlinterfaces`, `bioconductor/all`, `bioconductor/mass`, `bioconductor/cluster`, `bioconductor/keggorthology`, and `bioconductor/lattice`
- Output: `feature_selection`
This executes supervised classification with internal cross-validation and embedded feature selection to mitigate selection bias.

---

## [234] source=multitask_sft_big

**USER:** I have genomic signal data in bedgraph format and need an automated workflow to clip chromosome boundaries and convert it to bigwig. Which workflow can I run?

**ASSISTANT:** You can use the 'Bedgraph Bedclip Bedgraphtobigwig' workflow. It takes an input bedgraph file, processes it through 'ucsc/bedclip' to ensure coordinates stay within chromosome boundaries, and converts it to bigwig using 'ucsc/bedgraphtobigwig'. Its outputs include bigwig, bedgraph, versions, and yml files.

---

## [235] source=multitask_sft_big

**USER:** What outputs and Bioconductor tools are involved in running the microstasis workflow?

**ASSISTANT:** The microstasis workflow produces cluster_assignments and visualizations. It integrates the following Bioconductor/R packages: bioconductor/microstasis, bioconductor/treesummarizedexperiment, bioconductor/refmanager, bioconductor/rmarkdown, bioconductor/knitr, and bioconductor/sessioninfo.

---

## [236] source=multitask_sft_big

**USER:** I have single-cell flow cytometry experiments with multiple markers. I need to apply data transformation, automatically remove debris, and export to text. How should I set this up?

**ASSISTANT:** You can use the 'Transform FCS data' tool from Flow Cytometry Analysis. It provides data transformation options, optional automated debris gating using flowDensity, and conversion of FCS files to text format.

---

## [237] source=multitask_sft_big

**USER:** I want to estimate sample size and statistical power for a planned RNA-seq experiment using hypothesized read counts and dispersion parameters. How does the rnaseqsamplesize workflow execute this?

**ASSISTANT:** The 'rnaseqsamplesize' workflow in domain transcriptomics executes power and sample size estimation without physical files by taking your user-defined numeric values for average read count and dispersion. Leveraging `bioconductor/rnaseqsamplesize` (along with reference integration via `bioconductor/expressionatlas` and `bioconductor/recount`), it calculates the required sample size and produces summary tables (`table/csv`), power curves (`plot/pdf`), and R data objects (`object/rds`).

---

## [238] source=multitask_sft_big

**USER:** Which Bioconductor packages and tools comprise the msgbsR workflow?

**ASSISTANT:** The msgbsR workflow comprises three primary Bioconductor components: bioconductor/msgbsr, bioconductor/genomicranges, and bioconductor/summarizedexperiment.

---

## [239] source=multitask_sft_big

**USER:** What output file types should I expect when completing the dexseq_python_htseq_workflow?

**ASSISTANT:** The workflow produces three types of outputs: tabular results (`table/csv`), visualization plots (`plot/pdf`), and serialized R objects (`object/rds`).

---

## [240] source=multitask_sft_big

**USER:** I am designing a SARS-CoV-2 selection analysis pipeline and need a tool to aggregate my HyPhy results with sample metadata into a final summary. Which tool should I configure for this step?

**ASSISTANT:** You should include 'sarscov2summary' (Sequence Analysis) as the summary step. It is a custom summary script specifically built for the SARS-CoV-2 Selection Analysis workflow to synthesize HyPhy outputs and metadata.

---

## [241] source=multitask_sft_big

**USER:** How can I predict drug combination transcriptional synergy using CPA-inspired models across two compounds?

**ASSISTANT:** You can execute the workflow `virtual_cell/cpa_drug_combination_synergy`. It utilizes the tool `CPA_DRUG_COMBINATION_SYNERGY` based on the Compositional Perturbation Autoencoder framework (Lotfollahi et al. 2023). It queries drug targets from curated databases like DrugBank/ChEMBL and requires input parameters including `drug_a_name`, `drug_a_targets`, `drug_a_cmax_nM`, `drug_b_name`, `drug_b_targets`, `drug_b_cmax_nM`, `cell_line`, `synergy_model`, `dose_ratio_a`, and `dose_ratio_b`.

---

## [242] source=multitask_sft_big

**USER:** I want to perform multi-omics integration of gene expression with CNV, methylation, and miRNA matrices in transcriptomics. What workflow and tools support this?

**ASSISTANT:** You can use the `gintomics` workflow. It integrates gene or miRNA expression data with genomic modifications (CNV or methylation) or transcriptional regulators (TF or miRNA) using individual matrices (`gene_exp_matrix.csv`, `cnv_matrix.csv`, `meth_matrix.csv`, and `miRNA_exp_matrix.csv`). It utilizes Bioconductor tools including `bioconductor/gintomics`, `bioconductor/multiassayexperiment`, and `bioconductor/shiny` to generate copy number segments and interactive visualizations.

---

## [243] source=multitask_sft_big

**USER:** I have matched miRNA and mRNA transcriptomic profiles along with a set of known validated target interactions. How can I predict and validate target interactions?

**ASSISTANT:** You can deploy the mirlab workflow in transcriptomics. It utilizes bioconductor/mirlab to integrate your matched miRNA and mRNA expression data with your ground truth interaction table, outputting predicted relationships and validation metrics as CSV tables, PDF plots, and RDS objects.

---

## [244] source=multitask_sft_big

**USER:** I need to perform multiple sequence alignment quality control prior to phylogenetic tree reconstruction in a comparative genomics pipeline. How can I invoke trimAl in automated gap-based mode?

**ASSISTANT:** You can integrate trimAl into your phylogenetic QC pipeline using the `-gappyout` automated mode. For example:
```bash
trimal -in input_alignment.fasta -out trimmed_alignment.fasta -gappyout
```
This command trims columns based on the gap distribution, preparing the MSA for downstream phylogenetic inference.

---

## [245] source=multitask_sft_big

**USER:** I have an amino acid multiple sequence alignment in FASTA format and need to mask alignment positions, calculate consensus sequences/matrices, and generate conservation scores. How should I set this up?

**ASSISTANT:** You can run the `msa_alignment_masking_consensus_and_conservation` workflow from the transcriptomics domain. 
- **Input**: `exampleAA.fasta` (FASTA file containing amino acid sequences)
- **Functionality**: Applies masks to the alignment, computes consensus matrices/sequences, and calculates position-specific conservation scores.
- **Output**: `consensus_score`.

---

## [246] source=multitask_sft_big

**USER:** I am setting up a structural variant detection pipeline with this numbered toolset. What is the necessary first step before executing downstream modules?

**ASSISTANT:** The first step is to execute `1_create_conf` to generate the shared configuration file, as all other pipeline programs beginning with a number depend on this configuration.

---

## [247] source=multitask_sft_big

**USER:** Can you summarize the tools and outputs involved in executing the scdblfinder workflow?

**ASSISTANT:** The scdblfinder workflow operates on an input `sce.rds` (a SingleCellExperiment object with raw counts) using Bioconductor packages including `scDblFinder`, `biocstyle`, `bluster`, `scrnaseq`, `scater`, and `scran`. It scores and classifies doublets, producing updated `cluster_assignments` and a modified `singlecellexperiment` object containing the doublet scores.

---

## [248] source=multitask_sft_big

**USER:** I am designing an RNA-Seq network analysis pipeline. Where does 'WGCNA: preprocessing (RNA)' fit in?

**ASSISTANT:** In an RNA co-expression network analysis workflow, `WGCNA: preprocessing (RNA)` fits at the initial stage where raw/normalized RNA expression profiles are prepared, checked, and formatted before running network construction and module detection algorithms in WGCNA.

---

## [249] source=multitask_sft_big

**USER:** What input parameters are required to run the Predict ADMET Properties (AI) workflow, and what output files will it produce?

**ASSISTANT:** To run the 'Predict ADMET Properties (AI)' workflow via the `PREDICT_ADMET_PROPERTIES` tool, you need to provide:
- Inputs: `smiles_list` and `ADMET_model_type`.

The workflow outputs three files:
- `tsv_admet`
- `csv_scores`
- `pdf_report`.

---

## [250] source=multitask_sft_big

**USER:** I want to identify and rank candidate cancer driver genes by integrating patient mutation data, expression outliers, and a gene influence graph. Which workflow and tool should I set up?

**ASSISTANT:** You can use the 'drivernet' workflow (domain: transcriptomics), which utilizes the 'bioconductor/drivernet' tool. It integrates patient mutation data, expression outlier matrices, and a gene-gene interaction network with permutation-based significance testing to prioritize driver genes.

---

## [251] source=multitask_sft_big

**USER:** Can you outline how 'Get Codon and Bicodon frequency' fits into a codon usage bias analysis workflow?

**ASSISTANT:** In a codon bias analysis workflow, input gene sequences are passed into 'Get Codon and Bicodon frequency' to calculate both individual codon usage and codon pair (bicodon) frequencies. The tool generates frequency tables structured like CoCoPUTs (Refseq_Bicod.tsv), which can then be directly ingested into downstream comparative genomics or translational efficiency analyses.

---

## [252] source=multitask_sft_big

**USER:** How can I set up an automated workflow to preprocess and model LiP-MS and TrP-MS data using Bioconductor packages?

**ASSISTANT:** You can use the 'msstatslip' workflow. It integrates 'bioconductor/msstatslip', 'bioconductor/gghighlight', and 'bioconductor/tidyverse'. Given your Spectronaut LiP-MS export, TrP-MS export, and reference FASTA file, the workflow preprocesses, summarizes, and models the data to yield output tables (CSV), visual plots (PDF), and R data objects (RDS).

---

## [253] source=multitask_sft_big

**USER:** I have low-coverage whole genome sequencing data and need an end-to-end workflow to impute missing genotypes using GLIMPSE. Which workflow should I use and what tools does it execute?

**ASSISTANT:** You should use `nf-core/vcf_impute_glimpse`. It takes `ch_input` and executes `glimpse/chunk`, `glimpse/phase`, `glimpse/ligate`, and `bcftools/index` to perform genotype imputation and output indexed, phased variant sets.

---

## [254] source=multitask_sft_big

**USER:** I have spatial transcriptomics count matrices and spot coordinates. How can I identify, classify, and cluster spatially variable genes?

**ASSISTANT:** You can utilize the 'spatialde' workflow. It incorporates 'bioconductor/spatialde' and 'bioconductor/spatialexperiment' to process your raw count matrix ('Rep11_MOB_0') and spatial coordinate metadata ('MOB_sample_info'), producing analytical visualizations of spatially variable genes.

---

## [255] source=multitask_sft_big

**USER:** I want to simulate a single-cell RNA-seq dataset with a continuous developmental trajectory from my reference data and visualize the simulation quality. What workflow, tools, and outputs are involved?

**ASSISTANT:** You can use the `scdesign3` workflow (transcriptomics domain).
- **Tools utilized**: bioconductor/scdesign3, bioconductor/singlecellexperiment, bioconductor/ggplot2.
- **Required inputs**: `example_count` (raw counts matrix) and `pseudotime` (vector of pseudotime values for cells).
- **Outputs produced**: `pseudotime_trajectory`, `singlecellexperiment`, and `counts_matrix`.

---

## [256] source=multitask_sft_big

**USER:** Can you outline the velociraptor workflow and specify its required tools and expected outputs for single-cell RNA velocity estimation?

**ASSISTANT:** The `velociraptor` workflow calculates RNA velocity from spliced and unspliced single-cell RNA-seq counts, projects vectors onto a low-dimensional embedding, and visualizes grid-summarized velocity vectors.

- **Input**: `sce` (SingleCellExperiment RDS containing "spliced" and "unspliced" assays)
- **Tools**: `bioconductor/velociraptor`, `bioconductor/biocstyle`, `bioconductor/ggplot2`, `bioconductor/knitr`, `bioconductor/scrnaseq`, `bioconductor/scater`
- **Outputs**: `pseudotime_trajectory`, `singlecellexperiment`, and `feature_selection`.

---

## [257] source=multitask_sft_big

**USER:** I want to subset tRNA sequences based on their base-pairing properties and extract structural elements. Which workflow should I use and what tools does it involve?

**ASSISTANT:** You can use the `trna` workflow (transcriptomics domain). It extracts specific tRNA structural elements and subsets tRNA sequences based on structural features and base-pairing properties using `bioconductor/trna` and `bioconductor/structstrings`.

---

## [258] source=multitask_sft_big

**USER:** I want to perform gene set enrichment analysis on a gene list and visualize the results. Can Biomni: Gene Set Enrichment Analysis output plots directly?

**ASSISTANT:** Yes, Biomni: Gene Set Enrichment Analysis includes built-in plotting functionality along with the enrichment analysis for your gene list.

---

## [259] source=multitask_sft_big

**USER:** I have a position weight matrix file and want to generate sequence logo visualizations and consensus scores in genomics. Which workflow should I run?

**ASSISTANT:** You should use the 'seqlogo' workflow. It takes a position weight matrix file ('pwm_matrix.txt') containing nucleotide probabilities and utilizes the 'bioconductor/seqlogo' tool to generate consensus scores and sequence logo visualizations.

---

## [260] source=multitask_sft_big

**USER:** We are conducting a microbial community profiling project using 16S rRNA gene amplicon sequencing. How does parallel_assign_taxonomy_rdp fit into our workflow?

**ASSISTANT:** In a 16S rRNA gene microbial profiling workflow, parallel_assign_taxonomy_rdp is used for the taxonomic classification step. After quality filtering and generating amplicon sequences or OTUs/ASVs, you execute parallel_assign_taxonomy_rdp (pointing to `scripts/assign_taxonomy.py`) to classify sequences against the RDP reference database in parallel across multiple processors.

---

## [261] source=multitask_sft_big

**USER:** How do I fit Fgbio Callmolecularconsensusreads into a consensus sequence generation pipeline for UMI-tagged BAM files?

**ASSISTANT:** In a UMI-tagged sequencing pipeline, after reads are mapped and grouped by their unique molecular identifier tags in a BAM file, pass the tagged BAM file into `Fgbio Callmolecularconsensusreads`. The tool will aggregate the reads sharing each unique molecular tag and output the called consensus sequences.

---

## [262] source=multitask_sft_big

**USER:** What tools and outputs are defined in the rrvgo workflow?

**ASSISTANT:** The rrvgo workflow utilizes the 'bioconductor/rrvgo' and 'bioconductor/knitr' tools. It produces two outputs: 'de_table' and 'visualizations'.

---

## [263] source=multitask_sft_big

**USER:** How do I structure a command-line call to hmmbuild to create a profile HMM from a multiple sequence alignment file?

**ASSISTANT:** The basic structure for hmmbuild is:
hmmbuild <hmmfile out> <msafile>
where <msafile> is your input multiple sequence alignment file and <hmmfile out> is the destination file for the generated profile HMM.

---

## [264] source=multitask_sft_big

**USER:** How do I prepare the input configuration for DNA-Bot to assemble multiple operon constructs?

**ASSISTANT:** To prepare input for DNA-Bot, create a CSV file where each row specifies one construct. Format each row as a defined sequence combining BASIC linker IDs and DNA part IDs matching your desired operon structure for high-throughput assembly.

---

## [265] source=multitask_sft_big

**USER:** What are the output data artifacts generated upon running the ode_signaling_simulation workflow?

**ASSISTANT:** The ode_signaling_simulation workflow produces five output artifacts: 'sdf', 'csv_scores', 'tsv_admet', 'tsv_pk', and 'pdf_report'.

---

## [266] source=multitask_sft_big

**USER:** What tools and expected output formats make up the river evaluation workflow?

**ASSISTANT:** The `river` workflow uses `bioconductor/river` and `bioconductor/devtools`. It produces outputs in `table/csv`, `plot/pdf`, and `object/rds` formats.

---

## [267] source=multitask_sft_big

**USER:** I have single-cell cytometry count data and want to cluster and visualize it using FlowSOM. What workflow is available and what tools does it wrap?

**ASSISTANT:** You can run the 'FlowSOM' workflow (single_cell domain). It takes `count_data` via the `input_files` input slot and wraps `bioconductor/flowsom` and `bioconductor/flowcore` to provide Self-Organizing Map (SOM) clustering and Minimal Spanning Tree (MST) visualization for cytometry data.

---

## [268] source=multitask_sft_big

**USER:** Can you outline the tools and expected outputs of the `pmp` workflow for processing metabolomics peak matrices?

**ASSISTANT:** The `pmp` workflow filters, normalizes, imputes, and scales metabolomics peak data. It utilizes `bioconductor/pmp`, `bioconductor/s4vectors`, `bioconductor/summarizedexperiment`, `bioconductor/ggplot2`, `bioconductor/gridextra`, and `bioconductor/reshape2`. It yields two primary outputs: `normalized_data` and `visualizations`.

---

## [269] source=multitask_sft_big

**USER:** What does the workflow `altcdfenvs_subset_and_modify_cdf_env` do, and what outputs does it produce?

**ASSISTANT:** The `altcdfenvs_subset_and_modify_cdf_env` workflow wraps an existing CDF environment package into a `CdfEnvAffy` object, subsets it to retain only specified probe sets of interest from an input text file, and renames the resulting environment.

It generates the following outputs:
- `table/csv`
- `plot/pdf`
- `object/rds`

---

## [270] source=multitask_sft_big

**USER:** I have a directory of raw Illumina IDAT files and need an epigenomics pipeline that performs quality control, preprocessing, and imputation all in a single run. What workflow can accomplish this?

**ASSISTANT:** You can run the `enmix` workflow. It takes a directory path containing raw IDAT files as input and performs quality control, preprocessing, and imputation in a single pipeline execution, utilizing tools such as `bioconductor/enmix`, `bioconductor/geneplotter`, and `bioconductor/minfidata`.

---

## [271] source=multitask_sft_big

**USER:** I have transcriptomics data formatted with individual IDs, conditions, and gene usage counts. How can I run a differential gene usage analysis and what output should I expect?

**ASSISTANT:** You can run the 'iggeneusage' workflow. Provide your data.frame containing columns 'individual_id', 'condition', 'gene_name', and 'gene_usage_count' (with optional 'replicate'). The workflow runs 'bioconductor/iggeneusage' using a Bayesian zero-inflated beta-binomial model and produces visualizations of differential gene usage.

---

## [272] source=multitask_sft_big

**USER:** I have curated molecular profiles and radiation sensitivity data in a RadioSet RData file. Which workflow should I trigger to identify radio-sensitivity signatures?

**ASSISTANT:** You should run the `radiogx_biomarker_discovery_signatures` workflow. You provide `radio_set.RData` as input, and it correlates molecular features with radiation response profiles to yield `copy_number_segments` and `visualizations`.

---

## [273] source=multitask_sft_big

**USER:** I have genomics FASTQ reads that might contain malformed records and broken pairs. Which workflow can sanitize the sequences and fix read pairing?

**ASSISTANT:** You should use the 'Fastq Sanitise Seqkit' workflow. It takes input FASTQ files, filters and reports malformed reads using seqkit/sana, and properly syncs paired-end reads using seqkit/pair, producing cleaned FASTQ files, version information, and YAML logs.

---

## [274] source=multitask_sft_big

**USER:** What tools are utilized in the rain workflow, and what output artifacts are produced?

**ASSISTANT:** The rain workflow utilizes the Bioconductor packages `bioconductor/rain` and `bioconductor/lattice`. Upon execution on an `expression_matrix.csv` file, it outputs results in three formats: a tabular CSV file (`table/csv`), visual diagnostic plots (`plot/pdf`), and serialized R objects (`object/rds`).

---

## [275] source=multitask_sft_big

**USER:** What inputs, outputs, and Bioconductor tools are involved in the ropls workflow?

**ASSISTANT:** The ropls workflow takes dataMatrix.tsv (a numeric matrix of samples as rows and variables as columns) as input and produces feature_selection and visualizations. It utilizes tools from bioconductor/ropls, bioconductor/biobase, bioconductor/multiassayexperiment, bioconductor/multidataset, bioconductor/summarizedexperiment, and bioconductor/phenomis.

---

## [276] source=multitask_sft_big

**USER:** I need to reorder my tabular data table so that specific columns appear first by name, without dropping the other columns. How can I achieve this?

**ASSISTANT:** You can use the 'Column arrange' tool from Text Manipulation. Specify the names of the columns you want to appear first in your desired order. The tool will place those named columns at the beginning and move all unspecified columns to the right while preserving their existing order.

---

## [277] source=multitask_sft_big

**USER:** I need an end-to-end single-cell workflow to perform both clustering and differential abundance testing on raw marker expression data while accounting for censored covariates.

**ASSISTANT:** You can deploy the `censcyt_censored_da_wrapper` workflow. It executes the complete differential abundance analysis pipeline (clustering and testing) from raw expression data (`d_input`, `experiment_info`, and `marker_info`), producing `differential_abundance` results, `cluster_assignments`, and diagnostic `visualizations`.

---

## [278] source=multitask_sft_big

**USER:** I have raw mass spectrometry CSV files in a folder and want to detect and normalize peaks to identify proto-biomarkers. Which workflow can I run?

**ASSISTANT:** You can run the proteomics workflow 'process' (using 'bioconductor/process'). Provide your raw mass spectrometry CSV files via the 'testdir' directory input to generate 'normalized_data'.

---

## [279] source=multitask_sft_big

**USER:** I have uncharacterized transcriptomics query samples and a labeled reference expression matrix. Which workflow can I run to calculate sample similarity using standard deviation feature selection?

**ASSISTANT:** You can run the `rgsea_sd_features` workflow in transcriptomics. It measures similarities between query and reference transcriptome samples using standard deviation-based feature selection. Provide `query_matrix.csv` (expression matrix for query samples) and `reference_matrix.csv` (expression matrix for reference samples with known classes), and it will output `enrichment_results` and `feature_selection`.

---

## [280] source=multitask_sft_big

**USER:** I need a workflow that takes a VCF file of single nucleotide variants along with mutation metadata (sample ID, age, chromosome, position, ref, alt), builds a trinucleotide feature matrix, and trains a supervised mutational signature. What workflow does this?

**ASSISTANT:** You can use the 'supersigs' workflow. It takes 'chr22.vcf.gz' (VCF containing SNVs) and 'example_dt' (data frame with sample_id, age, chromosome, position, ref, alt) to preprocess mutation data, construct a trinucleotide feature matrix, and train a supervised mutational signature (SuperSig).

---

## [281] source=multitask_sft_big

**USER:** I want to assemble a 2nd generation CAR-T construct targeting HER2 using a CD8alpha hinge and transmembrane domain with 4-1BB costimulation. Can you configure the `cart_construct_design` workflow?

**ASSISTANT:** You can use the `cart_construct_design` workflow. It selects the anti-HER2 scFv (VH-(G4S)3-VL format) from its 20-target library and assembles the full sequence: signal peptide -> HER2 scFv -> CD8alpha hinge/TM -> 4-1BB costimulatory domain -> CD3zeta activation domain. The workflow takes antigen target strings/gene names as input and outputs the construct sequence in FASTA, JSON, and TXT formats.

---

## [282] source=multitask_sft_big

**USER:** Can you summarize the sarks workflow, including its domain, underlying Bioconductor/R tools, and expected output formats?

**ASSISTANT:** Here is the summary for the `sarks` workflow:
- **Domain**: Transcriptomics
- **Purpose**: Identify individual sequence motifs correlated with numeric scores without spatial smoothing.
- **Tools**: `bioconductor/sarks`, `bioconductor/ggplot2`, and `bioconductor/rjava`
- **Inputs**: `simulatedSeqs` (named character vector) and `simulatedScores` (named numeric vector)
- **Outputs**: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [283] source=multitask_sft_big

**USER:** I have motif enrichment results from TOMTOM/HOMER ('sox2_motif_list.rda') and a list of genes expressed in embryonic stem cells ('ESC-expressed.txt'). How can I identify a transcriptional regulatory module around Sox2?

**ASSISTANT:** You can run the `rtrm` workflow. This workflow takes `sox2_motif_list.rda` and `ESC-expressed.txt` as required data inputs and integrates them with a filtered protein-protein interaction network. Utilizing tools such as `bioconductor/rtrm`, `bioconductor/motifdb`, and `bioconductor/pwmenrich`, it constructs the target transcriptional regulatory module and outputs a `network_graph` along with relevant `visualizations`.

---

## [284] source=multitask_sft_big

**USER:** How can I set up a transcriptomics workflow to run differential expression using the quasi-likelihood F-test framework in edgeR?

**ASSISTANT:** You can use the 'edger' workflow. Provide 'TableOfCounts.txt' (a tab-delimited text file containing gene counts and symbols) as input. The workflow executes 'bioconductor/edger' using the robust quasi-likelihood F-test framework and yields two outputs: 'de_table' and 'normalized_data'.

---

## [285] source=multitask_sft_big

**USER:** How does the `glmsparsenet_binary_classification_binomial` workflow operate, and what output should I expect?

**ASSISTANT:** The `glmsparsenet_binary_classification_binomial` workflow fits a network-penalized binomial logistic regression model using a correlation-based network constructed from the expression matrix (`xdata`) to classify the samples against binary labels (`ydata`). The resulting output is `feature_selection`.

---

## [286] source=multitask_sft_big

**USER:** I have a raw numerical count matrix from single-cell transcriptomics along with cell metadata. Which workflow will convert these into a SingleCellExperiment object suitable for scDataviz?

**ASSISTANT:** You should use the `scdataviz_import_numerical_data` workflow. It imports your numerical matrix (`mat`) and sample metadata (`metadata`) into a `SingleCellExperiment` object, producing the `singlecellexperiment` object, the `expression_matrix`, and `cluster_assignments` for downstream analysis in scDataviz.

---

## [287] source=multitask_sft_big

**USER:** How can I run an automated end-to-end delta-delta Ct analysis using the ddct pipeline with my SDS file 'Experiment1.txt'?

**ASSISTANT:** To run the `ddct` workflow:
1. Provide `Experiment1.txt` containing your individual SDS/SDM Ct values (and optionally `SampleAnno.txt` or `ddCt.conf`).
2. The pipeline executes the `ddCtExec` wrapper function utilizing tools from `bioconductor/ddct`, `bioconductor/biobase`, `bioconductor/rcolorbrewer`, and `bioconductor/lattice`.
3. It will generate your results across three formats: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [288] source=multitask_sft_big

**USER:** I need to set up a pipeline to run Bioconductor's mcia_multiomics. Which workflow template should I deploy?

**ASSISTANT:** You should deploy the `Mcia_multiomics` workflow, which encapsulates `bioconductor/mcia_multiomics` for multi-omics integration in the general domain.

---

## [289] source=multitask_sft_big

**USER:** I need a genomics workflow to generate both an IGV session XML and an interactive HTML report from my BAM/BigWig files and sample metadata. What workflow can accomplish this?

**ASSISTANT:** You can use the `tracktables` workflow (utilizing `bioconductor/tracktables`). It takes a `FileSheet` and a `SampleSheet` as data inputs and generates visualizations comprising interactive HTML tracktable reports and IGV session XML files.

---

## [290] source=multitask_sft_big

**USER:** I have FASTQ sequencing data and a reference FASTA file and want to detect novel and known miRNAs in transcriptomics data. Which workflow fits this?

**ASSISTANT:** You can use the subworkflow `nf-core/fastq_find_mirna_mirdeep2`. It takes `fastq` and `fa` files, processes sequence IDs, builds a Bowtie index, maps reads, and runs miRDeep2 to generate identified miRNAs as a `bed` file.

---

## [291] source=multitask_sft_big

**USER:** I want to set up a workflow using Bioconductor tools to identify cell neighborhoods with consistent differential expression across multiple conditions. What components make up the lemur workflow?

**ASSISTANT:** The `lemur` workflow integrates three Bioconductor/R tools: `bioconductor/lemur`, `bioconductor/singlecellexperiment`, and `bioconductor/tidyverse`. It takes `glioblastoma_example_data` (a SingleCellExperiment RDS object with counts and multi-condition `colData`), fits the LEMUR model, aligns embeddings, predicts differential expression, and outputs `de_table` containing the validated neighborhood differential expression results.

---

## [292] source=multitask_sft_big

**USER:** I have RMA expression data (`datA.rma`), MAS5 expression data (`datA.mas5`), and absent/present calls (`datA.amp`). How can I evaluate whether normalization was effective and generate diagnostic plots?

**ASSISTANT:** You can run the `macorrplot` workflow (`bioconductor/macorrplot`). Pass `datA.rma`, `datA.mas5`, and `datA.amp` as inputs. The workflow will evaluate normalization quality by plotting correlation versus variability across random gene pairs and produce the resulting `normalized_data` and `visualizations`.

---

## [293] source=multitask_sft_big

**USER:** What are the inputs, tools, and outputs associated with the `Bed Scatter Bedtools` workflow?

**ASSISTANT:** The `Bed Scatter Bedtools` workflow has the following specifications:
- **Input**: `bed`
- **Tool**: `bedtools/split`
- **Outputs**: `bam`, `bai`, `fasta_assembly`, and `multiqc_report`.

---

## [294] source=multitask_sft_big

**USER:** I need a workflow to process cytometric cell abundance data, normalize it, and generate barcode and boxplot visualizations of community dynamics. How can this be structured?

**ASSISTANT:** You can run the 'flowcybar' workflow. Provide 'Cell_number_sample.txt' as the input data. The workflow uses 'bioconductor/flowcybar' to normalize cytometric cell abundance data and outputs 'normalized_data' along with 'visualizations' (barcodes and boxplots).

---

## [295] source=multitask_sft_big

**USER:** How does the `msnid` proteomics workflow process peptide-spectrum matches into final identification objects?

**ASSISTANT:** The `msnid` workflow follows these steps:
1. Load MS/MS search results (e.g., tab-delimited PSM results or mzIdentML files) into `msnid`.
2. Assess enzymatic cleavage properties using `biostrings`.
3. Model and correct parent ion mass errors.
4. Optimize multi-dimensional filtering criteria to maximize PSM identifications subject to a user-defined target false discovery rate (FDR).
5. Export the filtered identification tables to an `MSnSet` (RDS object), CSV summary tables, and diagnostic PDF plots.

---

## [296] source=multitask_sft_big

**USER:** What outputs can I expect from the `msprep_summarized_experiment_pipeline` metabolomics workflow?

**ASSISTANT:** The `msprep_summarized_experiment_pipeline` produces three outputs: `summarizedexperiment` (the processed SummarizedExperiment object), `normalized_data`, and `visualizations`.

---

## [297] source=multitask_sft_big

**USER:** I want to perform functional enrichment analysis and generate exploratory plots directly from my DESeq2 macrophage results. Can you generate the appropriate workflow?

**ASSISTANT:** You can use the `mosdef` workflow designed for transcriptomics. It takes your DESeqDataSet count object (`dds_macrophage`) and DESeqResults object (`res_macrophage_IFNg_vs_naive`), leveraging Bioconductor packages such as `bioconductor/mosdef`, `bioconductor/deseq2`, `bioconductor/annotationdbi`, `bioconductor/topgo`, `bioconductor/ggplot2`, and `bioconductor/macrophage`. The workflow produces a differential expression table (`de_table`) and visualization outputs (`visualizations`).

---

## [298] source=multitask_sft_big

**USER:** I have merged amplicon FASTQ reads and reference sequences for synthetic community (SynCom) strains. How can I profile the community and correct sequencing errors?

**ASSISTANT:** You can execute the 'rbec' metagenomics workflow. It takes 'test_raw_merged_reads.fastq.gz' (raw merged amplicon reads) and 'test_ref.fasta' (reference sequences for SynCom strains), runs 'bioconductor/rbec', and outputs community profiles and corrections as 'table/csv', 'plot/pdf', and 'object/rds'.

---

## [299] source=multitask_sft_big

**USER:** I want to rank transcriptomic features, train an SVM classifier, and compare feature p-values and performance against SVM-RFE. What Bioconductor tools does the `sigfeature` workflow utilize?

**ASSISTANT:** The `sigfeature` workflow uses the following tools:
- `bioconductor/sigfeature`
- `bioconductor/summarizedexperiment`
- `bioconductor/e1071`
- `bioconductor/pheatmap`
- `bioconductor/rcolorbrewer`

---

## [300] source=multitask_sft_big

**USER:** I need a workflow to prepare reference genome index files for both Bismark and bwameth from a reference FASTA. What pipeline can achieve this?

**ASSISTANT:** You can use the `Fasta Index Bismark Bwameth` workflow. It processes a reference fasta to generate index files for Bismark and bwameth using `untar`, `gunzip`, `bismark/genomepreparation`, `bwameth/index`, and `samtools/faidx`.

---

## [301] source=multitask_sft_big

**USER:** How can I set up a workflow to perform resampling-based pathway analysis on two-sample gene expression data using built-in annotations?

**ASSISTANT:** You can use the `safe` transcriptomics workflow. It utilizes `bioconductor/safe`, `bioconductor/breastcancerupp`, and `bioconductor/doparallel`. It takes a gene expression matrix (`e3.upp`) and a binary phenotype vector (`p3.upp$p53`) as inputs, and generates `enrichment_results`, `pathway_results`, and `visualizations`.

---

## [302] source=multitask_sft_big

**USER:** I have multiple transcriptomic datasets and want to fit a Bayesian hierarchical model across all of them to identify both concordant and discordant differential expression patterns. What workflow should I execute?

**ASSISTANT:** You should use the **xde** workflow. It utilizes Bioconductor tools (`bioconductor/xde`, `bioconductor/genemeta`, and `bioconductor/siggenes`) to fit a Bayesian hierarchical model across multiple studies. It requires an RDS file containing an `ExpressionSetList` and outputs differential expression tables (`de_table`) and diagnostic visualizations (`visualizations`).

---

## [303] source=multitask_sft_big

**USER:** I have multiple genome assemblies in FASTA format and need an automated genomics pipeline to compare their quality alongside their annotations. What workflow can I run?

**ASSISTANT:** You can run the `nf-core/genomeqc` pipeline. It is specifically designed to compare the quality of multiple genomes and their annotations, taking FASTA files as input.

---

## [304] source=multitask_sft_big

**USER:** I have bulk RNA-seq count data from a single species and known housekeeping gene indices. How can I identify differentially expressed genes using the SFMEB method, and what outputs should I expect?

**ASSISTANT:** You can execute the `meb` workflow (utilizing `bioconductor/meb`, `bioconductor/singlecellexperiment`, and `bioconductor/summarizedexperiment`).

Inputs required:
1. `countsTable`: raw RNA-seq count matrix (genes in rows, samples/replicates in columns)
2. `train_id`: row indices indicating known housekeeping genes

Outputs produced:
- `de_table`: table of differentially expressed genes
- `cluster_assignments`: gene or sample cluster assignments
- `normalized_data`: normalized expression matrix

---

## [305] source=multitask_sft_big

**USER:** In a variant analysis workflow, what tool creates the underlying snpEff database needed for downstream annotations?

**ASSISTANT:** The tool to use is 'SnpEff build', which creates a snpEff database via `snpEff build`.

---

## [306] source=multitask_sft_big

**USER:** Can you summarize the inputs, underlying tools, and expected outputs for the rontotools Pathway-Express workflow?

**ASSISTANT:** For the `rontotools` workflow:
- **Input**: `topTable.RData` (a non-optional data frame with logFC, P.Value, adj.P.Val, and entrez gene IDs)
- **Tools**: `bioconductor/rontotools` and `bioconductor/graph`
- **Outputs**: `de_table`, `pathway_results`, and `visualizations`
It performs Pathway-Express analysis to identify significantly impacted signaling pathways using gene fold changes, p-values, and pathway topology.

---

## [307] source=multitask_sft_big

**USER:** Can you design a safety pharmacology workflow according to ICH S7A guidelines covering the mandatory organ systems for drug discovery candidate molecules?

**ASSISTANT:** You can deploy the `ich_s7a_safety_pharmacology` workflow. It evaluates the three mandatory core organ systems:
1. Cardiovascular: hERG IC50, QTc Fridericia, MAP, and HR (including the ICH S7B CiPA Tier 2 escalation trigger).
2. Central Nervous System (CNS): Irwin score, BBB penetration, sedation/tremor/convulsion risk, and CNS-MPO.
3. Respiratory: Respiratory Rate (RR), tidal volume, and SpO2.
It also supports supplemental systems like renal assessment and generates structured outputs in sdf, csv_scores, tsv_admet, tsv_pk, and pdf_report formats.

---

## [308] source=multitask_sft_big

**USER:** I need a workflow to evaluate codon usage bias and functional enrichment of highly expressed genes from open reading frames. What tools and outputs are involved?

**ASSISTANT:** You can use the 'cordon' workflow. 
- Input: `sequences.fasta` (DNA sequences of open reading frames)
- Included tools: `bioconductor/cordon`, `bioconductor/biobase`, and `bioconductor/ggplot2`
- Outputs: `enrichment_results` and `visualizations`

---

## [309] source=multitask_sft_big

**USER:** What sequence of tools is executed within the Alphagenome Track Prediction workflow?

**ASSISTANT:** The `alphagenome_track_prediction` workflow executes the following pipeline of tools in order:
1. `VALIDATE_REGION`: Validates the genomic input window (~1Mb).
2. `FETCH_SEQUENCE`: Extracts the reference genome sequence.
3. `ALPHAGENOME_PREDICT`: Generates functional genomic track predictions.
4. `VARIANT_EFFECT_SCORE`: Evaluates variant consequences if a VCF is provided.
5. `AGGREGATE_TRACKS`: Aggregates the multi-track prediction data.
6. `GENERATE_REPORT`: Produces the final JSON report.

---

## [310] source=multitask_sft_big

**USER:** I have mapped reads from a transcription factor ChIP-seq experiment and a matching control. What is the workflow step to call high-resolution TF binding sites using Peakzilla?

**ASSISTANT:** Feed your mapped ChIP-seq alignment data directly into `Peakzilla (ChIP-seq)`. Peakzilla will identify binding sites and enrichment peaks at high resolution, estimating required parameters automatically regardless of the organism, outputting precise transcription factor binding coordinates.

---

## [311] source=multitask_sft_big

**USER:** Can you configure the cytoviewer workflow entry for our imaging pipeline using count_data?

**ASSISTANT:** Here is the configuration for running the `cytoviewer` workflow:

```yaml
workflow: cytoviewer
domain: imaging
tools:
  - bioconductor/cytoviewer
  - bioconductor/cytomapper
inputs:
  count_data: "path/to/count_data.rds"
```

This will launch the interactive Shiny interface supporting both image-level and cell-level mask visualization.

---

## [312] source=multitask_sft_big

**USER:** Please outline the execution plan for running `scatterhatch` on my spatial coordinate file.

**ASSISTANT:** To execute the `scatterhatch` workflow:
1. Input: Provide `pdacData.csv` containing X/Y spatial coordinates and group annotations.
2. Processing: Run `bioconductor/scatterhatch` to assign colors and distinct hatching patterns to each group.
3. Output: Retrieve the generated plot stored under `visualizations`.

---

## [313] source=multitask_sft_big

**USER:** I have segmented QDNAseq RDS files from low-coverage whole-genome sequencing in '/data/qdnaseq_segments/'. How can I configure the ace workflow to produce absolute copy number segments and fitpicker tables?

**ASSISTANT:** You can configure the 'ace' workflow with the following specification:

```json
{
  "workflow": "ace",
  "data_inputs": {
    "Aligned": "/data/qdnaseq_segments/"
  }
}
```

This will trigger the pipeline utilizing bioconductor/ace, bioconductor/biobase, bioconductor/qdnaseq, and bioconductor/ggplot2 to yield copy number segments and visualization/fitpicker outputs.

---

## [314] source=multitask_sft_big

**USER:** What outputs and underlying Bioconductor tools are involved when running the ibh workflow?

**ASSISTANT:** The ibh workflow generates three outputs: 'de_table', 'cluster_assignments', and 'network_graph'. It integrates the following Bioconductor tools: bioconductor/ibh, bioconductor/simpintlists, bioconductor/stats, and bioconductor/yeastcc.

---

## [315] source=multitask_sft_big

**USER:** I need a transcriptomics workflow to identify impacted signaling pathways in colorectal cancer by combining topology perturbation and over-representation analysis. What does the 'spia' workflow look like?

**ASSISTANT:** The 'spia' workflow performs Signaling Pathway Impact Analysis using pre-existing pathway data:
- **Inputs**:
  - `DE_Colorectal`: Named numeric vector of log2 fold changes for differentially expressed genes, named by Entrez IDs.
  - `ALL_Colorectal`: Character vector of Entrez IDs for all genes profiled on the platform.
- **Tools Used**: `bioconductor/spia`, `bioconductor/rgraphviz`, `bioconductor/graph`
- **Outputs**: `de_table`, `enrichment_results`, `visualizations`

---

## [316] source=multitask_sft_big

**USER:** Can you summarize the input, underlying tool, and output specifications for the methped workflow?

**ASSISTANT:** Here is the specification for the `methped` workflow:
- Domain: Epigenomics
- Input: `methylation_data.csv` (matrix, data.frame, or ExpressionSet of DNA methylation beta values from Illumina 450k arrays)
- Underlying Tool: `bioconductor/methped`
- Output: `visualizations`
- Function: Classifies pediatric brain tumor samples into subtypes while handling missing values.

---

## [317] source=multitask_sft_big

**USER:** I need to set up an iterative BMA survival validation pipeline on our transcriptomic cohort. What does the iterativebmasurv_cross_validation workflow take in, what analysis does it execute, and what will it output?

**ASSISTANT:** The `iterativebmasurv_cross_validation` workflow operates as follows:
- Inputs: `trainData` (expression matrix), `trainSurv` (survival times vector), and `trainCens` (censoring status vector).
- Execution: It performs k-run n-fold cross-validation on the training set to evaluate model performance and optimize model parameters.
- Output: Generates `visualizations` summarizing the cross-validation performance.

---

## [318] source=multitask_sft_big

**USER:** I need to classify an uncharacterized RNA-seq expression matrix against a reference dataset and generate visualization plots. Which workflow accomplishes this?

**ASSISTANT:** You can use the `sampleclassifier_rnaseq_classification` workflow. It takes an RNA-seq reference matrix (`rnaseq_refmat`) and a query expression matrix (`rnaseq_testmat`), classifies the profiles, and outputs visualizations.

---

## [319] source=multitask_sft_big

**USER:** I need to scan a genomic FASTA sequence for non-standard, custom interstrand G-quadruplex structures. How can I achieve this?

**ASSISTANT:** You can use the `pqsfinder_custom_g4_detection` workflow. Provide your DNA sequence in FASTA format (`sequence.fa`). The workflow applies custom scoring functions and regular expressions to detect non-standard or customized G4 structures and outputs results in `table/csv`, `plot/pdf`, and `object/rds` formats.

---

## [320] source=multitask_sft_big

**USER:** Which underlying tools are executed by the nf-core/deepvariant pipeline, and what outputs does it yield?

**ASSISTANT:** The nf-core/deepvariant workflow sequentially runs three tools: `deepvariant/makeexamples`, `deepvariant/callvariants`, and `deepvariant/postprocessvariants`. It generates two primary outputs: `vcf` and `tbi`.

---

## [321] source=multitask_sft_big

**USER:** How does the bioconductor/tilingarray workflow segment sequential genomic data, and what are its outputs?

**ASSISTANT:** The `tilingarray` workflow fits a piecewise constant curve to sequential genomic data provided via `intensity_matrix.txt` and determines the optimal number of segments using statistical model selection criteria (AIC or BIC). The workflow generates three outputs: `copy_number_segments`, `normalized_data`, and `visualizations`.

---

## [322] source=multitask_sft_big

**USER:** I performed a CRISPR editing experiment and collected amplicon sequencing data. I have my FASTQ reads of the edited region and the unedited target FASTA sequence. How can I reconstruct a lineage tree and inspect the mutation patterns?

**ASSISTANT:** You can use the 'lintind' workflow. 
- Inputs: Provide your amplicon FASTQ reads to 'reads.fastq' and the unedited target sequence to 'reference.fasta'.
- Underlying tool: 'bioconductor/lintind'.
- Outputs: It generates visualizations showing indel patterns and the reconstructed lineage tree.

---

## [323] source=multitask_sft_big

**USER:** How can I perform crosswise permutation tests across several genomic region sets and visualize correlation matrices in epigenomics?

**ASSISTANT:** You can run the `regionereloaded` workflow (powered by `bioconductor/regionereloaded`). It accepts your genomic region sets (`Alist`, optional `Blist`) and reference `genome`, performs crosswise permutation tests, creates and clusters an association or correlation matrix, and outputs visual evaluations via heatmaps and dimensionality reduction.

---

## [324] source=multitask_sft_big

**USER:** I'm setting up an automated pipeline for bacterial genomics. How should I incorporate Pneumocat into a Streptococcus pneumoniae workflow?

**ASSISTANT:** In your pipeline, feed your raw or quality-filtered Illumina paired-end FASTQ reads directly into Pneumocat. Pneumocat will analyze the read pairs and output the predicted Streptococcus pneumoniae serotype, which can subsequently be routed into surveillance reports or downstream comparative genomics steps.

---

## [325] source=multitask_sft_big

**USER:** What types of output files are produced when running the speckle_propeller_on_precalculated_proportions workflow?

**ASSISTANT:** The `speckle_propeller_on_precalculated_proportions` workflow generates the following outputs:
- `table/csv`: Tabular propeller analysis results
- `plot/pdf`: Graphical output plots
- `object/rds`: Serialized R data object containing the results

---

## [326] source=multitask_sft_big

**USER:** What is the initial step for reference genome preparation when setting up a BWA alignment pipeline?

**ASSISTANT:** The initial step is to run `Bwa Index` on your reference genome FASTA file to generate the required index files for downstream alignment.

---

## [327] source=multitask_sft_big

**USER:** What output format will `nf-core/tiff_segmentation_vpt` produce after segmenting my MERSCOPE TIFF images?

**ASSISTANT:** The workflow produces segmentation results compiled in the `parquet` format (`parquet`), containing the spatial boundary coordinates and metadata generated by `vizgenpostprocessing/compiletilesegmentation`.

---

## [328] source=multitask_sft_big

**USER:** How should I structure a drug candidate screening workflow using the drug_discovery_screening_pipeline?

**ASSISTANT:** You can structure the screening workflow using `drug_discovery_screening_pipeline` as follows:
1. Input candidate drug compounds into the multi-process parallel pipeline.
2. Compute physicochemical properties with RDKit.
3. Evaluate binding affinity and predict ADMET properties using DeepPurpose.
4. Perform molecular docking using AutoDock Vina.

---

## [329] source=multitask_sft_big

**USER:** What tools and output files are generated by the qsmooth workflow?

**ASSISTANT:** The qsmooth workflow utilizes `bioconductor/qsmooth`, `bioconductor/summarizedexperiment`, `bioconductor/bodymaprat`, and `bioconductor/quantro`. It produces three outputs: `expression_matrix`, `normalized_data`, and `visualizations`.

---

## [330] source=multitask_sft_big

**USER:** In my workflow, I have a single dataset output that I need packaged into a collection structure without re-running analysis. What step should I add?

**ASSISTANT:** Add the 'Duplicate to Collection' tool from the Collection Operations suite to duplicate that dataset directly into a collection.

---

## [331] source=multitask_sft_big

**USER:** Can you configure a transcriptomics workflow to perform permutation-based gene set analysis on unpaired two-sample expression data?

**ASSISTANT:** You can use the `gsalightning` workflow (domain: transcriptomics):
- **Tool**: `bioconductor/gsalightning`
- **Function**: Performs permutation-based gene set analysis on unpaired two-sample expression data with optional restandardization.
- **Inputs**:
  - `expression_matrix.csv`: Matrix with genes as rows and samples as columns
  - `sample_metadata.csv`: Sample annotations containing group/condition factors
  - `gene_sets.gmt`: Curated gene set collections
- **Output**:
  - `enrichment_results`: Gene set enrichment results.

---

## [332] source=multitask_sft_big

**USER:** Can you outline the components, inputs, and outputs of the turbonorm pipeline?

**ASSISTANT:** Here is the structure of the `turbonorm` workflow:
- **Domain**: Epigenomics
- **Inputs**: 
  - `x.txt` (numeric vector of predictor values)
  - `y.txt` (numeric vector of response values)
- **Underlying Tools**: `bioconductor/turbonorm`, `bioconductor/lattice`, and `bioconductor/marray`
- **Method**: Fits a fast piecewise constant P-spline to scatterplot data
- **Output**: `normalized_data`

---

## [333] source=multitask_sft_big

**USER:** I am designing a microbiology imaging pipeline to assess bacterial cell shape changes after antibiotic treatment. How should I integrate Biomni: Segment And Analyze Microbial Cells?

**ASSISTANT:** You can integrate `Biomni: Segment And Analyze Microbial Cells` in your pipeline as follows:
1. Collect and preprocess your raw fluorescence microscopy images of microbial cultures.
2. Pass the fluorescence microscopy images into `Biomni: Segment And Analyze Microbial Cells` to perform automated cell segmentation.
3. Extract the resulting quantified morphological metrics (e.g., cell dimensions and shape features) for downstream statistical comparison between treated and untreated conditions.

---

## [334] source=multitask_sft_big

**USER:** I need to prepare a multi-megabase genomic FASTA database for BLAST nucleotide searches without getting swamped by low-complexity repeats. What is the standard preprocessing step?

**ASSISTANT:** The recommended preprocessing step is to run `dustmasker` from NCBI BLAST+ on your nucleotide FASTA database. It applies the symmetric DUST algorithm to mask out low-complexity nucleotide segments, which prevents non-specific repetitive alignments during downstream BLAST querying.

---

## [335] source=multitask_sft_big

**USER:** How can I set up an interactive visualization step for my DNA-seq copy number pipeline that includes LOH and SNV variants?

**ASSISTANT:** You can integrate CNViz into your workflow. Provide your probe, gene, and segment-level log2 copy number ratios along with your LOH and SNV data; CNViz will launch a Shiny application to visualize the integrated copy number profile.

---

## [336] source=multitask_sft_big

**USER:** Can you outline an alignment workflow for paired-end bisulfite sequencing data using Biscuit?

**ASSISTANT:** 1. Prepare bisulfite-converted paired-end sequencing reads (e.g., FASTQ files from WGBS or scWGBS) and indexed reference genome.
2. Run `Biscuit Align` on the paired-end read files against the reference genome.
3. Retain the resulting aligned alignments for downstream DNA methylation calling and analysis.

---

## [337] source=multitask_sft_big

**USER:** How can I set up an automated pipeline to perform differential abundance (DA) and differential state (DS) analysis on raw cytometry data?

**ASSISTANT:** You can use the `diffcyt` workflow. It utilizes Bioconductor packages (`bioconductor/diffcyt`, `bioconductor/hdcytodata`, and `bioconductor/flowcore`) through the single wrapper function `diffcyt()`. Provide `d_flowSet` (raw cytometry data in an RDS flowSet object), `experiment_info` (sample metadata), and `marker_info` (marker classifications) to produce `de_table` and `differential_abundance` outputs.

---

## [338] source=multitask_sft_big

**USER:** How do I construct a deconvolution workflow using granulator for heterogeneous tissue RNA-seq?

**ASSISTANT:** To set up a deconvolution workflow using `granulator`:
1. **Prepare Data**: Assemble your bulk RNA-seq expression matrix (heterogeneous tissue) and reference single-cell RNA-seq expression profiles or signature matrices.
2. **Deconvolution Setup**: Load the data into `granulator`'s unified testing interface.
3. **Benchmark & Run**: Execute multiple deconvolution algorithms supported by granulator to estimate cell type proportions.
4. **Evaluate**: Compare method performance and extract inferred cell fraction estimates for downstream differential analysis.

---

## [339] source=multitask_sft_big

**USER:** How does `Krakentools: Calculates alpha diversity` fit into an end-to-end Kraken metagenomics workflow?

**ASSISTANT:** In a standard metagenomics workflow: 1) Classify sequences using Kraken, Kraken 2, or KrakenUniq; 2) Perform abundance estimation using Bracken; 3) Use `Krakentools: Calculates alpha diversity` to assess alpha diversity from the resulting Bracken files across your comparative samples.

---

## [340] source=multitask_sft_big

**USER:** Generate an outline for a downstream RNA-seq exploratory workflow that leverages tidySummarizedExperiment.

**ASSISTANT:** Here is an outline for an exploratory workflow using `tidySummarizedExperiment`:
1. Load the transcriptomic `SummarizedExperiment` object into R.
2. Apply `tidySummarizedExperiment` to expose a tidy abstraction of the assay values, feature metadata, and sample metadata.
3. Use tidy operations for data exploration, filtering, and preparation for clustering or differential expression analysis within the assay domain.

---

## [341] source=multitask_sft_big

**USER:** I want to cluster uveal melanoma samples using only binary mutation data while weighting the clustering by patient overall survival. Can you specify the required workflow and its outputs?

**ASSISTANT:** Use the workflow `survclust_single_omic_clustering` (domain: genomics).

- **Inputs Required:**
  - `uvm_mut_dat`: Molecular data matrix (binary mutation matrix).
  - `uvm_survdat`: Survival matrix/data frame with time and event status (rownames matching samples in `uvm_mut_dat`).
- **Generated Outputs:**
  - `cluster_assignments`
  - `copy_number_segments`
  - `visualizations`

---

## [342] source=multitask_sft_big

**USER:** I need to configure a transcriptomics pipeline that runs Significance Analysis of Microarrays (SAM) on microarray expression data to identify differential expression and generate Delta plots. What would the workflow specification look like?

**ASSISTANT:** You can use the `siggenes` workflow:
- **Domain**: transcriptomics
- **Tools**: `bioconductor/siggenes`, `bioconductor/genefilter`
- **Inputs**:
  - `golub`: microarray expression matrix
  - `golub.cl`: class label vector for the samples
- **Outputs**:
  - `de_table`: table of differentially expressed genes
  - `visualizations`: SAM and Delta plots

---

## [343] source=multitask_sft_big

**USER:** How do I set up a step-by-step procedure to inspect k-mer frequency distributions using the FASTK suite?

**ASSISTANT:** To inspect k-mer frequency distributions:
1. Run the FASTK tool on your sequencing reads to compute k-mer counts and produce a '.hist' histogram file.
2. Execute FastK Histex, providing the '.hist' file to read and display the k-mer histogram for quality assessment and depth estimation.

---

## [344] source=multitask_sft_big

**USER:** Can you propose a minimal assembly workflow incorporating Raven for our long-read sequencing project?

**ASSISTANT:** A standard de novo assembly workflow utilizing Raven consists of:
1. Quality control of raw sequencing data (filtering low-quality or extremely short reads).
2. De novo genome assembly directly on the uncorrected long reads using Raven.
3. Post-assembly evaluation (e.g., assessing contiguity via N50 and completeness via BUSCO).
4. Optional downstream polishing using long- or short-read polishers.

---

## [345] source=multitask_sft_big

**USER:** What inputs, outputs, and underlying tools are configured in the Global Ctf Refinement cryo-EM workflow?

**ASSISTANT:** The `Global Ctf Refinement` workflow is configured with:
- **Tool:** `GLOBAL_CTF_REFINEMENT`
- **Input parameters:** `fit_tilt`, `fit_anisomag`, `fit_trefoil`, `fit_spherical`, and `use_cryosparc`
- **Outputs:** `.cs` metadata file and `.json` metadata file containing the estimated global aberration corrections.

---

## [346] source=multitask_sft_big

**USER:** What outputs can I expect from running scaff2chrom in my genome assembly pipeline?

**ASSISTANT:** `scaff2chrom` produces two output files:
1. A multifasta file containing the reconstructed chromosomes.
2. An AGP file locating the scaffolds within the reconstructed chromosomes.

---

## [347] source=multitask_sft_big

**USER:** I need to check for duplicate patients and cross-study contamination across multiple transcriptomic datasets. Which workflow should I run and what inputs does it take?

**ASSISTANT:** You should run the `doppelgangR` workflow. It accepts count/expression inputs structured as ExpressionSet objects (slot `input_files`), utilizing `bioconductor/doppelgangr`, `bioconductor/biobase`, and `bioconductor/curatedovariandata` to detect duplicate samples across genomic measurements, phenotype tables, and unique identifier fields.

---

## [348] source=multitask_sft_big

**USER:** I have raw .fcs flow cytometry files and need an automated quality control and preprocessing pipeline in R that integrates PeacoQC and visualizes the results. How can I build this?

**ASSISTANT:** You can use the `cytopipeline` workflow. It builds, executes, and visualizes a flow cytometry preprocessing pipeline via step-by-step S4 object construction, leveraging `bioconductor/cytopipeline`, PeacoQC for quality control, and `bioconductor/ggplot2` and `bioconductor/reshape2` to generate visualization outputs.

---

## [349] source=multitask_sft_big

**USER:** What tools are executed in the gcatest workflow, and what output should I expect?

**ASSISTANT:** The `gcatest` workflow executes `bioconductor/gcatest`, `bioconductor/lfa`, and `bioconductor/ggplot2`. The primary output generated is `gwas_summary_statistics`.

---

## [350] source=multitask_sft_big

**USER:** I have gene expression count data from a cell differentiation experiment and want to infer regulator-target networks and rank key transcriptional regulators. Which workflow should I use?

**ASSISTANT:** You should run the `RegEnrich` workflow. It takes count data (`count_data`) and integrates Bioconductor packages (`bioconductor/regenrich`, `bioconductor/biocparallel`, `bioconductor/geoquery`, `bioconductor/affy`, `bioconductor/annotate`) to perform differential expression, infer regulator-target networks, conduct enrichment analysis, and identify key gene regulators.

---

## [351] source=multitask_sft_big

**USER:** Can you outline the inputs, outputs, and function of the structuralvariantannotation_format_conversion_and_visualization workflow?

**ASSISTANT:** The `structuralvariantannotation_format_conversion_and_visualization` workflow operates within the variant_calling domain:
- **Function**: Converts breakpoint GRanges to BEDPE format and visualizes them using a circos plot.
- **Inputs**: `gridss.vcf` (structural variant calls) and `COLO829T.purple.sv.ann.vcf.gz` (annotated structural variant calls).
- **Outputs**: `vcf` and `visualizations`.

---

## [352] source=multitask_sft_big

**USER:** Can you configure the pipeline to perform MSPC peak calling from my two replicate GRanges objects in R?

**ASSISTANT:** You can configure `rmspc_peak_calling_from_granges` by providing your replicate peak objects `GR1` and `GR2`. The workflow will execute MSPC peak calling and generate tabular results (`table/csv`), diagnostic visualizations (`plot/pdf`), and serialized R results (`object/rds`).

---

## [353] source=multitask_sft_big

**USER:** Can you configure the BioMate structural biology workflow for Chai1 structure prediction?

**ASSISTANT:** Here is the configuration for the `chai1_structure_prediction` workflow:
- Domain: structural_biology
- Workflow: `chai1_structure_prediction`
- Required Inputs:
  - `input_fasta`: Path to input FASTA file
  - `num_trunk_recycles`: Number of trunk recycling iterations
  - `num_diffusion_timesteps`: Number of timesteps for diffusion
  - `seed`: Random seed for reproducibility
- Pipeline Tools:
  1. `CHAI1_PREDICT`
  2. `SUMMARISE_RESULTS`

---

## [354] source=multitask_sft_big

**USER:** Can you outline the inputs, workflow execution, and expected output types for dmrseq_dmr_simulation?

**ASSISTANT:** Here is the summary for `dmrseq_dmr_simulation`:
- **Input**: `bs_object.rds` (a pre-constructed BSseq object with WGBS counts from multiple same-condition samples).
- **Process**: Splits the homogeneous samples into artificial groups and injects synthetic in silico DMRs to benchmark detection performance.
- **Outputs**: Output files include results in `table/csv`, graphical summaries in `plot/pdf`, and processed data stored as `object/rds`.

---

## [355] source=multitask_sft_big

**USER:** How do I prepare a custom reference GTF for 10x Genomics Cell Ranger analysis?

**ASSISTANT:** To prepare your reference GTF, run the Cellranger Mkgtf module. This executes 'cellranger mkgtf' to filter your input GTF down to the relevant features and generate the filtered GTF needed by Cell Ranger reference-building steps.

---

## [356] source=multitask_sft_big

**USER:** I have training and test gene expression matrices with matched survival times and censoring vectors. Which workflow can I generate to perform survival risk modeling and model visualization using Bioconductor?

**ASSISTANT:** You can generate the 'iterativebmasurv' workflow. It uses 'bioconductor/iterativebmasurv' to train the iterative BMA survival model on your training sets (trainData, trainSurv, trainCens), predict risk scores and risk categories on test sets (testData, testSurv, testCens), evaluate survival differences, and output visualization plots.

---

## [357] source=multitask_sft_big

**USER:** How do I structure the inputs and outputs for the gmoviz_incremental_plotting workflow?

**ASSISTANT:** Configure the workflow with the following specifications:
- **Inputs**:
  - `coverage.bam` (BAM file for ideogram and coverage)
  - `features.gff3` (GFF file for features)
  - `numeric_data.txt` (numeric values for scatterplot/line graph)
- **Outputs**:
  - `visualizations` (the resulting customized circular plots)

---

## [358] source=multitask_sft_big

**USER:** I have a normalized gene expression matrix and want to build a gene regulatory network using Bioconductor. Can you outline the workflow using genie3?

**ASSISTANT:** You can run the `genie3` workflow: provide your gene expression matrix (`exprMatr`, where rows are genes and columns are samples) to the workflow, which executes `bioconductor/genie3` using tree-based methods to infer ranked regulatory links, returning an `expression_matrix` and a `network_graph`.

---

## [359] source=multitask_sft_big

**USER:** What outputs can I expect after executing the `piuma_seurat_integrated_tda` workflow on my single-cell dataset?

**ASSISTANT:** The `piuma_seurat_integrated_tda` workflow produces three outputs:
1. `cluster_assignments` (TDA-derived clusters)
2. `seurat_object` (the updated Seurat object containing integrated analysis results)
3. `summarizedexperiment` (a SummarizedExperiment representation of the data)

---

## [360] source=multitask_sft_big

**USER:** I need to perform virtual screening docking in drug discovery using AutoDock Vina. What workflow does BioMate provide and what are its inputs and outputs?

**ASSISTANT:** BioMate provides the `docking_autodock_vina` workflow (domain: `drug_discovery`) utilizing tool `DOCKING_AUTODOCK_VINA`.
- Inputs: `smiles_list`, `receptor_pdb_file`, `box_center`, `box_size`, `ncpu`, `exhaustiveness`, `n_poses`, `reference_ligand_smiles`, `randomSeed`
- Outputs: `pdbqt`

---

## [361] source=multitask_sft_big

**USER:** I have raw microbiome counts in a phyloseq S4 object. How can I perform differential abundance testing and visualize the results?

**ASSISTANT:** You can run the `phyloseq_differential_abundance_deseq2` workflow. It converts the phyloseq S4 object into a DESeq2 object, executes negative binomial differential abundance testing, and outputs a differential expression table (`de_table`), a differential abundance visualization (`differential_abundance`), and a `phylogenetic_tree`.

---

## [362] source=multitask_sft_big

**USER:** Can you summarize the architecture and dependencies of the drugTargetInteractions workflow for proteomics data?

**ASSISTANT:** The drugTargetInteractions workflow is tailored for proteomics. It accepts input count data via the 'input_files' slot and queries a local SQLite instance of the ChEMBL database to detect interactions between small molecules and gene/protein identifiers using Bioconductor tools ('bioconductor/drugtargetinteractions' and 'bioconductor/dt').

---

## [363] source=multitask_sft_big

**USER:** We want to analyze both differential gene expression and differential gene splicing together from transcript counts, aggregate to genes, and perform over-representation analysis. How does the pairedgsea workflow handle this?

**ASSISTANT:** The `pairedgsea` workflow (powered by `bioconductor/pairedgsea`) performs this pipeline:
1. Takes transcript-level counts (`counts.csv` with `'gene:transcript'` rownames) and sample metadata (`metadata.xlsx`).
2. Runs paired differential gene expression and differential gene splicing analyses.
3. Aggregates results to the gene level and conducts over-representation analysis.
4. Generates three output artifacts: `de_table`, `enrichment_results`, and `visualizations`.

---

## [364] source=multitask_sft_big

**USER:** Can you provide an overview of the tools and data features integrated into the nf-core/proteogenomicsdb workflow for proteogenomics database creation?

**ASSISTANT:** The nf-core/proteogenomicsdb (pgdb) workflow is built using Nextflow and pypgatk. It integrates tools and configuration modules including ensembl_downloader_config, ensembl_config, ensembl, add_reference, and gencode_url, and processes data types such as ncrna, pseudogenes, altorfs, and vcf to output proteogenomics protein databases.

---

