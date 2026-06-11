#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: banocc — compositional_covariance_analysis
// Infer the correlation and covariance of the unconstrained log-basis from compositional data using a Bayesian GLASSO model.
// Input: compositions_null
// Container: quay.io/biocontainers/bioconductor-banocc:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: banocc, rstan
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compile the BAnOCC Stan model
//  * 2. [Core Analysis] Run the MCMC sampler on the compositional data
//  * 3. [Core Analysis] Extract posterior estimates, credible intervals, and
//  * 4. [Core Analysis] Assess model convergence using traceplots and Rhat

nextflow.enable.dsl = 2

process BIOC_BANOCC_COMPOSITIONAL_COVARIANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
        library(banocc)
        library(rstan)
        
        # Read the input file 'compositions_null' from the working directory
        if (file.exists("compositions_null")) {
          df <- read.csv("compositions_null", header = TRUE, check.names = FALSE)
        } else if (file.exists("compositions_null.csv")) {
          df <- read.csv("compositions_null.csv", header = TRUE, check.names = FALSE)
        } else {
          stop("Required input file 'compositions_null' or 'compositions_null.csv' not found in the working directory.")
        }
        
        # If the first column is non-numeric (e.g., sample IDs), set it as row names
        if (!is.numeric(df[[1]])) {
          rownames(df) <- df[[1]]
          df <- df[-1]
        }
        compositions_null <- as.matrix(df)
        
        # Ensure row sums are strictly less than 1 as required by BAnOCC
        row_sums <- rowSums(compositions_null)
        if (any(row_sums >= 1)) {
          # Scale rows down so they sum to 0.95
          compositions_null <- (compositions_null / row_sums) * 0.95
        }
        
        # --- Compile the BAnOCC Stan model ---
        compiled_banocc_model <- rstan::stan_model(model_code = banocc::banocc_model) 
        
        # --- Run the MCMC sampler on the compositional data ---
        b_fit     <- banocc::run_banocc(C = compositions_null, compiled_banocc_model=compiled_banocc_model)
        
        # --- Extract posterior estimates, credible intervals, and ---
        b_output <- banocc::get_banocc_output(banoccfit=b_fit)
        b_out_nec <- banocc::get_banocc_output(banoccfit=b_fit, eval_convergence = FALSE)
        b_out_min_width <- banocc::get_banocc_output(banoccfit=b_fit, get_min_width = TRUE)
        b_out_snc <- banocc::get_banocc_output(banoccfit=b_fit, calc_snc = TRUE)
        
        # --- Assess model convergence using traceplots and Rhat ---
        pdf("traceplot.pdf", width = 10, height = 8)
        if (ncol(compositions_null) >= 2) {
          print(rstan::traceplot(b_fit\$Fit, pars=paste0("O[1,", 2:ncol(compositions_null), "]")))
        }
        dev.off()
        
        rhat_all <- rstan::summary(b_fit\$Fit)\$summary[, "Rhat"]
        
        # Save meaningful results to output files
        saveRDS(b_fit, "banocc_fit.rds")
        saveRDS(b_output, "banocc_output.rds")
        saveRDS(b_out_nec, "banocc_output_no_eval_convergence.rds")
        saveRDS(b_out_min_width, "banocc_output_min_width.rds")
        saveRDS(b_out_snc, "banocc_output_snc.rds")
        
        # Save Rhat statistics
        write.csv(as.data.frame(rhat_all), "rhat_statistics.csv", row.names = TRUE)
        
        # Save median estimates (from the non-evaluated convergence run to ensure values are present)
        if (!is.null(b_out_nec\$Estimates.median)) {
          write.csv(as.data.frame(b_out_nec\$Estimates.median), "estimates_median.csv", row.names = TRUE)
        }

    writeLines(c(
        '"BIOC_BANOCC_COMPOSITIONAL_COVARIANCE_ANALYSIS":',
        paste0('    banocc: ', as.character(packageVersion('banocc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compositional_covariance_analysis.csv versions.yml
    """
}

workflow BIOC_BANOCC_COMPOSITIONAL_COVARIANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ compositions_null ] ]

    main:
    BIOC_BANOCC_COMPOSITIONAL_COVARIANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BANOCC_COMPOSITIONAL_COVARIANCE_ANALYSIS.out.tables
    plots    = BIOC_BANOCC_COMPOSITIONAL_COVARIANCE_ANALYSIS.out.plots
    objects  = BIOC_BANOCC_COMPOSITIONAL_COVARIANCE_ANALYSIS.out.objects
    versions = BIOC_BANOCC_COMPOSITIONAL_COVARIANCE_ANALYSIS.out.versions
}
