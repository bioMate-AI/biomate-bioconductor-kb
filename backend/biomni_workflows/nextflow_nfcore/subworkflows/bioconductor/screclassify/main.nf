#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scReClassify — cell_type_reclassification
// Correct and fine-tune noisy or mislabeled cell type annotations in single-cell RNA-seq data using semi-supervised learning.
// Input: dat, cellTypes
// Container: quay.io/biocontainers/bioconductor-screclassify:1.16.0--r45hdfd78af_0
// R packages: devtools, dplyr, DT, scReClassify, SingleCellExperiment, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, SummarizedExperiment, scReClassify
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform dimension reduction using matPCs to retain principal components explaining at least 70% of the variance
//  * 2. [Core Analysis] Run multiAdaSampling to reclassify cells and correct mislabeled annotations
//  * 3. [Core Analysis] Identify cells that have been reclassified to a different cell type

nextflow.enable.dsl = 2

process BIOC_SCRECLASSIFY_CELL_TYPE_RECLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("devtools", "dplyr", "DT", "scReClassify", "SingleCellExperiment", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    suppressPackageStartupMessages({
      library(scReClassify)
    })
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -----------------------------------------------------------------------------
    # The pipeline reads exactly these files from the working directory:
    # - dat.rds: SingleCellExperiment object containing log-normalized expression data
    # - cellTypes.rds: character vector of initial cell type annotations
    if (!file.exists("dat.rds") || !file.exists("cellTypes.rds")) {
      stop("Required input files 'dat.rds' and/or 'cellTypes.rds' are missing from the working directory.")
    }
    
    dat <- readRDS("dat.rds")
    cellTypes <- readRDS("cellTypes.rds")
    
    # Ensure cellTypes is a character vector
    cellTypes <- as.character(cellTypes)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Perform Dimension Reduction
    # -----------------------------------------------------------------------------
    # Perform dimension reduction using matPCs to retain principal components 
    # explaining at least 70% of the variance.
    reducedDim(dat, "matPCs") <- matPCs(dat, assay = "logNorm", 0.7)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Run multiAdaSampling
    # -----------------------------------------------------------------------------
    # Run multiAdaSampling to reclassify cells and correct mislabeled annotations.
    set.seed(1)
    cellTypes.reclassify <- multiAdaSampling(
      dat, 
      cellTypes, 
      reducedDimName = "matPCs", 
      classifier = "svm", 
      percent = 1, 
      L = 10
    )
    
    # -----------------------------------------------------------------------------
    # Stage 3: Identify Reclassified Cells and Save Outputs
    # -----------------------------------------------------------------------------
    # Identify cells that have been reclassified to a different cell type.
    idx <- which(cellTypes.reclassify\$final != cellTypes)
    diff_table <- cbind(original = cellTypes[idx], reclassify = cellTypes.reclassify\$final[idx])
    
    # If the cells have names/IDs, preserve them in the output table
    if (!is.null(colnames(dat))) {
      rownames(diff_table) <- colnames(dat)[idx]
    } else if (!is.null(names(cellTypes))) {
      rownames(diff_table) <- names(cellTypes)[idx]
    }
    
    # Write meaningful results to output files
    write.csv(diff_table, "reclassification_differences.csv", row.names = TRUE)
    saveRDS(cellTypes.reclassify, "cellTypes_reclassify_results.rds")
    saveRDS(dat, "dat_with_pcs.rds")
    
    cat("Reclassification complete. Outputs saved:\n")
    cat("- 'reclassification_differences.csv': Table of original vs reclassified cell types\n")
    cat("- 'cellTypes_reclassify_results.rds': Full reclassification results object\n")
    cat("- 'dat_with_pcs.rds': SingleCellExperiment object with computed matPCs\n")

    writeLines(c(
        '"BIOC_SCRECLASSIFY_CELL_TYPE_RECLASSIFICATION":',
        paste0('    scReClassify: ', as.character(packageVersion('scReClassify')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_type_reclassification.csv versions.yml
    """
}

workflow BIOC_SCRECLASSIFY_CELL_TYPE_RECLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dat, cellTypes ] ]

    main:
    BIOC_SCRECLASSIFY_CELL_TYPE_RECLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_SCRECLASSIFY_CELL_TYPE_RECLASSIFICATION.out.tables
    plots    = BIOC_SCRECLASSIFY_CELL_TYPE_RECLASSIFICATION.out.plots
    objects  = BIOC_SCRECLASSIFY_CELL_TYPE_RECLASSIFICATION.out.objects
    versions = BIOC_SCRECLASSIFY_CELL_TYPE_RECLASSIFICATION.out.versions
}
