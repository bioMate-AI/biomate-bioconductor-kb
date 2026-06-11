#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDataviz — import_numerical_data
// Import any numerical matrix (e.g., custom single-cell expression matrix) into a SingleCellExperiment object for scDataviz.
// Input: mat, metadata
// Container: quay.io/biocontainers/bioconductor-scdataviz:1.20.0--r45hdfd78af_0
// R packages: scDataviz
// Bioconductor: 3.20 | R: 4.4
// Requires: scDataviz
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create numerical matrix and metadata. 2. Import data using importData

nextflow.enable.dsl = 2

process BIOC_SCDATAVIZ_IMPORT_NUMERICAL_DATA {
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
    .bm_deps <- c("scDataviz")
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
    library(scDataviz)
    
    # 1. Read user input files from the working directory
    # We assume 'matrix.csv' contains the numerical matrix (cells as rows, markers as columns)
    # and 'metadata.csv' contains the sample metadata with row names matching the cell IDs.
    mat_df <- read.csv("matrix.csv", row.names = 1, check.names = FALSE)
    mat <- as.matrix(mat_df)
    
    metadata <- read.csv("metadata.csv", row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
    
    # 2. Import data using importData exactly as documented
    sce <- importData(mat,
      assayname = 'normcounts',
      metadata = metadata)
    
    # 3. Save the meaningful results to output files
    saveRDS(sce, file = "sce_imported.rds")
    
    # Save a text summary of the imported SingleCellExperiment object
    sink("sce_summary.txt")
    cat("=== Imported SingleCellExperiment Object ===\n")
    print(sce)
    cat("\n=== Metadata Head ===\n")
    print(head(metadata(sce)))
    sink()

    writeLines(c(
        '"BIOC_SCDATAVIZ_IMPORT_NUMERICAL_DATA":',
        paste0('    scDataviz: ', as.character(packageVersion('scDataviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_import_numerical_data.csv versions.yml
    """
}

workflow BIOC_SCDATAVIZ_IMPORT_NUMERICAL_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mat, metadata ] ]

    main:
    BIOC_SCDATAVIZ_IMPORT_NUMERICAL_DATA(ch_input)

    emit:
    tables   = BIOC_SCDATAVIZ_IMPORT_NUMERICAL_DATA.out.tables
    plots    = BIOC_SCDATAVIZ_IMPORT_NUMERICAL_DATA.out.plots
    objects  = BIOC_SCDATAVIZ_IMPORT_NUMERICAL_DATA.out.objects
    versions = BIOC_SCDATAVIZ_IMPORT_NUMERICAL_DATA.out.versions
}
