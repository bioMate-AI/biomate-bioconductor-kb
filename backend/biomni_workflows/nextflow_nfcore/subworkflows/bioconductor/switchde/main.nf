#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: switchde — switchde_trajectory_analysis
// Infer and detect switch-like differential expression of genes along a single-cell trajectory using sigmoidal fitting.
// Input: counts.csv, coldata.csv
// Container: 1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, dplyr, ggplot2, switchde
// Visualizations: plot (ggplot/base)
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SWITCHDE_SWITCHDE_TRAJECTORY_ANALYSIS {
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
    .bm_deps <- c("switchde", "dplyr", "ggplot2")
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
    library(switchde)
    library(dplyr)
    library(ggplot2)
    
    # ==========================================
    # --- Load and Align Input Data ---
    # ==========================================
    message("Stage 1: Loading input datasets...")
    
    # Read counts and coldata
    counts <- read.csv("counts.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Set row names of counts using 'gene_id' if present
    if ("gene_id" %in% colnames(counts)) {
      rownames(counts) <- counts\$gene_id
      counts\$gene_id <- NULL
    } else {
      rownames(counts) <- counts[, 1]
      counts <- counts[, -1, drop = FALSE]
    }
    
    # Ensure sample alignment
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv.")
    }
    
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # ==========================================
    # --- Normalization and Pre-filtering ---
    # ==========================================
    message("Stage 2: Normalizing and filtering genes...")
    
    # Convert raw counts to log2(CPM + 1) to obtain logged expression data
    libsizes <- colSums(counts)
    libsizes[libsizes == 0] <- 1
    cpm <- t(t(counts) / libsizes) * 1e6
    log_expr <- log2(cpm + 1)
    
    # Apply strict pre-filtering to avoid MLE/EM convergence issues
    # Retain genes with mean expression > 0.1 and expressed in > 20% of cells
    filter_mask <- rowMeans(log_expr) > 0.1 & rowMeans(log_expr > 0) > 0.2
    X_filtered <- log_expr[filter_mask, , drop = FALSE]
    
    # Fallback if filtering is too strict
    if (nrow(X_filtered) < 5) {
      message("Warning: Strict filtering retained too few genes. Relaxing thresholds...")
      X_filtered <- log_expr[rowMeans(log_expr) > 0, , drop = FALSE]
    }
    
    # ==========================================
    # --- Pseudotime Extraction / Inference ---
    # ==========================================
    message("Stage 3: Extracting or inferring pseudotime trajectory...")
    
    # Check if a pseudotime column exists in coldata
    pseudotime_col <- grep("pseudotime|time|latent", colnames(coldata), ignore.case = TRUE, value = TRUE)
    
    if (length(pseudotime_col) > 0) {
      message(paste("Using existing pseudotime column:", pseudotime_col[1]))
      pseudotime <- as.numeric(coldata[[pseudotime_col[1]]])
    } else {
      message("No pseudotime column found. Inferring trajectory using PCA PC1...")
      # Compute PCA on the filtered log-expression matrix as a proxy for pseudotime
      pca <- prcomp(t(X_filtered), scale. = TRUE)
      pseudotime <- pca\$x[, 1]
      # Rescale pseudotime to [0, 1] range
      pseudotime <- (pseudotime - min(pseudotime)) / (max(pseudotime) - min(pseudotime))
    }
    
    # ==========================================
    # --- Fit Sigmoidal Models ---
    # ==========================================
    message("Stage 4: Fitting sigmoidal models...")
    
    # Create SingleCellExperiment object
    sce <- SingleCellExperiment(assays = list(exprs = as.matrix(X_filtered)))
    
    # Fit standard (non-zero-inflated) model
    sde <- switchde(sce, pseudotime)
    sde <- sde[order(sde\$qval), ]
    write.csv(sde, "switchde_results_standard.csv", row.names = FALSE)
    
    # Fit zero-inflated model on top candidate genes to optimize runtime
    # (EM algorithm takes ~20x longer, so we run on top 20 genes)
    top_n_genes <- min(20, nrow(sde))
    top_genes <- sde\$gene[1:top_n_genes]
    
    message("Fitting zero-inflated model on top candidate genes...")
    sce_top <- SingleCellExperiment(assays = list(exprs = as.matrix(X_filtered[top_genes, , drop = FALSE])))
    zde <- tryCatch({
      zde_fit <- switchde(sce_top, pseudotime, zero_inflated = TRUE)
      zde_fit[order(zde_fit\$qval), ]
    }, error = function(e) {
      message("Zero-inflated model fitting failed or was skipped: ", e\$message)
      data.frame(gene = top_genes, pval = NA, qval = NA, mu0 = NA, k = NA, t0 = NA, lambda = NA, EM_converged = FALSE)
    })
    write.csv(zde, "switchde_results_zero_inflated.csv", row.names = FALSE)
    
    # ==========================================
    # --- Downstream Filtering & Use Cases ---
    # ==========================================
    message("Stage 5: Performing downstream filtering and trajectory analysis...")
    
    # 1. Identify genes with strong switch-like behavior (high absolute k)
    switch_genes <- sde %>%
      filter(qval < 0.05) %>%
      filter(abs(k) > quantile(abs(k), 0.75, na.rm = TRUE))
    write.csv(switch_genes, "switch_like_genes.csv", row.names = FALSE)
    
    # 2. Find genes regulated in different parts of the trajectory (early vs late)
    pst_quantiles <- quantile(pseudotime, c(0, 0.5, 1))
    early_genes <- sde %>%
      filter(qval < 0.05, t0 >= pst_quantiles[1], t0 < pst_quantiles[2])
    late_genes <- sde %>%
      filter(qval < 0.05, t0 >= pst_quantiles[2], t0 <= pst_quantiles[3])
    
    write.csv(early_genes, "early_regulated_genes.csv", row.names = FALSE)
    write.csv(late_genes, "late_regulated_genes.csv", row.names = FALSE)
    
    # ==========================================
    # --- Visualization ---
    # ==========================================
    message("Stage 6: Generating diagnostic plots...")
    
    pdf("switchde_plots.pdf", width = 8, height = 6)
    
    # Plot top gene from standard model
    if (nrow(sde) > 0) {
      top_gene_std <- sde\$gene[1]
      pars_std <- extract_pars(sde, top_gene_std)
      p1 <- switchplot(X_filtered[top_gene_std, ], pseudotime, pars_std) +
        ggtitle(paste("Standard Model:", top_gene_std)) +
        theme_bw()
      print(p1)
    }
    
    # Plot top gene from zero-inflated model
    if (nrow(zde) > 0 && !all(is.na(zde\$qval))) {
      top_gene_zi <- zde\$gene[1]
      pars_zi <- extract_pars(zde, top_gene_zi)
      p2 <- switchplot(X_filtered[top_gene_zi, ], pseudotime, pars_zi) +
        ggtitle(paste("Zero-Inflated Model:", top_gene_zi)) +
        theme_bw()
      print(p2)
    }
    
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SWITCHDE_SWITCHDE_TRAJECTORY_ANALYSIS":',
        paste0('    switchde: ', as.character(packageVersion('switchde')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_switchde_trajectory_analysis.csv versions.yml
    """
}

workflow BIOC_SWITCHDE_SWITCHDE_TRAJECTORY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SWITCHDE_SWITCHDE_TRAJECTORY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SWITCHDE_SWITCHDE_TRAJECTORY_ANALYSIS.out.tables
    plots    = BIOC_SWITCHDE_SWITCHDE_TRAJECTORY_ANALYSIS.out.plots
    objects  = BIOC_SWITCHDE_SWITCHDE_TRAJECTORY_ANALYSIS.out.objects
    versions = BIOC_SWITCHDE_SWITCHDE_TRAJECTORY_ANALYSIS.out.versions
}
