#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MOFA2 — mefisto_covariate_analysis
// Train a covariate-aware factor model (MEFISTO) to capture smooth variation along a continuous covariate (e.g., time) and interpolate factors.
// Input: dd$data, time
// Container: quay.io/biocontainers/bioconductor-mofa2:1.20.2--r45h9ee0642_0
// R packages: MOFA2, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: MOFA2, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Create MOFA object using create_mofa. 2. Set covariates using set_covariates. 3. Define data, model, training, and MEFISTO options

nextflow.enable.dsl = 2

process BIOC_MOFA2_MEFISTO_COVARIATE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("MOFA2", "ggplot2")
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
            library(MOFA2)
            library(ggplot2)
            
            # Check for required input files in the working directory
            if (!file.exists("dd_data.rds") || !file.exists("time.rds")) {
              stop("Required input files 'dd_data.rds' and/or 'time.rds' are missing from the working directory.")
            }
            
            # Read user inputs
            dd <- list()
            dd\$data <- readRDS("dd_data.rds")
            time <- readRDS("time.rds")
            rownames(time) <- "time"
            
            # Set up PDF device to capture all plots
            pdf("mefisto_analysis_plots.pdf", width = 8, height = 6)
            
            # 1. Create MOFA object
            sm <- create_mofa(data = dd\$data)
            
            # 2. Set covariates
            sm <- set_covariates(sm, covariates = time)
            
            # 3. Define options
            data_opts <- get_default_data_options(sm)
            model_opts <- get_default_model_options(sm)
            model_opts\$num_factors <- 4
            train_opts <- get_default_training_options(sm)
            train_opts\$maxiter <- 100
            mefisto_opts <- get_default_mefisto_options(sm)
            
            # 4. Prepare and train the model
            sm <- prepare_mofa(sm, model_options = model_opts, mefisto_options = mefisto_opts, training_options = train_opts, data_options = data_opts)
            outfile = file.path(tempdir(),"model.hdf5")
            sm <- run_mofa(sm, outfile, use_basilisk = TRUE)
            
            # 5. Downstream analysis and visualization
            print(plot_variance_explained(sm))
            r <- plot_factor_cor(sm)
            
            # Save factor correlation matrix
            saveRDS(r, "factor_correlation_matrix.rds")
            
            # Get and save scale parameters
            scales_val <- get_scales(sm)
            write.csv(as.data.frame(scales_val), "scales.csv", row.names = TRUE)
            
            # Relate factors to covariates
            print(plot_factors_vs_cov(sm, color_by = "time"))
            df <- plot_factors_vs_cov(sm, color_by = "time", legend = FALSE, return_data = TRUE)
            write.csv(df, "factors_vs_cov_data.csv", row.names = FALSE)
            
            # Exploration of weights and data vs covariates
            print(plot_weights(sm, factors = 4, view = 1))
            print(plot_top_weights(sm, factors = 3, view = 1))
            print(plot_data_vs_cov(sm, factor=3, features = 2, color_by = "time", dot_size = 1))
            
            # Interpolation
            time_min <- min(time, na.rm = TRUE)
            time_max <- max(time, na.rm = TRUE)
            sm <- interpolate_factors(sm, new_values = seq(time_min, time_max + 0.1 * (time_max - time_min), length.out = 111))
            print(plot_interpolation_vs_covariate(sm, covariate = "time", factors = "Factor3"))
            
            # Close PDF device
            dev.off()
            
            # Save the final trained MOFA object
            saveRDS(sm, "mefisto_model.rds")

    writeLines(c(
        '"BIOC_MOFA2_MEFISTO_COVARIATE_ANALYSIS":',
        paste0('    MOFA2: ', as.character(packageVersion('MOFA2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mefisto_covariate_analysis.csv versions.yml
    """
}

workflow BIOC_MOFA2_MEFISTO_COVARIATE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dd$data, time ] ]

    main:
    BIOC_MOFA2_MEFISTO_COVARIATE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MOFA2_MEFISTO_COVARIATE_ANALYSIS.out.tables
    plots    = BIOC_MOFA2_MEFISTO_COVARIATE_ANALYSIS.out.plots
    objects  = BIOC_MOFA2_MEFISTO_COVARIATE_ANALYSIS.out.objects
    versions = BIOC_MOFA2_MEFISTO_COVARIATE_ANALYSIS.out.versions
}
