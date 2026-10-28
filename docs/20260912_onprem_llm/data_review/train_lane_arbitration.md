# TRAIN task: lane_arbitration  (1,027 instances)

## [0] source=multitask_sft_big

**USER:** Run a multi-factor differential expression analysis on my bulk RNA-seq read count matrix to assess the interaction between treatment (drug vs. vehicle) and genotype (wild-type vs. mutant) while controlling for sequencing batch effects.

**ASSISTANT:** cloud_workflow: Executing DESeq2 with multi-factor GLM fitting, dispersion estimation, and hypothesis testing on transcriptomic datasets requires an asynchronous cloud bioinformatic workflow.

---

## [1] source=multitask_sft_big

**USER:** Detect allele-specific transcription factor binding from ChIP-seq BAM files and heterozygous SNP calls while correcting for reference mapping bias and local copy-number variation.

**ASSISTANT:** cloud_workflow: BaalChIP requires multi-step processing of large aligned ChIP-seq BAM files and running iterative Bayesian modeling across genomic variants, necessitating distributed cloud compute.

---

## [2] source=multitask_sft_big

**USER:** Perform quality control, normalization, and batch effect inspection on GeoMx spatial transcriptomics raw count data using the standR pipeline.

**ASSISTANT:** cloud_workflow: Processing full spatial transcriptomics count matrices through standR involves multi-step data ingestion, filtering, and normalization workflows suited for containerized cloud execution.

---

## [3] source=multitask_sft_big

**USER:** Filter an existing RNA-seq SummarizedExperiment object for samples with high sequencing depth and generate a tidy ggplot visualizing marker gene expression across disease stages.

**ASSISTANT:** instant_compute: Manipulating and visualizing transcriptomic data with tidySummarizedExperiment is a lightweight R data wrangling and plotting task that runs quickly within an interactive execution environment without distributed cloud infrastructure.

---

## [4] source=multitask_sft_big

**USER:** Perform quality control, filtering, and out-of-core normalization on 500 Illumina MethylationEPIC array samples using the bigmelon pipeline to generate a clean beta-value matrix.

**ASSISTANT:** cloud_workflow: Processing hundreds of raw methylation array files requires scalable, memory-managed cloud pipeline execution to handle large data structures without out-of-memory errors.

---

## [5] source=multitask_sft_big

**USER:** Perform microbial signature over-representation analysis using BugSigDB on a list of differentially abundant gut bacterial species identified in my colorectal cancer study.

**ASSISTANT:** instant_compute: Querying BugSigDB signatures and computing taxonomic enrichment statistics is a lightweight R-based analytical task that executes within seconds without cloud orchestration.

---

## [6] source=multitask_sft_big

**USER:** Benchmark and select the best normalization and batch-correction pipeline for my single-cell RNA-seq expression matrix using data-driven evaluation metrics.

**ASSISTANT:** cloud_workflow: Evaluating and ranking a combinatorial suite of scRNA-seq normalization methods across QC metrics requires distributed, multi-step bioinformatics workflow execution on compute clusters.

---

## [7] source=multitask_sft_big

**USER:** Align and normalize feature profiles across multiple transcriptomic sample replicates using flagme to identify consistent differential peak patterns.

**ASSISTANT:** cloud_workflow: Executing the flagme processing pipeline involves compute-intensive multi-sample alignment and feature matching on large raw omics datasets, requiring asynchronous cloud workflow orchestration.

---

## [8] source=multitask_sft_big

**USER:** Perform fast gene set enrichment analysis (fgsea) on ranked differential expression gene lists from my RNA-seq dataset against the MSigDB Hallmark collection to identify enriched biological pathways.

**ASSISTANT:** cloud_workflow: Running fgsea requires executing a standardized Bioconductor computational pipeline against reference gene sets in a cloud environment.

---

## [9] source=multitask_sft_big

**USER:** Run comprehensive post-alignment RNA-seq quality control on mapped BAM files using RSeQC to assess strand specificity, junction saturation, and read genomic distribution.

**ASSISTANT:** cloud_workflow: Executing the nf-core/bam_rseqc Nextflow pipeline requires distributed compute resources to process heavy alignment files and run batch quality control modules.

---

## [10] source=multitask_sft_big

**USER:** Call germline single-nucleotide variants and small indels from an aligned whole-genome sequencing BAM file using DeepVariant.

**ASSISTANT:** cloud_workflow: DeepVariant is a computationally heavy genomic variant-calling pipeline that requires scalable cloud compute or GPU acceleration to process large read alignments into VCF files.

---

## [11] source=multitask_sft_big

**USER:** Impute dropout events and false zero values in my single-cell RNA-seq count matrix using ccImpute to improve downstream clustering and marker gene identification.

**ASSISTANT:** cloud_workflow: ccImpute is a bioinformatic transcriptomics pipeline that processes large single-cell matrices requiring distributed cloud compute resources.

---

## [12] source=multitask_sft_big

**USER:** Apply the opweight workflow to my RNA-seq differential expression test statistics to optimize p-value weights and enhance discovery power under 5% FDR control.

**ASSISTANT:** cloud_workflow: Executing optimal p-value weighting on large-scale transcriptomic datasets requires an asynchronous batch statistical pipeline with diagnostic model fitting and multiple testing adjustments.

---

## [13] source=multitask_sft_big

**USER:** Identify key transcriptional regulators driving differential expression between drug-treated and control RNA-seq samples using the RegEnrich pipeline on my count matrix and DESeq2 results.

**ASSISTANT:** cloud_workflow: RegEnrich involves a multi-step transcriptomics workflow that performs gene regulatory network inference and enrichment analysis on full gene expression datasets, requiring cloud infrastructure execution.

---

## [14] source=multitask_sft_big

**USER:** Perform differential methylation analysis between control and treated bisulfite sequencing samples to identify significant differentially methylated loci (DMLs) and regions (DMRs) using the DSS package.

**ASSISTANT:** cloud_workflow: Detecting DMLs and DMRs across genome-wide bisulfite sequencing data involves multi-step statistical modeling, dispersion shrinkage, and smoothing that require pipeline execution in a cloud compute environment.

---

## [15] source=multitask_sft_big

**USER:** Truncate the human GENCODE v44 GTF annotation to the 500 bp proximal to transcript poly(A) sites using txcutr to create an accurate reference for 3'-end single-cell RNA-seq quantification.

**ASSISTANT:** cloud_workflow: Building modified whole-transcriptome annotation models requires dedicated memory and containerized workflow execution on cloud infrastructure.

---

## [16] source=multitask_sft_big

**USER:** Quantify transposable element expression from my sorted RNA-seq BAM alignments using the atena package.

**ASSISTANT:** cloud_workflow: Processing high-throughput sequencing alignments for transposable element quantification requires memory and execution time best suited for a cloud workflow.

---

## [17] source=multitask_sft_big

**USER:** Run an integrated differential expression and methylation analysis on paired RNA-seq and methylation array profiles from patient tumor samples using the MEAL workflow.

**ASSISTANT:** cloud_workflow: Executing end-to-end multi-omic transcriptomics and epigenetic integration across multi-sample cohorts requires heavy pipeline orchestration and cloud compute.

---

## [18] source=multitask_sft_big

**USER:** Infer transcription factor-target gene regulatory networks and differential regulon activity from paired single-cell RNA-seq and ATAC-seq multiome datasets using epiregulon.

**ASSISTANT:** cloud_workflow: Inferring gene regulatory networks and TF activity from single-cell multiomic chromatin accessibility and expression data requires a multi-step, computationally intensive bioinformatics pipeline run on cloud infrastructure.

---

## [19] source=multitask_sft_big

**USER:** Process multiplexed RNA-seq and barcode sequencing data from an EpiDecoder screen to quantify epigenetic regulator binding affinities across targeted gene loci across multiple experimental conditions.

**ASSISTANT:** cloud_workflow: Running an end-to-end EpiDecoder processing pipeline involves multi-step cloud-based alignment, barcode demultiplexing, and quantitative enrichment calculations across large sequencing datasets.

---

## [20] source=multitask_sft_big

**USER:** Compare enriched Gene Ontology biological processes and KEGG pathways across four distinct gene clusters identified from a time-course RNA-seq experiment.

**ASSISTANT:** cloud_workflow: Performing multi-cluster functional enrichment analysis with clusterProfiler involves executing an asynchronous bioinformatics pipeline over user-provided genomic datasets against external biological annotation databases.

---

## [21] source=multitask_sft_big

**USER:** Screen and clean vector artifacts and foreign contaminant sequences from a draft genome assembly FASTA file using NCBI FCS-clean prior to public submission.

**ASSISTANT:** cloud_workflow: NCBI Foreign Contamination Screen (FCS) cleaning involves executing a containerized, compute-intensive bioinformatics workflow on large genome FASTA files.

---

## [22] source=multitask_sft_big

**USER:** Quantify differential histone mark enrichment and detect significant peak signals between patient and control ChIP-seq datasets using the CSSQ pipeline.

**ASSISTANT:** cloud_workflow: The CSSQ pipeline requires distributed high-throughput processing of large sequencing data files across multiple compute-intensive stages.

---

## [23] source=multitask_sft_big

**USER:** Align paired-end whole-genome sequencing FASTQ files to the GRCh38 reference genome to generate coordinate-sorted, deduplicated BAM files for downstream variant calling.

**ASSISTANT:** cloud_workflow: NGS read alignment on FASTQ data is a computationally intensive, multi-step pipeline requiring significant CPU, memory, and reference indexing that must be executed asynchronously in a cloud environment.

---

## [24] source=multitask_sft_big

**USER:** Execute the SpectraQL pipeline on my batch of single-cell RNA-seq FASTQ samples to perform transcript quantification, spectral decomposition of expression profiles, and cell-type cluster identification.

**ASSISTANT:** cloud_workflow: SpectraQL requires an asynchronous cloud workflow to handle the computationally intensive multi-step processing and spectral clustering of large transcriptomic sequencing datasets.

---

## [25] source=multitask_sft_big

**USER:** Run a 100 ns GPU-accelerated molecular dynamics simulation of the SARS-CoV-2 main protease complexed with an inhibitor using AMBER pmemd to evaluate binding stability and RMSD trajectories.

**ASSISTANT:** cloud_workflow: Full-scale molecular dynamics simulations using AMBER pmemd require long-running GPU cluster compute and automated stage orchestration typical of cloud workflows.

---

## [26] source=multitask_sft_big

**USER:** Perform neighborhood differential abundance testing on my single-cell RNA-seq dataset comparing treated and control samples using the MiloR framework.

**ASSISTANT:** cloud_workflow: MiloR involves intensive multi-step single-cell analysis including KNN graph neighborhood indexing, cell count aggregation, and GLM-based hypothesis testing on large expression datasets, requiring cloud pipeline execution.

---

## [27] source=multitask_sft_big

**USER:** Process raw Agilent Seahorse XFe96 respirometry data to perform quality control, normalize OCR and ECAR measurements against cell count, and calculate key bioenergetic parameters across experimental groups.

**ASSISTANT:** cloud_workflow: The seahtrue pipeline processes raw multi-well plate instrument files through multi-step parsing, normalization, and statistical analysis stages that require a containerized cloud workflow execution environment.

---

## [28] source=multitask_sft_big

**USER:** Run hypothesis testing using the hdtd package on my matrix-variate time-series RNA-seq expression dataset to test for equality of mean expression vectors and covariance structures across conditions.

**ASSISTANT:** instant_compute: The analysis consists of running statistical matrix tests in R on structured transcriptomic tables, which executes directly within an interactive computational runtime without requiring distributed cloud pipelines.

---

## [29] source=multitask_sft_big

**USER:** Identify transcription factor binding sites and determine spatial chromatin binding event positions from paired-end ChIP-seq BAM files using the PICS algorithm.

**ASSISTANT:** cloud_workflow: Running the PICS probabilistic peak-calling pipeline on high-throughput ChIP-seq alignment files requires distributed cloud compute and workflow orchestration to handle intensive I/O and statistical modeling.

---

## [30] source=multitask_sft_big

**USER:** Generate taxonomic abundance barplots and a PCoA ordination plot from my microbiome TreeSummarizedExperiment object using miaViz.

**ASSISTANT:** instant_compute: Visualizing microbiome profiling data and ordination plots with miaViz is a lightweight R-based computation that executes rapidly in an interactive compute environment.

---

## [31] source=multitask_sft_big

**USER:** Perform a multiple sequence alignment of orthologous transcript isoforms for the human, mouse, and rat TP53 genes to identify conserved splice sites and sequence variations.

**ASSISTANT:** cloud_workflow: Executing standard multiple sequence alignment tools like MAFFT or Clustal Omega on multi-sequence FASTA files requires batch command-line bioinformatics tooling orchestrated via a cloud workflow.

---

## [32] source=multitask_sft_big

**USER:** Perform differential gene expression analysis with MAST on single-cell RNA-seq count data comparing stimulated versus control T cells, controlling for cellular detection rate.

**ASSISTANT:** cloud_workflow: MAST differential expression analysis on single-cell transcriptomics matrices is computationally intensive and requires distributed cloud workflow infrastructure to process thousands of cells and genes asynchronously.

---

## [33] source=multitask_sft_big

**USER:** Construct and analyze synteny networks across ten angiosperm genomes to identify conserved collinear gene blocks and evolutionary duplication events using syntenet.

**ASSISTANT:** cloud_workflow: Multi-genome synteny network inference requires multi-step, computationally intensive sequence alignment and collinearity detection best suited for cloud-based pipeline execution.

---

## [34] source=multitask_sft_big

**USER:** Perform Cepo differential stability analysis on a large-scale atlas-level scRNA-seq dataset using parallel processing and out-of-memory disk backing to identify cell-type-specific identity genes without exhausting local RAM.

**ASSISTANT:** cloud_workflow: Parallelized out-of-memory differential stability computations on massive transcriptomic datasets require dedicated cloud infrastructure and batch workflow orchestration.

---

## [35] source=multitask_sft_big

**USER:** Identify and filter out anomalous or divergent outlier sequences from a multiple sequence alignment of homologous kinase domains using ODseq.

**ASSISTANT:** cloud_workflow: ODseq runs bootstrap-based distance matrix computations across large alignments as an asynchronous bioinformatics pipeline best suited for cloud workflow execution.

---

## [36] source=multitask_sft_big

**USER:** Run the rmspc workflow on my replicate peak files with stringent p-value thresholds to identify reproducible consensus enrichment regions across biological replicates.

**ASSISTANT:** cloud_workflow: The rmspc pipeline processes multiple replicate genomic datasets through statistical peak-calling evaluation, requiring dedicated batch compute resources typical of cloud workflows.

---

## [37] source=multitask_sft_big

**USER:** Visualize genome-wide differential gene expression across chromosomal coordinates by generating a chromosome heatmap from my RNA-seq dataset.

**ASSISTANT:** cloud_workflow: Generating chromosome-level heatmaps requires executing a multi-step bioinformatics workflow mapping genomic annotations to expression data on cloud compute infrastructure.

---

## [38] source=multitask_sft_big

**USER:** Evaluate and compare normalization methods and perform differential expression analysis on an RNA-seq expression matrix comparing treated versus control samples.

**ASSISTANT:** cloud_workflow: NormalyzerDE is a bioinformatics pipeline that benchmarks multiple normalization algorithms and runs differential expression analysis on high-throughput omics matrices, requiring automated cloud workflow execution.

---

## [39] source=multitask_sft_big

**USER:** Segment subbasal corneal nerves from a batch of in vivo confocal microscopy (IVCM) images to calculate corneal nerve fiber length (CNFL), branch density (CNBD), and total tortuosity for evaluating diabetic neuropathy progression.

**ASSISTANT:** cloud_workflow: Automating trace segmentation and morphometric parameter extraction across batches of high-resolution microscopy images requires an asynchronous, multi-step cloud-based image analysis pipeline.

---

## [40] source=multitask_sft_big

**USER:** Predict genome-wide transcriptional expression changes in K562 single-cell RNA-seq data following combinatorial CRISPR perturbations of TP53 and PTEN using GEARS.

**ASSISTANT:** cloud_models: Running GEARS requires executing a GPU-accelerated graph neural network model to infer single-cell transcriptomic perturbations, classifying it under cloud_models.

---

## [41] source=multitask_sft_big

**USER:** Run a GOstats hypergeometric enrichment analysis on my differentially expressed gene list from an unsupported organism using a custom gene-to-GO association table.

**ASSISTANT:** cloud_workflow: This task entails executing a multi-step R/Bioconductor statistical pipeline requiring data upload, environment setup, and batch computational execution in the cloud.

---

## [42] source=multitask_sft_big

**USER:** Process and demultiplex raw FASTQ files from a Parse Biosciences SPLiT-seq single-cell RNA-seq library to generate a gene expression count matrix.

**ASSISTANT:** cloud_workflow: Processing raw single-cell sequencing FASTQ reads through split-pool barcode parsing, read alignment, and UMI deduplication requires multi-step, computationally intensive cloud pipelines.

---

## [43] source=multitask_sft_big

**USER:** Cluster genes and samples from a normalized RNA-seq expression matrix using the HOPACH algorithm to identify ordered, hierarchically structured expression subclusters.

**ASSISTANT:** cloud_workflow: HOPACH is a computationally intensive transcriptomic clustering pipeline that requires cloud-based execution to process high-dimensional expression matrices.

---

## [44] source=multitask_sft_big

**USER:** Parse a multi-gigabyte L1000 GCTX matrix to extract and analyze perturbational gene expression signatures for specific drug treatments across multiple cancer cell lines.

**ASSISTANT:** cloud_workflow: Manipulating and slicing high-dimensional GCTX expression datasets with cmapR requires an orchestrated cloud bioinformatics environment with sufficient memory and storage.

---

## [45] source=multitask_sft_big

**USER:** Calculate the master mix recipe and standard thermal cycling conditions for amplifying a 1.2 kb DNA fragment using Phusion High-Fidelity DNA Polymerase in a 50 µL reaction.

**ASSISTANT:** instant_compute: Determining PCR reagent concentrations, reaction volumes, and baseline cycling parameters relies on straightforward deterministic calculations that execute instantaneously.

---

## [46] source=multitask_sft_big

**USER:** Perform differential expression analysis on NanoString nCounter count data between treated and control patient samples using positive spike-in and housekeeping gene normalization.

**ASSISTANT:** cloud_workflow: Processing raw NanoString data through NanoStringDiff involves multi-step statistical normalization and differential testing across experimental cohorts executed as a containerized bioinformatics workflow.

---

## [47] source=multitask_sft_big

**USER:** Retrieve raw FASTQ files and run metadata for BioProject accession PRJNA634567 from public repositories to prepare input files for an RNA-seq pipeline.

**ASSISTANT:** cloud_workflow: nf-core/fetchngs is a standard Nextflow workflow that automates the downloading and verification of large sequencing datasets from public archives across cloud infrastructure.

---

## [48] source=multitask_sft_big

**USER:** Align and quantify paired-end 10x Genomics Chromium scRNA-seq FASTQ samples from mouse brain tissue to produce cell-by-gene expression matrices and QC metrics using STARSolo.

**ASSISTANT:** cloud_workflow: Running the nf-core/scrnaseq Nextflow pipeline requires significant computational resources for genome indexing, barcode demultiplexing, and read alignment, making it an asynchronous cloud workflow.

---

## [49] source=multitask_sft_big

**USER:** Retrieve functional Gene Ontology terms and PubMed references for a list of differentially expressed Affymetrix HG-U133 Plus 2.0 probe sets using annaffy.

**ASSISTANT:** instant_compute: Querying Bioconductor annotation environments and compiling metadata tables for microarray probe sets is lightweight and completes within seconds.

---

## [50] source=multitask_sft_big

**USER:** Load the Ivy Glioblastoma Atlas Project (Ivy GAP) SummarizedExperiment dataset to analyze differential gene expression across anatomical glioblastoma structures.

**ASSISTANT:** instant_compute: Retrieving and analyzing a pre-packaged Bioconductor SummarizedExperiment container requires interactive R scripting and lightweight exploratory compute rather than heavy distributed pipelines or specialized GPU models.

---

## [51] source=multitask_sft_big

**USER:** Estimate genome-wide somatic epimutation rates (alpha and beta) across multiple generations of clonally propagated lineages using whole-genome bisulfite sequencing data.

**ASSISTANT:** cloud_workflow: Quantifying somatic epimutation rates from clonal methylation profiles requires executing a multi-step, computationally intensive bioinformatics pipeline on cloud infrastructure.

---

## [52] source=multitask_sft_big

**USER:** Normalize intensity and remove background noise from a 3-channel confocal fluorescence microscopy z-stack using flat-field correction and median filtering.

**ASSISTANT:** cloud_workflow: Microscopy image preprocessing involves running multi-step filtering and transformation pipelines on large image datasets using containerized cloud compute.

---

## [53] source=multitask_sft_big

**USER:** Process raw paired-end CUT&RUN sequencing FASTQ files targeting H3K27ac in human cells to perform read trimming, alignment against hg38, SEACR peak calling, and bigWig coverage track generation.

**ASSISTANT:** cloud_workflow: The nf-core/cutandrun pipeline is a multi-step Nextflow workflow requiring scalable cloud compute and storage infrastructure for parallel alignment, deduplication, and peak calling on large NGS datasets.

---

## [54] source=multitask_sft_big

**USER:** Run the CytoKernel pipeline on our single-cell RNA-seq count matrix to calculate cell neighborhood kernels, identify functional sub-clusters, and infer cell-cell interaction scores.

**ASSISTANT:** cloud_workflow: Cytokernel is a multi-step single-cell transcriptomics analysis pipeline that requires cloud-based distributed compute to process high-dimensional cellular matrices and calculate graph kernels.

---

## [55] source=multitask_sft_big

**USER:** Identify differentially active transcription factors between stimulated and resting CD8+ T cells by running transcription factor enrichment analysis on paired ATAC-seq BAM files and consensus peak calls.

**ASSISTANT:** cloud_workflow: Executing an ATAC-seq transcription factor enrichment pipeline requires multi-step, resource-intensive processing of large sequencing data files via an orchestrated cloud execution environment.

---

## [56] source=multitask_sft_big

**USER:** Construct a 3D affine transformation matrix to correct for sample drift across imaging channels, applying a 12-degree rotation around the Z-axis, uniform scaling of 1.02, and an offset of (14, -8, 2) voxels.

**ASSISTANT:** instant_compute: Constructing an affine transformation matrix from defined geometric parameters is a deterministic, lightweight mathematical calculation that runs instantly in the local session.

---

## [57] source=multitask_sft_big

**USER:** Run quality control metrics, normalization, and differential expression analysis on an isobaric TMT-16plex quantitative proteomics dataset comparing drug-treated and control cell lines.

**ASSISTANT:** cloud_workflow: Analyzing multiplexed isobaric labeling proteomics data involves multi-step preprocessing, normalization, and statistical modeling that require a dedicated bioinformatics pipeline execution environment.

---

## [58] source=multitask_sft_big

**USER:** I have mapped BAM files containing UMI tags and need to deduplicate reads based on UMI barcodes using UMI-tools, followed by indexing and calculating alignment statistics using Samtools.

**ASSISTANT:** cloud_workflow: Deduplicating and indexing large genomic alignment BAM files involves compute-intensive bioinformatics pipelines that require asynchronous cloud execution.

---

## [59] source=multitask_sft_big

**USER:** Query and import somatic mutation and clinical data for the TCGA-LUAD cohort from Terra workspaces into a cloud execution environment for downstream survival analysis.

**ASSISTANT:** cloud_workflow: Accessing and processing large-scale TCGA cohorts on the Terra platform requires asynchronous cloud infrastructure and pipeline orchestration.

---

## [60] source=multitask_sft_big

**USER:** Transfer a biological interaction network from igraph to Cytoscape using RCy3 to apply custom visual styles and extract network centrality metrics back into R for downstream analysis.

**ASSISTANT:** instant_compute: This task consists of executing lightweight R scripts to interconvert network data structures and calculate graph statistics without requiring heavy multi-node cloud pipelines or specialized hardware.

---

## [61] source=multitask_sft_big

**USER:** Run a step-by-step clustering analysis on my normalized single-cell RNA-seq count matrix using clusterExperiment to identify stable sub-populations through subsampling and cluster merging.

**ASSISTANT:** cloud_workflow: This task involves executing a multi-step transcriptomic clustering workflow on high-dimensional single-cell data requiring cloud compute infrastructure.

---

## [62] source=multitask_sft_big

**USER:** Analyze genome-wide fragment length distributions and end-motif fragmentation profiles from patient cell-free DNA paired-end BAM files to assess tumor-derived cfDNA biomarkers.

**ASSISTANT:** cloud_workflow: Extracting fragmentomic features from large paired-end sequencing BAM files requires heavy data I/O and scalable distributed compute suited for cloud genomic workflows.

---

## [63] source=multitask_sft_big

**USER:** Generate standard Bioconductor package infrastructure, documentation scaffolding, and GitHub Actions CI/CD configuration files for my R package.

**ASSISTANT:** instant_compute: Scaffolding R package files and configuring CI workflows with biocthis is a lightweight automation task that executes in seconds on local compute.

---

## [64] source=multitask_sft_big

**USER:** Design an optimized multiplex PCR primer set targeting conserved regions across 15 divergent dengue virus genomes while minimizing primer-dimer formation and cross-reactivity.

**ASSISTANT:** cloud_design: Multiplex primer generation across multiple viral genomes requires multi-objective thermodynamic optimization and combinatorial screening suitable for a cloud design workflow.

---

## [65] source=multitask_sft_big

**USER:** Impute missing CpG site methylation levels across a batch of low-coverage whole-genome bisulfite sequencing (WGBS) samples using methylimp2.

**ASSISTANT:** cloud_workflow: Imputation across genome-scale DNA methylation matrices requires significant memory and distributed batch compute typically orchestrated via cloud execution.

---

## [66] source=multitask_sft_big

**USER:** Annotate newly assembled bacteriophage contigs from a wastewater metagenome sample to identify structural genes, lysins, and taxonomic classification using nf-core/phageannotator.

**ASSISTANT:** cloud_workflow: nf-core/phageannotator is a Nextflow bioinformatics pipeline requiring multi-step tool orchestration and database querying that runs on distributed cloud or HPC infrastructure.

---

## [67] source=multitask_sft_big

**USER:** Identify differential exon usage between knock-down and wild-type samples using my preprocessed HTSeq exon count files and sample annotation table.

**ASSISTANT:** cloud_workflow: Fitting DEXSeq negative binomial generalized linear models across thousands of exons and biological replicates requires a multi-step, resource-intensive cloud pipeline execution.

---

## [68] source=multitask_sft_big

**USER:** Screen a large set of microbial protein FASTA files against custom profile HMMs to identify and rank candidate biosynthetic gene cluster enzymes.

**ASSISTANT:** cloud_workflow: This is an nf-core Nextflow data-processing pipeline that performs multi-sample HMMER searches and ranking, requiring scalable cloud compute infrastructure.

---

## [69] source=multitask_sft_big

**USER:** Perform a methylome-wide association study (MWAS) on a cohort of MBD-seq BAM files to identify differentially methylated regions associated with clinical traits while adjusting for principal components and covariates.

**ASSISTANT:** cloud_workflow: RamWAS requires multi-step, computationally demanding batch processing of large sequencing BAM files for alignment evaluation, methylation score estimation, and association modeling across high-throughput genomic cohorts.

---

## [70] source=multitask_sft_big

**USER:** Identify differentially expressed isoforms between control and drug-treated breast cancer samples from RSEM-generated isoform abundance matrices using EBSeq.

**ASSISTANT:** cloud_workflow: EBSeq isoform differential expression analysis requires statistical modeling across replicates on cloud infrastructure with specific R/Bioconductor toolchains and large expression matrices.

---

## [71] source=multitask_sft_big

**USER:** Simulate single-cell RNA-seq count matrices across 25 synthetic donor individuals incorporating eQTL effects, cell-type heterogeneity, and sample-level batch variation to benchmark population-scale scRNA-seq analysis tools.

**ASSISTANT:** cloud_workflow: Generating multi-individual population-scale single-cell transcriptomic data with complex genetic and technical variance structures requires asynchronous cloud-based pipeline execution.

---

## [72] source=multitask_sft_big

**USER:** Generate metaplots and heatmaps of RNA-seq signal coverage around transcript start sites and exon-intron boundaries from bigWig files using the GenomicPlot package.

**ASSISTANT:** cloud_workflow: Processing and summarizing large bigWig and genomic annotation files for multi-gene coverage visualization requires cloud-scale computing and dedicated workflow orchestration.

---

## [73] source=multitask_sft_big

**USER:** Retrieve the protein-protein interaction network and functional enrichment results for a list of DNA repair proteins (TP53, BRCA1, ATM, CHEK2, RAD51).

**ASSISTANT:** instant_compute: Querying the STRING database API for interaction scores and pathway enrichment is a lightweight, low-latency computational retrieval task that executes in seconds without heavy cloud infrastructure.

---

## [74] source=multitask_sft_big

**USER:** Run the nf-core/molkart pipeline to perform cell segmentation and assign transcript spots on my Resolve Biosciences Molecular Cartography spatial imaging data.

**ASSISTANT:** cloud_workflow: nf-core/molkart is an end-to-end Nextflow processing pipeline requiring scalable cloud infrastructure for spatial transcriptomics image segmentation and spot assignment.

---

## [75] source=multitask_sft_big

**USER:** Generate a high-density scatter plot with distinctive hatching patterns using scatterhatch to clearly visualize overlapping cell types in my spatial transcriptomics coordinate data.

**ASSISTANT:** instant_compute: Rendering a visualization with scatterhatch is a lightweight, script-driven plotting task that can be computed and returned in seconds.

---

## [76] source=multitask_sft_big

**USER:** Undo the last quality control filtering step on my single-cell RNA-seq AnnData object to restore the previous cell count matrix.

**ASSISTANT:** instant_compute: Restoring a prior in-memory session state or checkpoint after an interactive filtering operation is a lightweight, deterministic execution that runs immediately without cloud cluster scheduling.

---

## [77] source=multitask_sft_big

**USER:** Correct batch effects across multi-batch RNA-seq data stored in a SummarizedExperiment object where subtype identities are unknown using BUScorrect.

**ASSISTANT:** cloud_workflow: Executing batch-effect correction via BUScorrect on high-dimensional transcriptomics datasets requires running a multi-step, computationally intensive R/Bioconductor analysis pipeline in the cloud.

---

## [78] source=multitask_sft_big

**USER:** Profile promoter-level epigenetic enrichment and integrate ChIP-seq and RNA-seq datasets to analyze chromatin marks across differentially expressed genes.

**ASSISTANT:** cloud_workflow: Processing high-throughput sequencing alignments to calculate coverage profiles and aggregate enrichment scores across genomic features requires multi-step workflow execution on scalable cloud compute.

---

## [79] source=multitask_sft_big

**USER:** Run quantitative gene set analysis with QuSAGE on normalized microarray expression data comparing baseline and post-vaccination patient samples against the MSigDB Hallmark gene sets to identify significantly modulated immune pathways.

**ASSISTANT:** cloud_workflow: Executing QuSAGE requires containerized Bioconductor pipeline infrastructure to compute numeric variance convolutions across multi-sample transcriptomic matrices and comprehensive gene set collections.

---

## [80] source=multitask_sft_big

**USER:** Process raw NanoString nCounter RCC gene expression files and metadata to perform quality control, normalization, and differential expression analysis across experimental cohorts.

**ASSISTANT:** cloud_workflow: nf-core/nanostring is a multi-step Nextflow pipeline for processing raw NanoString data that requires distributed cloud infrastructure for execution.

---

## [81] source=multitask_sft_big

**USER:** Analyze the combinatorial occupancy patterns of ChIP-seq histone marks and transcription factor binding peaks across promoter regions using the genomation package.

**ASSISTANT:** cloud_workflow: Quantifying and clustering multi-track genomic feature intersections across large BED and BigWig datasets requires execution in a distributed cloud workflow environment.

---

## [82] source=multitask_sft_big

**USER:** Visualize genomic BAM alignments and narrowPeak ChIP-seq tracks around the human TP53 locus using an interactive igvR session in R.

**ASSISTANT:** instant_compute: igvR executes lightweight R scripts to initialize and control an interactive genome browser session without requiring heavy batch cloud infrastructure.

---

## [83] source=multitask_sft_big

**USER:** Identify candidate synthetic lethal partners for KRAS in non-small cell lung cancer by integrating patient RNA-seq profiles with functional dependency screens.

**ASSISTANT:** cloud_workflow: Predicting synthetic lethal interactions requires multi-step integration and intensive statistical scoring across large transcriptomic and screening datasets, necessitating an orchestrated cloud pipeline.

---

## [84] source=multitask_sft_big

**USER:** Simulate synthetic bulk RNA-seq datasets with predefined cell-type fractions from a single-cell RNA-seq reference to benchmark deconvolution algorithms.

**ASSISTANT:** cloud_workflow: Generating synthetic bulk profiles from high-dimensional single-cell count matrices requires multi-step sampling and significant memory, making it best suited for asynchronous cloud workflow execution.

---

## [85] source=multitask_sft_big

**USER:** Derive and validate a prognostic gene expression signature from preprocessed bulk RNA-seq data of triple-negative breast cancer patients to predict response to neoadjuvant chemotherapy.

**ASSISTANT:** cloud_workflow: Extracting and validating multi-gene transcriptomic signatures across large patient cohorts requires orchestrated multi-step differential expression, feature selection, and survival analysis pipelines executed on scalable cloud infrastructure.

---

## [86] source=multitask_sft_big

**USER:** Run incremental PCA and non-negative matrix factorization on a large-scale single-cell RNA-seq expression matrix using BiocSklearn to identify major cell subpopulation signatures.

**ASSISTANT:** cloud_workflow: Processing high-dimensional omics count matrices with machine learning decomposition methods requires distributed memory and scalable cloud compute infrastructure.

---

## [87] source=multitask_sft_big

**USER:** Run the inpower variant calling pipeline across a cohort of whole-exome sequencing FASTQ samples to detect low-frequency germline variants and assess statistical discovery power.

**ASSISTANT:** cloud_workflow: This task requires distributed, long-running batch compute across multi-sample sequencing datasets managed through a scalable cloud workflow engine.

---

## [88] source=multitask_sft_big

**USER:** Infer a metabolite correlation and structural network from untargeted LC-MS/MS feature tables to identify altered metabolic subnetworks between experimental conditions.

**ASSISTANT:** cloud_workflow: Constructing and analyzing comprehensive metabolic networks from high-dimensional metabolomics datasets involves multi-step statistical inference, spectral matching, and graph topology analysis suitable for cloud pipeline orchestration.

---

## [89] source=multitask_sft_big

**USER:** Identify and flag outlier microarrays from an AffyBatch object containing raw Affymetrix expression data before downstream normalization and analysis.

**ASSISTANT:** cloud_workflow: Detecting multivariate outliers from high-dimensional Affymetrix microarray batches requires executing a multi-step quality control pipeline in an R environment on cloud infrastructure.

---

## [90] source=multitask_sft_big

**USER:** Estimate genomic saturation and the number of unobserved genes from transposon insertion count data in a bacterial mutagenesis experiment.

**ASSISTANT:** instant_compute: Fitting statistical occupancy and multinomial distribution models with the occugene R package involves lightweight numerical optimization on count data that finishes in seconds within interactive compute environments.

---

## [91] source=multitask_sft_big

**USER:** Process a batch of multiplexed mass cytometry (CyTOF) FCS files to perform automated continuous debarcoding, background subtraction, and sample-level quality control using flowSpecs.

**ASSISTANT:** cloud_workflow: Batch debarcoding and multi-step quality preprocessing of cytometry FCS files requires distributed file I/O and pipeline orchestration suitable for a cloud workflow.

---

## [92] source=multitask_sft_big

**USER:** Perform statistical testing for allelic imbalance and dynamic seesaw patterns across RNA-seq samples using fishpond and inferential replicate quantifications.

**ASSISTANT:** cloud_workflow: Testing allelic imbalance across multi-sample transcriptomics data with inferential replicates requires running a specialized computational pipeline suited for cloud workflow execution.

---

## [93] source=multitask_sft_big

**USER:** Perform phenotype association testing and gene set enrichment analysis on a normalized gene expression dataset across multiple clinical variables using the phenoTest package.

**ASSISTANT:** cloud_workflow: Associating genome-wide expression profiles with multiple patient phenotypes and evaluating downstream pathway enrichment requires an orchestrated multi-step bioinformatics pipeline on cloud compute.

---

## [94] source=multitask_sft_big

**USER:** Perform statistical analysis to test for differences in cell type proportions across disease cohorts in my single-cell RNA-seq dataset using speckle's linear modeling and ANOVA.

**ASSISTANT:** cloud_workflow: Fitting linear models and performing ANOVA across cell type abundance matrices requires executing a dedicated R/Bioconductor statistical pipeline on cloud infrastructure.

---

## [95] source=multitask_sft_big

**USER:** Predict transcriptional synergy and perturbation responses for combinations of oncology drugs across my single-cell RNA-seq dataset using a Compositional Perturbation Autoencoder model.

**ASSISTANT:** cloud_models: The CPA framework requires specialized GPU resources to train neural networks and infer high-dimensional single-cell perturbation responses for combinatorial drug screening.

---

## [96] source=multitask_sft_big

**USER:** Perform self-organizing map (SOM) clustering and functional gene set enrichment analysis on a bulk RNA-seq count matrix to identify distinct tumor molecular subtypes.

**ASSISTANT:** cloud_workflow: Running oposSOM involves intensive unsupervised machine learning and extensive downstream reporting on high-dimensional transcriptomics data, requiring batch cloud workflow execution.

---

## [97] source=multitask_sft_big

**USER:** Delineate genomic zones of co-expressed genes across chromosomes from a cohort tumor RNA-seq expression matrix.

**ASSISTANT:** cloud_workflow: Genome-wide segmentation regression and zone delineation across large transcriptomic matrices require high-throughput bioinformatics pipeline execution in the cloud.

---

## [98] source=multitask_sft_big

**USER:** Assess the library quality and fragment size distribution of my paired-end ATAC-seq BAM files, including calculating TSS enrichment scores and mitochondrial contamination rates across samples.

**ASSISTANT:** cloud_workflow: ATAC-seq quality control requires high-throughput genomic data processing and signal matrix computation on large alignment files, necessitating execution via a cloud bioinformatics pipeline.

---

## [99] source=multitask_sft_big

**USER:** Run the SGCP pipeline on raw single-cell RNA-seq FASTQ files to perform read alignment, barcode demultiplexing, UMI counting, and generate quality-controlled gene expression matrices.

**ASSISTANT:** cloud_workflow: Processing high-throughput single-cell transcriptomic sequencing reads through multi-step alignment and quantification workflows requires dedicated, scalable cloud computing resources.

---

## [100] source=multitask_sft_big

**USER:** Identify transcript usage quantitative trait loci (tuQTLs) across 120 RNA-seq samples by testing associations between phased genotype variants and transcript-level Dirichlet-multinomial usage proportions using DRIMSeq.

**ASSISTANT:** cloud_workflow: Fitting per-gene Dirichlet-multinomial models across genome-wide SNP variants and multi-sample transcript count matrices requires high-throughput cloud workflow orchestration.

---

## [101] source=multitask_sft_big

**USER:** Identify novel alternative polyadenylation (APA) sites and quantify 3' UTR switching from paired tumor-normal RNA-seq BAM files.

**ASSISTANT:** cloud_workflow: InPAS performs compute-intensive processing of large genome-wide RNA-seq coverage tracks and statistical testing for 3' UTR length shifts, requiring distributed cloud pipeline execution.

---

## [102] source=multitask_sft_big

**USER:** Analyze TCGA breast invasive carcinoma RNA-seq cohorts using the bioCancer pipeline to identify differentially expressed genes, survival-associated biomarkers, and enriched oncogenic pathways.

**ASSISTANT:** cloud_workflow: Executing end-to-end cancer transcriptomics workflows on large patient cohorts requires multi-step automated pipelines and scalable cloud compute environments.

---

## [103] source=multitask_sft_big

**USER:** Identify differential m/z features between annotated tumor and normal tissue regions in my mass spectrometry imaging imzML dataset using Cardinal.

**ASSISTANT:** cloud_workflow: Running spatial class comparison on high-dimensional mass spectrometry imaging data requires a multi-step bioinformatic workflow executed on distributed cloud infrastructure.

---

## [104] source=multitask_sft_big

**USER:** Integrate matched single-cell RNA-seq and surface protein ADT count matrices from a CITE-seq experiment using NIPALS multiple co-inertia analysis (MCIA) to identify shared multi-modal dimensions.

**ASSISTANT:** cloud_workflow: Multimodal single-cell integration via NIPALS MCIA requires an intensive multi-step bioinformatics pipeline executing on cloud infrastructure.

---

## [105] source=multitask_sft_big

**USER:** Generate a high-resolution 2D Hilbert curve visualization of ChIP-seq coverage profiles across human chromosome 1 to inspect genome-wide signal distribution and focal enrichment.

**ASSISTANT:** cloud_workflow: Processing full-chromosome sequencing coverage vectors into multi-scale Hilbert curves requires memory-intensive genomic data handling suitable for cloud workflow execution.

---

## [106] source=multitask_sft_big

**USER:** Download and execute the standard GDC mRNA-seq alignment and quantification pipeline on TCGA lung adenocarcinoma whole-transcriptome sequencing samples to generate normalized gene expression matrices.

**ASSISTANT:** cloud_workflow: Processing large-scale cohort raw sequencing data through standard bioinformatics alignment and quantification pipelines requires distributed, long-running cloud workflow orchestration.

---

## [107] source=multitask_sft_big

**USER:** Phase heterozygous variants in a cohort whole-genome VCF file using SHAPEIT5 and a phased reference haplotype panel.

**ASSISTANT:** cloud_workflow: Haplotype phasing of large VCF datasets using SHAPEIT5 is computationally intensive and requires distributed cloud infrastructure to execute efficiently.

---

## [108] source=multitask_sft_big

**USER:** Run quality control and preprocessing on a single-cell RNA-seq count matrix using scater to compute QC metrics, filter low-quality cells, and generate PCA/t-SNE diagnostic plots.

**ASSISTANT:** cloud_workflow: Preprocessing and QC filtering of single-cell RNA-seq datasets involves a multi-step bioinformatic pipeline requiring dedicated cloud compute resources.

---

## [109] source=multitask_sft_big

**USER:** Extract, error-correct, and quantify lineage-tracing cell barcodes from raw paired-end FASTQ reads to track clonal dynamics in single-cell transcriptomics data.

**ASSISTANT:** cloud_workflow: Processing large-scale sequencing FASTQ files for barcode extraction and error-correction requires a distributed, multi-step bioinformatics pipeline on cloud infrastructure.

---

## [110] source=multitask_sft_big

**USER:** Run a population PBPK simulation using Simcyp to evaluate the systemic exposure and CYP3A4-mediated drug-drug interaction risk of candidate lead molecule BM-409 co-administered with ketoconazole.

**ASSISTANT:** cloud_workflow: Simcyp population-based PBPK modeling involves intensive ODE integration across hundreds of virtual subjects and physiological compartments, requiring a dedicated cloud workflow execution.

---

## [111] source=multitask_sft_big

**USER:** Compare the signal profiles of my histone modification ChIP-seq peaks between treatment and control replicates using similarpeak to quantify profile concordance across genomic regions.

**ASSISTANT:** cloud_workflow: Evaluating signal track similarity across genomic peak regions requires multi-step processing of genomic data files in a cloud bioinformatics workflow environment.

---

## [112] source=multitask_sft_big

**USER:** Perform linear model-based gene set enrichment analysis on normalized gene expression data to identify significantly enriched pathways associated with disease severity while adjusting for patient age and batch covariates.

**ASSISTANT:** cloud_workflow: Evaluating multi-covariate linear models with permutation-based significance testing across large transcriptomic matrices requires execution in a specialized cloud pipeline environment.

---

## [113] source=multitask_sft_big

**USER:** Evaluate the reproducibility of chromatin loop calls across two biological HiChIP replicates and filter high-confidence interactions using the idr2d pipeline.

**ASSISTANT:** cloud_workflow: Calculating two-dimensional irreproducible discovery rates on genomic contact replicates involves compute-intensive bioinformatic data processing that requires containerized cloud workflow execution.

---

## [114] source=multitask_sft_big

**USER:** Evaluate replicate reproducibility and identify high-confidence concordant features across biological replicates from an RNA-seq expression matrix using MARR.

**ASSISTANT:** cloud_workflow: Running the MARR reproducibility pipeline on high-throughput transcriptomic replicate profiles requires multi-step computational processing on cloud workflow infrastructure.

---

## [115] source=multitask_sft_big

**USER:** Cluster genomic copy number profiles from array CGH data across a patient tumor cohort to identify distinct recurrent aberration subtypes.

**ASSISTANT:** cloud_workflow: Processing and hierarchically clustering high-dimensional multi-sample array CGH profiles requires a multi-step genomic pipeline executed via a distributed cloud workflow.

---

## [116] source=multitask_sft_big

**USER:** Identify transcriptional regulatory modules and associated transcription factor binding targets from differential RNA-seq expression data integrated with protein-protein interaction networks.

**ASSISTANT:** cloud_workflow: Reconstructing transcriptional regulatory modules involves multi-step network integration, optimization, and enrichment analysis across large-scale transcriptomic and interactome datasets.

---

## [117] source=multitask_sft_big

**USER:** Generate novel core scaffolds to replace the quinazoline core of Gefitinib to bypass IP restrictions while maintaining key hinge-binding pharmacophore features against EGFR.

**ASSISTANT:** cloud_design: Scaffold hopping requires generative molecular design models and 3D pharmacophore-constrained optimization that require asynchronous cloud execution.

---

## [118] source=multitask_sft_big

**USER:** Standardize and correct ambiguous sample metadata annotations in my transcriptomic SummarizedExperiment object using a fine-tuned biomedical BERT model.

**ASSISTANT:** cloud_workflow: This task requires an asynchronous cloud workflow to handle multi-step ingestion, processing of Bioconductor SummarizedExperiment objects, and model-based metadata harmonization.

---

## [119] source=multitask_sft_big

**USER:** Run germline small variant calling on human whole-genome sequencing BAM files mapped to GRCh38 using DeepVariant.

**ASSISTANT:** cloud_workflow: This is a production nf-core Nextflow pipeline that requires distributed cloud infrastructure and substantial compute resources to process sequencing reads through deep learning models.

---

## [120] source=multitask_sft_big

**USER:** Run quality control and generate sequencing summary reports on raw basecalled FASTQ files from our latest Oxford Nanopore PromethION sequencing run.

**ASSISTANT:** cloud_workflow: Basecall quality control requires compute- and I/O-intensive bioinformatic pipeline processing on large raw sequencing datasets in a scalable cloud environment.

---

## [121] source=multitask_sft_big

**USER:** Convert peptide-spectrum match identification results from a large pepXML file into a tab-delimited text format for downstream statistical filtering and analysis.

**ASSISTANT:** cloud_workflow: Parsing and converting substantial mass spectrometry search output files like pepXML requires batch processing via asynchronous cloud workflow execution.

---

## [122] source=multitask_sft_big

**USER:** Filter peptide-spectrum matches from LC-MS/MS mzIdentML files using MSnID to achieve an optimized 1% peptide- and protein-level false discovery rate.

**ASSISTANT:** cloud_workflow: MSnID involves intensive statistical filtering and score-optimization workflows on large proteomics identification files that require cloud-based batch pipeline execution.

---

## [123] source=multitask_sft_big

**USER:** Generate a custom 50 kbp bin annotation file for the GRCh38 human reference genome incorporating GC content and mappability tracks for low-pass WGS copy number profiling in QDNAseq.

**ASSISTANT:** cloud_workflow: Calculating genome-wide GC content and mappability across reference chromosomes requires high-throughput genomic data processing best handled by a cloud workflow.

---

## [124] source=multitask_sft_big

**USER:** Run a case-control logistic regression interaction analysis on our GWAS cohort to test for SNP-environment interaction effects on disease susceptibility.

**ASSISTANT:** cloud_workflow: Testing high-throughput SNP interactions across large-scale cohort data requires batch genomic processing and multi-threaded statistical computation in the cloud.

---

## [125] source=multitask_sft_big

**USER:** Filter out formalin-fixation deamination artifacts (C>T/G>A) from somatic variant calls derived from FFPE tumor-normal sequencing data.

**ASSISTANT:** cloud_workflow: Processing and filtering artifactual variants from high-throughput genomic data files (VCF/BAM) requires distributed batch execution via cloud workflows.

---

## [126] source=multitask_sft_big

**USER:** Identify and filter all Bioconductor software packages categorized under the 'VariantAnnotation' and 'Sequencing' terms using biocViews metadata.

**ASSISTANT:** instant_compute: Querying and filtering Bioconductor package hierarchy tables and metadata via biocViews runs deterministically in a few seconds on a local R environment without cloud scaling.

---

## [127] source=multitask_sft_big

**USER:** Generate a publication-ready, color-coded visual representation of a multiple sequence alignment containing alternative splice isoforms of the human BRCA1 transcript.

**ASSISTANT:** instant_compute: Rendering and styling an existing multiple sequence alignment is a lightweight, deterministic script execution task that completes in seconds without distributed cloud infrastructure.

---

## [128] source=multitask_sft_big

**USER:** Run differential abundance analysis on TMT-labeled phosphoproteomics data across drug-treated and control samples using MSstatsPTM, adjusting for corresponding changes in global protein abundance.

**ASSISTANT:** cloud_workflow: MSstatsPTM executes a multi-step statistical pipeline with linear mixed-effects modeling across large mass spectrometry datasets, requiring cloud-orchestrated workflow execution.

---

## [129] source=multitask_sft_big

**USER:** Generate the empirical score distribution and p-value cutoffs for our transcription factor profile matrix across whole-genome promoter regions.

**ASSISTANT:** cloud_workflow: Evaluating profile score distributions across large-scale genomic sequence libraries requires batch pipeline execution and orchestrated cloud compute resources.

---

## [130] source=multitask_sft_big

**USER:** Perform genotype-imputed gene set enrichment analysis using GWAS summary statistics and transcriptomic eQTL weights to discover disease-associated biological pathways.

**ASSISTANT:** cloud_workflow: Running GIGSEA involves computationally intensive matrix operations and statistical permutations on genome-wide transcriptomic and genetic data that require cloud workflow execution.

---

## [131] source=multitask_sft_big

**USER:** Retrieve annotated protein targets, associated enzymes, and metabolic pathways for the human metabolite citrate using its HMDB ID.

**ASSISTANT:** instant_cited: Querying the Human Metabolome Database retrieves structured factual and cited reference records via a lightweight API lookup without intensive computational resources.

---

## [132] source=multitask_sft_big

**USER:** Filter lowly expressed transcripts and perform differential expression analysis on my RNA-seq count matrix comparing treated vs control samples using HTSFilter and edgeR.

**ASSISTANT:** cloud_workflow: Executing a complete RNA-seq differential expression pipeline with statistical filtering and dispersion modeling requires cloud workflow orchestration.

---

## [133] source=multitask_sft_big

**USER:** Identify and remove doublets from my raw single-cell RNA-seq gene expression count matrix using the scds computational doublet scoring pipeline.

**ASSISTANT:** cloud_workflow: Executing doublet detection on high-dimensional single-cell RNA-seq count matrices requires batch data processing and substantial memory resources typical of cloud bioinformatics pipelines.

---

## [134] source=multitask_sft_big

**USER:** Perform unsupervised spatial segmentation and principal component analysis on my MALDI mass spectrometry imaging dataset in imzML format to identify distinct metabolic tissue regions.

**ASSISTANT:** cloud_workflow: Processing and segmenting high-dimensional mass spectrometry imaging datasets with Cardinal requires significant compute and memory resources executed as a cloud pipeline.

---

## [135] source=multitask_sft_big

**USER:** Estimate optimal beta-value thresholds from whole-genome bisulfite sequencing data using BetaHMM to accurately classify genomic regions into discrete methylation states.

**ASSISTANT:** cloud_workflow: Fitting Beta-Hidden Markov Models on large-scale epigenetic sequencing datasets requires dedicated cloud computational resources to execute the multi-step statistical estimation pipeline.

---

## [136] source=multitask_sft_big

**USER:** Identify and report genomic regions with low coverage or ambiguous sequence alignments across my whole-genome sequencing BAM files using badregionfinder.

**ASSISTANT:** cloud_workflow: Detecting problematic genomic intervals across sequencing alignment files is a resource- and I/O-intensive NGS task suited for distributed cloud workflow execution.

---

## [137] source=multitask_sft_big

**USER:** Align paired-end Illumina FASTQ reads to the human GRCh38 reference genome index using rbowtie2 and output sorted BAM files.

**ASSISTANT:** cloud_workflow: NGS read alignment against large reference genomes requires significant CPU, memory, and storage resources that must be executed in a cloud workflow environment.

---

## [138] source=multitask_sft_big

**USER:** Select top discriminatory biomarker genes between tumor and adjacent normal tissue samples from a normalized RNA-seq count matrix using Maximum Mean Discrepancy.

**ASSISTANT:** cloud_workflow: Executing GeneSelectMMD involves running a multi-step transcriptomic feature selection pipeline on high-dimensional expression datasets that requires dedicated workflow orchestration.

---

## [139] source=multitask_sft_big

**USER:** Call somatic SNVs and indels on targeted sequencing BAM files from tumor-only samples without matched normal controls using GATK Mutect2.

**ASSISTANT:** cloud_workflow: Executing this nf-core Nextflow workflow involves heavy, multi-step cloud-based computing to process BAM files and generate Mutect2 somatic variant calls.

---

## [140] source=multitask_sft_big

**USER:** Import tandem mass spectrometry data from an MGF file into an R Spectra container and filter for high-quality MS2 spectra based on precursor charge and retention time.

**ASSISTANT:** instant_compute: Parsing and manipulating MGF spectra using the MsBackendMgf Bioconductor package is a lightweight data processing task that executes quickly in an interactive R environment without requiring distributed cloud infrastructure.

---

## [141] source=multitask_sft_big

**USER:** Simulate a synthetic scRNA-seq count matrix with three distinct cell populations and batch effects using Splatter, parameterized from an existing single-cell dataset.

**ASSISTANT:** cloud_workflow: Estimating parameters from single-cell count matrices and simulating synthetic scRNA-seq data via Splatter requires containerized, multi-step R/Bioconductor pipeline execution suited for a cloud workflow.

---

## [142] source=multitask_sft_big

**USER:** Import raw array CGH microarray image spot feature extraction data and trigger the stored procedure to ingest normalized genomic intensity profiles into the database.

**ASSISTANT:** cloud_workflow: Batch importing and processing array CGH imaging data via stored procedure ETL pipelines requires multi-step backend orchestration and significant compute resources.

---

## [143] source=multitask_sft_big

**USER:** Run diffusion map dimensionality reduction and pseudotime trajectory analysis on a single-cell RNA-seq expression matrix of hematopoietic stem and progenitor cells.

**ASSISTANT:** cloud_workflow: Diffusion map trajectory inference on high-dimensional single-cell expression data requires executing an R-based analytical pipeline via cloud workflow infrastructure.

---

## [144] source=multitask_sft_big

**USER:** Run an automated feature extraction and selection pipeline on untargeted metabolomics LC-MS peak tables to identify significant biomarker candidates between disease and control cohorts.

**ASSISTANT:** cloud_workflow: featseekr is a multi-step bioinformatics pipeline for high-throughput omics feature selection that requires asynchronous cloud compute execution.

---

## [145] source=multitask_sft_big

**USER:** Construct a pan-genome reference graph from a cohort of assembled human genome FASTAs and VCFs using grafgen to improve read mapping across structural variant regions.

**ASSISTANT:** cloud_workflow: Generating pan-genome reference graphs from multi-genome assembly data requires distributed cloud compute and standard batch bioinformatics pipeline orchestration.

---

## [146] source=multitask_sft_big

**USER:** Predict human clearance and volume of distribution by applying standard allometric scaling power laws to in vivo preclinical PK parameters from mice, rats, and dogs.

**ASSISTANT:** instant_compute: Allometric scaling relies on deterministic mathematical regression equations fitted across species body weights and PK parameters, which execute in milliseconds without requiring distributed cloud infrastructure or intensive ML inference.

---

## [147] source=multitask_sft_big

**USER:** Simulate free T4, total T3, and TSH concentration-time profiles over 8 weeks following a daily oral dose of 100 mcg levothyroxine in an adult with primary hypothyroidism.

**ASSISTANT:** instant_compute: The multi-compartment pharmacokinetic-pharmacodynamic model for thyroid hormone regulation can be solved deterministically and nearly instantaneously using numerical ODE solvers.

---

## [148] source=multitask_sft_big

**USER:** Segment multivariate genomic transcription profiles across multiple paired samples using a hidden semi-Markov model to detect coordinated copy number alterations with biomvrcns.

**ASSISTANT:** instant_compute: The analysis runs an R/Bioconductor statistical segmentation routine on processed tabular genomic data within standard local execution limits without needing distributed cloud pipelines.

---

## [149] source=multitask_sft_big

**USER:** Run PADOG pathway enrichment analysis on my normalized RNA-seq expression matrix and sample metadata to identify significantly altered KEGG pathways while down-weighting overlapping genes.

**ASSISTANT:** cloud_workflow: Executing PADOG involves running an intensive transcriptomics pathway analysis pipeline across full expression matrices and reference gene sets, requiring cloud-based workflow orchestration and computational resources.

---

## [150] source=multitask_sft_big

**USER:** Align paired-end RNA-seq FASTQ reads from human tumor samples to the GRCh38 reference genome using HISAT2 to generate sorted BAM files for downstream expression quantification.

**ASSISTANT:** cloud_workflow: Read alignment with HISAT2 is a computationally intensive, multi-threaded sequencing pipeline task requiring reference indices and dedicated cloud infrastructure.

---

## [151] source=multitask_sft_big

**USER:** Process paired-end shotgun metagenomic sequencing reads through quality filtering, assembly, and contig binning to reconstruct and characterize metagenome-assembled genomes (MAGs).

**ASSISTANT:** cloud_workflow: Metagenomic assembly, binning, and annotation with zitools require multi-step, high-throughput compute infrastructure beyond lightweight local execution.

---

## [152] source=multitask_sft_big

**USER:** Identify differentially methylated regions (DMRs) and generate genomic methylation profiles from whole-genome bisulfite sequencing (WGBS) data comparing treated and control samples.

**ASSISTANT:** cloud_workflow: Processing genome-scale bisulfite sequencing data for methylation profiling and DMR detection requires multi-step high-throughput pipeline execution and high-memory cloud computing.

---

## [153] source=multitask_sft_big

**USER:** Quantify and identify differential alternative splicing and alternative polyadenylation events across my tumor and normal RNA-seq samples using the VASP pipeline.

**ASSISTANT:** cloud_workflow: The VASP workflow involves multi-step, high-throughput processing of large RNA-seq junction and alignment files that require distributed cloud compute infrastructure.

---

## [154] source=multitask_sft_big

**USER:** Run cell deconvolution inference on a cohort of 50 bulk RNA-seq tumor samples using a paired single-cell reference matrix to quantify immune cell infiltration fractions.

**ASSISTANT:** cloud_workflow: Deconvolving cell-type proportions across transcriptomic datasets requires multi-step algorithmic processing and batch computation that must be orchestrated in the cloud.

---

## [155] source=multitask_sft_big

**USER:** I have raw FASTQ files with inconsistent read headers and invalid nucleotide characters, and I need to sanitize, validate, and clean them using SeqKit before running downstream analysis.

**ASSISTANT:** cloud_workflow: Processing and sanitizing high-throughput FASTQ sequencing data requires distributed cloud infrastructure running batch bioinformatics command-line pipelines.

---

## [156] source=multitask_sft_big

**USER:** Process time-lapse fluorescence microscopy stacks of ischemic myocardial tissue loaded with Rhod-2 AM to quantify mitochondrial calcium dynamics and compute delta F/F0 curves across regions of interest.

**ASSISTANT:** cloud_workflow: Quantifying intracellular calcium kinetics from multi-frame fluorescence imaging stacks requires an orchestrated cloud pipeline for image segmentation, motion correction, background subtraction, and signal extraction.

---

## [157] source=multitask_sft_big

**USER:** Assign taxonomic labels to assembled metagenomic contigs from an environmental soil sample using MMseqs2 against the UniRef50 database.

**ASSISTANT:** cloud_workflow: It is an intensive Nextflow pipeline requiring high-throughput, distributed cloud compute to query large metagenomic assemblies against reference sequence databases.

---

## [158] source=multitask_sft_big

**USER:** Process a set of raw cryo-ET tilt-series movies into high-resolution 3D tomograms through motion correction, tilt alignment, CTF estimation, and 3D reconstruction.

**ASSISTANT:** cloud_workflow: End-to-end cryo-ET processing involves a multi-step, resource-intensive computational pipeline that requires distributed GPU/CPU orchestration over large volumetric datasets.

---

## [159] source=multitask_sft_big

**USER:** Map identified peptide sequences from a bottom-up tandem mass spectrometry dataset back to their corresponding genomic coordinates to detect novel translational events and splice junctions.

**ASSISTANT:** cloud_workflow: ginmappeR is a multi-step bioinformatics pipeline for mapping proteomic peptide identifications to reference genomes and transcript models, requiring scalable cloud workflow execution.

---

## [160] source=multitask_sft_big

**USER:** Process raw LC-MS/MS proteomic and untargeted metabolomic mzML files through an integrated feature extraction, alignment, and quantification pipeline to identify co-regulated proteins and metabolites across experimental groups.

**ASSISTANT:** cloud_workflow: Analyzing multi-omics mass spectrometry data requires multi-step orchestration of heavy computational pipelines such as peak detection, peptide/metabolite identification, and batch correction on cloud infrastructure.

---

## [161] source=multitask_sft_big

**USER:** Annotate the assembled FASTA contigs from a newly sequenced clinical isolate of Pseudomonas aeruginosa to identify protein-coding genes, rRNAs, tRNAs, and functional product annotations.

**ASSISTANT:** cloud_workflow: Bacterial genome annotation requires orchestrating multi-step bioinformatics pipelines like Prokka or Bakta against reference databases, necessitating asynchronous batch execution in the cloud.

---

## [162] source=multitask_sft_big

**USER:** Run variant calling, structural variant detection, and clinical ranking on family-trio whole-genome sequencing FASTQ files to discover candidate causative mutations for an undiagnosed rare disorder.

**ASSISTANT:** cloud_workflow: Executing the nf-core/raredisease pipeline across multi-sample WGS datasets requires high-throughput cloud infrastructure for multi-step alignment, calling, and annotation.

---

## [163] source=multitask_sft_big

**USER:** Design a panel of Cas13 guide RNAs targeting isoform-specific splice junctions of human CD44 to evaluate selective transcript knockdown with minimal off-target effects across the transcriptome.

**ASSISTANT:** cloud_design: Designing optimized guide RNAs with comprehensive on-target efficiency scoring and transcriptome-wide off-target searches is a computationally intensive molecular sequence design task requiring specialized cloud infrastructure.

---

## [164] source=multitask_sft_big

**USER:** Identify enriched transcription factor binding motifs and candidate upstream regulons for a co-expression gene module derived from single-cell RNA-seq data using motif ranking databases.

**ASSISTANT:** cloud_workflow: RcisTarget requires staging multi-gigabyte cis-regulatory motif ranking databases and executing memory-intensive enrichment analyses that require cloud workflow orchestration.

---

## [165] source=multitask_sft_big

**USER:** Run quality control, preprocessing, and differential methylation analysis on Illumina Infinium EPIC array IDAT files comparing tumor versus normal tissue samples.

**ASSISTANT:** cloud_workflow: RnBeads is a multi-step genomic pipeline for comprehensive DNA methylation profiling that requires cloud compute infrastructure to process high-throughput array data and generate detailed reports.

---

## [166] source=multitask_sft_big

**USER:** Process and normalize high-throughput chromosome conformation capture (Hi-C/5C) interaction data to construct contact matrices and detect chromatin interaction features.

**ASSISTANT:** cloud_workflow: Analyzing high-resolution chromosome conformation capture datasets requires memory-intensive genomic matrix processing and multi-step pipeline execution suited for cloud infrastructure.

---

## [167] source=multitask_sft_big

**USER:** Co-design an anti-CD19 CAR-T genetic cassette and a CD8-targeting lipid nanoparticle (LNP) delivery platform optimized for direct in vivo T-cell reprogramming.

**ASSISTANT:** cloud_design: Multi-objective generative engineering of macromolecular binders and genetic payloads requires high-throughput structural optimization algorithms running on specialized cloud infrastructure.

---

## [168] source=multitask_sft_big

**USER:** Calibrate a prior knowledge signaling network to phosphoproteomic perturbation data measured across two time points using CellNOptR's genetic algorithm optimization.

**ASSISTANT:** cloud_workflow: Logic-based model calibration via genetic algorithms involves multi-step preprocessing and computationally intensive optimization loops suitable for cloud workflow execution.

---

## [169] source=multitask_sft_big

**USER:** Curate and index a custom compound database of 50,000 vendor molecules filtered for lead-likeness and PAINS exclusion with computed 3D conformers for downstream virtual screening.

**ASSISTANT:** cloud_workflow: Building and standardizing a large-scale custom compound database requires a multi-step chemoinformatics pipeline involving batch property calculation, filtering, and conformer generation on cloud infrastructure.

---

## [170] source=multitask_sft_big

**USER:** Index a set of coordinate-sorted BAM alignment files and extract read depth across specific genomic target coordinates using Rsamtools.

**ASSISTANT:** cloud_workflow: Manipulating and extracting coverage from high-throughput sequencing BAM files involves high I/O throughput and memory-intensive processing suited for distributed cloud infrastructure.

---

## [171] source=multitask_sft_big

**USER:** Process high-speed video microscopy recordings of human nasal epithelial cells to quantify ciliary beat frequency (CBF) and identify motility abnormalities across tissue regions.

**ASSISTANT:** cloud_workflow: Quantifying ciliary beat frequency involves a multi-step image and signal processing pipeline to extract pixel intensity time-series and perform Fourier transform analysis across high-speed video files.

---

## [172] source=multitask_sft_big

**USER:** Process paired-end 10x Genomics single-cell RNA-seq FASTQ reads using kallisto bus to generate error-corrected gene-cell count matrices.

**ASSISTANT:** cloud_workflow: High-throughput pseudoalignment and barcode-UMI processing of raw scRNA-seq datasets require distributed compute and memory resources typical of cloud workflow infrastructure.

---

## [173] source=multitask_sft_big

**USER:** Construct diffusion maps and infer pseudotime trajectories from a single-cell qPCR dataset while accounting for measurement thresholds and censored missing values.

**ASSISTANT:** cloud_workflow: Computing diffusion maps with censored value modeling on single-cell expression matrices requires running a dedicated R/Bioconductor bioinformatics workflow on cloud resources.

---

## [174] source=multitask_sft_big

**USER:** Process raw paired-end RNA-seq FASTQ files from treated and control cohorts to quantify transcript expression levels and identify differentially expressed genes using the PLPE workflow.

**ASSISTANT:** cloud_workflow: Executing end-to-end transcriptomic pipelines on raw sequencing data requires scalable, high-throughput cloud compute and orchestration for alignment and quantification.

---

## [175] source=multitask_sft_big

**USER:** Assess the quality of Ribo-seq BAM alignments from human embryonic kidney cells by computing read length distributions, 3-nt codon periodicity, and P-site offsets across annotated coding sequences.

**ASSISTANT:** cloud_workflow: Ribosome profiling quality control entails multi-step bioinformatic processing of large alignment (BAM) and annotation files that require scalable cloud compute.

---

## [176] source=multitask_sft_big

**USER:** Identify shared and study-specific differentially expressed gene patterns across four transcriptomic cohorts of sepsis patients using correlation motif analysis.

**ASSISTANT:** cloud_workflow: Fitting Bayesian correlation motif models across multi-study transcriptomic datasets requires intensive iterative expectation-maximization computation suited for managed cloud pipeline execution.

---

## [177] source=multitask_sft_big

**USER:** Quantify alternative splicing events and identify differentially spliced junctions from replicate RNA-seq BAM files between control and treated conditions using ASpli.

**ASSISTANT:** cloud_workflow: Processing large multi-sample RNA-seq BAM files against genome annotations to calculate exon/intron metrics and differential splicing requires substantial compute and storage typically managed as a cloud pipeline.

---

## [178] source=multitask_sft_big

**USER:** Quantify viral transcript abundance and profile host-pathogen interactions from raw 10x single-cell RNA-seq FASTQ data of virus-infected lung tissue.

**ASSISTANT:** cloud_workflow: Processing high-throughput single-cell sequencing reads to align and detect viral RNAs alongside the host transcriptome requires intensive multi-step cloud bioinformatics pipeline execution.

---

## [179] source=multitask_sft_big

**USER:** Compress raw Illumina BeadArray bead-level text and image files into space-efficient .bab format for long-term archiving of a microarray study.

**ASSISTANT:** cloud_workflow: Batch compression and decompression of multi-gigabyte raw BeadArray image and data files require scalable cloud storage and pipeline compute.

---

## [180] source=multitask_sft_big

**USER:** Query and retrieve harmonized RNA-seq expression matrices and standardized clinical metadata for colorectal cancer from the OmicsMLRepo repository using OmicsMLRepoR for machine learning benchmark preparation.

**ASSISTANT:** instant_compute: This task involves querying metadata and downloading curated benchmark datasets via an interactive R package client, which executes quickly in a lightweight compute session without requiring heavy distributed cloud pipelines.

---

## [181] source=multitask_sft_big

**USER:** Infer developmental trajectories and single-cell pseudotime from my hematopoietic stem cell scRNA-seq expression matrix using Monocle.

**ASSISTANT:** cloud_workflow: Monocle trajectory inference requires multi-step preprocessing, dimensionality reduction, and heavy graph learning suited for cloud bioinformatics pipeline execution.

---

## [182] source=multitask_sft_big

**USER:** Simulate 30x coverage paired-end Illumina reads from the GRCh38 human reference genome with predefined somatic SNVs to benchmark a variant calling pipeline.

**ASSISTANT:** cloud_workflow: Simulating high-depth whole-genome sequencing reads requires scalable high-performance compute and large storage handled through batch cloud workflow orchestration.

---

## [183] source=multitask_sft_big

**USER:** Run the GeneRecommender algorithm on a target set of DNA repair genes across our normalized microarray expression datasets to identify ranked co-expressed candidates.

**ASSISTANT:** cloud_workflow: GeneRecommender involves multi-step Bioconductor matrix operations and scoring across large transcriptomic datasets, requiring cloud pipeline execution.

---

## [184] source=multitask_sft_big

**USER:** Execute the MPFE workflow on raw WGBS FASTQ sequencing data to perform adapter trimming, bisulfite-aware alignment, and extract CpG methylation feature matrices across multiple samples.

**ASSISTANT:** cloud_workflow: Processing large-scale epigenomic sequencing datasets through multi-step alignment and methylation feature extraction requires distributed cloud compute and containerized workflow orchestration.

---

## [185] source=multitask_sft_big

**USER:** Align my paired-end ATAC-seq FASTQ files to the human GRCh38 reference genome using Chromap to generate a duplicate-removed BAM file.

**ASSISTANT:** cloud_workflow: Aligning high-throughput FASTQ sequencing reads to a full reference genome requires heavy compute and memory resources orchestrated through a dedicated cloud bioinformatics workflow.

---

## [186] source=multitask_sft_big

**USER:** Query and extract validated human ligand-receptor interaction pairs using the LRBaseDbi package in R for downstream cell-cell communication analysis.

**ASSISTANT:** instant_compute: Querying SQLite-backed ligand-receptor database objects via LRBaseDbi is a lightweight, deterministic R operation that finishes in seconds without distributed cloud resources.

---

## [187] source=multitask_sft_big

**USER:** Perform multivariate gene set analysis on normalized RNA-seq count data between treated and control conditions to identify significantly shifted KEGG pathways using the GSAR algorithm.

**ASSISTANT:** cloud_workflow: Gene set analysis with statistical permutations across high-throughput transcriptomic matrices requires running containerized R/Bioconductor pipeline workflows on cloud compute.

---

## [188] source=multitask_sft_big

**USER:** Extract and summarize read depth across targeted genomic intervals from a cohort of whole-genome BAM files using parallel chunked file processing.

**ASSISTANT:** cloud_workflow: The GenomicFiles framework orchestrates heavy, distributed I/O and matrix reductions across multiple large sequencing files that require asynchronous cloud pipeline execution.

---

## [189] source=multitask_sft_big

**USER:** Run probe-pair level CCPROMISE analysis to identify integrative genomic associations between microRNA and mRNA expression profiles linked to patient clinical outcomes.

**ASSISTANT:** cloud_workflow: Probe-pair level CCPROMISE is a multi-step transcriptomic pipeline requiring cloud-based computation for statistical modeling and permutation testing across high-dimensional genomic datasets.

---

## [190] source=multitask_sft_big

**USER:** Normalize RT-qPCR cycle threshold (Ct) values across experimental groups using geNorm and compute relative expression fold-changes via the delta-delta-Ct method.

**ASSISTANT:** instant_compute: Normalizing qPCR Ct tables and evaluating reference gene stability is a lightweight statistical calculation that executes in seconds on standard CPU without requiring distributed cloud infrastructure.

---

## [191] source=multitask_sft_big

**USER:** Download uniformly processed RNA-seq gene expression count matrices and QC metadata for human SRA study SRP049407 using getDEE2.

**ASSISTANT:** instant_compute: Querying and fetching pre-indexed expression summaries from the DEE2 database is a lightweight data retrieval task that executes rapidly without cloud orchestration.

---

## [192] source=multitask_sft_big

**USER:** Calculate pairwise and per-site FST statistics from my multi-sample population VCF file to measure genetic differentiation between two geographical cohorts.

**ASSISTANT:** cloud_workflow: Computing genome-wide fixation statistics from large multi-sample VCF files requires running specialized bioinformatic tools on dedicated cloud compute infrastructure.

---

## [193] source=multitask_sft_big

**USER:** Run automated preprocessing, cell segmentation, and morphological feature extraction across a multi-well plate batch of high-content fluorescence microscopy images.

**ASSISTANT:** cloud_workflow: Executing end-to-end image processing and feature extraction on large multi-channel microscopy datasets requires scalable, distributed cloud pipeline orchestration.

---

## [194] source=multitask_sft_big

**USER:** Run SC3 consensus clustering on my filtered scRNA-seq expression matrix to identify stable cell clusters and calculate cluster-specific marker genes.

**ASSISTANT:** cloud_workflow: SC3 consensus clustering involves computationally intensive distance matrix calculations, spectral transformations, and repetitive k-means iterations across thousands of cells that require cloud workflow resources.

---

## [195] source=multitask_sft_big

**USER:** Analyze transcript-level Salmon quantification counts with bootstrap replicates across 10 RNA-seq samples to identify genes showing significant differential transcript usage between knockout and wild-type conditions using Fishpond.

**ASSISTANT:** cloud_workflow: Running differential transcript usage workflows like Fishpond requires processing multi-sample quantification directories with inferential replicates and executing multi-step statistical testing pipelines.

---

## [196] source=multitask_sft_big

**USER:** Map and visualize chromosome-scale local ancestry tracts and genomic copy number segments across an admixed cohort from segment call files and phased genotypes.

**ASSISTANT:** cloud_workflow: Generating whole-genome chromosome segment and ancestry maps from genomic coordinate callsets requires multi-step pipeline orchestration and substantial compute resources typical of bioinformatics cloud workflows.

---

## [197] source=multitask_sft_big

**USER:** Process a multi-temporal stack of Sentinel-2 satellite tiles across a grazing reserve to generate vegetation index time series and rangeland fractional cover metrics.

**ASSISTANT:** cloud_workflow: The nf-core/rangeland pipeline is a containerized Nextflow workflow requiring distributed cloud compute resources for heavy geospatial image processing.

---

## [198] source=multitask_sft_big

**USER:** Provide a step-by-step heat-shock transformation protocol for chemically competent DH5alpha E. coli cells using a plasmid containing ampicillin resistance.

**ASSISTANT:** instant_cited: Retrieving a standard, established laboratory protocol relies on literature-backed procedural knowledge that can be served immediately with citations without requiring cloud execution or computational simulation.

---

## [199] source=multitask_sft_big

**USER:** Integrate environmental exposome data with whole-blood RNA-seq gene expression matrices using omicRexposome to detect exposure-induced transcriptional signatures and enriched pathways.

**ASSISTANT:** cloud_workflow: The omicrexposome workflow executes multi-step high-dimensional association testing and functional integration between exposome metrics and transcriptomic datasets requiring cloud-based pipeline orchestration.

---

## [200] source=multitask_sft_big

**USER:** Run consensus clustering on my multi-cohort RNA-seq expression matrix to identify robust and reproducible tumor molecular subtypes.

**ASSISTANT:** cloud_workflow: Executing consensus clustering across high-dimensional transcriptomic datasets involves computationally demanding, iterative resampling pipelines requiring scalable cloud workflow orchestration.

---

## [201] source=multitask_sft_big

**USER:** Perform functional decomposition and biological pathway-driven cell clustering on a single-cell RNA-seq count matrix using ASURAT with Gene Ontology and KEGG databases.

**ASSISTANT:** cloud_workflow: ASURAT executes a multi-step single-cell transcriptomics pipeline involving pathway database mapping, matrix transformation, and high-dimensional clustering that requires cloud compute infrastructure.

---

## [202] source=multitask_sft_big

**USER:** Check the expiration date and retention policy for temporary scratch directories in my project workspace.

**ASSISTANT:** instant_compute: Inspecting or updating directory expiration policies is a quick file-system metadata task executed immediately without requiring heavy cloud orchestration.

---

## [203] source=multitask_sft_big

**USER:** Detect dynamic co-expression changes and higher-order gene interactions along a developmental pseudotime trajectory from my single-cell RNA-seq dataset using scHOT.

**ASSISTANT:** cloud_workflow: scHOT performs computationally demanding permutation testing and trajectory-based correlation modeling across single-cell matrices, requiring asynchronous cloud pipeline execution.

---

## [204] source=multitask_sft_big

**USER:** Predict and profile immunogenic peptides and functional epitopes from human microbiome metagenomic contigs using nf-core/metapep.

**ASSISTANT:** cloud_workflow: nf-core/metapep is an end-to-end Nextflow pipeline requiring distributed cloud computing to perform gene calling, taxonomic profiling, and peptide/epitope prediction on large metagenomic datasets.

---

## [205] source=multitask_sft_big

**USER:** Dissect pathway-level heterogeneity and identify latent factors driving variation in a single-cell RNA-seq count matrix using MSigDB gene sets.

**ASSISTANT:** cloud_workflow: Running Slalom entails computationally intensive Bayesian latent variable modeling across thousands of single cells and gene sets, requiring standard asynchronous cloud workflow infrastructure.

---

## [206] source=multitask_sft_big

**USER:** I have raw Affymetrix microarray CEL files from a transcriptomics study and need to perform flexible three-step preprocessing—background correction, quantile normalization, and probe summarization—along with PLM-based quality assessment using affyPLM.

**ASSISTANT:** cloud_workflow: Preprocessing raw microarray probe-level data through background correction, normalization, and summarization pipelines requires multi-step bioinformatics workflow execution in the cloud.

---

## [207] source=multitask_sft_big

**USER:** Identify potential drug repurposing candidates by searching our set of differentially expressed up- and down-regulated disease genes against the LINCS L1000 database using signaturesearch.

**ASSISTANT:** cloud_workflow: Screening transcriptomic signatures against large-scale reference perturbation databases like LINCS L1000 requires multi-step data loading, high-memory scoring algorithms, and long-running pipeline execution.

---

## [208] source=multitask_sft_big

**USER:** Convert OpenMS quantitative TMT proteomics output files into an MSstatsTMT-compatible format for downstream differential abundance analysis.

**ASSISTANT:** cloud_workflow: This is a multi-step proteomics data processing pipeline requiring cloud-based workflow execution to handle and transform large mass spectrometry quantitation outputs.

---

## [209] source=multitask_sft_big

**USER:** Detect rare aberrant splicing events and outlier junctions across a cohort of patient RNA-seq BAM files to identify potential disease-causing variants.

**ASSISTANT:** cloud_workflow: FRASER requires high-throughput junction extraction and cohort-wide statistical modeling across heavy RNA-seq datasets, which necessitates asynchronous distributed execution in a cloud workflow.

---

## [210] source=multitask_sft_big

**USER:** Detect and quantify multi-allelic copy number variations from targeted NGS BAM files across a multi-sample cohort using CNVrd2.

**ASSISTANT:** cloud_workflow: Processing high-throughput sequencing BAM files for read-depth counting and Bayesian CNV segmentation requires scalable cloud computing infrastructure.

---

## [211] source=multitask_sft_big

**USER:** Segment whole-genome bisulfite sequencing methylation profiles into homogeneous methylation domains and identify differentially methylated regions across experimental conditions using methylKit.

**ASSISTANT:** cloud_workflow: Methylome segmentation on genome-wide sequencing data requires running a multi-step bioinformatics pipeline on cloud infrastructure to process large genomic tracks.

---

## [212] source=multitask_sft_big

**USER:** Estimate and correct inflation and bias in my epigenome-wide association study (EWAS) z-scores using the bacon empirical Bayes method.

**ASSISTANT:** instant_compute: Fitting empirical null distribution mixture models on association summary statistics is a lightweight analytical task that executes quickly within an interactive compute sandbox.

---

## [213] source=multitask_sft_big

**USER:** Normalize my bulk RNA-seq count matrix to correct for systematic GC-content and gene length biases across 24 paired tumor and normal samples.

**ASSISTANT:** cloud_workflow: Conditional quantile normalization (CQN) across multi-sample RNA-seq datasets requires running containerized R/Bioconductor analysis pipelines with file-based inputs and outputs.

---

## [214] source=multitask_sft_big

**USER:** Perform Gene Set Enrichment Analysis (GSEA) on a ranked differential gene expression list from RNA-seq treated vs. control samples against the MSigDB Hallmark gene sets to identify significantly enriched pathways.

**ASSISTANT:** cloud_workflow: GSEA involves executing standardized multi-step bioinformatics pipelines and statistical permutation tests against large pathway databases, which run as cloud workflows.

---

## [215] source=multitask_sft_big

**USER:** Analyze ribosome occupancy and metagene translation efficiency across coding sequences and UTRs from a multi-sample Ribo-seq experiment stored in a .ribo file.

**ASSISTANT:** cloud_workflow: Processing and summarizing large-scale ribosome profiling datasets across multiple samples requires distributed cloud resources and multi-step pipeline execution.

---

## [216] source=multitask_sft_big

**USER:** Perform differential abundance and differential state analysis across patient cohorts using diffcyt on multi-sample high-dimensional single-cell marker expression data.

**ASSISTANT:** cloud_workflow: Running diffcyt involves multi-step clustering and generalized linear mixed modeling across multi-sample high-dimensional datasets, which requires scalable cloud bioinformatics workflow execution.

---

## [217] source=multitask_sft_big

**USER:** Perform differential abundance analysis on a cohort of mass cytometry (CyTOF) samples linked to censored patient survival outcomes to identify cell clusters correlated with time-to-event endpoints.

**ASSISTANT:** cloud_workflow: censcyt runs a multi-step bioinformatics pipeline involving cell clustering, marker quantification, and censored survival regression across high-dimensional cytometry datasets requiring cloud infrastructure.

---

## [218] source=multitask_sft_big

**USER:** Run the CompSpot pipeline to perform comparative spatial transcriptomics spot deconvolution and differential expression analysis across multiple 10x Visium tissue sections.

**ASSISTANT:** cloud_workflow: This multi-sample spatial genomics analysis requires distributed data processing and multi-step pipeline execution on cloud infrastructure.

---

## [219] source=multitask_sft_big

**USER:** Detect and score positioned nucleosomes across the yeast genome from paired-end MNase-seq BAM files using Fourier transform filtering.

**ASSISTANT:** cloud_workflow: Genome-wide nucleosome peak calling from high-throughput sequencing alignments requires intensive data processing and file handling typical of cloud workflow execution.

---

## [220] source=multitask_sft_big

**USER:** Bin assembled metagenomic contigs from multiple environmental samples using CONCOCT based on nucleotide composition and read coverage profiles.

**ASSISTANT:** cloud_workflow: It is an nf-core Nextflow pipeline designed for orchestrating multi-step, resource-intensive metagenomic binning on cloud or HPC infrastructure.

---

## [221] source=multitask_sft_big

**USER:** Perform sub-spot spatial clustering and resolution enhancement on 10x Genomics Visium spatial transcriptomics data of human tissue to identify fine-scale anatomical domains.

**ASSISTANT:** cloud_workflow: BayesSpace runs Bayesian MCMC algorithms on high-dimensional spatial transcriptomics matrices and coordinate data, requiring dedicated asynchronous cloud workflow execution.

---

## [222] source=multitask_sft_big

**USER:** Estimate modern human DNA contamination in my low-depth ancient BAM files using ANGSD doCounts and X-chromosome polymorphism tables.

**ASSISTANT:** cloud_workflow: Processing sequencing BAM files with ANGSD to compute allele counts and evaluate sample contamination requires high-performance, multi-step cloud bioinformatics pipeline execution.

---

## [223] source=multitask_sft_big

**USER:** Evaluate a panel of lead-optimization small molecules for hERG potassium channel inhibition and cardiotoxicity risk using a QSAR prediction model.

**ASSISTANT:** instant_compute: hERG QSAR scoring utilizes pre-trained machine learning models on molecular descriptors to deliver rapid safety predictions on SMILES inputs within seconds without requiring heavy GPU orchestration.

---

## [224] source=multitask_sft_big

**USER:** Retrieve, preprocess, and perform multi-omic integration of paired host transcriptomic and gut metagenomic datasets from the HoloFood database for dietary intervention cohorts.

**ASSISTANT:** cloud_workflow: HoloFoodR orchestrates large-scale multi-omic data retrieval and intensive downstream bioinformatics processing pipelines that require cloud computing resources.

---

## [225] source=multitask_sft_big

**USER:** Call SNPs and indels from paired-end FASTQ sequencing reads against a reference genome using the cpvsnp pipeline.

**ASSISTANT:** cloud_workflow: Variant calling across raw high-throughput sequencing datasets requires heavy, multi-step command-line alignment and filtering tools executed on scalable cloud infrastructure.

---

## [226] source=multitask_sft_big

**USER:** Identify gene expression signatures significantly correlated with disease severity by running a supervised gene-trait association analysis on an RNA-seq expression dataset and clinical metadata table.

**ASSISTANT:** cloud_workflow: Supervised association testing across high-dimensional transcriptomic datasets and phenotypic traits requires multi-step statistical pipeline execution on cloud infrastructure.

---

## [227] source=multitask_sft_big

**USER:** Perform differential expression analysis on high-throughput RT-qPCR Ct data comparing control and treated sample groups using the unified Wilcoxon-Mann-Whitney test pipeline.

**ASSISTANT:** cloud_workflow: It executes an R/Bioconductor statistical pipeline requiring batch processing of RT-qPCR expression matrices on cloud infrastructure.

---

## [228] source=multitask_sft_big

**USER:** Adjust epigenome-wide or genome-wide association study summary statistics for inflation and bias using the BACON method, calculating inflation-corrected effect sizes and 95% confidence intervals.

**ASSISTANT:** cloud_workflow: Running the BACON adjustment on genome-scale association statistics requires executing a standardized statistical bioinformatics pipeline on cloud compute infrastructure.

---

## [229] source=multitask_sft_big

**USER:** Generate diagnostic coverage plots and genomic region visualizations for differentially expressed regions identified from RNA-seq sample groups using derfinder analysis results.

**ASSISTANT:** cloud_workflow: Executing derfinderPlot involves processing large genomic coverage tracks and region metadata across RNA-seq cohorts, requiring scalable cloud-based bioinformatics workflow execution.

---

## [230] source=multitask_sft_big

**USER:** Perform consensus gene set analysis on my differential expression dataset using the piano package to identify robustly enriched biological pathways across multiple statistical GSA methods.

**ASSISTANT:** cloud_workflow: Executing multi-method consensus gene set analysis across transcriptomic gene sets involves containerized R/Bioconductor statistical pipelines that require cloud workflow batch execution.

---

## [231] source=multitask_sft_big

**USER:** Process raw paired-end Hi-C sequencing reads to generate normalized contact matrices, identify topologically associating domains (TADs), and detect significant chromatin loops across the genome.

**ASSISTANT:** cloud_workflow: Processing high-throughput chromosome conformation capture data involves computationally heavy, multi-step alignment, filtering, and matrix binning steps that require scalable cloud compute resources.

---

## [232] source=multitask_sft_big

**USER:** Process paired-end CUT&Tag FASTQ sequencing files with spike-in calibration against human and E. coli genomes to generate normalized coverage bigWig tracks and peak calls.

**ASSISTANT:** cloud_workflow: Epigenomic multi-genome alignment, spike-in normalization, and peak calling require high-throughput multi-step compute orchestration on cloud infrastructure.

---

## [233] source=multitask_sft_big

**USER:** Run the nf-core/spatialvi pipeline on my multi-sample 10x Visium spatial transcriptomics datasets to perform image alignment, probabilistic spatial expression modeling, and spatial domain clustering across slides.

**ASSISTANT:** cloud_workflow: nf-core/spatialvi is a high-throughput Nextflow bioinformatics pipeline requiring containerized cloud compute resources for distributed spatial transcriptomics data integration and deep generative modeling.

---

## [234] source=multitask_sft_big

**USER:** Align a multi-FASTA file containing 50 homologous cytochrome c oxidase subunit I (COI) protein sequences using MUSCLE to generate a multiple sequence alignment.

**ASSISTANT:** cloud_workflow: MUSCLE is a containerized command-line bioinformatics tool executed as an asynchronous cloud workflow to handle multiple sequence alignment tasks.

---

## [235] source=multitask_sft_big

**USER:** Evaluate and compare the batch effect correction performance of multiple scRNA-seq integration algorithms on my multi-batch PBMC dataset using comprehensive CellMixS mixing scores and LISI metrics.

**ASSISTANT:** cloud_workflow: Running comprehensive CellMixS metric calculations across large single-cell transcriptomic datasets requires significant computational resources and automated pipeline execution in the cloud.

---

## [236] source=multitask_sft_big

**USER:** Run the podcall pipeline to detect enriched chromatin peaks and analyze differential epigenomic signals across my paired-end ChIP-seq BAM datasets.

**ASSISTANT:** cloud_workflow: Executing end-to-end epigenomic peak calling on sequencing data involves multi-step, compute-intensive genomic processing best suited for distributed cloud workflows.

---

## [237] source=multitask_sft_big

**USER:** Convert a multi-sample whole-genome sequencing VCF file into CoreArray Genomic Data Structure (GDS) format using gdsfmt for scalable downstream association analysis.

**ASSISTANT:** cloud_workflow: Processing and converting multi-sample VCF files into GDS storage requires significant I/O, memory, and batch pipeline execution suitable for cloud infrastructure.

---

## [238] source=multitask_sft_big

**USER:** Analyze paired-end STARR-seq sequencing data to identify active enhancers and quantify transcriptional regulatory activity across the genome.

**ASSISTANT:** cloud_workflow: Processing STARR-seq sequencing datasets involves multi-step genomic alignment and statistical peak-calling pipelines that must be executed on cloud infrastructure.

---

## [239] source=multitask_sft_big

**USER:** Perform statistical assessment of cell differentiation trajectories and reconstruct cell-state hierarchy trees from my single-cell RNA-seq expression matrix using sincell.

**ASSISTANT:** cloud_workflow: Executing sincell for single-cell lineage reconstruction and distance-based hierarchical modeling involves a multi-step bioinformatics pipeline requiring cloud compute execution.

---

## [240] source=multitask_sft_big

**USER:** Analyze paired-end targeted bisulfite sequencing FASTQ reads to align them against the human reference genome and call CpG site methylation percentages across target regions.

**ASSISTANT:** cloud_workflow: Processing targeted bisulfite NGS data requires an asynchronous, multi-step pipeline involving read trimming, bisulfite-aware alignment, and methylation extraction on cloud compute.

---

## [241] source=multitask_sft_big

**USER:** Scatter a large target capture BED file across balanced sub-intervals using bedtools to optimize downstream parallelized variant calling.

**ASSISTANT:** cloud_workflow: Executing an nf-core Nextflow processing pipeline on genomic data requires distributed compute via the cloud workflow execution lane.

---

## [242] source=multitask_sft_big

**USER:** Query a GA4GH Beacon v2 endpoint to check for the presence and allele frequency of the variant chr7:g.140753336A>T (BRAF V600E) across open genomic cohorts.

**ASSISTANT:** instant_compute: The tool issues fast REST API queries against GA4GH-compliant services to retrieve genomic records and metadata without requiring long-running cloud cluster orchestration or heavy GPU resources.

---

## [243] source=multitask_sft_big

**USER:** Calculate the statistical significance, odds ratio, and Jaccard index for the overlap between my list of differentially expressed genes and a curated DNA repair pathway gene set.

**ASSISTANT:** instant_compute: Gene overlap testing involves lightweight statistical calculations (such as Fisher's exact test) that execute in seconds without requiring distributed cloud infrastructure.

---

## [244] source=multitask_sft_big

**USER:** Process and quantify histone post-translational modifications from raw chromatin mass spectrometry data across differential epigenetic perturbation conditions using the squallms pipeline.

**ASSISTANT:** cloud_workflow: Executing the squallms pipeline requires long-running, multi-step batch processing and significant compute infrastructure to handle raw data quantification.

---

## [245] source=multitask_sft_big

**USER:** I need a standard bench protocol including reaction mixtures and thermocycling parameters to assemble three DNA inserts into a backbone vector using BsaI Golden Gate assembly.

**ASSISTANT:** instant_cited: Generating an established molecular biology protocol requires immediate retrieval and synthesis of standardized experimental conditions with literature-backed best practices.

---

## [246] source=multitask_sft_big

**USER:** Run pseudotime trajectory inference on my scRNA-seq AnnData object of human hematopoietic stem and progenitor cells to map differentiation lineages toward erythroid and myeloid fates.

**ASSISTANT:** cloud_workflow: Trajectory inference requires compute-intensive graph traversal, manifold estimation, and differential gene expression analysis along lineages on large single-cell datasets, requiring execution as a batch cloud workflow.

---

## [247] source=multitask_sft_big

**USER:** Run genotype calling and quality assessment on a cohort of Affymetrix Genome-Wide Human SNP 6.0 array CEL files using the crlmm package.

**ASSISTANT:** cloud_workflow: Batch processing of high-density microarray intensity files requires a scalable, end-to-end bioinformatics pipeline executed on cloud compute infrastructure.

---

## [248] source=multitask_sft_big

**USER:** I have an unfiltered single-cell RNA-seq count matrix with significant ambient RNA background and want to run DecontX to estimate contamination percentages and generate a decontaminated expression matrix.

**ASSISTANT:** cloud_workflow: DecontX Bayesian estimation and ambient RNA matrix decontamination on large scRNA-seq datasets require substantial compute and memory resources best suited for asynchronous cloud workflow execution.

---

## [249] source=multitask_sft_big

**USER:** Estimate the order and accumulation pathways of somatic mutations across a cohort of tumor samples by fitting a mixture of mutagenetic trees using Rtreemix.

**ASSISTANT:** cloud_workflow: Estimating mixture models of mutagenetic trees with the EM algorithm on cross-sectional genomic datasets requires sustained computational resources and pipeline execution.

---

## [250] source=multitask_sft_big

**USER:** Filter and summarize genetic variants from a multi-sample cohort VCF based on phenotypic traits and functional impact predictions using TVTB.

**ASSISTANT:** cloud_workflow: Processing cohort-scale VCF files against phenotype tables requires substantial computational memory and pipeline orchestration typical of genomic cloud workflows.

---

## [251] source=multitask_sft_big

**USER:** Filter low-count transcripts and perform differential abundance analysis across treated and control RNA-seq samples using the nf-core/abundance_differential_filter pipeline.

**ASSISTANT:** cloud_workflow: This is an nf-core bioinformatics data-processing pipeline that requires containerized Nextflow execution on cloud or cluster resources.

---

## [252] source=multitask_sft_big

**USER:** Screen a curated library of 50,000 drug-like compounds against the binding pocket of human CDK2 using DrugCLIP to identify top candidate inhibitors.

**ASSISTANT:** cloud_models: DrugCLIP relies on GPU-accelerated deep learning inference to compute cross-modal contrastive embeddings and binding scores between target pockets and large compound libraries.

---

## [253] source=multitask_sft_big

**USER:** Generate a zoomed-in karyotype plot of human chromosome 17 (q21.1 to q21.31) displaying copy number variation segments and gene annotations using karyoploteR.

**ASSISTANT:** instant_compute: Rendering genomic region plots with karyoploteR is a lightweight R-based visualization task that executes rapidly in a local or sandbox environment without requiring distributed cloud infrastructure.

---

## [254] source=multitask_sft_big

**USER:** Interactively explore and visualize differentially methylated regions alongside RNA-seq expression tracks using Bioconductor GenomicRanges objects in epivizr.

**ASSISTANT:** instant_compute: Epivizr executes lightweight R/Bioconductor operations to serve and render genomic ranges without requiring distributed cloud pipelines or heavy GPU models.

---

## [255] source=multitask_sft_big

**USER:** Assess and correct dye bias across a multi-sample cohort of Illumina HumanMethylation450 BeadChip arrays using skew-normal distribution modeling in skewr.

**ASSISTANT:** cloud_workflow: Processing multi-sample Illumina DNA methylation array intensity data and executing statistical dye-bias normalization pipelines require dedicated compute infrastructure suitable for batch bioinformatics workflows.

---

## [256] source=multitask_sft_big

**USER:** Query published eQTL datasets for a set of GWAS lead variants to identify associated target genes and tissue-specific expression effects.

**ASSISTANT:** instant_compute: Querying the Qtlizer database via its API to retrieve eQTL summary statistics is lightweight and returns results in seconds without demanding cloud pipeline infrastructure.

---

## [257] source=multitask_sft_big

**USER:** Generate 3D low-energy conformers, enumerate tautomers, and sample ionization states for a batch of candidate small-molecule SMILES strings using Gypsum-DL.

**ASSISTANT:** cloud_workflow: Enumerating ionization states, chiral forms, and 3D conformers across chemical structures requires distributed, multi-threaded batch processing suitable for a cloud workflow.

---

## [258] source=multitask_sft_big

**USER:** Align multiple transcript isoforms across orthologous mammalian genomes to identify conserved exon structures and alternative splicing events using MIRAGE.

**ASSISTANT:** cloud_workflow: The workflow executes a computationally demanding multi-step comparative transcriptomics alignment pipeline requiring cloud-scale compute resources and genomic reference data.

---

## [259] source=multitask_sft_big

**USER:** Perform score-based Gene Ontology enrichment analysis on my RNA-seq differential expression results using topGO to identify significantly enriched biological processes based on gene p-values.

**ASSISTANT:** cloud_workflow: This requires executing a specialized R/Bioconductor computational pipeline on expression datasets, which runs in a cloud environment.

---

## [260] source=multitask_sft_big

**USER:** Cluster and identify distinct immune cell sub-populations across a batch of high-dimensional flow cytometry FCS files using automated flowMeans gating.

**ASSISTANT:** cloud_workflow: The flowMeans tool runs a multi-step non-parametric clustering pipeline on high-dimensional single-cell cytometry datasets requiring cloud-based workflow execution.

---

## [261] source=multitask_sft_big

**USER:** Generate a density-preserving UMAP (densMAP) dimensionality reduction plot from my single-cell RNA-seq expression matrix to assess transcriptomic cluster density variations.

**ASSISTANT:** cloud_workflow: Running density-preserving dimension reduction on high-dimensional single-cell transcriptomics matrices requires cloud-based pipeline execution and computational resources.

---

## [262] source=multitask_sft_big

**USER:** Infer high-confidence functional targets of miR-155 by integrating sequence-based prediction scores with transcriptomic log-fold change data from overexpression RNA-seq experiments.

**ASSISTANT:** cloud_workflow: TargetScore requires a multi-step bioinformatics processing pipeline that applies variational Bayesian modeling across genome-wide expression datasets and sequence feature matrices.

---

## [263] source=multitask_sft_big

**USER:** Identify enriched transcription factor binding motifs from ranked ChIP-seq peak regions using BCRANK.

**ASSISTANT:** cloud_workflow: Running BCRANK requires executing an R/Bioconductor pipeline on genomic FASTA inputs and ranked peak data, which fits batch cloud workflow execution.

---

## [264] source=multitask_sft_big

**USER:** Analyze raw small RNA sequencing FASTQ reads from human serum samples to perform adapter trimming, QC, and quantify known and novel microRNAs.

**ASSISTANT:** cloud_workflow: nf-core/smrnaseq is a multi-step Nextflow pipeline that requires scalable cloud compute for read trimming, reference alignment, QC, and miRNA quantification on high-throughput sequencing data.

---

## [265] source=multitask_sft_big

**USER:** Process raw Ribo-seq FASTQ reads from human cell lines to assess ribosome footprint size distribution, determine P-site offsets, and quantify translation efficiency across coding sequences.

**ASSISTANT:** cloud_workflow: RiboProfiling is a multi-step high-throughput sequencing pipeline that requires heavy cloud compute resources for alignment, quality control, and translation quantification.

---

## [266] source=multitask_sft_big

**USER:** Infer transcription factor regulatory activities and target gene dynamics from paired tumor and control transcriptomic expression matrices using the PECA pipeline.

**ASSISTANT:** cloud_workflow: PECA runs an intensive multi-step statistical transcriptomics modeling pipeline on genomic datasets requiring asynchronous cloud compute.

---

## [267] source=multitask_sft_big

**USER:** Generate 1280-dimensional Universal Cell Embeddings (UCE) from my processed PBMC AnnData h5ad file for cross-tissue single-cell representation learning.

**ASSISTANT:** cloud_models: Extracting embeddings with Universal Cell Embedding requires executing a deep-learning single-cell foundation model on cloud GPU infrastructure.

---

## [268] source=multitask_sft_big

**USER:** Execute the CeTF PCIT and RIF analysis pipeline on my RNA-seq normalized expression counts and candidate transcription factor list to identify key regulatory drivers and build co-expression networks.

**ASSISTANT:** cloud_workflow: This multi-step transcriptomic network inference and regulatory impact factor analysis is computationally intensive and requires distributed pipeline execution on cloud infrastructure.

---

## [269] source=multitask_sft_big

**USER:** Analyze quantified phosphoproteomics data to impute missing phosphosite values, score kinase-substrate relationships, and reconstruct active signal transduction networks using the PhosR pipeline.

**ASSISTANT:** cloud_workflow: PhosR is a multi-step computational phosphoproteomics pipeline requiring orchestrated cloud processing for data filtering, imputation, kinase activity scoring, and downstream pathway reconstruction.

---

## [270] source=multitask_sft_big

**USER:** Process raw paired-end RNA-seq FASTQ files from a 24-sample patient cohort to generate transcript-level abundance matrices and differential expression results.

**ASSISTANT:** cloud_workflow: Executing end-to-end multi-sample transcriptomic alignment and quantification requires orchestrating resource-intensive batch pipelines on scalable cloud infrastructure.

---

## [271] source=multitask_sft_big

**USER:** Quantify target protein knockdown from raw 16-bit TIFF Western blot images across a 6-point PROTAC dose-response series, normalizing band densitometry against beta-actin controls and exporting relative expression statistics.

**ASSISTANT:** cloud_workflow: Multi-step image processing involving lane detection, background subtraction, and densitometric normalization across high-resolution blot files requires an asynchronous cloud data pipeline.

---

## [272] source=multitask_sft_big

**USER:** Run differential protein expression analysis on MaxQuant label-free quantification (LFQ) output using DEqMS to adjust for peptide-spectrum match variance across treatment and control groups.

**ASSISTANT:** cloud_workflow: This is a multi-step omics data processing pipeline that requires executing standardized bioinformatic workflows on cloud compute infrastructure.

---

## [273] source=multitask_sft_big

**USER:** Detect small indels and single nucleotide variants by comparing high-depth tumor and normal BAM files across target genomic regions.

**ASSISTANT:** cloud_workflow: Processing high-throughput sequencing BAM alignments for somatic variant and indel calling requires scalable compute infrastructure and storage managed in cloud workflows.

---

## [274] source=multitask_sft_big

**USER:** Predict and extract secondary structure features, including minimum free energy (MFE), base-pairing probabilities, and stem-loop motifs, for a 450-nt therapeutic mRNA untranslated region.

**ASSISTANT:** cloud_workflow: Evaluating RNA thermodynamic ensembles and secondary structure features involves multi-step command-line bioinformatics pipelines using toolkits like ViennaRNA.

---

## [275] source=multitask_sft_big

**USER:** Run a Reactome gene set enrichment analysis (GSEA) on my ranked list of differentially expressed genes from an RNA-seq experiment to identify significantly enriched signaling pathways.

**ASSISTANT:** cloud_workflow: Executing GSEA with ReactomePA involves running an R/Bioconductor statistical pipeline with pathway database queries and visualization generation in a cloud environment.

---

## [276] source=multitask_sft_big

**USER:** Fine-map candidate causal variants and protein-coding genes within a 4 Mb QTL interval on mouse chromosome 11 identified in an F2 cross for insulin resistance across C57BL/6J and 129S1/SvImJ strains.

**ASSISTANT:** cloud_workflow: Executing mousefm requires automated extraction, cross-strain variant querying, and algorithmic candidate prioritization over genomic intervals via multi-step cloud-based workflow execution.

---

## [277] source=multitask_sft_big

**USER:** Download and convert all raw paired-end sequencing data from GEO accession GSE152418 into FASTQ format for downstream transcriptomic analysis.

**ASSISTANT:** cloud_workflow: Retrieving and converting large SRA datasets from GEO into FASTQ format requires long-running cloud batch processing and high I/O bandwidth.

---

## [278] source=multitask_sft_big

**USER:** Analyze longitudinal gut microbiome compositional shifts across infant stool samples collected over 12 months and visualize temporal taxonomic trajectories using miaViz.

**ASSISTANT:** cloud_workflow: Tracking taxon abundance trajectories across serial metagenomic profiles requires orchestrating a multi-step R/Bioconductor pipeline on serialized TreeSummarizedExperiment data.

---

## [279] source=multitask_sft_big

**USER:** Infer maximum-likelihood gene phylogenies and model codon substitution rates across a multi-species ortholog dataset using the nf-core/genephylomodeler pipeline.

**ASSISTANT:** cloud_workflow: It is an nf-core Nextflow workflow requiring multi-step, scalable cloud or HPC execution to perform compute-intensive phylogenetic modeling.

---

## [280] source=multitask_sft_big

**USER:** Identify putative upstream regulators and sign-consistent causal signaling subnets from our differential gene expression dataset using the CausalR SCAN algorithm.

**ASSISTANT:** cloud_workflow: Running CausalR's sequential causal network scan involves multi-step graph traversal, network scoring, and hypothesis testing on biological interaction graphs that require cloud pipeline execution.

---

## [281] source=multitask_sft_big

**USER:** Normalize my RNA-seq raw count matrix to remove unwanted technical batch variation across samples using empirical control genes with RUVSeq before differential expression analysis.

**ASSISTANT:** cloud_workflow: RUVSeq performs data-intensive factor analysis and normalization across transcriptomic count matrices, requiring a multi-step bioinformatics processing workflow in the cloud.

---

## [282] source=multitask_sft_big

**USER:** Identify and prioritize novel therapeutic targets from an RNA-seq count matrix comparing triple-negative breast cancer biopsies against adjacent normal tissues.

**ASSISTANT:** cloud_workflow: Prioritizing therapeutic targets from transcriptomic profiles requires an asynchronous, multi-step pipeline integrating differential expression, network centrality, and druggability annotation.

---

## [283] source=multitask_sft_big

**USER:** Run pathway and subnetwork enrichment analysis on a list of dysregulated KEGG metabolite IDs from an untargeted metabolomics experiment using FELLA.

**ASSISTANT:** cloud_workflow: FELLA requires loading large pre-built KEGG network models and executing diffusion algorithms, necessitating an asynchronous cloud-based bioinformatics workflow environment.

---

## [284] source=multitask_sft_big

**USER:** Run the LFA pipeline on our cohort of paired tumor-normal BAM files to call and annotate low-frequency somatic variants across targeted genomic regions.

**ASSISTANT:** cloud_workflow: This task involves high-throughput NGS data processing and variant discovery across large BAM files, requiring cloud-orchestrated workflow execution.

---

## [285] source=multitask_sft_big

**USER:** Identify core gene expression modules and attractor pathways across multiple cell differentiation stages from a normalized bulk RNA-seq dataset using the attract framework.

**ASSISTANT:** cloud_workflow: The attract pipeline requires multi-step statistical modeling, synexpression group decomposition, and pathway enrichment across large transcriptomic matrices, necessitating asynchronous execution in a cloud workflow environment.

---

## [286] source=multitask_sft_big

**USER:** Quantify tumor cellularity and segment cell nuclei from H&E-stained breast cancer tissue microarray (TMA) images to estimate tumor purity.

**ASSISTANT:** cloud_workflow: Processing high-resolution histology images for cell segmentation and cellularity estimation requires an automated, resource-intensive batch image analysis pipeline.

---

## [287] source=multitask_sft_big

**USER:** Design high-efficiency sgRNAs targeting the early exons of human PDCD1 for CRISPR-Cas9 knockout while minimizing predicted off-target cleavage.

**ASSISTANT:** cloud_workflow: Knockout sgRNA design requires executing a multi-step bioinformatics pipeline involving gene annotation mapping, on-target efficiency scoring, and genome-wide off-target alignment.

---

## [288] source=multitask_sft_big

**USER:** Annotate cell clusters in my single-cell RNA-seq dataset by matching cluster expression profiles against a custom list of cell-type marker genes using clustifyr.

**ASSISTANT:** cloud_workflow: Annotating scRNA-seq clusters against marker gene lists requires executing an R-based Bioconductor pipeline on large expression matrices, which demands cloud-based compute and memory resources.

---

## [289] source=multitask_sft_big

**USER:** Build a custom BSgenome Bioconductor package from our newly assembled plant genome FASTA files to enable genome-wide motif scanning and coordinate-based sequence extraction.

**ASSISTANT:** cloud_workflow: Generating and indexing a custom BSgenome data package involves intensive multi-step file processing and validation across full-genome assemblies, making it suited for a cloud bioinformatics pipeline.

---

## [290] source=multitask_sft_big

**USER:** Design a specific oligonucleotide FISH probe targeting the 16S rRNA gene of Pseudomonas aeruginosa with optimal hybridization thermodynamics and minimal cross-hybridization to related Gamma-proteobacteria.

**ASSISTANT:** cloud_design: Oligonucleotide probe design requires combinatorial candidate selection, thermodynamic hybridization modeling, and background database specificity screening performed in the cloud.

---

## [291] source=multitask_sft_big

**USER:** Run a custom GPU-accelerated pipeline on cloud infrastructure to process large-scale single-cell image embeddings.

**ASSISTANT:** cloud_workflow: Executing specialized GPU-heavy compute jobs requires provisioning cloud-based accelerator resources and asynchronous execution rather than lightweight or instant processing.

---

## [292] source=multitask_sft_big

**USER:** Run Bayesian PCA or probabilistic PCA on my incomplete metabolomics feature matrix to impute missing values and generate principal component coordinates for sample clustering.

**ASSISTANT:** instant_compute: Dimensionality reduction and missing-value imputation via PCA algorithms run deterministically within seconds on tabular matrices inside a standard compute sandbox.

---

## [293] source=multitask_sft_big

**USER:** Run comprehensive quality control metrics including insert size and alignment summaries on my sample BAM file using Picard tools.

**ASSISTANT:** cloud_workflow: Processing large BAM files with Picard requires compute- and I/O-intensive tools that must be executed asynchronously in a cloud workflow environment.

---

## [294] source=multitask_sft_big

**USER:** Perform an immunogenomics association analysis using MiDAS on a cohort of 450 cancer patient genotypes to identify HLA allele and amino acid-level variants associated with response to immune checkpoint blockade.

**ASSISTANT:** cloud_workflow: HLA and KIR fine-mapping analysis across multi-sample patient cohorts involves multi-step statistical workflows and heavy tabular genomic processing that require distributed cloud compute.

---

## [295] source=multitask_sft_big

**USER:** Perform co-expressed gene-set enrichment analysis on an RNA-seq time-series dataset to identify drug-responsive pathway clusters using cogena.

**ASSISTANT:** cloud_workflow: Running cogena requires batch multi-step clustering and statistical gene-set enrichment pipelines on expression matrices within a managed compute environment.

---

## [296] source=multitask_sft_big

**USER:** Construct and visualize a directed gene regulatory network from gene expression data using Bioconductor graph infrastructure.

**ASSISTANT:** cloud_workflow: Executing graph algorithms and generating rendered biological network topologies requires an orchestrated R/Bioconductor containerized environment.

---

## [297] source=multitask_sft_big

**USER:** Run the PureCN pipeline on matched tumor-normal BAM and VCF files from a targeted sequencing cohort to determine tumor purity, ploidy, and copy-number biomarkers.

**ASSISTANT:** cloud_workflow: Executing PureCN involves a multi-step genomic pipeline processing large alignment and variant files that requires scalable cloud workflow infrastructure.

---

## [298] source=multitask_sft_big

**USER:** Identify and prioritize candidate genes for drought tolerance by integrating RNA-seq differential expression results and QTL intervals using cageminer.

**ASSISTANT:** cloud_workflow: cageminer executes a multi-step data integration pipeline combining genomic intervals, co-expression networks, and expression matrices that requires cloud workflow execution.

---

## [299] source=multitask_sft_big

**USER:** Trace lineage-specific amino acid substitution paths across an avian influenza phylogenetic tree and MSA to identify adaptive mutation trajectories.

**ASSISTANT:** cloud_workflow: Phylogenetic mutation path reconstruction from multi-sequence alignments requires multi-step compute-intensive bioinformatic pipeline processing on cloud infrastructure.

---

## [300] source=multitask_sft_big

**USER:** Train and validate a gene expression classification model using the cancerclass package to predict clinical outcomes from patient transcriptomic profiles.

**ASSISTANT:** cloud_workflow: The cancerclass workflow requires executing a multi-step transcriptomic pipeline comprising data preprocessing, feature selection, and cross-validated predictive modeling on high-throughput expression data.

---

## [301] source=multitask_sft_big

**USER:** Simulate the phenotypic impact and growth dynamics of a targeted metabolic gene knockout in an E. coli strain over a complete division cycle using the integrated whole-cell simulation framework.

**ASSISTANT:** cloud_workflow: Whole-cell models require orchestrating complex, multi-scale sub-simulations (ODEs, stochastic processes, and flux balance analysis) across extended cellular timelines, necessitating asynchronous cloud pipeline execution.

---

## [302] source=multitask_sft_big

**USER:** Process and reconstruct a raw non-uniformly sampled hyperspectral Raman imaging datacube to correct for spatial sampling variations, remove baseline drift, and produce calibrated spectral maps of the material sample.

**ASSISTANT:** cloud_workflow: Executing non-uniform spectral signal processing and datacube reconstruction requires a multi-step, computationally intensive pipeline handled on cloud infrastructure.

---

## [303] source=multitask_sft_big

**USER:** Identify diagnostic pigengenes and train an interpretable decision tree classifier to distinguish clinical subtypes using my normalized gene expression matrix.

**ASSISTANT:** cloud_workflow: The pigengene pipeline requires multi-step transcriptomic co-expression network module extraction and classification algorithms best suited for cloud workflow execution.

---

## [304] source=multitask_sft_big

**USER:** Analyze paired patient dermatology photographs and accompanying clinical notes using a multimodal biomedical vision-language foundation model to suggest potential diagnoses.

**ASSISTANT:** cloud_models: Inference on large multimodal medical vision-language models requires dedicated cloud GPU resources due to high memory and compute requirements.

---

## [305] source=multitask_sft_big

**USER:** Reconstruct transcript models and identify novel intergenic transcripts by pooling RNA-seq BAM alignments across multiple replicate samples using PRAM.

**ASSISTANT:** cloud_workflow: Processing and pooling large RNA-seq BAM files to assemble and reconstruct transcript models requires high memory, intensive disk I/O, and batch cloud execution.

---

## [306] source=multitask_sft_big

**USER:** Identify and quantify differential alternative splicing events across tumor and normal RNA-seq datasets using EventPointer.

**ASSISTANT:** cloud_workflow: EventPointer executes a multi-step transcriptomic pipeline requiring substantial compute to process transcript structures and calculate splicing event statistics across biological samples.

---

## [307] source=multitask_sft_big

**USER:** Analyze my batch of whole-slide immunohistochemistry images of 5xFAD mouse brain sections to segment and quantify amyloid-beta plaque burden, count, and size distribution across the cortex and hippocampus.

**ASSISTANT:** cloud_workflow: Processing and segmenting large batches of high-resolution histology images requires an automated multi-step bioimage analysis pipeline running on cloud infrastructure.

---

## [308] source=multitask_sft_big

**USER:** Infer a dynamic gene regulatory network from time-series RNA-seq expression data of immune-stimulated cells using Bayesian network modeling.

**ASSISTANT:** cloud_workflow: Gene regulatory network inference using MCMC-based Bayesian linear regression on transcriptomic time-series matrices requires long-running, multi-step pipeline processing on cloud infrastructure.

---

## [309] source=multitask_sft_big

**USER:** Run PCAtools on my normalized RNA-seq gene expression matrix and sample metadata to generate scree plots, biplots, and correlate principal components with clinical covariates.

**ASSISTANT:** cloud_workflow: Running PCAtools on transcriptomics expression matrices involves executing standard batch bioinformatics software within a cloud computational environment.

---

## [310] source=multitask_sft_big

**USER:** Build a unified SQLite genomic annotation database for the human genome assembly GRCh38 incorporating Ensembl and RefSeq transcript models using sitadela.

**ASSISTANT:** cloud_workflow: Downloading, parsing, and indexing multi-source genome annotations into an SQLite database is a long-running, resource-intensive pipeline requiring cloud-based workflow execution.

---

## [311] source=multitask_sft_big

**USER:** Analyze paired AlkAniline-Seq BAM files across human transcriptomes to detect and quantify m7G and m3C RNA modifications at single-base resolution.

**ASSISTANT:** cloud_workflow: Processing large-scale sequencing alignments through the rnamodr AlkAniline-Seq pipeline requires significant computational resources, specialized reference annotations, and multi-step workflow execution.

---

## [312] source=multitask_sft_big

**USER:** Identify potential allosteric binding pockets and calculate druggability scores for the AlphaFold-predicted structure of human KRAS G12D to evaluate small-molecule tractability.

**ASSISTANT:** cloud_workflow: Detecting 3D surface cavities and calculating volumetric and physicochemical druggability metrics requires executing a dedicated structural bioinformatics analysis pipeline on the cloud.

---

## [313] source=multitask_sft_big

**USER:** Predict the zygosity and loss-of-heterozygosity status of somatic mutations in patient tumor samples using paired small variant VCFs and copy number segmentation data.

**ASSISTANT:** cloud_workflow: Integrating genomic variant calls with copy number profiles and purity estimates to assess variant zygosity requires a multi-step, computationally intensive bioinformatic pipeline run in the cloud.

---

## [314] source=multitask_sft_big

**USER:** Identify coordinated dysregulated gene pathways across cancer progression stages from an RNA-seq count matrix using the CoGPS pipeline.

**ASSISTANT:** cloud_workflow: Executing the CoGPS transcriptomic pathway analysis pipeline requires multi-step workflow orchestration and compute infrastructure in the cloud.

---

## [315] source=multitask_sft_big

**USER:** Call statistically significant enrichment peaks and calculate binding scores from mapped ChIP-seq BAM alignments using the CSAR pipeline.

**ASSISTANT:** cloud_workflow: Processing high-throughput sequencing alignments for epigenomic peak calling requires distributed cloud compute resources and file storage.

---

## [316] source=multitask_sft_big

**USER:** Calculate Storey q-values and estimate the proportion of true null hypotheses (pi0) from a list of differential expression p-values to control the false discovery rate.

**ASSISTANT:** instant_compute: Estimating FDR q-values from an input vector of p-values is a lightweight, deterministic statistical calculation that completes in seconds within an execution sandbox.

---

## [317] source=multitask_sft_big

**USER:** Cluster a multi-FASTA file of 150,000 bacterial protein sequences at 80% sequence identity and 80% alignment coverage to reduce redundancy before downstream phylogenomic analysis.

**ASSISTANT:** cloud_workflow: Clustering large sequence datasets with MMseqs2 requires an asynchronous, compute-heavy multi-step pipeline executed on cloud infrastructure.

---

## [318] source=multitask_sft_big

**USER:** Run the smoothclust workflow on my single-cell RNA-seq count matrix to smooth dropout noise and identify distinct cell subpopulation clusters.

**ASSISTANT:** cloud_workflow: Executing transcriptomics clustering pipelines on high-dimensional count matrices requires cloud-based workflow infrastructure for smoothing, matrix manipulation, and unsupervised clustering.

---

## [319] source=multitask_sft_big

**USER:** Cluster time-series RNA-seq gene expression profiles from a multi-timepoint experiment to identify distinct temporal co-expression patterns using TMixClust.

**ASSISTANT:** cloud_workflow: TMixClust performs complex mixture-model clustering on large transcriptomic time-series matrices, requiring asynchronous cloud workflow execution.

---

## [320] source=multitask_sft_big

**USER:** Retrieve the gene summary, genomic coordinates, and reference sequence accessions for human TP53 from the NCBI database.

**ASSISTANT:** instant_cited: Querying NCBI via biodbNcbi is a lightweight, real-time database lookup that returns verified biological records with cited database accessions.

---

## [321] source=multitask_sft_big

**USER:** Run Bayesian fine-mapping and variant effect size estimation on genome-wide summary statistics to identify credible causal variants associated with type 2 diabetes.

**ASSISTANT:** cloud_workflow: Bayesian GWAS fine-mapping involves high-throughput multi-step batch computation over large linkage disequilibrium matrices and summary statistics, requiring scalable cloud execution.

---

## [322] source=multitask_sft_big

**USER:** Analyze multi-channel fluorescence microscopy images of HeLa cells stained with DAPI and EdU to segment nuclei and quantify the proportion of cells in G0/G1, S, and G2/M phases.

**ASSISTANT:** cloud_workflow: Segmenting high-resolution microscopy images and extracting single-cell nuclear fluorescence intensity metrics across large image sets requires a multi-step cloud-based bioimage analysis pipeline.

---

## [323] source=multitask_sft_big

**USER:** Retrieve the FDA-approved drug label information for pembrolizumab, specifically detailing its indications, boxed warnings, and dosage contraindications.

**ASSISTANT:** instant_cited: Fetching regulatory drug label text from databases like openFDA is an instantaneous reference retrieval task that provides cited factual information without requiring heavy computational infrastructure.

---

## [324] source=multitask_sft_big

**USER:** Extract and quantify de novo mutational signatures from a cohort of somatic VCF files using empirical Bayesian NMF.

**ASSISTANT:** cloud_workflow: Deconvolving mutational signatures across multi-sample genomic cohorts requires multi-step variant matrix generation and intensive matrix factorization executed as a cloud pipeline.

---

## [325] source=multitask_sft_big

**USER:** Perform a longitudinal differential abundance analysis on our multi-timepoint count matrix and metadata using the metagenomeSeq workflow to detect features with significant temporal variation.

**ASSISTANT:** cloud_workflow: This request requires executing a multi-step, compute-intensive statistical pipeline on cloud infrastructure to process longitudinal abundance data across time points.

---

## [326] source=multitask_sft_big

**USER:** Generate dot plots, enrichment maps, and gene-concept network (cnetplot) visualizations from my DESeq2 RNA-seq differential expression results.

**ASSISTANT:** cloud_workflow: Running automated functional enrichment analysis and rendering publication-ready graphical figures from tabular transcriptomics data requires a containerized Bioconductor pipeline execution environment.

---

## [327] source=multitask_sft_big

**USER:** Identify and prioritize candidate cell-surface receptor targets from a single-cell RNA-seq expression matrix of tumor and matched normal tissue samples.

**ASSISTANT:** cloud_workflow: Executing the SurfR pipeline on large-scale transcriptomics datasets involves multi-step data processing, statistical filtering, and surfaceome annotation that require scalable cloud computing resources.

---

## [328] source=multitask_sft_big

**USER:** Cluster and analyze B-cell receptor CDR3 sequences from my 10x Genomics single-cell V(D)J sequencing dataset using scRepertoire to identify shared clonotype lineages across patient samples.

**ASSISTANT:** cloud_workflow: Running scRepertoire-based BCR repertoire sequence clustering and clonotype integration involves multi-step single-cell bioinformatics tools requiring dedicated cloud workflow execution.

---

## [329] source=multitask_sft_big

**USER:** Perform functional enrichment analysis and generate an integrated protein-protein interaction network visualization for my set of differentially expressed proteins from a shotgun proteomics dataset.

**ASSISTANT:** cloud_workflow: Constructing and rendering interactive functional enrichment networks from proteomics data requires a multi-step bioinformatics pipeline running asynchronously in the cloud.

---

## [330] source=multitask_sft_big

**USER:** Identify differentially methylated regions (DMRs) across the genome between treated and control whole-genome bisulfite sequencing (WGBS) samples using the DMRcate pipeline.

**ASSISTANT:** cloud_workflow: Analyzing genome-wide sequencing data for differential methylation using DMRcate requires substantial computational resources, multi-step genomic file processing, and specialized Bioconductor package execution in a cloud bioinformatics workflow.

---

## [331] source=multitask_sft_big

**USER:** Detect dysregulated microRNA clusters and their co-targeting pathways from cancer RNA-seq gene expression matrices using panomiR.

**ASSISTANT:** cloud_workflow: panomiR executes an end-to-end multi-step transcriptomics workflow integrating pathway enrichment with miRNA regulatory network modeling that requires cloud execution resources.

---

## [332] source=multitask_sft_big

**USER:** Run pathway enrichment analysis on my RNA-seq differential expression dataset and generate an interactive iSEEpathways dashboard to visualize dysregulated biological processes.

**ASSISTANT:** cloud_workflow: Executing transcriptomic pathway enrichment algorithms and hosting the interactive Bioconductor iSEE application requires a multi-step cloud-based workflow environment.

---

## [333] source=multitask_sft_big

**USER:** Identify significant narrow peaks from paired-end H3K4me3 ChIP-seq BAM files against a matched input control to characterize active transcription start sites.

**ASSISTANT:** cloud_workflow: Peak calling from large genomic alignment BAM files requires intensive read processing and statistical modeling best executed on cloud workflow infrastructure.

---

## [334] source=multitask_sft_big

**USER:** Annotate a cohort VCF file with precomputed genome-wide conservation and functional scores, such as phastCons and CADD, using the GenomicScores package.

**ASSISTANT:** cloud_workflow: Extracting and overlapping position-level annotations from multi-gigabyte genomic score databases across thousands of variants requires distributed cloud batch computing.

---

## [335] source=multitask_sft_big

**USER:** Visualize base call frequencies, insertions, and deletions across targeted genomic loci from BAM alignment files using BBCAnalyzer.

**ASSISTANT:** cloud_workflow: Extracting alignment metrics and rendering base-count plots from large sequencing BAM files requires cloud-based bioinformatics compute and storage resources.

---

## [336] source=multitask_sft_big

**USER:** Annotate coding sequences, promoters, origins of replication, and selection markers in a newly assembled 6.5 kb plasmid FASTA file.

**ASSISTANT:** cloud_workflow: Feature annotation requires running sequence alignment tools against curated plasmid feature databases via a multi-step bioinformatics pipeline.

---

## [337] source=multitask_sft_big

**USER:** Run the MASTR workflow on raw paired-end RNA-seq FASTQ files to perform quality control, read alignment, transcript quantification, and identification of differential expression between treated and control conditions.

**ASSISTANT:** cloud_workflow: The MASTR transcriptomics pipeline processes high-throughput sequencing datasets through multi-step compute-intensive alignment and quantification steps that require cloud-based batch orchestration.

---

## [338] source=multitask_sft_big

**USER:** Run a multi-sample CAMERA differential analysis to identify and annotate differential peaks, isotopic clusters, and adducts across sample groups.

**ASSISTANT:** cloud_workflow: Generating a multi-sample differential report with CAMERA requires running multi-step bioinformatics pipeline software and compute-heavy peak grouping on cloud infrastructure.

---

## [339] source=multitask_sft_big

**USER:** Run a hierarchical association testing pipeline on my large-scale GWAS genotype and phenotype data to detect significantly associated SNP clusters while controlling the family-wise error rate.

**ASSISTANT:** cloud_workflow: Hierarchical GWAS analysis involves multi-step processing of large genomic variant datasets that require distributed compute and batch execution in the cloud.

---

## [340] source=multitask_sft_big

**USER:** Run Gene Set Enrichment Analysis (GSEA) using the escape method on my precomputed differential expression gene list to identify dysregulated biological pathways.

**ASSISTANT:** cloud_workflow: Executing an escape-based GSEA pipeline on transcriptomic differential expression data requires containerized, asynchronous workflow execution on cloud infrastructure.

---

## [341] source=multitask_sft_big

**USER:** Run region-level gene set enrichment analysis on differentially methylated regions identified from Illumina Infinium MethylationEPIC data to adjust for probe density bias across GO terms.

**ASSISTANT:** cloud_workflow: Executing missMethyl's region-level gene set testing requires a dedicated R/Bioconductor environment to process genomic intervals against annotated pathway databases.

---

## [342] source=multitask_sft_big

**USER:** Retrieve the official phenotype names and labels for a list of Human Phenotype Ontology identifiers, such as HP:0001250 and HP:0000252.

**ASSISTANT:** instant_cited: Fetching HPO term names requires a rapid biomedical ontology database query returning standard referenced metadata without intensive computational overhead.

---

## [343] source=multitask_sft_big

**USER:** Train and evaluate a Random Forest classification model with 10-fold cross-validation on a normalized tumor RNA-seq expression dataset to predict cancer subtype and identify top predictive biomarker genes using MLInterfaces.

**ASSISTANT:** cloud_workflow: The task involves intensive multi-step data transformation, cross-validated machine learning training, and feature extraction across high-dimensional transcriptomic matrices requiring cloud infrastructure.

---

## [344] source=multitask_sft_big

**USER:** Scan the human reference genome (GRCh38) to identify all exact and single-mismatch binding sites for a dictionary of 50,000 custom 20-nt probe sequences using BSgenome.

**ASSISTANT:** cloud_workflow: Matching a large dictionary of oligonucleotide patterns across an entire mammalian reference genome requires high-memory sequence data structures and substantial compute time, necessitating an asynchronous cloud workflow.

---

## [345] source=multitask_sft_big

**USER:** Generate an interactive HTML exploration and summary report from differential expression results obtained with derfinder for my RNA-seq dataset.

**ASSISTANT:** cloud_workflow: Running the regionreport pipeline requires cloud-based execution of R/Bioconductor dependencies on large genomic range data to generate comprehensive graphical HTML reports.

---

## [346] source=multitask_sft_big

**USER:** Calculate base-level coverage and extract splice junction counts across specific target regions from an aligned RNA-seq BAM file using megadepth.

**ASSISTANT:** cloud_workflow: Processing high-throughput sequencing BAM files for coverage quantification requires scalable compute infrastructure and storage characteristic of cloud bioinformatics workflows.

---

## [347] source=multitask_sft_big

**USER:** Detect and flag doublet-driven cell clusters in my 10x single-cell RNA-seq dataset using scDblFinder.

**ASSISTANT:** cloud_workflow: Executing scDblFinder on single-cell count matrices is an intensive bioinformatics pipeline that requires dedicated cloud workflow compute resources.

---

## [348] source=multitask_sft_big

**USER:** Generate read count, GC content, and per-base quality score statistics for my raw paired-end FASTQ sequencing datasets to evaluate data quality prior to alignment.

**ASSISTANT:** cloud_workflow: Analyzing high-throughput raw FASTQ files requires asynchronous pipeline execution and dedicated storage resources on cloud infrastructure.

---

## [349] source=multitask_sft_big

**USER:** Run Bayesian fine-mapping using deep variational inference on my GWAS summary statistics and LD matrix for the 17q21 locus to identify 95% credible causal variants.

**ASSISTANT:** cloud_workflow: Fine-mapping with deep variational inference involves computationally intensive optimization over large genomic LD matrices and summary statistics that must be executed on cloud infrastructure.

---

## [350] source=multitask_sft_big

**USER:** I have raw whole-exome sequencing FASTQ files from a child with an undiagnosed rare disorder and both parents; run a trio variant calling and inheritance filtering pipeline to identify candidate de novo and recessive causal variants.

**ASSISTANT:** cloud_workflow: Trio variant calling requires resource-intensive multi-step genomic alignment and joint calling pipelines on large sequencing datasets that must execute as batch workflows in the cloud.

---

## [351] source=multitask_sft_big

**USER:** Perform a two-way ANOVA on clonogenic assay data to assess the statistical interaction between a novel chemotherapeutic agent and radiation dose on tumor cell colony survival.

**ASSISTANT:** cloud_workflow: Running the CFAssay analytical pipeline on multi-condition colony formation data requires cloud-based R package execution and structured statistical report generation.

---

## [352] source=multitask_sft_big

**USER:** Run Independent Hypothesis Weighting (IHW) on our DESeq2 differential expression p-values using base mean expression as an informative covariate to control the false discovery rate at 5%.

**ASSISTANT:** cloud_workflow: Executing Independent Hypothesis Weighting across transcriptome-scale differential test statistics is a data-intensive bioinformatics pipeline managed via asynchronous cloud execution.

---

## [353] source=multitask_sft_big

**USER:** Perform targeted metabolite identification and peak quantification on a batch of GC-MS netCDF raw files using retention index markers and a reference mass spectral library.

**ASSISTANT:** cloud_workflow: Processing raw GC-MS chromatograms through retention index correction, peak picking, and library matching requires multi-file, computationally intensive data processing pipelines suited for cloud workflow execution.

---

## [354] source=multitask_sft_big

**USER:** Construct a genome-scale metabolic network from KEGG KGML files, integrate differential gene expression profiles from my RNA-seq study, and extract significantly dysregulated metabolic subpaths.

**ASSISTANT:** cloud_workflow: Integrating network topology with transcriptomic data and executing path-mining algorithms requires a multi-step, computationally demanding bioinformatics pipeline best handled in a cloud execution environment.

---

## [355] source=multitask_sft_big

**USER:** Evaluate 3' to 5' probe decay profiles across Affymetrix CEL files and correct for RNA degradation using integrated calibration curves.

**ASSISTANT:** cloud_workflow: Processing raw microarray CEL files and running integrated calibration models requires multi-step computational pipeline execution on cloud infrastructure.

---

## [356] source=multitask_sft_big

**USER:** Predict immune checkpoint inhibitor response and compute immune cell infiltration scores from my normalized bulk RNA-seq dataset of 45 melanoma patients using the EASIER pipeline.

**ASSISTANT:** cloud_workflow: The EASIER analysis involves multi-step pathway enrichment, transcription factor activity inference, and cell deconvolution across a transcriptomic cohort, requiring multi-step cloud workflow execution.

---

## [357] source=multitask_sft_big

**USER:** Identify and call non-reference retrotransposon insertions (LINE-1, Alu, and SVA) from tumor-normal whole-genome sequencing BAM files using the SVAretro pipeline.

**ASSISTANT:** cloud_workflow: Detecting retrotransposon structural variants across large genomic BAM files requires multi-step, computationally intensive pipeline execution on cloud infrastructure.

---

## [358] source=multitask_sft_big

**USER:** Aggregate single-cell RNA-seq expression data along a hierarchical clustering lineage tree into a TreeSummarizedExperiment object to test for differential abundance and expression across distinct tree branches.

**ASSISTANT:** cloud_workflow: Constructing hierarchical tree structures and performing node-level aggregations on large single-cell datasets requires multi-step computational pipeline orchestration on cloud infrastructure.

---

## [359] source=multitask_sft_big

**USER:** Perform an integrated genomic analysis combining multi-sample copy number variation (CNV) calls with matched RNA-seq gene expression data to identify genes whose expression is significantly modulated by CNVs across a patient cohort.

**ASSISTANT:** cloud_workflow: Integrating cohort-scale CNV range summarization with full transcriptomic expression matrices involves multi-step statistical testing and heavy data processing best suited for distributed cloud pipeline execution.

---

## [360] source=multitask_sft_big

**USER:** I have a list of SRA accessions (SRR11054321, SRR11054322) from a published RNA-seq study and want to download and convert them into paired-end FASTQ files using SRA-tools.

**ASSISTANT:** cloud_workflow: This is an nf-core Nextflow pipeline designed to orchestrate the batch downloading and extraction of large sequencing datasets from NCBI SRA on cloud computing infrastructure.

---

## [361] source=multitask_sft_big

**USER:** Quantify gene expression profiles from paired-end metatranscriptomic RNA-seq FASTQ files by aligning reads against the Integrated Gene Catalog (IGC).

**ASSISTANT:** cloud_workflow: Aligning high-throughput sequencing reads against a massive reference gene catalog requires computationally intensive, multi-step pipeline execution on cloud infrastructure.

---

## [362] source=multitask_sft_big

**USER:** Generate a customized karyotype ideogram plotting copy number alteration (CNA) regions across human chromosomes from a BED file using the karyoploteR Bioconductor package.

**ASSISTANT:** instant_compute: Rendering chromosome ideograms and genomic track visualizations with karyoploteR is a deterministic, lightweight R script that executes within seconds.

---

## [363] source=multitask_sft_big

**USER:** Run HMMcopy on single-cell whole-genome sequencing BAM files to correct for GC-content and mappability biases and call copy number alterations across the genome.

**ASSISTANT:** cloud_workflow: HMMcopy processes large genomic BAM files through multi-step read counting, bias correction, and HMM segmentation requiring cloud-orchestrated computational pipelines.

---

## [364] source=multitask_sft_big

**USER:** Run a combined metagenomic assembly and binning pipeline across longitudinal gut microbiome sequencing reads to recover and refine high-quality metagenome-assembled genomes (MAGs).

**ASSISTANT:** cloud_workflow: Metagenomic assembly, read alignment, and multi-tool bin refinement involve heavy, long-running batch computational steps that require distributed cloud infrastructure.

---

## [365] source=multitask_sft_big

**USER:** Validate a list of gene identifiers to verify that they conform to standard Ensembl ID patterns and differentiate between gene, transcript, and protein accessions.

**ASSISTANT:** instant_compute: Pattern validation against Ensembl accession regular expressions is a lightweight, deterministic parsing task that executes immediately without requiring cloud pipeline infrastructure.

---

## [366] source=multitask_sft_big

**USER:** Predict the blood-brain barrier permeability and CNS penetration profile for a candidate series of small-molecule LRRK2 inhibitors targeting Parkinson's disease.

**ASSISTANT:** cloud_models: Evaluating CNS penetration requires running inference on pre-trained deep learning or ensemble QSAR models specialized in blood-brain barrier pharmacokinetics.

---

## [367] source=multitask_sft_big

**USER:** Visualize a phylogenetic tree of orthologous transcript isoforms alongside both an expression heatmap and a barplot of fold changes stacked at the same position using ggtreeExtra.

**ASSISTANT:** instant_compute: This task involves running lightweight R plotting scripts using ggtree and ggtreeExtra on provided tree and transcriptomic matrices, which executes quickly in a sandbox environment.

---

## [368] source=multitask_sft_big

**USER:** Perform gene set enrichment analysis on my narrow ChIP-seq peak BED file using PolyEnrich to account for gene locus length bias and identify enriched biological pathways.

**ASSISTANT:** cloud_workflow: Executing the PolyEnrich Bioconductor algorithm on peak data against functional gene set databases requires a multi-step genomic cloud workflow.

---

## [369] source=multitask_sft_big

**USER:** Simulate dynamic metabolite fluxes and biomass growth over a 48-hour fermentation cycle using a comprehensive Escherichia coli kinetic ODE model.

**ASSISTANT:** cloud_workflow: Integrating large, stiff systems of ordinary differential equations across extended time courses requires dedicated, asynchronous cloud computational pipelines.

---

## [370] source=multitask_sft_big

**USER:** Predict the CYP450 inhibition profile across five major isoforms (CYP1A2, 2C9, 2C19, 2D6, 3A4) and estimate human intrinsic and hepatic clearance for a prioritized series of lead oncology candidates.

**ASSISTANT:** cloud_workflow: This task requires an orchestrated multi-model pipeline that evaluates multiple metabolic endpoints and integrates in vitro-to-in vivo clearance extrapolation in the cloud.

---

## [371] source=multitask_sft_big

**USER:** Annotate cell types in a single-cell RNA-seq dataset of human peripheral blood mononuclear cells using pretrained immune models with scAnnotatR.

**ASSISTANT:** cloud_workflow: Single-cell cell type annotation with scAnnotatR involves running an automated, resource-intensive transcriptomics processing pipeline on large expression matrices.

---

## [372] source=multitask_sft_big

**USER:** Detect differentially methylated regions across predefined promoter and CpG island intervals from targeted bisulfite sequencing count data comparing tumor and normal samples.

**ASSISTANT:** cloud_workflow: Running differential methylation modeling and permutation testing on targeted bisulfite sequencing data requires multi-step bioinformatics pipeline execution on cloud infrastructure.

---

## [373] source=multitask_sft_big

**USER:** Identify differentially co-expressed gene modules and pairs between tumor and normal tissue transcriptomic profiles using empirical Bayes modeling.

**ASSISTANT:** cloud_workflow: EBcoexpress performs computationally intensive pairwise correlation modeling and empirical Bayes shrinkage across high-dimensional transcriptomic matrices, requiring batch processing in a cloud workflow environment.

---

## [374] source=multitask_sft_big

**USER:** Run a differential gene expression meta-analysis combining DESeq2, edgeR, and limma on my RNA-seq raw count matrix across treated and untreated conditions using metaseqr2.

**ASSISTANT:** cloud_workflow: The metaseqr2 workflow executes an ensemble of computationally intensive RNA-seq differential expression algorithms that requires batch cloud execution.

---

## [375] source=multitask_sft_big

**USER:** Estimate cell-type proportions from bulk RNA-seq count data using a paired single-cell reference dataset with the lute deconvolution framework.

**ASSISTANT:** cloud_workflow: Transcriptomic deconvolution across multiple algorithms and high-dimensional expression matrices requires cloud-based pipeline execution.

---

## [376] source=multitask_sft_big

**USER:** Call and filter low-frequency single nucleotide variants and indels from targeted amplicon deep-sequencing data using the R453Plus1Toolbox.

**ASSISTANT:** cloud_workflow: Processing high-throughput sequencing data for variant detection and quality filtering requires substantial computational resources managed through a scalable cloud workflow.

---

## [377] source=multitask_sft_big

**USER:** Run the GATK Best Practices germline variant calling pipeline on 30x paired-end Illumina WGS FASTQ files for a trio cohort to produce analysis-ready, joint-genotyped VCF files.

**ASSISTANT:** cloud_workflow: Whole-genome GATK germline analysis is a heavy multi-step pipeline requiring orchestration across distributed high-performance cloud compute.

---

## [378] source=multitask_sft_big

**USER:** Scan a set of ATAC-seq peak regions in BED format against the JASPAR CORE vertebrate motif database to identify candidate transcription factor binding sites.

**ASSISTANT:** cloud_workflow: Genome-wide motif matching across large coordinate sets requires executing containerized Bioconductor workloads with reference genome assemblies on cloud infrastructure.

---

## [379] source=multitask_sft_big

**USER:** Automate the multi-channel clustering and concentration calculation of raw droplet fluorescence data from my multiplex ddPCR assay.

**ASSISTANT:** cloud_workflow: Automated clustering and droplet classification on experimental ddPCR datasets require running computationally intensive Bioconductor workflows on uploaded input files.

---

## [380] source=multitask_sft_big

**USER:** Normalize spatial and intensity-dependent dye biases across raw two-color microarray expression slides using the nnnorm pipeline.

**ASSISTANT:** cloud_workflow: Batch transcriptomic normalization across experimental array datasets requires running standard multi-step bioinformatics pipeline tools in a scalable cloud environment.

---

## [381] source=multitask_sft_big

**USER:** Identify the most stable reference genes from a qPCR Ct dataset across experimental conditions using the geNorm algorithm in SLqPCR.

**ASSISTANT:** instant_compute: Analyzing gene expression stability values from tabular qPCR Ct data via SLqPCR requires minimal computational overhead and completes quickly in a lightweight local or single-container runtime.

---

## [382] source=multitask_sft_big

**USER:** Distribute parallel differential expression and transcript quantification jobs across multiple cluster nodes using RedisParam as the BiocParallel backend.

**ASSISTANT:** cloud_workflow: Orchestrating distributed asynchronous worker queues for large-scale transcriptomic processing requires cloud workflow infrastructure.

---

## [383] source=multitask_sft_big

**USER:** Run the nf-core/airrflow pipeline on our paired-end bulk BCR sequencing FASTQ files to perform V(D)J gene annotation, clonal lineage reconstruction, and repertoire diversity profiling.

**ASSISTANT:** cloud_workflow: nf-core/airrflow is an extensive Nextflow bioinformatics pipeline requiring cloud or cluster infrastructure to process heavy multi-step immune repertoire sequencing workflows.

---

## [384] source=multitask_sft_big

**USER:** Calculate the relative binding free energies (RBFE) for a series of 10 congeneric small-molecule inhibitors bound to CDK2 to prioritize candidates for synthesis.

**ASSISTANT:** cloud_workflow: Alchemical relative binding free energy calculations involve constructing a perturbation network and executing computationally intensive, multi-nanosecond molecular dynamics simulations across multiple lambda windows on cloud GPU infrastructure.

---

## [385] source=multitask_sft_big

**USER:** I have a batch of 30 whole-genome sequencing BAM files stored in AWS S3 and need to convert them back into paired-end FASTQ files for re-alignment against a new reference build.

**ASSISTANT:** cloud_workflow: Extracting FASTQ reads from large BAM files across a cohort requires running a distributed Nextflow bioinformatics pipeline on cloud infrastructure.

---

## [386] source=multitask_sft_big

**USER:** I have Salmon quantification directories (quant.sf files) from 12 RNA-seq samples and an Ensembl transcript-to-gene mapping table. Can you import and summarize these transcript-level abundance estimates to gene-level counts and scaled TPM matrices using tximport for downstream DESeq2 analysis?

**ASSISTANT:** cloud_workflow: Processing multi-sample quantification outputs into gene-level count matrices with tximport requires running an automated bioinformatics pipeline inside an R/Bioconductor containerized cloud environment.

---

## [387] source=multitask_sft_big

**USER:** Identify and quantify metabolites from 1D 1H-NMR spectra of plasma samples against the standard reference library using ASICS.

**ASSISTANT:** cloud_workflow: ASICS executes multi-step spectral preprocessing, library alignment, and statistical deconvolution on metabolomics data requiring containerized cloud pipeline execution.

---

## [388] source=multitask_sft_big

**USER:** Extract unique molecular identifiers from raw paired-end FASTQ reads with UMI-tools, trim adapter sequences and low-quality bases using Trim Galore, and assess read quality with FastQC.

**ASSISTANT:** cloud_workflow: This is a multi-step raw sequencing data preprocessing pipeline requiring high-throughput batch compute and dedicated bioinformatics software execution in the cloud.

---

## [389] source=multitask_sft_big

**USER:** Run the GSReg analysis workflow on multi-sample RNA-seq expression profiles to identify differentially regulated pathways between treatment and control cohorts.

**ASSISTANT:** cloud_workflow: GSReg requires running multi-sample permutation and statistical gene set regulation pipelines on transcriptomic datasets, which requires containerized cloud execution.

---

## [390] source=multitask_sft_big

**USER:** Split my indexed human whole-genome sequencing BAM file into separate BAM files corresponding to specific chromosome regions defined in a BED file.

**ASSISTANT:** cloud_workflow: Splitting large alignment BAM files by genomic coordinates requires high-throughput bioinformatic tools and cloud infrastructure for intensive data processing.

---

## [391] source=multitask_sft_big

**USER:** Perform quality control filtering, sample normalization, and PLS-DA statistical modeling on an untargeted LC-MS metabolomics feature matrix.

**ASSISTANT:** cloud_workflow: Phenomis runs multi-step metabolomics data preprocessing, normalization, and multivariate statistical pipelines that require cloud workflow orchestration for batch omics datasets.

---

## [392] source=multitask_sft_big

**USER:** Analyze patient tumor RNA-seq expression profiles to detect chromosomal copy number variations and regional genomic alterations using the CAFE pipeline.

**ASSISTANT:** cloud_workflow: Processing transcriptomic datasets through the multi-step CAFE analysis pipeline requires high-throughput genomic data parsing and heavy compute best handled by an asynchronous cloud workflow.

---

## [393] source=multitask_sft_big

**USER:** Reconstruct a downstream signaling network from phosphoproteomic perturbation data and a prior knowledge network using linear programming optimization.

**ASSISTANT:** cloud_workflow: Network reconstruction via integer linear programming requires multi-step data integration and computational solver optimization typically orchestrated in cloud workflows.

---

## [394] source=multitask_sft_big

**USER:** Simulate a synthetic single-cell RNA-seq count matrix with continuous developmental trajectories and batch effects derived from my reference dataset using scDesign3.

**ASSISTANT:** cloud_workflow: Fitting probabilistic copula models and simulating high-dimensional single-cell count matrices is computationally demanding and requires pipeline execution in a cloud workflow environment.

---

## [395] source=multitask_sft_big

**USER:** I need to process and render large multiplexed spatial imaging datasets on disk using cytomapper and HDF5Array to avoid out-of-memory errors during downstream analysis.

**ASSISTANT:** cloud_workflow: Handling and processing out-of-memory multi-channel spatial imaging data requires a scalable, multi-step cloud bioinformatics pipeline with adequate I/O and compute resources.

---

## [396] source=multitask_sft_big

**USER:** Identify robustly differentially expressed genes across multiple independent transcriptomic datasets using the Rank Product non-parametric meta-analysis algorithm.

**ASSISTANT:** cloud_workflow: Running RankProd differential expression analysis requires multi-step data matrix processing, permutation testing, and FDR estimation typical of a cloud bioinformatic workflow.

---

## [397] source=multitask_sft_big

**USER:** Retrieve the NSC number, chemical structure, and NCI-60 GI50 bioactivity profile for the anti-cancer compound cisplatin from the NCI database.

**ASSISTANT:** instant_cited: Fetching specific compound records and screening bioactivity from the NCI repository is a direct factual database retrieval that returns cited reference data.

---

## [398] source=multitask_sft_big

**USER:** Normalize multiple Hi-C contact matrices from Cooler (.cool) format across biological replicates using the BNBC method to correct for between-sample systematic biases.

**ASSISTANT:** cloud_workflow: Normalizing genome-wide Hi-C contact matrices from large cooler files involves intensive multi-sample matrix processing that requires distributed cloud computing pipelines.

---

## [399] source=multitask_sft_big

**USER:** Identify statistically significant intra-chromosomal chromatin loops from my 10 kb-binned Hi-C contact matrix and genomic bias files using Fit-Hi-C.

**ASSISTANT:** cloud_workflow: Fit-Hi-C involves multi-step statistical fitting and genomic background probability calculation on large contact matrices, requiring scalable batch compute resources.

---

## [400] source=multitask_sft_big

**USER:** Integrate matched transcriptomic and proteomic profiles from our clinical trial cohort to train and cross-validate a multi-view classification model for predicting patient drug response.

**ASSISTANT:** cloud_workflow: Multi-view cross-validation, feature selection, and ensemble classification across high-dimensional multi-omics datasets require a multi-step, resource-intensive bioinformatics workflow pipeline.

---

## [401] source=multitask_sft_big

**USER:** Detect copy number alterations and segments across a cohort of tumor samples from high-density array CGH data using parallelized segmentation algorithms.

**ASSISTANT:** cloud_workflow: Analyzing genome-wide array CGH data across multiple samples requires scalable cloud compute and distributed memory to perform parallel segmentation and copy number variant calling.

---

## [402] source=multitask_sft_big

**USER:** Classify the subcellular localization of unassigned proteins by running k-NN transfer learning with pRoloc integrating spatial proteomics profile data and Gene Ontology auxiliary annotations.

**ASSISTANT:** cloud_workflow: This is a multi-step spatial proteomics data pipeline requiring cloud-based workflow execution for auxiliary data integration, cross-validation, and algorithmic classification.

---

## [403] source=multitask_sft_big

**USER:** Generate a trackViewer dandelion plot to visualize alternative splicing events and transcript-level variant distributions across the TP53 locus using our RNA-seq annotation and variant call data.

**ASSISTANT:** cloud_workflow: Executing this Bioconductor visualization workflow requires running containerized R genomic packages and processing transcript annotation files on cloud infrastructure.

---

## [404] source=multitask_sft_big

**USER:** Generate fishplots and clonal architecture diagrams from longitudinal tumor variant frequency data to track clonal evolution across treatment timepoints.

**ASSISTANT:** instant_compute: Visualizing cancer clonal dynamics using the clevrvis R package is a lightweight data processing and plotting task that executes rapidly in an interactive compute environment without requiring distributed cloud infrastructure.

---

## [405] source=multitask_sft_big

**USER:** Align paired-end FASTQ sequencing reads using BWA and run bamcmp to separate graft and host reads from xenograft samples.

**ASSISTANT:** cloud_workflow: This is a Nextflow data-processing pipeline requiring scalable cloud orchestration for compute-intensive FASTQ alignment and BAM processing.

---

## [406] source=multitask_sft_big

**USER:** Generate spatial spot plots and UMAP dimensionality reduction plots from my Visium SpatialExperiment dataset to visualize spatial clustering and marker gene expression across tissue sections.

**ASSISTANT:** cloud_workflow: Executing spatial transcriptomics visualization pipelines on SpatialExperiment objects requires cloud-based bioinformatic workflow environments with appropriate R/Bioconductor dependencies.

---

## [407] source=multitask_sft_big

**USER:** I have a taxonomic abundance table and sample metadata from a gut microbiome study and want to calculate alpha and beta diversity metrics and generate PCoA ordination plots to compare community structures across patient cohorts.

**ASSISTANT:** cloud_workflow: This is a multi-step bioinformatics metagenomic workflow that requires cloud resources to parse abundance tables, compute dissimilarity matrices, and execute multivariate statistical ordinations.

---

## [408] source=multitask_sft_big

**USER:** Stream and filter a 10 GB multi-SDF compound library to screen for Lipinski-compliant drug-like leads and compute their chemical fingerprints.

**ASSISTANT:** cloud_workflow: Processing multi-gigabyte molecular structure files via chunked streaming requires an asynchronous batch pipeline that exceeds synchronous execution limits.

---

## [409] source=multitask_sft_big

**USER:** Cluster and compare protein and translated RNA-seq sequencing samples across conditions by generating k-mer sketches with nf-core/kmermaid.

**ASSISTANT:** cloud_workflow: It is an nf-core Nextflow pipeline designed to run multi-sample genomic sequence sketching and clustering across scalable distributed cloud infrastructure.

---

## [410] source=multitask_sft_big

**USER:** Preprocess and perform quality control on raw paired-end FASTQ files with unique molecular identifiers (UMIs) by extracting UMIs, trimming adapters, and generating FastQC reports.

**ASSISTANT:** cloud_workflow: This is a Nextflow-based high-throughput sequencing pipeline that requires distributed cloud or HPC compute infrastructure to process intensive read trimming, UMI extraction, and QC steps.

---

## [411] source=multitask_sft_big

**USER:** Preprocess raw 1D 1H-NMR metabolomics spectra from our clinical serum study using PepsNMR, performing phase correction, baseline correction, internal referencing, and bucketing to produce a normalized metabolite feature matrix.

**ASSISTANT:** cloud_workflow: PepsNMR is a multi-step bioinformatic pipeline that processes batches of raw spectral data files through sequential transformations, which requires asynchronous cloud pipeline execution.

---

## [412] source=multitask_sft_big

**USER:** Design an asymmetric IgG-like bispecific antibody targeting human CD3 and HER2 using a knobs-into-holes heterodimeric Fc scaffold with optimized scFv linkers to minimize light-chain mispairing.

**ASSISTANT:** cloud_design: Engineering bispecific antibodies requires computationally intensive 3D structural modeling, interface redesign, and conformational optimization across multi-chain assemblies typical of cloud-based molecular design pipelines.

---

## [413] source=multitask_sft_big

**USER:** Screen my candidate IgG1 antibody variable region sequences for developability liabilities, including aggregation propensity, thermal stability, and post-translational modification motifs.

**ASSISTANT:** cloud_workflow: Assessing antibody developability requires an asynchronous multi-step computational pipeline that couples structural homology modeling with spatial charge and aggregation surface calculations.

---

## [414] source=multitask_sft_big

**USER:** Construct a gene co-expression network and identify hub genes from my normalized RNA-seq count matrix across disease and control conditions using BioNERO.

**ASSISTANT:** cloud_workflow: Reconstructing large-scale biological co-expression networks, detecting modules, and computing hub statistics from transcriptomic data require multi-step cloud-based workflow execution.

---

## [415] source=multitask_sft_big

**USER:** Determine ABO blood group genotypes and predicted serological phenotypes from patient whole-genome sequencing FASTQ samples.

**ASSISTANT:** cloud_workflow: nf-core/abotyper is a Nextflow bioinformatics pipeline requiring distributed cloud compute to align sequencing reads and call ABO alleles.

---

## [416] source=multitask_sft_big

**USER:** Evaluate organelle marker resolution and spatial separation in our hyperLOPIT quantitative proteomics dataset using the pRoloc Bioconductor pipeline.

**ASSISTANT:** cloud_workflow: Assessing spatial proteomics fractionation profiles with pRoloc requires executing a multi-step R/Bioconductor bioinformatics data processing workflow in a cloud environment.

---

## [417] source=multitask_sft_big

**USER:** Align two multi-channel fluorescence microscopy z-stack volumes to correct for lateral drift and rotational shift between imaging rounds.

**ASSISTANT:** cloud_workflow: Processing and spatially registering multidimensional microscopy image stacks requires scalable cloud pipeline execution.

---

## [418] source=multitask_sft_big

**USER:** Benchmark and evaluate multiple differential expression methods like DESeq2, edgeR, and limma-voom on my RNA-seq count dataset using the benchdamic framework to assess precision, recall, and FDR control.

**ASSISTANT:** cloud_workflow: Benchmarking multiple statistical differential abundance pipelines across simulation or real count matrices requires long-running computational batch processing in the cloud.

---

## [419] source=multitask_sft_big

**USER:** Process a mouse brain MERFISH dataset to perform transcript assignment, cell segmentation, clustering, and identification of spatially variable genes across cortical layers.

**ASSISTANT:** cloud_workflow: MERFISH spatial transcriptomics processing involves high-memory image and transcript coordinate processing, spatial neighborhood graphing, and clustering that require orchestrated cloud pipeline compute.

---

## [420] source=multitask_sft_big

**USER:** Segment histological cross-sections of murine aortic tissue to quantify luminal diameter, wall thickness, and geometry across an aneurysm model cohort.

**ASSISTANT:** cloud_workflow: Automated aortic morphometry requires an end-to-end image processing and segmentation pipeline running on scalable cloud compute.

---

## [421] source=multitask_sft_big

**USER:** Annotate a set of lentiviral integration site coordinates against human genomic features, distance to nearest transcription start sites, and CpG islands using hiAnnotator.

**ASSISTANT:** cloud_workflow: Running hiAnnotator involves batch spatial overlap analysis of genomic coordinates against multiple large reference annotation tracks in a bioinformatics pipeline.

---

## [422] source=multitask_sft_big

**USER:** Quantify spatial cell-type colocalization and cell-cell interaction patterns from spot-level spatial transcriptomics data using join-count statistics.

**ASSISTANT:** cloud_workflow: Executing spatial autocorrelation and join-count analysis across large-scale spatial transcriptomics spot coordinate arrays requires substantial memory and multi-step data processing within a cloud workflow.

---

## [423] source=multitask_sft_big

**USER:** Remove host contamination from our metagenomic paired-end FASTQ files using reference genomes before downstream assembly.

**ASSISTANT:** cloud_workflow: This nf-core Nextflow pipeline requires distributed cloud infrastructure and workflow orchestration to align and filter large high-throughput FASTQ sequencing datasets against host reference genomes.

---

## [424] source=multitask_sft_big

**USER:** Run the nf-core/omicsgenetraitassociation pipeline on my normalized plasma proteomics expression matrix and patient clinical metadata to identify protein biomarkers significantly associated with cardiovascular disease status while adjusting for age and BMI.

**ASSISTANT:** cloud_workflow: Executing an nf-core pipeline for statistical multi-omics trait association testing requires distributed compute and cloud workflow orchestration.

---

## [425] source=multitask_sft_big

**USER:** Convert an igraph network of gene-disease associations into an interactive JavaScript D3 visualization using RGraph2js.

**ASSISTANT:** cloud_workflow: Generating interactive JavaScript web visualizations via RGraph2js requires executing R-based bioinformatics workflows within a cloud computing environment.

---

## [426] source=multitask_sft_big

**USER:** Identify transcription factor motif deviation scores across single-cell ATAC-seq peak count matrices to uncover differential motif variability between cell populations.

**ASSISTANT:** cloud_workflow: chromVAR involves computationally intensive GC-matched background peak sampling and genome-wide motif deviation calculations on large single-cell epigenomic matrices, requiring scalable cloud pipeline execution.

---

## [427] source=multitask_sft_big

**USER:** Run pathway enrichment analysis on my list of differentially expressed genes against the Reactome database using fedup to identify significantly enriched biological pathways.

**ASSISTANT:** instant_compute: Running Fisher's exact test pathway enrichment analysis with fedup is computationally lightweight and can be executed quickly within an interactive container environment.

---

## [428] source=multitask_sft_big

**USER:** Profile taxonomic composition and functional pathway stability across longitudinal metagenomic FASTQ samples from a clinical microbiome study.

**ASSISTANT:** cloud_workflow: Comprehensive metagenomic analysis involves multi-step, compute-heavy pipelines for read quality control, taxonomic classification, and assembly that require scalable cloud compute resources.

---

## [429] source=multitask_sft_big

**USER:** Estimate 5-methylcytosine (5mC) and 5-hydroxymethylcytosine (5hmC) levels across CpG sites from paired bisulfite and oxidative bisulfite Illumina EPIC array data using the ENmix MLE algorithm.

**ASSISTANT:** cloud_workflow: Processing high-density microarray methylation matrices with maximum likelihood estimation requires substantial memory and computational time, making it best suited for a cloud bioinformatics workflow.

---

## [430] source=multitask_sft_big

**USER:** Find and format the full scientific citations and PubMed IDs for landmark publications on lipid nanoparticle mRNA delivery systems.

**ASSISTANT:** instant_cited: Retrieving and formatting literature references relies on rapid database lookup and citation generation rather than heavy background computation or structural modeling.

---

## [431] source=multitask_sft_big

**USER:** Identify aberrant splicing events and RNA splicing outliers across patient RNA-seq BAM files to detect potential pathogenic variants.

**ASSISTANT:** cloud_workflow: Detecting aberrant splicing with SASER requires heavy computational resources for RNA-seq junction extraction, statistical modeling, and multi-sample cohort-level pipeline execution.

---

## [432] source=multitask_sft_big

**USER:** Simulate longitudinal 16S rRNA count data with spiked-in differentially abundant taxa across two treatment cohorts to benchmark statistical testing performance.

**ASSISTANT:** cloud_workflow: Generating synthetic longitudinal microbiome count matrices across multiple biological replicates and parameter sweeps requires scalable cloud pipeline execution.

---

## [433] source=multitask_sft_big

**USER:** Query exon-exon junction counts and coverage for the TP53 gene across GTEx samples using the snapcount R/Bioconductor package.

**ASSISTANT:** instant_compute: Snapcount queries pre-compiled Snaptron web APIs and returns a RangedSummarizedExperiment object within seconds, making it suitable for immediate execution without dedicated cloud cluster provisioning.

---

## [434] source=multitask_sft_big

**USER:** Annotate and query a multi-sample VCF from a rare pediatric trio cohort using GEMINI to identify candidate de novo and compound heterozygous pathogenic variants.

**ASSISTANT:** cloud_workflow: Building a GEMINI database and executing inheritance pattern extraction across cohort-scale genomic VCFs requires multi-step batch pipeline orchestration on cloud compute infrastructure.

---

## [435] source=multitask_sft_big

**USER:** Visualize genome-wide copy number variations and gene density across human chromosomes in a trellis layout using my BED-formatted genomic segment data.

**ASSISTANT:** instant_compute: Rendering genomic trellis plots with the gtrellis R package is a deterministic, fast data visualization task that executes in an interactive compute sandbox without distributed cloud pipelines.

---

## [436] source=multitask_sft_big

**USER:** Process multi-channel fluorescence microscopy images from a 384-well Cell Painting assay to perform illumination correction, cell segmentation, and morphological feature extraction.

**ASSISTANT:** cloud_workflow: This task runs an nf-core Nextflow pipeline to process large high-content imaging datasets using distributed compute resources in the cloud.

---

## [437] source=multitask_sft_big

**USER:** Analyze Tomo-seq cryosectioned RNA sequencing data to align slice-specific read counts, normalize transcript profiles, and reconstruct spatial gene expression patterns across developmental tissue sections.

**ASSISTANT:** cloud_workflow: Executing end-to-end spatial transcriptomics processing and reconstruction pipelines requires scalable multi-step orchestration on high-performance cloud workflow infrastructure.

---

## [438] source=multitask_sft_big

**USER:** Construct a custom Bioconductor BSgenome data package from chromosome FASTA files for a newly assembled fungal genome.

**ASSISTANT:** cloud_workflow: Forging a genome-wide BSgenome data package entails multi-step sequence indexing, format conversion, and package bundling that require dedicated batch compute resources.

---

## [439] source=multitask_sft_big

**USER:** Detect de novo primary transcription units and identify active promoter regions from paired-end GRO-seq BAM alignment files using groHMM.

**ASSISTANT:** cloud_workflow: groHMM performs genome-scale Hidden Markov Model evaluations on large nascent RNA sequencing datasets, requiring cloud workflow infrastructure for data-intensive processing.

---

## [440] source=multitask_sft_big

**USER:** Screen and remove foreign contamination, adaptors, and vector sequences from my newly assembled plant genome FASTA using NCBI FCS before submitting to GenBank.

**ASSISTANT:** cloud_workflow: nf-core/fasta_clean_fcs is a full Nextflow pipeline requiring cloud or HPC infrastructure to run memory- and compute-intensive NCBI Foreign Contamination Screen tools against large reference databases.

---

## [441] source=multitask_sft_big

**USER:** Integrate 10x Genomics single-cell RNA-seq expression data with paired scTCR-seq profiling across tumor and peripheral blood samples to quantify clonal expansion, clonotype sharing, and repertoire diversity across T cell clusters.

**ASSISTANT:** cloud_workflow: Integrating and analyzing multi-sample single-cell immune repertoire datasets alongside transcriptomic data requires a multi-step R/Bioconductor bioinformatics pipeline running on scalable cloud compute infrastructure.

---

## [442] source=multitask_sft_big

**USER:** Correct dye-specific intensity bias across a set of two-color Agilent microarray samples to produce normalized expression values for differential expression analysis.

**ASSISTANT:** cloud_workflow: Processing and normalizing multi-sample two-color microarray datasets through dye-bias correction algorithms requires a multi-step bioinformatics pipeline executed on cloud infrastructure.

---

## [443] source=multitask_sft_big

**USER:** Evaluate the functional impact of candidate intronic SNPs on pre-mRNA splicing branchpoint architecture using branchpointer.

**ASSISTANT:** cloud_workflow: Predicting splicing branchpoints and assessing variant impacts across genomic coordinates requires orchestrating multi-step genomic data processing and annotation pipelines best suited for a cloud workflow.

---

## [444] source=multitask_sft_big

**USER:** Perform Gene Ontology (GO) and KEGG pathway enrichment analysis on a list of differentially expressed human genes to identify significantly dysregulated biological processes.

**ASSISTANT:** cloud_workflow: clusterProfiler requires running an R/Bioconductor analysis pipeline with organism annotation databases to compute enrichment statistics and generate visualization plots on cloud infrastructure.

---

## [445] source=multitask_sft_big

**USER:** Run functional enrichment and pathway topology analysis on my tandem mass tag (TMT) proteomics dataset to identify dysregulated signaling networks.

**ASSISTANT:** cloud_workflow: Executing the funOmics pipeline involves multi-step data processing, statistical enrichment, and pathway mapping across large proteomics datasets, requiring asynchronous cloud infrastructure.

---

## [446] source=multitask_sft_big

**USER:** Calculate decay-corrected percent injected dose per gram (%ID/g), organ residence times, and tumor-to-normal tissue ratios from tabular gamma counter counts and tissue weights collected at 24h, 72h, and 168h post-injection of a 89Zr-labeled monoclonal antibody.

**ASSISTANT:** instant_compute: The analysis relies on deterministic mathematical radioisotope decay corrections, mass normalizations, and trapezoidal pharmacokinetic integration on structured tabular data that execute rapidly in-memory.

---

## [447] source=multitask_sft_big

**USER:** Import RSEM gene and transcript quantification files across my RNA-seq samples to create gene-level count matrices ready for DESeq2 analysis.

**ASSISTANT:** instant_compute: Aggregating pre-computed RSEM tabular summaries with tximport is a lightweight R task that executes in seconds on standard CPU resources.

---

## [448] source=multitask_sft_big

**USER:** Cluster and visualize high-dimensional immune cell subsets from my multi-sample CyTOF FCS files using FlowSOM self-organizing maps and metaclustering.

**ASSISTANT:** cloud_workflow: Running FlowSOM on multi-sample cytometry datasets requires multi-step preprocessing, grid training, and metaclustering pipelines executed on cloud compute infrastructure.

---

## [449] source=multitask_sft_big

**USER:** Compare two ranked lists of differentially expressed genes from distinct RNA-seq studies using the OrderedList algorithm to evaluate concordance and extract statistically significant overlapping signatures.

**ASSISTANT:** instant_compute: Evaluating rank concordance across gene lists requires lightweight statistical analysis and permutation testing on tabular data that executes rapidly in a local environment without distributed cloud infrastructure.

---

## [450] source=multitask_sft_big

**USER:** Identify putative gene functions and taxonomic origins for a set of novel assembled contigs by querying the NCBI nucleotide (nt) database via remote BLAST.

**ASSISTANT:** cloud_workflow: Executing batch BLAST sequence alignments against massive external reference databases involves asynchronous querying, data transfers, and prolonged execution best managed by a cloud workflow.

---

## [451] source=multitask_sft_big

**USER:** Launch an interactive iSEE dashboard to explore cell clusters, UMAP projections, and marker gene expression from my processed SingleCellExperiment dataset.

**ASSISTANT:** cloud_workflow: Deploying an interactive iSEE Shiny application on large single-cell datasets requires dedicated cloud memory and containerized runtime infrastructure.

---

## [452] source=multitask_sft_big

**USER:** Analyze paired-end RNA-seq FASTQ files from 12 human tumor and normal samples to perform adapter trimming, STAR alignment against GRCh38, Salmon quantification, and aggregate QC reporting.

**ASSISTANT:** cloud_workflow: nf-core/rnaseq is a multi-step Nextflow pipeline that requires cloud-scale distributed computing to handle heavy I/O and compute tasks like alignment and transcript quantification.

---

## [453] source=multitask_sft_big

**USER:** Perform gene set enrichment analysis (GSEA) on my ranked list of differentially expressed genes from RNA-seq to identify significantly enriched KEGG pathways and Gene Ontology terms using clusterProfiler.

**ASSISTANT:** cloud_workflow: Running clusterProfiler GSEA involves executing an R/Bioconductor bioinformatics data pipeline against annotation databases, which is characteristic of a cloud workflow.

---

## [454] source=multitask_sft_big

**USER:** Identify differentially expressed genes with biologically meaningful effect sizes from an RNA-seq count matrix by testing against a minimum log2 fold-change threshold of 1.2 using edgeR glmTreat.

**ASSISTANT:** cloud_workflow: This task involves running an automated R/Bioconductor statistical pipeline on sequencing count datasets and metadata files within a cloud execution container.

---

## [455] source=multitask_sft_big

**USER:** Perform mixture model analysis on metabolomics profiling data with non-random missingness to identify metabolite associations with patient disease status.

**ASSISTANT:** cloud_workflow: Fitting mixture models across hundreds of left-censored metabolomics features requires multi-step, compute-intensive execution handled in a cloud environment.

---

## [456] source=multitask_sft_big

**USER:** Generate a secure shareable link and update access permissions for the workspace object 'processed_scrnaseq_matrix' to share with a collaborating lab.

**ASSISTANT:** instant_compute: Managing and generating shared object references or permissions is a lightweight metadata operation handled immediately via platform API calls without requiring high-performance cloud batch execution.

---

## [457] source=multitask_sft_big

**USER:** Cluster millions of metagenomic viral contigs from a multi-sample FASTA file using Vclust prefiltering and pairwise alignment to generate sequence-similarity clusters.

**ASSISTANT:** cloud_workflow: This is an nf-core Nextflow workflow executing multi-step prefiltering, alignment, and clustering algorithms on large sequence datasets requiring distributed cloud compute resources.

---

## [458] source=multitask_sft_big

**USER:** Run the nf-core/dia_proteomics_analysis pipeline on a cohort of 30 DIA mass spectrometry plasma samples to perform protein identification and label-free quantification against the human reference proteome.

**ASSISTANT:** cloud_workflow: Executing an nf-core Nextflow pipeline on large-scale mass spectrometry data requires orchestrated distributed computing resources in a cloud workflow environment.

---

## [459] source=multitask_sft_big

**USER:** Calculate ATP concentrations and percentage cell viability from a 96-well plate reader luminescence (RLU) dataset for drug-treated patient biopsy samples.

**ASSISTANT:** instant_compute: This task entails deterministic tabular processing and standard curve interpolation on plate reader data, which can be executed immediately without distributed cloud infrastructure.

---

## [460] source=multitask_sft_big

**USER:** Evaluate the robustness of our graph neural network transcriptomic cancer classifier by identifying the minimal expression perturbations required to flip diagnostic predictions using an adversarial random walk attack.

**ASSISTANT:** cloud_models: Adversarial perturbation attacks against transcriptomic machine learning models require intensive iterative model inference and gradient-guided optimization hosted on cloud model infrastructure.

---

## [461] source=multitask_sft_big

**USER:** Generate publication-ready multi-track genome browser plots showing ChIP-seq signal BigWig files, peak call BED regions, and gene annotations across the TP53 locus.

**ASSISTANT:** cloud_workflow: Visualizing multi-omic track files such as BigWigs and BED annotations across genomic loci requires cloud-based bioinformatics processing pipelines and plotting dependencies.

---

## [462] source=multitask_sft_big

**USER:** Estimate the channel spillover matrix and deconvolve isotopic crosstalk across my multi-marker CyTOF proteomics FCS files using single-stained bead controls.

**ASSISTANT:** cloud_workflow: Correcting cross-channel signal spillover across multi-sample proteomics/cytometry dataset files requires batch data processing and matrix compensation via an asynchronous cloud pipeline.

---

## [463] source=multitask_sft_big

**USER:** Retrieve the RNA and protein expression profile of human CLDN18 across healthy tissues and gastric carcinoma samples to evaluate target specificity and potential on-target off-tumor risks.

**ASSISTANT:** instant_cited: This task performs a fast database lookup against reference expression atlases (like GTEx or HPA) returning structured, source-cited tissue expression data without heavy computational orchestration.

---

## [464] source=multitask_sft_big

**USER:** Perform soft fuzzy c-means clustering on time-series TMT proteomics abundance data across six time points to identify distinct temporal expression patterns and hub proteins.

**ASSISTANT:** cloud_workflow: Running the Mfuzz workflow involves multi-step data standardization, parameter optimization (m value), and fuzzy clustering that execute asynchronously as a containerized bioinformatics pipeline.

---

## [465] source=multitask_sft_big

**USER:** Cluster MS/MS spectra and generate spectral similarity networks from my external LC-MS/MS peaklist using CluMSID.

**ASSISTANT:** cloud_workflow: Executing the CluMSID metabolomics pipeline on external peaklists requires multi-step spectral processing and network generation on cloud infrastructure.

---

## [466] source=multitask_sft_big

**USER:** Randomize 192 patient samples across two 96-well plates using Omixer to balance covariates such as age, biological sex, and batch effects prior to automated liquid handling.

**ASSISTANT:** instant_compute: Omixer performs multivariate sample randomization and plate layout optimization via rapid algorithmic computation that executes in seconds without requiring heavy distributed cloud infrastructure.

---

## [467] source=multitask_sft_big

**USER:** Generate hex-binned dimension reduction plots for a large single-cell RNA-seq dataset to mitigate overplotting and summarize gene expression density using iSEEhex.

**ASSISTANT:** cloud_workflow: Processing large-scale single-cell matrices and computing hexagonal binning aggregations requires dedicated cloud computing memory and workflow orchestration.

---

## [468] source=multitask_sft_big

**USER:** Run the SCArray pipeline on raw single-cell HDF5 count matrices to perform memory-efficient quality control filtering, normalization, and scalable principal component analysis across 500,000 cells.

**ASSISTANT:** cloud_workflow: This is a heavy, multi-step single-cell analysis pipeline that requires cloud infrastructure for distributed and out-of-core genomic array computations.

---

## [469] source=multitask_sft_big

**USER:** Calculate Z'-factor and control CVs across raw 384-well plate luminescence data, normalize percent inhibition, and call hit compounds exceeding 3 standard deviations from the negative control mean.

**ASSISTANT:** instant_compute: Microplate quality control and statistical hit calling rely on deterministic tabular data analysis and standard formulas that execute rapidly within an interactive computational runtime.

---

## [470] source=multitask_sft_big

**USER:** Compress and extract essential functional annotations from a batch of retrieved UniProt entries to minimize prompt token count for downstream analysis.

**ASSISTANT:** instant_compute: Pruning and condensing structured database records is a lightweight, deterministic parsing task that runs immediately without cloud orchestration.

---

## [471] source=multitask_sft_big

**USER:** Filter RNA-seq differential expression results to identify significantly dysregulated transcripts using a threshold of adjusted p-value < 0.05 and |log2FC| >= 1.5 between control and treated samples.

**ASSISTANT:** cloud_workflow: Filtering and processing large-scale transcriptomic differential abundance datasets requires multi-step automated bioinformatics pipelines executed on cloud infrastructure.

---

## [472] source=multitask_sft_big

**USER:** Convert a protein-protein interaction network stored as an R graphNEL object into Cytoscape using RCy3 while preserving node annotations and edge weights.

**ASSISTANT:** instant_compute: The task performs lightweight R script execution to transform and map graph data structures in seconds without requiring distributed cloud infrastructure.

---

## [473] source=multitask_sft_big

**USER:** Run gene set enrichment analysis on my RNA-seq differential expression results against MSigDB Hallmark gene sets to identify dysregulated biological pathways.

**ASSISTANT:** cloud_workflow: Gene set enrichment analysis involves multi-step data processing, curated database querying, and statistical permutation testing that runs as a bioinformatics pipeline in the cloud.

---

## [474] source=multitask_sft_big

**USER:** Automatically determine the optimal number of principal components to retain by modeling technical noise on my single-cell RNA-seq expression matrix using scran.

**ASSISTANT:** cloud_workflow: Modeling variance components and running denoising PCA across thousands of single cells requires dedicated compute resources executed as a cloud pipeline.

---

## [475] source=multitask_sft_big

**USER:** Subsample my paired-end RNA-seq FASTQ files to 5 million reads and quantify transcript expression levels using Salmon against the GRCh38 reference transcriptome.

**ASSISTANT:** cloud_workflow: This task executes an end-to-end Nextflow transcriptomics pipeline requiring high-throughput compute infrastructure for FASTQ subsampling and Salmon pseudo-alignment.

---

## [476] source=multitask_sft_big

**USER:** Remove unwanted batch variation from an RNA-seq expression dataset using negative control genes with RUVcorr to obtain an accurate gene-gene co-expression correlation matrix.

**ASSISTANT:** cloud_workflow: Applying RUVcorr across full-scale transcriptomic expression matrices involves computationally intensive singular value decompositions and parameter evaluations suited for cloud workflow execution.

---

## [477] source=multitask_sft_big

**USER:** Assess the statistical power and determine the minimum sample size required for my planned differential gene expression experiment using pilot RNA-seq count data via ERSSA.

**ASSISTANT:** cloud_workflow: ERSSA performs computationally intensive, iterative subsampling and repeated differential expression tests across multiple sample size cohorts, requiring distributed cloud pipeline execution.

---

## [478] source=multitask_sft_big

**USER:** Perform multi-factor differential expression analysis on an RNA-seq count matrix to identify genes responsive to treatment while controlling for donor and batch covariates.

**ASSISTANT:** cloud_workflow: Running multi-factor RNA-seq differential expression across multiple samples requires orchestrating a batch statistical transcriptomics pipeline on cloud infrastructure.

---

## [479] source=multitask_sft_big

**USER:** Identify spatially variable genes (SVGs) across tissue spots from a 10x Genomics Visium spatial transcriptomics dataset using nearest-neighbor Gaussian processes.

**ASSISTANT:** cloud_workflow: nnSVG requires fitting statistical spatial process models across thousands of spots and genes on high-dimensional transcriptomics data, which necessitates dedicated cloud workflow execution.

---

## [480] source=multitask_sft_big

**USER:** Infer a genome-wide competing endogenous RNA (ceRNA) interaction network from matched miRNA and mRNA expression profiles across TCGA breast cancer samples using sparse partial correlation analysis.

**ASSISTANT:** cloud_workflow: SPONGE ceRNA network inference involves heavy matrix computations and extensive empirical null distribution sampling across high-dimensional transcriptomic datasets, requiring distributed cloud pipeline execution.

---

## [481] source=multitask_sft_big

**USER:** Run differential expression analysis on an RNA-seq count matrix across disease and control cohorts using edgeR to identify significantly altered genes.

**ASSISTANT:** cloud_workflow: Executing an edgeR transcriptomics pipeline requires multi-sample statistical modeling, dispersion estimation, and standardized workflow execution in a cloud compute environment.

---

## [482] source=multitask_sft_big

**USER:** Analyze raw mass spectrometry proteomics datasets using the MOMA pipeline to quantify post-translational modifications and map differentially expressed protein modules across disease cohorts.

**ASSISTANT:** cloud_workflow: Running the MOMA proteomics pipeline requires orchestrating heavy, asynchronous batch processing and database searching on cloud infrastructure.

---

## [483] source=multitask_sft_big

**USER:** Run Bayesian factor analysis using scBFA on my raw single-cell RNA-seq count matrix to identify latent factors while modeling technical dropout for downstream clustering.

**ASSISTANT:** cloud_workflow: Fitting Bayesian factor analysis models across thousands of cells and genes is computationally intensive and requires cloud workflow orchestration.

---

## [484] source=multitask_sft_big

**USER:** Perform Gene Set Variation Analysis (GSVA) on a normalized bulk RNA-seq expression matrix using MSigDB Hallmark gene sets to quantify sample-level pathway enrichment scores.

**ASSISTANT:** cloud_workflow: GSVA is a standard bioinformatics batch pipeline requiring cloud execution to process expression matrices against reference gene sets.

---

## [485] source=multitask_sft_big

**USER:** Tidy differential expression results from an RNA-seq DESeqDataSet object into a tidy tibble using biobroom for plotting with ggplot2.

**ASSISTANT:** instant_compute: Converting Bioconductor data structures into tidy tabular formats is a lightweight R computation that runs in seconds without requiring distributed cloud infrastructure.

---

## [486] source=multitask_sft_big

**USER:** Classify patient serum metabolomic profiles into three distinct clinical stages and extract top discriminatory features using generalized partial least squares.

**ASSISTANT:** cloud_workflow: Multi-class GPLS on high-dimensional omics datasets requires an orchestrated computational data analysis pipeline with cross-validation and feature importance ranking.

---

## [487] source=multitask_sft_big

**USER:** Optimize hyperparameters and architecture for a convolutional neural network trained on genomic regulatory sequences using the nf-core/deepmodeloptim pipeline.

**ASSISTANT:** cloud_workflow: This task runs an nf-core Nextflow workflow requiring orchestrated distributed compute and GPU resources to evaluate and train deep learning models.

---

## [488] source=multitask_sft_big

**USER:** Estimate cell-type proportions from our NanoString GeoMx spatial transcriptomics expression matrix using a single-cell RNA-seq reference profile via SpatialDecon.

**ASSISTANT:** cloud_workflow: SpatialDecon is a multi-step transcriptomic deconvolution pipeline requiring reference profile alignment, matrix normalization, and computationally intensive deconvolution algorithms executed via cloud workflows.

---

## [489] source=multitask_sft_big

**USER:** Infer upstream causal signaling networks driving altered transcription factor activities from my RNA-seq differential expression results using CARNIVAL.

**ASSISTANT:** cloud_workflow: CARNIVAL executes an intensive multi-step omics pipeline integrating prior knowledge networks with integer linear programming solvers, requiring scalable cloud workflow infrastructure.

---

## [490] source=multitask_sft_big

**USER:** Assess the strand-specificity of my paired-end RNA-seq BAM alignments to confirm library strandedness before running transcript quantification.

**ASSISTANT:** cloud_workflow: Evaluating strand-specificity requires parsing large alignment BAM files and calculating read-strand proportions across genomic features using distributed cloud processing.

---

## [491] source=multitask_sft_big

**USER:** Process raw paired-end DamID-seq FASTQ files to map genomic binding profiles, call enriched peaks, and identify chromatin interaction sites across experimental conditions.

**ASSISTANT:** cloud_workflow: Processing high-throughput epigenomic sequencing data through alignment, quality filtering, and peak-calling requires scalable distributed compute and long-running pipeline orchestration.

---

## [492] source=multitask_sft_big

**USER:** Construct an interactive protein-protein interaction network from an edge list using RCyjs, mapping differential gene expression values to node color and degree centrality to node size.

**ASSISTANT:** instant_compute: Generating and styling Cytoscape.js network visualizations in R is a lightweight data transformation and rendering task that executes in seconds without distributed cloud infrastructure.

---

## [493] source=multitask_sft_big

**USER:** Generate a circular genomic visualization of Escherichia coli K-12 highlighting specific operon loci and GC content using ecolitk.

**ASSISTANT:** instant_compute: Executing ecolitk routines to map coordinates and render bacterial genome visualizations is a fast, lightweight R computation that runs in seconds without distributed cloud infrastructure.

---

## [494] source=multitask_sft_big

**USER:** Perform co-expression module identification, hub gene analysis, and functional enrichment on my normalized RNA-seq expression dataset using CEMiTool.

**ASSISTANT:** cloud_workflow: CEMiTool executes a multi-step transcriptomic co-expression network and pathway enrichment pipeline requiring containerized cloud workflow execution.

---

## [495] source=multitask_sft_big

**USER:** I have an AnnData h5ad file of single-cell RNA-seq data from human lung tissue and want to annotate cell types across my clusters using Panhumanpy.

**ASSISTANT:** cloud_workflow: Running automated reference-based cell-type annotation on large single-cell transcriptomic datasets requires an asynchronous, containerized bioinformatics processing pipeline.

---

## [496] source=multitask_sft_big

**USER:** Process a cohort of raw Illumina Infinium MethylationEPIC IDAT files to perform background subtraction, dye-bias normalization, probe masking, and beta-value extraction.

**ASSISTANT:** cloud_workflow: Processing raw DNA methylation microarray IDAT files through quality control, normalization, and signal extraction across multiple samples requires a multi-step bioinformatic pipeline run on cloud infrastructure.

---

## [497] source=multitask_sft_big

**USER:** Filter and correct genotyping errors in a raw GBS VCF file from an F2 biparental population using GBScleanR to generate a high-quality marker set for genetic mapping.

**ASSISTANT:** cloud_workflow: Processing and cleaning multi-sample GBS variant call matrices with hidden Markov models is a batch genomic pipeline that requires cloud workflow infrastructure.

---

## [498] source=multitask_sft_big

**USER:** Simulate synthetic spatial transcriptomics count matrices with spatially variable gene expression patterns and controlled noise levels to benchmark spatial clustering algorithms.

**ASSISTANT:** cloud_workflow: Simulating high-dimensional spatial transcriptomics data using Gaussian processes involves computationally intensive parameter sampling and matrix operations suited for cloud workflow execution.

---

## [499] source=multitask_sft_big

**USER:** I have paired-end whole-genome bisulfite sequencing FASTQ files that I need aligned to the GRCh38 reference genome using bwameth and deduplicated to prepare analysis-ready BAM files for methylation calling.

**ASSISTANT:** cloud_workflow: Aligning high-throughput bisulfite sequencing reads against an indexed genome and marking duplicates is a multi-step, compute-intensive data processing pipeline that requires cloud or cluster execution.

---

## [500] source=multitask_sft_big

**USER:** Fit fractional drug release data from a crosslinked hydrogel to the Korsmeyer-Peppas equation to calculate the release exponent n and identify the underlying diffusion mechanism.

**ASSISTANT:** instant_compute: Fitting time-series dissolution data to the empirical power-law equation requires standard regression analytics that execute instantaneously in a lightweight compute environment.

---

## [501] source=multitask_sft_big

**USER:** Perform customized quality control, background correction, and dye-bias normalization on Illumina MethylationEPIC array IDAT files using the ENmix pipeline to generate clean methylation beta values.

**ASSISTANT:** cloud_workflow: Preprocessing large cohorts of high-density DNA methylation array data with ENmix requires multi-step array processing, heavy I/O, and substantial memory best executed as an asynchronous cloud workflow.

---

## [502] source=multitask_sft_big

**USER:** Impute and quantify the expression of hundreds of unmeasured surface proteins across single cells from our high-throughput FCS flow cytometry panel.

**ASSISTANT:** cloud_workflow: Infinity Flow is an asynchronous, computationally intensive pipeline that trains regression models across single-cell cytometry files and requires scalable cloud workflow infrastructure.

---

## [503] source=multitask_sft_big

**USER:** Identify spatial tissue domains and cluster spatial transcriptomics gene expression data from a 10x Visium dataset using the MEB empirical Bayes algorithm.

**ASSISTANT:** cloud_workflow: Iterative empirical Bayes spatial clustering on multi-spot transcriptomics matrices requires compute-intensive background execution via a cloud workflow.

---

## [504] source=multitask_sft_big

**USER:** Identify differentially variable CpG probes between tumor and matched normal tissue samples from Illumina EPIC methylation array data using missmethyl.

**ASSISTANT:** cloud_workflow: Testing differential variability across hundreds of thousands of CpG sites on methylation arrays requires a multi-step R/Bioconductor workflow running on cloud-scale compute.

---

## [505] source=multitask_sft_big

**USER:** Infer a gene regulatory network from normalized RNA-seq expression data to identify master transcription factors and modular subnetworks associated with disease progression.

**ASSISTANT:** cloud_workflow: Gene regulatory network inference using bioNERO requires multi-step preprocessing, computationally heavy algorithm execution (such as GENIE3 or correlation matrices), and downstream topological analysis suited for an asynchronous cloud workflow.

---

## [506] source=multitask_sft_big

**USER:** Build a pangenome variation graph from ten phased bacterial genome FASTA assemblies using the nf-core/pangenome pipeline to analyze core and accessory structural variants.

**ASSISTANT:** cloud_workflow: nf-core/pangenome is a multi-step Nextflow genomics pipeline requiring cloud or HPC infrastructure for resource-intensive graph construction, alignment, and visualization.

---

## [507] source=multitask_sft_big

**USER:** Generate interactive dimensional reduction plots (PCA and t-SNE) from my normalized microarray ExpressionSet to inspect sample clustering and potential batch effects.

**ASSISTANT:** cloud_workflow: Processing and generating interactive multidimensional visualizations from transcriptomics expression sets requires executing a containerized bioinformatics workflow in the cloud.

---

## [508] source=multitask_sft_big

**USER:** Assemble and functionally annotate raw paired-end Illumina sequencing reads for a newly isolated bacterial strain using the bioga pipeline.

**ASSISTANT:** cloud_workflow: Genome assembly and annotation involve multi-step, computationally intensive bioinformatics tools that require asynchronous, long-running execution on cloud infrastructure.

---

## [509] source=multitask_sft_big

**USER:** Perform differential binding and co-localization analysis across multiple histone modification and transcription factor ChIP-seq peak sets to identify cell-type-specific regulatory elements using extraChIPs.

**ASSISTANT:** cloud_workflow: Processing and integrating multi-sample genomic alignments and peak call files requires scalable cloud workflow infrastructure for data-intensive bioinformatics pipelines.

---

## [510] source=multitask_sft_big

**USER:** Perform sparse PLS regression on my plasma proteomics abundance matrix to identify key protein biomarkers predictive of clinical disease severity scores with tuned cross-validation.

**ASSISTANT:** cloud_workflow: Fitting a sparse PLS regression model with cross-validation and feature selection on high-dimensional proteomics datasets requires executing a multi-step biostatistical pipeline in a cloud environment.

---

## [511] source=multitask_sft_big

**USER:** Benchmark AlphaMissense pathogenicity scores against clinical missense classifications from ClinVar for BRCA1 to calculate ROC-AUC and optimal classification thresholds.

**ASSISTANT:** cloud_workflow: Benchmarking variant effect predictors across ClinVar catalogs requires multi-step genomic data ingestion, variant matching, and statistical evaluation pipeline execution in the cloud.

---

## [512] source=multitask_sft_big

**USER:** Infer continuous cell-state differentiation trajectories across time-series single-cell RNA-seq datasets using flow matching trajectory modeling.

**ASSISTANT:** cloud_workflow: Orchestrating flow matching across large multi-condition single-cell datasets requires distributed GPU resources and multi-step pipeline execution.

---

## [513] source=multitask_sft_big

**USER:** Run PCA and OPLS-DA on an untargeted metabolomics feature matrix formatted as a SummarizedExperiment to identify discriminatory metabolites between disease and healthy control groups.

**ASSISTANT:** cloud_workflow: Executing the ropls pipeline requires multi-step multivariate statistical modeling, cross-validation, and diagnostic generation running in an orchestrated containerized bioinformatics workflow.

---

## [514] source=multitask_sft_big

**USER:** Assess whether gut microbiome compositional shifts in colorectal cancer patients reflect dysbiosis by running eudysbiome on genus-level differential abundance profiles compared to healthy controls.

**ASSISTANT:** cloud_workflow: eudysbiome is a multi-step metagenomic analysis workflow that statistically evaluates and annotates differential taxa abundance against a curated database of eubiotic and dysbiotic associations.

---

## [515] source=multitask_sft_big

**USER:** Perform hierarchical gene set enrichment and generalized covariate-adjusted pathway testing using GlobalAncova on normalized transcriptomic expression data.

**ASSISTANT:** cloud_workflow: Executing GlobalAncova hierarchical hypothesis testing on transcriptomic datasets requires a multi-step R/Bioconductor statistical pipeline executed in a cloud environment.

---

## [516] source=multitask_sft_big

**USER:** Calculate the exact motif hit counts and sequence-level p-values for a STAT3 position frequency matrix across human promoter sequences using a higher-order Markov background model.

**ASSISTANT:** cloud_workflow: Running motifcounter requires executing a multi-step genomic sequence analysis pipeline with custom FASTA/PWM inputs and compute-intensive statistical modeling on cloud infrastructure.

---

## [517] source=multitask_sft_big

**USER:** Perform quality control on targeted sequencing BAM files using probe capture regions to assess on-target specificity, enrichment fold, and coverage uniformity.

**ASSISTANT:** cloud_workflow: Processing large BAM alignment files to compute targeted capture metrics and generate comprehensive quality control reports requires intensive batch computation on the cloud.

---

## [518] source=multitask_sft_big

**USER:** Screen a candidate panel of 15 siRNA designs targeting human PCSK9 for transcriptomic off-target silencing and seed-region complementation against the Ensembl human reference transcriptome.

**ASSISTANT:** cloud_workflow: Evaluating siRNA off-target liability involves running sequence alignment and thermodynamic binding algorithms across the full transcriptome, requiring an asynchronous multi-step bioinformatics cloud pipeline.

---

## [519] source=multitask_sft_big

**USER:** Simulate the human pharmacokinetic clearance and terminal half-life of an engineered IgG1 antibody using its pH 6.0 and pH 7.4 FcRn binding kinetics.

**ASSISTANT:** cloud_workflow: Predicting in vivo antibody clearance via mechanistic FcRn-mediated recycling requires running a multi-compartment PBPK simulation pipeline in the cloud.

---

## [520] source=multitask_sft_big

**USER:** Generate a hierarchically clustered heatmap with both sample and gene annotations from my normalized RNA-seq count matrix and clinical metadata.

**ASSISTANT:** cloud_workflow: Generating a double-annotated heatmap via Heatplus requires containerized bioinformatics workflow execution to process high-dimensional expression matrices and map complex clinical annotations.

---

## [521] source=multitask_sft_big

**USER:** Stream and extract targeted gene expression matrices from a large-scale single-cell RNA-seq dataset stored in Zarr format using Rarr for downstream differential expression analysis.

**ASSISTANT:** cloud_workflow: Processing and subsetting large multi-gigabyte Zarr arrays of transcriptomics data requires managed cloud infrastructure and memory-efficient workflow execution.

---

## [522] source=multitask_sft_big

**USER:** Normalize an RNA-seq gene expression matrix across heterogeneous tissue types using smooth quantile normalization with qsmooth while preserving group-specific biological differences.

**ASSISTANT:** cloud_workflow: Executing transcriptomics normalization on multi-sample expression datasets with biological metadata requires pipeline orchestration and compute resources appropriate for a cloud workflow.

---

## [523] source=multitask_sft_big

**USER:** Analyze and visualize cell-cell communication networks and ligand-receptor interactions from a single-cell RNA-sequencing dataset using InterCellar.

**ASSISTANT:** cloud_workflow: InterCellar is an R/Bioconductor pipeline that processes high-dimensional single-cell transcriptomic data to infer intercellular signaling, requiring a containerized cloud workflow environment.

---

## [524] source=multitask_sft_big

**USER:** Perform Kaplan-Meier survival analysis and fit a Cox proportional hazards regression model on patient clinical metadata to evaluate overall survival stratified by TP53 mutation status.

**ASSISTANT:** instant_compute: Kaplan-Meier estimation and Cox regression on clinical cohort tables are lightweight statistical computing tasks that execute quickly in a standard Python or R environment.

---

## [525] source=multitask_sft_big

**USER:** Detect genes exhibiting subtle transcriptional distribution changes across cell states in a scRNA-seq count matrix using scshapes distribution fitting.

**ASSISTANT:** cloud_workflow: Fitting parametric distribution models across high-dimensional single-cell transcriptomic matrices requires multi-step, resource-intensive batch computation best executed via a cloud workflow.

---

## [526] source=multitask_sft_big

**USER:** Annotate a ChIP-seq peak BED file against the hg38 genome to visualize genomic feature distributions and proximity to transcription start sites using ChIPseeker.

**ASSISTANT:** cloud_workflow: Annotating genomic peak intervals requires reference transcript databases and executing R/Bioconductor pipeline tooling best handled as an asynchronous cloud workflow.

---

## [527] source=multitask_sft_big

**USER:** Identify and quantify emerging adverse event safety signals for semaglutide by analyzing FDA FAERS post-marketing surveillance data using disproportionality metrics like ROR and PRR.

**ASSISTANT:** cloud_workflow: Extracting, filtering, and running disproportionality statistics across millions of multi-year FDA FAERS adverse event records requires an asynchronous multi-step data processing pipeline.

---

## [528] source=multitask_sft_big

**USER:** Estimate and correct for hidden batch effects in an RNA-seq count matrix of 50 tumor and normal samples using surrogate variable analysis (svaseq) prior to differential expression analysis.

**ASSISTANT:** cloud_workflow: Surrogate variable analysis on large sequencing count matrices involves multi-step statistical pipeline execution and data processing that requires cloud computing infrastructure.

---

## [529] source=multitask_sft_big

**USER:** Identify differentially methylated regions across tumor and matched-normal whole-genome bisulfite sequencing datasets using the mbamethyl model-based analysis pipeline.

**ASSISTANT:** cloud_workflow: Processing multi-sample bisulfite sequencing datasets for model-based differential methylation detection requires multi-step, long-running pipeline execution on cloud infrastructure.

---

## [530] source=multitask_sft_big

**USER:** Run Blacksheep outlier analysis on my RNA-seq expression table to identify genes with extreme transcript abundance in TP53-mutant versus wild-type tumors.

**ASSISTANT:** cloud_workflow: Executing an automated Blacksheep piecewise outlier pipeline requires multi-step tabular data processing, threshold calculation, and statistical testing on cloud infrastructure.

---

## [531] source=multitask_sft_big

**USER:** Analyze raw or filtered CITE-seq single-cell RNA and ADT count matrices to perform multimodal normalization, weighted nearest neighbor integration, and surface marker correlation across immune cell populations.

**ASSISTANT:** cloud_workflow: Processing and integrating high-dimensional multimodal single-cell RNA and surface protein datasets requires a multi-step, compute-intensive bioinformatics workflow.

---

## [532] source=multitask_sft_big

**USER:** Construct splicing graphs from RNA-seq BAM alignments and a reference GTF annotation to detect and quantify alternative splicing events across conditions.

**ASSISTANT:** cloud_workflow: Generating splicing graphs from high-throughput transcriptomic alignments requires a multi-step, computationally intensive NGS processing pipeline executed in the cloud.

---

## [533] source=multitask_sft_big

**USER:** Aggregate and standardize protein groups across multiple mass spectrometry runs using the PGCA algorithm on our peptide identification datasets.

**ASSISTANT:** cloud_workflow: PGCA involves running multi-file bioinformatics batch processing and protein group clustering pipelines that require cloud infrastructure.

---

## [534] source=multitask_sft_big

**USER:** Analyze differential expression of small RNA loci across multiple biological conditions stratified by read length classes using the baySeq statistical pipeline.

**ASSISTANT:** cloud_workflow: Running empirical Bayes differential expression analysis across multiple conditions and small RNA length distributions involves long-running multi-step bioinformatic pipeline computation on cloud infrastructure.

---

## [535] source=multitask_sft_big

**USER:** Import and parse an MSP-format tandem mass spectral library into an R Spectra object using MsBackendMsp to inspect precursor m/z values and fragmentation spectra.

**ASSISTANT:** instant_compute: Parsing MSP library files and manipulating spectra objects with MsBackendMsp is a lightweight, deterministic R-based computation suitable for standard execution environments.

---

## [536] source=multitask_sft_big

**USER:** Design an optimized mRNA therapeutic candidate encoding human erythropoietin (EPO), incorporating synonymous codon optimization for hepatic translation, secondary structure free-energy minimization to prevent degradation, and selection of stabilizing 5' and 3' UTRs.

**ASSISTANT:** cloud_design: Designing full-length mRNA therapeutics requires iterative generative sequence optimization and RNA folding simulations across multiple regulatory elements, fitting the cloud_design lane.

---

## [537] source=multitask_sft_big

**USER:** Retrieve a detailed spending summary and budget breakdown for my active NHGRI AnVIL workspaces to monitor cloud compute costs.

**ASSISTANT:** instant_compute: Querying and aggregating cloud workspace billing metrics relies on lightweight API calls and fast data processing that complete within seconds without batch cloud orchestration.

---

## [538] source=multitask_sft_big

**USER:** Retrieve chemical properties, HMDB IDs, and metabolic pathway annotations for a candidate list of dysregulated serum metabolites.

**ASSISTANT:** instant_cited: Database queries and cross-referencing against standard metabolomics repositories require rapid, reference-backed information retrieval without heavy cloud compute.

---

## [539] source=multitask_sft_big

**USER:** Fit a penalized generalized least squares model on high-dimensional gene expression data while controlling for sample relatedness and correlation structure.

**ASSISTANT:** cloud_workflow: Fitting high-dimensional penalized generalized least squares regression models on large genomic matrices requires iterative optimization and cloud-based batch compute resources.

---

## [540] source=multitask_sft_big

**USER:** Build a custom Kraken2 and Bracken taxonomic reference database using bacterial and archaeal genomes from NCBI RefSeq for metagenomic classification.

**ASSISTANT:** cloud_workflow: Generating custom taxonomic indexing databases involves multi-step, resource-intensive sequence retrieval and indexing managed via a Nextflow cloud workflow.

---

## [541] source=multitask_sft_big

**USER:** Run tumor-only somatic variant calling on my tumor BAM alignment file using GATK Mutect2 and generate a filtered VCF of candidate somatic mutations.

**ASSISTANT:** cloud_workflow: Executing a standardized GATK somatic variant calling pipeline on heavy sequencing data requires cloud pipeline orchestration and high-performance compute.

---

## [542] source=multitask_sft_big

**USER:** Evaluate dose-response curves and compute IC50 and AUC metrics from high-throughput cell viability screening data across multiple cell line replicates.

**ASSISTANT:** cloud_workflow: It is an nf-core Nextflow pipeline designed for high-throughput batch processing and pharmacogenomic curve-fitting that requires cloud workflow orchestration.

---

## [543] source=multitask_sft_big

**USER:** Process raw paired-end FASTQ files from a SAMMY-seq experiment to assess chromatin accessibility across nuclear fractions, generating aligned BAM files, normalized coverage bigWig tracks, and QC metrics.

**ASSISTANT:** cloud_workflow: nf-core/sammyseq is a multi-step Nextflow pipeline for processing high-throughput epigenomics sequencing data requiring scalable cloud compute infrastructure.

---

## [544] source=multitask_sft_big

**USER:** Run the IloReg workflow on my single-cell RNA-seq expression matrix to perform iterative leader ordering clustering and identify cell-type-specific gene regulatory drivers.

**ASSISTANT:** cloud_workflow: IloReg executes a computationally demanding, multi-step single-cell clustering and consensus feature-selection pipeline that requires cloud-based bioinformatics workflow infrastructure.

---

## [545] source=multitask_sft_big

**USER:** Build an interactive iSEEindex dashboard to catalog, browse, and launch iSEE exploratory sessions across multiple single-cell RNA-seq datasets.

**ASSISTANT:** cloud_workflow: Aggregating and hosting multiple large SingleCellExperiment objects within an interactive iSEEindex web application requires cloud-based orchestration and persistent runtime resources.

---

## [546] source=multitask_sft_big

**USER:** Generate a sample-to-sample correlation heatmap and MA-plot from my normalized transcriptomic count matrix to evaluate replicate reproducibility across experimental groups.

**ASSISTANT:** cloud_workflow: This task requires running an asynchronous cloud-based bioinformatics pipeline to parse large expression matrices, compute statistical correlation metrics, and render diagnostic transcriptomics plots.

---

## [547] source=multitask_sft_big

**USER:** Analyze high-throughput T-cell receptor CDR3 sequencing data from longitudinal patient samples to quantify repertoire diversity, track expanding clonotypes, and compare V(D)J gene segment usage.

**ASSISTANT:** cloud_workflow: Processing and comparing multi-sample immune repertoire sequencing datasets requires automated, scalable pipeline execution for clonotype alignment, diversity statistics, and comparative reporting.

---

## [548] source=multitask_sft_big

**USER:** Screen and position reactive acrylamide and chloroacetamide warheads onto our lead scaffold targeting Cys797 of the EGFR kinase domain to optimize covalent binding affinity and selectivity.

**ASSISTANT:** cloud_design: Covalent warhead placement and conformational optimization require generative molecular modeling and covalent docking simulations executed on cloud resources.

---

## [549] source=multitask_sft_big

**USER:** Detect allele-specific methylation and identify differentially allele-specifically methylated regions (DAMEs) across multiple whole-genome bisulfite sequencing BAM files.

**ASSISTANT:** cloud_workflow: damefinder is a multi-step bioinformatics pipeline that processes high-throughput bisulfite sequencing alignment files requiring distributed cloud computing resources.

---

## [550] source=multitask_sft_big

**USER:** Perform interactive principal component analysis and quality control exploration on my RNA-seq count matrix to detect potential outliers and batch effects across sample groups.

**ASSISTANT:** cloud_workflow: Running RNA-seq exploratory data analysis pipelines on expression matrices and metadata requires containerized bioinformatics environments and cloud workflow execution.

---

## [551] source=multitask_sft_big

**USER:** Identify significant isoform switching and differential transcript usage between control and knockdown RNA-seq samples using the stageR two-stage testing framework on transcript-level count matrices.

**ASSISTANT:** cloud_workflow: This task entails executing a multi-step transcriptomic statistical analysis pipeline on large-scale count datasets, requiring cloud-based workflow orchestration.

---

## [552] source=multitask_sft_big

**USER:** Evaluate the proarrhythmic cardiotoxicity risk of a lead compound by simulating ventricular action potential duration and net charge (qNet) across therapeutic concentrations using the CiPA O'Hara-Rudy dynamic ODE model parameterized with multi-channel patch-clamp inhibition data.

**ASSISTANT:** cloud_workflow: Simulating stiff cardiac electrophysiology ODE systems over hundreds of pacing cycles across multiple ion-channel inhibition profiles requires multi-step numerical integration orchestrated as an asynchronous cloud workflow.

---

## [553] source=multitask_sft_big

**USER:** Demix SARS-CoV-2 lineages and calculate lineage abundance confidence intervals via Freyja bootstrapping from wastewater sequencing BAM files.

**ASSISTANT:** cloud_workflow: This Nextflow pipeline processes aligned sequencing data through variant calling and iterative Freyja demixing algorithms, requiring distributed cloud workflow execution.

---

## [554] source=multitask_sft_big

**USER:** Identify differentially expressed transcripts in a low-replicate microarray expression dataset by fitting a Power Law Global Error Model (PLGEM) to account for signal-dependent noise.

**ASSISTANT:** cloud_workflow: The PLGEM transcriptomics pipeline involves multi-step data normalization, iterative power-law parameter fitting, and permutation-based significance testing on high-dimensional expression matrices that require automated cloud workflow execution.

---

## [555] source=multitask_sft_big

**USER:** Quantify transcript- and gene-level expression abundances across multiple paired-end RNA-seq FASTQ samples using pseudo-alignment tools against the Ensembl human transcriptome reference.

**ASSISTANT:** cloud_workflow: nf-core/quantify_pseudo_alignment is a distributed Nextflow pipeline that requires cloud compute infrastructure and workflow orchestration to process sequencing reads and perform pseudo-alignment quantification.

---

## [556] source=multitask_sft_big

**USER:** Configure and execute an automated bioinformatics analysis pipeline using pipeFrame to process multi-sample NGS FASTQ data through trimming, alignment, and variant calling.

**ASSISTANT:** cloud_workflow: Running multi-step data processing pipelines with pipeFrame involves intensive computational steps and pipeline orchestration that require cloud workflow infrastructure.

---

## [557] source=multitask_sft_big

**USER:** Annotate my MACS2 ChIP-seq narrowPeak file against the human hg38 genome to identify target genes, visualize genomic feature distributions, and plot peak distance to transcription start sites using ChIPseeker.

**ASSISTANT:** cloud_workflow: ChIP-seq peak annotation requires executing a bioinformatic pipeline that processes genomic coordinate files against reference genome annotation databases.

---

## [558] source=multitask_sft_big

**USER:** I have paired-end total RNA-seq reads from soil microbiome samples without reference genomes. Run the nf-core/metatdenovo pipeline to assemble transcripts de novo, quantify gene expression, and generate functional annotations using EggNOG.

**ASSISTANT:** cloud_workflow: The nf-core/metatdenovo pipeline is a distributed multi-tool Nextflow workflow requiring heavy compute resources for de novo assembly and annotation.

---

## [559] source=multitask_sft_big

**USER:** Visualize predicted B-cell and T-cell epitope profiles across a target protein antigen to identify immunogenic hotspots.

**ASSISTANT:** instant_compute: Generating and rendering immunogenicity landscape visualizations from antigen sequence or scoring data is a fast, deterministic task completed in seconds.

---

## [560] source=multitask_sft_big

**USER:** Find curated databases, modeling software, and cell-line engineering repositories for optimizing therapeutic antibody glycosylation.

**ASSISTANT:** instant_cited: The task retrieves and summarizes established tools and reference repositories using verified literature and database lookups without requiring heavy cloud computing or design pipelines.

---

## [561] source=multitask_sft_big

**USER:** Analyze evolutionary mutational paths and algebraic symmetry shifts across aligned SARS-CoV-2 spike protein coding sequences using the GenomAutomorphism pipeline.

**ASSISTANT:** cloud_workflow: Running the genomautomorphism analysis over genomic sequence alignments requires executing multi-step algebraic and mutational mapping algorithms in an asynchronous cloud pipeline.

---

## [562] source=multitask_sft_big

**USER:** Analyze raw paired-end FASTQ files from an H3K27ac ChIP-seq experiment against the GRCh38 reference genome, including quality control, Bowtie2 alignment, duplicate removal, and MACS2 peak calling.

**ASSISTANT:** cloud_workflow: ChIP-seq processing requires multi-step orchestration of computationally intensive alignment and peak-calling tools operating on large genomic data files in a distributed cloud environment.

---

## [563] source=multitask_sft_big

**USER:** Cluster assembled metagenomic contigs into draft metagenome-assembled genomes (MAGs) using CONCOCT based on sequence composition and differential coverage across samples.

**ASSISTANT:** cloud_workflow: Metagenomic binning with CONCOCT is a multi-step bioinformatic pipeline requiring compute-intensive coverage depth profiling and statistical clustering on cloud infrastructure.

---

## [564] source=multitask_sft_big

**USER:** Run the domain transcriptomics pipeline on paired-end RNA-seq FASTQ samples to quantify protein-domain-level transcript abundance and detect differential domain usage between healthy and diseased tissues.

**ASSISTANT:** cloud_workflow: Domain transcriptomics involves high-throughput alignment, feature quantification, and statistical testing across large sequencing datasets, requiring multi-step batch compute on cloud infrastructure.

---

## [565] source=multitask_sft_big

**USER:** Build a custom Kraken2 taxonomic database by indexing user-provided bacterial genome FASTA files alongside NCBI taxonomy for metagenomic read classification.

**ASSISTANT:** cloud_workflow: Building a Kraken2 database from FASTA files is an intensive multi-step Nextflow pipeline requiring significant RAM and distributed cloud compute.

---

## [566] source=multitask_sft_big

**USER:** Process a continuous stream of raw FASTQ sequencing files through automated quality control, adapter trimming, and alignment pipelines.

**ASSISTANT:** cloud_workflow: Orchestrating high-throughput data ingestion, trimming, and alignment across distributed compute nodes requires an asynchronous multi-step cloud workflow.

---

## [567] source=multitask_sft_big

**USER:** Process small RNA-seq aligned BAM files to quantify miRNA and isomiR expression using mirTop and generate comprehensive alignment statistics.

**ASSISTANT:** cloud_workflow: Executing this Nextflow-based nf-core pipeline across multi-sample BAM datasets requires distributed cloud compute and containerized workflow orchestration.

---

## [568] source=multitask_sft_big

**USER:** Generate comparative RNA secondary structure arc diagrams and analyze base-pairing covariation across homologous transcript sequences using the R4RNA workflow.

**ASSISTANT:** cloud_workflow: Analyzing multi-sequence alignments and rendering comparative secondary structure annotations requires an orchestrated, containerized bioinformatics data-processing workflow.

---

## [569] source=multitask_sft_big

**USER:** Annotate and analyze distal promoter-enhancer chromatin loops from paired-end ChIA-PET sequencing data to characterize regulatory interactions across the genome.

**ASSISTANT:** cloud_workflow: Processing high-throughput chromatin conformation datasets requires multi-step alignment, anchor annotation, and statistical loop-calling pipelines executed on scalable cloud compute.

---

## [570] source=multitask_sft_big

**USER:** Run CellBender on my raw droplet scRNA-seq H5AD file to remove ambient RNA contamination and output a cleaned AnnData object.

**ASSISTANT:** cloud_workflow: Executing CellBender for ambient RNA removal on single-cell AnnData datasets requires high-performance cloud batch execution and GPU acceleration.

---

## [571] source=multitask_sft_big

**USER:** Run exploratory data analysis and quality control profiling on tandem mass spectrometry identification tables across our multi-batch proteomics experiment.

**ASSISTANT:** cloud_workflow: Comprehensive MS/MS exploratory data analysis and QC report generation across multi-sample proteomics datasets require automated, multi-step pipeline processing on scalable cloud infrastructure.

---

## [572] source=multitask_sft_big

**USER:** Run functional enrichment analysis on a list of differentially expressed genes from an RNA-seq experiment to identify significantly overrepresented GO terms and KEGG pathways.

**ASSISTANT:** cloud_workflow: Executing the fenr transcriptomics pipeline requires multi-step workflow orchestration and data-intensive processing best handled via cloud infrastructure.

---

## [573] source=multitask_sft_big

**USER:** Run an automated hierarchical gating pipeline on a batch of 30 PBMC flow cytometry FCS files using an OpenCyto gating template to quantify T-cell subsets across study cohorts.

**ASSISTANT:** cloud_workflow: Processing multi-sample FCS files through an OpenCyto gating template involves high-throughput bioinformatic data processing that requires containerized cloud execution.

---

## [574] source=multitask_sft_big

**USER:** Demultiplex raw Illumina NovaSeq BCL files into individual sample FASTQ files using a provided sample sheet and bcl-convert.

**ASSISTANT:** cloud_workflow: Executing nf-core/bcl_demultiplex requires orchestrating a multi-step Nextflow pipeline over high-volume raw sequencing data on cloud or cluster infrastructure.

---

## [575] source=multitask_sft_big

**USER:** Identify orthologous transposable elements and KRAB-ZFP gene regulatory interactions between human and chimpanzee transcriptome count data using the TEKRABber pipeline.

**ASSISTANT:** cloud_workflow: Running TEKRABber involves multi-step transcriptome-wide differential expression and correlation analysis across large sample matrices, requiring cloud workflow orchestration.

---

## [576] source=multitask_sft_big

**USER:** Process raw LC-MS/MS mass spectrometry data using the HERON pipeline to perform peptide identification, label-free quantification, and differential protein abundance analysis between patient and control cohorts.

**ASSISTANT:** cloud_workflow: The HERON proteomics pipeline requires distributed batch orchestration and significant computational resources to process large raw MS files through multi-step search, quantification, and statistical modeling.

---

## [577] source=multitask_sft_big

**USER:** Construct an interaction network for the NCI-PID p53 signaling pathway and compute node degree and betweenness centrality metrics using NCIgraph.

**ASSISTANT:** instant_compute: Parsing pathway databases into graph objects and calculating standard topological metrics runs deterministically in a few seconds.

---

## [578] source=multitask_sft_big

**USER:** Perform differential expression analysis on my normalized microarray gene expression dataset using Laplace mixture modeling with the lapmix package.

**ASSISTANT:** cloud_workflow: Fitting mixture models across genome-wide expression matrices requires batch statistical processing and pipeline execution on cloud bioinformatics infrastructure.

---

## [579] source=multitask_sft_big

**USER:** Identify differentially methylated cytosines (DMCs) and regions (DMRs) across tumor and normal WGBS samples using methylSig.

**ASSISTANT:** cloud_workflow: Differential methylation analysis across high-coverage whole-genome bisulfite sequencing datasets requires multi-sample statistical testing executed through an asynchronous cloud bioinformatics workflow.

---

## [580] source=multitask_sft_big

**USER:** Calculate semantic similarity scores across a list of candidate genes associated with Parkinson's disease using the Disease Ontology to identify functionally coherent gene subsets.

**ASSISTANT:** cloud_workflow: This task executes an R-based bioinformatics pipeline requiring specialized ontology databases and structured multi-step similarity matrix computations.

---

## [581] source=multitask_sft_big

**USER:** Quantify trabecular and cortical microarchitecture parameters (BV/TV, Tb.Th, Tb.N, and cortical thickness) from a batch of murine femoral microCT DICOM image stacks to evaluate treatment efficacy in an osteoporosis model.

**ASSISTANT:** cloud_workflow: Processing 3D volumetric microCT datasets involves multi-step image segmentation, thresholding, and standardized morphometric calculations that require scalable cloud compute resources.

---

## [582] source=multitask_sft_big

**USER:** Perform automated quality control on multi-parameter flow cytometry FCS files using flowClean to detect and filter out anomalous fluorescent events caused by flow rate fluctuations.

**ASSISTANT:** cloud_workflow: Running automated QC algorithms and anomaly detection on high-dimensional flow cytometry data files requires cloud workflow execution and file handling.

---

## [583] source=multitask_sft_big

**USER:** Run the nf-core/diseasemodulediscovery pipeline using my GWAS-derived risk genes and a human protein-protein interaction network to identify significant disease module subnetworks.

**ASSISTANT:** cloud_workflow: This is an nf-core bioinformatics pipeline designed to execute network medicine algorithms and graph clustering across biological networks in a cloud workflow environment.

---

## [584] source=multitask_sft_big

**USER:** Predict the disruption or creation of transcription factor binding motifs caused by a set of non-coding GWAS single-nucleotide variants.

**ASSISTANT:** cloud_workflow: motifbreakR requires loading large reference genome assemblies and comprehensive transcription factor position weight matrix databases, which necessitates execution within a cloud workflow environment.

---

## [585] source=multitask_sft_big

**USER:** Run taxonomic and functional profiling on a cohort of 50 paired-end whole-genome shotgun metagenomic FASTQ samples to identify differentially abundant gut bacterial species and metabolic pathways.

**ASSISTANT:** cloud_workflow: Metagenomic profiling requires resource-intensive multi-step pipelines (quality trimming, host removal, taxonomic classification, and pathway mapping) running over large raw sequencing datasets on cloud infrastructure.

---

## [586] source=multitask_sft_big

**USER:** Cluster and visualize overlapping gene set enrichment results from my RNA-seq experiment using visse to identify coherent biological themes.

**ASSISTANT:** instant_compute: The visse package performs fast, lightweight network-based clustering and thematic visualization of gene set enrichment data that executes directly in an interactive R environment without requiring multi-node cloud orchestration.

---

## [587] source=multitask_sft_big

**USER:** Convert a perturbational RNA-seq differential expression matrix into pathway expression profiles (PEPs) across MSigDB gene sets using the gep2pep pipeline.

**ASSISTANT:** cloud_workflow: Running the gep2pep Bioconductor workflow requires batch computational resources to compute rank-based pathway enrichments across large transcriptomic matrices.

---

## [588] source=multitask_sft_big

**USER:** Map a set of single-cell RNA-seq cluster annotations to standardized Cell Ontology terms and extract their lineage hierarchies using the ontoproc R package.

**ASSISTANT:** instant_compute: Ontology traversal and term mapping via ontoproc are lightweight computational tasks that execute rapidly within an interactive R environment without requiring distributed cloud infrastructure.

---

## [589] source=multitask_sft_big

**USER:** Reconstruct active intracellular signaling pathways from my bulk RNA-seq differential expression dataset by finding network paths between perturbed receptors and target transcription factors across the human interactome.

**ASSISTANT:** cloud_workflow: Network-based pathway reconstruction from transcriptomics data requires multi-step computational pipeline execution and graph traversal across large interactome networks on cloud infrastructure.

---

## [590] source=multitask_sft_big

**USER:** Run the nf-core/fastquorum pipeline to detect and analyze quorum-sensing gene clusters across my bacterial isolate sequencing datasets.

**ASSISTANT:** cloud_workflow: This is an nf-core Nextflow pipeline requiring multi-step, scalable execution across cloud or HPC infrastructure.

---

## [591] source=multitask_sft_big

**USER:** Scan my set of ATAC-seq peak FASTA sequences against human JASPAR transcription factor position weight matrices using motifmatchr to identify putative motif binding sites.

**ASSISTANT:** cloud_workflow: Scanning large sets of genomic sequences against motif position weight matrices requires dedicated compute resources to run Bioconductor sequence-matching pipelines.

---

## [592] source=multitask_sft_big

**USER:** Run the nf-core utility Nextflow pipeline on my compute cluster to test workflow configuration and validate parameter settings across test datasets.

**ASSISTANT:** cloud_workflow: This is a Nextflow-based pipeline that requires orchestrating containerized multi-step batch jobs on distributed cloud or HPC infrastructure.

---

## [593] source=multitask_sft_big

**USER:** Perform gene set enrichment analysis on an H3K4me3 ChIP-seq peak BED file to identify enriched Gene Ontology terms while adjusting for locus length bias.

**ASSISTANT:** cloud_workflow: ChIP-Enrich runs a specialized genomic interval analysis workflow requiring reference annotation databases and statistical modeling that execute asynchronously in a cloud environment.

---

## [594] source=multitask_sft_big

**USER:** Perform power analysis and sample size estimation on single-cell RNA-seq pilot data to determine the number of cells and sequencing depth required to detect differentially expressed genes across conditions.

**ASSISTANT:** cloud_workflow: POWSC involves parameter estimation, iterative single-cell count simulations, and repeated differential expression testing that require batch cloud compute.

---

## [595] source=multitask_sft_big

**USER:** Align paired-end whole-genome sequencing FASTQ reads from a patient sample against the GRCh38 human reference genome and generate coordinate-sorted BAM files with marked duplicates.

**ASSISTANT:** cloud_workflow: Aligning high-throughput genomic sequencing data against a reference genome is computationally intensive and requires distributed cloud infrastructure running bioinformatics pipeline tools.

---

## [596] source=multitask_sft_big

**USER:** Identify putative RNA-binding protein binding sites and enriched motifs across my human eCLIP transcriptomic dataset.

**ASSISTANT:** cloud_workflow: This task entails executing a multi-step batch transcriptomic pipeline on cloud infrastructure to process sequencing data, call peaks, and annotate sequence binding sites.

---

## [597] source=multitask_sft_big

**USER:** Benchmark gene expression platform accuracy, precision, and bias across known RNA spike-in concentrations in our transcriptomic dataset using spktools.

**ASSISTANT:** cloud_workflow: Analyzing multi-sample spike-in transcriptomic data and generating calibration curves requires running a full cloud bioinformatics pipeline.

---

## [598] source=multitask_sft_big

**USER:** Convert a multi-sample cohort VCF file into an indexed on-disk VCFArray backend to enable scalable genotype matrix queries across thousands of samples.

**ASSISTANT:** cloud_workflow: Transforming large-scale genomic VCF datasets into multidimensional array structures is a data-intensive batch pipeline requiring distributed cloud storage and workflow execution.

---

## [599] source=multitask_sft_big

**USER:** Run the ERMA pipeline on raw paired-end whole-genome bisulfite sequencing FASTQ files to perform adapter trimming, bisulfite-aware alignment, and generate genome-wide CpG methylation profiles.

**ASSISTANT:** cloud_workflow: The ERMA pipeline is a high-throughput, multi-step epigenomic processing workflow requiring substantial cloud compute, storage, and parallel execution for alignment and methylation extraction.

---

## [600] source=multitask_sft_big

**USER:** Analyze spatial cell-cell interactions and aggregate neighborhood graphs from segmented multiplexed imaging mass cytometry (IMC) data across patient tissue samples.

**ASSISTANT:** cloud_workflow: Processing multi-image spatial single-cell datasets for neighborhood analysis and permutation-based interaction testing requires a multi-step, computationally intensive R pipeline executed in the cloud.

---

## [601] source=multitask_sft_big

**USER:** Calculate hexagonal bin summaries on my single-cell RNA-seq UMAP embeddings using schex to visualize marker gene expression without overplotting.

**ASSISTANT:** instant_compute: Binning dimensionally reduced single-cell data and rendering hexbin plots is a lightweight R-based analytical task that executes quickly within an interactive compute environment.

---

## [602] source=multitask_sft_big

**USER:** Identify discordant read pairs and structural variation-induced fusion transcripts from paired-end RNA-seq FASTQ samples across a 30-patient cancer cohort.

**ASSISTANT:** cloud_workflow: Detecting discordant read alignments and structural fusions from high-throughput RNA-seq data requires intensive multi-step pipeline orchestration and scalable cloud compute.

---

## [603] source=multitask_sft_big

**USER:** Combine correlated gene-level differential expression p-values for a 45-gene hypoxia signature using our RNA-seq expression matrix to obtain an accurate pathway-level significance score.

**ASSISTANT:** cloud_workflow: Executing Empirical Brown's Method on transcriptomic datasets requires running containerized Bioconductor statistical pipelines to compute empirical correlation structures across sample expression profiles.

---

## [604] source=multitask_sft_big

**USER:** Identify robust molecular biomarker signatures across integrated metabolomics and lipidomics profiling datasets from a clinical cohort using the Biosigner multi-assay pipeline.

**ASSISTANT:** cloud_workflow: This multi-assay statistical feature selection pipeline processes multi-omics data matrices through repeated cross-validation classifiers, requiring distributed cloud pipeline execution.

---

## [605] source=multitask_sft_big

**USER:** Cluster differentially expressed genes across a multi-condition RNA-seq time-course experiment and generate quality control and expression profile plots using DEGreport.

**ASSISTANT:** cloud_workflow: Running DEGreport on transcriptomic count matrices requires batch processing, clustering algorithms, and pipeline execution best suited for a cloud workflow environment.

---

## [606] source=multitask_sft_big

**USER:** Process a 40 GB microarray intensity dataset using BufferedMatrix to perform out-of-core normalization and filtering without running out of RAM.

**ASSISTANT:** cloud_workflow: Manipulating out-of-core, disk-buffered genomic matrices requires scalable cloud compute infrastructure and high-throughput scratch storage beyond standard local resources.

---

## [607] source=multitask_sft_big

**USER:** Generate an interactive HTML report with IGV-compatible genomic track visualizations and sample annotations for a set of ChIP-seq peak intervals.

**ASSISTANT:** cloud_workflow: Building interactive track tables across genomic regions and sequencing files requires cloud workflow orchestration to process genomic data and render visual report assets.

---

## [608] source=multitask_sft_big

**USER:** Identify co-expression gene modules and uncover hierarchical network organization from a normalized bulk RNA-seq expression matrix using NetSAM.

**ASSISTANT:** cloud_workflow: NetSAM executes multi-step, computationally intensive network construction, seriation, and module identification algorithms on transcriptomic data that require batch cloud workflow execution.

---

## [609] source=multitask_sft_big

**USER:** Generate a formatted HTML test report summarizing liquid handler execution logs and well-plate dispense metrics for pipeline validation.

**ASSISTANT:** instant_compute: Rendering a structured HTML validation report from test data involves lightweight deterministic templating and code execution that completes immediately without external cloud infrastructure.

---

## [610] source=multitask_sft_big

**USER:** Normalize my TMT phosphoproteomics abundance matrix against matched total protein expression levels to account for protein turnover and uncover true phosphorylation site dynamics.

**ASSISTANT:** cloud_workflow: The PhosphoNormalizer pipeline processes large-scale paired proteomic and phosphoproteomic quantification tables through multi-step statistical corrections and QC filtering on cloud execution infrastructure.

---

## [611] source=multitask_sft_big

**USER:** Visualize and compare differential gene expression across three treatment timepoints mapped directly onto the KEGG Cell Cycle pathway using Pathview.

**ASSISTANT:** cloud_workflow: Rendering multi-sample KEGG pathway maps from transcriptomic datasets requires cloud-based bioinformatic pipeline execution to handle pathway coordinate fetching, expression mapping, and high-resolution rendering.

---

## [612] source=multitask_sft_big

**USER:** Identify differentially spliced gene isoforms between control and drug-treated RNA-seq samples using regsplice on exon and junction count matrices.

**ASSISTANT:** cloud_workflow: Differential alternative splicing detection with regsplice requires statistical modeling and pipeline execution on multi-sample RNA-seq count datasets via cloud infrastructure.

---

## [613] source=multitask_sft_big

**USER:** Call copy number variants and loss of heterozygosity from Illumina SNP microarray Log R Ratio and B-allele frequency data using the VanillaICE workflow.

**ASSISTANT:** cloud_workflow: VanillaICE is an automated genomic variant-calling pipeline that requires cloud computing infrastructure to process high-throughput microarray intensity datasets.

---

## [614] source=multitask_sft_big

**USER:** Optimize the coding sequence of human interleukin-2 for maximal heterologous expression in Escherichia coli BL21(DE3) while removing BsaI and BsmBI restriction sites and avoiding repetitive hairpins.

**ASSISTANT:** instant_compute: Codon optimization relies on deterministic algorithms utilizing host-specific codon adaptation tables and rule-based motif filtering that execute rapidly in-memory without requiring heavy cloud compute or generative deep learning models.

---

## [615] source=multitask_sft_big

**USER:** Map the subcellular localization of human proteins from high-resolution quantitative proteomics fractionation data using the SubCellBarCode pipeline.

**ASSISTANT:** cloud_workflow: SubCellBarCode requires executing a multi-step, resource-intensive spatial proteomics bioinformatics pipeline with machine-learning classification on large fractionation datasets.

---

## [616] source=multitask_sft_big

**USER:** Run a differential methylation analysis pipeline on multi-sample epigenomic sequencing datasets to identify significantly altered genomic regions and generate QC summaries.

**ASSISTANT:** cloud_workflow: Epigenomic profiling with the yamss workflow requires multi-step alignment, statistical modeling, and high-throughput processing across large sequencing datasets that necessitate cloud pipeline orchestration.

---

## [617] source=multitask_sft_big

**USER:** Query the WikiPathways database using rWikiPathways to download and render the human apoptosis pathway image with mapped expression values from imaging mass cytometry.

**ASSISTANT:** instant_compute: It runs a lightweight R script to query the WikiPathways API and generate annotated pathway visualizations locally within seconds without requiring distributed cloud infrastructure.

---

## [618] source=multitask_sft_big

**USER:** Create an R CDF environment package from an Affymetrix tiling microarray CDF file for ChIP-chip epigenomic profiling analysis.

**ASSISTANT:** instant_compute: The task is a lightweight, single-step Bioconductor utility execution that parses a CDF file into an R package within seconds in an interactive environment.

---

## [619] source=multitask_sft_big

**USER:** Generate comprehensive mapping and alignment quality metrics for a cohort of whole-genome sequencing BAM files using samtools stats, flagstat, and idxstats.

**ASSISTANT:** cloud_workflow: Executing an nf-core Nextflow pipeline across large genomic alignment files requires distributed cloud workflow orchestration.

---

## [620] source=multitask_sft_big

**USER:** Quantify transposable element and human endogenous retrovirus (HERV) expression levels from my RNA-seq alignment BAM files using the Telescope reassignment model.

**ASSISTANT:** cloud_workflow: Telescope quantification is a compute- and memory-intensive bioinformatics pipeline that resolves multi-mapping RNA-seq reads across repetitive genomic loci, requiring execution on cloud or HPC infrastructure.

---

## [621] source=multitask_sft_big

**USER:** Perform differential expression analysis on a paired-sample RNA-seq count matrix using baySeq with a beta-binomial model to detect differentially expressed genes.

**ASSISTANT:** cloud_workflow: Empirical Bayes differential expression modeling on high-throughput transcriptome count data involves multi-step statistical fitting and iterative parameter estimation suited for cloud workflow execution.

---

## [622] source=multitask_sft_big

**USER:** Query the CZ CELLxGENE Discover portal using cellxgenedp to identify and filter single-cell RNA-seq datasets profiling human pulmonary fibrosis.

**ASSISTANT:** instant_compute: Querying and filtering dataset metadata through the cellxgenedp API is a lightweight programmatic task that completes within seconds without requiring heavy cloud compute resources.

---

## [623] source=multitask_sft_big

**USER:** Infer a transcriptional gene regulatory network from my time-series knockout microarray dataset using the Network Topology Weight (NTW) algorithm.

**ASSISTANT:** cloud_workflow: Inferring network topology weights from multi-condition expression datasets involves computationally intensive regression and parameter estimation best suited for an asynchronous cloud workflow.

---

## [624] source=multitask_sft_big

**USER:** Import text files containing p-values and FDR estimates from multiple differential gene expression callers into iCOBRA and export standardized performance evaluation tables.

**ASSISTANT:** cloud_workflow: Executing this transcriptomics benchmarking pipeline requires automated data transformation and evaluation across tool outputs within a containerized cloud workflow environment.

---

## [625] source=multitask_sft_big

**USER:** Cluster and visualize enriched Gene Ontology terms from my RNA-seq differential expression results into hierarchical subtrees and consensus groups using goSTAG.

**ASSISTANT:** instant_compute: Hierarchical structuring and visualization of GO terms from tabular enrichment results with goSTAG runs quickly within an interactive R environment without demanding high-performance cloud infrastructure.

---

## [626] source=multitask_sft_big

**USER:** Identify high-order epistatic gene-gene interactions associated with disease risk from cohort PLINK genotype data using a genetic algorithm.

**ASSISTANT:** cloud_workflow: Genome-wide epistasis detection via genetic algorithms involves intensive combinatorial search across large variant datasets requiring distributed cloud workflow execution.

---

## [627] source=multitask_sft_big

**USER:** Align pooled CRISPR screen FASTQ reads to a custom sgRNA reference library using BWA to generate alignment files and quantify guide RNA counts across treatment conditions.

**ASSISTANT:** cloud_workflow: Processing high-throughput sequencing reads with BWA alignment and abundance counting requires multi-step computational pipeline execution on cloud infrastructure.

---

## [628] source=multitask_sft_big

**USER:** Identify differentially methylated cut sites and genomic regions between control and treated samples from multiplexed methylation-sensitive bisulfite sequencing (mRRBS) count data.

**ASSISTANT:** cloud_workflow: Analyzing genome-wide methylation-sensitive bisulfite sequencing datasets involves multi-step statistical processing and high-throughput NGS data pipelines suited for cloud workflow execution.

---

## [629] source=multitask_sft_big

**USER:** Run a functional enrichment benchmark across my differential gene expression results to identify significantly overrepresented biological pathways and evaluate method consistency.

**ASSISTANT:** cloud_workflow: This task entails executing a multi-step transcriptomic pipeline requiring cloud infrastructure to process differential expression tables and compute pathway enrichment statistics.

---

## [630] source=multitask_sft_big

**USER:** Analyze allele-specific expression from my scRNA-seq BAM files and phased VCF to characterize monoallelic expression across individual cell clusters.

**ASSISTANT:** cloud_workflow: Processing aligned single-cell sequencing data to quantify allele-level counts requires heavy multi-step pipeline orchestration and substantial compute resources.

---

## [631] source=multitask_sft_big

**USER:** Verify whether the pre-trained DeepVariant v1.6 whole-genome sequencing model checkpoint is already downloaded and cached locally.

**ASSISTANT:** instant_compute: Checking the local availability or download status of a model file is an immediate, lightweight verification task that executes instantaneously without requiring cloud orchestration or heavy model inference.

---

## [632] source=multitask_sft_big

**USER:** Run a joint single-cell RNA-seq and ATAC-seq analysis on paired 10x Multiome FASTQ files from human PBMCs to call chromatin peaks, quantify gene expression, and identify cell-type-specific regulatory networks.

**ASSISTANT:** cloud_workflow: Processing paired single-cell RNA and ATAC sequencing data involves resource-intensive, multi-step bioinformatics pipelines for alignment, peak calling, and multimodal integration that require distributed cloud infrastructure.

---

## [633] source=multitask_sft_big

**USER:** Run automated gating and high-dimensional clustering analysis on multi-channel imaging flow cytometry data from a 96-well panel to characterize distinct immune cell sub-populations.

**ASSISTANT:** cloud_workflow: Processing high-dimensional flow or imaging cytometry data across multiple samples requires an asynchronous multi-step pipeline executing data preprocessing, normalization, and clustering on cloud infrastructure.

---

## [634] source=multitask_sft_big

**USER:** Create an alternative CDF environment for an Affymetrix HG-U133 Plus 2.0 microarray using updated Ensembl gene annotations to regroup probe sets by transcript targets.

**ASSISTANT:** instant_compute: The task involves running lightweight R/Bioconductor code to parse probe coordinates and re-assign probe set mappings, which executes quickly within standard interactive compute resources.

---

## [635] source=multitask_sft_big

**USER:** Annotate untargeted LC-MS/MS metabolomics features from mzML files by matching experimental tandem mass spectra against the MassBank reference spectral library.

**ASSISTANT:** cloud_workflow: Batch spectral matching and metabolite identification across large mass spectrometry datasets require asynchronous cloud pipeline execution and substantial compute resources.

---

## [636] source=multitask_sft_big

**USER:** Calculate the amino acid composition, molecular weight, isoelectric point, and net charge for a set of peptide sequences in FASTA format using pepstat.

**ASSISTANT:** instant_compute: The pepstat tool executes lightweight, deterministic physicochemical property calculations for peptides in seconds without needing heavy cloud infrastructure.

---

## [637] source=multitask_sft_big

**USER:** Run quality control assessments and differential guide abundance analysis on a pooled CRISPR screen count matrix using gCrisprTools to identify significantly depleted and enriched target genes.

**ASSISTANT:** cloud_workflow: Processing pooled CRISPR screening count matrices through QC visualization, statistical normalization, and gene-level testing requires a high-throughput bioinformatic workflow.

---

## [638] source=multitask_sft_big

**USER:** Estimate cell-type proportions from bulk RNA-seq gene expression matrices of human tumor biopsies using reference transcriptomic signatures.

**ASSISTANT:** cloud_workflow: Running multi-step transcriptomic processing and deconvolution pipelines on high-dimensional expression datasets requires distributed cloud workflow execution.

---

## [639] source=multitask_sft_big

**USER:** Retrieve study metadata and the normalized metabolite abundance matrix for study ST001000 from the Metabolomics Workbench repository using the REST API for exploratory analysis.

**ASSISTANT:** instant_compute: Querying the Metabolomics Workbench API and parsing tabular study matrices executes rapidly within an interactive R computing environment without requiring distributed cloud pipelines.

---

## [640] source=multitask_sft_big

**USER:** Benchmark the performance, runtime, and phenotype relevance of multiple gene set enrichment methods (e.g., GSEA, CAMERA, and ORA) across curated GEO RNA-seq datasets using the GSEABenchmarkeR pipeline.

**ASSISTANT:** cloud_workflow: Systematically benchmarking multiple enrichment analysis algorithms across extensive transcriptomic reference datasets involves a high-throughput, multi-step pipeline requiring cloud workflow orchestration.

---

## [641] source=multitask_sft_big

**USER:** Predict base-resolution epigenomic and transcriptional signal tracks for a 100 kb genomic region surrounding a candidate regulatory variant using the AlphaGenome model.

**ASSISTANT:** cloud_models: Predicting multi-track functional genomic profiles from sequence inputs relies on large deep learning genomic foundation models requiring GPU-accelerated inference.

---

## [642] source=multitask_sft_big

**USER:** Analyze raw mzML mass spectrometry files from our label-free quantitative proteomics experiment against the human UniProt database to identify and quantify differentially abundant proteins.

**ASSISTANT:** cloud_workflow: nf-core/proteomicslfq is an intensive multi-step Nextflow pipeline for mass spectrometry search and feature quantification that requires scalable, distributed cloud computing infrastructure.

---

## [643] source=multitask_sft_big

**USER:** Assemble and taxonomically classify viral contigs from raw paired-end Illumina wastewater metagenomic sequencing data to survey circulating viral pathogens.

**ASSISTANT:** cloud_workflow: nf-core/viralmetagenome is an extensive, multi-step Nextflow pipeline that requires scalable high-performance cloud compute to perform read QC, host depletion, de novo assembly, and viral taxonomic annotation.

---

## [644] source=multitask_sft_big

**USER:** Calculate concordance metrics and compare copy number variation (CNV) segmentation profiles across multiple tumor-normal sample pairs.

**ASSISTANT:** cloud_workflow: Evaluating multi-sample CNV callsets requires running a specialized bioinformatics workflow on cloud infrastructure to process genomic segments and generate statistical metrics.

---

## [645] source=multitask_sft_big

**USER:** Detect low-frequency somatic single nucleotide variants from our high-depth targeted sequencing BAM files across multiple matched control replicates using the deepSNV Shearwater Bayesian algorithm.

**ASSISTANT:** cloud_workflow: Running Bayesian variant calling on high-coverage deep sequencing alignment files requires a multi-step, compute-intensive bioinformatics cloud pipeline.

---

## [646] source=multitask_sft_big

**USER:** Filter out human host contamination and non-target taxa from raw paired-end metagenomic sequencing reads prior to downstream assembly.

**ASSISTANT:** cloud_workflow: nf-core/detaxizer is a comprehensive Nextflow pipeline that requires scalable cloud compute to classify and remove unwanted taxonomic reads using reference databases.

---

## [647] source=multitask_sft_big

**USER:** Integrate paired miRNA and mRNA expression datasets from tumor and normal samples using miRIT to identify dysregulated regulatory networks and functionally enriched target pathways.

**ASSISTANT:** cloud_workflow: Executing the miRIT integrative pipeline requires multi-step computational batch processing across expression matrices and target prediction databases on cloud infrastructure.

---

## [648] source=multitask_sft_big

**USER:** Run the OUTRIDER pipeline on a normalized RNA-seq count matrix of 50 patient samples to detect aberrant gene expression outliers and identify candidate disease-associated genes.

**ASSISTANT:** cloud_workflow: Fitting autoencoders and computing genome-wide statistical significance for expression outliers across multi-sample RNA-seq datasets requires substantial computational resources executed as an asynchronous cloud pipeline.

---

## [649] source=multitask_sft_big

**USER:** Identify differentially expressed proteins and infer functional pathway alterations from label-free quantitative mass spectrometry intensity matrices across patient cohorts.

**ASSISTANT:** cloud_workflow: Processing raw or filtered proteomics intensity datasets through normalization, missing-value imputation, and statistical inference requires an asynchronous cloud workflow pipeline.

---

## [650] source=multitask_sft_big

**USER:** Determine Km, Vmax, and kcat by fitting initial velocity data from a fluorogenic substrate titration to the Michaelis-Menten equation for a recombinant protease.

**ASSISTANT:** instant_compute: Non-linear regression analysis of enzyme kinetic data is a deterministic, lightweight numerical calculation that completes rapidly in an interactive computing session.

---

## [651] source=multitask_sft_big

**USER:** Calculate inbreeding coefficients and the additive relationship matrix from a four-generation pedigree dataset using the GeneticsPed package.

**ASSISTANT:** instant_compute: Pedigree tracing, sorting, and kinship matrix calculations are lightweight deterministic R computations that run within seconds inside a sandbox environment.

---

## [652] source=multitask_sft_big

**USER:** Analyze raw paired-end RIC-seq chimeric sequencing data from human cells to identify and annotate genome-wide RNA-RNA duplex interactions.

**ASSISTANT:** cloud_workflow: Processing high-throughput RNA-RNA crosslinking sequencing data requires an intensive multi-step pipeline for read trimming, chimeric mapping, and duplex calling that necessitates cloud infrastructure.

---

## [653] source=multitask_sft_big

**USER:** Integrate matched DNA methylation arrays and RNA-seq gene expression datasets from a TCGA lung adenocarcinoma cohort using EpiMix to identify functional epigenetic driver genes.

**ASSISTANT:** cloud_workflow: Fitting beta-mixture models and regularized regression across paired high-dimensional methylation and transcriptomic cohort data requires intensive multi-step computational pipeline execution in the cloud.

---

## [654] source=multitask_sft_big

**USER:** Run the REBET pipeline to perform gene-based rare variant association tests across multiple disease subphenotypes using whole-exome VCF files and phenotype data.

**ASSISTANT:** cloud_workflow: Analyzing multi-sample genomic variant data for subphenotype associations requires long-running, distributed workflow execution on cloud infrastructure.

---

## [655] source=multitask_sft_big

**USER:** Screen a library of 100,000 vendor small molecules against a 4-point receptor-based pharmacophore model to identify candidate hits for follow-up docking.

**ASSISTANT:** cloud_workflow: Screening large multi-conformer chemical libraries against 3D spatial pharmacophores requires distributed batch processing on asynchronous cloud infrastructure.

---

## [656] source=multitask_sft_big

**USER:** Perform differential expression analysis on RNA-seq raw count matrices across two treatment groups using the TCC normalization and tag-count comparison pipeline.

**ASSISTANT:** cloud_workflow: The TCC pipeline involves multi-step statistical normalization and differential expression testing across replicate genomic datasets that require cloud-based bioinformatics workflow orchestration.

---

## [657] source=multitask_sft_big

**USER:** I have single-cell RNA-seq count matrices from multiple experimental batches that show sequencing depth disparities; please run the batchelor batch rescaling pipeline to normalize coverage and correct batch-to-batch scale differences across all shared genes.

**ASSISTANT:** cloud_workflow: Running batchelor batch rescaling requires executing a multi-step single-cell transcriptomics data processing pipeline on cloud infrastructure to handle memory-intensive count matrices.

---

## [658] source=multitask_sft_big

**USER:** Cluster and generate heatmaps of ChIP-seq signal profiles around transcription start sites across multiple histone modification bigWig files using profileplyr.

**ASSISTANT:** cloud_workflow: Extracting and clustering read coverage profiles from multiple large bigWig files across tens of thousands of genomic loci requires cloud-scale compute memory and parallel file I/O.

---

## [659] source=multitask_sft_big

**USER:** Perform quality control, functional normalization, and probe-wise differential methylation analysis on raw Illumina EPIC array IDAT files comparing tumor and normal tissue samples.

**ASSISTANT:** cloud_workflow: Processing and normalizing multi-sample raw DNA methylation microarray datasets with minfi requires an intensive, multi-step bioinformatics pipeline executed in a scalable cloud environment.

---

## [660] source=multitask_sft_big

**USER:** Authenticate with Illumina BaseSpace to retrieve project metadata, query sequencing runs, and download aligned BAM and VCF files for a cohort of clinical samples.

**ASSISTANT:** cloud_workflow: Retrieving and staging large-scale high-throughput sequencing data from Illumina BaseSpace requires orchestrating asynchronous cloud data transfers and secondary analysis pipelines.

---

## [661] source=multitask_sft_big

**USER:** Identify evolutionary conserved transcription factor binding sites across a multi-species whole-genome alignment using JASPAR position frequency matrices and TFBSTools.

**ASSISTANT:** cloud_workflow: Genome-wide phylogenetic footprinting requires intensive alignment parsing and large-scale motif scanning across multiple genomes, demanding long-running cloud compute infrastructure.

---

## [662] source=multitask_sft_big

**USER:** Execute an end-to-end bulk RNA-seq pipeline on raw paired-end FASTQ samples, including FastQC quality control, STAR alignment against GRCh38, featureCounts gene quantification, and DESeq2 differential expression analysis.

**ASSISTANT:** cloud_workflow: Executing a standardized multi-step raw transcriptomics pipeline requires distributed compute, containerized tools, and workflow management for alignment and quantification.

---

## [663] source=multitask_sft_big

**USER:** Process and normalize raw GenePix (.gpr) protein microarray files using protgear to perform background subtraction, replicate filtering, and batch-corrected intensity normalization across samples.

**ASSISTANT:** cloud_workflow: Processing raw multi-file protein microarray datasets through multi-step background correction, CV filtering, and normalization requires batch compute in a cloud workflow.

---

## [664] source=multitask_sft_big

**USER:** Run pseudobulk differential gene expression analysis across cell types and clinical conditions on a multi-donor scRNA-seq dataset using dreamlet.

**ASSISTANT:** cloud_workflow: dreamlet performs resource-intensive pseudobulk processing and linear mixed-effects modeling on large single-cell cohort datasets that necessitate cloud pipeline execution.

---

## [665] source=multitask_sft_big

**USER:** Process paired-end FASTQ reads from an INTACT-seq experiment to perform quality control, nuclear transcript alignment, and differential expression analysis across distinct cell types.

**ASSISTANT:** cloud_workflow: End-to-end processing of multi-sample sequencing data through alignment and quantification requires a multi-step pipeline executed on scalable cloud infrastructure.

---

## [666] source=multitask_sft_big

**USER:** Profile the spatial distribution of MeRIP-seq m6A peaks across transcript landmarks (5' UTR, CDS, and 3' UTR) from a BED file using the Guitar package.

**ASSISTANT:** cloud_workflow: Mapping large genomic interval datasets to transcriptomic landmarks and generating distribution plots requires multi-step bioinformatic cloud pipeline execution with transcript annotation data.

---

## [667] source=multitask_sft_big

**USER:** Run comprehensive quality control, adapter trimming, and summary reporting on raw paired-end Illumina FASTQ files from a whole-genome sequencing run.

**ASSISTANT:** cloud_workflow: Evaluating raw sequencing read quality and filtering large FASTQ files requires multi-step bioinformatic tool execution best handled by a cloud workflow engine.

---

## [668] source=multitask_sft_big

**USER:** Predict the shift in single-cell transcriptional states for CD8+ T cells following IFNG stimulation using a pre-trained GEARS model on my Perturb-seq dataset.

**ASSISTANT:** cloud_models: Predicting cellular perturbation responses relies on specialized deep learning foundation and graph neural network models that require GPU-accelerated cloud compute for inference.

---

## [669] source=multitask_sft_big

**USER:** Perform feature selection via binomial deviance on a large-scale scRNA-seq dataset of 200,000 cells stored in an HDF5-backed matrix using the scry package.

**ASSISTANT:** cloud_workflow: Calculating deviance feature selection on massive single-cell transcriptomics matrices requires scalable, high-memory cloud computing infrastructure.

---

## [670] source=multitask_sft_big

**USER:** Process raw paired-end FASTQ reads from a massively parallel reporter assay (MPRA) to extract barcodes, quantify DNA and RNA tag counts, and assess the differential regulatory activity of non-coding candidate variants.

**ASSISTANT:** cloud_workflow: Analyzing MPRA sequencing data requires an orchestrated multi-step batch pipeline for read trimming, barcode parsing, quantification, and statistical modeling of enhancer activity across biological replicates.

---

## [671] source=multitask_sft_big

**USER:** Identify gene fusions and structural variants from paired-end targeted DNA sequencing FASTQ files of tumor-biopsy samples.

**ASSISTANT:** cloud_workflow: dnafusion is a multi-step Nextflow pipeline that requires distributed cloud resources to align reads and run computationally intensive structural variant callers.

---

## [672] source=multitask_sft_big

**USER:** Execute a custom Nextflow pipeline to align paired-end whole-exome sequencing FASTQ files against the GRCh38 reference genome with BWA-MEM2 and call germline SNVs using GATK HaplotypeCaller.

**ASSISTANT:** cloud_workflow: Orchestrating multi-step genomics data processing on large raw sequencing files requires distributed batch compute and pipeline management on cloud infrastructure.

---

## [673] source=multitask_sft_big

**USER:** Reconstruct the clonal evolutionary trajectories and subclonal architecture from longitudinal tumor whole-exome sequencing data of colorectal cancer patients.

**ASSISTANT:** cloud_workflow: The nf-core/tumourevo pipeline requires distributed compute orchestration to process high-throughput genomic sequencing files through multi-step clonal deconvolution and phylogenetic analysis tools.

---

## [674] source=multitask_sft_big

**USER:** Query and extract verified ligand-receptor pairs and downstream signaling pathways from OmniPath for a set of differentially expressed genes to model cell-cell communication.

**ASSISTANT:** instant_compute: Querying and filtering prior knowledge interaction networks via the OmnipathR API is lightweight and completes within seconds in a standard interactive execution environment without distributed cloud infrastructure.

---

## [675] source=multitask_sft_big

**USER:** Analyze high-dimensional multiplexed imaging data to construct phenotype graphs and identify differential cell population clusters between treated and control cohorts.

**ASSISTANT:** cloud_workflow: Constructing and statistically analyzing cell phenotype graphs from large imaging datasets requires a multi-step, distributed data processing pipeline executed on cloud infrastructure.

---

## [676] source=multitask_sft_big

**USER:** Run gene set enrichment analysis on my paired-end RNA-seq count matrix to identify dysregulated KEGG pathways while accounting for read count distribution and gene length bias.

**ASSISTANT:** cloud_workflow: Running SeqGSEA requires heavy permutation-based statistical testing and multi-step data processing pipelines on high-throughput RNA-seq datasets that necessitate cloud infrastructure.

---

## [677] source=multitask_sft_big

**USER:** Perform SAMspectral clustering on high-dimensional single-cell flow cytometry data to identify distinct immune cell subpopulations and rare phenotypes.

**ASSISTANT:** cloud_workflow: Executing SAMspectral spectral clustering on high-dimensional single-cell data requires running a compute-intensive bioinformatics processing pipeline in a cloud execution environment.

---

## [678] source=multitask_sft_big

**USER:** Infer regulatory modules and identify driver genes by integrating RNA-seq gene expression, DNA methylation, and copy number variation datasets from TCGA using the AMARETTO pipeline.

**ASSISTANT:** cloud_workflow: AMARETTO is a complex, multi-step regulatory network inference pipeline operating across large multi-omics datasets that requires batch cloud execution resources.

---

## [679] source=multitask_sft_big

**USER:** Call narrow peaks on my H3K4me3 ChIP-seq alignment BAM file against the matched input control using MACS2 with a q-value cutoff of 0.01.

**ASSISTANT:** cloud_workflow: Executing MACS2 on large sequencing BAM files requires cloud infrastructure to run the multi-step genomics data processing pipeline.

---

## [680] source=multitask_sft_big

**USER:** Annotate my whole-exome sequencing VCF file with VEP and filter for high-confidence non-synonymous variants with a minor allele frequency below 1%.

**ASSISTANT:** cloud_workflow: Annotating and filtering large genomic VCF datasets requires running standard bioinformatic pipelines and toolchains that execute via cloud workflows.

---

## [681] source=multitask_sft_big

**USER:** Sanitize and standardize read headers in my batch of paired-end Illumina FASTQ files to fix non-standard naming schemes and validate sequence formatting prior to running nf-core/rnaseq.

**ASSISTANT:** cloud_workflow: This task involves executing an nf-core Nextflow workflow to process and validate large sequencing data sets in parallel using distributed cloud compute.

---

## [682] source=multitask_sft_big

**USER:** Perform a meta-analysis on multi-cohort transcriptomic expression data to identify robust differentially expressed genes across disparate origins using the Rank Product algorithm.

**ASSISTANT:** cloud_workflow: This multi-origin transcriptomic meta-analysis requires executing an end-to-end bioinformatics pipeline on cloud infrastructure to process and statistically integrate data from multiple cohorts.

---

## [683] source=multitask_sft_big

**USER:** Reconstruct cellular lineage trees and characterize indel scar distributions from single-cell CRISPR-Cas9 lineage tracing sequencing data using LinTInd.

**ASSISTANT:** cloud_workflow: The LinTInd pipeline requires a scalable multi-step bioinformatics workflow to process sequencing reads, call indel mutations, and reconstruct compute-intensive phylogenetic lineage trees.

---

## [684] source=multitask_sft_big

**USER:** Extract known pseudouridine and m6A modification sites on human mRNA transcripts and map them to genomic coordinates using the EpiTxDb Bioconductor package.

**ASSISTANT:** instant_compute: Querying and filtering epitranscriptomic modifications from an SQLite-backed EpiTxDb object requires lightweight, fast R code execution without distributed cloud resources.

---

## [685] source=multitask_sft_big

**USER:** Download and integrate somatic mutation, RNA-seq, and clinical data for the TCGA-BRCA cohort from cBioPortal into a MultiAssayExperiment object.

**ASSISTANT:** cloud_workflow: Retrieving and assembling multi-omic cancer datasets across multiple assays involves an asynchronous, network-intensive genomics ETL pipeline.

---

## [686] source=multitask_sft_big

**USER:** Generate a comprehensive quality control and comparative repertoire report from multiple antibody sequencing libraries to evaluate V(D)J germline gene usage, CDR3 diversity, and somatic hypermutation rates.

**ASSISTANT:** cloud_workflow: Analyzing and visualizing multi-sample antibody repertoire sequencing datasets requires substantial memory and multi-step pipeline execution typical of NGS cloud workflows.

---

## [687] source=multitask_sft_big

**USER:** I want to see the list of all supported pathway and functional annotation databases available in BioMate for running gene set enrichment analysis.

**ASSISTANT:** instant_cited: This is a lightweight metadata retrieval task that returns standard reference catalog information without running heavy computational analysis.

---

## [688] source=multitask_sft_big

**USER:** Perform automated model-based clustering and population gating on multi-parameter flow cytometry FCS files using flowClust.

**ASSISTANT:** cloud_workflow: Automated clustering of large-scale flow cytometry datasets requires running a multi-step bioinformatics pipeline on cloud compute infrastructure.

---

## [689] source=multitask_sft_big

**USER:** Run the seqcat pipeline on multi-sample VCF files to assess concordance and batch-evaluate variant calls across multiple sequencing platforms.

**ASSISTANT:** cloud_workflow: Executing variant concordance analysis and processing multi-sample VCF callsets requires pipeline orchestration and compute resources appropriate for a cloud workflow.

---

## [690] source=multitask_sft_big

**USER:** Run the xenLite pipeline on my raw 10x Xenium spatial transcriptomics dataset to perform transcript assignment QC, filter low-confidence spots, and generate single-cell spatial count matrices.

**ASSISTANT:** cloud_workflow: Processing high-resolution single-cell spatial transcriptomics data involves distributed computing and multi-step pipeline execution on large image and coordinate files.

---

## [691] source=multitask_sft_big

**USER:** Standardize and integrate clinical findings with flow cytometry assay data from ImmPort study SDY269 into Bioconductor ExpressionSet objects for downstream immune response analysis.

**ASSISTANT:** cloud_workflow: Harmonizing multi-assay clinical trial cohorts from the ImmPort database requires an orchestrated bioinformatic data extraction and transformation pipeline executed on cloud infrastructure.

---

## [692] source=multitask_sft_big

**USER:** Analyze differential exon usage across my paired-end RNA-seq samples from treated and control conditions using DEXSeq to detect alternative splicing.

**ASSISTANT:** cloud_workflow: DEXSeq requires computationally intensive exon-level count aggregation and generalized linear modeling across biological replicates, necessitating distributed cloud workflow execution.

---

## [693] source=multitask_sft_big

**USER:** Initialize and validate pipeline parameters, input schemas, and environment configuration for a standardized nf-core workflow execution.

**ASSISTANT:** cloud_workflow: This is a Nextflow-based workflow utility designed to orchestrate and validate distributed bioinformatics pipeline runs in a cloud environment.

---

## [694] source=multitask_sft_big

**USER:** Integrate filtered 10x Genomics single-cell TCR sequencing data with our Seurat object using scRepertoire to quantify clonotype diversity and visualize dominant clonotypes across T-cell clusters.

**ASSISTANT:** cloud_workflow: Processing single-cell V(D)J repertoire data and integrating it with large scRNA-seq expression matrices requires a multi-step bioinformatic pipeline executed in a cloud compute environment.

---

## [695] source=multitask_sft_big

**USER:** Load and parse a multi-gigabyte imzML mass spectrometry imaging dataset to extract spatial coordinates and m/z spectra for downstream MSI analysis.

**ASSISTANT:** cloud_workflow: Processing large-scale mass spectrometry imaging files such as imzML requires cloud-based asynchronous compute due to high memory and file-handling demands.

---

## [696] source=multitask_sft_big

**USER:** Process raw 10x Genomics Xenium in situ spatial transcriptomics data through quality control, transcript assignment, cell segmentation, and initial clustering.

**ASSISTANT:** cloud_workflow: Running the nf-core/spatialxe Nextflow pipeline requires containerized, multi-core cloud compute resources to process and analyze high-volume spatial imaging and transcriptomic datasets.

---

## [697] source=multitask_sft_big

**USER:** Perform advanced read quality control and contaminant filtering on raw paired-end Illumina metagenomic FASTQ files to trim adapters, remove low-quality reads, and generate comprehensive QC metrics.

**ASSISTANT:** cloud_workflow: Running multi-step read quality control and contamination screening on large sequencing files requires dedicated batch cloud compute and bioinformatics workflow orchestration.

---

## [698] source=multitask_sft_big

**USER:** Run quality control assessment and generate an aggregate MultiQC report on raw paired-end Illumina FASTQ reads to detect low-quality bases and adapter contamination.

**ASSISTANT:** cloud_workflow: Comprehensive sequencing quality control requires running batch bioinformatic pipeline tools on large NGS data files using cloud infrastructure.

---

## [699] source=multitask_sft_big

**USER:** Run the nf-core/variantcatalogue pipeline on multi-sample cohort VCF files to generate a comprehensive variant catalogue with calculated allele frequencies and quality metrics.

**ASSISTANT:** cloud_workflow: nf-core/variantcatalogue is an asynchronous, resource-intensive Nextflow pipeline that orchestrates distributed cloud batch computing to aggregate and catalog large-scale genomic variation data.

---

## [700] source=multitask_sft_big

**USER:** Extract and annotate unique anchor nodes from genome-wide HiChIP chromatin interaction data in BEDPE format to identify regulatory hub loci across the human genome.

**ASSISTANT:** cloud_workflow: Parsing genome-scale chromatin conformation datasets and annotating interaction nodes across chromosomes requires multi-step bioinformatics pipeline execution on cloud infrastructure.

---

## [701] source=multitask_sft_big

**USER:** Process a cohort of paired-end RNA-seq FASTQ samples to perform quality control, alignment, read counting, and edgeR differential gene expression analysis using an automated systemPipeR workflow.

**ASSISTANT:** cloud_workflow: systemPipeR coordinates multi-step NGS command-line tools and heavy compute tasks across distributed cloud or cluster environments.

---

## [702] source=multitask_sft_big

**USER:** Map a list of human Ensembl gene IDs to their corresponding gene symbols, Entrez IDs, and chromosomal coordinates using the Homo.sapiens OrganismDbi package.

**ASSISTANT:** instant_compute: Querying and cross-referencing annotations via OrganismDbi is a lightweight R computation that runs in seconds on standard CPU environments without requiring cloud pipeline orchestration.

---

## [703] source=multitask_sft_big

**USER:** Perform cluster deconvolution and generate spatial pie chart visualizations on my 10x Visium spatial transcriptomics count matrix and tissue coordinates using SpatialCPie.

**ASSISTANT:** cloud_workflow: Running SpatialCPie involves multi-step constrained matrix factorization and cluster proportion modeling across spatial transcriptomics datasets, requiring a containerized cloud workflow pipeline.

---

## [704] source=multitask_sft_big

**USER:** Align the 3D coordinates of wild-type human glucokinase (PDB: 1V4S) with the allosterically activated state (PDB: 3IDH) to calculate backbone RMSD and identify conformational shifts in the active site.

**ASSISTANT:** instant_compute: Pairwise protein structural superposition and RMSD calculation run deterministically in seconds within an execution sandbox using standard structural alignment libraries.

---

## [705] source=multitask_sft_big

**USER:** Prioritize candidate disease proteins for dilated cardiomyopathy from a specified list of seed genes using functional annotations and weighted protein-protein interaction networks.

**ASSISTANT:** instant_compute: The wppi algorithm performs network-based random walk calculations and functional scoring that run rapidly within a standard analytical compute environment without requiring distributed pipeline infrastructure.

---

## [706] source=multitask_sft_big

**USER:** Estimate individual ancestry coefficients and evaluate cross-entropy across K=1 to K=8 using sNMF in LEA on my genotype dataset of 300 natural Arabidopsis accessions.

**ASSISTANT:** cloud_workflow: Iterative population structure inference and LFMM association scans across multiple latent factors require long-running compute and pipeline orchestration on cloud infrastructure.

---

## [707] source=multitask_sft_big

**USER:** Calculate relative gene expression fold-changes from my RT-qPCR Ct data using the 2^(-ddCt) method with GAPDH as the reference gene across treated and control conditions.

**ASSISTANT:** instant_compute: Delta-delta Ct quantification performs straightforward, deterministic statistical calculations on small tabular qPCR datasets that execute in seconds without distributed cloud resources.

---

## [708] source=multitask_sft_big

**USER:** Run a domain-level differential transcriptomics analysis on RNA-seq count data to identify significantly dysregulated protein domain expression patterns across disease cohorts.

**ASSISTANT:** cloud_workflow: High-throughput transcriptomic processing and domain-level expression quantification require multi-step, resource-intensive bioinformatics pipelines executed asynchronously in the cloud.

---

## [709] source=multitask_sft_big

**USER:** Quantify the spatial overlap and calculate Pearson's and Manders' colocalization coefficients between GLUT4 and the transferrin receptor in dual-channel confocal immunofluorescence Z-stacks of skeletal muscle tissue.

**ASSISTANT:** cloud_workflow: Processing high-resolution multi-channel microscopy image files through background subtraction, Costes thresholding, and pixel-intensity correlation pipelines requires asynchronous, high-throughput cloud computation.

---

## [710] source=multitask_sft_big

**USER:** Filter out unexpressed and background-level probes from my microarray expression matrix using limma detection p-values prior to differential expression analysis.

**ASSISTANT:** cloud_workflow: Preprocessing and filtering large transcriptomic expression datasets using limma constitutes an asynchronous bioinformatics data processing pipeline executed in the cloud.

---

## [711] source=multitask_sft_big

**USER:** Retrieve the coding sequences (CDS) in FASTA format for human BRCA1 (ENSG00000012048) and TP53 (ENSG00000141510) across all canonical transcript isoforms.

**ASSISTANT:** instant_compute: Fetching and extracting annotated coding sequences from standard biological databases via REST APIs is a deterministic, lightweight task that completes in seconds.

---

## [712] source=multitask_sft_big

**USER:** Find alternative antihypertensive medications to replace amlodipine for a patient taking simvastatin to avoid adverse drug interactions based on the DDInter database.

**ASSISTANT:** cloud_workflow: This process requires querying the DDInter database, screening therapeutic alternatives via ATC codes, and ranking candidate compounds through an automated interaction-filtering workflow.

---

## [713] source=multitask_sft_big

**USER:** Visualize multiplexed marker expression and cell phenotype segmentation masks across multi-region imaging mass cytometry (IMC) tissue samples.

**ASSISTANT:** cloud_workflow: Generating composite multi-channel image visualizations and segmented cell overlays from high-dimensional imaging datasets requires scalable batch cloud execution.

---

## [714] source=multitask_sft_big

**USER:** Detect transcription start sites and perform differential TSS usage analysis across conditions from aligned 5'-end CAGE-seq BAM files using icetea.

**ASSISTANT:** cloud_workflow: Analyzing high-throughput aligned sequencing BAM files for TSS peak identification and differential transcription expression requires automated, resource-intensive cloud workflow execution.

---

## [715] source=multitask_sft_big

**USER:** Perform differential expression and calibrated principal component analysis on an RNA-seq assay with precision weights using the weitrix Bioconductor workflow to account for observational uncertainty.

**ASSISTANT:** cloud_workflow: Executing end-to-end transcriptomic variance calibration and exploratory component modeling on weighted expression matrices requires multi-step data processing within a dedicated cloud workflow environment.

---

## [716] source=multitask_sft_big

**USER:** Calculate tumor microenvironment (TME) cell-type infiltration and immune signature scores from a bulk RNA-seq expression matrix of patient samples.

**ASSISTANT:** cloud_workflow: Batch transcriptomic signature deconvolution and immune scoring across cohorts involve multi-step data processing pipelines suited for cloud workflow orchestration.

---

## [717] source=multitask_sft_big

**USER:** Infer single-cell clonal assignments and subclone architecture by integrating scRNA-seq variant allele matrices with bulk somatic mutation profiles using cardelino.

**ASSISTANT:** cloud_workflow: Cardelino requires a multi-step bioinformatics workflow environment to process high-dimensional single-cell mutation counts and perform Bayesian MCMC subclonal deconvolution.

---

## [718] source=multitask_sft_big

**USER:** Simulate clonal evolution and drug resistance dynamics across 100 tumor replicates using OncoSimulR with an epistatic fitness landscape of five driver genes.

**ASSISTANT:** cloud_workflow: Stochastic simulations of tumor progression and clonal dynamics across multiple replicates require long-running computational pipeline execution.

---

## [719] source=multitask_sft_big

**USER:** Run nf-core/createpanelrefs to generate target interval references, GC-content annotations, and a panel of normals from our targeted capture design BED files and baseline control BAMs.

**ASSISTANT:** cloud_workflow: Executing the full nf-core/createpanelrefs Nextflow pipeline for reference generation across multiple control samples requires cloud-scale workflow orchestration.

---

## [720] source=multitask_sft_big

**USER:** Retrieve taxonomic abundance profiles and sample metadata from the EBI MGnify database for marine study MGYS00002010 to perform downstream diversity analysis in R.

**ASSISTANT:** instant_compute: MGnifyR functions as a lightweight R client querying the public EBI MGnify API to fetch and structure metadata and abundance tables, requiring only fast interactive compute rather than heavy cloud pipelines.

---

## [721] source=multitask_sft_big

**USER:** Merge overlapping and adjacent ChIP-seq peak intervals from my BED file into a unified, non-redundant consensus peak set.

**ASSISTANT:** instant_compute: Merging genomic coordinate intervals is a deterministic, lightweight interval-arithmetic task that can be executed rapidly in an instant compute environment.

---

## [722] source=multitask_sft_big

**USER:** Analyze two-condition transcriptomic count data using the Twilight pipeline to detect differentially expressed genes and estimate local false discovery rates.

**ASSISTANT:** cloud_workflow: Executing end-to-end transcriptomic pipelines like Twilight requires distributed compute resources for multi-step statistical modeling and gene filtering.

---

## [723] source=multitask_sft_big

**USER:** Perform penalized Cox proportional hazards regression and dynamic survival risk prediction on a high-dimensional clinical transcriptomics dataset using rcaspar.

**ASSISTANT:** cloud_workflow: This multi-step transcriptomics analysis requires automated cross-validation, feature penalization, and bootstrap resampling on cohort-scale expression matrices in a managed workflow environment.

---

## [724] source=multitask_sft_big

**USER:** I want to extract and unpack multiple large compressed tar.gz archives containing raw FASTQ files from a sequencing project using the nf-core/archive_extract pipeline.

**ASSISTANT:** cloud_workflow: Executing an nf-core pipeline to batch unpack distributed, large-scale genomic archive files requires scalable cloud workflow infrastructure.

---

## [725] source=multitask_sft_big

**USER:** Perform tensor decomposition-based unsupervised feature extraction on my multi-condition transcriptomic dataset to identify key differentially expressed biomarker genes.

**ASSISTANT:** cloud_workflow: Executing TD-based unsupervised feature extraction across large multidimensional transcriptomic matrices is a multi-step bioinformatics pipeline requiring asynchronous cloud processing.

---

## [726] source=multitask_sft_big

**USER:** Parse a BioPAX Level 3 OWL file from Reactome to extract the molecular interaction network and generate node-edge tables for network analysis.

**ASSISTANT:** instant_compute: Parsing BioPAX XML files and converting pathway topologies into graph data structures is a fast, deterministic R-based computation that executes within standard interactive compute resources.

---

## [727] source=multitask_sft_big

**USER:** Identify potential repurposable drug candidates for non-alcoholic steatohepatitis (NASH) by screening our disease-associated differential gene expression profile against reference drug-induced perturbation signatures using the DrugVsDisease pipeline.

**ASSISTANT:** cloud_workflow: This task requires running an asynchronous, multi-step bioinformatics pipeline that queries large reference perturbagen expression databases to calculate connectivity and enrichment scores.

---

## [728] source=multitask_sft_big

**USER:** Fit substrate concentration versus initial reaction velocity data to the Michaelis-Menten equation to determine Vmax, Km, and turnover number.

**ASSISTANT:** instant_compute: Non-linear regression analysis of enzyme kinetic data is a deterministic mathematical calculation that runs immediately without requiring heavy cloud orchestration.

---

## [729] source=multitask_sft_big

**USER:** Perform advanced tensor decomposition-based unsupervised feature extraction on multi-condition transcriptomic expression matrices to identify robust biomarker gene sets.

**ASSISTANT:** cloud_workflow: Executing tensor decomposition workflows on high-dimensional multi-sample transcriptomics data requires multi-step processing and scalable cloud compute infrastructure.

---

## [730] source=multitask_sft_big

**USER:** Generate an interactive sequence feature plot showing post-translational modifications and Pfam domains for human p53 (P04637).

**ASSISTANT:** instant_compute: Rendering protein feature tracks and sequence annotations with Pviz is a lightweight deterministic task that executes in seconds without requiring distributed cloud infrastructure.

---

## [731] source=multitask_sft_big

**USER:** Calculate gene signature enrichment scores for T cell exhaustion and cytotoxicity gene sets across cells in my single-cell RNA-seq Seurat object using UCell.

**ASSISTANT:** cloud_workflow: Evaluating rank-based gene set scores across thousands of single cells within a Seurat pipeline is a multi-step bioinformatics task that requires cloud workflow execution for scalable compute and memory handling.

---

## [732] source=multitask_sft_big

**USER:** Perform set-based and network-based pathway enrichment analysis on an RNA-seq differential expression dataset using KEGG pathways.

**ASSISTANT:** cloud_workflow: The EnrichmentBrowser pipeline requires cloud infrastructure to normalize expression matrices, map gene sets, and run computationally intensive network-based enrichment algorithms.

---

## [733] source=multitask_sft_big

**USER:** Run the semi-supervised cell type annotation workflow on my unlabeled single-cell RNA-seq count matrix using the provided PBMC labeled reference dataset.

**ASSISTANT:** cloud_workflow: Executing a semi-supervised transcriptomics workflow requires orchestrating multi-step preprocessing, iterative model training, and label propagation over large single-cell datasets on cloud infrastructure.

---

## [734] source=multitask_sft_big

**USER:** Identify conserved transcriptional submodules between case and control samples by integrating differential expression profiles with protein-protein interaction networks using the AMOUNTAIN two-layer module detection algorithm.

**ASSISTANT:** cloud_workflow: This task involves executing a multi-step bioinformatics network-analysis pipeline that requires sustained cloud computation for multi-layered graph optimization and permutation testing.

---

## [735] source=multitask_sft_big

**USER:** Analyze targeted CRISPR-Cas9 amplicon sequencing FASTQ reads to evaluate editing efficiency, quantify indel profiles, and identify mutation outcomes across treated samples.

**ASSISTANT:** cloud_workflow: Running the nf-core/crisprseq Nextflow pipeline requires distributed cloud infrastructure to process raw high-throughput sequencing reads through alignment and editing-quantification tools.

---

## [736] source=multitask_sft_big

**USER:** Interactively explore organelle proteomics data to inspect protein subcellular localization assignments and validate organelle markers using an interactive dashboard.

**ASSISTANT:** cloud_workflow: Launching and serving the interactive R/Shiny environment of pRolocGUI requires persistent cloud container hosting and session management.

---

## [737] source=multitask_sft_big

**USER:** Quantify transposable element and gene expression levels from our aligned RNA-seq BAM files using the TEtranscripts and atena quantification pipeline.

**ASSISTANT:** cloud_workflow: Processing and quantifying repetitive elements from large RNA-seq BAM files requires substantial computational resources and workflow orchestration on the cloud.

---

## [738] source=multitask_sft_big

**USER:** Evaluate my pipeline of candidate small molecules against the ICH S7A core battery to predict adverse liabilities across cardiovascular, respiratory, and central nervous systems.

**ASSISTANT:** cloud_workflow: Assessing candidates against regulatory ICH S7A safety pharmacology endpoints requires an orchestrated cloud pipeline running multi-endpoint predictive models across vital organ systems.

---

## [739] source=multitask_sft_big

**USER:** Apply a pre-trained frozen surrogate variable analysis (fSVA) model to adjust for batch effects and estimate surrogate variables in my validation RNA-seq expression dataset.

**ASSISTANT:** cloud_workflow: This workflow executes multi-sample transcriptomic batch-correction and matrix transformations on input expression data, which requires dedicated cloud workflow execution.

---

## [740] source=multitask_sft_big

**USER:** Identify cell types and sub-states showing significant differential abundance between drug-treated and control patients by running MiloR neighborhood contrast testing on my single-cell RNA-seq dataset.

**ASSISTANT:** cloud_workflow: Differential abundance analysis using MiloR requires neighborhood graph construction, dispersion estimation, and contrast modeling on large single-cell datasets, necessitating scalable cloud pipeline execution.

---

## [741] source=multitask_sft_big

**USER:** Generate an interactive filtering widget to inspect and sort differential expression statistics from my uploaded summary table.

**ASSISTANT:** instant_compute: Configuring and rendering interactive UI widgets from structured tabular data is handled via lightweight, immediate deterministic computation.

---

## [742] source=multitask_sft_big

**USER:** Predict the pathogenicity and clinical impact of novel missense variants across the human BRCA1 protein using AlphaMissense.

**ASSISTANT:** cloud_models: AlphaMissense requires GPU-accelerated deep learning model inference in the cloud to evaluate structural variant effects and pathogenicity scores.

---

## [743] source=multitask_sft_big

**USER:** Identify copy number variants (CNVs) across a cohort of tumor-normal whole-exome sequencing BAM files using CODEX normalization and segmentation.

**ASSISTANT:** cloud_workflow: Multi-sample exome depth extraction, Poisson latent factor modeling, and genome-wide CNV segmentation require high-memory, long-running cloud workflow orchestration.

---

## [744] source=multitask_sft_big

**USER:** Identify rare DNA methylation outliers across whole-blood Illumina EPIC array samples from patients with rare developmental disorders compared to a reference cohort.

**ASSISTANT:** cloud_workflow: Genome-wide epimutation screening across multi-sample methylation arrays involves batch normalization and heavy statistical outlier modeling requiring distributed cloud pipeline execution.

---

## [745] source=multitask_sft_big

**USER:** Simulate single-cell RNA-seq count matrices across distinct biological groups using Splatter to benchmark differential expression sensitivity and compare synthetic cell distributions against an empirical reference dataset.

**ASSISTANT:** cloud_workflow: Generating synthetic single-cell datasets, fitting Splatter parameters, and computing comparative differential metrics requires an orchestrated batch bioinformatics execution pipeline.

---

## [746] source=multitask_sft_big

**USER:** Transfer annotated cell types from a reference human PBMC scRNA-seq dataset to an unannotated clinical cohort dataset using an unsupervised integration pipeline.

**ASSISTANT:** cloud_workflow: Cross-dataset single-cell RNA-seq integration and label transfer require a multi-step, memory-intensive bioinformatics pipeline executed on cloud infrastructure.

---

## [747] source=multitask_sft_big

**USER:** Identify cell-type marker genes from a single-cell RNA-seq UMI count matrix using Gamma-Poisson generalized linear models with glmGamPoi.

**ASSISTANT:** cloud_workflow: Fitting Gamma-Poisson GLMs across thousands of genes and single cells is a multi-step, compute-intensive transcriptomic pipeline that requires execution in a cloud workflow environment.

---

## [748] source=multitask_sft_big

**USER:** Run a cross-study differential expression analysis on raw RNA-seq count matrices from treated versus control patient cohorts to identify shared significantly perturbed genes.

**ASSISTANT:** cloud_workflow: Differential expression across transcriptomic datasets involves multi-step data normalization, statistical modeling, and contrast evaluation that requires structured cloud pipeline execution.

---

## [749] source=multitask_sft_big

**USER:** Calculate stably expressed gene (scSEG) indices from my normalized single-cell RNA-seq matrix to identify reliable negative control genes for downstream batch correction in scMerge.

**ASSISTANT:** cloud_workflow: Computing single-cell stably expressed gene indices requires executing multi-step matrix-level transcriptomic algorithms within a cloud workflow environment.

---

## [750] source=multitask_sft_big

**USER:** Process my raw GRO-seq FASTQ reads to align the data, generate HOMER tag directories, and call nascent transcripts and active transcription units.

**ASSISTANT:** cloud_workflow: nf-core/homer_groseq is a multi-step Nextflow pipeline requiring distributed cloud computing resources to process raw sequencing reads through QC, alignment, and HOMER-based nascent transcription analysis.

---

## [751] source=multitask_sft_big

**USER:** Identify validated and predicted mRNA targets for human microRNAs hsa-miR-21-5p and hsa-miR-155-5p and retrieve their associated disease annotations using multiMiR.

**ASSISTANT:** instant_compute: Querying microRNA target databases and annotations via the multiMiR package is a lightweight programmatic task that completes within seconds in a sandboxed compute environment.

---

## [752] source=multitask_sft_big

**USER:** Decontaminate ambient RNA and spot-swapping noise from my 10x Visium spatial transcriptomics count matrix using SpotClean.

**ASSISTANT:** cloud_workflow: Running SpotClean requires computational processing of full spatial expression matrices via an asynchronous cloud pipeline.

---

## [753] source=multitask_sft_big

**USER:** Run differential protein conformation and abundance analysis on paired limited proteolysis-mass spectrometry (LiP-MS) and global proteomics datasets comparing drug-treated versus control samples using MSstatsLiP.

**ASSISTANT:** cloud_workflow: MSstatsLiP is a complex, multi-step statistical pipeline that performs normalization, peptide-to-protein summarization, and differential testing across large quantitative mass spectrometry datasets requiring cloud compute resources.

---

## [754] source=multitask_sft_big

**USER:** Design a CRISPR-assisted genomic integration cassette to engineer Escherichia coli Nissle 1917 for hypoxia-inducible delivery of an anti-inflammatory nanobody at a validated safe-harbor locus.

**ASSISTANT:** cloud_design: Generating targeted bacterial genomic knock-in strategies requires complex genetic circuit composition, promoter optimization, and homology arm construct design.

---

## [755] source=multitask_sft_big

**USER:** Perform automated quality control and filter out low-quality cells from an scRNA-seq count matrix of 8,000 cells using the cellity classification pipeline.

**ASSISTANT:** cloud_workflow: Executing feature extraction and machine-learning-based quality control on large single-cell transcriptomic datasets requires cloud-based pipeline execution with scalable compute resources.

---

## [756] source=multitask_sft_big

**USER:** Deduplicate my UMI-tagged RNA-seq alignment BAM files using UMI-tools and generate post-deduplication mapping statistics with Samtools.

**ASSISTANT:** cloud_workflow: This is an nf-core Nextflow pipeline designed to process large genomic BAM files through computationally intensive UMI deduplication and alignment quality metrics calculation on cloud infrastructure.

---

## [757] source=multitask_sft_big

**USER:** Run consensus clustering on a normalized single-cell RNA-seq expression matrix using clusterExperiment to identify stable cell subpopulations.

**ASSISTANT:** cloud_workflow: Resampling-based consensus clustering across high-dimensional single-cell transcriptomic data requires sustained computational memory and multi-core cloud pipeline execution.

---

## [758] source=multitask_sft_big

**USER:** Run comprehensive quality control, fragment size distribution, and transcription start site enrichment analysis on my paired-end ATAC-seq BAM files.

**ASSISTANT:** cloud_workflow: ATAC-seq quality control and downstream chromatin accessibility analysis involve processing large sequencing files through multi-step bioinformatics tools requiring scalable cloud workflow execution.

---

## [759] source=multitask_sft_big

**USER:** Process raw paired-end Hi-C FASTQ files from a human sample to map chromatin interactions, generate normalized Hi-C contact maps, and call topologically associating domains (TADs).

**ASSISTANT:** cloud_workflow: nf-core/hic is a multi-step Nextflow bioinformatics pipeline that requires cloud-based distributed computing resources to process large sequencing datasets into genome-wide contact matrices.

---

## [760] source=multitask_sft_big

**USER:** Estimate cell-type proportions from bulk RNA-seq gene expression profiles using a reference scRNA-seq signature matrix.

**ASSISTANT:** cloud_workflow: Transcriptomic deconvolution involves multi-sample statistical modeling and reference matrix normalization that requires running a batch bioinformatics workflow in the cloud.

---

## [761] source=multitask_sft_big

**USER:** Predict potential lysine acetylation sites and their mediating acetyltransferases (such as p300/CBP) in human p53 using ASEB.

**ASSISTANT:** instant_compute: ASEB evaluates sequence motifs and position-specific scoring matrices for acetylation prediction, completing execution in seconds without heavy GPU or distributed cloud infrastructure.

---

## [762] source=multitask_sft_big

**USER:** Process raw paired-end ATAC-seq FASTQ reads to perform adapter trimming, align to the GRCh38 human reference genome, filter mitochondrial reads, and call open chromatin peaks using MACS2.

**ASSISTANT:** cloud_workflow: It is a standard high-throughput Nextflow pipeline requiring distributed cloud computing resources for alignment, deduplication, and peak calling on sequencing data.

---

## [763] source=multitask_sft_big

**USER:** Predict high-confidence protein-protein interaction complexes from multi-replicate SEC-MS co-fractionation data using the PrInCE pipeline benchmarked against the CORUM complex repository.

**ASSISTANT:** cloud_workflow: PrInCE is an intensive multi-step bioinformatics pipeline involving chromatogram smoothing, metric feature engineering, machine learning classification, and cross-validation across co-fractionation replicates.

---

## [764] source=multitask_sft_big

**USER:** Annotate functional genetic consequences and amino acid changes for variants in a human WGS VCF file against the GRCh38 genome build using SnpEff.

**ASSISTANT:** cloud_workflow: Running SnpEff variant annotation requires executing a resource-intensive bioinformatics pipeline with reference genome databases on cloud compute infrastructure.

---

## [765] source=multitask_sft_big

**USER:** Genotype known polymorphic inversions across my cohort of whole-genome sequencing VCF files using reference inversion haplotype scores.

**ASSISTANT:** cloud_workflow: Scoring and calling structural inversions across genomic cohorts requires multi-step data processing and computationally intensive bioinformatics pipeline execution.

---

## [766] source=multitask_sft_big

**USER:** Identify differentially edited RNA regions between tumor and normal RNA-seq samples from an RNA editing proportion matrix using rnaeditr.

**ASSISTANT:** cloud_workflow: Analyzing differential RNA editing across transcriptomic regions requires running a multi-step Bioconductor pipeline with statistical modeling on cloud compute resources.

---

## [767] source=multitask_sft_big

**USER:** Dock candidate small molecule CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C into the active site of ABL kinase using DiffDock to predict its 3D binding pose.

**ASSISTANT:** cloud_models: DiffDock relies on a deep diffusion generative model requiring GPU acceleration to sample and score small-molecule docking poses against a target structure.

---

## [768] source=multitask_sft_big

**USER:** Run quality assessment and outlier detection across 40 bulk RNA-seq tumor and normal tissue samples to identify potential batch effects and low-integrity profiles.

**ASSISTANT:** cloud_workflow: Quality control, batch diagnostics, and outlier screening across multi-sample transcriptomic datasets require multi-step pipeline processing on cloud infrastructure.

---

## [769] source=multitask_sft_big

**USER:** Analyze single-cell RNA-seq count data using the APL workflow to generate association plots and identify cluster-specific marker genes.

**ASSISTANT:** cloud_workflow: Executing end-to-end transcriptomic analysis pipelines requires coordinated multi-step processing and scalable high-performance compute resources.

---

## [770] source=multitask_sft_big

**USER:** Identify, quantify, and generate visualization plots for telomeric repeat motifs across chromosomes in my newly assembled eukaryotic genome FASTA file.

**ASSISTANT:** cloud_workflow: This task involves executing a multi-step Nextflow pipeline requiring containerized bioinformatics tools and compute resources to search and visualize telomeric repeats across genome assemblies.

---

## [771] source=multitask_sft_big

**USER:** Run the GmicR workflow on paired host RNA-seq and microbial abundance profiles to infer gene-microbe correlation networks and identify key transcriptomic drivers of host-microbiome interactions.

**ASSISTANT:** cloud_workflow: GmicR performs multi-step statistical integration and network inference on transcriptomic data that requires cloud infrastructure and workflow orchestration.

---

## [772] source=multitask_sft_big

**USER:** Analyze repeat-masked intervals in the human genome (hg38) using Bioconductor's BSgenome package to extract unmasked promoter sequences and calculate their GC content.

**ASSISTANT:** instant_compute: This task involves running lightweight R/Bioconductor sequence inspection and frequency calculations that execute within minutes in an interactive compute environment.

---

## [773] source=multitask_sft_big

**USER:** Calculate genome-wide single-base-level F-statistics on RNA-seq coverage matrices to identify differentially expressed regions between experimental conditions.

**ASSISTANT:** cloud_workflow: Computing base-resolution F-statistics across genome-wide RNA-seq coverage tracks requires high-memory, multi-threaded cloud bioinformatics infrastructure.

---

## [774] source=multitask_sft_big

**USER:** Execute a GATK Best Practices germline variant calling pipeline on whole-genome sequencing FASTQ files stored in an Azure Blob container via AnVIL.

**ASSISTANT:** cloud_workflow: Running distributed genomic pipelines across large cloud-hosted sequencing datasets requires asynchronous batch workflow orchestration on cloud infrastructure.

---

## [775] source=multitask_sft_big

**USER:** Calculate comprehensive quality control metrics and generate diagnostic summary plots from MaxQuant search outputs for 24 LC-MS/MS proteomic runs to evaluate digestion efficiency, peak shapes, and identification consistency.

**ASSISTANT:** cloud_workflow: Analyzing multi-run mass spectrometry data to generate multi-parametric QC reports requires standardized bioinformatics pipeline execution on cloud computing infrastructure.

---

## [776] source=multitask_sft_big

**USER:** Cluster and generate advanced hierarchical grouped layout visualizations for a set of RNA-binding protein motif position weight matrices derived from transcriptomic data.

**ASSISTANT:** cloud_workflow: This task runs an intensive multi-step R/Bioconductor motifStack pipeline requiring motif alignment, distance calculation, and complex vector plot generation on cloud infrastructure.

---

## [777] source=multitask_sft_big

**USER:** Cluster a collection of novel transcription factor binding motifs derived from ChIP-seq peaks alongside reference JASPAR motifs, and generate a stacked sequence logo phylogenetic tree to assess motif similarity.

**ASSISTANT:** cloud_workflow: Executing the motifStack pipeline requires running specialized Bioconductor R algorithms and file parsers to perform hierarchical clustering and generate high-resolution stacked motif visualizations in an automated cloud workflow.

---

## [778] source=multitask_sft_big

**USER:** Process raw paired-end 16S rRNA amplicon FASTQ reads to cluster sequences into operational taxonomic units (OTUs) at 97% identity, remove chimeras, and generate a taxonomically classified OTU abundance table.

**ASSISTANT:** cloud_workflow: Processing large-scale amplicon sequencing data through multi-step quality filtering, clustering, and taxonomic assignment requires distributed high-performance cloud workflow orchestration.

---

## [779] source=multitask_sft_big

**USER:** Generate an NCBI GEO submission package including MD5 checksums, processed expression matrices, and completed metadata templates for my 24-sample RNA-seq experiment.

**ASSISTANT:** cloud_workflow: Generating MD5 checksums and staging large multi-sample sequencing files alongside processed matrices requires long-running, I/O-intensive batch execution on cloud infrastructure.

---

## [780] source=multitask_sft_big

**USER:** Run a goodness-of-fit test on my RNA-seq expression matrix using the globaltest package to determine if our clinical covariate model sufficiently captures variation across KEGG immune pathways.

**ASSISTANT:** cloud_workflow: Executing globaltest goodness-of-fit evaluations on high-dimensional transcriptomic data requires running multi-step statistical R/Bioconductor analyses within a cloud compute environment.

---

## [781] source=multitask_sft_big

**USER:** Infer a condition-specific gene regulatory network using pandaR by integrating tumor RNA-seq expression data with transcription factor sequence motif priors and protein-protein interactions.

**ASSISTANT:** cloud_workflow: Running PANDA involves iterative message-passing across genome-scale network matrices integrating transcriptomics, PPI, and motif data, requiring scalable cloud compute and memory resources.

---

## [782] source=multitask_sft_big

**USER:** Run a customized step-by-step DNA methylation analysis on Illumina Infinium EPIC array IDAT files, covering data import, quality control, normalization, and differential methylation testing across sample groups.

**ASSISTANT:** cloud_workflow: Executing an RnBeads tailored analysis requires running a heavy, multi-step bioinformatics pipeline on large-scale genomic methylation data that exceeds instant compute capacity.

---

## [783] source=multitask_sft_big

**USER:** Assess the stability and sensitivity of differential expression calls from my RNA-seq count matrix by running an ALDEx2 sensitivity analysis across different scale-simulation parameters and Dirichlet Monte Carlo samplings.

**ASSISTANT:** cloud_workflow: ALDEx2 sensitivity analysis involves computationally intensive Monte Carlo Dirichlet sampling and iterative statistical testing across high-dimensional count matrices, requiring distributed cloud pipeline execution.

---

## [784] source=multitask_sft_big

**USER:** Generate aesthetic color schemes and transform genomic range coordinates into ideogram layouts for transcript visualization using biovizBase in R.

**ASSISTANT:** instant_compute: biovizBase provides lightweight R utility functions and coordinate transformations for genomic data plotting that execute rapidly in an interactive compute session.

---

## [785] source=multitask_sft_big

**USER:** Cluster single-cell spatial phenotypes from multiplexed imaging mass cytometry (IMC) data across 35 marker channels using the FuseSOM pipeline.

**ASSISTANT:** cloud_workflow: FuseSOM performs compute- and memory-intensive self-organizing map clustering and integration on high-dimensional spatial single-cell data, requiring cloud-based workflow infrastructure.

---

## [786] source=multitask_sft_big

**USER:** Detect and quantify kataegis foci from whole-genome somatic VCF files of tumor samples using katdetectr.

**ASSISTANT:** cloud_workflow: Processing large-scale somatic variant call sets to identify genomic hypermutation clusters requires pipeline orchestration and significant compute resources best suited for a cloud workflow.

---

## [787] source=multitask_sft_big

**USER:** Identify differentially expressed genes between disease and control samples from microarray expression data using linear modeling and empirical Bayes statistics.

**ASSISTANT:** cloud_workflow: Differential gene expression analysis with limma involves multi-step matrix normalization, contrast fitting, and statistical moderation executed as a containerized bioinformatics pipeline.

---

## [788] source=multitask_sft_big

**USER:** Annotate peak regions from a PAR-CLIP experiment to analyze binding distributions across transcript features and identify enriched RNA motifs.

**ASSISTANT:** cloud_workflow: RCAS is a multi-step transcriptome annotation pipeline that requires reference genomic data and significant computational processing suited for distributed cloud workflow execution.

---

## [789] source=multitask_sft_big

**USER:** Process raw paired-end RNA-seq FASTQ files to perform read alignment, transcript quantification, and generate gene-level count matrices.

**ASSISTANT:** cloud_workflow: Full RNA-seq data processing pipelines involve compute- and storage-intensive workflow orchestration suitable for cloud execution.

---

## [790] source=multitask_sft_big

**USER:** Align chromatographic peaks and group metabolomic features across untargeted LC-MS mzML sample runs using XCMS parameters optimized for high-resolution data.

**ASSISTANT:** cloud_workflow: XCMS feature grouping across multi-file raw metabolomics datasets is a computationally heavy, long-running bioinformatics processing pipeline executed on cloud infrastructure.

---

## [791] source=multitask_sft_big

**USER:** Process paired-end FASTQ reads from a deep mutational scanning library targeting the SARS-CoV-2 receptor-binding domain to quantify amino acid variant abundance and calculate fitness enrichment scores across selection rounds.

**ASSISTANT:** cloud_workflow: As an nf-core Nextflow pipeline, deepmutscan requires orchestrating multi-step alignment, variant quantification, and scoring workloads across high-throughput sequencing data on cloud or HPC infrastructure.

---

## [792] source=multitask_sft_big

**USER:** Identify subclonal tumor cell populations and cell-to-cell heterogeneity from a single-cell RNA-seq count matrix using ccfindr.

**ASSISTANT:** cloud_workflow: Running ccfindr on single-cell transcriptomic matrices involves computationally intensive Bayesian non-negative matrix factorization and clustering that require cloud-based batch processing.

---

## [793] source=multitask_sft_big

**USER:** Identify homologs and functional annotations for an uncharacterized Streptomyces protein sequence by querying the NCBI non-redundant protein database using BLASTp.

**ASSISTANT:** cloud_workflow: Executing sequence homology searches against large reference databases requires asynchronous orchestration of bioinformatics database query jobs.

---

## [794] source=multitask_sft_big

**USER:** Import a CSV table of differential gene expression results (log2 fold changes and p-values) as node attributes into an active Cytoscape network using RCy3.

**ASSISTANT:** instant_compute: Mapping tabular annotations onto network nodes via RCy3 is a lightweight, deterministic R execution task that completes in seconds without distributed cloud resources.

---

## [795] source=multitask_sft_big

**USER:** Perform covariate-aware batch effect correction on our multi-batch scRNA-seq expression matrix while preserving biological variation across treatment conditions.

**ASSISTANT:** cloud_workflow: Batch correction on high-dimensional transcriptomics matrices involves multi-step data transformation and intensive pipeline execution best suited for cloud workflow infrastructure.

---

## [796] source=multitask_sft_big

**USER:** Run a CEMiTool diagnostic analysis on my normalized bulk RNA-seq expression matrix and sample metadata to evaluate soft-thresholding beta power selection and troubleshoot poor module detection.

**ASSISTANT:** cloud_workflow: Executing CEMiTool modular co-expression diagnostics and parameter tuning on full transcriptomic datasets requires cloud-based computational pipeline infrastructure.

---

## [797] source=multitask_sft_big

**USER:** Detect large-scale differentially methylated blocks across whole-genome bisulfite sequencing (WGBS) profiles comparing colorectal cancer tumor biopsies to matched normal mucosal tissues.

**ASSISTANT:** cloud_workflow: Genome-wide block detection using dmrseq across multi-sample WGBS datasets requires high-memory statistical smoothing and permutation testing that exceeds local resources and must run as an asynchronous cloud pipeline.

---

## [798] source=multitask_sft_big

**USER:** Process multi-channel fluorescence microscopy images to filter and quantify cyanobacteria cells in environmental water samples.

**ASSISTANT:** cloud_workflow: High-throughput microscopy image segmentation and autofluorescence filtering require asynchronous, computationally intensive pipeline processing in the cloud.

---

## [799] source=multitask_sft_big

**USER:** Design degenerate RT-qPCR primers and hydrolysis probes targeting conserved genomic regions across a multiple sequence alignment of 250 dengue virus isolates.

**ASSISTANT:** cloud_workflow: Screening and optimizing degenerate primer-probe combinations from multi-sequence alignments involves a multi-step sequence conservation and thermodynamic scoring pipeline best executed as a cloud workflow.

---

## [800] source=multitask_sft_big

**USER:** Run Bayesian co-clustering on a single-cell RNA-seq count matrix using celda to discover cell subpopulations and co-regulated gene modules.

**ASSISTANT:** cloud_workflow: Celda performs computationally intensive MCMC sampling for latent Dirichlet allocation clustering on single-cell data, requiring cloud-based workflow execution.

---

## [801] source=multitask_sft_big

**USER:** Perform locus-based gene set enrichment analysis on my H3K27ac ChIP-seq peaks using ChIP-Enrich, adjusting for gene locus length and peak proximity to TSS regulatory regions.

**ASSISTANT:** cloud_workflow: Running ChIP-Enrich on user-supplied genomic peak files requires reference genome annotations and multi-step statistical modeling executed in a cloud workflow environment.

---

## [802] source=multitask_sft_big

**USER:** Infer single-cell developmental trajectories and order differentiating neural progenitor cells along pseudotime from a normalized scRNA-seq expression matrix using TSCAN.

**ASSISTANT:** cloud_workflow: TSCAN trajectory reconstruction and pseudotime gene dynamics analysis require multi-step data processing pipelines executed on cloud compute infrastructure.

---

## [803] source=multitask_sft_big

**USER:** Perform position-dependent kernel association testing (PODKAT) to identify rare-variant associations across sliding genomic windows using cohort VCF files and a phenotype matrix.

**ASSISTANT:** cloud_workflow: Genome-wide rare variant kernel association testing on large cohort VCF files is computationally intensive and requires distributed, long-running batch processing.

---

## [804] source=multitask_sft_big

**USER:** Quantify the spatial clustering of differentially expressed genes on a human protein-protein interaction network using SANTA with 1,000 Monte Carlo permutations.

**ASSISTANT:** cloud_workflow: SANTA involves computationally intensive Monte Carlo graph-permutation tests across genome-scale interaction networks that require batch cloud workflow execution.

---

## [805] source=multitask_sft_big

**USER:** Register a custom reference transcriptome with its FASTA and GTF sources in tximeta to import Salmon quantification outputs with automatic genomic coordinate and transcript-to-gene annotations.

**ASSISTANT:** instant_compute: Registering linked transcriptomes and importing quantification files via tximeta is a lightweight Bioconductor computation that runs quickly in an interactive container without cloud workflow orchestration.

---

## [806] source=multitask_sft_big

**USER:** Run the PRONE transcriptomics pipeline on my paired-end RNA-seq FASTQ files to perform read alignment, quantification, and differential expression network analysis.

**ASSISTANT:** cloud_workflow: Multi-step transcriptomic data processing and network analysis pipelines require coordinated, long-running cloud infrastructure rather than instant execution.

---

## [807] source=multitask_sft_big

**USER:** Identify conserved active subnetwork modules by integrating cross-species RNA-seq differential expression p-values with protein-protein interaction networks using the AMOUNTAIN algorithm.

**ASSISTANT:** cloud_workflow: Extracting active functional subnetworks from biological interaction graphs and transcriptomic data requires an orchestrated multi-step cloud-based workflow for network optimization and permutation testing.

---

## [808] source=multitask_sft_big

**USER:** Map a list of human Ensembl gene IDs to their corresponding HGNC gene symbols, chromosome locations, and Entrez IDs using biomaRt.

**ASSISTANT:** instant_compute: Querying BioMart for gene identifier conversions and genomic annotations is a lightweight API/script task that completes in seconds without requiring distributed pipeline engines or heavy cloud hardware.

---

## [809] source=multitask_sft_big

**USER:** Perform multifactorial differential methylation analysis on whole-genome bisulfite sequencing data to identify DMLs and DMRs associated with disease status while adjusting for age and sex covariates using the DSS package.

**ASSISTANT:** cloud_workflow: This task requires heavy genomic data processing and statistical model fitting across large bisulfite sequencing matrices, necessitating a cloud-based multi-step bioinformatics workflow execution.

---

## [810] source=multitask_sft_big

**USER:** Run biclustering on normalized bulk RNA-seq expression data to discover co-regulated gene modules across patient subgroups.

**ASSISTANT:** cloud_workflow: Biclustering high-dimensional transcriptomic matrices involves compute-heavy pipeline execution and file-based data transformations suited for cloud workflow orchestration.

---

## [811] source=multitask_sft_big

**USER:** Perform differential expression analysis, batch-effect correction, and cell-type deconvolution on a bulk RNA-seq count matrix using tidybulk.

**ASSISTANT:** cloud_workflow: End-to-end transcriptomic pipeline execution on large count matrices requires containerized multi-step processing and dedicated compute resources.

---

## [812] source=multitask_sft_big

**USER:** Integrate H3K4me3 ChIP-seq signal and RNA-seq expression data to generate a stacked profile visualization across transcription start sites sorted by gene expression levels.

**ASSISTANT:** cloud_workflow: The epistack workflow requires high-throughput genomic data extraction across multi-gigabyte signal tracks and matrix aggregation before rendering complex integrated visualizations, necessitating cloud-based execution.

---

## [813] source=multitask_sft_big

**USER:** Run a cohort-wide gene-based rare variant burden test on whole-exome sequencing VCF files to identify candidate risk genes associated with familial cardiomyopathy using phenotype and covariate tables.

**ASSISTANT:** cloud_workflow: The nf-core/rarevariantburden pipeline is a distributed Nextflow workflow designed to execute intensive, multi-step cohort association tests requiring scalable cloud or HPC compute infrastructure.

---

## [814] source=multitask_sft_big

**USER:** Optimize the feature selection threshold and penalty parameters for an SVM classifier using repeated nested cross-validation on my normalized transcriptomic cohort data via ClassifyR.

**ASSISTANT:** cloud_workflow: Running nested cross-validation parameter sweeps across multi-omics or transcriptomic datasets is computationally intensive and requires distributed execution as a long-running cloud workflow.

---

## [815] source=multitask_sft_big

**USER:** Quantify epithelial-mesenchymal transition (EMT) pathway activity across my cohort of RNA-seq tumor samples by calculating rank-based single-sample gene set scores using singscore on a normalized expression matrix.

**ASSISTANT:** cloud_workflow: Running singscore on bulk or single-cell expression matrices requires executing containerized Bioconductor workflow pipelines on cloud compute.

---

## [816] source=multitask_sft_big

**USER:** Quantify and visualize on-target indel mutation frequencies and variant spectra from CRISPR amplicon sequencing BAM files across treated and control samples using CrispRVariants.

**ASSISTANT:** cloud_workflow: Analyzing NGS BAM alignments to characterize and plot CRISPR-induced variant frequencies involves computationally intensive data processing suitable for cloud-based bioinformatic pipelines.

---

## [817] source=multitask_sft_big

**USER:** Identify and quantify alternative polyadenylation (APA) events and calculate proximal-to-distal poly(A) site usage ratios across matched tumor and normal RNA-seq BAM files.

**ASSISTANT:** cloud_workflow: Analyzing alternative polyadenylation from aligned RNA-seq BAM files requires resource-intensive genomic data parsing and statistical modeling suitable for an automated cloud workflow.

---

## [818] source=multitask_sft_big

**USER:** Generate an overlay visualization of predicted cell nuclei segmentation masks onto raw multi-channel fluorescence microscopy images with boundary contours and custom color maps.

**ASSISTANT:** instant_compute: Rendering overlays and composite visual plots from precomputed segmentation masks and raw images is a lightweight, deterministic image-processing task that executes rapidly within an instant compute environment.

---

## [819] source=multitask_sft_big

**USER:** Perform cell-type-specific epigenome-wide association analysis on bulk DNA methylation array data to identify CpG markers associated with disease phenotypes while deconvolving cellular heterogeneity.

**ASSISTANT:** cloud_workflow: High-resolution EWAS on large DNA methylation matrices involves compute-intensive deconvolution algorithms and multi-step statistical modeling best executed on scalable cloud infrastructure.

---

## [820] source=multitask_sft_big

**USER:** Serialize a GenomicRanges object of ChIP-seq peak coordinates into an on-disk directory using the alabaster.ranges specification for lightweight data exchange.

**ASSISTANT:** instant_compute: Serializing and parsing genomic range data using the Alabaster framework is a fast, lightweight R data processing task that executes within seconds in an interactive compute container.

---

## [821] source=multitask_sft_big

**USER:** Normalize two-color cDNA microarray raw spot intensity data across print-tip groups using optimized local intensity-dependent normalization to correct for spatial and dye biases.

**ASSISTANT:** cloud_workflow: OLIN performs compute-heavy, model-based spatial and intensity-dependent normalization across high-dimensional microarray datasets that require asynchronous cloud pipeline execution.

---

## [822] source=multitask_sft_big

**USER:** Analyze my multiplexed spatial transcriptomics dataset using the Statial workflow to identify localized cell-state changes and differential marker expression associated with proximity to tumor cells.

**ASSISTANT:** cloud_workflow: Running the Statial pipeline requires multi-step spatial neighbor graph construction and cell-state modeling on large spatial transcriptomics datasets, classifying it as a cloud workflow.

---

## [823] source=multitask_sft_big

**USER:** Identify and remove doublet cells from a 10x Genomics single-cell RNA-seq count matrix to ensure clean downstream cell clustering and marker gene discovery.

**ASSISTANT:** cloud_workflow: Doublet detection on large single-cell gene expression matrices requires dedicated bioinformatics pipeline execution with significant memory and compute resources.

---

## [824] source=multitask_sft_big

**USER:** Run an OPLS-DA on my normalized LC-MS metabolomics peak table to identify differential metabolites and VIP scores separating disease and control patient cohorts.

**ASSISTANT:** cloud_workflow: This task runs an established R-based multivariate metabolomics pipeline requiring cloud infrastructure to fit supervised PLS/OPLS models and perform cross-validation.

---

## [825] source=multitask_sft_big

**USER:** Call germline and somatic single-nucleotide variants and small indels from paired-end RNA sequencing FASTQ data aligned against the GRCh38 human reference genome.

**ASSISTANT:** cloud_workflow: The process requires running a multi-step Nextflow pipeline incorporating alignment, BAM preprocessing, and GATK variant calling over large transcriptomic sequencing datasets on scalable cloud infrastructure.

---

## [826] source=multitask_sft_big

**USER:** Identify gene expression biomarkers significantly correlated with paclitaxel sensitivity across GDSC breast cancer cell lines using PharmacoGx.

**ASSISTANT:** cloud_workflow: Evaluating drug-gene associations across large pharmacogenomic matrices requires multi-step pipeline processing and statistical modeling executed on cloud compute.

---

## [827] source=multitask_sft_big

**USER:** Fit an integrative penalized regression model using graper on paired transcriptomic and epigenetic data to identify group-penalized molecular biomarkers predictive of patient drug response.

**ASSISTANT:** cloud_workflow: Fitting variational Bayes penalized regression across high-dimensional multi-omics feature matrices requires distributed batch computation and structured data pipeline execution.

---

## [828] source=multitask_sft_big

**USER:** Identify internal polyadenylation sites from our RNA-seq BAM files to analyze alternative polyadenylation across differentiated and reprogramming cell states.

**ASSISTANT:** cloud_workflow: Detecting transcriptomic polyadenylation sites requires multi-step computational pipeline execution and high-memory cloud infrastructure to process large sequencing alignments.

---

## [829] source=multitask_sft_big

**USER:** Identify differentially expressed genes and isoforms across three embryonic developmental stages from my RNA-seq expected count matrix using EBSeq.

**ASSISTANT:** cloud_workflow: Running EBSeq for empirical Bayes differential expression analysis on multi-condition RNA-seq count matrices requires batch bioinformatic pipeline execution in a scalable cloud environment.

---

## [830] source=multitask_sft_big

**USER:** Perform in silico tryptic digestion of the human tumor protein p53 sequence with up to two missed cleavages to generate peptide fragments for targeted proteomics analysis.

**ASSISTANT:** instant_compute: In silico proteolysis via cleaver is a deterministic, computationally lightweight sequence-processing operation that returns results within seconds without requiring heavy cloud infrastructure.

---

## [831] source=multitask_sft_big

**USER:** Normalize and compute gene expression estimates from Affymetrix GeneChip CEL files using the Langmuir adsorption model.

**ASSISTANT:** cloud_workflow: Processing raw microarray CEL files with the affyILM Bioconductor package requires dedicated cloud infrastructure to handle file ingestion and compute-intensive non-linear modeling.

---

## [832] source=multitask_sft_big

**USER:** Calculate growth rate inhibition metrics including GR50, GRmax, and AUC from multi-concentration cell viability assay data across treated cancer cell lines.

**ASSISTANT:** cloud_workflow: Processing high-throughput screening datasets with GRmetrics requires batch curve fitting, multi-condition parameter estimation, and report generation in a containerized pipeline environment.

---

## [833] source=multitask_sft_big

**USER:** Evaluate and compare the batch effect integration quality of Harmony and Seurat on my merged single-cell RNA-seq dataset using CellMixS metrics.

**ASSISTANT:** cloud_workflow: Benchmarking scRNA-seq integration algorithms with CellMixS requires running heavy transcriptomic evaluation pipelines on dedicated cloud compute infrastructure.

---

## [834] source=multitask_sft_big

**USER:** Perform joint spatial domain clustering across four Visium brain tissue sections using BANKSY to identify shared microenvironments across biological replicates.

**ASSISTANT:** cloud_workflow: Jointly processing and clustering multi-sample spatial transcriptomics datasets requires orchestrating multi-step preprocessing, spatial matrix calculations, and workflow execution on cloud compute infrastructure.

---

## [835] source=multitask_sft_big

**USER:** Perform reference-free cell-type deconvolution on a 10x Visium spatial transcriptomics spot count matrix using RETROFIT to estimate spot composition and cell-type specific expression profiles.

**ASSISTANT:** cloud_workflow: RETROFIT executes computationally intensive Bayesian iterative modeling on spatial transcriptomics matrices that requires asynchronous cloud compute rather than immediate interactive processing.

---

## [836] source=multitask_sft_big

**USER:** Perform statistical power estimation and sample size calculations across patient cohorts for an upcoming 40-marker CyTOF immune profiling study.

**ASSISTANT:** cloud_workflow: Simulating high-dimensional mass cytometry data and evaluating statistical power across complex marker-cell type combinations requires a distributed, multi-step computational pipeline.

---

## [837] source=multitask_sft_big

**USER:** Run PureCN on matched tumor-normal targeted sequencing BAMs and VCFs to estimate tumor purity, ploidy, and absolute copy number profiles.

**ASSISTANT:** cloud_workflow: PureCN is a multi-step cancer genomics pipeline processing large sequencing files that requires distributed cloud infrastructure and reference datasets to execute.

---

## [838] source=multitask_sft_big

**USER:** Generate a standalone publication-ready sample annotation plot using ComplexHeatmap to visualize clinical covariates like tumor grade, age, and mutation status across patient cohorts.

**ASSISTANT:** instant_compute: Rendering annotation-only heatmaps from tabular metadata relies on quick R-based visualization code that executes within an interactive sandboxed environment.

---

## [839] source=multitask_sft_big

**USER:** Run the nf-core/phaseimpute pipeline on low-coverage whole-genome sequencing BAM files to perform haplotype phasing and genotype imputation using the 1000 Genomes Project reference panel.

**ASSISTANT:** cloud_workflow: The nf-core/phaseimpute pipeline is an orchestrated Nextflow workflow designed for computationally intensive, multi-step genomic phasing and imputation across distributed cloud or HPC resources.

---

## [840] source=multitask_sft_big

**USER:** Analyze raw LC-MS/MS mzML files using the PIRAT workflow to perform peptide identification, false discovery rate filtering, and protein inference across sample replicates.

**ASSISTANT:** cloud_workflow: Running the PIRAT proteomics pipeline involves compute-intensive multi-step batch processing of mass spectrometry data that requires cloud infrastructure.

---

## [841] source=multitask_sft_big

**USER:** Screen assembled metagenomic contigs to discover and annotate biosynthetic gene clusters (BGCs), antimicrobial peptides (AMPs), and antibiotic resistance genes (ARGs).

**ASSISTANT:** cloud_workflow: nf-core/funcscan is a multi-tool Nextflow workflow designed for functional screening across large genomic and metagenomic assemblies requiring high-performance compute.

---

## [842] source=multitask_sft_big

**USER:** Identify active metabolic modules and pathway subgraphs by integrating differential RNA-seq expression data with metabolic network topologies using GATOM.

**ASSISTANT:** cloud_workflow: GATOM executes computationally intensive graph scoring and mixed-integer linear programming solvers over genome-scale metabolic networks, requiring a containerized cloud workflow environment.

---

## [843] source=multitask_sft_big

**USER:** Estimate cell-type proportions from a cohort of whole-genome bisulfite sequencing (WGBS) methylation count matrices using methylCC.

**ASSISTANT:** cloud_workflow: Processing large-scale genomic methylation matrices for reference-free cell-type deconvolution requires cloud-scale compute and batch workflow execution.

---

## [844] source=multitask_sft_big

**USER:** Quantify CD4+ T-cell infiltration, microglial activation (Iba1+), and demyelination area in spinal cord histological sections from an EAE mouse model to assess neuroinflammatory lesion severity.

**ASSISTANT:** cloud_workflow: Analyzing high-resolution histological imaging data across multiple CNS tissue sections requires a scalable, multi-step cloud-based image processing and segmentation pipeline.

---

## [845] source=multitask_sft_big

**USER:** Identify shared gene co-expression modules across my drought-stressed and control RNA-seq expression datasets using BioNERO's consensus network pipeline.

**ASSISTANT:** cloud_workflow: Detecting consensus co-expression modules across multiple transcriptomic datasets requires multi-step network construction, topological overlap calculations, and clustering that demand cloud computing resources.

---

## [846] source=multitask_sft_big

**USER:** Analyze drug combination synergy and antagonism between paclitaxel and carboplatin across ovarian cancer cell lines in a PharmacoSet, and identify transcriptomic markers correlated with synergistic response.

**ASSISTANT:** cloud_workflow: Processing high-throughput pharmacogenomic perturbation datasets and calculating dose-response synergy metrics against transcriptomic profiles requires an automated, resource-intensive cloud pipeline.

---

## [847] source=multitask_sft_big

**USER:** Classify single cells into discrete cell cycle stages (G1, S, and G2M) from an input single-cell RNA-seq expression matrix using the tricycle projection method.

**ASSISTANT:** cloud_workflow: Executing the tricycle cell cycle phase inference pipeline on scRNA-seq data requires containerized, multi-step cloud workflow execution with specialized Bioconductor dependencies.

---

## [848] source=multitask_sft_big

**USER:** Process raw LC-MS/MS mzML files using MSnbase to perform spectrum filtering, chromatographic peak extraction, and isobaric TMT reporter ion quantification across experimental batches.

**ASSISTANT:** cloud_workflow: Mass spectrometry data processing pipelines involving raw mzML parsing, retention time alignment, and quantitative matrix generation require intensive compute and I/O resources suited for cloud workflows.

---

## [849] source=multitask_sft_big

**USER:** Identify intrinsically disordered regions (IDRs) across the human alpha-synuclein sequence (UniProt: P37840) to evaluate conformational flexibility.

**ASSISTANT:** instant_compute: Protein disorder prediction from amino acid sequence uses lightweight analytical algorithms or fast sequence-based models that compute results in seconds.

---

## [850] source=multitask_sft_big

**USER:** Process raw paired-end FASTQ reads from an ATAC-seq experiment to perform quality trimming, Bowtie2 genome alignment, deduplication, and open chromatin peak calling.

**ASSISTANT:** cloud_workflow: Epigenomic high-throughput sequencing data processing involves resource-intensive multi-step bioinformatics pipelines (alignment, filtering, peak calling) requiring cloud infrastructure orchestration.

---

## [851] source=multitask_sft_big

**USER:** I have an RNA-seq gene expression matrix and sample metadata across multiple experimental batches; run BatchQC to diagnose potential batch effects, evaluate variation across conditions, and generate diagnostic QC plots.

**ASSISTANT:** cloud_workflow: Evaluating batch effects across high-throughput transcriptomic matrices requires running an orchestrated, multi-step bioinformatics pipeline in the cloud.

---

## [852] source=multitask_sft_big

**USER:** Run comprehensive quality control on a label-free proteomics intensity matrix to evaluate sample clustering, missing value patterns, and potential batch effects using MatrixQCvis.

**ASSISTANT:** cloud_workflow: MatrixQCvis operates as a multi-step bioinformatics pipeline that processes quantitative proteomics matrices and renders interactive QC diagnostic reports using cloud compute resources.

---

## [853] source=multitask_sft_big

**USER:** Train a Random Forest QSAR model using molecular fingerprints and RDKit descriptors on an EGFR bioactivity dataset to predict pIC50 values for newly proposed compounds.

**ASSISTANT:** cloud_workflow: Building and validating a Random Forest QSAR model involves a multi-step tabular ML pipeline including batch descriptor calculation, cross-validation, and performance evaluation executed in the cloud.

---

## [854] source=multitask_sft_big

**USER:** Predict Phase I and Phase II human metabolites for the small-molecule inhibitor dasatinib using BioTransformer to identify potential clearance pathways.

**ASSISTANT:** cloud_workflow: Simulating enzymatic metabolic biotransformations through BioTransformer requires executing a multi-step external bioinformatic processing pipeline in the cloud.

---

## [855] source=multitask_sft_big

**USER:** Deconvolve cell type proportions across spatial transcriptomics spots in a 10x Visium dataset using a matched scRNA-seq reference through the SPOTlight two-step workflow.

**ASSISTANT:** cloud_workflow: SPOTlight spatial deconvolution is a resource-intensive, multi-step transcriptomic pipeline requiring non-negative matrix factorization and marker regression executed on cloud computing infrastructure.

---

## [856] source=multitask_sft_big

**USER:** Analyze raw paired-end RNA-seq data from SARS-CoV-2 infected host tissue samples to quantify viral read coverage and identify differentially expressed host response genes.

**ASSISTANT:** cloud_workflow: The covrna workflow requires multi-step sequence alignment, coverage profiling, and differential expression analysis on high-throughput sequencing datasets, necessitating distributed cloud compute.

---

## [857] source=multitask_sft_big

**USER:** Apply a phylogenetic isometric log-ratio transformation to an ASV abundance table and associated phylogenetic tree to conduct compositional microbiome balance analysis.

**ASSISTANT:** cloud_workflow: This task involves executing a containerized metagenomic processing pipeline on cloud compute to handle data transformation and phylogenetic balance calculations across large microbiome datasets.

---

## [858] source=multitask_sft_big

**USER:** Calculate transcription factor binding affinity scores across target promoter sequences using position frequency matrices with MatrixRider.

**ASSISTANT:** cloud_workflow: MatrixRider is an R/Bioconductor data analysis tool requiring containerized, multi-step pipeline processing on input sequence and matrix files.

---

## [859] source=multitask_sft_big

**USER:** Download and parse the expression matrix and clinical metadata for accession GSE42872 to inspect sample annotations and gene expression levels.

**ASSISTANT:** instant_compute: Retrieving and parsing GEO series matrix files via GEOquery is a lightweight, interactive compute task that completes quickly without requiring distributed cloud pipeline orchestration.

---

## [860] source=multitask_sft_big

**USER:** Run gene set enrichment analysis on my DESeq2 differential expression gene list against the MSigDB Hallmark gene sets to identify significantly enriched pathways.

**ASSISTANT:** cloud_workflow: Executing fgsea on transcriptomic gene lists with reference gene set collections requires a cloud-orchestrated bioinformatics data-processing pipeline.

---

## [861] source=multitask_sft_big

**USER:** Generate error-corrected consensus reads from paired-end FASTQ files with unique molecular identifiers (UMIs) using fgbio for low-frequency variant detection.

**ASSISTANT:** cloud_workflow: Generating consensus reads from raw sequencing data with fgbio involves multi-step, computationally intensive alignment, grouping, and consensus filtering tasks that require scalable cloud workflow execution.

---

## [862] source=multitask_sft_big

**USER:** Normalize a single-cell RNA sequencing raw count matrix and detect differentially expressed genes across conditions using Linnorm.

**ASSISTANT:** cloud_workflow: Linnorm executes an intensive statistical normalization and differential expression pipeline on transcriptomic count datasets that requires cloud-based bioinformatic processing.

---

## [863] source=multitask_sft_big

**USER:** Evaluate cross-species concordance of differential gene expression profiles between human patient tumor data and a corresponding mouse disease model using the AGDEX package.

**ASSISTANT:** cloud_workflow: AGDEX requires multi-dataset processing, comparative differential expression profiling, and computationally intensive permutation testing suited for distributed cloud workflow execution.

---

## [864] source=multitask_sft_big

**USER:** Align and average 2,500 picked macromolecular subvolumes from reconstructed cryo-electron tomograms to determine a high-resolution 3D consensus density map.

**ASSISTANT:** cloud_workflow: Subtomogram averaging is a multi-step, computationally intensive image-processing pipeline requiring distributed GPU cluster resources for iterative 3D alignment, classification, and reconstruction.

---

## [865] source=multitask_sft_big

**USER:** Analyze whole-genome sequencing BAM files of circulating cell-free DNA (cfDNA) to profile fragment size distributions and genomic end motifs for cancer liquid biopsy monitoring.

**ASSISTANT:** cloud_workflow: Processing large-scale cfDNA sequencing files through multi-step fragmentomic and quality control pipelines requires scalable cloud compute resources.

---

## [866] source=multitask_sft_big

**USER:** Normalize dual-channel array CGH intensity datasets from tumor samples to eliminate dye and spatial biases and segment copy number alterations using CGHnormaliter.

**ASSISTANT:** cloud_workflow: This task entails executing a multi-step genomic data processing pipeline over raw microarray files using the CGHnormaliter R/Bioconductor package on cloud compute resources.

---

## [867] source=multitask_sft_big

**USER:** Simulate the sensitivity of differentially expressed genes to scale uncertainty in my RNA-seq count matrix by running ALDEx2 scale simulation across Dirichlet Monte Carlo samples.

**ASSISTANT:** cloud_workflow: Running ALDEx2 scale simulations requires executing a multi-step, computationally intensive R/Bioconductor differential expression workflow on high-dimensional count data.

---

## [868] source=multitask_sft_big

**USER:** Perform automated multivariate outlier detection on a batch of raw Affymetrix microarray CEL files from a clinical transcriptomics study to flag substandard arrays before downstream normalization.

**ASSISTANT:** cloud_workflow: Screening large batches of expression microarrays for quality control requires running an R/Bioconductor pipeline on cloud infrastructure with multi-file input processing.

---

## [869] source=multitask_sft_big

**USER:** Integrate matched RNA-seq, DNA methylation, and miRNA profiling data from our cancer cohort using Affinity Network Fusion (ANF) to discover consensus patient clusters and correlate them with survival outcomes.

**ASSISTANT:** cloud_workflow: Fusing multi-view biological network matrices across patient cohorts and executing downstream spectral clustering and survival evaluation requires an orchestrated bioinformatics pipeline on cloud infrastructure.

---

## [870] source=multitask_sft_big

**USER:** Upload three gene lists of differentially expressed transcripts to generate an annotated VennDetail diagram and extract overlapping subset tables.

**ASSISTANT:** cloud_workflow: The VennDetail workflow requires asynchronous cloud execution to process multi-set genomic lists, compute intersection subsets, and generate high-resolution visualization artifacts.

---

## [871] source=multitask_sft_big

**USER:** Annotate the variant rs121913529 (BRAF V600E) with ClinVar clinical significance, gnomAD allele frequencies, and CADD pathogenicity scores using MyVariant.info.

**ASSISTANT:** instant_compute: Retrieving variant annotations via the MyVariant.info REST API is a lightweight query that executes in seconds within an interactive runtime environment.

---

## [872] source=multitask_sft_big

**USER:** Scatter a whole-genome BED file into balanced genomic intervals and run parallel bedtools intersect against targeted variant call sets.

**ASSISTANT:** cloud_workflow: Partitioning large genomic coordinate files and orchestrating parallelized bedtools tasks across compute nodes requires cloud pipeline execution.

---

## [873] source=multitask_sft_big

**USER:** Identify an optimal subset of prognostic gene expression biomarkers from high-dimensional RNA-seq count matrices using genetic algorithm-based feature selection.

**ASSISTANT:** cloud_workflow: Iterative genetic algorithm feature selection over large transcriptomic expression profiles is computationally intensive and requires multi-step cloud workflow execution.

---

## [874] source=multitask_sft_big

**USER:** Analyze and plot the distribution of specific oligonucleotide sequence motifs across a set of promoter sequences.

**ASSISTANT:** instant_compute: Scanning oligonucleotide patterns and generating motif frequency plots across input sequences is a lightweight task that runs quickly within an interactive container environment.

---

## [875] source=multitask_sft_big

**USER:** I have a set of homologous gene family sequences across multiple vertebrate species in FASTA format and want to run the nf-core/multiplesequencealign pipeline using MAFFT and T-Coffee to generate and benchmark multiple sequence alignments.

**ASSISTANT:** cloud_workflow: nf-core/multiplesequencealign is a Nextflow batch workflow that requires orchestrating containerized multiple alignment and evaluation tools across distributed cloud compute resources.

---

## [876] source=multitask_sft_big

**USER:** Calculate a patient's 10-year absolute risk of breast cancer by integrating their polygenic risk score (PRS) with clinical and epidemiological risk factor data using the iCARE tool.

**ASSISTANT:** instant_compute: Estimating absolute disease risk from summary risk coefficients and genomic risk factor profiles via the iCARE package is a fast statistical calculation executable within seconds.

---

## [877] source=multitask_sft_big

**USER:** Profile eCLIP read density and binding enrichment around custom transcriptomic window intervals flanking alternative 3' splice sites.

**ASSISTANT:** cloud_workflow: Processing high-throughput sequencing alignment files and aggregating signal over thousands of custom genomic windows requires distributed cloud compute workflow execution.

---

## [878] source=multitask_sft_big

**USER:** Identify differentially abundant cell populations in CyTOF mass cytometry cohorts across clinical conditions using hypersphere assignment and negative binomial GLMs.

**ASSISTANT:** cloud_workflow: Cydar executes a multi-step high-dimensional cytometry analysis pipeline requiring scalable compute for spatial hypersphere cell allocation, count aggregation, and differential statistical modeling across multi-sample cohorts.

---

## [879] source=multitask_sft_big

**USER:** Estimate continuous cell-cycle position and infer cell-cycle stages for my single-cell RNA-seq dataset of cortical neural progenitors using tricycle reference projections.

**ASSISTANT:** cloud_workflow: Projecting single-cell expression matrices onto continuous cell-cycle reference spaces requires batch bioinformatics pipeline execution on cloud infrastructure.

---

## [880] source=multitask_sft_big

**USER:** Run a Bayesian knockdown analysis on a normalized microarray ExpressionSet to estimate regulatory relationships and identify potential target genes downstream of a knocked-down transcription factor.

**ASSISTANT:** cloud_workflow: Executing Bayesian knockdown models on transcriptomic ExpressionSet objects requires running an asynchronous cloud bioinformatics workflow with specialized Bioconductor packages.

---

## [881] source=multitask_sft_big

**USER:** Segment and count individual bacterial cells from a batch of fluorescence microscopy images to quantify cell morphology and population density.

**ASSISTANT:** cloud_models: Deep learning-based cell segmentation relies on GPU-accelerated neural network inference to process microscopy image datasets.

---

## [882] source=multitask_sft_big

**USER:** Perform de novo hybrid assembly and functional annotation on paired-end Illumina and Oxford Nanopore FASTQ sequencing data for a novel bacterial isolate.

**ASSISTANT:** cloud_workflow: Genome assembly and annotation pipelines involve multi-tool, high-throughput computational steps that require orchestrated distributed cloud computing resources.

---

## [883] source=multitask_sft_big

**USER:** Process 24 raw LC-MS/MS DIA data files to identify and quantify synaptic proteome alterations between control and Alzheimer's disease mouse models.

**ASSISTANT:** cloud_workflow: Multi-sample mass spectrometry raw file processing, peptide identification, and quantitative statistical testing require distributed, long-running pipeline execution.

---

## [884] source=multitask_sft_big

**USER:** Normalize an isobaric or label-free proteomics intensity matrix across samples using Mean-Balanced Quantile Normalization (MBQN) to adjust for asymmetric batch effects.

**ASSISTANT:** instant_compute: MBQN executes deterministic statistical matrix normalization on tabular expression data that completes quickly without requiring distributed cloud pipelines or GPU acceleration.

---

## [885] source=multitask_sft_big

**USER:** Download paired-end FASTQ read files for SRA accessions SRR12345678 and SRR12345679 using SRA-Tools prefetch and fasterq-dump.

**ASSISTANT:** cloud_workflow: Retrieving and extracting high-throughput SRA sequencing data requires distributed network I/O, substantial storage, and long-running asynchronous batch pipeline execution.

---

## [886] source=multitask_sft_big

**USER:** Align and overlay high-resolution H&E histology images with Visium spot-level spatial transcriptomics data to visualize tumor marker expression patterns across tissue sections.

**ASSISTANT:** cloud_workflow: Processing large pathology slide images alongside spatial transcriptomics coordinate matrices requires a multi-step, computationally intensive cloud pipeline.

---

## [887] source=multitask_sft_big

**USER:** Process 1D 1H-NMR raw spectra from our cohort study using the alpsNMR pipeline to perform baseline correction, peak detection, alignment across samples, and metabolite feature quantification.

**ASSISTANT:** cloud_workflow: Executing end-to-end NMR spectra processing with alpsNMR involves multi-step data-intensive signal processing and peak quantification that requires a cloud execution pipeline.

---

## [888] source=multitask_sft_big

**USER:** Analyze raw 4C-seq alignment data around a targeted promoter viewpoint using Basic4Cseq to filter non-informative ligation fragments, normalize interaction frequencies, and visualize local chromatin looping profiles.

**ASSISTANT:** cloud_workflow: Processing high-throughput genomic BAM alignment files through fragment filtering, statistical normalization, and interaction calling requires cloud pipeline execution infrastructure.

---

## [889] source=multitask_sft_big

**USER:** Fit a modified Gompertz model to optical density (OD600) time-series data from an engineered bacterial culture to estimate lag time, maximum specific growth rate, and carrying capacity.

**ASSISTANT:** instant_compute: Fitting a mathematical Gompertz growth equation to numerical time-series data is a deterministic regression task that completes within seconds using standard scientific computing libraries.

---

## [890] source=multitask_sft_big

**USER:** Classify my bulk RNA-seq tumor expression matrix against TCGA reference cohorts to identify primary cancer types and molecular subtypes.

**ASSISTANT:** cloud_workflow: Executing sampleclassifier requires automated, multi-step cloud infrastructure to perform heavy data normalization, feature selection, and machine learning inference across large transcriptomic datasets.

---

## [891] source=multitask_sft_big

**USER:** Identify combinatorial chromatin states and differential enrichment patterns across multiple histone ChIP-seq datasets (e.g., H3K4me3, H3K27ac, H3K27me3) between two biological conditions using chromstaR.

**ASSISTANT:** cloud_workflow: Combinatorial chromatin state discovery requires multi-step processing of large BAM alignment files and computationally intensive hidden Markov modeling across whole genomes.

---

## [892] source=multitask_sft_big

**USER:** Generate a custom TxDb annotation database from an Ensembl GTF file and reference genome assembly for transcript-level genomic feature analysis.

**ASSISTANT:** cloud_workflow: Parsing full-genome GTF/GFF files and compiling structured SQLite transcript databases is a resource-intensive data processing task suited for cloud workflow execution.

---

## [893] source=multitask_sft_big

**USER:** Analyze matched polysome-bound and total RNA-seq count data across treated and control conditions to identify changes in translation efficiency and uncouple translational regulation from transcriptional abundance using anota2seq.

**ASSISTANT:** cloud_workflow: The anota2seq pipeline requires multi-step statistical modeling via ANCOVA on paired transcriptomic count matrices, requiring a cloud workflow execution environment for bioinformatics data processing.

---

## [894] source=multitask_sft_big

**USER:** Validate the structural integrity, voxel dimensions, and affine orientation of an uploaded T1-weighted NIfTI volume (sub-01_T1w.nii.gz) prior to running a neuroimaging pipeline.

**ASSISTANT:** cloud_workflow: Verifying large neuroimaging datasets requires executing server-side file inspection and quality-check tools within a dedicated workflow environment.

---

## [895] source=multitask_sft_big

**USER:** Call high-resolution nucleosome positions and calculate occupancy from paired-end MNase-seq BAM files across promoter regions using the RJMCMC nucleosomes algorithm.

**ASSISTANT:** cloud_workflow: Nucleosome positioning via Reversible Jump Markov Chain Monte Carlo on sequencing alignment data requires a compute-intensive batch processing workflow executed in the cloud.

---

## [896] source=multitask_sft_big

**USER:** Segment genomic array-CGH profiles and detect chromosomal breakpoints to identify copy number gains and losses across patient tumor samples using the GLAD algorithm.

**ASSISTANT:** cloud_workflow: Genome-wide copy number segmentation across multiple high-resolution genomic profiles requires intensive computation and pipeline execution in a cloud environment.

---

## [897] source=multitask_sft_big

**USER:** Detect potential sample swaps and verify sample identity across matched Illumina EPIC methylation arrays and SNP genotyping data using omicsprint.

**ASSISTANT:** cloud_workflow: Running omicsprint across large multi-omics cohorts requires distributed compute and genomic workflow orchestration to process array data and call sample identities.

---

## [898] source=multitask_sft_big

**USER:** Preprocess and perform quality control on my annotated single-cell RNA-seq count matrix to construct a formatted reference tree for cell type annotation using CHETAH.

**ASSISTANT:** cloud_workflow: Preparing and performing QC on single-cell transcriptomic reference datasets involves intensive multi-step matrix operations and hierarchical structuring that require asynchronous cloud pipeline execution.

---

## [899] source=multitask_sft_big

**USER:** Design potent and specific siRNA candidates targeting human STAT3 mRNA, complete with thermodynamic profiling, off-target transcriptome filtering, and chemical modification patterns.

**ASSISTANT:** cloud_workflow: Comprehensive siRNA design is a multi-step bioinformatics pipeline combining motif scoring, secondary structure predictions, and genome-wide off-target alignment searches that require cloud workflow execution.

---

## [900] source=multitask_sft_big

**USER:** Identify genome-wide nucleolus-associated domains (NADs) from NAD-seq paired-end BAM files compared against genomic background controls.

**ASSISTANT:** cloud_workflow: Detecting nucleolus-associated domains from high-throughput sequencing datasets requires intensive domain-calling algorithms and file processing best suited for a distributed cloud workflow.

---

## [901] source=multitask_sft_big

**USER:** Quantify targeted cell lineage barcodes and generate count tables from raw paired-end FASTQ files across multiplexed clonal tracking samples.

**ASSISTANT:** cloud_workflow: Processing raw high-throughput sequencing files to align and count molecular barcodes requires distributed batch compute and automated pipeline orchestration.

---

## [902] source=multitask_sft_big

**USER:** Identify perturbed signaling pathways and topologically altered sub-networks from our comparative RNA-seq expression dataset using the Graphite and Clipper algorithms.

**ASSISTANT:** cloud_workflow: Topological pathway enrichment analysis across complex biological networks requires running multi-step computational pipelines in a cloud execution environment.

---

## [903] source=multitask_sft_big

**USER:** Convert aligned TAPS sequencing BAM files to accurately identify 5mC and 5hmC DNA methylation modifications across genomic samples.

**ASSISTANT:** cloud_workflow: This is an end-to-end nf-core bioinformatics pipeline requiring distributed cloud workflow orchestration to process large sequencing BAM files.

---

## [904] source=multitask_sft_big

**USER:** Intersect my ChIP-seq peak file with annotated promoter regions to find significant genomic overlaps and associated target genes.

**ASSISTANT:** cloud_workflow: Genomic region intersection requires batch processing of high-throughput coordinate files (such as BED or GFF) using command-line bioinformatics tools executed in a cloud pipeline.

---

## [905] source=multitask_sft_big

**USER:** Generate an interactive UMAP and marker gene expression dashboard from my processed 10x Genomics single-cell RNA-seq AnnData object.

**ASSISTANT:** cloud_workflow: Generating full-scale single-cell visualization suites and interactive dashboards from large matrix objects requires asynchronous pipeline execution in the cloud.

---

## [906] source=multitask_sft_big

**USER:** Identify structural outliers and cluster heterogeneous disease samples by running the TTMap algorithm on normalized RNA-seq gene expression matrices against baseline controls.

**ASSISTANT:** cloud_workflow: TTMap requires multi-step high-throughput transcriptomic processing and topological mapping that executes as a containerized cloud bioinformatics workflow.

---

## [907] source=multitask_sft_big

**USER:** Demultiplex our cell hashing single-cell RNA-seq dataset by classifying cell barcodes into donor sample singlets, doublets, and negative droplets using demuxmix on the raw HTO count matrix.

**ASSISTANT:** cloud_workflow: Demuxmix is a bioinformatics pipeline workflow that processes large single-cell sequencing count matrices and requires cloud computational resources.

---

## [908] source=multitask_sft_big

**USER:** Analyze shallow whole-genome sequencing BAM files from plasma cell-free DNA samples using cfdnakit to profile copy number alterations and estimate circulating tumor DNA fraction.

**ASSISTANT:** cloud_workflow: Executing cfDNA copy-number and tumor-fraction analysis across sequencing BAM files requires multi-step computational pipeline orchestration and distributed cloud resources.

---

## [909] source=multitask_sft_big

**USER:** Simulate exposure-response relationships and generate a Phase 2 dose selection justification report for our oncology candidate using Phase 1 pharmacokinetic and receptor occupancy data.

**ASSISTANT:** cloud_workflow: Dose justification involves an orchestrated multi-step pharmacometric pipeline combining data aggregation, population PK/PD simulation, and regulatory documentation.

---

## [910] source=multitask_sft_big

**USER:** Evaluate the assembly metrics, contamination levels, and gene completeness of my newly assembled fungal genome FASTA using nf-core/genomeqc.

**ASSISTANT:** cloud_workflow: nf-core/genomeqc is a multi-tool Nextflow pipeline that orchestrates high-throughput genomic quality control benchmarks requiring distributed cloud or cluster compute resources.

---

## [911] source=multitask_sft_big

**USER:** Perform Savitzky-Golay smoothing and peak picking on an experimental tandem mass spectrum intensity array to extract centroided m/z peaks.

**ASSISTANT:** instant_compute: MsCoreUtils provides low-level, vectorized spectral processing and mathematical functions that execute within seconds in an interactive compute environment.

---

## [912] source=multitask_sft_big

**USER:** Add newly assembled bacterial isolate FASTA files to a custom Kraken2 library and build the index for metagenomic taxonomic classification.

**ASSISTANT:** cloud_workflow: Building and indexing a custom Kraken2 k-mer database requires substantial RAM, storage, and processing time that necessitate dedicated cloud infrastructure.

---

## [913] source=multitask_sft_big

**USER:** Overlay RNA-seq differential gene expression log2 fold-change values onto the Escher central carbon metabolism pathway map for E. coli.

**ASSISTANT:** instant_compute: Mapping expression values onto a predefined metabolic pathway map is a lightweight, deterministic data-formatting and visualization process that completes in seconds.

---

## [914] source=multitask_sft_big

**USER:** Calculate regional principal components across genomic tiling windows from cohort-level Illumina EPIC DNA methylation beta-value matrices to capture local epigenetic variation for downstream EWAS covariate adjustment.

**ASSISTANT:** cloud_workflow: Computing windowed regional principal components across large-scale methylation arrays requires multi-step data chunking, dimensionality reduction, and cloud batch processing resources.

---

## [915] source=multitask_sft_big

**USER:** Analyze time-series transcriptomic profiling data paired with real-time cell monitoring to identify dynamically regulated genes across multiple exposure intervals.

**ASSISTANT:** cloud_workflow: Processing multi-sample longitudinal transcriptomic data requires orchestrated cloud infrastructure for sequence processing, quantification, and time-course differential expression modeling.

---

## [916] source=multitask_sft_big

**USER:** Segment individual nuclei and cell boundaries from a 40-channel CODEX multiplexed tissue image of breast cancer and quantify single-cell marker intensities.

**ASSISTANT:** cloud_workflow: Processing multi-channel high-resolution multiplexed pathology images requires an asynchronous cloud pipeline combining deep-learning segmentation models with feature extraction and quantification algorithms.

---

## [917] source=multitask_sft_big

**USER:** I have raw paired-end sequencing reads with unique molecular identifiers (UMIs) and need to run initial quality control, extract UMI sequences, and trim adapter and low-quality sequences prior to alignment.

**ASSISTANT:** cloud_workflow: This task orchestrates a Nextflow bioinformatics pipeline (FastQC, UMI-tools, and fastp) for computationally intensive, high-throughput sequence data preprocessing.

---

## [918] source=multitask_sft_big

**USER:** Identify a minimal prognostic gene signature and evaluate patient survival risk by running iterative Bayesian Model Averaging (BMA) on high-dimensional transcriptomic expression profiles linked with clinical survival outcomes.

**ASSISTANT:** cloud_workflow: Iterative Bayesian Model Averaging for survival analysis is a multi-step statistical bioinformatics pipeline that requires cloud computing resources to iteratively fit Cox proportional hazards models across thousands of candidate genes.

---

## [919] source=multitask_sft_big

**USER:** Perform differential expression analysis on my RNA-seq raw count matrix comparing treated versus control replicates using the edgeR classic pipeline.

**ASSISTANT:** cloud_workflow: Executing an edgeR differential expression pipeline requires multi-step statistical data processing and report generation over transcriptomic count files, necessitating asynchronous cloud workflow execution.

---

## [920] source=multitask_sft_big

**USER:** Cluster and visualize a collection of discovered transcription factor binding motifs from our differential expression and regulatory analysis using motifStack to explore motif relationships interactively.

**ASSISTANT:** instant_compute: Aligning position weight matrices and rendering interactive hierarchical motif trees requires modest computational resources and can be executed quickly in a standard containerized R environment.

---

## [921] source=multitask_sft_big

**USER:** I want to identify, cluster, and build phylogenetic profiles for protein sequences across several newly sequenced bacterial genomes using the nf-core/proteinfamilies pipeline.

**ASSISTANT:** cloud_workflow: nf-core/proteinfamilies is a distributed, multi-tool Nextflow pipeline that requires cloud or HPC infrastructure to perform compute-intensive profile HMM searches and protein sequence clustering.

---

## [922] source=multitask_sft_big

**USER:** Run the fastseg workflow on normalized transcriptomic read depth data to detect genomic segments and focal copy number alterations across tumor samples.

**ASSISTANT:** cloud_workflow: Fastseg executes compute-intensive segmentation algorithms across chromosomal coordinates and multiple samples, necessitating automated pipeline orchestration on cloud infrastructure.

---

## [923] source=multitask_sft_big

**USER:** Visualize the genome-wide distribution of somatic mutations by generating chromosome-scale histogram density plots from an annotated BED file of tumor variants.

**ASSISTANT:** cloud_workflow: Profiling and rendering feature densities across whole chromosomes from genomic track files is an asynchronous bioinformatics pipeline task suited for cloud workflow execution.

---

## [924] source=multitask_sft_big

**USER:** Generate diagnostic QC plots using chipenrich for an H3K27ac ChIP-seq peak set (hg38) to assess gene locus length bias and peak-to-TSS distance distributions prior to gene set enrichment.

**ASSISTANT:** cloud_workflow: Mapping genome-wide ChIP-seq peak sets against reference genomic locus definitions to produce diagnostic enrichment QC plots requires running a containerized bioinformatics pipeline on cloud infrastructure.

---

## [925] source=multitask_sft_big

**USER:** Generate a gene expression count matrix from raw single-cell RNA-seq FASTQ files for a 10x Genomics PBMC dataset.

**ASSISTANT:** cloud_workflow: Extracting count matrices from high-throughput genomic sequencing data requires multi-step pipeline processing and scalable cloud compute infrastructure.

---

## [926] source=multitask_sft_big

**USER:** Call copy number aberrations from our low-pass whole-genome sequencing BAM file using WisecondorX calibrated against our healthy reference panel.

**ASSISTANT:** cloud_workflow: Analyzing low-coverage BAM files for CNV detection with WisecondorX is a multi-step, compute-heavy bioinformatics pipeline that requires asynchronous cloud workflow orchestration.

---

## [927] source=multitask_sft_big

**USER:** Run automated lymph-gate identification, fluorescence marker normalization, and population statistical extraction across a 24-sample FCS cohort using flowStats.

**ASSISTANT:** cloud_workflow: Analyzing multi-sample single-cell flow cytometry data requires batch processing, peak alignment, and automated gating via an asynchronous bioinformatics pipeline.

---

## [928] source=multitask_sft_big

**USER:** Align paired-end FASTQ sequencing reads against the GRCh38 human reference genome using the MapAD mapper and generate coordinate-sorted BAM files with alignment QC metrics.

**ASSISTANT:** cloud_workflow: Executing an nf-core pipeline to process and align high-throughput FASTQ sequencing data requires distributed compute orchestration and containerized execution on the cloud.

---

## [929] source=multitask_sft_big

**USER:** Generate a whole-genome ideogram plotting the chromosomal distribution of copy number variations and SNV densities from an annotated genomic BED file.

**ASSISTANT:** instant_compute: Rendering chromosome ideograms and genomic tracks from tabular coordinate data is a lightweight data visualization task that executes quickly in a sandboxed compute environment.

---

## [930] source=multitask_sft_big

**USER:** Construct an SBML model for a synthetic toggle switch circuit with two mutually repressing transcription factors (LacI and TetR), defining their species, Hill kinetic rate laws, and protein degradation parameters.

**ASSISTANT:** instant_compute: Programmatically constructing, parameterizing, and serializing a biochemical network into standard SBML format runs via lightweight libraries in seconds without requiring heavy distributed cloud infrastructure.

---

## [931] source=multitask_sft_big

**USER:** Analyze raw paired-end RNA-seq FASTQ files to identify, quantify, and functionally characterize differentially expressed long non-coding RNAs (lncRNAs) across tumor versus normal tissues using the NORCE pipeline.

**ASSISTANT:** cloud_workflow: The NORCE transcriptomics pipeline requires multi-step high-throughput alignment, quantification, and network analysis that necessitate scalable cloud computing resources.

---

## [932] source=multitask_sft_big

**USER:** Phase common and rare SNVs and indels in a multi-sample cohort VCF using the SHAPEIT5 workflow with standard reference panels.

**ASSISTANT:** cloud_workflow: This is an nf-core Nextflow pipeline designed for high-throughput genomic phasing that requires cloud or cluster batch execution infrastructure.

---

## [933] source=multitask_sft_big

**USER:** Identify and classify all transcription factor families across a predicted proteome FASTA file from a newly sequenced plant species using PlantTFHunter.

**ASSISTANT:** cloud_workflow: Genome-wide identification of transcription factors against profile HMM libraries requires resource-intensive batch sequence alignment and multi-step pipeline execution in the cloud.

---

## [934] source=multitask_sft_big

**USER:** Calculate ZIP, Bliss, Loewe, and HSA synergy scores and generate 2D/3D interaction surface maps from dose-response matrix data for an oncology drug combination screen.

**ASSISTANT:** cloud_workflow: Calculating multi-model drug combination synergy and rendering multidimensional response surfaces requires running a multi-step biostatistical analysis pipeline in a cloud execution environment.

---

## [935] source=multitask_sft_big

**USER:** Call and filter germline single-nucleotide variants and indels from a set of paired-end whole-exome sequencing BAM files using standard quality thresholds.

**ASSISTANT:** cloud_workflow: Variant calling on high-throughput sequencing data requires substantial multi-step computational resources, disk space, and runtime that must be executed on a distributed cloud pipeline.

---

## [936] source=multitask_sft_big

**USER:** Cluster single-cell RNA-seq gene expression matrices and infer developmental trajectories using Rank Constrained Similarity Learning (RCSL).

**ASSISTANT:** cloud_workflow: Running single-cell RNA-seq similarity learning, clustering, and pseudo-time trajectory reconstruction requires a multi-step bioinformatic workflow executed on cloud infrastructure.

---

## [937] source=multitask_sft_big

**USER:** Analyze Phase II trial multi-omics data to identify predictive biomarker thresholds (e.g., HER2 expression and ctDNA dynamics) for enriching patient responder cohorts in an upcoming oncology study.

**ASSISTANT:** cloud_workflow: Patient enrichment analysis requires multi-step data ingestion, genomic variant filtering, and statistical cohort stratification executing across distributed cloud pipelines.

---

## [938] source=multitask_sft_big

**USER:** Align paired-end RNA-seq FASTQ reads to the human reference genome to identify canonical and non-canonical splice junctions using SpliceMap.

**ASSISTANT:** cloud_workflow: Spliced read alignment against a whole genome is a computationally intensive bioinformatics task requiring high-memory and multi-core cloud infrastructure.

---

## [939] source=multitask_sft_big

**USER:** Identify diagnostic protein biomarker signatures from a high-dimensional plasma proteomics expression matrix by fitting a network-regularized generalized linear model integrating STRING protein-protein interaction networks.

**ASSISTANT:** cloud_workflow: Running glmSparseNet involves an end-to-end bioinformatics pipeline combining PPI network retrieval, high-dimensional regularization, and cross-validation on large omics datasets.

---

## [940] source=multitask_sft_big

**USER:** Standardize TCGA-BRCA biospecimen barcodes, separate primary tumor from matched normal samples, and assemble multi-omics assays into a unified MultiAssayExperiment object for downstream analysis.

**ASSISTANT:** cloud_workflow: Harmonizing multi-assay TCGA cohorts and processing large genomic data packages requires execution within a distributed cloud bioinformatics pipeline.

---

## [941] source=multitask_sft_big

**USER:** Train genetically regulated gene expression prediction models from matched genotype and transcriptomic microarray data using AffiXcan and evaluate tissue-specific trait associations.

**ASSISTANT:** cloud_workflow: AffiXcan involves multi-step statistical model training and cross-validation across large genomic and transcriptomic cohort matrices that require asynchronous cloud execution.

---

## [942] source=multitask_sft_big

**USER:** Run Signaling Pathway Impact Analysis (SPIA) on my RNA-seq differential expression results to identify significantly perturbed KEGG signaling pathways taking into account pathway topology and gene log fold changes.

**ASSISTANT:** cloud_workflow: SPIA involves executing specialized Bioconductor packages against reference pathway topology databases in a dedicated bioinformatics cloud environment.

---

## [943] source=multitask_sft_big

**USER:** Perform comprehensive quality control, batch assessment, and outlier filtering on an untargeted LC-MS metabolomics peak table containing pooled QC samples.

**ASSISTANT:** cloud_workflow: The qmtools workflow processes multi-sample metabolomics feature datasets through a multi-step computational QC and normalization pipeline on cloud infrastructure.

---

## [944] source=multitask_sft_big

**USER:** Identify spatially variable genes across annotated histological domains in my 10x Visium spatial transcriptomics dataset using DESpace.

**ASSISTANT:** cloud_workflow: DESpace performs domain-specific differential expression testing across spatial clusters on large transcriptomics count matrices, requiring containerized compute in a cloud workflow.

---

## [945] source=multitask_sft_big

**USER:** Perform GC-content and sequencing depth normalization on my raw RNA-seq gene count matrix using EDASeq, and identify differentially expressed genes between treated and control samples.

**ASSISTANT:** cloud_workflow: This multi-step RNA-seq pipeline requires heavy genomic feature annotation and statistical normalization best executed as an asynchronous cloud workflow.

---

## [946] source=multitask_sft_big

**USER:** Identify orthologous gene families and generate an interactive orthology summary report across multiple newly annotated bacterial proteomes.

**ASSISTANT:** cloud_workflow: nf-core/reportho is an intensive Nextflow pipeline that requires distributed cloud compute to perform cross-species orthology inference and reporting.

---

## [947] source=multitask_sft_big

**USER:** Verify if genomic coordinate chr7:55249071 (EGFR T790M) has at least 30x sequencing depth in the patient's tumor BAM file.

**ASSISTANT:** cloud_workflow: Interrogating locus-specific read coverage requires running bioinformatics utilities like samtools against large alignment files in a cloud execution environment.

---

## [948] source=multitask_sft_big

**USER:** Run comprehensive quality control and filtering on somatic variant callsets (VCFs) from tumor-normal whole-exome sequencing to identify artifactual mutations.

**ASSISTANT:** cloud_workflow: Evaluating somatic mutation call quality across genomic datasets involves compute-intensive bioinformatic pipeline processing requiring cloud infrastructure.

---

## [949] source=multitask_sft_big

**USER:** Retrieve all verified drug-target interactions, binding affinities (IC50/Ki), and supporting literature references for human EGFR kinase domain inhibitors.

**ASSISTANT:** instant_cited: This query retrieves curated, evidence-backed pharmacology data from established databases without requiring cloud-scale simulation or deep learning inference.

---

## [950] source=multitask_sft_big

**USER:** Estimate bisulfite conversion error rates and quantify site-specific methylation levels across high-throughput WGBS alignment BAM files.

**ASSISTANT:** cloud_workflow: Processing large whole-genome bisulfite sequencing datasets through the BEAT analysis pipeline requires heavy computational resources and distributed batch execution.

---

## [951] source=multitask_sft_big

**USER:** Convert MaxQuant evidence and proteinGroups output files along with an annotation table into the standardized input format for MSstats differential abundance analysis.

**ASSISTANT:** cloud_workflow: This process requires batch data transformation, validation, and conversion of large proteomics search outputs using a containerized workflow execution environment.

---

## [952] source=multitask_sft_big

**USER:** Perform a 100 ns GROMACS molecular dynamics simulation and calculate MM-GBSA binding free energy for human CDK2 complexed with a candidate small-molecule inhibitor to assess dynamic binding stability.

**ASSISTANT:** cloud_workflow: Multi-step all-atom molecular dynamics equilibration, production runs, and subsequent trajectory MM-GBSA calculations require orchestrated, compute-intensive execution on cloud GPU/HPC infrastructure.

---

## [953] source=multitask_sft_big

**USER:** Infer an upstream Boolean signaling network topology from knockdown transcriptomic data using B-NEM with my pre-assigned E-gene expression matrix and candidate S-gene interaction graph.

**ASSISTANT:** cloud_workflow: Boolean Nested Effects Model inference requires iterative network topology searches and likelihood evaluations across perturbation data that must be executed as a multi-step cloud workflow.

---

## [954] source=multitask_sft_big

**USER:** Identify allele-specific expression across heterozygous SNVs in my paired RNA-seq samples using the MBASED beta-binomial statistical framework.

**ASSISTANT:** cloud_workflow: MBASED involves multi-step processing of high-throughput RNA sequencing data and computationally demanding gene-level integration of allele counts that requires cloud workflow execution.

---

## [955] source=multitask_sft_big

**USER:** Identify robustly up- and down-regulated genes across multiple heterogeneous transcriptomic datasets by running a Rank Product multi-condition contrast meta-analysis.

**ASSISTANT:** cloud_workflow: This task involves executing an end-to-end multi-step transcriptomics pipeline for differential expression across multi-condition expression matrices on backend compute infrastructure.

---

## [956] source=multitask_sft_big

**USER:** Identify genes with significant differential transcriptional variability between tumor and normal tissue samples from an RNA-seq count dataset using the missmethyl R/Bioconductor pipeline.

**ASSISTANT:** cloud_workflow: Running differential variability analysis on high-throughput transcriptomics count matrices requires multi-step R/Bioconductor pipeline execution in a cloud compute environment.

---

## [957] source=multitask_sft_big

**USER:** Perform a 5-fold cross-validation using AffiXcan on my matched genotype and RNA-seq expression cohort to evaluate gene expression prediction accuracy.

**ASSISTANT:** cloud_workflow: AffiXcan k-fold cross-validation is a computationally intensive, multi-step pipeline processing large-scale transcriptomic and genomic data across multiple folds on cloud infrastructure.

---

## [958] source=multitask_sft_big

**USER:** Train a multi-layer perceptron on pathway enrichment profiles derived from RNA-seq expression data to classify disease phenotypes.

**ASSISTANT:** cloud_workflow: It executes a multi-step transcriptomic pipeline combining pathway scoring with downstream neural network training, which requires coordinated cloud compute resources.

---

## [959] source=multitask_sft_big

**USER:** Analyze cell-cell spatial microenvironments and neighborhood enrichment patterns in my 10x Xenium spatial transcriptomics dataset using the CatsCradle pipeline.

**ASSISTANT:** cloud_workflow: Spatial transcriptomics neighborhood analysis requires multi-step spatial graph construction, coordinate processing, and statistical enrichment suitable for scalable cloud workflow execution.

---

## [960] source=multitask_sft_big

**USER:** Impute missing peptide intensity values in a label-free LC-MS/MS proteomics abundance matrix using low-rank approximation to prepare data for differential expression analysis.

**ASSISTANT:** cloud_workflow: Running msImpute on high-dimensional mass spectrometry datasets requires containerized bioinformatics pipeline execution in a cloud compute environment.

---

## [961] source=multitask_sft_big

**USER:** Identify statistical outliers in a vector of phenotypic gene expression values using Rosner's extreme studentized deviate test.

**ASSISTANT:** instant_compute: Running parametric and non-parametric outlier detection algorithms on numerical datasets executes rapidly as a lightweight statistical computation without requiring distributed cloud resources.

---

## [962] source=multitask_sft_big

**USER:** Perform hierarchical differential abundance testing on my multi-sample single-cell dataset using treekoR to identify cell lineages associated with patient treatment response.

**ASSISTANT:** cloud_workflow: Running treekoR requires executing a multi-step single-cell statistical pipeline across patient cohorts that exceeds lightweight browser execution and relies on cloud resources.

---

## [963] source=multitask_sft_big

**USER:** Benchmark my custom Affymetrix expression summarization method against RMA and MAS 5.0 on Latin Square spike-in datasets to generate standard assessment tables and ROC curves.

**ASSISTANT:** cloud_workflow: Evaluating microarray summarization algorithms using affycomp involves orchestrating multi-step statistical benchmarking pipelines on standardized spike-in datasets in the cloud.

---

## [964] source=multitask_sft_big

**USER:** Identify transcriptome-wide binding sites and motif enrichment for an RNA-binding protein from raw eCLIP-seq FASTQ reads.

**ASSISTANT:** cloud_workflow: nf-core/clipseq is a complex Nextflow pipeline requiring distributed cloud computing for adapter trimming, read mapping, peak calling, and cross-link site resolution.

---

## [965] source=multitask_sft_big

**USER:** Visualize small RNA sequencing read depth and strand distribution across microRNA hairpin regions from mapped BAM files using ssviz.

**ASSISTANT:** cloud_workflow: Processing high-throughput small RNA-seq alignment files to generate region-specific coverage and distribution plots requires genomic computing pipelines executed in the cloud.

---

## [966] source=multitask_sft_big

**USER:** Filter tandem mass spectrometry peptide-spectrum matches and map post-translational modification sites to protein sequences using MSnID.

**ASSISTANT:** cloud_workflow: This task requires running an automated proteomics pipeline on mass spectrometry identification datasets to perform FDR filtering and sequence modification mapping in a cloud compute environment.

---

## [967] source=multitask_sft_big

**USER:** Adjust for batch effects across multiple sequencing batches in my bulk RNA-seq raw count matrix using ComBat-seq while preserving biological condition covariates.

**ASSISTANT:** cloud_workflow: Applying ComBat-seq to high-dimensional RNA-seq count matrices requires running an R/Bioconductor pipeline on cloud compute infrastructure.

---

## [968] source=multitask_sft_big

**USER:** Process raw paired-end FASTQ reads from a single-cell RNA-seq experiment using scPipe to demultiplex barcodes, align against the mouse reference genome, and generate a quality-filtered gene expression count matrix.

**ASSISTANT:** cloud_workflow: Processing raw single-cell sequencing reads through multi-step demultiplexing, alignment, and quantification requires heavy distributed compute and cloud-based pipeline orchestration.

---

## [969] source=multitask_sft_big

**USER:** Perform quality control, normalization, differential expression, and lipid set enrichment analysis (LSEA) on targeted LC-MS lipidomics data comparing disease and control samples.

**ASSISTANT:** cloud_workflow: Executing the lipidr data processing and enrichment pipeline on metabolomics datasets requires running a multi-step analytical workflow on cloud compute resources.

---

## [970] source=multitask_sft_big

**USER:** Quantify gene expression and perform differential transcriptomic analysis across multi-strain bacterial RNA-seq datasets.

**ASSISTANT:** cloud_workflow: This task requires running an end-to-end multi-step bioinformatics pipeline involving read trimming, alignment, and feature counting across multiple samples on cloud compute infrastructure.

---

## [971] source=multitask_sft_big

**USER:** Analyze longitudinal cellular barcoding count matrices from a hematopoietic stem cell lineage tracing study to evaluate clonal diversity, shared lineage contributions, and clonal persistence across multiple time points.

**ASSISTANT:** cloud_workflow: Processing and tracking high-throughput cellular barcoding data across longitudinal time points and tissues requires a multi-step genomic analysis pipeline running on cloud compute infrastructure.

---

## [972] source=multitask_sft_big

**USER:** Identify differentially expressed genes and generate volcano plots from an RNA-seq count matrix comparing drug-treated versus vehicle control samples.

**ASSISTANT:** cloud_workflow: Differential expression analysis with DESeq2 involves multi-step statistical modeling, dispersion estimation, and multiple-testing corrections across genomic datasets that require a dedicated bioinformatics pipeline environment.

---

## [973] source=multitask_sft_big

**USER:** Quantify nascent RNA synthesis, processing, and degradation rates from a 4sU-seq and total RNA-seq time-course experiment.

**ASSISTANT:** cloud_workflow: Estimating post-transcriptional kinetics with INSPEcT involves multi-step statistical modeling and ODE fitting on sequencing data that requires scalable cloud execution.

---

## [974] source=multitask_sft_big

**USER:** Call copy number variations from paired tumor-normal whole-exome sequencing BAM files by integrating read depth and B-allele frequencies using the iCNV pipeline.

**ASSISTANT:** cloud_workflow: Executing full-scale genomic CNV calling on high-throughput sequencing files requires specialized, multi-step cloud pipeline orchestration and compute resources.

---

## [975] source=multitask_sft_big

**USER:** Identify and annotate somatic structural variants, including chromosomal rearrangements and gene fusions, from paired tumor-normal whole-genome sequencing BAM files of a glioblastoma patient.

**ASSISTANT:** cloud_workflow: Detecting structural variants from whole-genome sequencing data requires orchestrating compute-intensive, multi-step bioinformatics pipelines across distributed cloud infrastructure.

---

## [976] source=multitask_sft_big

**USER:** Benchmark single-cell RNA-seq filtering, normalization, and clustering pipelines on our dataset using pipecomp to evaluate pipeline performance.

**ASSISTANT:** cloud_workflow: Benchmarking and evaluating multi-step scRNA-seq analysis pipelines across data variations requires scalable, multi-step cloud workflow execution.

---

## [977] source=multitask_sft_big

**USER:** Perform longitudinal trajectory clustering on a multi-timepoint RNA-seq dataset of LPS-stimulated macrophages to identify temporally co-expressed gene modules.

**ASSISTANT:** cloud_workflow: Analyzing multi-timepoint transcriptomics datasets requires an orchestrated multi-step pipeline for normalization, dynamic spline modeling, and cluster validation that exceeds local compute limits.

---

## [978] source=multitask_sft_big

**USER:** Identify conserved biomarker expression patterns across multiple transcriptomic datasets by running AW-Fisher meta-analysis and categorization on my RNA-seq cohorts.

**ASSISTANT:** cloud_workflow: This multi-dataset transcriptomic integration and pattern categorization pipeline requires orchestration of distributed bioinformatics compute jobs across cloud infrastructure.

---

## [979] source=multitask_sft_big

**USER:** Call genomic variants from my aligned BAM file against the human reference genome using FreeBayes and filter/sort the resulting VCF with bcftools.

**ASSISTANT:** cloud_workflow: Executing FreeBayes variant calling and bcftools filtering on large BAM alignment files requires a multi-step, resource-intensive pipeline running on cloud compute infrastructure.

---

## [980] source=multitask_sft_big

**USER:** Synthesize the current literature on KRAS G12D inhibitor mechanisms and clinical trial outcomes into a structured briefing document with peer-reviewed references.

**ASSISTANT:** instant_cited: The task performs rapid retrieval, synthesis, and grounded citation of scientific literature without requiring long-running cloud infrastructure or heavy generative modeling.

---

## [981] source=multitask_sft_big

**USER:** Run alignment, clustering, and SNP variant calling on raw multiplexed paired-end RAD-seq FASTQ files for population genetics analysis using nf-core/radseq.

**ASSISTANT:** cloud_workflow: Executing nf-core/radseq requires orchestrating a multi-step, resource-intensive Nextflow pipeline on cloud or HPC infrastructure to process high-throughput sequencing reads.

---

## [982] source=multitask_sft_big

**USER:** Run a topological pathway enrichment analysis on my differential metabolomics and transcriptomics data to identify significantly altered metabolic sub-pathways using graphite and Clipper.

**ASSISTANT:** cloud_workflow: Executing graphite and Clipper on mixed omics data requires a multi-step bioinformatics pipeline with network graph construction, covariance modeling, and compute-intensive permutation tests.

---

## [983] source=multitask_sft_big

**USER:** Generate and bundle standardized GRCh38 reference genome files and aligner indices (STAR, BWA, Bowtie2) for downstream genomic analysis pipelines.

**ASSISTANT:** cloud_workflow: Building genomic reference indices with nf-core/references is a multi-step Nextflow pipeline that requires cloud computing infrastructure and large storage resources.

---

## [984] source=multitask_sft_big

**USER:** Quantify T-cell division peaks, proliferation index, and precursor frequency from multi-sample flow cytometry FCS files labeled with CFSE under varying stimulation conditions.

**ASSISTANT:** cloud_workflow: Processing and deconvolving multi-generational flow cytometry FCS files across experimental batches requires a dedicated, multi-step computational pipeline.

---

## [985] source=multitask_sft_big

**USER:** Run a standard RNA-seq analysis pipeline on paired-end FASTQ files from treated versus control samples to generate quality control reports, gene quantification tables, and differential expression results.

**ASSISTANT:** cloud_workflow: Processing raw transcriptomics sequencing data through alignment, quantification, and statistical testing requires multi-step pipeline orchestration on cloud compute resources.

---

## [986] source=multitask_sft_big

**USER:** Run an IsoformSwitchAnalyzeR analysis on my transcript-level Salmon quantification data to identify differential isoform switches and predict functional consequences such as domain loss and nonsense-mediated decay between control and treated samples.

**ASSISTANT:** cloud_workflow: Executing an IsoformSwitchAnalyzeR workflow involves intensive multi-step processing of transcriptomic quantification data combined with external functional annotation predictions, requiring a dedicated cloud workflow environment.

---

## [987] source=multitask_sft_big

**USER:** Simulate the organ biodistribution and plasma pharmacokinetics of a PEGylated lipid nanoparticle formulation across RES organs and solid tumor tissue over 72 hours using a physiologically-based pharmacokinetic (PBPK) model.

**ASSISTANT:** cloud_workflow: Multi-compartment PBPK modeling of nanoparticle disposition requires executing multi-step ODE-based clearance and tissue-penetration simulation pipelines on cloud infrastructure.

---

## [988] source=multitask_sft_big

**USER:** Align a set of raw single-end small RNA sequencing FASTQ reads against the human reference genome index using rbowtie to generate SAM/BAM alignments.

**ASSISTANT:** cloud_workflow: Short read alignment on high-throughput sequencing datasets is computationally intensive and requires cloud workflow orchestration with scalable memory and CPU resources.

---

## [989] source=multitask_sft_big

**USER:** Annotate and cluster co-eluting mass spectrometry features into cliques to resolve adducts and isotopic peaks from an untargeted LC-MS dataset.

**ASSISTANT:** cloud_workflow: CliqueMS requires executing a multi-step algorithmic network clustering and annotation pipeline over large mass spectrometry feature tables using containerized cloud infrastructure.

---

## [990] source=multitask_sft_big

**USER:** Align paired-end whole-genome bisulfite sequencing (WGBS) FASTQ samples against the human reference genome GRCh38 and remove PCR duplicates using Bismark.

**ASSISTANT:** cloud_workflow: Aligning bisulfite-treated sequencing reads and performing duplicate removal requires distributed, high-memory cloud compute to run standard high-throughput NGS workflows.

---

## [991] source=multitask_sft_big

**USER:** Run a differential expression analysis on a multi-factor transcriptomics dataset with treatment, time point, and batch covariates using a complex experimental design matrix.

**ASSISTANT:** cloud_workflow: Multi-factor transcriptomic sequencing analyses require asynchronous cloud workflow execution for robust statistical modeling and pipeline-scale processing.

---

## [992] source=multitask_sft_big

**USER:** Simulate FFPE-specific chimeric reads and cytosine deamination damage on a reference BAM file to benchmark the robustness of our somatic variant caller.

**ASSISTANT:** cloud_workflow: Modifying large high-throughput sequencing alignment files with synthetic artifact profiles requires distributed compute resources suited for managed cloud workflows.

---

## [993] source=multitask_sft_big

**USER:** Simulate volatile fatty acid (VFA) yields and profile distribution from anaerobic fermentation of food waste under varying pH and retention times.

**ASSISTANT:** cloud_models: Simulating dynamic microbial bioprocess kinetics and metabolic flux distributions for VFA production requires computationally intensive mathematical modeling executed on cloud infrastructure.

---

## [994] source=multitask_sft_big

**USER:** Generate a visual karyotype map depicting structural genomic coordinates and feature annotations across chromosomes from an input BED file using chromDraw.

**ASSISTANT:** cloud_workflow: Rendering chromosomal idiograms and mapping feature densities from BED files requires executing specialized command-line bioinformatics visualization tools on cloud infrastructure.

---

## [995] source=multitask_sft_big

**USER:** Integrate paired single-cell RNA-seq and ATAC-seq count matrices from a 10x Multiome experiment into a unified MuData container, perform multimodal quality control filtering, and compute joint neighborhood graphs.

**ASSISTANT:** cloud_workflow: Processing and integrating high-dimensional multi-omics single-cell matrices with MuData requires distributed, high-memory cloud infrastructure to execute compute-intensive preprocessing and dimensionality reduction pipelines.

---

## [996] source=multitask_sft_big

**USER:** Run gene set variation analysis (GSVA) on my label-free proteomics dataset containing missing values, including preprocessing, imputation, and pathway enrichment score computation across sample groups.

**ASSISTANT:** cloud_workflow: This multi-step omics pipeline requires executing data preprocessing, missing-value imputation, and sample-level pathway enrichment algorithms on scalable cloud compute infrastructure.

---

## [997] source=multitask_sft_big

**USER:** Create an interactive Tkinter widget interface for researchers to select local FASTQ files and configure quality-filtering thresholds.

**ASSISTANT:** instant_compute: Building and executing lightweight interactive GUI widgets is a direct, fast computation that runs instantly without requiring heavy cloud-based pipelines or machine learning infrastructure.

---

## [998] source=multitask_sft_big

**USER:** Perform cluster-based Mutual Nearest Neighbors (MNN) batch effect correction using batchelor on my multi-batch scRNA-seq data to align cell populations across sequencing runs.

**ASSISTANT:** cloud_workflow: Batch correction on single-cell transcriptomics matrices requires substantial computational resources and pipeline execution managed via cloud workflows.

---

## [999] source=multitask_sft_big

**USER:** Run the MAIT pipeline on paired-end bisulfite sequencing data to perform quality trimming, genome alignment, and identify differentially methylated regions across treatment and control cohorts.

**ASSISTANT:** cloud_workflow: Processing raw epigenetic sequencing reads and calling differential methylation requires high-throughput, multi-step cloud workflow execution with substantial compute and memory resources.

---

## [1000] source=multitask_sft_big

**USER:** Scan a set of human ChIP-seq peak regions against the JASPAR CORE vertebrate motif database using TFBSTools to identify enriched transcription factor binding sites.

**ASSISTANT:** cloud_workflow: Scanning genomic ranges against extensive position weight matrix databases using Bioconductor packages requires dedicated cloud bioinformatics pipeline execution and file I/O handling.

---

## [1001] source=multitask_sft_big

**USER:** Map a list of human UniProt protein accessions to their corresponding Ensembl gene IDs and Gene Ontology terms using biobtreeR.

**ASSISTANT:** instant_compute: The biobtreeR package performs rapid biological identifier mapping and cross-database graph queries that execute in seconds within a standard compute environment.

---

## [1002] source=multitask_sft_big

**USER:** Model regional DNA methylation profiles across promoter sites and correlate them with RNA-seq expression levels using the BPRMeth pipeline.

**ASSISTANT:** cloud_workflow: Running BPRMeth on high-throughput genomic and transcriptomic datasets involves multi-step statistical profiling that requires dedicated cloud workflow execution.

---

## [1003] source=multitask_sft_big

**USER:** Upload an image of an LB agar plate to automatically detect, segment, and count the bacterial colonies (CFUs) to calculate transformation efficiency.

**ASSISTANT:** cloud_models: Automated bacterial colony detection and segmentation from plate images requires deep learning computer vision inference executed on cloud GPU infrastructure.

---

## [1004] source=multitask_sft_big

**USER:** Run an automated transcriptomic meta-analysis across three independent Crohn's disease gene expression cohorts to identify consistently perturbed genes with empirical FDR correction.

**ASSISTANT:** cloud_workflow: Cross-study transcriptomic meta-analysis requires multi-dataset ingestion, statistical effect-size aggregation, and permutation-based FDR control executed via a cloud pipeline.

---

## [1005] source=multitask_sft_big

**USER:** Process a raw 10x Genomics scRNA-seq count matrix into a Bioconductor SingleCellExperiment object, perform cell quality control filtering, and run normalization and PCA dimensionality reduction.

**ASSISTANT:** cloud_workflow: Constructing and analyzing a SingleCellExperiment object from high-throughput single-cell count matrices involves multi-step bioinformatics pipeline operations requiring dedicated cloud compute.

---

## [1006] source=multitask_sft_big

**USER:** Test pairwise statistical overlap and calculate odds ratios across multiple differentially expressed gene sets to identify shared transcriptional programs.

**ASSISTANT:** instant_compute: Pairwise hypergeometric and Fisher's exact tests across discrete gene lists are lightweight statistical calculations that execute in seconds without requiring distributed cloud pipeline infrastructure.

---

## [1007] source=multitask_sft_big

**USER:** Load and convert 10x Genomics feature-barcode matrix files into a SingleCellExperiment object in R using the TENxIO package.

**ASSISTANT:** instant_compute: Parsing and converting standard 10x Genomics output files into Bioconductor data structures is a lightweight computational task that executes rapidly in an interactive computing session.

---

## [1008] source=multitask_sft_big

**USER:** Train and evaluate Random Forest and SVM classifiers on my normalized RNA-seq count matrix to distinguish cancer subtypes and extract key predictive biomarker genes.

**ASSISTANT:** cloud_workflow: Multi-algorithm machine learning classification and cross-validation on high-dimensional transcriptomic matrices require multi-step batch execution in a scalable cloud workflow environment.

---

## [1009] source=multitask_sft_big

**USER:** Retrieve and preprocess raw RNA-seq count matrices and matched clinical metadata for TCGA-PRAD and GEO dataset GSE6919 to identify differentially expressed prostate cancer biomarkers.

**ASSISTANT:** cloud_workflow: Downloading, harmonizing, and processing large-scale transcriptomic cohorts from GEO and TCGA requires multi-step cloud-based workflow execution and data pipelines.

---

## [1010] source=multitask_sft_big

**USER:** Identify differentially expressed genes between treated and untreated samples from an RNA-seq gene count matrix using DESeq2.

**ASSISTANT:** cloud_workflow: Two-group transcriptomic differential expression requires orchestrating statistical modeling, normalization, and quality control steps across replicated count matrices within a cloud-based bioinformatics pipeline.

---

## [1011] source=multitask_sft_big

**USER:** Perform functional enrichment clustering and reconstruct gene-term interaction networks from a list of differentially expressed genes.

**ASSISTANT:** cloud_workflow: The fgnet workflow executes a multi-step pipeline integrating database queries, clustering algorithms, and network visualization that requires cloud-based orchestration.

---

## [1012] source=multitask_sft_big

**USER:** Detect germline copy number variations (CNVs) across a cohort of 24 whole-exome sequencing BAM files using cn.mops.

**ASSISTANT:** cloud_workflow: Multi-sample CNV detection from high-throughput NGS alignment files requires significant computational memory and execution time characteristic of cloud workflows.

---

## [1013] source=multitask_sft_big

**USER:** Analyze spatial transcriptomics data from a 10x Visium slide to perform quality control, normalize spot counts, and project gene expression profiles onto the histological tissue image using the Spaniel pipeline.

**ASSISTANT:** cloud_workflow: Processing spatial transcriptomics datasets and generating high-resolution spatial overlay visualizations require dedicated cloud workflow infrastructure for data-intensive bioinformatics pipelines.

---

## [1014] source=multitask_sft_big

**USER:** Translate a bedtools intersect command with reciprocal overlap criteria into equivalent Bioconductor GenomicRanges R code and run it on sample BED intervals.

**ASSISTANT:** instant_compute: Evaluating and translating BEDTools range operations into R/Bioconductor code via HelloRanges is lightweight and executes interactively within seconds without dedicated cloud infrastructure.

---

## [1015] source=multitask_sft_big

**USER:** Calculate genome-wide on-target efficiency and off-target mismatch scores for a custom library of sgRNAs targeting human transcript isoforms.

**ASSISTANT:** cloud_workflow: Genome-wide CRISPR target assessment requires computationally intensive sequence alignment and multi-metric scoring pipelines that run as cloud-based workflows.

---

## [1016] source=multitask_sft_big

**USER:** Predict the oligomeric state (dimer vs. trimer) of a coiled-coil protein sequence using ProCoil.

**ASSISTANT:** instant_compute: ProCoil executes a fast support vector machine scoring method on sequence profiles to predict coiled-coil oligomerization within seconds.

---

## [1017] source=multitask_sft_big

**USER:** Infer a sparse gene regulatory network from high-dimensional transcriptomic data while incorporating biological pathway constraints using SparseNetGLS.

**ASSISTANT:** cloud_workflow: SparseNetGLS performs computationally intensive penalized generalized least squares optimization across large omics matrices, requiring cloud-based workflow infrastructure.

---

## [1018] source=multitask_sft_big

**USER:** Run an end-to-end RNA-seq differential expression analysis pipeline on paired-end FASTQ reads from treated vs. control samples to identify top differentially expressed genes and enriched pathways.

**ASSISTANT:** cloud_workflow: Transcriptomics pipelines require multi-step, high-throughput computational processing—including read alignment, quantification, and statistical modeling—orchestrated asynchronously on cloud infrastructure.

---

## [1019] source=multitask_sft_big

**USER:** Run nf-core/mitodetect on paired-end whole-genome sequencing FASTQ files from tumor and normal tissue samples to identify mitochondrial DNA variants and quantify heteroplasmy levels.

**ASSISTANT:** cloud_workflow: Executing an nf-core pipeline like mitodetect requires scalable, distributed cloud infrastructure to process high-throughput sequencing data through multi-step alignment and variant calling workflows.

---

## [1020] source=multitask_sft_big

**USER:** Calculate treeness, alignment summary metrics, and parsimony-informative sites for my multiple sequence alignment and Newick tree using PhyKIT.

**ASSISTANT:** cloud_workflow: Executing PhyKIT on sequence alignments and tree files requires running command-line phylogenomic tools within an asynchronous cloud bioinformatics workflow.

---

## [1021] source=multitask_sft_big

**USER:** Profile RNA-protein binding sites and peak enrichments from raw paired-end eCLIP FASTQ data in HepG2 cells against control samples.

**ASSISTANT:** cloud_workflow: Processing raw CLIP-seq sequencing reads involves computationally intensive, multi-step tasks including adapter trimming, alignment, peak calling, and motif profiling that require distributed cloud compute.

---

## [1022] source=multitask_sft_big

**USER:** Detect and quantify post-transcriptional RNA modifications across annotated transcriptomes from high-throughput RiboMeth-seq BAM alignment files.

**ASSISTANT:** cloud_workflow: Processing sequencing alignment data to call and quantify RNA modifications requires heavy compute infrastructure, transcript mapping, and multi-step pipeline execution.

---

## [1023] source=multitask_sft_big

**USER:** Perform Gene Ontology enrichment analysis and semantic similarity clustering using GOstats on my set of differentially expressed genes to generate visual DAGs and redundancy-reduced term plots.

**ASSISTANT:** cloud_workflow: This requires executing a multi-step Bioconductor workflow to compute statistical overrepresentation and semantic similarity matrices across Gene Ontology hierarchies on user-supplied gene sets.

---

## [1024] source=multitask_sft_big

**USER:** Generate a comprehensive quality control analysis including read quality distributions, adapter contamination, and GC content for paired-end RNA-seq FASTQ files using qckitfastq.

**ASSISTANT:** cloud_workflow: Evaluating raw high-throughput sequencing data in FASTQ format requires scalable cloud compute to handle data transfer and intensive processing.

---

## [1025] source=multitask_sft_big

**USER:** Perform Disease Ontology (DO) enrichment analysis on a list of upregulated human gene IDs from a colorectal cancer RNA-seq study to identify significantly associated disease phenotypes.

**ASSISTANT:** instant_compute: Disease Ontology over-representation analysis executes rapid statistical tests (e.g., hypergeometric distribution) against pre-indexed databases, delivering results in seconds without requiring distributed cloud pipeline orchestration.

---

## [1026] source=multitask_sft_big

**USER:** Retrieve normalized tissue-specific expression data for human BRCA1 and perform a TopAnat anatomical enrichment test on a set of breast cancer candidate genes using the BgeeDB R package.

**ASSISTANT:** instant_compute: The analysis involves executing straightforward R/Bioconductor API calls and statistical tests to query Bgee without requiring multi-step distributed cloud orchestration.

---

