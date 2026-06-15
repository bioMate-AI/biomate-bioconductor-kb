# Full package list — 200 Bioconductor skills

100 most-downloaded + 100 rising-star **analysis** packages. **⭐ = rising star.** Workflows are the distinct analyses each package supports (multi-workflow packages expose each as a `### ` recipe in their `SKILL.md`). ← back to the [README](README.md).

**Jump to a domain:** [transcriptomics](#transcriptomics--97-packages) · [genomics](#genomics--33-packages) · [general](#general--19-packages) · [proteomics](#proteomics--16-packages) · [epigenomics](#epigenomics--10-packages) · [single-cell](#single-cell--8-packages) · [variant-calling](#variant-calling--4-packages) · [metagenomics](#metagenomics--4-packages) · [imaging](#imaging--4-packages) · [enrichment](#enrichment--2-packages) · [annotation](#annotation--2-packages) · [metabolomics](#metabolomics--1-packages)

## transcriptomics  (97 packages)

| Package | Description | Workflows |
|---|---|---|
| [affy](skills/transcriptomics/affy/SKILL.md) | The package contains functions for exploratory oligonucleotide array analysis. The… | *(single analysis)* |
| [apeglm](skills/transcriptomics/apeglm/SKILL.md) | apeglm provides Bayesian shrinkage estimators for effect sizes for a variety of GLM… | *(single analysis)* |
| [ASURAT](skills/transcriptomics/asurat/SKILL.md) ⭐ | ASURAT is a software for single-cell data analysis. Using ASURAT, one can simultaneously… | *(single analysis)* |
| [AUCell](skills/transcriptomics/aucell/SKILL.md) | AUCell allows to identify cells with active gene sets (e.g. signatures, gene modules...)… | *(single analysis)* |
| [awst](skills/transcriptomics/awst/SKILL.md) ⭐ | We propose an Asymmetric Within-Sample Transformation (AWST) to regularize RNA-seq read… | *(single analysis)* |
| [batchelor](skills/transcriptomics/batchelor/SKILL.md) | Implements a variety of methods for batch correction of single-cell (RNA sequencing)… | Cluster Mnn Correction; Batch Rescaling |
| [BindingSiteFinder](skills/transcriptomics/bindingsitefinder/SKILL.md) ⭐ | Precise knowledge on the binding sites of an RNA-binding protein (RBP) is key to… | Differential Binding Analysis |
| [BloodGen3Module](skills/transcriptomics/bloodgen3module/SKILL.md) ⭐ | The BloodGen3Module package provides functions for R user performing module repertoire… | *(single analysis)* |
| [BUSseq](skills/transcriptomics/busseq/SKILL.md) ⭐ | BUSseq R package fits an interpretable Bayesian hierarchical model---the Batch Effects… | *(single analysis)* |
| [cageminer](skills/transcriptomics/cageminer/SKILL.md) ⭐ | This package aims to integrate GWAS-derived SNPs and coexpression networks to mine… | *(single analysis)* |
| [cardelino](skills/transcriptomics/cardelino/SKILL.md) ⭐ | Methods to infer clonal tree configuration for a population of cells using single-cell… | Clone Id Denovo |
| [CBNplot](skills/transcriptomics/cbnplot/SKILL.md) ⭐ | This package provides the visualization of bayesian network inferred from gene expression… | *(single analysis)* |
| [CellBarcode](skills/transcriptomics/cellbarcode/SKILL.md) ⭐ | The package CellBarcode performs Cellular DNA Barcode analysis. It can handle all kinds… | Scrnaseq Sam Lineage Barcoding |
| [cellxgenedp](skills/transcriptomics/cellxgenedp/SKILL.md) ⭐ | The cellxgene data portal (https://cellxgene.cziscience.com/) provides a graphical user… | *(single analysis)* |
| [condiments](skills/transcriptomics/condiments/SKILL.md) ⭐ | This package encapsulate many functions to conduct a differential topology analysis. It… | *(single analysis)* |
| [COTAN](skills/transcriptomics/cotan/SKILL.md) ⭐ | Statistical and computational method to analyze the co-expression of gene pairs at single… | Cell Clustering And Dea; Gene Coexpression And Clustering |
| [crisprBase](skills/transcriptomics/crisprbase/SKILL.md) ⭐ | Provides S4 classes for general nucleases, CRISPR nucleases, CRISPR nickases, and base… | *(single analysis)* |
| [crisprDesign](skills/transcriptomics/crisprdesign/SKILL.md) ⭐ | Provides a comprehensive suite of functions to design and annotate CRISPR guide RNA… | *(single analysis)* |
| [crisprScore](skills/transcriptomics/crisprscore/SKILL.md) ⭐ | Provides R wrappers of several on-target and off-target scoring methods for CRISPR guide… | Off Target Specificity Prediction; Indel Frameshift Prediction; Cas12A On Target Scoring; Cas13D On Target Scoring; Off Target Specificity Scoring |
| [crisprViz](skills/transcriptomics/crisprviz/SKILL.md) ⭐ | Provides functionalities to visualize and contextualize CRISPR guide RNAs (gRNAs) on… | Compare Multiple Guidesets |
| [dada2](skills/transcriptomics/dada2/SKILL.md) | The dada2 package infers exact amplicon sequence variants (ASVs) from high-throughput… | *(single analysis)* |
| [deconvR](skills/transcriptomics/deconvr/SKILL.md) ⭐ | This package provides a collection of functions designed for analyzing deconvolution of… | Atlas Extension And Signature Generation |
| [DESeq2](skills/transcriptomics/deseq2/SKILL.md) | Uses DESeq2 to estimate variance-mean dependence in count data from high-throughput… | De From Transcript Abundance; Multi Factor Analysis; Transformation And Qc; Likelihood Ratio Test |
| [DESpace](skills/transcriptomics/despace/SKILL.md) ⭐ | Intuitive framework for identifying spatially variable genes (SVGs) via edgeR, a popular… | Differential Spatial Patterns |
| [DExMA](skills/transcriptomics/dexma/SKILL.md) ⭐ | performing all the steps of gene expression meta-analysis considering the possible… | Batch Effect Correction; Download Geo Data |
| [Dino](skills/transcriptomics/dino/SKILL.md) ⭐ | Dino normalizes single-cell, mRNA sequencing data to correct for technical variation,… | Single Cell Experiment Normalization; Custom Depth Normalization |
| [DropletUtils](skills/transcriptomics/dropletutils/SKILL.md) | The filtering uses intelligent methods to generate output 10X matrices as would be… | Demultiplex Hashed Libraries; Detect Empty Droplets; Remove Swapping And Chimeric Effects; Remove Barcode Swapping; Remove Chimeric Reads |
| [easier](skills/transcriptomics/easier/SKILL.md) ⭐ | This package provides a workflow for the use of EaSIeR tool, developed to assess… | *(single analysis)* |
| [edgeR](skills/transcriptomics/edger/SKILL.md) | Estimates differential gene expression for short read sequence count using methods… | Glm Lrt Pipeline; Classic Pipeline; Fold Change Threshold Testing |
| [EnhancedVolcano](skills/transcriptomics/enhancedvolcano/SKILL.md) | Volcano plots represent a useful way to visualise the results of differential expression… | *(single analysis)* |
| [epistack](skills/transcriptomics/epistack/SKILL.md) ⭐ | The epistack package main objective is the visualizations of stacks of genomic tracks… | Promoter Epigenetics Expression |
| [escheR](skills/transcriptomics/escher/SKILL.md) ⭐ | The creation of effective visualizations is a fundamental component of data analysis. In… | Binned Spatial Visualization; Dataframe Visualization |
| [fgsea](skills/transcriptomics/fgsea/SKILL.md) | A tabular file with gene symbols in the first column, and a ranked statistic (e.g.… | Gene Set Coregulation Analysis; Over Representation Analysis |
| [FindIT2](skills/transcriptomics/findit2/SKILL.md) ⭐ | This package implements functions to find influential TF and target based on different… | *(single analysis)* |
| [gatom](skills/transcriptomics/gatom/SKILL.md) ⭐ | This package implements a metabolic network analysis pipeline to identify an active… | Lipidomics Metabolite Level Active Module |
| [genomicInstability](skills/transcriptomics/genomicinstability/SKILL.md) ⭐ | This package contain functions to run genomic instability analysis (GIA) from scRNA-Seq… | Reference Based Gia |
| [GenomicSuperSignature](skills/transcriptomics/genomicsupersignature/SKILL.md) ⭐ | Connect new gene expression profile with the relevant information from the existing… | *(single analysis)* |
| [GEOquery](skills/transcriptomics/geoquery/SKILL.md) | This tool fetches microarray data directly from GEO database, based on the GEOQuery R… | *(single analysis)* |
| [GeoTcgaData](skills/transcriptomics/geotcgadata/SKILL.md) ⭐ | Gene Expression Omnibus(GEO) and The Cancer Genome Atlas (TCGA) provide us with a wealth… | Tcga Id Conversion And Normalization; Cnv Differential Analysis; Dna Methylation Differential Analysis; Geo Chip Data Preprocessing |
| [glmGamPoi](skills/transcriptomics/glmgampoi/SKILL.md) | Fit linear models to overdispersed count data. The package can estimate the… | Cell Level Marker Gene Identification |
| [granulator](skills/transcriptomics/granulator/SKILL.md) ⭐ | granulator is an R package for the cell type deconvolution of heterogeneous tissues based… | *(single analysis)* |
| [GSEABase](skills/transcriptomics/gseabase/SKILL.md) | This package provides classes and methods to support Gene Set Enrichment Analysis (GSEA). | *(single analysis)* |
| [GSVA](skills/transcriptomics/gsva/SKILL.md) | Gene Set Variation Analysis (GSVA) is a non-parametric, unsupervised method for… | Single Cell Gsva; Proteomics Missing Values |
| [HarmonizR](skills/transcriptomics/harmonizr/SKILL.md) ⭐ | An implementation, which takes input data and makes it available for proper batch effect… | *(single analysis)* |
| [illuminaio](skills/transcriptomics/illuminaio/SKILL.md) | Tools for parsing Illumina's microarray output files, including IDAT. | *(single analysis)* |
| [InterCellar](skills/transcriptomics/intercellar/SKILL.md) ⭐ | InterCellar is implemented as an R/Bioconductor Package containing a Shiny app that… | *(single analysis)* |
| [limma](skills/transcriptomics/limma/SKILL.md) | Given a matrix of counts (e.g. from featureCounts) and optional information about the… | Filtering Unexpressed Probes; Single Channel Microarray Analysis |
| [MAST](skills/transcriptomics/mast/SKILL.md) | Methods and models for handling zero-inflated single cell assay data. | Gene Set Enrichment Analysis; Scrnaseq Hurdle Analysis |
| [mastR](skills/transcriptomics/mastr/SKILL.md) ⭐ | mastR is an R package designed for automated screening of signatures of interest for… | Multi Dataset Signature Aggregation; Single Cell Pseudo Bulk Signature |
| [MetaboCoreUtils](skills/transcriptomics/metabocoreutils/SKILL.md) | MetaboCoreUtils defines metabolomics-related core functionality provided as low-level… | Quality Assessment And Filtering; Signal Drift Adjustment |
| [metapod](skills/transcriptomics/metapod/SKILL.md) | Implements a variety of methods for combining p-values in differential analyses of… | *(single analysis)* |
| [mirTarRnaSeq](skills/transcriptomics/mirtarrnaseq/SKILL.md) ⭐ | mirTarRnaSeq R package can be used for interactive mRNA miRNA sequencing statistical… | Mirna Mrna Correlation Multi Timepoint; Mirna Mrna Relationship Two Timepoint |
| [monocle](skills/transcriptomics/monocle/SKILL.md) | Monocle performs differential expression and time-series analysis for single-cell… | *(single analysis)* |
| [msa](skills/transcriptomics/msa/SKILL.md) | The 'msa' package provides a unified R/Bioconductor interface to the multiple sequence… | Alignment Masking Consensus And Conservation; Phylogenetic Tree Reconstruction; Pretty Print Alignment |
| [MSstatsLiP](skills/transcriptomics/msstatslip/SKILL.md) ⭐ | Tools for LiP peptide and protein significance analysis. Provides functions for… | Proteolytic Resistance Analysis |
| [NanoTube](skills/transcriptomics/nanotube/SKILL.md) ⭐ | NanoTube includes functions for the processing, quality control, analysis, and… | *(single analysis)* |
| [nnSVG](skills/transcriptomics/nnsvg/SKILL.md) ⭐ | Method for scalable identification of spatially variable genes (SVGs) in… | *(single analysis)* |
| [omicsViewer](skills/transcriptomics/omicsviewer/SKILL.md) ⭐ | omicsViewer visualizes ExpressionSet (or SummarizedExperiment) in an interactive way. The… | *(single analysis)* |
| [ompBAM](skills/transcriptomics/ompbam/SKILL.md) ⭐ | This packages provides C++ header files for developers wishing to create R packages that… | *(single analysis)* |
| [ORFhunteR](skills/transcriptomics/orfhunter/SKILL.md) ⭐ | The ORFhunteR package is a R and C++ library for an automatic determination and… | Predict And Annotate Orfs; Orf Prediction And Annotation |
| [pathview](skills/transcriptomics/pathview/SKILL.md) | Pathview is a stand-alone software package for pathway based data integration and… | Id Mapping And Visualization; Multi Sample Comparison; Discrete Data Visualization |
| [ProteoDisco](skills/transcriptomics/proteodisco/SKILL.md) ⭐ | ProteoDisco is an R package to facilitate proteogenomics studies. It houses functions to… | Splice Junctions Workflow; Manual Transcripts Workflow |
| [ptairMS](skills/transcriptomics/ptairms/SKILL.md) ⭐ | This package implements a suite of methods to preprocess data from PTR-TOF-MS instruments… | Single Raw File Processing |
| [RiboDiPA](skills/transcriptomics/ribodipa/SKILL.md) ⭐ | This package performs differential pattern analysis for Ribo-seq data. It identifies… | Step By Step Pipeline; Exon Level Pipeline; Exon Level Analysis |
| [scanMiR](skills/transcriptomics/scanmir/SKILL.md) ⭐ | A set of tools for working with miRNA affinity models (KdModels), efficiently scanning… | *(single analysis)* |
| [scAnnotatR](skills/transcriptomics/scannotatr/SKILL.md) ⭐ | The package comprises a set of pretrained machine learning models to predict basic immune… | Train Basic Classifier; Train Child Classifier |
| [SCArray](skills/transcriptomics/scarray/SKILL.md) ⭐ | Provides large-scale single-cell omics data manipulation using Genomic Data Structure… | *(single analysis)* |
| [scater](skills/transcriptomics/scater/SKILL.md) | A collection of tools for doing various analyses of single-cell RNA-seq gene expression… | *(single analysis)* |
| [sccomp](skills/transcriptomics/sccomp/SKILL.md) ⭐ | A robust and outlier-aware method for testing differential tissue composition from… | Differential Variability Analysis; Model Comparison Loo; Random Effects Modeling |
| [scDblFinder](skills/transcriptomics/scdblfinder/SKILL.md) | The scDblFinder package gathers various methods for the detection and handling of… | Find Doublet Clusters; Compute Doublet Density |
| [scDesign3](skills/transcriptomics/scdesign3/SKILL.md) ⭐ | We present a statistical simulator, scDesign3, to generate realistic single-cell and… | *(single analysis)* |
| [scran](skills/transcriptomics/scran/SKILL.md) | Implements miscellaneous functions for interpretation of single-cell RNA-seq data.… | Gene Correlation Analysis; Automated Pc Selection |
| [scuttle](skills/transcriptomics/scuttle/SKILL.md) | Provides basic utility functions for performing single-cell analyses, focusing on simple… | Scaling Normalization |
| [sechm](skills/transcriptomics/sechm/SKILL.md) ⭐ | sechm provides a simple interface between SummarizedExperiment objects and the… | *(single analysis)* |
| [SGCP](skills/transcriptomics/sgcp/SKILL.md) ⭐ | SGC is a semi-supervised pipeline for gene clustering in gene co-expression networks. SGC… | *(single analysis)* |
| [siggenes](skills/transcriptomics/siggenes/SKILL.md) | Identification of differentially expressed genes and estimation of the False Discovery… | *(single analysis)* |
| [SimBu](skills/transcriptomics/simbu/SKILL.md) ⭐ | SimBu can be used to simulate bulk RNA-seq datasets with known cell type fractions. You… | *(single analysis)* |
| [simpleSeg](skills/transcriptomics/simpleseg/SKILL.md) ⭐ | Image segmentation is the process of identifying the borders of individual objects (in… | *(single analysis)* |
| [SingleR](skills/transcriptomics/singler/SKILL.md) | Performs unbiased cell type recognition from single-cell RNA sequencing data, by… | Annotation With Single Cell Reference And Diagnostics |
| [spatialDE](skills/transcriptomics/spatialde/SKILL.md) ⭐ | SpatialDE is a method to find spatially variable genes (SVG) from spatial transcriptomics… | Spatial Experiment Workflow |
| [SpatialExperiment](skills/transcriptomics/spatialexperiment/SKILL.md) | Defines an S4 class for storing data from spatial -omics experiments. The class extends… | *(single analysis)* |
| [SpliceWiz](skills/transcriptomics/splicewiz/SKILL.md) ⭐ | The analysis and visualization of alternative splicing (AS) events from RNA sequencing… | Novel Splicing Detection; Star Alignment And Reference Generation; Coverage Visualization; Novel Splicing Analysis |
| [SpotClean](skills/transcriptomics/spotclean/SKILL.md) ⭐ | SpotClean is a computational method to adjust for spot swapping in spatial… | Spatial Experiment Workflow |
| [SpotSweeper](skills/transcriptomics/spotsweeper/SKILL.md) ⭐ | Spatially-aware quality control (QC) software for both spot-level and artifact-level QC… | Technical Artifact Detection |
| [standR](skills/transcriptomics/standr/SKILL.md) ⭐ | standR is an user-friendly R package providing functions to assist conducting… | *(single analysis)* |
| [Statial](skills/transcriptomics/statial/SKILL.md) ⭐ | Statial is a suite of functions for identifying changes in cell state. The functionality… | Continuous Cell State Changes |
| [sva](skills/transcriptomics/sva/SKILL.md) | The sva package contains functions for removing batch effects and other unwanted… | Frozen Sva Prediction; Sequencing; Combat Known Batches; Combat Seq Rna Seq |
| [tanggle](skills/transcriptomics/tanggle/SKILL.md) ⭐ | Offers functions for plotting split (or implicit) networks (unrooted, undirected) and… | Explicit Networks |
| [TDbasedUFEadv](skills/transcriptomics/tdbasedufeadv/SKILL.md) ⭐ | This is an advanced version of TDbasedUFE, which is a comprehensive package to perform… | Multi Omics Sharing Features; Multi Omics Sharing Samples |
| [TrajectoryUtils](skills/transcriptomics/trajectoryutils/SKILL.md) | Implements low-level utilities for single-cell trajectory analysis, primarily intended… | *(single analysis)* |
| [transformGamPoi](skills/transcriptomics/transformgampoi/SKILL.md) ⭐ | Variance-stabilizing transformations help with the analysis of heteroskedastic data… | Model Residuals Transformation |
| [treeio](skills/transcriptomics/treeio/SKILL.md) | "'treeio' is an R package to make it easier to import and store phylogenetic tree with… | *(single analysis)* |
| [treekoR](skills/transcriptomics/treekor/SKILL.md) ⭐ | treekoR is a novel framework that aims to utilise the hierarchical nature of single cell… | *(single analysis)* |
| [tximport](skills/transcriptomics/tximport/SKILL.md) | "Current version only works in 'merge' mode: A single table of gene summarizations is… | Gene Level Import And Edger Limma; Transcript Level Import And Summarization; Alevin Import; Rsem Import; Stringtie Import |
| [vissE](skills/transcriptomics/visse/SKILL.md) ⭐ | This package enables the interpretation and analysis of results from a gene set… | *(single analysis)* |
| [Voyager](skills/transcriptomics/voyager/SKILL.md) ⭐ | SpatialFeatureExperiment (SFE) is a new S4 class for working with spatial single-cell… | *(single analysis)* |
| [zenith](skills/transcriptomics/zenith/SKILL.md) ⭐ | Zenith performs gene set analysis on the result of differential expression using linear… | *(single analysis)* |

## genomics  (33 packages)

| Package | Description | Workflows |
|---|---|---|
| [annotate](skills/genomics/annotate/SKILL.md) | This tool uses the label-tree function from HyPhy to annotate a phylogenetic tree. It… | *(single analysis)* |
| [beer](skills/genomics/beer/SKILL.md) ⭐ | BEER implements a Bayesian model for analyzing phage-immunoprecipitation sequencing… | *(single analysis)* |
| [biocViews](skills/genomics/biocviews/SKILL.md) | Infrastructure to support 'views' used to classify Bioconductor packages. 'biocViews' are… | *(single analysis)* |
| [Biostrings](skills/genomics/biostrings/SKILL.md) | Memory efficient string containers, string matching algorithms, and other utilities, for… | *(single analysis)* |
| [BSgenome](skills/genomics/bsgenome/SKILL.md) | Infrastructure shared by all the Biostrings-based genome data packages. | Constant Width Dictionary Search; Masked Genome Analysis; Constant Width Dict Search; Masked Sequence Analysis |
| [clusterProfiler](skills/genomics/clusterprofiler/SKILL.md) | This package supports functional characteristics of both coding and non-coding genomics… | Biological Theme Comparison; Gene Set Enrichment Analysis |
| [cogeqc](skills/genomics/cogeqc/SKILL.md) ⭐ | cogeqc aims to facilitate systematic quality checks on standard comparative genomics… | *(single analysis)* |
| [ComplexHeatmap](skills/genomics/complexheatmap/SKILL.md) | Complex heatmaps are efficient to visualize associations between different sources of… | Annotations Only; Custom Dendrogram Axes |
| [ConsensusClusterPlus](skills/genomics/consensusclusterplus/SKILL.md) | algorithm for determining cluster count and membership by stability evidence in… | Custom Distance Consensus Clustering |
| [DECIPHER](skills/genomics/decipher/SKILL.md) | A toolset for deciphering and managing biological sequences. | Microarray Design And Analysis; Fish Probe Design; Pcr Primer Design |
| [DNAcopy](skills/genomics/dnacopy/SKILL.md) | Implements the circular binary segmentation (CBS) algorithm to segment DNA copy number… | *(single analysis)* |
| [doubletrouble](skills/genomics/doubletrouble/SKILL.md) ⭐ | doubletrouble aims to identify duplicated genes from whole-genome protein sequences and… | *(single analysis)* |
| [epialleleR](skills/genomics/epialleler/SKILL.md) ⭐ | Epialleles are specific DNA methylation patterns that are mitotically and/or meiotically… | Long Read Methylation Analysis; Methylation Bimodality Ecdf; Methylation Calling Unannotated Bams; Sequence Variant Association; Long Read Methylation Reporting; Methylation Pattern And Ecdf Visualization … |
| [GenomicAlignments](skills/genomics/genomicalignments/SKILL.md) | Provides efficient containers for storing and manipulating short genomic alignments… | Overlap Encoding And Splicing Compatibility; Splice Junction Overlap Encoding |
| [GenomicFeatures](skills/genomics/genomicfeatures/SKILL.md) | Extract the genomic locations of genes, transcripts, exons, introns, and CDS, for the… | *(single analysis)* |
| [GenomicRanges](skills/genomics/genomicranges/SKILL.md) | The ability to efficiently represent and manipulate genomic annotations and alignments is… | *(single analysis)* |
| [ggbio](skills/genomics/ggbio/SKILL.md) | The ggbio package extends and specializes the grammar of graphics for biological data.… | *(single analysis)* |
| [ggmanh](skills/genomics/ggmanh/SKILL.md) ⭐ | Manhattan plot and QQ Plot are commonly used to visualize the end result of Genome Wide… | Binned Manhattan Plot; Gds Variant Annotation Plotting |
| [ggtree](skills/genomics/ggtree/SKILL.md) | "'ggtree' extends the 'ggplot2' plotting system which implemented the grammar of… | *(single analysis)* |
| [GOSemSim](skills/genomics/gosemsim/SKILL.md) | The semantic comparisons of Gene Ontology (GO) annotations provide quantitative ways to… | *(single analysis)* |
| [Gviz](skills/genomics/gviz/SKILL.md) | Genomic data analyses requires integrated visualization of known genomic information and… | Gene Region Visualization |
| [KEGGREST](skills/genomics/keggrest/SKILL.md) | "A package that provides a client interface to the Kyoto Encyclopedia of Genes and… | *(single analysis)* |
| [LinTInd](skills/genomics/lintind/SKILL.md) ⭐ | When we combine gene-editing technology and sequencing technology, we need to reconstruct… | *(single analysis)* |
| [MSA2dist](skills/genomics/msa2dist/SKILL.md) ⭐ | MSA2dist calculates pairwise distances between all sequences of a DNAStringSet or a… | *(single analysis)* |
| [OrganismDbi](skills/genomics/organismdbi/SKILL.md) | The package enables a simple unified interface to several annotation packages each of… | *(single analysis)* |
| [rBLAST](skills/genomics/rblast/SKILL.md) ⭐ | Seamlessly interfaces the Basic Local Alignment Search Tool (BLAST) to search genetic… | Create Custom Blast Db; Create And Query Custom Db |
| [Rsamtools](skills/genomics/rsamtools/SKILL.md) | This package provides an interface to the 'samtools', 'bcftools', and 'tabix' utilities… | *(single analysis)* |
| [rtracklayer](skills/genomics/rtracklayer/SKILL.md) | Extensible framework for interacting with multiple genome browsers (currently UCSC… | *(single analysis)* |
| [ShortRead](skills/genomics/shortread/SKILL.md) | This package implements sampling, iteration, and input of FASTQ files. The package… | Fastq Filtering And Trimming; Parsing Custom Tabular Sequence Files; Custom Column Parsing |
| [supersigs](skills/genomics/supersigs/SKILL.md) ⭐ | Generate SuperSigs (supervised mutational signatures) from single nucleotide variants in… | Partial Signature Adjustment; Predict Supersig |
| [syntenet](skills/genomics/syntenet/SKILL.md) ⭐ | syntenet can be used to infer synteny networks from whole-genome protein sequences and… | Pairwise Synteny Detection |
| [TFBSTools](skills/genomics/tfbstools/SKILL.md) | TFBSTools is a package for the analysis and manipulation of transcription factor binding… | Pairwise Alignment Scanning; Genome Wide Phylogenetic Footprinting; De Novo Motif Discovery |
| [txdbmaker](skills/genomics/txdbmaker/SKILL.md) | A set of tools for making TxDb objects from genomic annotations from various sources… | *(single analysis)* |

## general  (19 packages)

| Package | Description | Workflows |
|---|---|---|
| [basilisk](skills/general/basilisk/SKILL.md) | Installs a self-contained conda instance that is managed by the R/Bioconductor… | *(single analysis)* |
| [Biobase](skills/general/biobase/SKILL.md) | Functions that are needed by many other packages or which replace R functions. | *(single analysis)* |
| [biovizBase](skills/general/biovizbase/SKILL.md) | The biovizBase package is designed to provide a set of utilities, color schemes and… | *(single analysis)* |
| [DOSE](skills/general/dose/SKILL.md) | This package implements five methods proposed by Resnik, Schlicker, Jiang, Lin and Wang… | Gene Set Enrichment Analysis; Semantic Similarity Analysis |
| [ExperimentHub](skills/general/experimenthub/SKILL.md) | This package provides a client for the Bioconductor ExperimentHub web resource.… | *(single analysis)* |
| [faers](skills/general/faers/SKILL.md) ⭐ | The FDA Adverse Event Reporting System (FAERS) is a database used for the spontaneous… | *(single analysis)* |
| [gdsfmt](skills/general/gdsfmt/SKILL.md) | Provides a high-level R interface to CoreArray Genomic Data Structure (GDS) data files.… | *(single analysis)* |
| [genefilter](skills/general/genefilter/SKILL.md) | Some basic functions for filtering genes. | Independent Filtering Diagnostics; Gene Finding |
| [geneplotter](skills/general/geneplotter/SKILL.md) | Functions for plotting genomic data | Single Chromosome Expression Plotting |
| [graphite](skills/general/graphite/SKILL.md) | Graph objects from pathway topology derived from KEGG, Panther, PathBank, PharmGKB,… | Clipper Mixed Metabolomics; Clipper Gene Expression; Topology Gsa Analysis |
| [gypsum](skills/general/gypsum/SKILL.md) | "Client for the gypsum REST API (https://gypsum.artifactdb.com), a cloud-based file store… | *(single analysis)* |
| [immunotation](skills/general/immunotation/SKILL.md) ⭐ | MHC (major histocompatibility complex) molecules are cell surface complexes that present… | *(single analysis)* |
| [mosbi](skills/general/mosbi/SKILL.md) ⭐ | This package is a implementation of biclustering ensemble method MoSBi (Molecular… | *(single analysis)* |
| [MultiAssayExperiment](skills/general/multiassayexperiment/SKILL.md) | Harmonize data management of multiple experimental assays performed on an overlapping set… | *(single analysis)* |
| [pcaMethods](skills/general/pcamethods/SKILL.md) | Provides Bayesian PCA, Probabilistic PCA, Nipals PCA, Inverse Non-Linear PCA and the… | Pca Diagnostics Validation; Expressionset Pca Imputation; Robust Pca Outliers |
| [qvalue](skills/general/qvalue/SKILL.md) | This package takes a list of p-values resulting from the simultaneous testing of many… | Fdr Estimation From Test Statistics |
| [ResidualMatrix](skills/general/residualmatrix/SKILL.md) | Provides delayed computation of a matrix of residuals after fitting a linear model to… | *(single analysis)* |
| [seqLogo](skills/general/seqlogo/SKILL.md) | seqLogo takes the position weight matrix of a DNA sequence motif and plots the… | *(single analysis)* |
| [topGO](skills/general/topgo/SKILL.md) | topGO package provides tools for testing GO terms while accounting for the topology of… | Score Based Expression Enrichment |

## proteomics  (16 packages)

| Package | Description | Workflows |
|---|---|---|
| [bandle](skills/proteomics/bandle/SKILL.md) ⭐ | The Bandle package enables the analysis and visualisation of differential localisation… | *(single analysis)* |
| [BioNAR](skills/proteomics/bionar/SKILL.md) ⭐ | the R package BioNAR, developed to step by step analysis of PPI network. The aim is to… | *(single analysis)* |
| [drugTargetInteractions](skills/proteomics/drugtargetinteractions/SKILL.md) ⭐ | Provides utilities for identifying drug-target interactions for sets of small molecule or… | *(single analysis)* |
| [MatrixQCvis](skills/proteomics/matrixqcvis/SKILL.md) ⭐ | Data quality assessment is an integral part of preparatory data analysis to ensure sound… | *(single analysis)* |
| [mixOmics](skills/proteomics/mixomics/SKILL.md) | Multivariate methods are well suited to large omics data sets where the number of… | Splsda Classification; Spls Regression |
| [MsBackendMassbank](skills/proteomics/msbackendmassbank/SKILL.md) ⭐ | Mass spectrometry (MS) data backend supporting import and export of MS/MS library spectra… | *(single analysis)* |
| [MsCoreUtils](skills/proteomics/mscoreutils/SKILL.md) | MsCoreUtils defines low-level functions for mass spectrometry data and is independent of… | *(single analysis)* |
| [MsDataHub](skills/proteomics/msdatahub/SKILL.md) ⭐ | The MsDataHub package uses the ExperimentHub infrastructure to distribute raw mass… | *(single analysis)* |
| [MSnbase](skills/proteomics/msnbase/SKILL.md) | MSnbase provides infrastructure for manipulation, processing and visualisation of mass… | Label Free Quantitation; Chromatographic Srm Import; Chromatogram Extraction |
| [mzID](skills/proteomics/mzid/SKILL.md) | A parser for mzIdentML files implemented using the XML package. The parser tries to be… | *(single analysis)* |
| [mzR](skills/proteomics/mzr/SKILL.md) | mzR provides a unified API to the common file formats and parsers available for mass… | *(single analysis)* |
| [PhIPData](skills/proteomics/phipdata/SKILL.md) ⭐ | PhIPData defines an S4 class for phage-immunoprecipitation sequencing (PhIP-seq)… | *(single analysis)* |
| [PSMatch](skills/proteomics/psmatch/SKILL.md) | The PSMatch package helps proteomics practitioners to load, handle and manage Peptide… | Ms2 Fragment Ion Analysis; Fragment Ion Calculation And Visualization |
| [QFeatures](skills/proteomics/qfeatures/SKILL.md) | The QFeatures infrastructure enables the management and processing of quantitative… | *(single analysis)* |
| [STRINGdb](skills/proteomics/stringdb/SKILL.md) | "tags: [bioconductor, r, proteomics, vignette-grounded]" | *(single analysis)* |
| [TargetDecoy](skills/proteomics/targetdecoy/SKILL.md) ⭐ | A first step in the data analysis of Mass Spectrometry (MS) based proteomics data is to… | *(single analysis)* |

## epigenomics  (10 packages)

| Package | Description | Workflows |
|---|---|---|
| [bumphunter](skills/epigenomics/bumphunter/SKILL.md) | Tools for finding bumps in genomic data | Full Bumphunter Analysis |
| [ChIPseeker](skills/epigenomics/chipseeker/SKILL.md) | ChIPseeker is a Bioconductor package for annotating ChIP-seq data analysis. Peak… | Multi Dataset Comparison; Peak Annotation And Enrichment; Overlap Testing And Geo Mining; Peak Annotation And Feature Distribution; Peak Overlap Significance And Geo Mining |
| [epigraHMM](skills/epigenomics/epigrahmm/SKILL.md) ⭐ | epigraHMM provides a set of tools for the analysis of epigenomic data based on hidden… | Differential Peak Calling |
| [extraChIPs](skills/epigenomics/extrachips/SKILL.md) ⭐ | This package builds on existing tools and adds some simple but extremely useful… | *(single analysis)* |
| [HiCDCPlus](skills/epigenomics/hicdcplus/SKILL.md) ⭐ | Systematic 3D interaction calls and differential analysis for Hi-C and HiChIP. The… | *(single analysis)* |
| [HiCExperiment](skills/epigenomics/hicexperiment/SKILL.md) ⭐ | R generic interface to Hi-C contact matrices in `.(m)cool`, `.hic` or HiC-Pro derived… | *(single analysis)* |
| [HiContacts](skills/epigenomics/hicontacts/SKILL.md) ⭐ | HiContacts provides a collection of tools to analyse and visualize Hi-C datasets imported… | Contact Map Analysis; Topological Feature Mapping |
| [MACSr](skills/epigenomics/macsr/SKILL.md) ⭐ | The Model-based Analysis of ChIP-Seq (MACS) is a widely used toolkit for identifying… | *(single analysis)* |
| [miaSim](skills/epigenomics/miasim/SKILL.md) ⭐ | Microbiome time series simulation with generalized Lotka-Volterra model, Self-Organized… | *(single analysis)* |
| [minfi](skills/epigenomics/minfi/SKILL.md) | Tools to analyze & visualize Illumina Infinium methylation arrays. | *(single analysis)* |

## single-cell  (8 packages)

| Package | Description | Workflows |
|---|---|---|
| [cytoMEM](skills/single-cell/cytomem/SKILL.md) ⭐ | MEM, Marker Enrichment Modeling, automatically generates and displays quantitative labels… | *(single analysis)* |
| [demuxmix](skills/single-cell/demuxmix/SKILL.md) ⭐ | A package for demultiplexing single-cell sequencing experiments of pooled cells labeled… | Pooling Non Labeled With Labeled Cells |
| [hoodscanR](skills/single-cell/hoodscanr/SKILL.md) ⭐ | hoodscanR is an user-friendly R package providing functions to assist cellular… | *(single analysis)* |
| [MuData](skills/single-cell/mudata/SKILL.md) ⭐ | Save MultiAssayExperiments to h5mu files supported by muon and mudata. Muon is a Python… | *(single analysis)* |
| [scReClassify](skills/single-cell/screclassify/SKILL.md) ⭐ | A post hoc cell type classification tool to fine-tune cell type annotations generated by… | *(single analysis)* |
| [SingleCellExperiment](skills/single-cell/singlecellexperiment/SKILL.md) | Defines a S4 class for storing data from single-cell experiments. This includes… | *(single analysis)* |
| [TreeSummarizedExperiment](skills/single-cell/treesummarizedexperiment/SKILL.md) | TreeSummarizedExperiment has extended SingleCellExperiment to include hierarchical… | *(single analysis)* |
| [zellkonverter](skills/single-cell/zellkonverter/SKILL.md) | Provides methods to convert between Python AnnData objects and SingleCellExperiment… | *(single analysis)* |

## variant-calling  (4 packages)

| Package | Description | Workflows |
|---|---|---|
| [AnnotationHub](skills/variant-calling/annotationhub/SKILL.md) | This package provides a client for the Bioconductor AnnotationHub web resource. The… | *(single analysis)* |
| [snpStats](skills/variant-calling/snpstats/SKILL.md) | Classes and statistical methods for large SNP association studies. This extends the… | Imputation And Association; Ld Analysis; Fst Calculation; Linkage Disequilibrium; Snp Imputation And Association |
| [VariantAnnotation](skills/variant-calling/variantannotation/SKILL.md) | Annotate variants, compute amino acid coding changes, predict coding outcomes. | Genotype To Snpmatrix; Vcf Filtering |
| [vsn](skills/variant-calling/vsn/SKILL.md) | The package implements a method for normalising microarray intensities from single- and… | Affymetrix Genechip Normalization; Reference Normalization; Rglist Normalization |

## metagenomics  (4 packages)

| Package | Description | Workflows |
|---|---|---|
| [biomformat](skills/metagenomics/biomformat/SKILL.md) | This is an R package for interfacing with the BIOM format. This package includes basic… | *(single analysis)* |
| [DirichletMultinomial](skills/metagenomics/dirichletmultinomial/SKILL.md) | "Dirichlet-multinomial mixture models can be used to describe variability in microbial… | Generative Classification |
| [microbiome](skills/metagenomics/microbiome/SKILL.md) | Utilities for microbiome analysis. | *(single analysis)* |
| [phyloseq](skills/metagenomics/phyloseq/SKILL.md) | phyloseq provides a set of classes and tools to facilitate the import, storage, analysis,… | Exploratory Analysis And Visualization; Data Filtering And Transformation; Differential Abundance Deseq2 |

## imaging  (4 packages)

| Package | Description | Workflows |
|---|---|---|
| [cytoviewer](skills/imaging/cytoviewer/SKILL.md) ⭐ | This R package supports interactive visualization of multi-channel images and… | *(single analysis)* |
| [EBImage](skills/imaging/ebimage/SKILL.md) | EBImage provides general purpose functionality for image processing and analysis. In the… | Image Thresholding And Object Manipulation |
| [flowCore](skills/imaging/flowcore/SKILL.md) | Provides S4 data structures and basic functions to deal with flow cytometry data. | Gatingset Hierarchical Analysis |
| [lisaClust](skills/imaging/lisaclust/SKILL.md) ⭐ | lisaClust provides a series of functions to identify and visualise regions of tissue… | Custom Lisa Clustering |

## enrichment  (2 packages)

| Package | Description | Workflows |
|---|---|---|
| [enrichplot](skills/enrichment/enrichplot/SKILL.md) | The 'enrichplot' package implements several visualization methods for interpreting… | *(single analysis)* |
| [ReactomePA](skills/enrichment/reactomepa/SKILL.md) | Reactome is a free, open-source, curated and peer-reviewed pathway database. Their goal… | Reactome Gsea |

## annotation  (2 packages)

| Package | Description | Workflows |
|---|---|---|
| [biomaRt](skills/annotation/biomart/SKILL.md) | In recent years a wealth of biological data has become available in public data… | *(single analysis)* |
| [KEGGgraph](skills/annotation/kegggraph/SKILL.md) | KEGGGraph is an interface between KEGG pathway and graph object as well as a collection… | Chemical Reaction Network Analysis; Chemical Reaction Network Parsing; Expression Data Integration And Neighborhood Subsetting; Pathway Merging And Crosstalk |

## metabolomics  (1 packages)

| Package | Description | Workflows |
|---|---|---|
| [rgoslin](skills/metabolomics/rgoslin/SKILL.md) ⭐ | The R implementation for the Grammar of Succint Lipid Nomenclature parses different short… | *(single analysis)* |

