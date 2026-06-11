#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: anota2seq — rna_seq_matrix_analysis
// Perform a step-by-step translational efficiency analysis starting from raw RNA-seq count matrices.
// Input: dataP, dataT, phenoVec
// Container: quay.io/biocontainers/bioconductor-anota2seq:1.32.0--r45hdfd78af_0
// R packages: anota2seq, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: anota2seq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the Anota2seqDataSet and normalize/transform raw counts using anota2seqDataSetFromMatrix
//  * 2. [Core Analysis] Assess model assumptions (influential data points and common slopes) using anota2seqPerformQC
//  * 3. [Core Analysis] Test for normal distribution of regression residuals using anota2seqResidOutlierTest
//  * 4. [Core Analysis] Analyze changes in translational efficiency and buffering using anota2seqAnalyze
//  * 5. [Core Analysis] Select significant genes based on slope and adjusted p-value thresholds using anota2seqSelSigGenes
//  * 6. [Core Analysis] Categorize genes into gene expression modes using anota2seqRegModes
//  * 7. [Visualization & Output] Visualize results using anota2seqPlotFC, anota2seqPlotPvalues, and anota2seqPlotGenes
//  * 8. [Visualization & Output] Extract output tables using anota2seqGetOutput

nextflow.enable.dsl = 2

process BIOC_ANOTA2SEQ_RNA_SEQ_MATRIX_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("anota2seq", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required library
        library(anota2seq)
        
        # ==========================================
        # 1. READ USER INPUT FILES
        # ==========================================
        
        # Read dataP (matrix of raw counts for translated/polysome-associated mRNA)
        if (file.exists("dataP.rds")) {
          dataP <- readRDS("dataP.rds")
        } else if (file.exists("dataP.csv")) {
          dataP <- as.matrix(read.csv("dataP.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("dataP.tsv")) {
          dataP <- as.matrix(read.delim("dataP.tsv", row.names = 1, check.names = FALSE))
        } else {
          stop("Error: dataP file (dataP.rds, dataP.csv, or dataP.tsv) not found in the working directory.")
        }
        
        # Read dataT (matrix of raw counts for total mRNA)
        if (file.exists("dataT.rds")) {
          dataT <- readRDS("dataT.rds")
        } else if (file.exists("dataT.csv")) {
          dataT <- as.matrix(read.csv("dataT.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("dataT.tsv")) {
          dataT <- as.matrix(read.delim("dataT.tsv", row.names = 1, check.names = FALSE))
        } else {
          stop("Error: dataT file (dataT.rds, dataT.csv, or dataT.tsv) not found in the working directory.")
        }
        
        # Read phenoVec (character vector describing the sample class for each column)
        if (file.exists("phenoVec.rds")) {
          phenoVec <- readRDS("phenoVec.rds")
        } else if (file.exists("phenoVec.csv")) {
          phenoVec <- as.character(read.csv("phenoVec.csv", header = FALSE)[[1]])
        } else if (file.exists("phenoVec.txt")) {
          phenoVec <- readLines("phenoVec.txt")
        } else {
          stop("Error: phenoVec file (phenoVec.rds, phenoVec.csv, or phenoVec.txt) not found in the working directory.")
        }
        
        # ==========================================
        # 2. ANOTA2SEQ ANALYSIS PIPELINE
        # ==========================================
        
        # Initialize the Anota2seqDataSet and normalize/transform raw counts
        ads <- anota2seqDataSetFromMatrix(
            dataP = dataP,    
            dataT = dataT,
            phenoVec = phenoVec,
            dataType = "RNAseq",   
            filterZeroGenes = TRUE, 
            normalize = TRUE,       
            transformation = "TMM-log2",   
            varCutOff = NULL)
        
        # Assess model assumptions (influential data points and common slopes)
        ads <- anota2seqPerformQC(Anota2seqDataSet = ads,
                                  generateSingleGenePlots = TRUE)
        
        # Test for normal distribution of regression residuals
        ads <- anota2seqResidOutlierTest(ads, residFitPlot = FALSE,
                                  generateSingleGenePlots = TRUE, nGraphs = 12)
        
        # Analyze changes in translational efficiency and buffering
        ads <- anota2seqAnalyze(Anota2seqDataSet = ads,
                                analysis = c("translation", "buffering", "total mRNA", "translated mRNA"))
        
        # Select significant genes based on slope and adjusted p-value thresholds
        ads <- anota2seqSelSigGenes(Anota2seqDataSet = ads,
                                    analysis = c("translation", "buffering", "total mRNA", "translated mRNA"),
                                    selContrast = 1,
                                    minSlopeTranslation = -1,
                                    maxSlopeTranslation = 2,
                                    minSlopeBuffering = -2,
                                    maxSlopeBuffering = 1,
                                    maxPAdj = 0.05)
        
        # Categorize genes into gene expression modes
        ads <- anota2seqRegModes(ads)
        
        # ==========================================
        # 3. VISUALIZATION AND OUTPUT GENERATION
        # ==========================================
        
        # Save plots to a PDF file
        pdf("anota2seq_analysis_plots.pdf", width = 10, height = 7)
        anota2seqPlotFC(ads, selContrast = 1, plotToFile = FALSE)
        anota2seqPlotPvalues(ads, selContrast = 1, plotToFile = FALSE)
        anota2seqPlotGenes(ads, selContrast = 1, analysis = "translation", plotToFile = FALSE)
        dev.off()
        
        # Print head of selected translation output to console
        print(head(anota2seqGetOutput(ads, analysis = "translation", output = "selected", getRVM = TRUE, selContrast = 1)))
        
        # Extract and save full output tables
        translation_selected <- anota2seqGetOutput(ads, analysis = "translation", output = "selected", getRVM = TRUE, selContrast = 1)
        write.csv(translation_selected, "translation_selected_genes.csv", row.names = TRUE)
        
        buffering_selected <- anota2seqGetOutput(ads, analysis = "buffering", output = "selected", getRVM = TRUE, selContrast = 1)
        write.csv(buffering_selected, "buffering_selected_genes.csv", row.names = TRUE)
        
        # Save the complete Anota2seqDataSet object
        saveRDS(ads, "anota2seq_dataset.rds")

    writeLines(c(
        '"BIOC_ANOTA2SEQ_RNA_SEQ_MATRIX_ANALYSIS":',
        paste0('    anota2seq: ', as.character(packageVersion('anota2seq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_matrix_analysis.csv versions.yml
    """
}

workflow BIOC_ANOTA2SEQ_RNA_SEQ_MATRIX_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataP, dataT, phenoVec ] ]

    main:
    BIOC_ANOTA2SEQ_RNA_SEQ_MATRIX_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ANOTA2SEQ_RNA_SEQ_MATRIX_ANALYSIS.out.tables
    plots    = BIOC_ANOTA2SEQ_RNA_SEQ_MATRIX_ANALYSIS.out.plots
    objects  = BIOC_ANOTA2SEQ_RNA_SEQ_MATRIX_ANALYSIS.out.objects
    versions = BIOC_ANOTA2SEQ_RNA_SEQ_MATRIX_ANALYSIS.out.versions
}
