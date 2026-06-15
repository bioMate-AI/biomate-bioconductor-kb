#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: wpm — summarized_experiment_to_plate_map
// Generate and visualize a randomized well-plate map starting from a SummarizedExperiment object.
// Input: se
// Container: quay.io/biocontainers/bioconductor-wpm:1.20.0--r45hdfd78af_0
// R packages: ggplot2, wpm
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ggplot2, wpm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Convert the SummarizedExperiment object into the WPM-compatible format using convertSE
//  * 2. [Core Analysis] Run the backtracking randomization algorithm using wrapperWPM
//  * 3. [Visualization & Output] Visualize the generated plate map using drawMap

nextflow.enable.dsl = 2

process BIOC_WPM_SUMMARIZED_EXPERIMENT_TO_PLATE_MAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("ggplot2", "wpm", "SummarizedExperiment")
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
    library(wpm)
    library(SummarizedExperiment)
    library(ggplot2)
    
    # Read the user input file 'se' from the working directory
    if (file.exists("se")) {
      se <- readRDS("se")
    } else if (file.exists("se.rds")) {
      se <- readRDS("se.rds")
    } else {
      stop("Error: Input file 'se' or 'se.rds' not found in the working directory.")
    }
    
    # Extract colData from the SummarizedExperiment object
    colData <- SummarizedExperiment::colData(se)
    
    # Dynamically determine the grouping variable (use the first column of colData)
    group_var <- colnames(colData)[1]
    
    # Determine appropriate plate dimensions for the number of samples to fit in 1 plate
    n_samples <- nrow(colData)
    if (n_samples <= 6) {
      p_lines <- 2; p_cols <- 3
    } else if (n_samples <= 24) {
      p_lines <- 4; p_cols <- 6
    } else if (n_samples <= 48) {
      p_lines <- 6; p_cols <- 8
    } else if (n_samples <= 96) {
      p_lines <- 8; p_cols <- 12
    } else if (n_samples <= 384) {
      p_lines <- 16; p_cols <- 24
    } else if (n_samples <= 1536) {
      p_lines <- 32; p_cols <- 48
    } else {
      p_cols <- ceiling(sqrt(n_samples))
      p_lines <- ceiling(n_samples / p_cols)
    }
    
    # Stage 1: Convert the SummarizedExperiment object into the WPM-compatible format
    df <- wpm::convertSE(se, group_var)
    
    # Stage 2: Run the backtracking randomization algorithm
    wpm_result <- wpm::wrapperWPM(user_df = df,
                plate_dims = list(p_lines, p_cols),
                nb_plates = 1,
                spatial_constraint = "NS")
    
    # Stage 3: Visualize the generated plate map
    drawned_map <- wpm::drawMap(df = wpm_result,
            sample_gps = length(levels(as.factor(colData[[group_var]]))),
            gp_levels = levels(as.factor(colData[[group_var]])),
            plate_lines = p_lines,
            plate_cols = p_cols,
            project_title = "my Project Title")
    
    # Write named output files for the results
    write.csv(wpm_result, "wpm_result.csv", row.names = FALSE)
    saveRDS(wpm_result, "wpm_result.rds")
    
    ggplot2::ggsave(
        filename = "plate_map.pdf",
        plot = drawned_map,
        width = 10,
        height = 7,
        units = "in"
    )

    writeLines(c(
        '"BIOC_WPM_SUMMARIZED_EXPERIMENT_TO_PLATE_MAP":',
        paste0('    wpm: ', as.character(packageVersion('wpm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summarized_experiment_to_plate_map.csv versions.yml
    """
}

workflow BIOC_WPM_SUMMARIZED_EXPERIMENT_TO_PLATE_MAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ se ] ]

    main:
    BIOC_WPM_SUMMARIZED_EXPERIMENT_TO_PLATE_MAP(ch_input)

    emit:
    tables   = BIOC_WPM_SUMMARIZED_EXPERIMENT_TO_PLATE_MAP.out.tables
    plots    = BIOC_WPM_SUMMARIZED_EXPERIMENT_TO_PLATE_MAP.out.plots
    objects  = BIOC_WPM_SUMMARIZED_EXPERIMENT_TO_PLATE_MAP.out.objects
    versions = BIOC_WPM_SUMMARIZED_EXPERIMENT_TO_PLATE_MAP.out.versions
}
