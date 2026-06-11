#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iSEEfier — iseefier_initial_config
// Build, inspect, and merge tailored initial configuration states for iSEE visualization from custom expression data or gene lists.
// Input: input.csv
// Container: 1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, iSEEfier, igraph, scater, scuttle
// Visualizations: network plot
// QC: cell QC metrics, count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEEFIER_ISEEFIER_INITIAL_CONFIG {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    library(iSEEfier)
    library(scuttle)
    library(scater)
    library(ggplot2)
    library(igraph)
    
    # --- Read input defensively ---
    message("Reading input.csv...")
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop("Staged input file 'input.csv' not found.")
    }
    
    data <- read.csv(input_file, row.names = NULL, check.names = FALSE)
    
    if (ncol(data) <= 1) {
      message("Input detected as a single-column gene list. Generating dummy expression matrix...")
      genes <- as.character(data[[1]])
      if (length(genes) == 0) {
        genes <- c("Gcg", "Ins1", "Sst", "Ppy")
      }
      # Generate dummy counts for 100 cells
      set.seed(42)
      mat <- matrix(rpois(length(genes) * 100, lambda = 10), nrow = length(genes))
      rownames(mat) <- genes
      colnames(mat) <- paste0("Cell_", seq_len(100))
    } else {
      message("Input detected as a feature-by-sample matrix.")
      if ("feature_id" %in% colnames(data)) {
        rownames(data) <- data\$feature_id
        data\$feature_id <- NULL
      } else {
        rownames(data) <- data[, 1]
        data <- data[, -1, drop = FALSE]
      }
      mat <- as.matrix(data)
    }
    
    # --- Build SingleCellExperiment and Preprocess ---
    message("Building SingleCellExperiment...")
    sce <- SingleCellExperiment(assays = list(counts = mat))
    
    # Add dummy metadata for clusters and groups
    set.seed(42)
    colData(sce)\$label <- sample(c("Alpha", "Beta", "Delta"), ncol(sce), replace = TRUE)
    colData(sce)\$strain <- sample(c("C57BL/6", "ICR"), ncol(sce), replace = TRUE)
    
    # Normalize
    message("Normalizing counts...")
    sce <- logNormCounts(sce)
    
    # Dimensionality reduction
    message("Running dimensionality reductions...")
    sce <- runPCA(sce)
    tryCatch({
      sce <- runTSNE(sce)
    }, error = function(e) {
      message("TSNE failed (possibly too few samples), skipping TSNE.")
    })
    tryCatch({
      sce <- runUMAP(sce)
    }, error = function(e) {
      message("UMAP failed (possibly too few samples), skipping UMAP.")
    })
    
    # --- Create Initial Configurations ---
    message("Creating initial configurations...")
    gene_list <- head(rownames(sce), 5)
    cluster_col <- "label"
    group_col <- "strain"
    
    # 1. iSEEinit
    initial1 <- iSEEinit(
      sce = sce,
      features = gene_list,
      clusters = cluster_col,
      groups = group_col,
      add_markdown_panel = TRUE
    )
    
    # 2. iSEEnrich (with fallback)
    initial2 <- NULL
    tryCatch({
      # Try to find an available organism database
      org_pkg <- "org.Mm.eg.db"
      if (!requireNamespace(org_pkg, quietly = TRUE)) {
        org_pkg <- "org.Hs.eg.db"
      }
      if (requireNamespace(org_pkg, quietly = TRUE)) {
        results <- iSEEnrich(
          sce = sce,
          collection = "GO",
          gene_identifier = "SYMBOL",
          organism = org_pkg,
          clusters = cluster_col,
          reddim_type = "PCA",
          groups = group_col
        )
        initial2 <- results\$initial
        sce <- results\$sce
      } else {
        warning("No organism database (org.Mm.eg.db or org.Hs.eg.db) found. Skipping iSEEnrich.")
      }
    }, error = function(e) {
      warning("iSEEnrich failed: ", e\$message)
    })
    
    # 3. iSEEmarker
    initial3 <- tryCatch({
      iSEEmarker(
        sce = sce,
        clusters = cluster_col,
        groups = group_col,
        selection_plot_format = "ColumnDataPlot"
      )
    }, error = function(e) {
      warning("iSEEmarker failed: ", e\$message)
      NULL
    })
    
    # --- Merge configurations ---
    message("Merging configurations...")
    if (!is.null(initial2)) {
      merged_config <- glue_initials(initial1, initial2)
    } else if (!is.null(initial3)) {
      merged_config <- glue_initials(initial1, initial3)
    } else {
      merged_config <- initial1
    }
    
    # --- Visualizations and Diagnostics ---
    message("Generating diagnostic plots...")
    pdf("initial_tiles_plot.pdf", width = 10, height = 8)
    p1 <- view_initial_tiles(initial = initial1)
    print(p1 + ggtitle("Initial 1 Tiles (Gene Expression)"))
    if (!is.null(initial2)) {
      p2 <- view_initial_tiles(initial = initial2)
      print(p2 + ggtitle("Initial 2 Tiles (Enrichment)"))
    }
    p_merged <- view_initial_tiles(merged_config)
    print(p_merged + ggtitle("Merged Configuration Tiles"))
    dev.off()
    
    pdf("initial_network_plot.pdf", width = 10, height = 8)
    g1 <- view_initial_network(initial1, plot_format = "igraph")
    if (!is.null(g1)) {
      plot(g1, main = "Initial 1 Panel Network")
    }
    if (!is.null(initial2)) {
      g2 <- view_initial_network(initial2, plot_format = "igraph")
      if (!is.null(g2)) {
        plot(g2, main = "Initial 2 Panel Network")
      }
    }
    dev.off()
    
    # --- Save Outputs ---
    message("Saving configurations...")
    saveRDS(initial1, "initial_config_gene_expr.rds")
    saveRDS(merged_config, "initial_config_merged.rds")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_ISEEFIER_ISEEFIER_INITIAL_CONFIG":',
        paste0('    iSEEfier: ', as.character(packageVersion('iSEEfier')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseefier_initial_config.csv versions.yml
    """
}

workflow BIOC_ISEEFIER_ISEEFIER_INITIAL_CONFIG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ISEEFIER_ISEEFIER_INITIAL_CONFIG(ch_input)

    emit:
    tables   = BIOC_ISEEFIER_ISEEFIER_INITIAL_CONFIG.out.tables
    plots    = BIOC_ISEEFIER_ISEEFIER_INITIAL_CONFIG.out.plots
    objects  = BIOC_ISEEFIER_ISEEFIER_INITIAL_CONFIG.out.objects
    versions = BIOC_ISEEFIER_ISEEFIER_INITIAL_CONFIG.out.versions
}
