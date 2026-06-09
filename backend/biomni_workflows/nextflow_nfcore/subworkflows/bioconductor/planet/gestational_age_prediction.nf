#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: planet — gestational_age_prediction
// Predict gestational age from placental DNA methylation data using three specialized placental epigenetic clocks.
// Input: DNAm_betas.rds, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-planet:1.18.0--r45hdfd78af_0
// Requires: dplyr, ggplot2, planet, tidyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Predict gestational age using predictAge with the "RPC", "CPC", and "RRPC" clock types
//  * 2. [Core Analysis] Append the predicted values to the sample metadata

nextflow.enable.dsl = 2

process BIOC_PLANET_GESTATIONAL_AGE_PREDICTION {
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
    
    # 1. Read the declared user input files
    # DNAm_betas.rds: matrix of DNA methylation beta values with CpGs as rows and samples as columns
    plBetas <- readRDS("DNAm_betas.rds")
    
    # sample_metadata.csv: sample information data frame
    plPhenoData <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
    
    # 2. Predict gestational age using predictAge with the "RPC", "CPC", and "RRPC" clock types
    # and append the predicted values to the sample metadata.
    plPhenoData <- plPhenoData %>%
      mutate(
        ga_RPC = predictAge(plBetas, type = "RPC"),
        ga_CPC = predictAge(plBetas, type = "CPC"),
        ga_RRPC = predictAge(plBetas, type = "RRPC")
      )
    
    # 3. Write named output files for the meaningful results
    # Save the updated metadata with predictions as CSV and RDS
    write.csv(plPhenoData, "predicted_gestational_age.csv", row.names = FALSE)
    saveRDS(plPhenoData, "predicted_gestational_age.rds")
    
    # Generate and save diagnostic plots
    pdf("gestational_age_predictions_plot.pdf", width = 8, height = 6)
    
    # Check if reported gestational age is available in the metadata to plot correlation
    if ("gestation_wk" %in% colnames(plPhenoData)) {
      plot_data <- plPhenoData %>%
        pivot_longer(
          cols = c("ga_RPC", "ga_CPC", "ga_RRPC"),
          names_to = "clock_type",
          names_prefix = "ga_",
          values_to = "ga"
        )
      
      # Determine if disease status is available for coloring
      color_aes <- if ("disease" %in% colnames(plPhenoData)) aes(x = gestation_wk, y = ga, col = disease) else aes(x = gestation_wk, y = ga)
      
      p <- ggplot(plot_data, color_aes) +
        geom_point() +
        geom_smooth(method = "lm", se = FALSE, color = "black", linetype = "dashed") +
        facet_wrap(~ clock_type) +
        theme_bw() +
        theme(legend.position = "top") +
        labs(
          x = "Reported GA (weeks)",
          y = "Inferred GA (weeks)",
          title = "Comparison of Placental Epigenetic Clocks",
          col = "Group"
        )
      print(p)
    } else {
      # If reported GA is not available, plot the distribution of predictions across clocks
      plot_data <- plPhenoData %>%
        pivot_longer(
          cols = c("ga_RPC", "ga_CPC", "ga_RRPC"),
          names_to = "clock_type",
          names_prefix = "ga_",
          values_to = "ga"
        )
      
      p <- ggplot(plot_data, aes(x = clock_type, y = ga, fill = clock_type)) +
        geom_boxplot(alpha = 0.7) +
        geom_jitter(width = 0.1, alpha = 0.5) +
        theme_bw() +
        theme(legend.position = "none") +
        labs(
          x = "Clock Type",
          y = "Inferred GA (weeks)",
          title = "Distribution of Predicted Gestational Age"
        )
      print(p)
    }
    
    dev.off()

    writeLines(c(
        '"BIOC_PLANET_GESTATIONAL_AGE_PREDICTION":',
        paste0('    planet: ', as.character(packageVersion('planet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gestational_age_prediction.csv versions.yml
    """
}

workflow BIOC_PLANET_GESTATIONAL_AGE_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DNAm_betas.rds, sample_metadata.csv ] ]

    main:
    BIOC_PLANET_GESTATIONAL_AGE_PREDICTION(ch_input)

    emit:
    tables   = BIOC_PLANET_GESTATIONAL_AGE_PREDICTION.out.tables
    plots    = BIOC_PLANET_GESTATIONAL_AGE_PREDICTION.out.plots
    objects  = BIOC_PLANET_GESTATIONAL_AGE_PREDICTION.out.objects
    versions = BIOC_PLANET_GESTATIONAL_AGE_PREDICTION.out.versions
}
