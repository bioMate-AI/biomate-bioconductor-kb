#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SLqPCR — slqpcr_analysis_pipeline
// Perform comprehensive qPCR analysis including relative quantity calculation, housekeeping gene selection, stability evaluation, and normalization.
// Input: input.csv
// Container: 1.76.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SLqPCR
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SLQPCR_SLQPCR_ANALYSIS_PIPELINE {
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
    .bm_deps <- c("SLqPCR")
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
    library(SLqPCR)
    
    # Define parameters
    efficiency <- 2
    
    # Read input defensively
    if (!file.exists("input.csv")) {
      stop("Staged input file 'input.csv' not found.")
    }
    
    # Read CSV
    df <- read.csv("input.csv", check.names = FALSE)
    
    # Determine row names / feature IDs
    if ("feature_id" %in% colnames(df)) {
      rownames(df) <- df\$feature_id
      df\$feature_id <- NULL
    } else if (is.character(df[[1]]) || is.factor(df[[1]])) {
      rownames(df) <- df[[1]]
      df <- df[-1]
    }
    
    # Transpose to sample-by-feature (samples as rows, genes as columns)
    qpcr_data <- as.data.frame(t(df))
    
    # Ensure all columns are numeric
    qpcr_data <- as.data.frame(lapply(qpcr_data, function(x) as.numeric(as.character(x))))
    rownames(qpcr_data) <- colnames(df)
    colnames(qpcr_data) <- rownames(df)
    
    # Check dimensions
    n_genes <- ncol(qpcr_data)
    n_samples <- nrow(qpcr_data)
    
    if (n_genes < 3) {
      message("Fewer than 3 genes provided. Skipping housekeeping gene selection and using all genes for normalization.")
    
      # Fallback normalization using geometric mean of all genes
      normalized_data <- qpcr_data
      for (i in 1:n_samples) {
        gmean <- geomMean(as.numeric(qpcr_data[i, ]))
        normalized_data[i, ] <- qpcr_data[i, ] / gmean
      }
    
      # Write fallback outputs
      ranking_df <- data.frame(
        Rank = seq_len(n_genes),
        Gene = colnames(qpcr_data),
        stringsAsFactors = FALSE
      )
      write.csv(ranking_df, "hk_rankings.csv", row.names = FALSE)
    
      normalized_out <- as.data.frame(t(normalized_data))
      normalized_out <- cbind(feature_id = rownames(normalized_out), normalized_out)
      write.csv(normalized_out, "normalized_expression.csv", row.names = FALSE)
    
      # Create fallback PDF
      pdf("stability_plots.pdf", width = 8, height = 5)
      plot.new()
      text(0.5, 0.5, "Insufficient genes (< 3) for stability analysis", cex = 1.2)
      dev.off()
    
    } else {
      # Calculate relative quantities
      rel_data <- apply(qpcr_data, 2, relQuantPCR, E = efficiency)
    
      # Select housekeeping genes using Vandesompele method
      gene_names <- colnames(rel_data)
      res_hk <- selectHKgenes(
        rel_data,
        method = "Vandesompele",
        geneSymbol = gene_names,
        minNrHK = 2,
        trace = FALSE,
        na.rm = TRUE
      )
    
      # Determine optimal number of housekeeping genes based on pairwise variation (V)
      # Vandesompele et al. recommend a threshold of 0.15
      v_vals <- res_hk\$variation
      opt_k <- 2
      if (length(v_vals) > 0) {
        rev_v <- rev(v_vals)
        for (i in seq_along(rev_v)) {
          if (rev_v[i] < 0.15) {
            opt_k <- i + 1
            break
          }
        }
        # If all variations are above 0.15, default to 3 or the minimum variation
        if (opt_k == 2 && rev_v[1] >= 0.15) {
          opt_k <- min(3, n_genes)
        }
      }
      opt_k <- max(2, min(opt_k, n_genes))
    
      # Extract selected housekeeping genes
      selected_hk <- res_hk\$ranking[1:opt_k]
    
      # Calculate stability measure M for selected HK genes
      hk_m_values <- geneStabM(rel_data[, selected_hk, drop = FALSE])
    
      # Normalize qPCR data using selected HK genes
      hk_indices <- match(selected_hk, colnames(qpcr_data))
      normalized_data <- normPCR(qpcr_data, hk_indices)
    
      # Write rankings
      ranks_vector <- c(1, seq_len(length(res_hk\$ranking) - 1))
      ranking_df <- data.frame(
        Rank = ranks_vector,
        Gene = res_hk\$ranking,
        stringsAsFactors = FALSE
      )
      write.csv(ranking_df, "hk_rankings.csv", row.names = FALSE)
    
      # Write normalized expression (transposed back to feature-by-sample)
      normalized_out <- as.data.frame(t(normalized_data))
      normalized_out <- cbind(feature_id = rownames(normalized_out), normalized_out)
      write.csv(normalized_out, "normalized_expression.csv", row.names = FALSE)
    
      # Generate diagnostic plots
      pdf("stability_plots.pdf", width = 12, height = 6)
      par(mfrow = c(1, 2))
    
      # Plot 1: Average expression stability M
      plot(
        res_hk\$meanM,
        type = "b",
        ylab = "Average expression stability M",
        xlab = "Number of remaining control genes",
        axes = FALSE,
        pch = 19,
        col = "darkblue",
        lwd = 2,
        main = "Gene Stability Measure (M)"
      )
      axis(1, at = seq_along(res_hk\$meanM), labels = as.character(n_genes:2))
      axis(2)
      box()
      abline(h = seq(0.2, 1.2, by = 0.2), lty = 2, col = "grey")
    
      # Plot 2: Pairwise variation
      if (length(v_vals) > 0) {
        v_names <- paste0("V", (n_genes-1):2, "/", n_genes:3)
        barplot(
          v_vals,
          names.arg = v_names,
          col = "skyblue",
          main = "Pairwise Variation (V)",
          ylab = "Pairwise variation V",
          las = 2
        )
        abline(h = 0.15, lty = 2, col = "red", lwd = 2)
      } else {
        plot.new()
        text(0.5, 0.5, "No pairwise variation data available")
      }
    
      dev.off()
    }

    writeLines(c(
        '"BIOC_SLQPCR_SLQPCR_ANALYSIS_PIPELINE":',
        paste0('    SLqPCR: ', as.character(packageVersion('SLqPCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_slqpcr_analysis_pipeline.csv versions.yml
    """
}

workflow BIOC_SLQPCR_SLQPCR_ANALYSIS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SLQPCR_SLQPCR_ANALYSIS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_SLQPCR_SLQPCR_ANALYSIS_PIPELINE.out.tables
    plots    = BIOC_SLQPCR_SLQPCR_ANALYSIS_PIPELINE.out.plots
    objects  = BIOC_SLQPCR_SLQPCR_ANALYSIS_PIPELINE.out.objects
    versions = BIOC_SLQPCR_SLQPCR_ANALYSIS_PIPELINE.out.versions
}
