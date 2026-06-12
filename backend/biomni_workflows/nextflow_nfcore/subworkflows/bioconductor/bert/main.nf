#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BERT — standard_batch_correction
// Perform batch-effect correction on a data frame or matrix using ComBat or limma, with optional parallel processing.
// Input: expression_data.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BERT
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the expression data
//  * 2. [Core Analysis] Run BERT batch correction specifying the method (ComBat or limma) and parallelization cores

nextflow.enable.dsl = 2

process BIOC_BERT_STANDARD_BATCH_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("BERT")
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
    
    # Load the required library
    library(BERT)
    
    # 1. Load the expression data
    # The file is expected to be in the working directory, with samples in rows,
    # features in columns, and a mandatory 'Batch' column.
    if (!file.exists("expression_data.csv")) {
      stop("Error: 'expression_data.csv' not found in the working directory.")
    }
    
    dataset_raw <- read.csv("expression_data.csv", check.names = FALSE)
    
    # 2. Run BERT batch correction specifying the method (ComBat or limma) and parallelization cores
    
    # (a) Standard BERT (uses ComBat by default)
    message("Running standard BERT batch correction...")
    dataset_adjusted <- BERT(dataset_raw)
    write.csv(dataset_adjusted, "dataset_adjusted_standard.csv", row.names = FALSE)
    
    # (b) Sequential adjustment with limma
    message("Running BERT batch correction with limma...")
    dataset_adjusted_limma <- BERT(dataset_raw, method="limma")
    write.csv(dataset_adjusted_limma, "dataset_adjusted_limma.csv", row.names = FALSE)
    
    # (c) Parallel batch effect correction with ComBat (using 2 cores)
    message("Running parallel BERT batch correction with ComBat (2 cores)...")
    dataset_adjusted_parallel <- tryCatch({
      BERT(dataset_raw, cores=2)
    }, error = function(e) {
      message("Parallel execution with 2 cores failed or is not supported on this system. Falling back to sequential.")
      BERT(dataset_raw, cores=1)
    })
    write.csv(dataset_adjusted_parallel, "dataset_adjusted_parallel.csv", row.names = FALSE)
    
    message("Batch correction completed successfully. Outputs saved to CSV files.")

    writeLines(c(
        '"BIOC_BERT_STANDARD_BATCH_CORRECTION":',
        paste0('    BERT: ', as.character(packageVersion('BERT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_batch_correction.csv versions.yml
    """
}

workflow BIOC_BERT_STANDARD_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.csv ] ]

    main:
    BIOC_BERT_STANDARD_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BERT_STANDARD_BATCH_CORRECTION.out.tables
    plots    = BIOC_BERT_STANDARD_BATCH_CORRECTION.out.plots
    objects  = BIOC_BERT_STANDARD_BATCH_CORRECTION.out.objects
    versions = BIOC_BERT_STANDARD_BATCH_CORRECTION.out.versions
}
