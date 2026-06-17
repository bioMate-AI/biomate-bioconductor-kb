#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bayNorm — baynorm_supplementary_generation
// Generate alternative 2D normalized matrices (MAP or mean of posterior) using pre-existing prior parameters estimated from a previous bayNorm run.
// Input: rse, bayNorm_3D
// Container: quay.io/biocontainers/bioconductor-baynorm:1.28.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, SummarizedExperiment, bayNorm
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run bayNorm_sup with mode_version=TRUE to generate a 2D MAP matrix
//  * 2. [Core Analysis] Run bayNorm_sup with mean_version=TRUE to generate a 2D posterior mean matrix

nextflow.enable.dsl = 2

process BIOC_BAYNORM_BAYNORM_SUPPLEMENTARY_GENERATION {
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
    .bm_deps <- c("bayNorm")
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
    library(bayNorm)
    
    # Define input file paths
    rse_path <- "rse.rds"
    bayNorm_3d_path <- "bayNorm_3D.rds"
    
    # Check if input files exist
    if (!file.exists(rse_path)) {
      stop(paste("Required input file missing:", rse_path))
    }
    if (!file.exists(bayNorm_3d_path)) {
      stop(paste("Required input file missing:", bayNorm_3d_path))
    }
    
    # Read user inputs
    rse <- readRDS(rse_path)
    bayNorm_3D <- readRDS(bayNorm_3d_path)
    
    # 1. Run bayNorm_sup with mode_version=TRUE to generate a 2D MAP matrix
    message("Generating 2D MAP normalized matrix...")
    bayNorm_2D_mode <- bayNorm_sup(
        Data=rse,
        PRIORS=bayNorm_3D\$PRIORS,
        input_params=bayNorm_3D\$input_params,
        mode_version=TRUE,
        mean_version = FALSE,
        verbose =FALSE)
    
    # 2. Run bayNorm_sup with mean_version=TRUE to generate a 2D posterior mean matrix
    message("Generating 2D posterior mean normalized matrix...")
    bayNorm_2D_mean <- bayNorm_sup(
        Data=rse,
        PRIORS=bayNorm_3D\$PRIORS,
        input_params=bayNorm_3D\$input_params,
        mode_version=FALSE,
        mean_version = TRUE,
        verbose =FALSE)
    
    # Save RDS outputs
    saveRDS(bayNorm_2D_mode, "bayNorm_2D_mode.rds")
    saveRDS(bayNorm_2D_mean, "bayNorm_2D_mean.rds")
    
    # Export normalized count matrices to CSV
    if (!is.null(bayNorm_2D_mode\$Bay_out)) {
      write.csv(as.matrix(bayNorm_2D_mode\$Bay_out), "bayNorm_2D_mode_counts.csv", row.names = TRUE)
    }
    if (!is.null(bayNorm_2D_mean\$Bay_out)) {
      write.csv(as.matrix(bayNorm_2D_mean\$Bay_out), "bayNorm_2D_mean_counts.csv", row.names = TRUE)
    }
    
    message("Workflow completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_BAYNORM_BAYNORM_SUPPLEMENTARY_GENERATION":',
        paste0('    bayNorm: ', as.character(packageVersion('bayNorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_baynorm_supplementary_generation.csv versions.yml
    """
}

workflow BIOC_BAYNORM_BAYNORM_SUPPLEMENTARY_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rse, bayNorm_3D ] ]

    main:
    BIOC_BAYNORM_BAYNORM_SUPPLEMENTARY_GENERATION(ch_input)

    emit:
    tables   = BIOC_BAYNORM_BAYNORM_SUPPLEMENTARY_GENERATION.out.tables
    plots    = BIOC_BAYNORM_BAYNORM_SUPPLEMENTARY_GENERATION.out.plots
    objects  = BIOC_BAYNORM_BAYNORM_SUPPLEMENTARY_GENERATION.out.objects
    versions = BIOC_BAYNORM_BAYNORM_SUPPLEMENTARY_GENERATION.out.versions
}
