#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: splatter — splat_standard_simulation
// Estimate simulation parameters from an empirical single-cell count matrix and simulate a new synthetic dataset.
// Input: sce, counts
// Container: quay.io/biocontainers/bioconductor-splatter:1.34.0--r45hdfd78af_0
// R packages: SingleCellExperiment, ggplot2, scater, splatter
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scater, splatter
// Visualizations: PCA plot
// QC: diagnostic MA/PCA QC, cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate parameters from real data using splatEstimate. 2. Simulate synthetic counts using splatSimulate

nextflow.enable.dsl = 2

process BIOC_SPLATTER_SPLAT_STANDARD_SIMULATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SingleCellExperiment", "ggplot2", "scater", "splatter")
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
        suppressPackageStartupMessages({
          library(splatter)
          library(scater)
        })
        
        # Set seed for reproducibility
        set.seed(1)
        
        # Read user inputs from the working directory
        sce <- readRDS("sce.rds")
        counts_mat <- readRDS("counts.rds")
        
        # Estimate parameters from real data
        params <- splatEstimate(counts_mat)
        
        # Simulate data using estimated parameters
        sim <- splatSimulate(params)
        
        # Save the simulated SingleCellExperiment object
        saveRDS(sim, "sim.rds")
        
        # Save the estimated parameters
        saveRDS(params, "params.rds")
        
        # Extract and save simulated counts matrix
        sim_counts <- counts(sim)
        write.csv(as.matrix(sim_counts), "sim_counts.csv", row.names = TRUE)
        
        # Generate and save PCA plot of simulated data
        tryCatch({
          sim <- logNormCounts(sim)
          sim <- runPCA(sim)
          pdf("sim_pca.pdf")
          print(plotPCA(sim))
          dev.off()
        }, error = function(e) {
          message("Could not generate PCA plot: ", e\$message)
        })

    writeLines(c(
        '"BIOC_SPLATTER_SPLAT_STANDARD_SIMULATION":',
        paste0('    splatter: ', as.character(packageVersion('splatter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splat_standard_simulation.csv versions.yml
    """
}

workflow BIOC_SPLATTER_SPLAT_STANDARD_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce, counts ] ]

    main:
    BIOC_SPLATTER_SPLAT_STANDARD_SIMULATION(ch_input)

    emit:
    tables   = BIOC_SPLATTER_SPLAT_STANDARD_SIMULATION.out.tables
    plots    = BIOC_SPLATTER_SPLAT_STANDARD_SIMULATION.out.plots
    objects  = BIOC_SPLATTER_SPLAT_STANDARD_SIMULATION.out.objects
    versions = BIOC_SPLATTER_SPLAT_STANDARD_SIMULATION.out.versions
}
