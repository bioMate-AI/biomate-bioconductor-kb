#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: splatter — compare_and_diff_simulations
// Compare simulated datasets with each other or against a real reference dataset to evaluate simulation quality.
// Input: sim1, sim2
// Container: quay.io/biocontainers/bioconductor-splatter:1.34.0--r45hdfd78af_0
// R packages: SingleCellExperiment, cowplot, splatter
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, cowplot, splatter
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read user input files from the working directory
//  * 2. [Core Analysis] Combine and compare datasets using compareSCEs
//  * 3. [Core Analysis] Calculate differences relative to a reference dataset
//  * 4. [Core Analysis] Write meaningful output files

nextflow.enable.dsl = 2

process BIOC_SPLATTER_COMPARE_AND_DIFF_SIMULATIONS {
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
    .bm_deps <- c("SingleCellExperiment", "cowplot", "splatter")
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
    library(splatter)
    library(cowplot)
    
    # --- Read user input files from the working directory ---
    # The pipeline expects 'sim1.rds' and 'sim2.rds' containing SingleCellExperiment objects
    sim1 <- readRDS("sim1.rds")
    sim2 <- readRDS("sim2.rds")
    
    # --- Combine and compare datasets using compareSCEs ---
    comparison <- compareSCEs(list(Splat = sim1, Simple = sim2))
    
    # --- Calculate differences relative to a reference dataset ---
    difference <- diffSCEs(list(Splat = sim1, Simple = sim2), ref = "Simple")
    
    # --- Write meaningful output files ---
    # Save the raw comparison and difference list objects
    saveRDS(comparison, "comparison.rds")
    saveRDS(difference, "difference.rds")
    
    # Save tabular results as CSV files
    write.csv(as.data.frame(comparison\$RowData), "comparison_RowData.csv", row.names = FALSE)
    write.csv(as.data.frame(comparison\$ColData), "comparison_ColData.csv", row.names = FALSE)
    write.csv(as.data.frame(difference\$RowData), "difference_RowData.csv", row.names = FALSE)
    write.csv(as.data.frame(difference\$ColData), "difference_ColData.csv", row.names = FALSE)
    
    # Generate and save visualization panels
    comp_panel <- makeCompPanel(comparison)
    cowplot::save_plot("comp_panel.png", comp_panel, nrow = 4, ncol = 3)
    
    diff_panel <- makeDiffPanel(difference)
    cowplot::save_plot("diff_panel.png", diff_panel, nrow = 3, ncol = 5)

    writeLines(c(
        '"BIOC_SPLATTER_COMPARE_AND_DIFF_SIMULATIONS":',
        paste0('    splatter: ', as.character(packageVersion('splatter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_and_diff_simulations.csv versions.yml
    """
}

workflow BIOC_SPLATTER_COMPARE_AND_DIFF_SIMULATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sim1, sim2 ] ]

    main:
    BIOC_SPLATTER_COMPARE_AND_DIFF_SIMULATIONS(ch_input)

    emit:
    tables   = BIOC_SPLATTER_COMPARE_AND_DIFF_SIMULATIONS.out.tables
    plots    = BIOC_SPLATTER_COMPARE_AND_DIFF_SIMULATIONS.out.plots
    objects  = BIOC_SPLATTER_COMPARE_AND_DIFF_SIMULATIONS.out.objects
    versions = BIOC_SPLATTER_COMPARE_AND_DIFF_SIMULATIONS.out.versions
}
