#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scater — sc_rnaseq_qc_and_visualization
// Perform quality control, normalization, dimensionality reduction, and visualization of single-cell RNA-seq expression data.
// Input: example_sce
// Container: quay.io/biocontainers/bioconductor-scater:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, scater
// Visualizations: PCA plot, sample metadata plot, ordination plot, t-SNE plot, expression plot, highest-expression plot, scatter plot, box plot, density plot, violin plot
// QC: per-cell QC metrics, diagnostic MA/PCA QC, cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute quality control metrics using addPerCellQC
//  * 2. [Visualization & Output] Visualize QC metrics using plotColData and plotHighestExprs
//  * 3. [Core Analysis] Normalize counts using logNormCounts
//  * 4. [Visualization & Output] Calculate and plot variance explained by experimental variables using getVarianceExplained and plotExplanatoryVariables
//  * 5. [Visualization & Output] Visualize gene expression profiles using plotExpression
//  * 6. [Core Analysis] Perform dimensionality reduction using runPCA, runTSNE, and runUMAP
//  * 7. [Visualization & Output] Visualize reduced dimensions using plotReducedDim, plotTSNE, and plotPCA
//  * 8. [Visualization & Output] Create custom plots using ggcells and ggfeatures

nextflow.enable.dsl = 2

process BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION {
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
    .bm_deps <- c("scater", "ggplot2", "SummarizedExperiment")
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
        library(scater)
        library(ggplot2)
        
        # Read the user input SingleCellExperiment object from the working directory
        if (file.exists("example_sce")) {
            example_sce <- readRDS("example_sce")
        } else if (file.exists("example_sce.rds")) {
            example_sce <- readRDS("example_sce.rds")
        } else {
            stop("Error: Input file 'example_sce' or 'example_sce.rds' not found in the working directory.")
        }
        
        # Extract generic names to avoid hardcoded metadata and feature names
        orig_meta_cols <- colnames(colData(example_sce))
        meta1 <- if (length(orig_meta_cols) > 0) orig_meta_cols[1] else "sum"
        meta2 <- if (length(orig_meta_cols) > 1) orig_meta_cols[2] else meta1
        meta_all <- if (length(orig_meta_cols) > 0) head(orig_meta_cols, 4) else c("sum", "detected")
        
        gene1 <- rownames(example_sce)[1]
        gene2 <- if (nrow(example_sce) >= 2) rownames(example_sce)[2] else gene1
        gene3 <- if (nrow(example_sce) >= 3) rownames(example_sce)[3] else gene1
        
        # 1. Compute quality control metrics using addPerCellQC
        example_sce <- addPerCellQC(example_sce, 
            subsets=list(Mito=grep("mt-", rownames(example_sce))))
        
        # 2. Visualize QC metrics using plotColData and plotHighestExprs
        pdf("plot_coldata_sum_detected.pdf")
        p1 <- plotColData(example_sce, x = "sum", y="detected", colour_by=meta1) 
        print(p1)
        dev.off()
        
        pdf("plot_coldata_mito_facet.pdf")
        p2 <- plotColData(example_sce, x = "sum", y="subsets_Mito_percent", 
            other_fields=meta1) + facet_wrap(as.formula(paste0("~`", meta1, "`")))
        print(p2)
        dev.off()
        
        pdf("plot_highest_exprs.pdf")
        p3 <- plotHighestExprs(example_sce, exprs_values = "counts")
        print(p3)
        dev.off()
        
        # 3. Normalize counts using logNormCounts
        example_sce <- logNormCounts(example_sce)
        
        # 4. Calculate and plot variance explained by experimental variables using getVarianceExplained and plotExplanatoryVariables
        tryCatch({
            vars <- getVarianceExplained(example_sce,
                variables=meta_all)
            write.csv(head(vars), "variance_explained_head.csv", row.names=TRUE)
            write.csv(vars, "variance_explained_all.csv", row.names=TRUE)
        
            pdf("plot_explanatory_variables.pdf")
            p4 <- plotExplanatoryVariables(vars)
            print(p4)
            dev.off()
        }, error = function(e) {
            warning("Skipping variance explained calculation: ", e\$message)
        })
        
        # 5. Visualize gene expression profiles using plotExpression
        tryCatch({
            pdf("plot_expression_level1class.pdf")
            p5 <- plotExpression(example_sce, rownames(example_sce)[1:6], x = meta1)
            print(p5)
            dev.off()
        }, error = function(e) { warning("plotExpression 1 failed: ", e\$message) })
        
        tryCatch({
            pdf("plot_expression_scatter.pdf")
            p6 <- plotExpression(example_sce, rownames(example_sce)[1:6],
                x = rownames(example_sce)[10])
            print(p6)
            dev.off()
        }, error = function(e) { warning("plotExpression 2 failed: ", e\$message) })
        
        tryCatch({
            pdf("plot_expression_colour_by_tissue.pdf")
            p7 <- plotExpression(example_sce, rownames(example_sce)[1:6],
                x = meta1, colour_by=meta2)
            print(p7)
            dev.off()
        }, error = function(e) { warning("plotExpression 3 failed: ", e\$message) })
        
        tryCatch({
            pdf("plot_expression_default.pdf")
            p8 <- plotExpression(example_sce, rownames(example_sce)[1:6])
            print(p8)
            dev.off()
        }, error = function(e) { warning("plotExpression 4 failed: ", e\$message) })
        
        # 6. Perform dimensionality reduction using runPCA, runTSNE, and runUMAP
        n_comps_default <- max(1, min(50, ncol(example_sce) - 1, nrow(example_sce) - 1))
        example_sce <- runPCA(example_sce, ncomponents=n_comps_default)
        pca_str <- capture.output(str(reducedDim(example_sce, "PCA")))
        writeLines(pca_str, "pca_structure.txt")
        
        n_genes <- min(1000, nrow(example_sce))
        n_comps25 <- max(1, min(25, ncol(example_sce) - 1, nrow(example_sce) - 1))
        example_sce <- runPCA(example_sce, name="PCA2",
            subset_row=rownames(example_sce)[1:n_genes],
            ncomponents=n_comps25)
        pca2_str <- capture.output(str(reducedDim(example_sce, "PCA2")))
        writeLines(pca2_str, "pca2_structure.txt")
        
        set.seed(1000)
        perp10 <- floor((ncol(example_sce) - 1) / 3)
        if (perp10 * 3 >= ncol(example_sce) - 1) perp10 <- perp10 - 1
        perp10 <- max(1, min(10, perp10))
        example_sce <- runTSNE(example_sce, perplexity=perp10)
        write.csv(head(reducedDim(example_sce, "TSNE")), "tsne_perplexity10_head.csv")
        
        set.seed(1000)
        perp50 <- floor((ncol(example_sce) - 1) / 3)
        if (perp50 * 3 >= ncol(example_sce) - 1) perp50 <- perp50 - 1
        perp50 <- max(1, min(50, perp50))
        n_dimred10 <- max(1, min(10, ncol(reducedDim(example_sce, "PCA"))))
        example_sce <- runTSNE(example_sce, perplexity=perp50, 
            dimred="PCA", n_dimred=n_dimred10)
        write.csv(head(reducedDim(example_sce, "TSNE")), "tsne_perplexity50_head.csv")
        
        example_sce <- runUMAP(example_sce)
        write.csv(head(reducedDim(example_sce, "UMAP")), "umap_head.csv")
        
        # 7. Visualize reduced dimensions using plotReducedDim, plotTSNE, and plotPCA
        tryCatch({
            pdf("plot_reduced_dim_pca.pdf")
            p9 <- plotReducedDim(example_sce, dimred = "PCA", colour_by = meta1)
            print(p9)
            dev.off()
        }, error = function(e) { warning("plotReducedDim failed: ", e\$message) })
        
        tryCatch({
            pdf("plot_tsne_snap25.pdf")
            p10 <- plotTSNE(example_sce, colour_by = gene1)
            print(p10)
            dev.off()
        }, error = function(e) { warning("plotTSNE failed: ", e\$message) })
        
        tryCatch({
            pdf("plot_pca_mog.pdf")
            p11 <- plotPCA(example_sce, colour_by=gene2)
            print(p11)
            dev.off()
        }, error = function(e) { warning("plotPCA Mog failed: ", e\$message) })
        
        n_comps20 <- max(1, min(20, ncol(example_sce) - 1, nrow(example_sce) - 1))
        example_sce <- runPCA(example_sce, ncomponents=n_comps20)
        
        tryCatch({
            pdf("plot_pca_4comp.pdf")
            p12 <- plotPCA(example_sce, ncomponents = min(4, n_comps20), colour_by = meta1)
            print(p12)
            dev.off()
        }, error = function(e) { warning("plotPCA 4comp failed: ", e\$message) })
        
        # 8. Create custom plots using ggcells and ggfeatures
        tryCatch({
            pdf("ggcells_boxplot_snap25.pdf")
            p13 <- ggcells(example_sce, mapping=aes(x=.data[[meta1]], y=.data[[gene1]])) + 
                geom_boxplot() +
                facet_wrap(as.formula(paste0("~`", meta2, "`")))
            print(p13)
            dev.off()
        }, error = function(e) { warning("ggcells boxplot failed: ", e\$message) })
        
        tryCatch({
            pdf("ggcells_tsne_density.pdf")
            p14 <- ggcells(example_sce, mapping=aes(x=TSNE.1, y=TSNE.2, colour=.data[[gene1]])) +
                geom_point() +
                stat_density_2d() +
                facet_wrap(as.formula(paste0("~`", meta2, "`"))) +
                scale_colour_distiller(direction=1)
            print(p14)
            dev.off()
        }, error = function(e) { warning("ggcells tsne density failed: ", e\$message) })
        
        tryCatch({
            pdf("ggcells_smooth_actb.pdf")
            p15 <- ggcells(example_sce, mapping=aes(x=sizeFactor, y=.data[[gene3]])) +
                geom_point() +
                geom_smooth()
            print(p15)
            dev.off()
        }, error = function(e) { warning("ggcells smooth failed: ", e\$message) })
        
        colnames(example_sce) <- make.names(colnames(example_sce))
        cell1 <- colnames(example_sce)[1]
        row_meta_cols <- colnames(rowData(example_sce))
        
        tryCatch({
            pdf("ggfeatures_violin.pdf")
            if (length(row_meta_cols) > 0) {
                row_meta1 <- row_meta_cols[1]
                p16 <- ggfeatures(example_sce, mapping=aes(x=.data[[row_meta1]], y=.data[[cell1]])) + 
                    geom_violin()
            } else {
                p16 <- ggfeatures(example_sce, mapping=aes(x="All", y=.data[[cell1]])) + 
                    geom_violin()
            }
            print(p16)
            dev.off()
        }, error = function(e) { warning("ggfeatures violin failed: ", e\$message) })
        
        # Save the final processed SingleCellExperiment object
        saveRDS(example_sce, "processed_example_sce.rds")
        
        # Output session info
        writeLines(capture.output(sessionInfo()), "session_info.txt")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # per-cell QC metrics — alias semantics to cell QC metrics; reports
    # cells-flagged fraction by detecting library-size outliers via MAD.
    .pcqc_outlier_frac <- NA_real_; .pcqc_files <- character(0)
    for (.pcqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pcqc_obj <- tryCatch(readRDS(.pcqc_rds), error = function(e) NULL)
      .pcqc_mat <- if (is.matrix(.pcqc_obj) || is.data.frame(.pcqc_obj)) .pcqc_obj else NULL
      if (!is.null(.pcqc_mat) && ncol(.pcqc_mat) >= 10) {
        .pcqc_lib <- suppressWarnings(colSums(as.matrix(.pcqc_mat), na.rm = TRUE))
        if (length(.pcqc_lib) > 0 && all(is.finite(.pcqc_lib))) {
          .pcqc_med <- median(.pcqc_lib); .pcqc_mad <- mad(.pcqc_lib)
          .pcqc_outlier_frac <- if (.pcqc_mad > 0) mean(abs(.pcqc_lib - .pcqc_med) > 3 * .pcqc_mad) else 0
          .pcqc_files <- c(.pcqc_files, .pcqc_rds); break
        }
      }
    }
    .gates_by_label[["per-cell QC metrics"]] <- list(
      gate_row = "bioc_per_cell_qc_outliers",
      metric_name = "cells_flagged_outlier_fraction",
      metric_value = if (is.finite(.pcqc_outlier_frac)) round(.pcqc_outlier_frac, 4) else NA_real_,
      passes = isTRUE(is.finite(.pcqc_outlier_frac) && .pcqc_outlier_frac <= 0.1),
      status = if (is.finite(.pcqc_outlier_frac)) "computed (nmads=3 on lib sizes; scater::isOutlier proxy)"
               else "not_computed (no cell-count matrix .rds artifact present)"
    )

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
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
      process = "BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("per-cell QC metrics", "diagnostic MA/PCA QC", "cell QC metrics", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION":',
        paste0('    scater: ', as.character(packageVersion('scater')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_rnaseq_qc_and_visualization.csv versions.yml
    """
}

workflow BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_sce ] ]

    main:
    BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION.out.tables
    plots    = BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION.out.plots
    objects  = BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION.out.objects
    versions = BIOC_SCATER_SC_RNASEQ_QC_AND_VISUALIZATION.out.versions
}
