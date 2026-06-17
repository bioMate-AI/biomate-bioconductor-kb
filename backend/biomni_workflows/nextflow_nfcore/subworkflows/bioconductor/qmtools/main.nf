#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qmtools — metabolomics_preprocessing_and_analysis
// Preprocess quantitative metabolomics data (filtering, imputation, normalization), cluster redundant features, and perform differential abundance analysis.
// Input: faahko_se.RData
// Container: quay.io/biocontainers/bioconductor-qmtools:1.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ggplot2, patchwork, pls, qmtools, vsn
// Visualizations: PCA plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Feature filtering based on missing values (removeFeatures)
//  * 2. [Visualization & Output] Missing value visualization (plotMiss) and imputation (imputeIntensity)
//  * 3. [Visualization & Output] Intensity normalization (normalizeIntensity) and visualization (plotBox)
//  * 4. [Visualization & Output] Dimension reduction (reduceFeatures) and visualization (plotReduced)
//  * 5. [Visualization & Output] Feature clustering based on retention time and intensity correlation (clusterFeatures, plotRTgroup)
//  * 6. [Core Analysis] Differential abundance analysis between sample groups (compareSamples)

nextflow.enable.dsl = 2

process BIOC_QMTOOLS_METABOLOMICS_PREPROCESSING_AND_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("qmtools", "vsn", "pls", "ggplot2", "patchwork", "SummarizedExperiment")
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
                 library(SummarizedExperiment)
       library(qmtools)
            library(vsn)
            library(pls)
            library(ggplot2)
            library(patchwork)
            
            # Set seed for reproducibility
            set.seed(1e8)
            
            # ----------------------------------------------------------------------
            # Data Loading
            # ----------------------------------------------------------------------
            # Read the user-provided SummarizedExperiment object
            load("faahko_se.RData")
            
            # Ensure the object is named faahko_se
            if (!exists("faahko_se") && exists("se")) {
              faahko_se <- se
            }
            
            # Only keep the first assay for the workflow as documented
            if (length(assays(faahko_se)) > 1) {
              assays(faahko_se)[2:length(assays(faahko_se))] <- NULL
            }
            
            # ----------------------------------------------------------------------
            # 1. Feature Filtering
            # ----------------------------------------------------------------------
            # Check dimensions and filter features based on missing values
            dim_original <- dim(faahko_se)
            cat("Original dimensions: ", paste(dim_original, collapse = " x "), "\n")
            
            faahko_se_80 <- removeFeatures(faahko_se, i = "raw",
                                           group = colData(faahko_se)\$sample_group,
                                           cut = 0.80)
            dim_cut_80 <- dim(faahko_se_80)
            cat("Dimensions after 0.80 cut: ", paste(dim_cut_80, collapse = " x "), "\n")
            
            dim_cut_85 <- dim(removeFeatures(faahko_se, i = "raw",
                                             group = colData(faahko_se)\$sample_group,
                                             cut = 0.85))
            cat("Dimensions after 0.85 cut: ", paste(dim_cut_85, collapse = " x "), "\n")
            
            dim_wt_only <- dim(removeFeatures(faahko_se, i = "raw",
                                              group = colData(faahko_se)\$sample_group,
                                              levels = "WT", cut = 0.85))
            cat("Dimensions after WT-only 0.85 cut: ", paste(dim_wt_only, collapse = " x "), "\n")
            
            # Apply the 0.80 cut as the actual filtering step
            faahko_se <- faahko_se_80
            
            # ----------------------------------------------------------------------
            # 2. Missing Value Visualization and Imputation
            # ----------------------------------------------------------------------
            # Sample group information
            g <- factor(colData(faahko_se)\$sample_group, levels = c("WT", "KO"))
            
            # Visualization of missing values
            pdf("plot_missing_values.pdf", width = 10, height = 5)
            print(plotMiss(faahko_se, i = "raw", group = g))
            dev.off()
            
            # Impute missing values using kNN
            se <- imputeIntensity(faahko_se, i = "raw", name = "knn", method = "knn")
            
            # Compare unscaled vs scaled imputation
            m <- assay(faahko_se, "raw")
            knn_scaled <- as.data.frame(
              imputeIntensity(scale(m), method = "knn")
            )
            knn_unscaled <- as.data.frame(assay(se, "knn"))
            
            idx <- which(is.na(m[, 1]) | is.na(m[, 2]))
            col1 <- colnames(m)[1]
            col2 <- colnames(m)[2]
            p1_imp <- ggplot(knn_unscaled[idx, ], aes(x = .data[[col1]], y = .data[[col2]])) +
              geom_point() + theme_bw()
            p2_imp <- ggplot(knn_scaled[idx, ], aes(x = .data[[col1]], y = .data[[col2]])) +
              geom_point() + theme_bw()
            
            pdf("plot_imputed_comparison.pdf", width = 10, height = 5)
            print(p1_imp + p2_imp + plot_annotation(title = "Imputed values: unscaled vs scaled"))
            dev.off()
            
            # ----------------------------------------------------------------------
            # 3. Intensity Normalization
            # ----------------------------------------------------------------------
            # Normalize using VSN
            se <- normalizeIntensity(se, i = "knn", name = "knn_vsn", method = "vsn")
            
            # Visualize before vs after normalization
            p1_norm <- plotBox(se, i = "knn", group = g, log2 = TRUE)
            p2_norm <- plotBox(se, i = "knn_vsn", group = g)
            
            pdf("plot_normalization_comparison.pdf", width = 10, height = 5)
            print(p1_norm + p2_norm + plot_annotation(title = "Before vs After normalization"))
            dev.off()
            
            # ----------------------------------------------------------------------
            # 4. Dimension Reduction
            # ----------------------------------------------------------------------
            # PCA
            m_pca <- reduceFeatures(se, i = "knn_vsn", method = "pca", ncomp = 2)
            pca_summary <- capture.output(summary(m_pca))
            writeLines(pca_summary, "pca_summary.txt")
            
            # PLS-DA
            m_plsda <- reduceFeatures(se, i = "knn_vsn", method = "plsda", ncomp = 2, y = g)
            plsda_summary <- capture.output(summary(m_plsda))
            writeLines(plsda_summary, "plsda_summary.txt")
            
            # Plot PCA and PLS-DA
            p_pca <- plotReduced(m_pca, group = g)
            p_plsda <- plotReduced(m_plsda, label = TRUE, ellipse = TRUE)
            
            pdf("plot_pca_plsda.pdf", width = 10, height = 5)
            print(p_pca + p_plsda + plot_annotation(title = "PCA and PLS-DA"))
            dev.off()
            
            # ----------------------------------------------------------------------
            # 5. Feature Clustering
            # ----------------------------------------------------------------------
            # Cluster features based on retention time and intensity correlation
            se <- clusterFeatures(se, i = "knn_vsn", rtime_var = "rtmed",
                                  rt_cut = 10, cor_cut = 0.7)
            
            # Save clustering results to a CSV file
            clustering_results <- as.data.frame(rowData(se)[, c("rtmed", "rtime_group", "feature_group")])
            write.csv(clustering_results, "feature_clustering_results.csv", row.names = TRUE)
            
            # Plot retention time hclust dendrogram
            rts <- rowData(se)\$rtmed
            rt_cut <- 10
            fit_hclust <- hclust(dist(rts, "manhattan"))
            
            pdf("plot_rt_hclust.pdf", width = 10, height = 5)
            plot(as.dendrogram(fit_hclust), leaflab = "none")
            rect.hclust(fit_hclust, h = rt_cut)
            dev.off()
            
            # Connected grouping
            se_connected <- clusterFeatures(se, i = "knn_vsn", rtime_var = "rtmed",
                                            rt_cut = 10, cor_cut = 0.7,
                                            cor_grouping = "connected")
            fg_conn <- na.omit(rowData(se_connected)\$feature_group)[1]
            pdf("plot_rtgroup_connected.pdf", width = 6, height = 6)
            print(plotRTgroup(se_connected, i = "knn_vsn", group = fg_conn))
            dev.off()
            
            # Louvain grouping
            se_louvain <- clusterFeatures(se, i = "knn_vsn", rtime_var = "rtmed",
                                          rt_cut = 10, cor_cut = 0.7,
                                          cor_grouping = "louvain")
            fg_louv <- na.omit(rowData(se_louvain)\$feature_group)[1]
            pdf("plot_rtgroup_louvain.pdf", width = 6, height = 6)
            print(plotRTgroup(se_louvain, i = "knn_vsn", group = fg_louv))
            dev.off()
            
            # Pairs plot for Louvain grouping
            pdf("plot_rtgroup_pairs.pdf", width = 8, height = 8)
            print(plotRTgroup(se_louvain, i = "knn_vsn", group = fg_louv, type = "pairs"))
            dev.off()
            
            # ----------------------------------------------------------------------
            # 6. Differential Abundance Analysis
            # ----------------------------------------------------------------------
            # Compute statistics for the contrast: KO - WT
            fit <- compareSamples(se, i = "knn_vsn", group = "sample_group",
                                  class1 = "WT", class2 = "KO")
            write.csv(fit, "differential_abundance_results.csv", row.names = TRUE)
            
            # Include covariates
            colData(se)\$covar <- rep_len(c("A", "B"), ncol(se))
            fit_covar <- compareSamples(se, i = "knn_vsn", group = "sample_group",
                                        covariates = "covar", class1 = "WT", class2 = "KO",
                                        number = 5)
            write.csv(fit_covar, "differential_abundance_covariates_results.csv", row.names = TRUE)
            
            # Save the final processed SummarizedExperiment object
            saveRDS(se, "processed_se.rds")
            
            cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_QMTOOLS_METABOLOMICS_PREPROCESSING_AND_ANALYSIS":',
        paste0('    qmtools: ', as.character(packageVersion('qmtools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabolomics_preprocessing_and_analysis.csv versions.yml
    """
}

workflow BIOC_QMTOOLS_METABOLOMICS_PREPROCESSING_AND_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ faahko_se.RData ] ]

    main:
    BIOC_QMTOOLS_METABOLOMICS_PREPROCESSING_AND_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_QMTOOLS_METABOLOMICS_PREPROCESSING_AND_ANALYSIS.out.tables
    plots    = BIOC_QMTOOLS_METABOLOMICS_PREPROCESSING_AND_ANALYSIS.out.plots
    objects  = BIOC_QMTOOLS_METABOLOMICS_PREPROCESSING_AND_ANALYSIS.out.objects
    versions = BIOC_QMTOOLS_METABOLOMICS_PREPROCESSING_AND_ANALYSIS.out.versions
}
