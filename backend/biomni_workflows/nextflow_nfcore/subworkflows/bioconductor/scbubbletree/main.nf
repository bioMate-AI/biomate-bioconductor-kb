#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scBubbletree — sc_bubbletree_louvain_workflow
// Determine clustering resolution, perform Louvain clustering, build a bubbletree, and annotate it with categorical and numeric features.
// Input: A, m, e
// Container: quay.io/biocontainers/bioconductor-scbubbletree:1.12.0--r45hdfd78af_0
// R packages: ggplot2, ggtree, patchwork, scBubbletree
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, ggtree, patchwork, scBubbletree
// Visualizations: phylogenetic tree
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Inputs from Working Directory
//  * 2. [Visualization & Output] Determine Louvain Resolution Parameter r Using get_r
//  * 3. [Visualization & Output] Perform Louvain Clustering and Hierarchical Grouping
//  * 4. [Visualization & Output] Annotate Bubbletree with Categorical Features
//  * 5. [Visualization & Output] Annotate Bubbletree with Numeric Features
//  * 6. [Visualization & Output] Visualize Individual Cell Features

nextflow.enable.dsl = 2

process BIOC_SCBUBBLETREE_SC_BUBBLETREE_LOUVAIN_WORKFLOW {
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
    .bm_deps <- c("ggplot2", "ggtree", "patchwork", "scBubbletree")
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
    library(scBubbletree)
    library(ggplot2)
    library(ggtree)
    library(patchwork)
    
    # ==========================================
    # --- Read User Inputs from Working Directory ---
    # ==========================================
    
    # Read A (low-dimensional PCA embedding matrix)
    if (file.exists("A.rds")) {
      A <- readRDS("A.rds")
    } else if (file.exists("A.csv")) {
      A <- as.matrix(read.csv("A.csv", row.names = 1))
    } else {
      stop("Error: Input file 'A' (PCA embedding matrix) not found as 'A.rds' or 'A.csv' in the working directory.")
    }
    
    # Read m (cell metadata dataframe)
    if (file.exists("m.rds")) {
      m <- readRDS("m.rds")
    } else if (file.exists("m.csv")) {
      m <- read.csv("m.csv", row.names = 1)
    } else {
      stop("Error: Input file 'm' (cell metadata dataframe) not found as 'm.rds' or 'm.csv' in the working directory.")
    }
    
    # Read e (normalized marker gene expression matrix)
    if (file.exists("e.rds")) {
      e <- readRDS("e.rds")
    } else if (file.exists("e.csv")) {
      e <- as.matrix(read.csv("e.csv", row.names = 1))
    } else {
      stop("Error: Input file 'e' (normalized marker gene expression matrix) not found as 'e.rds' or 'e.csv' in the working directory.")
    }
    
    # Ensure row names match across inputs
    common_cells <- intersect(rownames(A), rownames(m))
    if (!is.null(rownames(e))) {
      common_cells <- intersect(common_cells, rownames(e))
    }
    
    if (length(common_cells) == 0) {
      warning("Warning: No overlapping cell IDs found between inputs. Proceeding with raw inputs as-is.")
    } else {
      A <- A[common_cells, , drop = FALSE]
      m <- m[common_cells, , drop = FALSE]
      if (!is.null(rownames(e))) {
        e <- e[common_cells, , drop = FALSE]
      } else {
        e <- e[1:length(common_cells), , drop = FALSE]
      }
    }
    
    # =========================================================================
    # --- Determine Louvain Resolution Parameter r Using get_r ---
    # =========================================================================
    message("Determining clustering resolution...")
    b_r <- get_r(B_gap = 5,
                 rs = 10^seq(from = -4, to = 0.5, by = 0.5),
                 x = A,
                 n_start = 10,
                 iter_max = 50,
                 algorithm = "original",
                 knn_k = 50,
                 cores = 1)
    
    # Save resolution results
    saveRDS(b_r, "b_r_resolution_results.rds")
    write.csv(b_r\$gap_stats_summary, "gap_stats_summary.csv", row.names = FALSE)
    
    # Plot Gap statistic curve
    p_gap <- ggplot(data = b_r\$gap_stats_summary) +
      geom_line(aes(x = r, y = gap_mean)) +
      geom_point(aes(x = r, y = gap_mean), size = 1) +
      geom_errorbar(aes(x = r, y = gap_mean, ymin = L95, ymax = H95), width = 0.1) +
      ylab(label = "Gap") +
      xlab(label = "r") +
      scale_x_log10() +
      annotation_logticks(base = 10, sides = "b") +
      theme_bw()
    
    pdf("gap_statistic_plot.pdf", width = 6, height = 5)
    print(p_gap)
    dev.off()
    
    # =========================================================================
    # --- Perform Louvain Clustering and Hierarchical Grouping ---
    # =========================================================================
    message("Performing Louvain clustering and building bubbletree...")
    l <- get_bubbletree_graph(x = A,
                              r = 0.1,
                              algorithm = "original",
                              n_start = 20,
                              iter_max = 100,
                              knn_k = 50,
                              cores = 1,
                              B = 300,
                              N_eff = 200,
                              round_digits = 1,
                              show_simple_count = FALSE)
    
    # Save bubbletree results
    saveRDS(l, "bubbletree_graph_results.rds")
    write.csv(l\$tree_meta, "bubbletree_tree_meta.csv", row.names = FALSE)
    
    # =========================================================================
    # --- Annotate Bubbletree with Categorical Features ---
    # =========================================================================
    message("Attaching categorical features...")
    # Ensure the metadata column exists; fallback to first column if not found
    cat_feature_col <- "cell_line_demuxlet"
    if (!cat_feature_col %in% colnames(m)) {
      cat_feature_col <- colnames(m)[1]
      message(paste("Specified metadata column 'cell_line_demuxlet' not found. Using:", cat_feature_col))
    }
    
    w1 <- get_cat_tiles(btd = l,
                        f = m[[cat_feature_col]],
                        integrate_vertical = TRUE,
                        round_digits = 1,
                        x_axis_name = 'Cell line',
                        rotate_x_axis_labels = TRUE,
                        tile_text_size = 2.75)
    
    # Save categorical annotation plot
    pdf("bubbletree_categorical_tiles.pdf", width = 10, height = 6)
    p_cat <- (l\$tree | w1\$plot) + patchwork::plot_layout(widths = c(1, 1))
    print(p_cat)
    dev.off()
    
    # =========================================================================
    # --- Annotate Bubbletree with Numeric Features ---
    # =========================================================================
    message("Attaching numeric features...")
    w3 <- get_num_tiles(btd = l,
                        fs = e,
                        summary_function = "mean",
                        x_axis_name = 'Gene expression',
                        rotate_x_axis_labels = TRUE,
                        round_digits = 1,
                        tile_text_size = 2.75)
    
    w4 <- get_num_violins(btd = l,
                          fs = e,
                          x_axis_name = 'Gene expression',
                          rotate_x_axis_labels = TRUE)
    
    # Save numeric annotation plots
    pdf("bubbletree_numeric_annotations.pdf", width = 12, height = 6)
    p_num <- (l\$tree | w3\$plot | w4\$plot) +
      patchwork::plot_layout(widths = c(1.5, 2, 2.5)) +
      patchwork::plot_annotation(tag_levels = 'A')
    print(p_num)
    dev.off()
    
    # =========================================================================
    # --- Visualize Individual Cell Features ---
    # =========================================================================
    message("Visualizing individual cell features...")
    g_cell_feature_1 <- get_num_cell_tiles(btd = l,
                                           f = e[, 1],
                                           tile_bw = FALSE,
                                           x_axis_name = paste(colnames(e)[1], "gene expr."),
                                           rotate_x_axis_labels = FALSE)
    
    # Save individual cell feature plot
    pdf("bubbletree_individual_cell_features.pdf", width = 10, height = 6)
    p_cell <- (l\$tree | g_cell_feature_1\$plot) + patchwork::plot_layout(widths = c(1, 1))
    print(p_cell)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_SCBUBBLETREE_SC_BUBBLETREE_LOUVAIN_WORKFLOW":',
        paste0('    scBubbletree: ', as.character(packageVersion('scBubbletree')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_bubbletree_louvain_workflow.csv versions.yml
    """
}

workflow BIOC_SCBUBBLETREE_SC_BUBBLETREE_LOUVAIN_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ A, m, e ] ]

    main:
    BIOC_SCBUBBLETREE_SC_BUBBLETREE_LOUVAIN_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SCBUBBLETREE_SC_BUBBLETREE_LOUVAIN_WORKFLOW.out.tables
    plots    = BIOC_SCBUBBLETREE_SC_BUBBLETREE_LOUVAIN_WORKFLOW.out.plots
    objects  = BIOC_SCBUBBLETREE_SC_BUBBLETREE_LOUVAIN_WORKFLOW.out.objects
    versions = BIOC_SCBUBBLETREE_SC_BUBBLETREE_LOUVAIN_WORKFLOW.out.versions
}
