#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MatrixQCvis — matrixqcvis_proteomics_pipeline
// Perform a comprehensive quality control, multi-stage normalization/imputation processing, and differential expression analysis on proteomics intensity data usin
// Input: intensity.csv, coldata.csv
// Container: 1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MatrixQCvis, SummarizedExperiment, ggplot2, limma
// Visualizations: UpSet plot, box plot, heatmap, PCA plot, volcano plot
// QC: missing-value handling, variance-stabilizing normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MATRIXQCVIS_MATRIXQCVIS_PROTEOMICS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("MatrixQCvis", "limma", "ggplot2", "SummarizedExperiment")
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
     library(SummarizedExperiment)
   library(MatrixQCvis)
    library(limma)
    library(ggplot2)
    
    # ==========================================
    # --- Load Data and Construct SummarizedExperiment ---
    # ==========================================
    
    # Read input files
    intensity_df <- read.csv("intensity.csv", row.names = 1, check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between intensity matrix and coldata
    common_samples <- intersect(colnames(intensity_df), rownames(coldata_df))
    if (length(common_samples) == 0) {
        stop("Error: No common samples found between intensity.csv and coldata.csv")
    }
    
    intensity_mat <- as.matrix(intensity_df[, common_samples, drop = FALSE])
    coldata_sub <- coldata_df[common_samples, , drop = FALSE]
    
    # Ensure required columns exist in colData
    if (!"sample" %in% colnames(coldata_sub)) {
        coldata_sub\$sample <- rownames(coldata_sub)
    }
    if (!"condition" %in% colnames(coldata_sub)) {
        coldata_sub\$condition <- coldata_sub[[1]] # Fallback to the first column
    }
    
    # Convert 0 values to NA to represent missing values typical in proteomics
    intensity_mat[intensity_mat == 0] <- NA
    
    # Construct SummarizedExperiment
    se <- SummarizedExperiment(
        assays = list(raw = intensity_mat),
        colData = coldata_sub
    )
    
    # Filter out features with zero standard deviation
    se_sds <- apply(assay(se), 1, sd, na.rm = TRUE)
    se <- se[!is.na(se_sds) & se_sds > 0, ]
    
    # ==========================================
    # --- Missing Value Diagnostics ---
    # ==========================================
    
    # 1. Samples measured/missing barplot
    tbl_missing <- samplesMeasuredMissing(se)
    p_missing_samples <- barplotSamplesMeasuredMissing(tbl_missing, measured = FALSE)
    ggsave("qc_missing_samples.pdf", plot = p_missing_samples, width = 8, height = 6)
    
    # 2. Feature missingness histogram
    p_hist_feature <- histFeature(assay(se), measured = FALSE)
    ggsave("qc_missing_features_hist.pdf", plot = p_hist_feature, width = 8, height = 6)
    
    # 3. Feature missingness by condition
    p_hist_cat <- histFeatureCategory(se, measured = FALSE, category = "condition")
    ggsave("qc_missing_features_by_condition.pdf", plot = p_hist_cat, width = 8, height = 6)
    
    # 4. UpSet plot of missingness across conditions
    pdf("qc_missing_upset.pdf", width = 10, height = 8)
    tryCatch({
        upsetCategory(se, category = "condition", measured = FALSE)
    }, error = function(e) {
        plot.new()
        text(0.5, 0.5, paste("UpSet plot generation failed:\n", e\$message), cex = 1.2)
    })
    dev.off()
    
    # ==========================================
    # --- Normalization, Transformation, and Imputation ---
    # ==========================================
    
    a_raw <- assay(se)
    
    # 1. Normalization
    a_norm <- normalizeAssay(a_raw, method = "sum")
    
    # Update SE with normalized assay for batch correction step
    se_norm <- se
    assay(se_norm) <- a_norm
    
    # 2. Batch correction (default to none)
    a_batch <- batchCorrectionAssay(se_norm, method = "none")
    
    # 3. Transformation (vsn with log2 fallback)
    a_trans <- tryCatch({
        transformAssay(a_batch, method = "vsn")
    }, error = function(e) {
        warning("vsn transformation failed, falling back to log2: ", e\$message)
        transformAssay(a_batch, method = "log2")
    })
    
    # 4. Imputation (MinDet with minimum value fallback)
    a_imputed <- tryCatch({
        imputeAssay(a_trans, method = "MinDet")
    }, error = function(e) {
        warning("MinDet imputation failed, falling back to minimum value imputation: ", e\$message)
        a_temp <- a_trans
        a_temp[is.na(a_temp)] <- min(a_temp, na.rm = TRUE)
        a_temp
    })
    
    # Create fully processed SummarizedExperiment
    se_processed <- se
    assay(se_processed) <- a_imputed
    
    # ==========================================
    # --- Post-Processing Quality Control ---
    # ==========================================
    
    # 1. CV comparison across processing stages
    cv_raw <- cv(a_raw, "raw")
    cv_norm <- cv(a_norm, "normalized")
    cv_trans <- cv(a_trans, "transformed")
    cv_imputed <- cv(a_imputed, "imputed")
    
    df_cv <- data.frame(
        raw = cv_raw,
        normalized = cv_norm,
        transformed = cv_trans,
        imputed = cv_imputed
    )
    p_cv <- plotCV(df_cv)
    ggsave("qc_cv_comparison.pdf", plot = p_cv, width = 8, height = 6)
    
    # 2. Boxplot/Violin plot of processed values
    p_boxplot <- createBoxplot(se_processed, orderCategory = "condition", title = "Processed Intensities", log = FALSE, violin = TRUE)
    ggsave("qc_processed_boxplot.pdf", plot = p_boxplot, width = 10, height = 6)
    
    # 3. Drift Plot
    highlight_level <- unique(colData(se_processed)\$condition)[1]
    p_drift <- driftPlot(se_processed, aggregation = "median", category = "condition",
                         orderCategory = "condition", level = highlight_level, method = "loess")
    ggsave("qc_drift_plot.pdf", plot = p_drift, width = 10, height = 6)
    
    # 4. Distance Matrix Heatmap
    dist_mat <- distShiny(assay(se_processed))
    pdf("qc_sample_distance_heatmap.pdf", width = 8, height = 8)
    tryCatch({
        distSample(dist_mat, se_processed, "condition", use_raster = FALSE)
    }, error = function(e) {
        plot.new()
        text(0.5, 0.5, paste("Distance heatmap failed:\n", e\$message), cex = 1.2)
    })
    dev.off()
    
    # Sum of distances plot
    p_sum_dist <- sumDistSample(dist_mat, title = "Processed Distances")
    ggsave("qc_sum_distances.pdf", plot = p_sum_dist, width = 8, height = 6)
    
    # ==========================================
    # --- Dimension Reduction ---
    # ==========================================
    
    pca_res <- tryCatch({
        dimensionReduction(se_processed, method = "PCA")
    }, error = function(e) {
        NULL
    })
    
    if (!is.null(pca_res)) {
        p_pca <- tryCatch({
            dimensionReductionPlot(pca_res, annotation = colData(se_processed)\$condition)
        }, error = function(e) {
            NULL
        })
        if (!is.null(p_pca)) {
            ggsave("qc_pca_plot.pdf", plot = p_pca, width = 8, height = 6)
        }
    }
    
    # Fallback PCA if MatrixQCvis dimension reduction fails
    if (is.null(pca_res) || !file.exists("qc_pca_plot.pdf")) {
        pca_decomp <- prcomp(t(assay(se_processed)), scale. = TRUE)
        pca_df <- data.frame(pca_decomp\$x, condition = colData(se_processed)\$condition)
        p_pca_fallback <- ggplot(pca_df, aes(x = PC1, y = PC2, color = condition)) +
            geom_point(size = 3) +
            theme_minimal() +
            labs(title = "PCA (Processed Intensities)")
        ggsave("qc_pca_plot.pdf", plot = p_pca_fallback, width = 8, height = 6)
    }
    
    # ==========================================
    # --- Differential Expression Analysis ---
    # ==========================================
    
    conds <- factor(colData(se_processed)\$condition)
    design <- model.matrix(~ 0 + conds)
    colnames(design) <- levels(conds)
    
    fit <- lmFit(assay(se_processed), design)
    
    unique_conds <- levels(conds)
    if (length(unique_conds) >= 2) {
        # Compare the first two conditions
        contrast_formula <- paste0("`", unique_conds[1], "` - `", unique_conds[2], "`")
        contrast_matrix <- makeContrasts(contrasts = contrast_formula, levels = design)
        fit2 <- contrasts.fit(fit, contrast_matrix)
        fit2 <- eBayes(fit2, trend = TRUE, robust = TRUE)
        
        top_table <- topTable(fit2, number = Inf, adjust.method = "fdr")
        write.csv(top_table, "differential_expression_results.csv", row.names = TRUE)
        
        # Volcano Plot
        p_volcano <- tryCatch({
            volcanoPlot(top_table, type = "ttest")
        }, error = function(e) {
            # Fallback volcano plot
            ggplot(top_table, aes(x = logFC, y = -log10(P.Value))) +
                geom_point(alpha = 0.5, aes(color = adj.P.Val < 0.05)) +
                scale_color_manual(values = c("black", "red")) +
                theme_minimal() +
                labs(title = paste("Volcano Plot:", unique_conds[1], "vs", unique_conds[2]),
                     x = "Log2 Fold Change", y = "-log10(p-value)")
        })
        ggsave("differential_expression_volcano.pdf", plot = p_volcano, width = 8, height = 6)
    } else {
        # Write informative table if DE cannot be performed
        write.csv(data.frame(Message = "At least 2 distinct conditions are required for differential expression analysis."),
                  "differential_expression_results.csv", row.names = FALSE)
        
        pdf("differential_expression_volcano.pdf", width = 8, height = 6)
        plot.new()
        text(0.5, 0.5, "DE analysis skipped: < 2 conditions", cex = 1.2)
        dev.off()
    }
    
    message("MatrixQCvis pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # VSN — DESeqTransform / vsd matrix; mean-SD slope ≤ 0.5 (vsn::meanSdPlot).
    .vsn_slope <- NA_real_
    for (.vsn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .vsn_obj <- tryCatch(readRDS(.vsn_rds), error = function(e) NULL)
      .vsn_mat <- NULL
      if (!is.null(.vsn_obj)) {
        if (inherits(.vsn_obj, "DESeqTransform") || inherits(.vsn_obj, "SummarizedExperiment")) {
          .vsn_mat <- tryCatch(assay(.vsn_obj), error = function(e) NULL)
        } else if (is.matrix(.vsn_obj)) { .vsn_mat <- .vsn_obj }
      }
      if (!is.null(.vsn_mat) && nrow(.vsn_mat) > 100) {
        .vsn_rmean <- suppressWarnings(rowMeans(.vsn_mat, na.rm = TRUE))
        .vsn_rsd <- suppressWarnings(apply(.vsn_mat, 1, sd, na.rm = TRUE))
        .vsn_ok <- is.finite(.vsn_rmean) & is.finite(.vsn_rsd)
        if (sum(.vsn_ok) > 50) {
          .vsn_fit <- tryCatch(lm(.vsn_rsd[.vsn_ok] ~ .vsn_rmean[.vsn_ok]), error = function(e) NULL)
          if (!is.null(.vsn_fit)) { .vsn_slope <- round(abs(coef(.vsn_fit)[2]), 4); break }
        }
      }
    }
    .gates_by_label[["variance-stabilizing normalization"]] <- list(
      gate_row = "bioc_vsn_normalization",
      metric_name = "mean_sd_slope_after_vsn",
      metric_value = .vsn_slope,
      passes = isTRUE(is.finite(.vsn_slope) && .vsn_slope <= 0.5),
      status = if (is.finite(.vsn_slope)) "computed (lm slope row-SD ~ row-mean)"
               else "not_computed (no DESeqTransform/vsd .rds present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MATRIXQCVIS_MATRIXQCVIS_PROTEOMICS_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "variance-stabilizing normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MATRIXQCVIS_MATRIXQCVIS_PROTEOMICS_PIPELINE":',
        paste0('    MatrixQCvis: ', as.character(packageVersion('MatrixQCvis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrixqcvis_proteomics_pipeline.csv versions.yml
    """
}

workflow BIOC_MATRIXQCVIS_MATRIXQCVIS_PROTEOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MATRIXQCVIS_MATRIXQCVIS_PROTEOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MATRIXQCVIS_MATRIXQCVIS_PROTEOMICS_PIPELINE.out.tables
    plots    = BIOC_MATRIXQCVIS_MATRIXQCVIS_PROTEOMICS_PIPELINE.out.plots
    objects  = BIOC_MATRIXQCVIS_MATRIXQCVIS_PROTEOMICS_PIPELINE.out.objects
    versions = BIOC_MATRIXQCVIS_MATRIXQCVIS_PROTEOMICS_PIPELINE.out.versions
}
