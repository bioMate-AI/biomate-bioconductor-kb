#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phenopath — summarized_experiment_workflow
// Fit the PhenoPath model using a SummarizedExperiment object containing expression data and sample metadata.
// Input: summarized_experiment.rds
// Container: quay.io/biocontainers/bioconductor-phenopath:1.34.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, dplyr, ggplot2, phenopath
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare the SummarizedExperiment object
//  * 2. [Visualization & Output] Fit the PhenoPath model using phenopath() with the SummarizedExperiment and covariate specifications (vector, column name, or form

nextflow.enable.dsl = 2

process BIOC_PHENOPATH_SUMMARIZED_EXPERIMENT_WORKFLOW {
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
    .bm_deps <- c("phenopath", "ggplot2", "dplyr")
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
      library(phenopath)
      library(ggplot2)
      library(dplyr)
    })
    
    # ==========================================
    # 1. Prepare the SummarizedExperiment object
    # ==========================================
    
    # Read the user input file
    sce <- readRDS("summarized_experiment.rds")
    
    # Ensure the assay is named "exprs" as expected by default in phenopath
    if (!"exprs" %in% names(assays(sce))) {
      names(assays(sce))[1] <- "exprs"
    }
    
    # Ensure there is a covariate column named "x" in colData
    if (!"x" %in% colnames(colData(sce))) {
      colData(sce)\$x <- colData(sce)[[1]]
    }
    
    # Create the 'sim' object to match the documented code's use of sim\$x
    sim <- list(x = colData(sce)\$x)
    
    # ==========================================
    # 2. Fit the PhenoPath model
    # ==========================================
    
    # Fit the model using the formula interface
    fit <- phenopath(sce, ~ x)
    
    # ==========================================
    # 3. Save Outputs and Diagnostics
    # ==========================================
    
    # Save the final fit object
    saveRDS(fit, "phenopath_fit.rds")
    
    # Extract and save trajectory (pseudotimes)
    z_est <- trajectory(fit)
    sample_names <- colnames(sce)
    if (is.null(sample_names)) {
      sample_names <- paste0("sample_", seq_along(z_est))
    }
    trajectory_df <- data.frame(
      sample_id = sample_names,
      phenopath_z = z_est
    )
    write.csv(trajectory_df, "trajectory_results.csv", row.names = FALSE)
    
    # Extract and save interaction effects using the robust built-in function
    df_beta <- interactions(fit)
    write.csv(df_beta, "interaction_effects.csv", row.names = FALSE)
    
    # Generate diagnostic plots
    pdf("phenopath_diagnostics.pdf", width = 7, height = 5)
    tryCatch({
      print(plot_elbo(fit))
    }, error = function(e) {
      warning("Could not plot ELBO: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_PHENOPATH_SUMMARIZED_EXPERIMENT_WORKFLOW":',
        paste0('    phenopath: ', as.character(packageVersion('phenopath')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summarized_experiment_workflow.csv versions.yml
    """
}

workflow BIOC_PHENOPATH_SUMMARIZED_EXPERIMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ summarized_experiment.rds ] ]

    main:
    BIOC_PHENOPATH_SUMMARIZED_EXPERIMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_PHENOPATH_SUMMARIZED_EXPERIMENT_WORKFLOW.out.tables
    plots    = BIOC_PHENOPATH_SUMMARIZED_EXPERIMENT_WORKFLOW.out.plots
    objects  = BIOC_PHENOPATH_SUMMARIZED_EXPERIMENT_WORKFLOW.out.objects
    versions = BIOC_PHENOPATH_SUMMARIZED_EXPERIMENT_WORKFLOW.out.versions
}
