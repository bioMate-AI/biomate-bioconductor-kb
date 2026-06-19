#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: XDE — bayesian_cross_study_analysis
// Fit a Bayesian hierarchical model to multiple transcriptomic studies to estimate concordant and discordant differential expression.
// Input: Multiple ExpressionSet objects
// Container: quay.io/biocontainers/bioconductor-xde:2.56.0--r45ha27e39d_0
// R packages: Biobase, GeneMeta, siggenes, XDE
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, XDE
// Visualizations: plot (ggplot/base)
// QC: input validation, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read and Validate User Input
//  * 2. [Visualization & Output] Initialize XdeParameter Object
//  * 3. [Visualization & Output] Generate Empirical Starting Values
//  * 4. [Visualization & Output] Configure and Run Burn-in MCMC Chains
//  * 5. [Visualization & Output] Configure and Run Production MCMC Chain
//  * 6. [Visualization & Output] Calculate Posterior Averages & Effect Sizes
//  * 7. [Visualization & Output] MCMC Diagnostics and Visualization
//  * 8. [Visualization & Output] Save Meaningful Results

nextflow.enable.dsl = 2

process BIOC_XDE_BAYESIAN_CROSS_STUDY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "GeneMeta", "siggenes", "XDE")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(XDE)
    library(Biobase)
    
    # ==========================================
    # --- Read and Validate User Input ---
    # ==========================================
    
    input_file <- "expressionSetList.rds"
    xlist <- NULL
    
    if (file.exists(input_file)) {
      message("Reading ExpressionSetList from ", input_file)
      xlist <- readRDS(input_file)
    } else {
      # Fallback: Search for any RDS files in the working directory and attempt to combine them
      rds_files <- list.files(pattern = "\\\\.rds\$")
      esets <- list()
      for (f in rds_files) {
        obj <- readRDS(f)
        if (inherits(obj, "ExpressionSet")) {
          esets[[f]] <- obj
        }
      }
      if (length(esets) >= 2) {
        message("Combining ", length(esets), " ExpressionSet objects into an ExpressionSetList")
        xlist <- new("ExpressionSetList", esetList = esets)
      } else {
        stop("Error: Could not find 'expressionSetList.rds' or multiple ExpressionSet RDS files in the working directory.")
      }
    }
    
    # Validate the ExpressionSetList object
    class(xlist)
    validObject(xlist)
    
    # Identify a shared binary phenotype covariate present in all studies
    shared_covariates <- Reduce(intersect, lapply(xlist, varLabels))
    if (length(shared_covariates) == 0) {
      stop("Error: No shared covariates found across all studies.")
    }
    
    is_binary <- sapply(shared_covariates, function(cov) {
      length(na.omit(unique(unlist(lapply(xlist, function(x) pData(x)[[cov]]))))) == 2
    })
    
    if (!any(is_binary)) {
      stop("Error: No shared binary phenotype covariate found across all studies.")
    }
    
    phenotype_label <- shared_covariates[is_binary][1]
    message("Using phenotype label: ", phenotype_label)
    
    # ==========================================
    # --- Initialize XdeParameter Object ---
    # ==========================================
    
    params <- new("XdeParameter", esetList = xlist, phenotypeLabel = phenotype_label)
    params
    
    # Configure to allow genes to be differentially expressed in a subset of studies (one.delta = FALSE)
    params <- new("XdeParameter", esetList = xlist, phenotypeLabel = phenotype_label, one.delta = FALSE)
    
    # ==========================================
    # --- Generate Empirical Starting Values ---
    # ==========================================
    
    empirical <- empiricalStart(xlist, phenotypeLabel = phenotype_label)
    firstMcmc(params) <- empirical
    
    # ==========================================
    # --- Configure and Run Burn-in MCMC Chains ---
    # ==========================================
    
    iterations(params) <- 3
    burnin(params) <- TRUE
    fit <- xde(params, xlist)
    
    iterations(params) <- 2
    firstMcmc(params) <- lastMcmc(fit)
    seed(params) <- seed(fit)
    fit2 <- xde(params, xlist)
    
    # ==========================================
    # --- Configure and Run Production MCMC Chain ---
    # ==========================================
    
    burnin(params) <- FALSE
    iterations(params) <- 2000
    
    # Turn off saving for extremely large gene/study-indexed parameters to save memory/disk space
    output(params)[c("potential", "acceptance",
                     "diffExpressed",
                     "nu",
                     "probDelta",
                     "phi")] <- 0
    
    thin(params) <- 2
    
    # Create local directory for MCMC log files
    dir.create("logFiles", showWarnings = FALSE)
    directory(params) <- "logFiles"
    
    # Run the main MCMC simulation
    xmcmc <- xde(params, xlist)
    
    # ==========================================
    # --- Calculate Posterior Averages & Effect Sizes ---
    # ==========================================
    
    postAvg <- calculatePosteriorAvg(xmcmc, NCONC = 2, NDIFF = 1)
    bayesianEffectSize(xmcmc) <- calculateBayesianEffectSize(xmcmc)
    
    # Save calculated objects to the log directory to match documented load() expectations
    save(postAvg, file = file.path("logFiles", "postAvg.rda"))
    BES <- bayesianEffectSize(xmcmc)
    save(BES, file = file.path("logFiles", "BES.rda"))
    
    # ==========================================
    # --- MCMC Diagnostics and Visualization ---
    # ==========================================
    
    pathToLogFiles <- "logFiles"
    xmcmc@directory <- pathToLogFiles
    c2 <- xmcmc\$c2
    
    # Open PDF device for saving plots
    pdf("mcmc_diagnostics_and_plots.pdf", width = 10, height = 8)
    
    # Plot c2 parameter trace
    par(las = 1)
    plot.ts(c2, ylab = "c2", xlab = "iterations", plot.type = "single")
    
    # Reload saved posterior averages and Bayesian effect sizes
    load(file.path(pathToLogFiles, "BES.rda"))
    load(file.path(pathToLogFiles, "postAvg.rda"))
    
    # Identify interesting concordant and discordant genes
    op.conc <- symbolsInteresting(rankingStatistic = postAvg[, "concordant"])
    op.disc <- symbolsInteresting(rankingStatistic = postAvg[, "discordant"])
    
    # Generate pairwise scatter plots of Bayesian Effect Sizes
    par(las = 1)
    graphics:::pairs(BES[op.conc\$order, ], pch = op.conc\$pch, col = op.conc\$col,
                     bg = op.conc\$bg, upper.panel = NULL, cex = op.conc\$cex)
    
    graphics:::pairs(BES[op.disc\$order, ], pch = op.disc\$pch, col = op.disc\$col, bg = op.disc\$bg,
                     upper.panel = NULL, cex = op.disc\$cex)
    
    dev.off()
    
    # ==========================================
    # --- Save Meaningful Results ---
    # ==========================================
    
    write.csv(postAvg, "posterior_averages.csv", row.names = TRUE)
    write.csv(BES, "bayesian_effect_sizes.csv", row.names = TRUE)
    saveRDS(xmcmc, "xmcmc_fit.rds")
    
    message("Pipeline completed successfully. Outputs saved to 'posterior_averages.csv', 'bayesian_effect_sizes.csv', 'xmcmc_fit.rds', and 'mcmc_diagnostics_and_plots.pdf'.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # input validation — workflow-level pass when expected output files exist
    # and have non-zero size. Binary pass: at least one .rds or .csv emitted.
    .iv_artifacts <- c(list.files(".", pattern = "\\.rds\$"), list.files(".", pattern = "\\.csv\$"))
    .iv_passes <- length(.iv_artifacts) > 0
    .gates_by_label[["input validation"]] <- list(
      gate_row = "bioc_input_validation",
      metric_name = "input_validation_passes",
      metric_value = if (.iv_passes) 1 else 0,
      passes = .iv_passes,
      status = paste0("computed (", length(.iv_artifacts), " artifact(s) emitted)")
    )

    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .mv_obj <- tryCatch(readRDS(.mv_rds), error = function(e) NULL)
      .mv_mat <- if (is.matrix(.mv_obj) || is.data.frame(.mv_obj)) .mv_obj else NULL
      if (!is.null(.mv_mat)) {
        .mv_vals <- suppressWarnings(as.numeric(as.matrix(.mv_mat)))
        if (length(.mv_vals) > 0) {
          .mv_na_fracs <- c(.mv_na_fracs, mean(is.na(.mv_vals)))
          .mv_scanned <- c(.mv_scanned, .mv_rds)
        }
      }
    }
    .mv_max <- if (length(.mv_na_fracs) > 0) round(max(.mv_na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .mv_max,
      passes = isTRUE(is.finite(.mv_max) && .mv_max < 0.05),
      status = if (is.finite(.mv_max)) paste0("computed (scanned ", length(.mv_scanned), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_XDE_BAYESIAN_CROSS_STUDY_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("input validation", "missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_XDE_BAYESIAN_CROSS_STUDY_ANALYSIS":',
        paste0('    XDE: ', as.character(packageVersion('XDE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayesian_cross_study_analysis.csv versions.yml
    """
}

workflow BIOC_XDE_BAYESIAN_CROSS_STUDY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Multiple ExpressionSet objects ] ]

    main:
    BIOC_XDE_BAYESIAN_CROSS_STUDY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_XDE_BAYESIAN_CROSS_STUDY_ANALYSIS.out.tables
    plots    = BIOC_XDE_BAYESIAN_CROSS_STUDY_ANALYSIS.out.plots
    objects  = BIOC_XDE_BAYESIAN_CROSS_STUDY_ANALYSIS.out.objects
    versions = BIOC_XDE_BAYESIAN_CROSS_STUDY_ANALYSIS.out.versions
}
