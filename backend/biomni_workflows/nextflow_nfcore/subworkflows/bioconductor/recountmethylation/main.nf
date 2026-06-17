#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: recountmethylation — recountmethylation_preprocessing_variance
// Filter cross-reactive probes from DNA methylation beta values, perform variance and ANOVA-based differential analysis across conditions, and generate diagnostic
// Input: matrix.csv, coldata.csv
// Container: 1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: recountmethylation
// Visualizations: box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RECOUNTMETHYLATION_RECOUNTMETHYLATION_PREPROCESSING_VARIANCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("recountmethylation")
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
    library(recountmethylation)
    
    # ----------------------------------------------------------------------
    # --- Load and Align Input Data ---
    # ----------------------------------------------------------------------
    message("Loading input datasets...")
    if (!file.exists("matrix.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'matrix.csv' and/or 'coldata.csv' are missing.")
    }
    
    # Read methylation beta values matrix
    beta_df <- read.csv("matrix.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!"feature_id" %in% colnames(beta_df)) {
      stop("Input matrix.csv must contain a 'feature_id' column.")
    }
    rownames(beta_df) <- beta_df\$feature_id
    beta_df\$feature_id <- NULL
    beta_matrix <- as.matrix(beta_df)
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!all(c("sample", "condition") %in% colnames(coldata))) {
      stop("Input coldata.csv must contain 'sample' and 'condition' columns.")
    }
    
    # Align samples between matrix and metadata
    common_samples <- intersect(colnames(beta_matrix), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between matrix.csv and coldata.csv.")
    }
    message(paste("Aligned", length(common_samples), "samples for analysis."))
    
    beta_matrix <- beta_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # ----------------------------------------------------------------------
    # --- Filter Cross-Reactive Probes ---
    # ----------------------------------------------------------------------
    message("Identifying and filtering cross-reactive CpG probes...")
    cross_reactive_probes <- tryCatch({
      recountmethylation::get_crossreactive_cpgs()
    }, error = function(e) {
      warning("Could not retrieve cross-reactive CpGs from recountmethylation: ", e\$message)
      character(0)
    })
    
    if (length(cross_reactive_probes) > 0) {
      keep_probes <- setdiff(rownames(beta_matrix), cross_reactive_probes)
      num_filtered <- nrow(beta_matrix) - length(keep_probes)
      message(paste("Filtered out", num_filtered, "cross-reactive probes."))
      beta_filtered <- beta_matrix[keep_probes, , drop = FALSE]
    } else {
      message("No cross-reactive probes filtered (list empty or unavailable).")
      beta_filtered <- beta_matrix
    }
    
    # Save the filtered beta matrix
    write_filtered_df <- data.frame(feature_id = rownames(beta_filtered), beta_filtered, check.names = FALSE)
    write.csv(write_filtered_df, "filtered_beta_matrix.csv", row.names = FALSE)
    message("Saved filtered beta matrix to 'filtered_beta_matrix.csv'.")
    
    # ----------------------------------------------------------------------
    # --- Variance and ANOVA-based Differential Analysis ---
    # ----------------------------------------------------------------------
    message("Calculating probe-wise summary statistics and performing ANOVA...")
    
    probe_means <- rowMeans(beta_filtered, na.rm = TRUE)
    probe_vars <- apply(beta_filtered, 1, var, na.rm = TRUE)
    probe_sds <- apply(beta_filtered, 1, sd, na.rm = TRUE)
    
    # Perform ANOVA across conditions for each probe
    p_values <- apply(beta_filtered, 1, function(x) {
      tryCatch({
        fit <- lm(x ~ coldata\$condition)
        av <- anova(fit)
        av[["Pr(>F)"]][1]
      }, error = function(e) {
        NA_real_
      })
    })
    
    stats_df <- data.frame(
      probe_id = rownames(beta_filtered),
      mean = probe_means,
      variance = probe_vars,
      sd = probe_sds,
      p_value = p_values,
      adj_p_value = p.adjust(p_values, method = "BH"),
      stringsAsFactors = FALSE
    )
    
    # Rank probes by descending variance
    stats_df <- stats_df[order(stats_df\$variance, decreasing = TRUE), ]
    write.csv(stats_df, "high_variance_probes.csv", row.names = FALSE)
    message("Saved probe statistics to 'high_variance_probes.csv'.")
    
    # ----------------------------------------------------------------------
    # --- Diagnostic and Quality Control Visualizations ---
    # ----------------------------------------------------------------------
    message("Generating diagnostic plots...")
    
    pdf("dnam_qc_variance_plots.pdf", width = 8, height = 11)
    
    # Layout: 3 plots vertically
    layout(matrix(c(1, 2, 3, 4), nrow = 4, ncol = 1), heights = c(1.2, 1.5, 1.2, 1.2))
    par(mar = c(4, 4, 3, 2))
    
    # Plot 1: Overall Beta Value Density
    plot(density(beta_filtered[, 1], na.rm = TRUE), 
         main = "Beta Value Density (All Samples)", 
         xlab = "Beta Value", ylab = "Density", 
         col = "gray80", lwd = 1, ylim = c(0, 6))
    if (ncol(beta_filtered) > 1) {
      for (i in 2:ncol(beta_filtered)) {
        lines(density(beta_filtered[, i], na.rm = TRUE), col = "gray80", lwd = 1)
      }
    }
    lines(density(rowMeans(beta_filtered, na.rm = TRUE), na.rm = TRUE), col = "darkblue", lwd = 2.5)
    legend("top", legend = c("Individual Samples", "Mean Profile"), col = c("gray80", "darkblue"), lwd = c(1, 2.5), bty = "n")
    
    # Plot 2: PCA of Top Variable Probes
    top_n <- min(500, nrow(beta_filtered))
    if (top_n > 5) {
      top_probes <- stats_df\$probe_id[1:top_n]
      pca_data <- t(beta_filtered[top_probes, , drop = FALSE])
      
      # Simple mean imputation for PCA if any missing values exist
      for (col in 1:ncol(pca_data)) {
        if (any(is.na(pca_data[, col]))) {
          pca_data[is.na(pca_data[, col]), col] <- mean(pca_data[, col], na.rm = TRUE)
        }
      }
      
      pca_res <- prcomp(pca_data, scale. = TRUE)
      pc1 <- pca_res\$x[, 1]
      pc2 <- pca_res\$x[, 2]
      
      cond_factor <- as.factor(coldata\$condition)
      colors <- palette()[1:nlevels(cond_factor)]
      sample_colors <- colors[cond_factor]
      
      plot(pc1, pc2, col = sample_colors, pch = 19, cex = 1.5,
           xlab = paste0("PC1 (", round(100 * (pca_res\$sdev[1]^2 / sum(pca_res\$sdev^2)), 1), "%)"),
           ylab = paste0("PC2 (", round(100 * (pca_res\$sdev[2]^2 / sum(pca_res\$sdev^2)), 1), "%)"),
           main = paste0("PCA of Top ", top_n, " Variable Probes"))
      legend("topright", legend = levels(cond_factor), col = colors, pch = 19, bty = "n")
    } else {
      plot(1, 1, type = "n", main = "PCA (Insufficient Probes for Analysis)")
    }
    
    # Plot 3 & 4: Boxplots of Top 2 Most Variable Probes
    top_2 <- stats_df\$probe_id[1:min(2, nrow(stats_df))]
    if (length(top_2) > 0) {
      for (pr in top_2) {
        boxplot(beta_filtered[pr, ] ~ coldata\$condition, 
                main = paste("Beta Values for Top Variable Probe:", pr), 
                xlab = "Condition", ylab = "Beta Value",
                col = "lightblue", las = 1)
      }
    }
    
    dev.off()
    message("Saved diagnostic plots to 'dnam_qc_variance_plots.pdf'.")
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_RECOUNTMETHYLATION_RECOUNTMETHYLATION_PREPROCESSING_VARIANCE":',
        paste0('    recountmethylation: ', as.character(packageVersion('recountmethylation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_recountmethylation_preprocessing_variance.csv versions.yml
    """
}

workflow BIOC_RECOUNTMETHYLATION_RECOUNTMETHYLATION_PREPROCESSING_VARIANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RECOUNTMETHYLATION_RECOUNTMETHYLATION_PREPROCESSING_VARIANCE(ch_input)

    emit:
    tables   = BIOC_RECOUNTMETHYLATION_RECOUNTMETHYLATION_PREPROCESSING_VARIANCE.out.tables
    plots    = BIOC_RECOUNTMETHYLATION_RECOUNTMETHYLATION_PREPROCESSING_VARIANCE.out.plots
    objects  = BIOC_RECOUNTMETHYLATION_RECOUNTMETHYLATION_PREPROCESSING_VARIANCE.out.objects
    versions = BIOC_RECOUNTMETHYLATION_RECOUNTMETHYLATION_PREPROCESSING_VARIANCE.out.versions
}
