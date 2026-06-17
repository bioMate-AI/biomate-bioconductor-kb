#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PCAtools — pca_transcriptomics_pipeline
// Perform comprehensive Principal Component Analysis (PCA) on transcriptomic count data, including normalization, dimensionality selection, sample clustering visu
// Input: counts.csv, coldata.csv
// Container: 2.22.4--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, PCAtools, ggplot2
// Visualizations: PCA plot
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
