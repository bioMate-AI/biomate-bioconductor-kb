#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scuttle — scaling_normalization
// Perform scaling normalization on single-cell RNA-seq data using median-based, pooling-based (deconvolution), or spike-in-based methods to remove cell-specific t
// Input: sce
// Container: quay.io/biocontainers/bioconductor-scuttle:1.20.0--r45ha27e39d_0
// R packages: SingleCellExperiment, scran, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scran, scuttle
// QC: clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute median-based size factors using medianSizeFactors
//  * 2. [Core Analysis] Perform pooling normalization by first clustering cells (using scran::quickCluster or metadata) and then computing pooled size fac
//  * 3. [Core Analysis] Alternatively, compute spike-in-based size factors using computeSpikeFactors if spike-in controls are available

nextflow.enable.dsl = 2

process BIOC_SCUTTLE_SCALING_NORMALIZATION {
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
    .bm_deps <- c("SingleCellExperiment", "scran", "scuttle")
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
    library(scuttle)
    library(scran)
    
    # Read user input
    # The pipeline reads the SingleCellExperiment object 'sce' from the working directory.
    sce <- readRDS("sce.rds")
    
    # Open a text file to log the summaries of the size factors
    sink("normalization_summaries.txt")
    
    # 1. Compute median-based size factors using medianSizeFactors
    cat("=== Median-based Size Factors ===\n")
    print(summary(medianSizeFactors(sce)))
    cat("\n")
    
    # 2. Perform pooling normalization by first clustering cells and then computing pooled size factors
    cat("=== Pooling Normalization (quickCluster) ===\n")
    clusters <- quickCluster(sce)
    sce <- computePooledFactors(sce, clusters=clusters)
    print(summary(sizeFactors(sce)))
    cat("\n")
    
    # Save the primary normalized object
    saveRDS(sce, "sce_normalized.rds")
    
    # Optional sub-step: pooling using metadata (level1class) if available
    cat("=== Pooling Normalization (level1class) ===\n")
    tryCatch({
      sce_meta <- computePooledFactors(sce, clusters=sce\$level1class)
      print(summary(sizeFactors(sce_meta)))
      saveRDS(sce_meta, "sce_normalized_level1class.rds")
    }, error = function(e) {
      cat("Skipped level1class pooling normalization: ", e\$message, "\n")
    })
    cat("\n")
    
    # 3. Compute spike-in-based size factors using computeSpikeFactors if ERCC controls are available
    cat("=== Spike-in Normalization (ERCC) ===\n")
    tryCatch({
      sce2 <- computeSpikeFactors(sce, "ERCC")
      print(summary(sizeFactors(sce2)))
      saveRDS(sce2, "sce_spike_normalized.rds")
    }, error = function(e) {
      cat("Skipped spike-in normalization: ", e\$message, "\n")
    })
    
    # Close the log file
    sink()

    writeLines(c(
        '"BIOC_SCUTTLE_SCALING_NORMALIZATION":',
        paste0('    scuttle: ', as.character(packageVersion('scuttle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scaling_normalization.csv versions.yml
    """
}

workflow BIOC_SCUTTLE_SCALING_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_SCUTTLE_SCALING_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SCUTTLE_SCALING_NORMALIZATION.out.tables
    plots    = BIOC_SCUTTLE_SCALING_NORMALIZATION.out.plots
    objects  = BIOC_SCUTTLE_SCALING_NORMALIZATION.out.objects
    versions = BIOC_SCUTTLE_SCALING_NORMALIZATION.out.versions
}
