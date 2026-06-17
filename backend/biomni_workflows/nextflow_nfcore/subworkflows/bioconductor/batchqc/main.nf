#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BatchQC — batch_diagnostics_and_correction
// Diagnose batch effects, normalize and batch-correct transcriptomics data, and perform differential expression analysis.
// Input: features, metadata
// Container: quay.io/biocontainers/bioconductor-batchqc:2.6.1--r45hdfd78af_0
// R packages: SummarizedExperiment, BatchQC, devtools
// Bioconductor: 3.20 | R: 4.4
// Requires: BatchQC, SummarizedExperiment
// Visualizations: box plot, heatmap, PCA plot, UMAP plot, volcano plot
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Create SummarizedExperiment Object
//  * 3. [Visualization & Output] Check Data Distribution
//  * 4. [Visualization & Output] Apply Normalization Methods
//  * 5. [Visualization & Output] Apply Batch Effect Correction
//  * 6. [Visualization & Output] Experimental Design & Confounding
//  * 7. [Visualization & Output] Lambda & Variation Analysis
//  * 8. [Visualization & Output] kBET Batch Effect Test
//  * 9. [Visualization & Output] Visualizations
//  * 10. [Visualization & Output] Differential Expression Analysis
//  * 11. [Visualization & Output] Save Corrected SummarizedExperiment Object

nextflow.enable.dsl = 2

process BIOC_BATCHQC_BATCH_DIAGNOSTICS_AND_CORRECTION {
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
    .bm_deps <- c("SummarizedExperiment", "BatchQC", "devtools")
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
    library(BatchQC)
    
    library(SummarizedExperiment)
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    
    find_file <- function(base_name) {
      extensions <- c(".csv", ".tsv", ".txt", "")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path) && !dir.exists(file_path)) {
          return(file_path)
        }
      }
      stop(paste("Error: Could not find file for", base_name))
    }
    
    features_path <- find_file("features")
    metadata_path <- find_file("metadata")
    
    # Read features matrix
    if (grepl("\\\\.tsv\$", features_path) || grepl("\\\\.txt\$", features_path)) {
      features <- as.matrix(read.delim(features_path, row.names = 1, check.names = FALSE))
    } else {
      features <- as.matrix(read.csv(features_path, row.names = 1, check.names = FALSE))
    }
    
    # Read metadata data frame
    if (grepl("\\\\.tsv\$", metadata_path) || grepl("\\\\.txt\$", metadata_path)) {
      metadata <- read.delim(metadata_path, row.names = 1, check.names = FALSE)
    } else {
      metadata <- read.csv(metadata_path, row.names = 1, check.names = FALSE)
    }
    
    # Ensure sample names match between features and metadata
    common_samples <- intersect(colnames(features), rownames(metadata))
    if (length(common_samples) == 0) {
      stop("Error: No common samples found between features columns and metadata rows.")
    }
    features <- features[, common_samples, drop = FALSE]
    metadata <- metadata[common_samples, , drop = FALSE]
    
    # ==========================================
    # Smart Column Detection for Batch and Covariate
    # ==========================================
    detected_batch <- NULL
    for (cand in c("Experiment", "batch", "Batch", "ExperimentID", "group")) {
      if (cand %in% colnames(metadata)) {
        detected_batch <- cand
        break
      }
    }
    if (is.null(detected_batch)) {
      detected_batch <- colnames(metadata)[1]
    }
    
    detected_covar <- NULL
    for (cand in c("TBStatus", "condition", "Condition", "TBStatusPTB", "treatment", "Group", "status")) {
      if (cand %in% colnames(metadata) && cand != detected_batch) {
        detected_covar <- cand
        break
      }
    }
    if (is.null(detected_covar)) {
      if (ncol(metadata) >= 2) {
        detected_covar <- colnames(metadata)[colnames(metadata) != detected_batch][1]
      } else {
        detected_covar <- detected_batch
      }
    }
    
    # Align metadata columns to match the vignette's expected names
    metadata\$batch <- as.factor(metadata[[detected_batch]])
    metadata\$condition <- as.factor(metadata[[detected_covar]])
    metadata\$Experiment <- metadata\$batch
    metadata\$TBStatus <- metadata\$condition
    
    # ==========================================
    # --- Create SummarizedExperiment Object ---
    # ==========================================
    
    se_object <- BatchQC::summarized_experiment(features, metadata)
    
    # Name your assay
    SummarizedExperiment::assayNames(se_object) <- "log_intensity"
    
    # Ensure all relevant metadata variables are factors
    se_object\$batch <- as.factor(se_object\$batch)
    se_object\$condition <- as.factor(se_object\$condition)
    
    # Duplicate the assay to "features" to match the TB workflow's assay_of_interest
    SummarizedExperiment::assays(se_object)[["features"]] <- SummarizedExperiment::assays(se_object)[["log_intensity"]]
    
    # Define variables for the TB workflow
    assay_of_interest <- "features"
    batch <- "Experiment"
    covar <- "TBStatus"
    
    # ==========================================
    # --- Check Data Distribution ---
    # ==========================================
    
    # AIC Model Fit
    TB_AIC <- compute_aic(se = se_object,
        assay_of_interest = assay_of_interest,
        batchind = batch,
        groupind = covar,
        maxit = 1000,
        zero_filt_percent = 15
        )
    
    write.csv(as.data.frame(TB_AIC["AIC_table"]), "AIC_table.csv")
    
    pdf("AIC_boxplot.pdf")
    print(TB_AIC["AIC_boxplot"])
    dev.off()
    
    # Set a seed if you would like reproducible results
    set.seed(1)
    
    num_genes_gof <- min(3000, nrow(se_object))
    TB_fit <- goodness_of_fit_nb(se = se_object,
        count_matrix = assay_of_interest,
        condition = covar,
        other_variables = batch,
        num_genes = num_genes_gof,
        method = "edgeR")
    
    pdf("goodness_of_fit_histogram.pdf")
    print(TB_fit\$res_histogram)
    dev.off()
    
    writeLines(TB_fit\$recommendation, "goodness_of_fit_recommendation.txt")
    
    # ==========================================
    # --- Apply Normalization Methods ---
    # ==========================================
    
    # CPM Normalization
    se_object <- BatchQC::normalize_SE(se = se_object, method = "CPM",
        log_bool = FALSE, assay_to_normalize = assay_of_interest,
        output_assay_name = "CPM_normalized_counts")
    
    # CPM Normalization w/log
    se_object <- BatchQC::normalize_SE(se = se_object, method = "CPM",
        log_bool = TRUE, assay_to_normalize = assay_of_interest,
        output_assay_name = "CPM_log_normalized_counts")
    
    # DESeq Normalization
    se_object <- BatchQC::normalize_SE(se = se_object, method = "DESeq",
        log_bool = FALSE, assay_to_normalize = assay_of_interest,
        output_assay_name = "DESeq_normalized_counts")
    
    # DESeq Normalization w/log
    se_object <- BatchQC::normalize_SE(se = se_object, method = "DESeq",
        log_bool = TRUE, assay_to_normalize = assay_of_interest,
        output_assay_name = "DESeq_log_normalized_counts")
    
    # log adjust
    se_object <- BatchQC::normalize_SE(se = se_object, method = "none",
        log_bool = TRUE, assay_to_normalize = assay_of_interest,
        output_assay_name = "log_normalized_counts")
    
    # ==========================================
    # --- Apply Batch Effect Correction ---
    # ==========================================
    
    # ComBat correction
    se_object <- BatchQC::batch_correct(se = se_object, method = "ComBat",
        assay_to_normalize = "CPM_log_normalized_counts", batch = batch,
        covar = c(covar), output_assay_name = "ComBat_corrected")
    
    # ==========================================
    # --- Experimental Design & Confounding ---
    # ==========================================
    
    batch_design_tibble <- BatchQC::batch_design(se = se_object, batch = batch, 
        covariate = covar)
    write.csv(as.data.frame(batch_design_tibble), "batch_design.csv", row.names = FALSE)
    
    confound_table <- BatchQC::confound_metrics(se = se_object, batch = batch)
    write.csv(as.data.frame(confound_table), "confound_metrics.csv")
    
    pearson_cor_result <- BatchQC::std_pearson_corr_coef(batch_design_tibble)
    writeLines(as.character(pearson_cor_result), "pearson_cor_result.txt")
    
    cramers_v_result <- BatchQC::cramers_v(batch_design_tibble)
    writeLines(as.character(cramers_v_result), "cramers_v_result.txt")
    
    # ==========================================
    # --- Lambda & Variation Analysis ---
    # ==========================================
    
    lambda_calculation <- run_lambda(se = se_object,
        assay = assay_of_interest,
        batch = batch,
        condition = covar)
    
    writeLines(c(
      paste("Recommendation:", lambda_calculation\$correction_recommendation),
      paste("Lambda Stat:", lambda_calculation\$lambda_stat)
    ), "lambda_calculation.txt")
    
    # Uncorrected variation
    ex_variation <- batchqc_explained_variation(se = se_object,
        batch = batch, condition = covar, assay_name = assay_of_interest)
    
    pdf("EV_boxplot_uncorrected_individual.pdf")
    EV_boxplot <- BatchQC::EV_plotter(batchqc_ev = ex_variation[[1]])
    print(EV_boxplot)
    dev.off()
    
    write.csv(as.data.frame(BatchQC::summary_stats_EV_table(ex_variation[[1]])), "EV_summary_uncorrected_individual.csv")
    
    pdf("EV_boxplot_uncorrected_residual.pdf")
    EV_boxplot_type_2 <- BatchQC::EV_plotter(batchqc_ev = ex_variation[[2]])
    print(EV_boxplot_type_2)
    dev.off()
    
    write.csv(as.data.frame(BatchQC::summary_stats_EV_table(ex_variation[[2]])), "EV_summary_uncorrected_residual.csv")
    
    # Corrected variation
    ex_variation_corr <- batchqc_explained_variation(se = se_object,
        batch = batch, condition = covar, assay_name = "ComBat_corrected")
    
    pdf("EV_boxplot_corrected_individual.pdf")
    EV_boxplot_corr <- BatchQC::EV_plotter(batchqc_ev = ex_variation_corr[[1]])
    print(EV_boxplot_corr)
    dev.off()
    
    write.csv(as.data.frame(BatchQC::summary_stats_EV_table(ex_variation_corr[[1]])), "EV_summary_corrected_individual.csv")
    
    pdf("EV_boxplot_corrected_residual.pdf")
    EV_boxplot_type_2_corr <- BatchQC::EV_plotter(batchqc_ev = ex_variation_corr[[2]])
    print(EV_boxplot_type_2_corr)
    dev.off()
    
    write.csv(as.data.frame(BatchQC::summary_stats_EV_table(ex_variation_corr[[2]])), "EV_summary_corrected_residual.csv")
    
    EV_table <- BatchQC::EV_table(batchqc_ev = ex_variation_corr[[1]])
    write.csv(as.data.frame(EV_table), "EV_table_corrected_individual.csv", row.names = FALSE)
    
    EV_table_type_2 <- BatchQC::EV_table(batchqc_ev = ex_variation_corr[[2]])
    write.csv(as.data.frame(EV_table_type_2), "EV_table_corrected_residual.csv", row.names = FALSE)
    
    # ==========================================
    # --- kBET Batch Effect Test ---
    # ==========================================
    
    tryCatch({
      TB_kBET <- BatchQC::run_kBET(se = se_object,
          assay_to_normalize = assay_of_interest,
          batch = batch)
    
      pdf("kBET_plot.pdf")
      print(BatchQC::plot_kBET(TB_kBET))
      dev.off()
    }, error = function(e) {
      warning("kBET analysis skipped or failed: ", e\$message)
    })
    
    # ==========================================
    # --- Visualizations ---
    # ==========================================
    
    n_feat_heatmap <- min(38, nrow(se_object))
    
    # Sample Correlations Heatmap
    tryCatch({
      heatmaps <- BatchQC::heatmap_plotter(se = se_object, assay = assay_of_interest,
          nfeature = n_feat_heatmap, annotation_column = c(batch, covar),
          log_option = "FALSE")
      correlation_heatmap <- heatmaps\$correlation_heatmap
      pdf("correlation_heatmap.pdf")
      print(correlation_heatmap)
      dev.off()
    }, error = function(e) {
      warning("Correlation heatmap failed: ", e\$message)
    })
    
    # Top N Heatmap
    tryCatch({
      heatmaps <- BatchQC::heatmap_plotter(se = se_object, assay = assay_of_interest,
          nfeature = n_feat_heatmap, annotation_column = c(batch, covar),
          log_option = FALSE)
      heatmap <- heatmaps\$topn_heatmap
      pdf("topn_heatmap.pdf")
      print(heatmap)
      dev.off()
    }, error = function(e) {
      warning("Top N heatmap failed: ", e\$message)
    })
    
    # Dendrograms
    tryCatch({
      dendrogram_plot <- BatchQC::dendrogram_plotter(se = se_object,
          assay = assay_of_interest,
          batch_var = batch,
          category_var = covar)
      pdf("dendrogram.pdf")
      print(dendrogram_plot\$dendrogram)
      dev.off()
    
      circular_dendrogram_plot <- BatchQC::dendrogram_plotter(
          se = se_object, assay = assay_of_interest, batch_var = batch,
          category_var = covar)
      pdf("circular_dendrogram.pdf")
      print(circular_dendrogram_plot\$circular_dendrogram)
      dev.off()
    }, error = function(e) {
      warning("Dendrogram plotting failed: ", e\$message)
    })
    
    # PCA Plot
    tryCatch({
      n_feat_pca <- min(20, nrow(se_object))
      pca_plot <- BatchQC::PCA_plotter(se = se_object, nfeature = n_feat_pca, color = batch,
          shape = covar, batch = batch,
          assays = c("log_normalized_counts", "ComBat_corrected"),
          xaxisPC = 1, yaxisPC = 2, log_option = FALSE)
      pdf("pca_plot.pdf")
      print(pca_plot\$plot)
      dev.off()
      write.csv(as.data.frame(pca_plot\$var_explained), "pca_var_explained.csv")
    }, error = function(e) {
      warning("PCA plotting failed: ", e\$message)
    })
    
    # UMAP Analysis
    n_neighbors <- min(15, ncol(se_object) - 1)
    if (n_neighbors < 2) n_neighbors <- 2
    
    tryCatch({
      umap_plot <- BatchQC::umap(se = se_object,
          assay_of_interest = assay_of_interest, batch = batch, covar = covar,
          neighbors = n_neighbors, min_distance = 0.1, spread = 1, log_option = TRUE)
      pdf("umap_plot_uncorrected.pdf")
      print(umap_plot)
      dev.off()
    }, error = function(e) {
      warning("Uncorrected UMAP failed: ", e\$message)
    })
    
    tryCatch({
      umap_plot_batch_corrected <- BatchQC::umap(se = se_object,
          assay_of_interest = "ComBat_corrected", batch = batch, covar = covar,
          neighbors = n_neighbors, min_distance = 0.1, spread = 1)
      pdf("umap_plot_corrected.pdf")
      print(umap_plot_batch_corrected)
      dev.off()
    }, error = function(e) {
      warning("Corrected UMAP failed: ", e\$message)
    })
    
    # ==========================================
    # --- Differential Expression Analysis ---
    # ==========================================
    
    differential_expression <- BatchQC::DE_analyze(se = se_object,
        method = "limma", batch = batch, conditions = c(covar),
        assay_to_analyze = assay_of_interest, padj_method = "BH")
    
    # Save DE results tables
    de_names <- names(differential_expression)
    for (nm in de_names) {
      safe_nm <- gsub("[^A-Za-z0-9_]", "_", nm)
      write.csv(as.data.frame(differential_expression[[nm]]), paste0("DE_results_", safe_nm, ".csv"))
    }
    
    # P-Value Plotting
    pdf("pval_plot.pdf")
    print(pval_plotter(differential_expression))
    dev.off()
    
    write.csv(as.data.frame(pval_summary(differential_expression)), "pval_summary.csv")
    
    # Volcano Plot
    # Ensure "TBStatusPTB" exists in differential_expression for the exact volcano_plot call
    de_names_filtered <- de_names[de_names != "(Intercept)"]
    if (length(de_names_filtered) == 0) de_names_filtered <- de_names
    target_de_name <- de_names_filtered[1]
    differential_expression[["TBStatusPTB"]] <- differential_expression[[target_de_name]]
    
    value <- round((max(abs(
        differential_expression[[length(differential_expression)]][, 1]))
        + min(
            abs(differential_expression[[length(differential_expression)]][, 1])))
        / 2)
    
    if (is.na(value) || is.infinite(value)) value <- 1
    
    pdf("volcano_plot.pdf")
    print(volcano_plot(DE_results = differential_expression[["TBStatusPTB"]],
        pslider = 0.05,
        fcslider = value))
    dev.off()
    
    # ==========================================
    # --- Save Corrected SummarizedExperiment Object ---
    # ==========================================
    
    file_location <- "corrected_se_object.rds"
    saveRDS(object = se_object, file = file_location)

    writeLines(c(
        '"BIOC_BATCHQC_BATCH_DIAGNOSTICS_AND_CORRECTION":',
        paste0('    BatchQC: ', as.character(packageVersion('BatchQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_diagnostics_and_correction.csv versions.yml
    """
}

workflow BIOC_BATCHQC_BATCH_DIAGNOSTICS_AND_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ features, metadata ] ]

    main:
    BIOC_BATCHQC_BATCH_DIAGNOSTICS_AND_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BATCHQC_BATCH_DIAGNOSTICS_AND_CORRECTION.out.tables
    plots    = BIOC_BATCHQC_BATCH_DIAGNOSTICS_AND_CORRECTION.out.plots
    objects  = BIOC_BATCHQC_BATCH_DIAGNOSTICS_AND_CORRECTION.out.objects
    versions = BIOC_BATCHQC_BATCH_DIAGNOSTICS_AND_CORRECTION.out.versions
}
