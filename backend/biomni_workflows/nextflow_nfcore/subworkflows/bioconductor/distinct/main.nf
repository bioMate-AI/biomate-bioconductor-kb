#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: distinct — distinct_differential_state_analysis
// Perform differential state analysis across cell clusters between two conditions using hierarchical non-parametric permutation tests.
// Input: counts.csv, coldata.csv
// Container: 1.22.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, distinct, ggplot2
// Visualizations: plot (ggplot/base)
// QC: low-count filtering, count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DISTINCT_DISTINCT_DIFFERENTIAL_STATE_ANALYSIS {
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
    .bm_deps <- c("distinct", "ggplot2")
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
    library(distinct)
    library(ggplot2)
    
    # ==========================================
    # --- Load and Align Input Data ---
    # ==========================================
    message("Loading input data...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Ensure required columns exist in coldata
    if (!"sample" %in% colnames(coldata) || !"condition" %in% colnames(coldata)) {
        stop("coldata.csv must contain 'sample' and 'condition' columns")
    }
    
    # Align counts and coldata columns/rows
    common_cells <- intersect(colnames(counts), rownames(coldata))
    if (length(common_cells) == 0) {
        stop("No common cell identifiers found between counts.csv columns and coldata.csv row names.")
    }
    counts <- counts[, common_cells, drop = FALSE]
    coldata <- coldata[common_cells, , drop = FALSE]
    
    # Convert condition and sample to factors
    coldata\$condition <- as.factor(coldata\$condition)
    coldata\$sample <- as.factor(coldata\$sample)
    
    # ==========================================
    # --- Quality Control & Normalization ---
    # ==========================================
    message("Performing quality control and normalization...")
    # Filter out genes with zero counts across all cells
    counts <- counts[rowSums(counts) > 0, , drop = FALSE]
    
    # Filter out cells with extremely low counts (QC)
    cell_sums <- colSums(counts)
    keep_cells <- cell_sums >= 50
    counts <- counts[, keep_cells, drop = FALSE]
    coldata <- coldata[keep_cells, , drop = FALSE]
    
    # Compute CPM (Counts Per Million) and logcounts
    libs <- colSums(counts)
    cpm <- t(t(counts) / libs) * 1e6
    logcounts <- log2(cpm + 1)
    
    # ==========================================
    # --- Unsupervised Cell Clustering ---
    # ==========================================
    message("Performing unsupervised cell clustering...")
    # Identify top highly variable genes for PCA-based clustering
    vars <- apply(logcounts, 1, var)
    top_genes <- names(sort(vars, decreasing = TRUE))[1:min(500, nrow(logcounts))]
    
    # Run PCA on top variable genes
    pca <- prcomp(t(logcounts[top_genes, ]))
    
    # Cluster cells using k-means on top PC components
    set.seed(42)
    n_clusters <- min(3, ncol(counts))
    clusters <- factor(paste0("Cluster_", kmeans(pca\$x[, 1:min(5, ncol(pca\$x))], centers = n_clusters)\$cluster))
    coldata\$cluster <- clusters
    
    # ==========================================
    # --- Build SingleCellExperiment Object ---
    # ==========================================
    sce <- SingleCellExperiment(
        assays = list(
            counts = as.matrix(counts),
            logcounts = as.matrix(logcounts),
            cpm = as.matrix(cpm)
        ),
        colData = coldata
    )
    
    # ==========================================
    # --- Set up Experimental Design ---
    # ==========================================
    message("Setting up experimental design...")
    # Extract unique sample-to-condition mapping
    sample_info <- unique(as.data.frame(colData(sce)[, c("sample", "condition")]))
    sample_info\$condition <- as.factor(sample_info\$condition)
    
    # Create design matrix (rownames must match sample IDs)
    design <- model.matrix(~ condition, data = sample_info)
    rownames(design) <- sample_info\$sample
    
    # ==========================================
    # --- Run Differential State Testing ---
    # ==========================================
    message("Running distinct differential testing...")
    set.seed(61217)
    
    res <- distinct_test(
        x = sce,
        name_assays_expression = "logcounts",
        name_cluster = "cluster",
        name_sample = "sample",
        design = design,
        column_to_test = 2,
        min_non_zero_cells = 5,
        n_cores = 1
    )
    
    # ==========================================
    # --- Compute Log2 Fold Changes ---
    # ==========================================
    message("Computing log2 fold changes...")
    res <- log2_FC(
        res = res,
        x = sce,
        name_assays_expression = "cpm",
        name_group = "condition",
        name_cluster = "cluster"
    )
    
    # Extract and save top results
    top_res <- top_results(res)
    write.csv(top_res, "distinct_results.csv", row.names = FALSE)
    message("Results successfully written to distinct_results.csv")
    
    # ==========================================
    # --- Visualization of Top Results ---
    # ==========================================
    message("Generating diagnostic plots...")
    pdf("distinct_plots.pdf", width = 10, height = 5)
    
    tryCatch({
        if (nrow(top_res) > 0) {
            # Select the top significant gene-cluster pair
            top_pair <- top_res[1, ]
            top_gene <- as.character(top_pair\$gene)
            top_cluster <- as.character(top_pair\$cluster_id)
            
            # Plot densities
            p1 <- plot_densities(
                x = sce,
                gene = top_gene,
                cluster = top_cluster,
                name_assays_expression = "logcounts",
                name_cluster = "cluster",
                name_sample = "sample",
                name_group = "condition"
            ) + ggtitle(paste("Density:", top_gene, "in", top_cluster))
            
            # Plot CDFs
            p2 <- plot_cdfs(
                x = sce,
                gene = top_gene,
                cluster = top_cluster,
                name_assays_expression = "logcounts",
                name_cluster = "cluster",
                name_sample = "sample",
                name_group = "condition"
            ) + ggtitle(paste("CDF:", top_gene, "in", top_cluster))
            
            print(p1)
            print(p2)
        } else {
            plot.new()
            text(0.5, 0.5, "No significant results found to plot.")
        }
    }, error = function(e) {
        message("Plotting failed with error: ", e\$message)
        plot.new()
        text(0.5, 0.5, paste("Plotting failed:", e\$message))
    })
    
    dev.off()
    message("Plots successfully saved to distinct_plots.pdf")

    writeLines(c(
        '"BIOC_DISTINCT_DISTINCT_DIFFERENTIAL_STATE_ANALYSIS":',
        paste0('    distinct: ', as.character(packageVersion('distinct')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_distinct_differential_state_analysis.csv versions.yml
    """
}

workflow BIOC_DISTINCT_DISTINCT_DIFFERENTIAL_STATE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DISTINCT_DISTINCT_DIFFERENTIAL_STATE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DISTINCT_DISTINCT_DIFFERENTIAL_STATE_ANALYSIS.out.tables
    plots    = BIOC_DISTINCT_DISTINCT_DIFFERENTIAL_STATE_ANALYSIS.out.plots
    objects  = BIOC_DISTINCT_DISTINCT_DIFFERENTIAL_STATE_ANALYSIS.out.objects
    versions = BIOC_DISTINCT_DISTINCT_DIFFERENTIAL_STATE_ANALYSIS.out.versions
}
