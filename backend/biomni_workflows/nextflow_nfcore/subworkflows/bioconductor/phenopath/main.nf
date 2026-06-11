#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phenopath — standard_matrix_workflow
// Fit the PhenoPath model using a gene expression matrix and a covariate vector to infer pseudotimes and identify significant gene-covariate interactions.
// Input: expression_matrix.csv, covariates.csv
// Container: quay.io/biocontainers/bioconductor-phenopath:1.34.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, phenopath
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the PhenoPath model using phenopath()
//  * 2. [Visualization & Output] Check model convergence using plot_elbo()
//  * 3. [Core Analysis] Extract the latent trajectory (pseudotimes) using trajectory()
//  * 4. [Core Analysis] Retrieve interaction effects, standard deviations, and significance using interaction_effects(), interaction_sds(), and significan

nextflow.enable.dsl = 2

process BIOC_PHENOPATH_STANDARD_MATRIX_WORKFLOW {
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
    suppressPackageStartupMessages({
      library(phenopath)
      library(dplyr)
      library(ggplot2)
    })
    
    # 1. Read User Inputs
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: expression_matrix.csv not found in the working directory.")
    }
    if (!file.exists("covariates.csv")) {
      stop("Error: covariates.csv not found in the working directory.")
    }
    
    # Read expression matrix (samples as rows, genes as columns)
    expression_matrix <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    sim_y <- as.matrix(expression_matrix)
    
    # Read covariates
    covariates_df <- read.csv("covariates.csv", row.names = 1, check.names = FALSE)
    
    # Extract covariate vector/matrix 'x'
    if ("x" %in% colnames(covariates_df)) {
      sim_x <- covariates_df\$x
    } else {
      sim_x <- covariates_df[, 1]
    }
    
    # Extract or approximate true/reference pseudotime 'z' for the correlation step
    if ("z" %in% colnames(covariates_df)) {
      sim_z <- covariates_df\$z
    } else if ("pseudotime" %in% colnames(covariates_df)) {
      sim_z <- covariates_df\$pseudotime
    } else {
      # Fallback: use the first principal component as a proxy for reference z
      pca <- prcomp(sim_y, scale. = TRUE)
      sim_z <- pca\$x[, 1]
    }
    
    # Construct the 'sim' object to match the documented code's variable names
    sim <- list(
      y = sim_y,
      x = sim_x,
      z = sim_z
    )
    
    # 2. Fit the PhenoPath model
    fit <- phenopath(sim\$y, sim\$x, elbo_tol = 1e-6, thin = 40)
    print(fit)
    
    # Save the fit object
    saveRDS(fit, "phenopath_fit.rds")
    
    # 3. Check model convergence
    pdf("elbo_convergence.pdf", width = 6, height = 4)
    p_elbo <- plot_elbo(fit)
    print(p_elbo)
    dev.off()
    
    # 4. Extract the latent trajectory (pseudotimes)
    inferred_trajectory <- trajectory(fit)
    trajectory_df <- data.frame(
      sample = rownames(sim\$y),
      inferred_pseudotime = inferred_trajectory
    )
    write.csv(trajectory_df, "inferred_trajectory.csv", row.names = FALSE)
    
    # 5. Compute correlation with reference z
    z_corr <- cor(sim\$z, trajectory(fit))
    cat("Correlation between reference z and inferred trajectory:", z_corr, "\n")
    writeLines(as.character(z_corr), "trajectory_correlation.txt")
    
    # 6. Retrieve interaction effects, standard deviations, and significance
    gene_names <- paste0("gene", seq_len(ncol(fit\$m_beta)))
    df_beta <- data_frame(beta = interaction_effects(fit),
                          beta_sd = interaction_sds(fit),
                          is_sig = significant_interactions(fit),
                          gene = gene_names)
    
    # Map back actual gene names if available
    if (!is.null(colnames(sim\$y))) {
      df_beta\$actual_gene_name <- colnames(sim\$y)
    }
    
    write.csv(df_beta, "interaction_effects.csv", row.names = FALSE)
    
    # Plot interaction effects
    pdf("interaction_effects.pdf", width = 8, height = 6)
    p_beta <- ggplot(df_beta, aes(x = gene, y = beta, color = is_sig)) +
      geom_point() +
      geom_errorbar(aes(ymin = beta - 2 * beta_sd, ymax = beta + 2 * beta_sd)) +
      theme(axis.text.x = element_text(angle = 90, hjust = 1),
            axis.title.x = element_blank()) +
      ylab(expression(beta)) +
      scale_color_brewer(palette = "Set2", name = "Significant")
    print(p_beta)
    dev.off()

    writeLines(c(
        '"BIOC_PHENOPATH_STANDARD_MATRIX_WORKFLOW":',
        paste0('    phenopath: ', as.character(packageVersion('phenopath')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_matrix_workflow.csv versions.yml
    """
}

workflow BIOC_PHENOPATH_STANDARD_MATRIX_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, covariates.csv ] ]

    main:
    BIOC_PHENOPATH_STANDARD_MATRIX_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_PHENOPATH_STANDARD_MATRIX_WORKFLOW.out.tables
    plots    = BIOC_PHENOPATH_STANDARD_MATRIX_WORKFLOW.out.plots
    objects  = BIOC_PHENOPATH_STANDARD_MATRIX_WORKFLOW.out.objects
    versions = BIOC_PHENOPATH_STANDARD_MATRIX_WORKFLOW.out.versions
}
