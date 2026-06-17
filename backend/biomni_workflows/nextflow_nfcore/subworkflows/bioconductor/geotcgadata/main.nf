#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeoTcgaData — rna_seq_differential_analysis
// Perform differential expression analysis on RNA-seq count data using a Wilcoxon test or other methods.
// Input: df, group
// Container: quay.io/biocontainers/bioconductor-geotcgadata:2.10.0--r45hdfd78af_0
// R packages: S4Vectors, SummarizedExperiment, ChAMP, GeoTcgaData
// Bioconductor: 3.20 | R: 4.4
// Requires: GeoTcgaData, S4Vectors, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare the count matrix and group vector (or construct a SummarizedExperiment object)
//  * 2. [Core Analysis] Run differential_RNA to identify differentially expressed genes

nextflow.enable.dsl = 2

process BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("S4Vectors", "SummarizedExperiment", "ChAMP", "GeoTcgaData")
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
    
    # Load required libraries
    library(GeoTcgaData)
    library(SummarizedExperiment)
    library(S4Vectors)
    
    # 1. Prepare the count matrix and group vector
    # Read df (matrix or data frame of raw RNA-seq counts) from the working directory
    if (file.exists("df.csv")) {
      df <- read.csv("df.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("df.tsv")) {
      df <- read.delim("df.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("df.rds")) {
      df <- readRDS("df.rds")
    } else {
      stop("Error: Could not find 'df.csv', 'df.tsv', or 'df.rds' in the working directory.")
    }
    
    # Read group (vector of sample group assignments) from the working directory
    if (file.exists("group.csv")) {
      group_data <- read.csv("group.csv", header = FALSE)
      group <- as.character(group_data[[1]])
    } else if (file.exists("group.txt")) {
      group <- readLines("group.txt")
    } else if (file.exists("group.rds")) {
      group <- readRDS("group.rds")
    } else {
      stop("Error: Could not find 'group.csv', 'group.txt', or 'group.rds' in the working directory.")
    }
    
    # Ensure df is a data frame
    df <- as.data.frame(df)
    
    # Validate dimensions
    if (ncol(df) != length(group)) {
      stop(sprintf("Dimension mismatch: df has %d columns, but group has %d elements.", ncol(df), length(group)))
    }
    
    # 2. Run differential_RNA to identify differentially expressed genes (Method 1: using data frame)
    result_df <- differential_RNA(counts = df, group = group, filte = FALSE, method = "Wilcoxon")
    
    # Save results from Method 1
    write.csv(result_df, "differential_RNA_results_df.csv", row.names = TRUE)
    
    # 3. Run differential_RNA to identify differentially expressed genes (Method 2: using SummarizedExperiment)
    colData <- S4Vectors::DataFrame(row.names = colnames(df), group = group)
    data <- SummarizedExperiment::SummarizedExperiment(
      assays = S4Vectors::SimpleList(counts = as.matrix(df)),
      colData = colData
    )
    
    result_se <- differential_RNA(counts = data, groupCol = "group", filte = FALSE, method = "Wilcoxon")
    
    # Save results from Method 2
    write.csv(result_se, "differential_RNA_results_se.csv", row.names = TRUE)
    saveRDS(result_se, "differential_RNA_results_se.rds")

    writeLines(c(
        '"BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS":',
        paste0('    GeoTcgaData: ', as.character(packageVersion('GeoTcgaData')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_differential_analysis.csv versions.yml
    """
}

workflow BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ df, group ] ]

    main:
    BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_GEOTCGADATA_RNA_SEQ_DIFFERENTIAL_ANALYSIS.out.versions
}
