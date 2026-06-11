#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scMET — differential_methylation_analysis
// Perform differential methylation (DM) and differential variability (DV) testing between two cell populations.
// Input: group_A_methylation.csv, group_B_methylation.csv, group_A_covariates.csv, group_B_covariates.csv
// Container: quay.io/biocontainers/bioconductor-scmet:1.12.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: data.table, scMET
// Visualizations: volcano plot, MA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run Bayesian inference independently for Group A using scmet
//  * 2. [Core Analysis] Run Bayesian inference independently for Group B using scmet
//  * 3. [Core Analysis] Perform differential testing using scmet_differential
//  * 4. [Visualization & Output] Plot differential results using scmet_plot_efdr_efnr_grid, scmet_plot_volcano, and scmet_plot_ma

nextflow.enable.dsl = 2

process BIOC_SCMET_DIFFERENTIAL_METHYLATION_ANALYSIS {
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
    suppressPackageStartupMessages(library(scMET))
    suppressPackageStartupMessages(library(data.table))
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read Group A methylation data
    if (!file.exists("group_A_methylation.csv")) {
      stop("Error: group_A_methylation.csv not found in the working directory.")
    }
    Y_A <- data.table::fread("group_A_methylation.csv")
    
    # Read Group B methylation data
    if (!file.exists("group_B_methylation.csv")) {
      stop("Error: group_B_methylation.csv not found in the working directory.")
    }
    Y_B <- data.table::fread("group_B_methylation.csv")
    
    # Read Group A covariates (optional)
    if (file.exists("group_A_covariates.csv")) {
      X_A_df <- read.csv("group_A_covariates.csv", row.names = 1)
      X_A <- as.matrix(X_A_df)
    } else {
      X_A <- NULL
    }
    
    # Read Group B covariates (optional)
    if (file.exists("group_B_covariates.csv")) {
      X_B_df <- read.csv("group_B_covariates.csv", row.names = 1)
      X_B <- as.matrix(X_B_df)
    } else {
      X_B <- NULL
    }
    
    # Construct the scmet_diff_dt structure to match the documented code
    scmet_diff_dt <- list(
      scmet_dt_A = list(Y = Y_A, X = X_A),
      scmet_dt_B = list(Y = Y_B, X = X_B)
    )
    
    # ==========================================
    # 2. Run Bayesian Inference Independently
    # ==========================================
    
    # Run scMET for Group A
    fit_A <- scmet(Y = scmet_diff_dt\$scmet_dt_A\$Y, X = scmet_diff_dt\$scmet_dt_A\$X, L = 4, iter = 20000, seed = 12)
    
    # Run scMET for Group B
    fit_B <- scmet(Y = scmet_diff_dt\$scmet_dt_B\$Y, X = scmet_diff_dt\$scmet_dt_B\$X, L = 4, iter = 20000, seed = 12)
    
    # ==========================================
    # 3. Perform Differential Testing
    # ==========================================
    
    diff_obj <- scmet_differential(obj_A = fit_A, obj_B = fit_B, evidence_thresh_m = 0.65, evidence_thresh_e = 0.65, group_label_A = "A", group_label_B = "B")
    
    # ==========================================
    # 4. Plot Differential Results
    # ==========================================
    
    # Save EFDR/EFNR grid plots
    pdf("efdr_efnr_grid_plots.pdf", width = 10, height = 5)
    gg1 <- scmet_plot_efdr_efnr_grid(obj = diff_obj, task = "diff_mu")
    gg2 <- scmet_plot_efdr_efnr_grid(obj = diff_obj, task = "diff_epsilon")
    if (inherits(gg1, "ggplot")) print(gg1)
    if (inherits(gg2, "ggplot")) print(gg2)
    dev.off()
    
    # Save Volcano plots
    pdf("volcano_plots.pdf", width = 8, height = 6)
    gg1 <- scmet_plot_volcano(diff_obj, task = "diff_mu")
    gg2 <- scmet_plot_volcano(diff_obj, task = "diff_epsilon")
    if (inherits(gg1, "ggplot")) print(gg1)
    if (inherits(gg2, "ggplot")) print(gg2)
    dev.off()
    
    # Save MA plots
    pdf("ma_plots.pdf", width = 10, height = 5)
    gg1 <- scmet_plot_ma(diff_obj, task = "diff_mu", x = "mu")
    gg2 <- scmet_plot_ma(diff_obj, task = "diff_epsilon", x = "mu")
    if (inherits(gg1, "ggplot")) print(gg1)
    if (inherits(gg2, "ggplot")) print(gg2)
    dev.off()
    
    # ==========================================
    # 5. Save Outputs to Files
    # ==========================================
    
    # Save RDS objects for downstream analysis
    saveRDS(fit_A, "fit_A.rds")
    saveRDS(fit_B, "fit_B.rds")
    saveRDS(diff_obj, "diff_obj.rds")
    
    # Save tabular summaries
    if (!is.null(diff_obj\$diff_mu_summary)) {
      write.csv(diff_obj\$diff_mu_summary, "diff_mu_summary.csv", row.names = FALSE)
    }
    if (!is.null(diff_obj\$diff_epsilon_summary)) {
      write.csv(diff_obj\$diff_epsilon_summary, "diff_epsilon_summary.csv", row.names = FALSE)
    }
    if (!is.null(diff_obj\$diff_gamma_summary)) {
      write.csv(diff_obj\$diff_gamma_summary, "diff_gamma_summary.csv", row.names = FALSE)
    }
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SCMET_DIFFERENTIAL_METHYLATION_ANALYSIS":',
        paste0('    scMET: ', as.character(packageVersion('scMET')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_SCMET_DIFFERENTIAL_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ group_A_methylation.csv, group_B_methylation.csv, group_A_covariates.csv, group_B_covariates.csv ] ]

    main:
    BIOC_SCMET_DIFFERENTIAL_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCMET_DIFFERENTIAL_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_SCMET_DIFFERENTIAL_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_SCMET_DIFFERENTIAL_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_SCMET_DIFFERENTIAL_METHYLATION_ANALYSIS.out.versions
}
