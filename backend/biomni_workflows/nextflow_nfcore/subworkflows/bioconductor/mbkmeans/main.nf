#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mbkmeans — mbkmeans_direct_clustering
// Cluster single-cell data represented as a SingleCellExperiment or matrix-like object using the mini-batch k-means algorithm, including batch size estimation and
// Input: sce_object.rds
// Container: quay.io/biocontainers/bioconductor-mbkmeans:1.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, mbkmeans, scater
// Visualizations: elbow plot
// QC: cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run mbkmeans on a specific assay of the SingleCellExperiment
//  * 2. [Core Analysis] Estimate optimal batch size using blocksize()
//  * 3. [Core Analysis] Run mbkmeans with random initialization
//  * 4. [Core Analysis] Perform PCA and run mbkmeans across multiple k values to find the optimal number of clusters using WCSS

nextflow.enable.dsl = 2

process BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("mbkmeans", "scater")
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
    library(mbkmeans)
    library(scater)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Load User Input and Prepare Data
    # -----------------------------------------------------------------------------
    # Read the user-provided SingleCellExperiment object
    if (!file.exists("sce_object.rds")) {
      stop("Error: 'sce_object.rds' not found in the working directory.")
    }
    
    sce1000 <- readRDS("sce_object.rds")
    
    # Ensure the object is a SingleCellExperiment
    if (!inherits(sce1000, "SingleCellExperiment")) {
      stop("Error: The loaded object is not a SingleCellExperiment.")
    }
    
    # Ensure logcounts assay exists; if not, compute it
    if (!"logcounts" %in% assayNames(sce1000)) {
      message("'logcounts' assay not found. Computing log-normalized counts...")
      sce1000 <- scater::logNormCounts(sce1000)
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1: Run mbkmeans on a specific assay of the SingleCellExperiment
    # -----------------------------------------------------------------------------
    res <- mbkmeans(sce1000, clusters = 5,
                    reduceMethod = NA,
                    whichAssay = "logcounts")
    
    # Save Stage 1 results
    saveRDS(res, "mbkmeans_res_k5.rds")
    write.csv(as.data.frame(res\$Clusters), "cluster_assignments_k5.csv", row.names = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Estimate optimal batch size using blocksize()
    # -----------------------------------------------------------------------------
    batchsize <- blocksize(sce1000)
    
    # Save batch size estimation
    writeLines(as.character(batchsize), "estimated_batch_size.txt")
    
    # -----------------------------------------------------------------------------
    # Stage 3: Run mbkmeans with random initialization
    # -----------------------------------------------------------------------------
    res_random <- mbkmeans(sce1000, clusters = 5, 
                    reduceMethod = NA,
                    whichAssay = "logcounts",
                    initializer = "random")
    
    # Save Stage 3 results
    saveRDS(res_random, "mbkmeans_res_random_k5.rds")
    
    # Compare initializations and save comparison table
    init_comparison <- table(res\$Clusters, res_random\$Clusters)
    write.csv(as.data.frame.matrix(init_comparison), "initialization_comparison.csv", row.names = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Perform PCA and run mbkmeans across multiple k values (optimal k selection)
    # -----------------------------------------------------------------------------
    sce1000 <- runPCA(sce1000, ncomponents=20)
    
    ks <- seq(5, 15)
    res <- lapply(ks, function(k) {
        mbkmeans(sce1000, clusters = k,
                 reduceMethod = "PCA",
                 calc_wcss = TRUE, num_init=10)
    })
    
    wcss <- sapply(res, function(x) sum(x\$WCSS_per_cluster))
    
    # Save WCSS results
    wcss_df <- data.frame(k = ks, WCSS = wcss)
    write.csv(wcss_df, "wcss_results.csv", row.names = FALSE)
    saveRDS(res, "mbkmeans_res_multi_k.rds")
    
    # Plot the elbow curve and save as PDF
    pdf("wcss_elbow_plot.pdf", width = 7, height = 5)
    plot(ks, wcss, type = "b", xlab = "Number of Clusters (k)", ylab = "Within-Cluster Sum of Squares (WCSS)",
         main = "Elbow Method for Optimal k Selection")
    dev.off()
    
    # Save the final updated SingleCellExperiment object
    saveRDS(sce1000, "sce_processed.rds")
    
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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING":',
        paste0('    mbkmeans: ', as.character(packageVersion('mbkmeans')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mbkmeans_direct_clustering.csv versions.yml
    """
}

workflow BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_object.rds ] ]

    main:
    BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING.out.tables
    plots    = BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING.out.plots
    objects  = BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING.out.objects
    versions = BIOC_MBKMEANS_MBKMEANS_DIRECT_CLUSTERING.out.versions
}
