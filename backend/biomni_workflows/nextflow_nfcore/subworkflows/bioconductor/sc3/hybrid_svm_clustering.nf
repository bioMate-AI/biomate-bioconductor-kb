#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SC3 — hybrid_svm_clustering
// Cluster large datasets (>5,000 cells) using a hybrid approach combining unsupervised clustering on a subset of cells and SVM label projection for the remaining 
// Input: expression_matrix.csv, cell_metadata.csv
// Container: quay.io/biocontainers/bioconductor-sc3:1.38.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SC3, SingleCellExperiment, scater
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run SC3 with SVM parameters to cluster training cells
//  * 2. [Core Analysis] Run SVM to predict labels for the remaining cells
//  * 3. [Core Analysis] Clear training indices and recalculate biological features for all cells

nextflow.enable.dsl = 2

process BIOC_SC3_HYBRID_SVM_CLUSTERING {
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
    .bm_deps <- c("SC3", "scater", "SummarizedExperiment")
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
    library(SC3)
    library(SummarizedExperiment)
    library(scater)
    
    # Read user input files
    expr_matrix <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    cell_metadata <- read.csv("cell_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align metadata with expression matrix columns
    common_cells <- intersect(colnames(expr_matrix), rownames(cell_metadata))
    if (length(common_cells) == 0) {
        stop("No common cells found between expression matrix columns and cell metadata rows.")
    }
    expr_matrix <- expr_matrix[, common_cells, drop = FALSE]
    cell_metadata <- cell_metadata[common_cells, , drop = FALSE]
    
    # Construct SingleCellExperiment object
    # SC3 requires both 'counts' and 'logcounts' assays to exist.
    # We assume the input expression matrix is normalized. We will use it for both.
    sce <- SingleCellExperiment(
        assays = list(
            counts = as.matrix(expr_matrix),
            logcounts = as.matrix(expr_matrix)
        ),
        colData = cell_metadata
    )
    
    # Define feature names in feature_symbol column
    rowData(sce)\$feature_symbol <- rownames(sce)
    
    # Remove features with duplicated names
    sce <- sce[!duplicated(rowData(sce)\$feature_symbol), ]
    
    # Determine a proportionally appropriate number of training cells for SVM
    # SC3 defaults to 5000 for datasets > 5000 cells. For smaller datasets, we use 20% of cells (minimum 50).
    svm_cells <- min(5000, max(50, round(ncol(sce) * 0.2)))
    # Ensure we do not request more training cells than available (must be a strict subset)
    svm_cells <- min(svm_cells, ncol(sce) - 1)
    
    # 1. Run SC3 with SVM parameters to cluster training cells
    sce <- sc3(sce, ks = 2:4, biology = TRUE, svm_num_cells = svm_cells)
    
    # 2. Run SVM to predict labels for the remaining cells
    sce <- sc3_run_svm(sce, ks = 2:4)
    
    # 3. Clear training indices and recalculate biological features for all cells
    metadata(sce)\$sc3\$svm_train_inds <- NULL
    sce <- sc3_calc_biology(sce, ks = 2:4)
    
    # Save the SingleCellExperiment object
    saveRDS(sce, "sc3_sce_output.rds")
    
    # Save cell metadata with clustering results
    write.csv(as.data.frame(colData(sce)), "sc3_cell_metadata_clustering.csv", row.names = TRUE)
    
    # Save gene metadata with biological features (DE, markers, etc.)
    write.csv(as.data.frame(rowData(sce)), "sc3_gene_metadata_biology.csv", row.names = TRUE)
    
    # Generate and save diagnostic/results plots
    pdf("sc3_plots.pdf", width = 8, height = 8)
    
    # We use tryCatch for plots to ensure the pipeline completes even if some plots fail due to data specifics
    tryCatch({
        sc3_plot_consensus(sce, k = 3)
    }, error = function(e) {
        message("Could not plot consensus matrix: ", e\$message)
    })
    
    tryCatch({
        sc3_plot_silhouette(sce, k = 3)
    }, error = function(e) {
        message("Could not plot silhouette: ", e\$message)
    })
    
    tryCatch({
        sc3_plot_expression(sce, k = 3)
    }, error = function(e) {
        message("Could not plot expression: ", e\$message)
    })
    
    tryCatch({
        sc3_plot_cluster_stability(sce, k = 3)
    }, error = function(e) {
        message("Could not plot cluster stability: ", e\$message)
    })
    
    tryCatch({
        sc3_plot_de_genes(sce, k = 3)
    }, error = function(e) {
        message("Could not plot DE genes: ", e\$message)
    })
    
    tryCatch({
        sc3_plot_markers(sce, k = 3)
    }, error = function(e) {
        message("Could not plot marker genes: ", e\$message)
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_SC3_HYBRID_SVM_CLUSTERING":',
        paste0('    SC3: ', as.character(packageVersion('SC3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hybrid_svm_clustering.csv versions.yml
    """
}

workflow BIOC_SC3_HYBRID_SVM_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, cell_metadata.csv ] ]

    main:
    BIOC_SC3_HYBRID_SVM_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SC3_HYBRID_SVM_CLUSTERING.out.tables
    plots    = BIOC_SC3_HYBRID_SVM_CLUSTERING.out.plots
    objects  = BIOC_SC3_HYBRID_SVM_CLUSTERING.out.objects
    versions = BIOC_SC3_HYBRID_SVM_CLUSTERING.out.versions
}
