#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MEB — sfmeb_bulk_different_species
// Identify differentially expressed genes in bulk RNA-seq data from different species using the SFMEB method.
// Input: countsTable, train_id
// Container: quay.io/biocontainers/bioconductor-meb:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MEB, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define candidate gamma parameters
//  * 2. [Core Analysis] Train the SFMEB model using NIMEB with ds = TRUE

nextflow.enable.dsl = 2

process BIOC_MEB_SFMEB_BULK_DIFFERENT_SPECIES {
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
    library(MEB)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Read countsTable (matrix containing 4 columns: species 1 gene lengths, species 1 counts, species 2 gene lengths, species 2 counts)
    if (file.exists("countsTable.csv")) {
      countsTable <- as.matrix(read.csv("countsTable.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("countsTable.tsv")) {
      countsTable <- as.matrix(read.delim("countsTable.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("countsTable.rds")) {
      countsTable <- readRDS("countsTable.rds")
    } else {
      stop("Error: countsTable file (countsTable.csv, countsTable.tsv, or countsTable.rds) not found in the working directory.")
    }
    
    # Read train_id (vector of row indices representing conserved genes)
    if (file.exists("train_id.csv")) {
      train_id_df <- read.csv("train_id.csv", header = FALSE)
      train_id <- as.integer(train_id_df[[1]])
    } else if (file.exists("train_id.txt")) {
      train_id <- as.integer(readLines("train_id.txt"))
    } else if (file.exists("train_id.rds")) {
      train_id <- readRDS("train_id.rds")
    } else {
      stop("Error: train_id file (train_id.csv, train_id.txt, or train_id.rds) not found in the working directory.")
    }
    
    # Ensure countsTable is a matrix
    countsTable <- as.matrix(countsTable)
    
    # -----------------------------------------------------------------------------
    # 2. Define Candidate Gamma Parameters & Train SFMEB Model
    # -----------------------------------------------------------------------------
    
    gamma <- seq(1e-07,2e-05,1e-06)
    
    sim_model_dsp <- NIMEB(countsTable=countsTable, train_id=train_id, gamma,
    nu = 0.01, reject_rate = 0.1, ds = TRUE)
    
    # -----------------------------------------------------------------------------
    # 3. Predict DE Genes & Save Outputs
    # -----------------------------------------------------------------------------
    
    # Predict discrimination results (TRUE = non-DE, FALSE = DE)
    sim_model_dsp_pred <- predict(sim_model_dsp\$model, countsTable)
    
    # Create prediction results data frame
    pred_df <- data.frame(
      Gene = rownames(countsTable),
      Prediction = sim_model_dsp_pred,
      Is_DE = !sim_model_dsp_pred
    )
    
    # Save prediction results
    write.csv(pred_df, "prediction_results.csv", row.names = FALSE)
    
    # Save training error vs gamma
    train_err_df <- data.frame(
      Gamma = gamma,
      Train_Error = sim_model_dsp\$train_error
    )
    write.csv(train_err_df, "training_error_vs_gamma.csv", row.names = FALSE)
    
    # Save the trained model object
    saveRDS(sim_model_dsp, "sim_model_dsp.rds")
    
    # Generate and save diagnostic plot of training error vs gamma
    pdf("training_error_vs_gamma.pdf")
    plot(gamma, sim_model_dsp\$train_error, type = "b", 
         xlab = "Gamma", ylab = "Training Error",
         main = "SFMEB Training Error vs Gamma")
    dev.off()

    writeLines(c(
        '"BIOC_MEB_SFMEB_BULK_DIFFERENT_SPECIES":',
        paste0('    MEB: ', as.character(packageVersion('MEB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sfmeb_bulk_different_species.csv versions.yml
    """
}

workflow BIOC_MEB_SFMEB_BULK_DIFFERENT_SPECIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countsTable, train_id ] ]

    main:
    BIOC_MEB_SFMEB_BULK_DIFFERENT_SPECIES(ch_input)

    emit:
    tables   = BIOC_MEB_SFMEB_BULK_DIFFERENT_SPECIES.out.tables
    plots    = BIOC_MEB_SFMEB_BULK_DIFFERENT_SPECIES.out.plots
    objects  = BIOC_MEB_SFMEB_BULK_DIFFERENT_SPECIES.out.objects
    versions = BIOC_MEB_SFMEB_BULK_DIFFERENT_SPECIES.out.versions
}
