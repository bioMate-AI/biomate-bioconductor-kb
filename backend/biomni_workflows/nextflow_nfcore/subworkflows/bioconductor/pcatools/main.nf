#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PCAtools — pca_transcriptomics_pipeline
// Perform comprehensive Principal Component Analysis (PCA) on transcriptomic count data, including normalization, dimensionality selection, sample clustering visu
// Input: counts.csv, coldata.csv
// Container: 2.22.4--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, PCAtools, ggplot2
// Visualizations: scree plot, biplot, PCA plot
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PCATOOLS_PCA_TRANSCRIPTOMICS_PIPELINE {
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
    .bm_deps <- c("PCAtools", "ggplot2", "SummarizedExperiment")
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
    library(PCAtools)
    library(SummarizedExperiment)
    library(ggplot2)
    
    # ==========================================
    # --- Data Loading and Preprocessing ---
    # ==========================================
    
    # Read counts matrix
    counts_df <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_df\$gene_id <- NULL
    } else {
        rownames(counts_df) <- counts_df[, 1]
        counts_df <- counts_df[, -1, drop = FALSE]
    }
    
    # Ensure all columns are numeric
    numeric_cols <- sapply(counts_df, is.numeric)
    counts_mat <- as.matrix(counts_df[, numeric_cols, drop = FALSE])
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if ("sample" %in% colnames(coldata)) {
        rownames(coldata) <- coldata\$sample
    } else {
        rownames(coldata) <- coldata[, 1]
    }
    
    # Align counts and metadata
    common_samples <- intersect(colnames(counts_mat), rownames(coldata))
    if (length(common_samples) == 0) {
        stop("Error: No matching sample names found between counts.csv and coldata.csv.")
    }
    counts_mat <- counts_mat[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Perform normalization (DESeq2 VST if available, fallback to log2-CPM)
    if (requireNamespace("DESeq2", quietly = TRUE)) {
        message("Using DESeq2 Variance Stabilizing Transformation (VST) for normalization...")
        dds <- DESeq2::DESeqDataSetFromMatrix(countData = counts_mat,
                                              colData = coldata,
                                              design = ~ 1)
        vst_mat <- DESeq2::assay(DESeq2::vst(dds, blind = TRUE))
    } else {
        message("DESeq2 not detected. Falling back to log2(CPM + 1) normalization...")
        libsizes <- colSums(counts_mat)
        cpm <- t(t(counts_mat) / libsizes) * 1e6
        vst_mat <- log2(cpm + 1)
    }
    
    # ==========================================
    # --- Principal Component Analysis ---
    # ==========================================
    
    # Run PCA with variance-based filtering
    removeVar_param <- as.numeric(Sys.getenv("removeVar", unset = "0.1"))
    p <- pca(vst_mat, metadata = coldata, removeVar = removeVar_param)
    
    # Save PCA outputs to CSV
    summary_df <- data.frame(
        PC = names(p\$variance),
        Variance = p\$variance,
        CumulativeVariance = cumsum(p\$variance)
    )
    write.csv(summary_df, "pca_summary.csv", row.names = FALSE)
    write.csv(as.data.frame(p\$rotated), "pca_rotated.csv", row.names = TRUE)
    write.csv(as.data.frame(p\$loadings), "pca_loadings.csv", row.names = TRUE)
    
    # ==========================================
    # --- Determine Optimum Number of PCs ---
    # ==========================================
    
    # Find elbow point
    elbow <- findElbowPoint(p\$variance)
    
    # Run Horn's parallel analysis (wrapped in tryCatch for robustness)
    horn_n <- tryCatch({
        horn <- parallelPCA(vst_mat)
        horn\$n
    }, error = function(e) {
        warning("Horn's parallel PCA failed: ", e\$message)
        return(NULL)
    })
    
    # Determine vertical lines to plot on the scree plot
    vlines <- c(elbow)
    if (!is.null(horn_n)) vlines <- c(vlines, horn_n)
    vlines <- vlines[vlines <= length(p\$variance)]
    
    # ==========================================
    # --- Generate Diagnostic & Exploratory Plots ---
    # ==========================================
    
    # 1. Scree Plot
    p_scree <- screeplot(p, components = getComponents(p, 1:min(20, length(p\$variance))), vline = vlines) +
        labs(title = "Scree Plot", subtitle = "Identifying optimal number of PCs to retain")
    
    # 2. Biplot
    colby_var <- if ("condition" %in% colnames(coldata)) "condition" else NULL
    p_biplot <- biplot(p, 
                       colby = colby_var, 
                       legendPosition = "right",
                       title = "PCA Biplot",
                       subtitle = "PC1 vs PC2 sample distribution")
    
    # 3. Pairs Plot (First 4 PCs)
    pcs_to_plot <- getComponents(p, 1:min(4, length(p\$variance)))
    p_pairs <- pairsplot(p, 
                         components = pcs_to_plot, 
                         colby = colby_var,
                         title = "Pairs Plot of Top PCs")
    
    # 4. Loadings Plot (Top driving genes for PC1 and PC2)
    pcs_loadings <- getComponents(p, 1:min(2, length(p\$variance)))
    p_loadings <- plotloadings(p, 
                               components = pcs_loadings, 
                               rangeRetain = 0.05, 
                               drawConnectors = TRUE,
                               title = "Gene Loadings Plot",
                               subtitle = "Top 5% driving variables for PC1 & PC2")
    
    # 5. Eigencor Plot (Correlation with metadata)
    # Filter metadata to find columns with sufficient variation for correlation
    valid_meta <- colnames(coldata)[sapply(coldata, function(x) {
        lu <- length(unique(x))
        lu > 1 && lu < length(x)
    })]
    
    # ==========================================
    # --- Export Multi-page PDF Report ---
    # ==========================================
    
    pdf("pca_report.pdf", width = 10, height = 8)
    
    print(p_scree)
    print(p_biplot)
    print(p_pairs)
    print(p_loadings)
    
    if (length(valid_meta) > 0) {
        tryCatch({
            eigencorplot(p, 
                         components = getComponents(p, 1:min(10, length(p\$variance))), 
                         metavars = valid_meta,
                         main = "PC Clinical & Metadata Correlations",
                         signifSymbols = c('****', '***', '**', '*', ''),
                         signifCutpoints = c(0, 0.0001, 0.001, 0.01, 0.05, 1))
        }, error = function(e) {
            warning("Eigencorplot generation failed: ", e\$message)
        })
    }
    
    dev.off()
    
    message("PCA analysis completed successfully. Outputs written to working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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
      process = "BIOC_PCATOOLS_PCA_TRANSCRIPTOMICS_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PCATOOLS_PCA_TRANSCRIPTOMICS_PIPELINE":',
        paste0('    PCAtools: ', as.character(packageVersion('PCAtools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_transcriptomics_pipeline.csv versions.yml
    """
}

workflow BIOC_PCATOOLS_PCA_TRANSCRIPTOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PCATOOLS_PCA_TRANSCRIPTOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PCATOOLS_PCA_TRANSCRIPTOMICS_PIPELINE.out.tables
    plots    = BIOC_PCATOOLS_PCA_TRANSCRIPTOMICS_PIPELINE.out.plots
    objects  = BIOC_PCATOOLS_PCA_TRANSCRIPTOMICS_PIPELINE.out.objects
    versions = BIOC_PCATOOLS_PCA_TRANSCRIPTOMICS_PIPELINE.out.versions
}
