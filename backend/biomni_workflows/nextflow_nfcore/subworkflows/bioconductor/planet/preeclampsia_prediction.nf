#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: planet — preeclampsia_prediction
// Calculate the probability of early-onset preeclampsia (EOPE) from placental DNA methylation samples.
// Input: DNAm_betas_normalized.rds
// Container: quay.io/biocontainers/bioconductor-planet:1.18.0--r45hdfd78af_0
// Requires: dplyr, ggplot2, planet, tidyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Predict preeclampsia status using predictPreeclampsia on the transposed, normalized beta matrix

nextflow.enable.dsl = 2

process BIOC_PLANET_PREECLAMPSIA_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(planet)
    library(dplyr)
    library(ggplot2)
    library(tidyr)
    
    # 1. Read the user input file
    # The input is a BMIQ-normalized matrix of DNA methylation beta values with samples as rows and CpGs as columns.
    input_file <- "DNAm_betas_normalized.rds"
    
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    x_test <- readRDS(input_file)
    
    # Ensure x_test is in matrix format as expected by the package
    if (!is.matrix(x_test)) {
      x_test <- as.matrix(x_test)
    }
    
    # 2. Predict preeclampsia status using predictPreeclampsia
    # Keep the documented function call and argument names exactly as shown in the vignette.
    preds <- x_test %>% predictPreeclampsia()
    
    # 3. Save the meaningful results
    # Save predictions as a CSV table
    write.csv(preds, "preeclampsia_predictions.csv", row.names = FALSE)
    
    # Save predictions as an RDS object
    saveRDS(preds, "preeclampsia_predictions.rds")
    
    # 4. Visualize the results and save as PDF
    # Since true class metadata is not provided in the input, we visualize the distribution of predicted probabilities and statuses.
    pdf("preeclampsia_predictions_plots.pdf", width = 8, height = 6)
    
    # Plot 1: Distribution of predicted EOPE probabilities
    p1 <- ggplot(preds, aes(x = EOPE)) +
      geom_histogram(binwidth = 0.05, fill = "skyblue", color = "black", alpha = 0.7) +
      theme_minimal() +
      labs(
        title = "Distribution of Predicted EOPE Probabilities",
        x = "Probability of Early-Onset Preeclampsia (EOPE)",
        y = "Count"
      )
    print(p1)
    
    # Plot 2: Count of predicted PE Statuses
    p2 <- ggplot(preds, aes(x = PE_Status, fill = PE_Status)) +
      geom_bar(alpha = 0.8) +
      scale_fill_manual(values = c("EOPE" = "#E69F00", "Normotensive" = "skyblue", "Non-PE Preterm" = "#999999")) +
      theme_minimal() +
      labs(
        title = "Predicted Preeclampsia Status Counts",
        x = "Predicted Status",
        y = "Count",
        fill = "Status"
      )
    print(p2)
    
    dev.off()

    writeLines(c(
        '"BIOC_PLANET_PREECLAMPSIA_PREDICTION":',
        paste0('    planet: ', as.character(packageVersion('planet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_preeclampsia_prediction.csv versions.yml
    """
}

workflow BIOC_PLANET_PREECLAMPSIA_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DNAm_betas_normalized.rds ] ]

    main:
    BIOC_PLANET_PREECLAMPSIA_PREDICTION(ch_input)

    emit:
    tables   = BIOC_PLANET_PREECLAMPSIA_PREDICTION.out.tables
    plots    = BIOC_PLANET_PREECLAMPSIA_PREDICTION.out.plots
    objects  = BIOC_PLANET_PREECLAMPSIA_PREDICTION.out.objects
    versions = BIOC_PLANET_PREECLAMPSIA_PREDICTION.out.versions
}
