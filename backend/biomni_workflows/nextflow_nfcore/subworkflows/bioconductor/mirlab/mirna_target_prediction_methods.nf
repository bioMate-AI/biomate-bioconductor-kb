#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miRLAB — mirna_target_prediction_methods
// Predict miRNA targets using alternative computational methods such as Mutual Information, causal inference (IDA), or linear regression (Lasso).
// Input: EMT35.csv
// Container: quay.io/biocontainers/bioconductor-mirlab:1.40.0--r45hdfd78af_0
// R packages: miRLAB
// Bioconductor: 3.20 | R: 4.4
// Requires: miRLAB
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define cause (miRNA) and effect (mRNA) column indices
//  * 2. [Core Analysis] Predict targets using Pearson, MI, IDA, or Lasso

nextflow.enable.dsl = 2

process BIOC_MIRLAB_MIRNA_TARGET_PREDICTION_METHODS {
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
    .bm_deps <- c("miRLAB")
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
    library(miRLAB)
    
    # Define the input dataset path (local file as requested)
    dataset <- "EMT35.csv"
    
    # Define cause (miRNA) and effect (mRNA) column indices
    cause <- 1:35       # column 1:35 are miRNAs
    effect <- 36:1189   # column 36:1189 are mRNAs
    
    # Predict miRNA targets using Pearson correlation
    message("Running Pearson correlation...")
    pearson <- Pearson(dataset, cause, effect)
    
    # Predict miRNA targets using Mutual Information
    message("Running Mutual Information...")
    mi <- MI(dataset, cause, effect)
    
    # Predict miRNA targets using causal inference (IDA)
    message("Running IDA...")
    ida <- IDA(dataset, cause, effect, "stable", 0.01)
    
    # Predict miRNA targets using linear regression (Lasso)
    message("Running Lasso...")
    lasso <- Lasso(dataset, cause, effect)
    
    # Save the results to CSV files
    message("Saving results to CSV files...")
    write.csv(pearson, file = "pearson_predictions.csv", row.names = TRUE)
    write.csv(mi, file = "mi_predictions.csv", row.names = TRUE)
    write.csv(ida, file = "ida_predictions.csv", row.names = TRUE)
    write.csv(lasso, file = "lasso_predictions.csv", row.names = TRUE)
    
    # Save the results as RDS objects for downstream R analysis
    message("Saving results to RDS files...")
    saveRDS(pearson, file = "pearson_predictions.rds")
    saveRDS(mi, file = "mi_predictions.rds")
    saveRDS(ida, file = "ida_predictions.rds")
    saveRDS(lasso, file = "lasso_predictions.rds")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MIRLAB_MIRNA_TARGET_PREDICTION_METHODS":',
        paste0('    miRLAB: ', as.character(packageVersion('miRLAB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_target_prediction_methods.csv versions.yml
    """
}

workflow BIOC_MIRLAB_MIRNA_TARGET_PREDICTION_METHODS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ EMT35.csv ] ]

    main:
    BIOC_MIRLAB_MIRNA_TARGET_PREDICTION_METHODS(ch_input)

    emit:
    tables   = BIOC_MIRLAB_MIRNA_TARGET_PREDICTION_METHODS.out.tables
    plots    = BIOC_MIRLAB_MIRNA_TARGET_PREDICTION_METHODS.out.plots
    objects  = BIOC_MIRLAB_MIRNA_TARGET_PREDICTION_METHODS.out.objects
    versions = BIOC_MIRLAB_MIRNA_TARGET_PREDICTION_METHODS.out.versions
}
