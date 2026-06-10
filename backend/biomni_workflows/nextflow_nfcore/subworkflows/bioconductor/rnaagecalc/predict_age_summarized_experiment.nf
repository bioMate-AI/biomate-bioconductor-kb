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
//  * 1. [Visualization & Output] Load SummarizedExperiment and package. 2. Construct or load SummarizedExperiment with "FPKM" or "counts" assay and "age" column in

nextflow.enable.dsl = 2

process BIOC_RNAAGECALC_PREDICT_AGE_SUMMARIZED_EXPERIMENT {
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
    
    # 1. Read the user input SummarizedExperiment object from the working directory
    input_file <- "se.rds"
    if (!file.exists(input_file)) {
      if (file.exists("se")) {
        input_file <- "se"
      } else {
        stop("Error: Input file 'se.rds' or 'se' not found in the working directory.")
      }
    }
    
    se <- readRDS(input_file)
    
    # 2. Predict age using predict_age_fromse
    # Determine exprtype based on assay names
    expr_type <- if ("FPKM" %in% assayNames(se)) "FPKM" else "counts"
    res3 <- predict_age_fromse(se = se, exprtype = expr_type)
    
    # Print the head of the results to console as in the documented code
    print("Head of predicted age results:")
    print(head(res3))
    
    # 3. Write the meaningful results to output files
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
