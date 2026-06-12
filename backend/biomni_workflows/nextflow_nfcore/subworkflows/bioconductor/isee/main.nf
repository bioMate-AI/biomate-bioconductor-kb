#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iSEE — isee_single_cell_explorer
// Build a complete SummarizedExperiment object from raw single-cell count and metadata files, perform normalization, compute PCA, calculate row/column statistics,
// Input: counts.csv, coldata.csv
// Container: 2.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, iSEE, viridis
// Visualizations: PCA plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEE_ISEE_SINGLE_CELL_EXPLORER {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
    .bm_deps <- c("iSEE", "SummarizedExperiment")
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
    
    # --- Load libraries and read input data ---    library(SummarizedExperiment)

    library(iSEE)
    
    # Read counts.csv (gene-by-cell count matrix, column 'gene_id' contains row names)
    counts_df <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!"gene_id" %in% colnames(counts_df)) {
      stop("counts.csv must contain a 'gene_id' column.")
    }
    rownames(counts_df) <- counts_df\$gene_id
    counts_df\$gene_id <- NULL
    counts_matrix <- as.matrix(counts_df)
    
    # Read coldata.csv (per-cell metadata with 'cell' and optional 'group')
    coldata_df <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!"cell" %in% colnames(coldata_df)) {
      stop("coldata.csv must contain a 'cell' column.")
    }
    rownames(coldata_df) <- coldata_df\$cell
    
    # Align cells between counts and coldata
    common_cells <- intersect(colnames(counts_matrix), rownames(coldata_df))
    if (length(common_cells) == 0) {
      stop("No common cells found between counts.csv and coldata.csv.")
    }
    counts_matrix <- counts_matrix[, common_cells, drop = FALSE]
    coldata_df <- coldata_df[common_cells, , drop = FALSE]
    
    # --- Normalization and Dimensionality Reduction (PCA) ---
    # Compute log-normalized counts (log2 CPM-like values)
    libsizes <- colSums(counts_matrix)
    libsizes[libsizes == 0] <- 1  # Prevent division by zero
    logcounts_matrix <- log2(t(t(counts_matrix) / libsizes) * 1e6 + 1)
    
    # Identify highly variable genes for PCA
    gene_vars <- apply(logcounts_matrix, 1, var)
    n_top <- min(500, nrow(logcounts_matrix))
    top_genes <- names(sort(gene_vars, decreasing = TRUE))[1:n_top]
    
    # Run PCA manually using base R to ensure compatibility and robustness
    pca_res <- prcomp(t(logcounts_matrix[top_genes, , drop = FALSE]), scale. = TRUE)
    coldata_df\$PC1 <- pca_res\$x[, 1]
    coldata_df\$PC2 <- pca_res\$x[, 2]
    
    # --- Construct SummarizedExperiment and compute metadata ---
    se <- SummarizedExperiment(
      assays = list(counts = counts_matrix, logcounts = logcounts_matrix),
      colData = coldata_df
    )
    
    # Add gene-level metadata to rowData
    rowData(se)\$mean_log <- rowMeans(logcounts_matrix)
    rowData(se)\$var_log <- gene_vars
    
    # --- Configure Custom Colormaps (ExperimentColorMap) ---
    col_list <- list()
    if ("group" %in% colnames(coldata_df)) {
      unique_groups <- unique(coldata_df\$group)
      group_colors <- rainbow(length(unique_groups))
      names(group_colors) <- unique_groups
      group_color_fun <- function(n) {
        group_colors
      }
      col_list\$group <- group_color_fun
    }
    
    ecm <- ExperimentColorMap(
      assays = list(
        logcounts = viridis::viridis,
        counts = heat.colors
      ),
      colData = col_list
    )
    
    # --- Programmatically configure initial iSEE panels ---
    # 1. ColumnDataPlot to visualize PCA coordinates computed manually
    cdp <- ColumnDataPlot(
      XAxis = "Column data",
      XAxisColumnData = "PC1",
      YAxis = "PC2",
      ColorBy = if ("group" %in% colnames(coldata_df)) "Column data" else "None",
      ColorByColumnData = if ("group" %in% colnames(coldata_df)) "group" else "PC1",
      PanelWidth = 6L
    )
    
    # 2. FeatureAssayPlot to visualize the top variable gene expression across groups
    top_gene <- top_genes[1]
    fap <- FeatureAssayPlot(
      YAxisFeatureName = top_gene,
      XAxis = if ("group" %in% colnames(coldata_df)) "Column data" else "None",
      XAxisColumnData = if ("group" %in% colnames(coldata_df)) "group" else "PC1",
      PanelWidth = 6L
    )
    
    # 3. RowDataTable to allow interactive selection of genes
    rdt <- RowDataTable(
      PanelWidth = 12L
    )
    
    # 4. ComplexHeatmapPlot to visualize expression patterns of top variable genes
    chp <- ComplexHeatmapPlot(
      PanelWidth = 12L
    )
    
    initial_panels <- list(cdp, fap, rdt, chp)
    
    # --- Build and Save the iSEE App Configuration ---
    app <- iSEE(se, initial = initial_panels, colormap = ecm)
    saveRDS(app, "isee_app.rds")
    
    # --- Generate static diagnostic outputs ---
    # Save static PCA plot
    pdf("pca_summary.pdf", width = 7, height = 6)
    if ("group" %in% colnames(coldata_df)) {
      plot(coldata_df\$PC1, coldata_df\$PC2, col = as.factor(coldata_df\$group),
           pch = 16, xlab = "PC1", ylab = "PC2", main = "Manually Computed PCA")
      legend("topright", legend = levels(as.factor(coldata_df\$group)),
             col = 1:length(unique(coldata_df\$group)), pch = 16)
    } else {
      plot(coldata_df\$PC1, coldata_df\$PC2, pch = 16, xlab = "PC1", ylab = "PC2",
           main = "Manually Computed PCA")
    }
    dev.off()
    
    # Save top variable genes table
    top_genes_df <- data.frame(
      gene_id = top_genes,
      mean_log = rowData(se)\$mean_log[top_genes],
      var_log = rowData(se)\$var_log[top_genes]
    )
    write.csv(top_genes_df, "top_variable_genes.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_ISEE_ISEE_SINGLE_CELL_EXPLORER":',
        paste0('    iSEE: ', as.character(packageVersion('iSEE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isee_single_cell_explorer.csv versions.yml
    """
}

workflow BIOC_ISEE_ISEE_SINGLE_CELL_EXPLORER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ISEE_ISEE_SINGLE_CELL_EXPLORER(ch_input)

    emit:
    tables   = BIOC_ISEE_ISEE_SINGLE_CELL_EXPLORER.out.tables
    plots    = BIOC_ISEE_ISEE_SINGLE_CELL_EXPLORER.out.plots
    objects  = BIOC_ISEE_ISEE_SINGLE_CELL_EXPLORER.out.objects
    versions = BIOC_ISEE_ISEE_SINGLE_CELL_EXPLORER.out.versions
}
