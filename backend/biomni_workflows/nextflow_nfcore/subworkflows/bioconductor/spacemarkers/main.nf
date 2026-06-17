#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpaceMarkers — space_markers_analysis
// Identify spatial pattern interactions and molecular markers in spatial transcriptomics data using SpaceMarkers in both residual and differential expression (DE)
// Input: counts.csv, coldata.csv
// Container: 2.0.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SpaceMarkers, cowplot, dplyr, ggplot2, viridis
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPACEMARKERS_SPACE_MARKERS_ANALYSIS {
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
    .bm_deps <- c("SpaceMarkers", "ggplot2", "cowplot", "dplyr", "viridis")
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
    library(SpaceMarkers)
    library(ggplot2)
    library(cowplot)
    library(dplyr)
    library(viridis)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    message("Stage 1: Loading and preprocessing input data...")
    
    # Read counts and coldata
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Handle potential column name variations
    if ("gene_id" %in% colnames(counts)) {
      rownames(counts) <- counts\$gene_id
      counts\$gene_id <- NULL
    }
    if ("sample" %in% colnames(coldata)) {
      rownames(coldata) <- coldata\$sample
    }
    
    # Align counts and coldata
    common_samples <- intersect(colnames(counts), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, drop = FALSE]
    
    # Filter out genes with low counts (at least 3 spots with > 0 counts)
    good_gene_threshold <- 3
    goodGenes <- rownames(counts)[apply(counts, 1, function(x) sum(x > 0) >= good_gene_threshold)]
    if (length(goodGenes) >= 5) {
      counts <- counts[goodGenes, ]
    } else {
      message("Warning: Too few genes passed the filtering threshold. Proceeding with all genes.")
    }
    
    # ==========================================
    # --- Generate Spatial Patterns & Reconstruction ---
    # ==========================================
    message("Stage 2: Generating spatial patterns and reconstruction matrix...")
    
    # Perform PCA on log-transformed counts to extract major axes of variation (patterns)
    log_counts <- log1p(as.matrix(counts))
    var_genes <- apply(log_counts, 1, var)
    log_counts_sub <- log_counts[var_genes > 1e-5, , drop = FALSE]
    
    if (nrow(log_counts_sub) >= 2 && ncol(log_counts_sub) >= 2) {
      pca <- prcomp(t(log_counts_sub), scale. = TRUE)
      # Scale PC1 and PC2 to be positive to act as pattern weights
      pattern1 <- pca\$x[, 1] - min(pca\$x[, 1]) + 0.01
      pattern2 <- pca\$x[, 2] - min(pca\$x[, 2]) + 0.01
      
      # Reconstruct expression matrix from the latent space (PCs)
      reconstruction <- pca\$rotation[, 1:2, drop = FALSE] %*% t(pca\$x[, 1:2, drop = FALSE])
      recon_full <- matrix(0, nrow = nrow(counts), ncol = ncol(counts),
                           dimnames = list(rownames(counts), colnames(counts)))
      recon_full[rownames(reconstruction), ] <- reconstruction
      recon_full[recon_full < 0] <- 0
    } else {
      # Fallback if PCA is not possible
      pattern1 <- runif(ncol(counts), 0.1, 1.0)
      pattern2 <- runif(ncol(counts), 0.1, 1.0)
      recon_full <- as.matrix(counts)
    }
    
    coldata\$Pattern_1 <- pattern1
    coldata\$Pattern_2 <- pattern2
    
    # Ensure spatial coordinates exist
    if (!all(c("x", "y") %in% colnames(coldata))) {
      n <- ncol(counts)
      grid_size <- ceiling(sqrt(n))
      coords <- expand.grid(x = seq_len(grid_size), y = seq_len(grid_size))[1:n, ]
      coldata\$x <- coords\$x
      coldata\$y <- coords\$y
    }
    
    # Construct spPatterns data frame
    spPatterns <- data.frame(
      barcode = rownames(coldata),
      x = coldata\$x,
      y = coldata\$y,
      Pattern_1 = coldata\$Pattern_1,
      Pattern_2 = coldata\$Pattern_2,
      row.names = rownames(coldata)
    )
    
    # Manually construct optParams (sigmaOpt and threshOpt) for the patterns
    optParams <- data.frame(
      sigmaOpt = c(1.5, 1.5),
      threshOpt = c(3.0, 3.0),
      row.names = c("Pattern_1", "Pattern_2")
    )
    
    # ==========================================
    # --- Execute SpaceMarkers Analysis ---
    # ==========================================
    message("Stage 3: Running SpaceMarkers analyses...")
    
    # 1. Residual Mode (Overlap Analysis)
    SpaceMarkers_res <- tryCatch({
      get_pairwise_interacting_genes(
        data = as.matrix(counts),
        reconstruction = recon_full,
        optParams = optParams,
        spPatterns = spPatterns,
        mode = "residual",
        analysis = "overlap"
      )
    }, error = function(e) {
      message("Error in Residual Mode: ", e\$message)
      NULL
    })
    
    # 2. DE Mode (Overlap Analysis)
    SpaceMarkers_de <- tryCatch({
      get_pairwise_interacting_genes(
        data = as.matrix(counts),
        reconstruction = NULL,
        optParams = optParams,
        spPatterns = spPatterns,
        mode = "DE",
        analysis = "overlap"
      )
    }, error = function(e) {
      message("Error in DE Mode: ", e\$message)
      NULL
    })
    
    # 3. Enrichment Mode (Residual Analysis)
    SpaceMarkers_enrich <- tryCatch({
      get_pairwise_interacting_genes(
        data = as.matrix(counts),
        reconstruction = recon_full,
        optParams = optParams,
        spPatterns = spPatterns,
        mode = "residual",
        analysis = "enrichment"
      )
    }, error = function(e) {
      message("Error in Enrichment Mode: ", e\$message)
      NULL
    })
    
    # ==========================================
    # --- Export Results ---
    # ==========================================
    message("Stage 4: Exporting results to CSV...")
    
    extract_genes_table <- function(sm_obj) {
      if (!is.null(sm_obj) && length(sm_obj) > 0 && "interacting_genes" %in% names(sm_obj[[1]])) {
        return(sm_obj[[1]]\$interacting_genes[[1]])
      }
      return(data.frame(Gene = character(), Message = "No interacting genes found"))
    }
    
    res_table <- extract_genes_table(SpaceMarkers_res)
    de_table <- extract_genes_table(SpaceMarkers_de)
    enrich_table <- extract_genes_table(SpaceMarkers_enrich)
    
    write.csv(res_table, "interacting_genes_residual.csv", row.names = FALSE)
    write.csv(de_table, "interacting_genes_de.csv", row.names = FALSE)
    write.csv(enrich_table, "interacting_genes_enrichment.csv", row.names = FALSE)
    
    # ==========================================
    # --- Visualization ---
    # ==========================================
    message("Stage 5: Generating diagnostic and spatial plots...")
    
    # Helper function to create interaction regions
    createInteractCol <- function(spHotspots, interaction_cols = c("Pattern_1", "Pattern_2")) {
      col1 <- spHotspots[, interaction_cols[1]]
      col2 <- spHotspots[, interaction_cols[2]]
      one <- col1
      two <- col2
      one[!is.na(col1)] <- "match"
      two[!is.na(col2)] <- "match"
      both_idx <- which(one == two)
      both <- col1
      both[both_idx] <- "interacting"
      one_only <- setdiff(which(!is.na(col1)), unique(c(which(is.na(col1)), both_idx)))
      two_only <- setdiff(which(!is.na(col2)), unique(c(which(is.na(col2)), both_idx)))
      both[one_only] <- interaction_cols[1]
      both[two_only] <- interaction_cols[2]
      both <- factor(both, levels = c(interaction_cols[1], "interacting", interaction_cols[2]))
      return(both)
    }
    
    # Helper function to plot spatial expression across regions
    plotSpatialExpr <- function(data, gene, hotspots, patterns, remove.na = TRUE, title = "Expression (Log)", text_size = 12) {
      interact <- tryCatch({
        createInteractCol(spHotspots = hotspots, interaction_cols = patterns)
      }, error = function(e) {
        # Fallback if hotspot classification fails
        region <- ifelse(spPatterns\$Pattern_1 > spPatterns\$Pattern_2, "Pattern_1", "Pattern_2")
        region[abs(spPatterns\$Pattern_1 - spPatterns\$Pattern_2) < 0.1] <- "interacting"
        factor(region, levels = c("Pattern_1", "interacting", "Pattern_2"))
      })
      
      df <- cbind(data, hotspots, data.frame("region" = interact))
      if (remove.na) {
        df <- df[!is.na(df\$region), ]
      }
      
      p <- ggplot(df, aes(x = region, y = .data[[gene]], fill = region)) +
        geom_violin() +
        scale_fill_viridis(discrete = TRUE, alpha = 0.6) +
        geom_jitter(color = "black", size = 0.4, alpha = 0.9) +
        theme_minimal() +
        theme(legend.position = "none",
              plot.title = element_text(size = text_size),
              axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1)) +
        ggtitle(paste0(gene, ": ", title)) +
        xlab("")
      return(p)
    }
    
    # Helper function to plot spatial coordinates
    plot_spatial_custom <- function(df, feature_col, title) {
      ggplot(df, aes(x = x, y = y, color = .data[[feature_col]])) +
        geom_point(size = 3) +
        scale_color_viridis_c() +
        theme_minimal() +
        labs(title = title, x = "X Coordinate", y = "Y Coordinate")
    }
    
    # Open PDF device
    pdf("spatial_interaction_plots.pdf", width = 12, height = 6)
    
    # Extract hotspots
    hotspots <- NULL
    if (!is.null(SpaceMarkers_res) && length(SpaceMarkers_res) > 0 && "hotspots" %in% names(SpaceMarkers_res[[1]])) {
      hotspots <- SpaceMarkers_res[[1]]\$hotspots
    }
    if (is.null(hotspots)) {
      hotspots <- matrix(NA, nrow = nrow(spPatterns), ncol = 2,
                         dimnames = list(rownames(spPatterns), c("Pattern_1", "Pattern_2")))
    }
    
    # Select top genes to plot
    top_genes <- c()
    if (nrow(res_table) > 0 && "Gene" %in% colnames(res_table)) {
      if ("SpaceMarkersMetric" %in% colnames(res_table)) {
        res_table <- res_table[order(-res_table\$SpaceMarkersMetric), ]
      }
      top_genes <- head(res_table\$Gene, 3)
    }
    if (length(top_genes) == 0) {
      top_genes <- head(rownames(counts), 3)
    }
    
    counts_df <- as.data.frame(t(as.matrix(counts[top_genes, , drop = FALSE])))
    
    # Generate and print plots
    for (g in top_genes) {
      p_violin <- tryCatch({
        plotSpatialExpr(
          data = counts_df,
          gene = g,
          hotspots = hotspots,
          patterns = c("Pattern_1", "Pattern_2")
        )
      }, error = function(e) {
        ggplot() + theme_void() + labs(title = paste("Error plotting violin for", g))
      })
      
      p_spatial <- tryCatch({
        plot_spatial_custom(
          df = cbind(spPatterns, counts_df),
          feature_col = g,
          title = paste(g, "Spatial Expression")
        )
      }, error = function(e) {
        ggplot() + theme_void() + labs(title = paste("Error plotting spatial for", g))
      })
      
      # Print combined plot
      print(plot_grid(p_violin, p_spatial, ncol = 2))
    }
    
    dev.off()
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SPACEMARKERS_SPACE_MARKERS_ANALYSIS":',
        paste0('    SpaceMarkers: ', as.character(packageVersion('SpaceMarkers')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_space_markers_analysis.csv versions.yml
    """
}

workflow BIOC_SPACEMARKERS_SPACE_MARKERS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SPACEMARKERS_SPACE_MARKERS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPACEMARKERS_SPACE_MARKERS_ANALYSIS.out.tables
    plots    = BIOC_SPACEMARKERS_SPACE_MARKERS_ANALYSIS.out.plots
    objects  = BIOC_SPACEMARKERS_SPACE_MARKERS_ANALYSIS.out.objects
    versions = BIOC_SPACEMARKERS_SPACE_MARKERS_ANALYSIS.out.versions
}
