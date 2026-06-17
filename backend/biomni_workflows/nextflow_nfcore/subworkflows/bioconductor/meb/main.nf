#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MEB — sfmeb_bulk_same_species
// Identify differentially expressed genes in bulk RNA-seq data from the same species using the SFMEB method.
// Input: countsTable, train_id
// Container: quay.io/biocontainers/bioconductor-meb:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MEB
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define candidate gamma parameters
//  * 2. [Core Analysis] Train the SFMEB model using NIMEB with ds = FALSE
//  * 3. [Core Analysis] Predict DEG status using predict on the trained model

nextflow.enable.dsl = 2

process BIOC_MEB_SFMEB_BULK_SAME_SPECIES {
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
    .bm_deps <- c("MEB")
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
    library(MEB)
    
    # ---------------------------------------------------------
    # 1. Read User Input Files
    # ---------------------------------------------------------
    
    # Read countsTable (matrix of raw RNA-seq counts)
    if (file.exists("countsTable.rds")) {
      countsTable <- readRDS("countsTable.rds")
    } else if (file.exists("countsTable.csv")) {
      countsTable <- as.matrix(read.csv("countsTable.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("countsTable.tsv")) {
      countsTable <- as.matrix(read.delim("countsTable.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: countsTable file not found (expected countsTable.rds, countsTable.csv, or countsTable.tsv)")
    }
    
    # Read train_id (vector of row indices representing known housekeeping genes)
    if (file.exists("train_id.rds")) {
      train_id <- readRDS("train_id.rds")
    } else if (file.exists("train_id.txt")) {
      train_id <- as.integer(readLines("train_id.txt"))
    } else if (file.exists("train_id.csv")) {
      train_id <- as.integer(read.csv("train_id.csv", header = FALSE)[[1]])
    } else {
      stop("Error: train_id file not found (expected train_id.rds, train_id.txt, or train_id.csv)")
    }
    
    # Ensure countsTable is a matrix
    countsTable <- as.matrix(countsTable)
    
    # ---------------------------------------------------------
    # 2. Execute Documented Workflow
    # ---------------------------------------------------------
    
    # Define candidate gamma parameters
    gamma <- seq(1e-06,5e-05,1e-06)
    
    # Train the SFMEB model using NIMEB with ds = FALSE
    sim_model_sp <- NIMEB(countsTable=countsTable, train_id=train_id, gamma,
    nu = 0.01, reject_rate = 0.05, ds = FALSE)
    
    # Predict DEG status using predict on the trained model
    sim_model_sp_pred <- predict(sim_model_sp\$model, countsTable)
    
    # Print summary to console
    summary(sim_model_sp_pred)
    
    # ---------------------------------------------------------
    # 3. Save Outputs
    # ---------------------------------------------------------
    
    # Save the trained model object
    saveRDS(sim_model_sp, "sim_model_sp.rds")
    
    # Save prediction results as a CSV table
    # TRUE means non-DE (inside the ball), FALSE means DE (outlier)
    results_df <- data.frame(
      Gene = rownames(countsTable),
      Prediction_Non_DE = sim_model_sp_pred,
      Is_DEG = !sim_model_sp_pred,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "sfmeb_predictions.csv", row.names = FALSE)
    
    # Save summary text
    sink("prediction_summary.txt")
    cat("Summary of SFMEB Predictions (TRUE = Non-DE, FALSE = DE):\n")
    print(summary(sim_model_sp_pred))
    sink()
    
    cat("Workflow completed successfully. Outputs saved to 'sim_model_sp.rds', 'sfmeb_predictions.csv', and 'prediction_summary.txt'.\n")

    writeLines(c(
        '"BIOC_MEB_SFMEB_BULK_SAME_SPECIES":',
        paste0('    MEB: ', as.character(packageVersion('MEB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sfmeb_bulk_same_species.csv versions.yml
    """
}

workflow BIOC_MEB_SFMEB_BULK_SAME_SPECIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countsTable, train_id ] ]

    main:
    BIOC_MEB_SFMEB_BULK_SAME_SPECIES(ch_input)

    emit:
    tables   = BIOC_MEB_SFMEB_BULK_SAME_SPECIES.out.tables
    plots    = BIOC_MEB_SFMEB_BULK_SAME_SPECIES.out.plots
    objects  = BIOC_MEB_SFMEB_BULK_SAME_SPECIES.out.objects
    versions = BIOC_MEB_SFMEB_BULK_SAME_SPECIES.out.versions
}
