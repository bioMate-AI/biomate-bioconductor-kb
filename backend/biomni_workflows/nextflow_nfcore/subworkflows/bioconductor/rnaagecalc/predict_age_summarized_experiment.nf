#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RNAAgeCalc — predict_age_summarized_experiment
// Calculate transcriptional age from a SummarizedExperiment object.
// Input: se
// Container: quay.io/biocontainers/bioconductor-rnaagecalc:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RNAAgeCalc, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the user input SummarizedExperiment object from the
//  * 2. [Visualization & Output] Predict age using predict_age_fromse
//  * 3. [Visualization & Output] Write the meaningful results to output files

nextflow.enable.dsl = 2

process BIOC_RNAAGECALC_PREDICT_AGE_SUMMARIZED_EXPERIMENT {
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
    .bm_deps <- c("RNAAgeCalc", "SummarizedExperiment")
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
    library(RNAAgeCalc)
    library(SummarizedExperiment)
    
    # --- Read the user input SummarizedExperiment object from the ---
    input_file <- "se.rds"
    if (!file.exists(input_file)) {
      if (file.exists("se")) {
        input_file <- "se"
      } else {
        stop("Error: Input file 'se.rds' or 'se' not found in the working directory.")
      }
    }
    
    se <- readRDS(input_file)
    
    # --- Predict age using predict_age_fromse ---
    # Determine exprtype based on assay names
    expr_type <- if ("FPKM" %in% assayNames(se)) "FPKM" else "counts"
    res3 <- predict_age_fromse(se = se, exprtype = expr_type)
    
    # Print the head of the results to console as in the documented code
    print("Head of predicted age results:")
    print(head(res3))
    
    # --- Write the meaningful results to output files ---
    # Save the prediction table as a CSV file
    write.csv(res3, file = "predicted_age_results.csv", row.names = TRUE)
    
    # Save the prediction table as an RDS object for downstream R analyses
    saveRDS(res3, file = "predicted_age_results.rds")
    
    # Optional: Generate and save a plot if chronological age is available and makeplot succeeds
    tryCatch({
      if ("ChronAge" %in% colnames(res3) || "age" %in% colnames(colData(se))) {
        pdf("rna_age_vs_chronological_age.pdf", width = 6, height = 6)
        tryCatch({
          makeplot(res3)
        }, finally = {
          dev.off()
        })
        message("Plot saved to 'rna_age_vs_chronological_age.pdf'")
      }
    }, error = function(e) {
      warning("Could not generate plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_RNAAGECALC_PREDICT_AGE_SUMMARIZED_EXPERIMENT":',
        paste0('    RNAAgeCalc: ', as.character(packageVersion('RNAAgeCalc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predict_age_summarized_experiment.csv versions.yml
    """
}

workflow BIOC_RNAAGECALC_PREDICT_AGE_SUMMARIZED_EXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ se ] ]

    main:
    BIOC_RNAAGECALC_PREDICT_AGE_SUMMARIZED_EXPERIMENT(ch_input)

    emit:
    tables   = BIOC_RNAAGECALC_PREDICT_AGE_SUMMARIZED_EXPERIMENT.out.tables
    plots    = BIOC_RNAAGECALC_PREDICT_AGE_SUMMARIZED_EXPERIMENT.out.plots
    objects  = BIOC_RNAAGECALC_PREDICT_AGE_SUMMARIZED_EXPERIMENT.out.objects
    versions = BIOC_RNAAGECALC_PREDICT_AGE_SUMMARIZED_EXPERIMENT.out.versions
}
