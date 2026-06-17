#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: planet — ethnicity_prediction
// Predict donor ethnicity (African, Asian, Caucasian) from placental DNA methylation data.
// Input: DNAm_betas.rds
// Container: quay.io/biocontainers/bioconductor-planet:1.18.0--r45hdfd78af_0
// R packages: dplyr, ggplot2, planet, tidyr
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, planet, scales, tidyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Verify that the required ethnicity CpGs are present in the dataset
//  * 2. [Core Analysis] Predict ethnicity using predictEthnicity

nextflow.enable.dsl = 2

process BIOC_PLANET_ETHNICITY_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("dplyr", "ggplot2", "planet", "tidyr")
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
    library(planet)
    library(dplyr)
    library(ggplot2)
    library(tidyr)
    
    # 1. Read User Input
    input_file <- "DNAm_betas.rds"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    plBetas <- readRDS(input_file)
    
    # 2. Verify that the required ethnicity CpGs are present in the dataset
    ethnicityCpGs <- planet::ethnicityCpGs
    cpgs_present <- all(ethnicityCpGs %in% rownames(plBetas))
    
    # Log verification result
    message("Verification: All required ethnicity CpGs present in input data: ", cpgs_present)
    
    # 3. Predict ethnicity using predictEthnicity
    results <- predictEthnicity(plBetas)
    
    # 4. Write named output files
    # Save predictions as CSV and RDS
    write.csv(results, "ethnicity_predictions.csv", row.names = FALSE)
    saveRDS(results, "ethnicity_predictions.rds")
    
    # Generate and save diagnostic plots to PDF
    pdf("ethnicity_plots.pdf", width = 7, height = 6)
    
    # Plot 1: Caucasian vs African probabilities
    p1 <- results %>%
      ggplot(aes(
        x = Prob_Caucasian, y = Prob_African,
        col = Predicted_ethnicity
      )) +
      geom_point(alpha = 0.7) +
      coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
      scale_x_continuous(labels = scales::percent) +
      scale_y_continuous(labels = scales::percent) +
      labs(
        x = "P(Caucasian)", 
        y = "P(African)", 
        title = "Predicted Ethnicity: Caucasian vs African Probability"
      ) +
      theme_minimal()
    print(p1)
    
    # Plot 2: Caucasian vs Asian probabilities
    p2 <- results %>%
      ggplot(aes(
        x = Prob_Caucasian, y = Prob_Asian,
        col = Predicted_ethnicity
      )) +
      geom_point(alpha = 0.7) +
      coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
      scale_x_continuous(labels = scales::percent) +
      scale_y_continuous(labels = scales::percent) +
      labs(
        x = "P(Caucasian)", 
        y = "P(Asian)", 
        title = "Predicted Ethnicity: Caucasian vs Asian Probability"
      ) +
      theme_minimal()
    print(p2)
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'ethnicity_predictions.csv', 'ethnicity_predictions.rds', and 'ethnicity_plots.pdf'.")

    writeLines(c(
        '"BIOC_PLANET_ETHNICITY_PREDICTION":',
        paste0('    planet: ', as.character(packageVersion('planet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ethnicity_prediction.csv versions.yml
    """
}

workflow BIOC_PLANET_ETHNICITY_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DNAm_betas.rds ] ]

    main:
    BIOC_PLANET_ETHNICITY_PREDICTION(ch_input)

    emit:
    tables   = BIOC_PLANET_ETHNICITY_PREDICTION.out.tables
    plots    = BIOC_PLANET_ETHNICITY_PREDICTION.out.plots
    objects  = BIOC_PLANET_ETHNICITY_PREDICTION.out.objects
    versions = BIOC_PLANET_ETHNICITY_PREDICTION.out.versions
}
