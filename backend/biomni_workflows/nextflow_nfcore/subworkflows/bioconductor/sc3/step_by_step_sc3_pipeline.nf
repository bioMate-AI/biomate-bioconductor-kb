#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SC3 — step_by_step_sc3_pipeline
// Run the SC3 clustering pipeline step-by-step to inspect intermediate results and customize parameters at each stage.
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
//  * 1. [Input & Preparation] Prepare the SingleCellExperiment object
//  * 2. [Core Analysis] Estimate the optimal number of clusters k
//  * 3. [Core Analysis] Calculate distance matrices
//  * 4. [Core Analysis] Perform transformations on distance matrices
//  * 5. [Core Analysis] Run k-means clustering
//  * 6. [Core Analysis] Calculate consensus matrix and clustering solutions
//  * 7. [Core Analysis] Calculate biological features (DE, markers, outliers)

nextflow.enable.dsl = 2

process BIOC_SC3_STEP_BY_STEP_SC3_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
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
        library(SC3)
        library(SummarizedExperiment)
        library(scater)
        
        # ==========================================
        # 1. Read User Input and Prepare Object
        # ==========================================
        
        # Read the expression matrix and cell metadata
        # expression_matrix.csv: rows = genes, columns = cells
        # cell_metadata.csv: rows = cells, columns = annotations
        exprs_mat <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
        cell_meta <- read.csv("cell_metadata.csv", row.names = 1, check.names = FALSE)
        
        # Align cells between expression matrix and metadata
        common_cells <- intersect(colnames(exprs_mat), rownames(cell_meta))
        if (length(common_cells) == 0) {
            stop("Error: No common cells found between expression_matrix.csv and cell_metadata.csv")
        }
        exprs_mat <- exprs_mat[, common_cells, drop = FALSE]
        cell_meta <- cell_meta[common_cells, , drop = FALSE]
        
        # SC3 requires both 'counts' and 'logcounts' assays to exist.
        # We assume the input expression matrix is normalized.
        counts_matrix <- as.matrix(exprs_mat)
        logcounts_matrix <- log2(counts_matrix + 1)
        
        # Create SingleCellExperiment object
        sce <- SingleCellExperiment(
            assays = list(
                counts = counts_matrix,
                logcounts = logcounts_matrix
            ),
            colData = cell_meta
        )
        
        # Define feature names in feature_symbol column (required by SC3)
        rowData(sce)\$feature_symbol <- rownames(sce)
        
        # Remove features with duplicated names
        sce <- sce[!duplicated(rowData(sce)\$feature_symbol), ]
        
        # ==========================================
        # 2. Run Step-by-Step SC3 Pipeline
        # ==========================================
        
        # Step 1: Prepare the SingleCellExperiment object
        sce <- sc3_prepare(sce)
        
        # Step 2: Estimate the optimal number of clusters k
        sce <- sc3_estimate_k(sce)
        estimated_k <- metadata(sce)\$sc3\$k_estimation
        message(paste("Estimated optimal number of clusters k:", estimated_k))
        
        # Step 3: Calculate distance matrices
        sce <- sc3_calc_dists(sce)
        
        # Step 4: Perform transformations on distance matrices
        sce <- sc3_calc_transfs(sce)
        
        # Step 5: Run k-means clustering
        sce <- sc3_kmeans(sce, ks = 2:4)
        
        # Step 6: Calculate consensus matrix and clustering solutions
        sce <- sc3_calc_consens(sce)
        
        # Step 7: Calculate biological features (DE, markers, outliers)
        sce <- sc3_calc_biology(sce, ks = 2:4)
        
        # ==========================================
        # 3. Save Outputs and Generate Plots
        # ==========================================
        
        # Save the complete SingleCellExperiment object
        saveRDS(sce, "sc3_pipeline_output.rds")
        
        # Export cell-related results (clustering solutions and outlier scores)
        col_data_results <- as.data.frame(colData(sce))
        write.csv(col_data_results, "sc3_cell_results.csv", row.names = TRUE)
        
        # Export gene-related results (DE genes, marker genes)
        row_data_results <- as.data.frame(rowData(sce))
        write.csv(row_data_results, "sc3_gene_results.csv", row.names = TRUE)
        
        # Generate diagnostic and visualization plots for k = 3
        pdf("sc3_pipeline_plots.pdf", width = 8, height = 8)
        
        # Helper to safely plot in case of data-specific constraints
        safe_plot <- function(plot_fun, name) {
            tryCatch({
                print(plot_fun)
            }, error = function(e) {
                message(paste("Could not generate plot:", name, "-", e\$message))
            })
        }
        
        message("Generating consensus plot...")
        safe_plot(sc3_plot_consensus(sce, k = 3), "Consensus Matrix")
        
        message("Generating silhouette plot...")
        safe_plot(sc3_plot_silhouette(sce, k = 3), "Silhouette Plot")
        
        message("Generating expression plot...")
        safe_plot(sc3_plot_expression(sce, k = 3), "Expression Matrix")
        
        message("Generating cluster stability plot...")
        safe_plot(sc3_plot_cluster_stability(sce, k = 3), "Cluster Stability")
        
        message("Generating DE genes plot...")
        safe_plot(sc3_plot_de_genes(sce, k = 3), "DE Genes")
        
        message("Generating marker genes plot...")
        safe_plot(sc3_plot_markers(sce, k = 3), "Marker Genes")
        
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SC3_STEP_BY_STEP_SC3_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SC3_STEP_BY_STEP_SC3_PIPELINE":',
        paste0('    SC3: ', as.character(packageVersion('SC3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_sc3_pipeline.csv versions.yml
    """
}

workflow BIOC_SC3_STEP_BY_STEP_SC3_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, cell_metadata.csv ] ]

    main:
    BIOC_SC3_STEP_BY_STEP_SC3_PIPELINE(ch_input)

    emit:
    tables   = BIOC_SC3_STEP_BY_STEP_SC3_PIPELINE.out.tables
    plots    = BIOC_SC3_STEP_BY_STEP_SC3_PIPELINE.out.plots
    objects  = BIOC_SC3_STEP_BY_STEP_SC3_PIPELINE.out.objects
    versions = BIOC_SC3_STEP_BY_STEP_SC3_PIPELINE.out.versions
}
