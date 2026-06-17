#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nnSVG — nnsvg_spatial_variable_genes
// Identify spatially variable genes (SVGs) from spatial transcriptomics data using nearest-neighbor Gaussian processes (nnSVG), supporting both single-sample cova
// Input: counts.csv, coldata.csv
// Container: 1.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: S4Vectors, SpatialExperiment, ggplot2, nnSVG, scran
// Visualizations: plot (ggplot/base)
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NNSVG_NNSVG_SPATIAL_VARIABLE_GENES {
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
    .bm_deps <- c("SpatialExperiment", "nnSVG", "scran", "ggplot2", "S4Vectors", "SummarizedExperiment")
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
    library(SpatialExperiment)
    library(SummarizedExperiment)
    library(nnSVG)
    library(scran)
    library(ggplot2)
    library(S4Vectors)
    
    # ==========================================
    # --- Load and Align Input Data ---
    # ==========================================
    message("Loading input data...")
    
    # Read counts matrix
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    } else if (is.character(counts_df[[1]]) || is.factor(counts_df[[1]])) {
      rownames(counts_df) <- counts_df[[1]]
      counts_df <- counts_df[, -1, drop = FALSE]
    }
    counts_mat <- as.matrix(counts_df)
    
    # Read coldata metadata
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    if (is.character(coldata[[1]]) || is.factor(coldata[[1]])) {
      rownames(coldata) <- coldata[[1]]
      coldata <- coldata[, -1, drop = FALSE]
    }
    
    # Align counts columns (spots/cells) and coldata rows
    common_spots <- intersect(colnames(counts_mat), rownames(coldata))
    if (length(common_spots) == 0) {
      if (ncol(counts_mat) == nrow(coldata)) {
        rownames(coldata) <- colnames(counts_mat)
        common_spots <- colnames(counts_mat)
      } else {
        stop("Error: Column names of counts.csv do not match row names of coldata.csv.")
      }
    }
    counts_mat <- counts_mat[, common_spots, drop = FALSE]
    coldata <- coldata[common_spots, , drop = FALSE]
    
    # Identify spatial coordinate columns in coldata
    col_names <- colnames(coldata)
    x_idx <- grep("^(x|xcoord|pxl_col|spatial_x|imagecol|col)\$", col_names, ignore.case = TRUE)
    y_idx <- grep("^(y|ycoord|pxl_row|spatial_y|imagerow|row)\$", col_names, ignore.case = TRUE)
    
    if (length(x_idx) == 0 || length(y_idx) == 0) {
      # Fallback: find first two numeric columns that aren't 'sample' or 'condition'
      numeric_cols <- which(sapply(coldata, is.numeric))
      numeric_cols <- setdiff(numeric_cols, which(col_names %in% c("sample", "condition")))
      if (length(numeric_cols) >= 2) {
        x_idx <- numeric_cols[1]
        y_idx <- numeric_cols[2]
      } else {
        stop("Error: Could not identify spatial coordinate columns (e.g., x, y) in coldata.csv.")
      }
    }
    
    spatial_coords <- as.matrix(coldata[, c(x_idx, y_idx)])
    colnames(spatial_coords) <- c("x", "y")
    
    # Construct SpatialExperiment object
    spe <- SpatialExperiment(
      assays = list(counts = counts_mat),
      colData = DataFrame(coldata),
      spatialCoords = spatial_coords
    )
    
    # ==========================================
    # --- Quality Control & Preprocessing ---
    # ==========================================
    message("Preprocessing and filtering data...")
    
    # Keep only spots over tissue if 'in_tissue' column is present
    if ("in_tissue" %in% colnames(colData(spe))) {
      spe <- spe[, colData(spe)\$in_tissue == 1]
    }
    
    # Filter out genes with zero expression across all spots
    ix_zero_genes <- rowSums(counts(spe)) == 0
    if (sum(ix_zero_genes) > 0) {
      spe <- spe[!ix_zero_genes, ]
    }
    
    # Filter out spots with zero expression across all genes
    ix_zero_spots <- colSums(counts(spe)) == 0
    if (sum(ix_zero_spots) > 0) {
      spe <- spe[, !ix_zero_spots]
    }
    
    # Determine if we have multiple samples
    has_multiple_samples <- FALSE
    if ("sample" %in% colnames(colData(spe))) {
      sample_ids <- unique(colData(spe)\$sample)
      if (length(sample_ids) > 1) {
        has_multiple_samples <- TRUE
      }
    }
    
    # ==========================================
    # --- Run nnSVG Analysis Pipeline ---
    # ==========================================
    if (has_multiple_samples) {
      message("Detected multiple samples. Running multi-sample rank-aggregation workflow...")
      
      sample_ids <- as.character(sample_ids)
      res_list <- list()
      
      for (s in seq_along(sample_ids)) {
        sample_id <- sample_ids[s]
        message(paste("Processing sample:", sample_id))
        
        # Subset to current sample
        spe_sub <- spe[, colData(spe)\$sample == sample_id]
        
        # Filter genes specifically for this sample
        spe_sub <- filter_genes(spe_sub, filter_mito = TRUE)
        
        # Remove any zero-expression spots/genes introduced by subsetting/filtering
        ix_zeros_g <- rowSums(counts(spe_sub)) == 0
        if (sum(ix_zeros_g) > 0) spe_sub <- spe_sub[!ix_zeros_g, ]
        ix_zeros_s <- colSums(counts(spe_sub)) == 0
        if (sum(ix_zeros_s) > 0) spe_sub <- spe_sub[, !ix_zeros_s]
        
        # Re-calculate logcounts for the subset
        spe_sub <- computeLibraryFactors(spe_sub)
        spe_sub <- logNormCounts(spe_sub)
        
        # Run nnSVG
        set.seed(123)
        spe_sub <- nnSVG(spe_sub, n_threads = 1)
        
        res_list[[sample_id]] <- rowData(spe_sub)
      }
      
      # Combine results across samples by averaging ranks
      res_ranks <- matrix(NA, nrow = nrow(spe), ncol = length(sample_ids))
      rownames(res_ranks) <- rownames(spe)
      colnames(res_ranks) <- sample_ids
      
      for (s in seq_along(sample_ids)) {
        sample_id <- sample_ids[s]
        rownames_s <- rownames(res_list[[sample_id]])
        res_ranks[rownames_s, s] <- res_list[[sample_id]][, "rank"]
      }
      
      # Remove genes filtered out in all samples
      ix_allna <- apply(res_ranks, 1, function(r) all(is.na(r)))
      res_ranks <- res_ranks[!ix_allna, , drop = FALSE]
      
      avg_ranks <- rowMeans(res_ranks, na.rm = TRUE)
      
      df_summary <- data.frame(
        gene_id = names(avg_ranks),
        overall_rank = rank(avg_ranks),
        average_rank = unname(avg_ranks),
        stringsAsFactors = FALSE
      )
      df_summary <- df_summary[order(df_summary\$average_rank), ]
      
    } else {
      message("Running single-sample workflow...")
      
      # Filter genes
      spe <- filter_genes(spe, filter_mito = TRUE)
      
      # Re-calculate logcounts
      spe <- computeLibraryFactors(spe)
      spe <- logNormCounts(spe)
      
      # Check for covariates (e.g., condition)
      X <- NULL
      if ("condition" %in% colnames(colData(spe))) {
        conds <- colData(spe)\$condition
        if (length(unique(conds)) > 1) {
          message("Adjusting for 'condition' covariate...")
          X <- model.matrix(~ droplevels(as.factor(conds)))
        }
      }
      
      # Run nnSVG
      set.seed(123)
      if (!is.null(X)) {
        spe <- nnSVG(spe, X = X, n_threads = 1)
      } else {
        spe <- nnSVG(spe, n_threads = 1)
      }
      
      df_summary <- as.data.frame(rowData(spe))
      df_summary\$gene_id <- rownames(df_summary)
      df_summary <- df_summary[order(df_summary\$rank), ]
    }
    
    # Save ranked SVG results
    write.csv(df_summary, "svg_results.csv", row.names = FALSE)
    message("Saved SVG results to 'svg_results.csv'")
    
    # ==========================================
    # --- Visualization ---
    # ==========================================
    message("Generating spatial visualization of the top SVG...")
    
    top_gene <- df_summary\$gene_id[1]
    coords <- spatialCoords(spe)
    expr_vals <- counts(spe)[top_gene, ]
    
    plot_df <- data.frame(
      x = coords[, 1],
      y = coords[, 2],
      expr = expr_vals
    )
    
    if ("sample" %in% colnames(colData(spe))) {
      plot_df\$sample <- colData(spe)\$sample
    }
    
    p <- ggplot(plot_df, aes(x = x, y = y, color = expr)) +
      geom_point(size = 1.2, alpha = 0.8) +
      coord_fixed() +
      scale_color_gradient(low = "gray90", high = "blue", trans = "sqrt", name = "counts") +
      ggtitle(paste("Top Spatially Variable Gene:", top_gene)) +
      theme_bw() +
      theme(
        plot.title = element_text(face = "italic", hjust = 0.5, size = 14),
        panel.grid = element_blank(),
        axis.title = element_blank(),
        axis.text = element_blank(),
        axis.ticks = element_blank()
      )
    
    if ("sample" %in% colnames(plot_df) && length(unique(plot_df\$sample)) > 1) {
      p <- p + facet_wrap(~ sample, scales = "free")
    }
    
    ggsave("top_svg_expression.pdf", plot = p, width = 8, height = 6)
    message("Saved spatial plot to 'top_svg_expression.pdf'")
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_NNSVG_NNSVG_SPATIAL_VARIABLE_GENES":',
        paste0('    nnSVG: ', as.character(packageVersion('nnSVG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nnsvg_spatial_variable_genes.csv versions.yml
    """
}

workflow BIOC_NNSVG_NNSVG_SPATIAL_VARIABLE_GENES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_NNSVG_NNSVG_SPATIAL_VARIABLE_GENES(ch_input)

    emit:
    tables   = BIOC_NNSVG_NNSVG_SPATIAL_VARIABLE_GENES.out.tables
    plots    = BIOC_NNSVG_NNSVG_SPATIAL_VARIABLE_GENES.out.plots
    objects  = BIOC_NNSVG_NNSVG_SPATIAL_VARIABLE_GENES.out.objects
    versions = BIOC_NNSVG_NNSVG_SPATIAL_VARIABLE_GENES.out.versions
}
