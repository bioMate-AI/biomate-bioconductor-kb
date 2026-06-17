#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bandle — differential_localisation_analysis
// Perform differential subcellular localisation analysis on mass-spectrometry-based spatial proteomics data across two conditions.
// Input: control_replicates.RData, treatment_replicates.RData
// Container: quay.io/biocontainers/bioconductor-bandle:1.14.0--r45ha27e39d_0
// R packages: MSnbase, bandle, dplyr, ggplot2, pRoloc, pheatmap, prolocdata, viridis
// Bioconductor: 3.20 | R: 4.4
// Requires: MSnbase, bandle, pRoloc
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input and Extract Common Features
//  * 2. [Visualization & Output] Fit Gaussian Processes to Marker Profiles
//  * 3. [Visualization & Output] Set Up and Check Dirichlet Prior
//  * 4. [Visualization & Output] Run the Main MCMC Model (bandle)
//  * 5. [Visualization & Output] Assess MCMC Convergence
//  * 6. [Visualization & Output] Extract Differential Localisation Probabilities
//  * 7. [Visualization & Output] Visualize Translocations and Generate Summary Table
//  * 8. [Visualization & Output] Estimate Uncertainty and Expected False Discovery Rate

nextflow.enable.dsl = 2

process BIOC_BANDLE_DIFFERENTIAL_LOCALISATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MSnbase", "bandle", "dplyr", "ggplot2", "pRoloc", "pheatmap", "prolocdata", "viridis")
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
        library(bandle)
        library(pRoloc)
        library(MSnbase)
        
        # -----------------------------------------------------------------------------
        # --- Load User Input and Extract Common Features ---
        # -----------------------------------------------------------------------------
        
        # Load control replicates
        con_env <- new.env()
        load("control_replicates.RData", envir = con_env)
        control_obj_name <- names(con_env)[1]
        control_replicates <- con_env[[control_obj_name]]
        
        # Load treatment replicates
        treat_env <- new.env()
        load("treatment_replicates.RData", envir = treat_env)
        treatment_obj_name <- names(treat_env)[1]
        treatment_replicates <- treat_env[[treatment_obj_name]]
        
        # Coerce to standard lists of MSnSet objects
        control_list <- as(control_replicates, "list")
        treatment_list <- as(treatment_replicates, "list")
        
        # Combine all replicates to find common features
        all_reps <- c(control_list, treatment_list)
        thplopit <- commonFeatureNames(all_reps)
        
        # -----------------------------------------------------------------------------
        # --- Fit Gaussian Processes to Marker Profiles ---
        # -----------------------------------------------------------------------------
        
        K <- length(getMarkerClasses(thplopit[[1]], fcol = "markers"))
        pc_prior <- matrix(NA, ncol = 3, K)
        pc_prior[seq.int(1:K), ] <- matrix(rep(c(1, 60, 100), each = K), ncol = 3)
        gpParams <- lapply(thplopit, function(x) fitGPmaternPC(x, hyppar = pc_prior))
        
        # Save GP Matern plot
        pdf("gp_matern_plots.pdf")
        plotGPmatern(thplopit[[1]], gpParams[[1]])
        dev.off()
        
        # -----------------------------------------------------------------------------
        # --- Set Up and Check Dirichlet Prior ---
        # -----------------------------------------------------------------------------
        
        set.seed(1)
        dirPrior = diag(rep(1, K)) + matrix(0.0005, nrow = K, ncol = K)
        predDirPrior <- prior_pred_dir(object = thplopit[[1]], dirPrior = dirPrior, q = 15)
        
        # -----------------------------------------------------------------------------
        # --- Run the Main MCMC Model (bandle) ---
        # -----------------------------------------------------------------------------
        
        # Reconstruct control and treatment lists from the harmonized thplopit object
        control <- lapply(seq_along(control_list), function(i) thplopit[[i]])
        treatment <- lapply(seq_along(treatment_list), function(i) thplopit[[i + length(control_list)]])
        
        params <- bandle(
          objectCond1 = control,
          objectCond2 = treatment,
          numIter = 10,
          burnin = 5L,
          thin = 1L,
          gpParams = gpParams,
          pcPrior = pc_prior,
          numChains = 4,
          dirPrior = dirPrior,
          seed = 1
        )
        
        # Define bandleres to match vignette variable naming for downstream functions
        bandleres <- params
        
        # -----------------------------------------------------------------------------
        # --- Assess MCMC Convergence ---
        # -----------------------------------------------------------------------------
        
        gelman_diag <- calculateGelman(params)
        saveRDS(gelman_diag, "gelman_diagnostics.rds")
        
        pdf("outliers_trace.pdf")
        plotOutliers(params)
        dev.off()
        
        # -----------------------------------------------------------------------------
        # Stages 6 & 7: Subset Chains and Process MCMC Results
        # -----------------------------------------------------------------------------
        
        params_converged <- params[-c(1, 4)]
        params_converged <- bandleProcess(params_converged)
        bandle_out <- summaries(params_converged)
        saveRDS(bandle_out, "bandle_summaries.rds")
        
        # -----------------------------------------------------------------------------
        # Stages 8 & 9: Predict Subcellular Localisation and Apply Thresholds
        # -----------------------------------------------------------------------------
        
        xx <- bandlePredict(control, treatment, params = params_converged, fcol = "markers")
        res_0h <- xx[[1]]
        res_12h <- xx[[2]]
        
        res_0h[[1]] <- getPredictions(res_0h[[1]], fcol = "bandle.allocation", scol = "bandle.probability", mcol = "markers", t = .99)
        res_12h[[1]] <- getPredictions(res_12h[[1]], fcol = "bandle.allocation", scol = "bandle.probability", mcol = "markers", t = .99)
        
        fData(res_0h[[1]])\$bandle.outlier.t <- 1 - fData(res_0h[[1]])\$bandle.outlier
        fData(res_12h[[1]])\$bandle.outlier.t <- 1 - fData(res_12h[[1]])\$bandle.outlier
        
        res_0h[[1]] <- getPredictions(res_0h[[1]], fcol = "bandle.allocation.pred", scol = "bandle.outlier.t", mcol = "markers", t = .99)
        res_12h[[1]] <- getPredictions(res_12h[[1]], fcol = "bandle.allocation.pred", scol = "bandle.outlier.t", mcol = "markers", t = .99)
        
        # Save processed predictions
        saveRDS(res_0h, "res_control_processed.rds")
        saveRDS(res_12h, "res_treatment_processed.rds")
        
        # -----------------------------------------------------------------------------
        # --- Extract Differential Localisation Probabilities ---
        # -----------------------------------------------------------------------------
        
        dl <- diffLocalisationProb(params_converged)
        write.csv(as.data.frame(dl), "diff_localisation_probabilities.csv")
        
        # -----------------------------------------------------------------------------
        # --- Visualize Translocations and Generate Summary Table ---
        # -----------------------------------------------------------------------------
        
        # Prepare datasets for translocation plotting
        res_control_unknowns <- unknownMSnSet(res_0h[[1]], fcol = "markers")
        res_treated_unknowns <- unknownMSnSet(res_12h[[1]], fcol = "markers")
        
        ind <- which(dl > 0.99)
        if (length(ind) == 0) {
          # Fallback to top 10 features if none exceed the 0.99 threshold
          ind <- order(dl, decreasing = TRUE)[1:min(10, length(dl))]
        }
        
        selected_features <- names(dl)[ind]
        valid_features <- intersect(selected_features, featureNames(res_control_unknowns))
        
        res_control_dl0.99 <- res_control_unknowns[valid_features, ]
        res_treated_dl0.99 <- res_treated_unknowns[valid_features, ]
        dl_msnsets <- list(res_control_dl0.99, res_treated_dl0.99)
        
        mrkCl <- getMarkerClasses(res_0h[[1]], fcol = "markers")
        dl_cols <- c(getStockcol()[seq_along(mrkCl)], "grey")
        names(dl_cols) <- c(mrkCl, "unknown")
        
        # Plot translocations
        pdf("translocations_plots.pdf")
        plotTranslocations(dl_msnsets, fcol = "bandle.allocation.pred", col = dl_cols)
        plotTranslocations(dl_msnsets, fcol = "bandle.allocation.pred", col = dl_cols, type = "chord")
        dev.off()
        
        # Generate and save translocation table
        tbl <- plotTable(dl_msnsets, fcol = "bandle.allocation.pred")
        write.csv(tbl, "translocations_table.csv", row.names = FALSE)
        
        # -----------------------------------------------------------------------------
        # --- Estimate Uncertainty and Expected False Discovery Rate ---
        # -----------------------------------------------------------------------------
        
        top_val <- min(100, length(dl))
        
        boot_t <- bootstrapdiffLocprob(params = bandleres, top = top_val, Bootsample = 5000, decreasing = TRUE)
        saveRDS(boot_t, "bootstrap_diff_loc_prob.rds")
        
        bin_t <- binomialDiffLocProb(params = bandleres, top = top_val, nsample = 5000, decreasing = TRUE)
        saveRDS(bin_t, "binomial_diff_loc_prob.rds")
        
        efdr_val <- EFDR(dl, threshold = 0.95)
        writeLines(as.character(efdr_val), "efdr_value.txt")

    writeLines(c(
        '"BIOC_BANDLE_DIFFERENTIAL_LOCALISATION_ANALYSIS":',
        paste0('    bandle: ', as.character(packageVersion('bandle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_localisation_analysis.csv versions.yml
    """
}

workflow BIOC_BANDLE_DIFFERENTIAL_LOCALISATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ control_replicates.RData, treatment_replicates.RData ] ]

    main:
    BIOC_BANDLE_DIFFERENTIAL_LOCALISATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BANDLE_DIFFERENTIAL_LOCALISATION_ANALYSIS.out.tables
    plots    = BIOC_BANDLE_DIFFERENTIAL_LOCALISATION_ANALYSIS.out.plots
    objects  = BIOC_BANDLE_DIFFERENTIAL_LOCALISATION_ANALYSIS.out.objects
    versions = BIOC_BANDLE_DIFFERENTIAL_LOCALISATION_ANALYSIS.out.versions
}
