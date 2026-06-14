#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BERT — summarized_experiment_correction
// Perform batch-effect correction directly on a SummarizedExperiment object.
// Input: summarized_experiment.rds
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BERT, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the SummarizedExperiment object
//  * 2. [Core Analysis] Run BERT batch correction by specifying the target assay name

nextflow.enable.dsl = 2

process BIOC_BERT_SUMMARIZED_EXPERIMENT_CORRECTION {
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
    .bm_deps <- c("BERT", "SummarizedExperiment")
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
    library(BERT)
    library(SummarizedExperiment)
    
    # 1. Load the SummarizedExperiment object
    input_file <- "summarized_experiment.rds"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    dataset_raw <- readRDS(input_file)
    
    # Ensure the first assay is named "expr" to match the documented code's argument exactly
    if (length(SummarizedExperiment::assays(dataset_raw)) > 0) {
      names(SummarizedExperiment::assays(dataset_raw))[1] <- "expr"
    } else {
      stop("The input SummarizedExperiment object does not contain any assays.")
    }
    
    # Ensure colData has "Batch" column as required by BERT
    if (!"Batch" %in% colnames(SummarizedExperiment::colData(dataset_raw))) {
      stop("The input SummarizedExperiment's colData must contain a 'Batch' column.")
    }
    
    # 2. Run BERT batch correction by specifying the target assay name
    # This call matches the documented code exactly.
    dataset_adjusted = BERT(dataset_raw, assayname = "expr")
    
    # 3. Save the results
    # Save the complete adjusted SummarizedExperiment object
    saveRDS(dataset_adjusted, "dataset_adjusted.rds")
    
    # Extract and save the corrected assay matrix
    # BERT appends "_BERTcorrected" to the specified assay name
    corrected_assay_name <- "expr_BERTcorrected"
    if (corrected_assay_name %in% names(SummarizedExperiment::assays(dataset_adjusted))) {
      corrected_matrix <- SummarizedExperiment::assay(dataset_adjusted, corrected_assay_name)
      write.csv(as.data.frame(corrected_matrix), "corrected_expression_values.csv", row.names = TRUE)
    }
    
    message("BERT batch correction completed successfully. Outputs saved to 'dataset_adjusted.rds' and 'corrected_expression_values.csv'.")

    writeLines(c(
        '"BIOC_BERT_SUMMARIZED_EXPERIMENT_CORRECTION":',
        paste0('    BERT: ', as.character(packageVersion('BERT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summarized_experiment_correction.csv versions.yml
    """
}

workflow BIOC_BERT_SUMMARIZED_EXPERIMENT_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ summarized_experiment.rds ] ]

    main:
    BIOC_BERT_SUMMARIZED_EXPERIMENT_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BERT_SUMMARIZED_EXPERIMENT_CORRECTION.out.tables
    plots    = BIOC_BERT_SUMMARIZED_EXPERIMENT_CORRECTION.out.plots
    objects  = BIOC_BERT_SUMMARIZED_EXPERIMENT_CORRECTION.out.objects
    versions = BIOC_BERT_SUMMARIZED_EXPERIMENT_CORRECTION.out.versions
}
