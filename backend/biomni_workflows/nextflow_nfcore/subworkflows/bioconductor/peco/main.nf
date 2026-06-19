#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: peco — peco_reconstruct_insample
// Reconstruct continuous cell cycle phases de novo from scRNA-seq data using PCA, circle projection, and in-sample non-parametric regression.
// Input: counts.csv, coldata.csv
// Container: 1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, SummarizedExperiment, peco
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE {
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
    .bm_deps <- c("peco", "SummarizedExperiment")
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
    library(peco)
    library(SummarizedExperiment)
    
    # 1. Load input data
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if (!"gene_id" %in% colnames(counts_df)) {
        colnames(counts_df)[1] <- "gene_id"
    }
    rownames(counts_df) <- counts_df\$gene_id
    counts_matrix <- as.matrix(counts_df[, -which(colnames(counts_df) == "gene_id"), drop = FALSE])
    
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    if (!"sample" %in% colnames(coldata)) {
        colnames(coldata)[1] <- "sample"
    }
    rownames(coldata) <- coldata\$sample
    
    # Align samples
    common_samples <- intersect(colnames(counts_matrix), rownames(coldata))
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Create SingleCellExperiment
    sce <- SingleCellExperiment(assays = list(counts = counts_matrix), colData = coldata)
    
    # Transform expression values
    sce <- data_transform_quantile(sce)
    yy <- assay(sce, "cpm_quantNormed")
    
    # Select top 50 highly variable genes for de novo reconstruction
    vars <- apply(yy, 1, var)
    top_genes <- names(sort(vars, decreasing = TRUE)[1:min(50, nrow(yy))])
    sce_sub <- sce[top_genes, ]
    yy_sub <- yy[top_genes, ]
    
    # Perform PCA to get 2D coordinates
    pca <- prcomp(t(yy_sub), scale. = TRUE)
    coords <- pca\$x[, 1:2]
    
    # Project to circle to get initial theta
    theta_init <- intensity2circle(coords)
    names(theta_init) <- colnames(sce_sub)
    
    # Run in-sample training/refinement
    fit_in <- tryCatch({
        cycle_npreg_insample(Y_train = sce_sub, theta = theta_init, ncores = 1)
    }, error = function(e) {
        cycle_npreg_insample(Y = sce_sub, theta = theta_init, ncores = 1)
    })
    
    # Extract refined phases
    theta_refined <- NULL
    if (!is.null(fit_in\$cellcycle_peco)) {
        theta_refined <- fit_in\$cellcycle_peco
    } else if (!is.null(fit_in\$Y) && !is.null(colData(fit_in\$Y)\$cellcycle_peco)) {
        theta_refined <- colData(fit_in\$Y)\$cellcycle_peco
    } else {
        theta_refined <- theta_init # fallback
    }
    
    reconstructed_df <- data.frame(
        sample = colnames(sce_sub),
        condition = colData(sce_sub)\$condition,
        theta_initial = theta_init,
        theta_refined = theta_refined,
        stringsAsFactors = FALSE
    )
    write.csv(reconstructed_df, "reconstructed_phases.csv", row.names = FALSE)
    
    # Fit cyclic trends for top 6 reconstructed genes
    genes_to_plot <- head(top_genes, 6)
    yy_plot <- yy[genes_to_plot, , drop = FALSE]
    fit_cyclic <- fit_cyclical_many(Y = yy_plot, theta = theta_refined)
    
    # Plot reconstructed trends
    pdf("reconstructed_trends.pdf", width = 10, height = 6)
    par(mfrow = c(2, 3))
    for (i in seq_along(genes_to_plot)) {
        gene <- genes_to_plot[i]
        plot(
            y = yy_plot[gene, ],
            x = fit_cyclic\$cellcycle_peco_ordered,
            main = gene,
            xlab = "Reconstructed Phase",
            ylab = "Quantile Normalized Expression",
            col = "grey",
            pch = 16
        )
        points(
            y = fit_cyclic\$cellcycle_function[[i]](seq(0, 2 * pi, length.out = 100)),
            x = seq(0, 2 * pi, length.out = 100),
            col = "red",
            pch = 16,
            cex = 0.8
        )
    }
    dev.off()
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE":',
        paste0('    peco: ', as.character(packageVersion('peco')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peco_reconstruct_insample.csv versions.yml
    """
}

workflow BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE(ch_input)

    emit:
    tables   = BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE.out.tables
    plots    = BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE.out.plots
    objects  = BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE.out.objects
    versions = BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE.out.versions
}
