#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scRecover — scrna_seq_imputation
// Detect and impute dropout values in a scRNA-seq raw read counts matrix or SingleCellExperiment object while keeping real zeros unchanged.
// Input: counts, labels
// Container: quay.io/biocontainers/bioconductor-screcover:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SingleCellExperiment, scRecover
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load or format input data (matrix or SingleCellExperiment)
//  * 2. [Core Analysis] Run scRecover with Kcluster or labels specified to perform imputation
//  * 3. [Visualization & Output] Retrieve imputed matrices from the specified output directory

nextflow.enable.dsl = 2

process BIOC_SCRECOVER_SCRNA_SEQ_IMPUTATION {
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
    .bm_deps <- c("scRecover", "BiocParallel", "SingleCellExperiment")
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
    library(scRecover)
    library(BiocParallel)
    suppressMessages(library(SingleCellExperiment))
    
    # ==========================================
    # 1. Load or format input data
    # ==========================================
    
    # Read counts matrix or SingleCellExperiment object from the working directory
    counts <- NULL
    if (file.exists("counts.rds")) {
      counts <- readRDS("counts.rds")
    } else if (file.exists("counts.csv")) {
      counts <- as.matrix(read.csv("counts.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("counts.tsv")) {
      counts <- as.matrix(read.delim("counts.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("sce.rds")) {
      sce_input <- readRDS("sce.rds")
      counts <- assay(sce_input, "counts")
    } else {
      stop("Error: Input counts file (counts.rds, counts.csv, counts.tsv, or sce.rds) not found in the working directory.")
    }
    
    # Read optional labels vector from the working directory
    labels <- NULL
    if (file.exists("labels.rds")) {
      labels <- readRDS("labels.rds")
    } else if (file.exists("labels.csv")) {
      labels <- read.csv("labels.csv", header = FALSE)[[1]]
    } else if (file.exists("labels.tsv")) {
      labels <- read.delim("labels.tsv", header = FALSE)[[1]]
    } else if (file.exists("labels.txt")) {
      labels <- readLines("labels.txt")
    }
    
    # Ensure counts is in matrix format if it's not already a SingleCellExperiment
    if (is.data.frame(counts)) {
      counts <- as.matrix(counts)
    }
    
    # ==========================================
    # 2. Parallel Execution Setup
    # ==========================================
    
    # Set the parameters and register the back-end to be used based on OS
    if (.Platform\$OS.type == "unix") {
      message("Setting up MulticoreParam for Unix/Mac parallel execution...")
      # Using a safe number of workers (2) to prevent resource exhaustion
      param <- MulticoreParam(workers = 2, progressbar = TRUE)
      register(param)
    } else {
      message("Setting up SnowParam for Windows parallel execution...")
      # Using a safe number of workers (2) to prevent resource exhaustion
      param <- SnowParam(workers = 2, type = "SOCK", progressbar = TRUE)
      register(param)
    }
    
    # ==========================================
    # 3. Run scRecover Imputation
    # ==========================================
    
    # Execute a single appropriate run of scRecover with parallelization and explicit outputDir
    if (!is.null(labels)) {
      message("Running parallel scRecover with labels specified...")
      scRecover(counts = counts, labels = labels, parallel = TRUE, BPPARAM = param, outputDir = "./outDir_scRecover/", verbose = FALSE)
    } else {
      message("Running parallel scRecover with Kcluster specified...")
      scRecover(counts = counts, Kcluster = 2, parallel = TRUE, BPPARAM = param, outputDir = "./outDir_scRecover/", verbose = FALSE)
    }
    
    # ==========================================
    # 4. Retrieve and Save Imputed Results
    # ==========================================
    
    # Locate and copy the primary imputed outputs to the working directory
    imputed_dirs <- c("./outDir_scRecover/")
    output_found <- FALSE
    
    for (dir in imputed_dirs) {
      if (dir.exists(dir)) {
        imputed_files <- list.files(dir, pattern = "\\\\.(csv|rds|txt)\$", full.names = TRUE, recursive = TRUE)
        if (length(imputed_files) > 0) {
          message("Imputation successful. Copying results from ", dir, " to working directory...")
          for (f in imputed_files) {
            dest_file <- file.path(".", paste0("final_", basename(f)))
            file.copy(f, dest_file, overwrite = TRUE)
            message("Saved: ", dest_file)
          }
          output_found <- TRUE
        }
      }
    }
    
    if (!output_found) {
      warning("No imputed output files were detected in the output directories.")
    }
    
    message("scRecover pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SCRECOVER_SCRNA_SEQ_IMPUTATION":',
        paste0('    scRecover: ', as.character(packageVersion('scRecover')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrna_seq_imputation.csv versions.yml
    """
}

workflow BIOC_SCRECOVER_SCRNA_SEQ_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, labels ] ]

    main:
    BIOC_SCRECOVER_SCRNA_SEQ_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_SCRECOVER_SCRNA_SEQ_IMPUTATION.out.tables
    plots    = BIOC_SCRECOVER_SCRNA_SEQ_IMPUTATION.out.plots
    objects  = BIOC_SCRECOVER_SCRNA_SEQ_IMPUTATION.out.objects
    versions = BIOC_SCRECOVER_SCRNA_SEQ_IMPUTATION.out.versions
}
