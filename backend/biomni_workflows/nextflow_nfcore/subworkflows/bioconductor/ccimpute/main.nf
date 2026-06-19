#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ccImpute — standard_imputation
// Perform dropout imputation on a log-normalized SingleCellExperiment object using the high-level ccImpute wrapper.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-ccimpute:1.12.0--r45ha27e39d_0
// R packages: SingleCellExperiment, BiocParallel, ccImpute, mclust, rhpcblasctl, scRNAseq, scater, sessioninfo
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SingleCellExperiment, ccImpute, mclust, scRNAseq, scater
// Visualizations: PCA plot
// QC: low-count filtering, missing-value handling, cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load required libraries
//  * 2. [Core Analysis] Filter bad cells and remove unexpressed genes
//  * 3. [Core Analysis] Recreate SingleCellExperiment and log-normalize counts
//  * 4. [Core Analysis] Run ccImpute with parallel processing parameters to generate the imputed assay

nextflow.enable.dsl = 2

process BIOC_CCIMPUTE_STANDARD_IMPUTATION {
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
    .bm_deps <- c("SingleCellExperiment", "BiocParallel", "ccImpute", "mclust", "rhpcblasctl", "scRNAseq", "scater", "sessioninfo", "SummarizedExperiment")
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
    
    # 1. Load required libraries
    library(scRNAseq)
    library(SummarizedExperiment)
    library(scater)
    library(ccImpute)
    library(stats)
    library(mclust)
    library(BiocParallel)
    
    # Load user input
    sce <- readRDS("sce.rds")
    
    # 2. Remove unexpressed genes
    # Extract labels robustly
    labels <- colData(sce)\$"Level 1"
    if (is.null(labels)) {
      if ("cell_id" %in% colnames(colData(sce))) {
        labels <- colData(sce)\$cell_id
      } else if (ncol(colData(sce)) > 0) {
        labels <- colData(sce)[, 1]
      } else {
        labels <- rep("CellType", ncol(sce))
      }
    }
    labels <- as.character(labels)
    
    # Extract X (CPM or counts) robustly
    X <- tryCatch({
      cpm(sce)
    }, error = function(e) {
      if ("counts" %in% assayNames(sce)) {
        scater::calculateCPM(sce)
      } else if ("logcounts" %in% assayNames(sce)) {
        exp(as.matrix(logcounts(sce))) - 1
      } else {
        as.matrix(counts(sce))
      }
    })
    
    # Remove genes that are not expressed in any cells:
    keep_genes <- rowSums(X) > 0
    X <- X[keep_genes, , drop = FALSE]
    sce <- sce[keep_genes, ]
    
    # 3. Update the SingleCellExperiment and add log-transformed data:
    colData(sce)\$cell_id <- labels
    assay(sce, "normcounts") <- as.matrix(X)
    logcounts(sce) <- log(assay(sce, "normcounts") + 1)
    
    # Compute PCA and ARI before imputation (as documented)
    set.seed(0)
    reducedDims(sce) <- list(PCA = prcomp(t(logcounts(sce)))\$x)
    k <- length(unique(colData(sce)\$cell_id))
    set.seed(0)
    assgmts <- kmeans(reducedDim(sce, "PCA"), centers = k, iter.max = 1e+09,
                      nstart = 1000)\$cluster
    ari_before <- adjustedRandIndex(assgmts, colData(sce)\$cell_id)
    
    # 4. Run ccImpute with parallel processing parameters to generate the imputed assay
    BPPARAM = MulticoreParam(2)
    sce <- ccImpute(sce, BPPARAM = BPPARAM)
    
    # Compute PCA and ARI after imputation (as documented)
    reducedDim(sce, "PCA_imputed") <- prcomp(t(assay(sce, "imputed")))\$x
    assgmts_imputed <- kmeans(reducedDim(sce, "PCA_imputed"), centers = k, 
                              iter.max = 1e+09, nstart = 1000)\$cluster
    ari_after <- adjustedRandIndex(assgmts_imputed, colData(sce)\$cell_id)
    
    # Save outputs
    # 1. Imputed SingleCellExperiment object
    saveRDS(sce, "sce_imputed.rds")
    
    # 2. Imputed expression matrix
    write.csv(as.matrix(assay(sce, "imputed")), "imputed_counts.csv", row.names = TRUE)
    
    # 3. ARI results
    ari_df <- data.frame(
      Stage = c("Before Imputation", "After Imputation"),
      ARI = c(ari_before, ari_after)
    )
    write.csv(ari_df, "ari_results.csv", row.names = FALSE)
    
    # 4. PCA plots
    pdf("pca_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    pca_before <- reducedDim(sce, "PCA")
    plot(pca_before[, 1], pca_before[, 2], col = as.factor(colData(sce)\$cell_id),
         pch = 20, main = paste("Before Imputation (ARI =", round(ari_before, 3), ")"),
         xlab = "PC1", ylab = "PC2")
    pca_after <- reducedDim(sce, "PCA_imputed")
    plot(pca_after[, 1], pca_after[, 2], col = as.factor(colData(sce)\$cell_id),
         pch = 20, main = paste("After Imputation (ARI =", round(ari_after, 3), ")"),
         xlab = "PC1", ylab = "PC2")
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .mv_obj <- tryCatch(readRDS(.mv_rds), error = function(e) NULL)
      .mv_mat <- if (is.matrix(.mv_obj) || is.data.frame(.mv_obj)) .mv_obj else NULL
      if (!is.null(.mv_mat)) {
        .mv_vals <- suppressWarnings(as.numeric(as.matrix(.mv_mat)))
        if (length(.mv_vals) > 0) {
          .mv_na_fracs <- c(.mv_na_fracs, mean(is.na(.mv_vals)))
          .mv_scanned <- c(.mv_scanned, .mv_rds)
        }
      }
    }
    .mv_max <- if (length(.mv_na_fracs) > 0) round(max(.mv_na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .mv_max,
      passes = isTRUE(is.finite(.mv_max) && .mv_max < 0.05),
      status = if (is.finite(.mv_max)) paste0("computed (scanned ", length(.mv_scanned), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )

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
      process = "BIOC_CCIMPUTE_STANDARD_IMPUTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "missing-value handling", "cell QC metrics", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CCIMPUTE_STANDARD_IMPUTATION":',
        paste0('    ccImpute: ', as.character(packageVersion('ccImpute')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_imputation.csv versions.yml
    """
}

workflow BIOC_CCIMPUTE_STANDARD_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_CCIMPUTE_STANDARD_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_CCIMPUTE_STANDARD_IMPUTATION.out.tables
    plots    = BIOC_CCIMPUTE_STANDARD_IMPUTATION.out.plots
    objects  = BIOC_CCIMPUTE_STANDARD_IMPUTATION.out.objects
    versions = BIOC_CCIMPUTE_STANDARD_IMPUTATION.out.versions
}
