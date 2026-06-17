#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fastLiquidAssociation — fast_liquid_association_pipeline
// Identify and statistically validate gene triplets exhibiting liquid association (where the correlation between two genes is mediated by a third gene) using a fa
// Input: counts.csv, coldata.csv
// Container: 1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: doParallel, fastLiquidAssociation
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FASTLIQUIDASSOCIATION_FAST_LIQUID_ASSOCIATION_PIPELINE {
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
    .bm_deps <- c("fastLiquidAssociation", "doParallel")
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
    library(fastLiquidAssociation)
    library(parallel)
    library(doParallel)
    
    # ==========================================
    # --- Read and Preprocess Input Data ---
    # ==========================================
    message("Stage 1: Loading and preprocessing data...")
    
    # Read expression matrix (genes as rows, samples as columns)
    if (!file.exists("counts.csv")) {
      stop("Required input file 'counts.csv' not found.")
    }
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    
    # If a 'gene_id' column exists, set it as row names
    if ("gene_id" %in% colnames(counts)) {
      rownames(counts) <- counts\$gene_id
      counts\$gene_id <- NULL
    }
    
    # Transpose so that samples are rows and genes are columns
    data_mat <- t(as.matrix(counts))
    
    # Filter out genes with more than 30% missing values
    na_pct <- colMeans(is.na(data_mat))
    data_mat <- data_mat[, na_pct < 0.3, drop = FALSE]
    
    if (ncol(data_mat) < 3) {
      stop("Fewer than 3 genes remaining after filtering. Liquid association requires at least 3 genes.")
    }
    
    # Select the top 50 most variable genes to keep the screening computationally feasible
    gene_vars <- apply(data_mat, 2, var, na.rm = TRUE)
    top_genes <- names(sort(gene_vars, decreasing = TRUE))[1:min(50, ncol(data_mat))]
    data_subset <- data_mat[, top_genes, drop = FALSE]
    
    # Determine the optimal 'cut' parameter (number of bins + 1)
    # Ho et al. recommend 15-30 observations per bin.
    n_samples <- nrow(data_subset)
    cut_val <- max(3, round(n_samples / 20) + 1)
    
    message(paste("Processing", ncol(data_subset), "genes across", n_samples, "samples with cut =", cut_val))
    
    # ==========================================
    # --- Screen Triplets using fastMLA ---
    # ==========================================
    message("Stage 2: Screening triplets with fastMLA...")
    
    cores <- min(parallel::detectCores(), 2)
    
    mla_res <- tryCatch({
      fastMLA(
        data = data_subset,
        topn = 50,
        nvec = 1:ncol(data_subset),
        rvalue = 0.1,
        cut = cut_val,
        threads = cores
      )
    }, error = function(e) {
      message("Warning: fastMLA failed: ", e\$message)
      NULL
    })
    
    # Write fastMLA results
    if (!is.null(mla_res) && nrow(mla_res) > 0) {
      write.csv(mla_res, "mla_results.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Message = "No triplets passed the screening phase."), "mla_results.csv", row.names = FALSE)
    }
    
    # ==========================================
    # --- Significance Testing via CNM ---
    # ==========================================
    message("Stage 3: Testing significance with mass.CNM...")
    
    cnm_res <- NULL
    if (!is.null(mla_res) && nrow(mla_res) > 0) {
      cnm_res <- tryCatch({
        mass.CNM(
          data = data_subset,
          GLA.mat = mla_res,
          nback = min(10, nrow(mla_res))
        )
      }, error = function(e) {
        message("Warning: mass.CNM failed: ", e\$message)
        NULL
      })
    }
    
    # Write CNM results
    if (!is.null(cnm_res) && !is.null(cnm_res[["top p-values"]])) {
      write.csv(cnm_res[["top p-values"]], "cnm_results.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Message = "No CNM significance results generated."), "cnm_results.csv", row.names = FALSE)
    }
    
    # ==========================================
    # --- Robust Bootstrap Estimation ---
    # ==========================================
    message("Stage 4: Running robust bootstrap estimation for complex triplets...")
    
    boots_res <- NULL
    if (!is.null(cnm_res)) {
      boot_triplets <- cnm_res[["bootstrap triplets"]]
      if (!is.null(boot_triplets) && nrow(boot_triplets) > 0) {
        clust <- parallel::makeCluster(cores)
        doParallel::registerDoParallel(clust)
        
        boots_res <- tryCatch({
          fastboots.GLA(
            tripmat = boot_triplets,
            data = data_subset,
            clust = clust,
            boots = 30,
            perm = 100,
            cut = cut_val
          )
        }, error = function(e) {
          message("Warning: fastboots.GLA failed: ", e\$message)
          NULL
        }, finally = {
          parallel::stopCluster(clust)
        })
      }
    }
    
    # Write bootstrap results
    if (!is.null(boots_res) && nrow(boots_res) > 0) {
      write.csv(boots_res, "bootstrap_results.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Message = "No triplets required or successfully processed via bootstrapping."), "bootstrap_results.csv", row.names = FALSE)
    }
    
    # ==========================================
    # --- Visualization of Top Triplet ---
    # ==========================================
    message("Stage 5: Generating liquid association diagnostic plots...")
    
    pdf("liquid_association_plot.pdf", width = 10, height = 5)
    plot_success <- FALSE
    
    if (!is.null(mla_res) && nrow(mla_res) > 0) {
      tryCatch({
        # Extract top triplet details
        top_trip <- mla_res[1, ]
        x1_name <- as.character(top_trip[[1]])
        x2_name <- as.character(top_trip[[2]])
        x3_name <- as.character(top_trip[[3]])
        
        x1 <- data_subset[, x1_name]
        x2 <- data_subset[, x2_name]
        x3 <- data_subset[, x3_name]
        
        # Stratify by the median of the mediator gene X3
        med_x3 <- median(x3, na.rm = TRUE)
        group <- ifelse(x3 <= med_x3, "Low X3", "High X3")
        
        # Set up side-by-side scatter plots
        par(mfrow = c(1, 2), mar = c(5, 4, 4, 2) + 0.1)
        
        # Low X3 Plot
        plot(x1[group == "Low X3"], x2[group == "Low X3"],
             xlab = x1_name, ylab = x2_name,
             main = paste("Low", x3_name, "\n(r =", round(cor(x1[group == "Low X3"], x2[group == "Low X3"], use = "complete.obs"), 2), ")"),
             col = "blue", pch = 16, cex = 1.2)
        abline(lm(x2[group == "Low X3"] ~ x1[group == "Low X3"]), col = "blue", lwd = 2)
        
        # High X3 Plot
        plot(x1[group == "High X3"], x2[group == "High X3"],
             xlab = x1_name, ylab = x2_name,
             main = paste("High", x3_name, "\n(r =", round(cor(x1[group == "High X3"], x2[group == "High X3"], use = "complete.obs"), 2), ")"),
             col = "red", pch = 16, cex = 1.2)
        abline(lm(x2[group == "High X3"] ~ x1[group == "High X3"]), col = "red", lwd = 2)
        
        plot_success <- TRUE
      }, error = function(e) {
        message("Warning: Failed to plot top triplet: ", e\$message)
      })
    }
    
    if (!plot_success) {
      plot.new()
      text(0.5, 0.5, "No valid liquid association triplets found to plot.", cex = 1.2)
    }
    dev.off()
    
    message("Pipeline complete. All outputs successfully written.")

    writeLines(c(
        '"BIOC_FASTLIQUIDASSOCIATION_FAST_LIQUID_ASSOCIATION_PIPELINE":',
        paste0('    fastLiquidAssociation: ', as.character(packageVersion('fastLiquidAssociation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fast_liquid_association_pipeline.csv versions.yml
    """
}

workflow BIOC_FASTLIQUIDASSOCIATION_FAST_LIQUID_ASSOCIATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_FASTLIQUIDASSOCIATION_FAST_LIQUID_ASSOCIATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_FASTLIQUIDASSOCIATION_FAST_LIQUID_ASSOCIATION_PIPELINE.out.tables
    plots    = BIOC_FASTLIQUIDASSOCIATION_FAST_LIQUID_ASSOCIATION_PIPELINE.out.plots
    objects  = BIOC_FASTLIQUIDASSOCIATION_FAST_LIQUID_ASSOCIATION_PIPELINE.out.objects
    versions = BIOC_FASTLIQUIDASSOCIATION_FAST_LIQUID_ASSOCIATION_PIPELINE.out.versions
}
