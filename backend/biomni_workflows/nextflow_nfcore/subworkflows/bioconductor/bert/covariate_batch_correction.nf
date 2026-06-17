#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BERT — covariate_batch_correction
// Perform batch-effect correction while preserving biological variation of interest by specifying categorical covariates.
// Input: expression_data_with_covariates.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BERT
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the expression data containing covariate columns
//  * 2. [Core Analysis] Run BERT batch correction (covariates are automatically detected or specified via covariatename)

nextflow.enable.dsl = 2

process BIOC_BERT_COVARIATE_BATCH_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    
    # Load required library
    library(BERT)
    
    # Set seed for reproducibility
    set.seed(1)
    
    # 1. Load the expression data containing covariate columns
    # The input file 'expression_data_with_covariates.csv' is expected to have samples in rows,
    # features in columns, a 'Batch' column, and one or more covariate columns prefixed with 'Cov_'.
    dataset_raw <- read.csv("expression_data_with_covariates.csv", check.names = FALSE)
    
    # 2. Run BERT batch correction
    # Covariates (e.g., 'Cov_1') are automatically detected and integrated into the batch effect correction process.
    dataset_adjusted <- BERT(dataset_raw)
    
    # 3. Save the adjusted dataset to a CSV file
    write.csv(dataset_adjusted, "adjusted_expression_data.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_BERT_COVARIATE_BATCH_CORRECTION":',
        paste0('    BERT: ', as.character(packageVersion('BERT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_covariate_batch_correction.csv versions.yml
    """
}

workflow BIOC_BERT_COVARIATE_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data_with_covariates.csv ] ]

    main:
    BIOC_BERT_COVARIATE_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BERT_COVARIATE_BATCH_CORRECTION.out.tables
    plots    = BIOC_BERT_COVARIATE_BATCH_CORRECTION.out.plots
    objects  = BIOC_BERT_COVARIATE_BATCH_CORRECTION.out.objects
    versions = BIOC_BERT_COVARIATE_BATCH_CORRECTION.out.versions
}
