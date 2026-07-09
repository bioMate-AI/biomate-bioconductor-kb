#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EnhancedVolcano — enhanced_volcano_transcriptomics
// Perform differential expression analysis on RNA-seq count data using DESeq2 and generate highly-configurable, publication-ready volcano plots using EnhancedVolc
// Input: counts.csv, coldata.csv
// Container: 1.28.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, EnhancedVolcano, ggplot2, gridExtra
// Visualizations: volcano plot
// QC: low-count filtering
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENHANCEDVOLCANO_ENHANCED_VOLCANO_TRANSCRIPTOMICS {
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
    .bm_deps <- c("DESeq2", "EnhancedVolcano", "ggplot2", "gridExtra")
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
    
    # --- Load required libraries ---
    library(DESeq2)
    library(EnhancedVolcano)
    library(ggplot2)
    library(gridExtra)
    library(grid)
    
    # --- Load and preprocess input data ---
    # Read counts and coldata from the working directory
    counts <- read.csv("counts.csv", row.names = "gene_id", check.names = FALSE)
    coldata <- read.csv("coldata.csv", row.names = "sample", check.names = FALSE)
    
    # Ensure sample names match between counts and coldata
    common_samples <- intersect(colnames(counts), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Ensure condition is a factor
    coldata\$condition <- as.factor(coldata\$condition)
    cond_levels <- levels(coldata\$condition)
    if (length(cond_levels) < 2) {
      stop("The 'condition' column must have at least two levels for differential analysis.")
    }
    
    # --- Differential Expression Analysis with DESeq2 ---
    dds <- DESeqDataSetFromMatrix(countData = counts, colData = coldata, design = ~ condition)
    
    # Filter out low-count genes to improve power
    keep <- rowSums(counts(dds)) >= 10
    dds <- dds[keep, ]
    
    # Run DESeq2 pipeline
    dds <- DESeq(dds)
    
    # Extract results for the primary contrast
    res <- results(dds, contrast = c("condition", cond_levels[2], cond_levels[1]))
    
    # Apply log2 fold change shrinkage for more stable estimates
    res_shrunk <- tryCatch({
      lfcShrink(dds, contrast = c("condition", cond_levels[2], cond_levels[1]), res = res, type = "normal")
    }, error = function(e) {
      warning("LFC shrinkage failed, using unshrunk results: ", e\$message)
      res
    })
    
    # Save differential expression results to CSV
    write.csv(as.data.frame(res_shrunk), "de_results.csv", row.names = TRUE)
    
    # Identify top significant genes for labeling
    top_genes <- rownames(res_shrunk)[order(res_shrunk\$pvalue, na.last = TRUE)][1:10]
    top_genes <- top_genes[!is.na(top_genes)]
    
    # --- Generate EnhancedVolcano Plots ---
    
    # Plot 1: Basic Volcano Plot
    pdf("volcano_basic.pdf", width = 8, height = 9)
    p_basic <- EnhancedVolcano(
      res_shrunk,
      lab = rownames(res_shrunk),
      x = "log2FoldChange",
      y = "pvalue",
      title = "Differential Expression: Basic Volcano",
      subtitle = paste(cond_levels[2], "vs", cond_levels[1]),
      pCutoff = 1e-5,
      FCcutoff = 1.0,
      pointSize = 2.0,
      labSize = 4.0
    )
    print(p_basic)
    dev.off()
    
    # Plot 2: Advanced Volcano Plot with Boxed Labels and Connectors
    pdf("volcano_advanced.pdf", width = 9, height = 10)
    p_adv <- EnhancedVolcano(
      res_shrunk,
      lab = rownames(res_shrunk),
      x = "log2FoldChange",
      y = "pvalue",
      selectLab = top_genes,
      xlab = bquote(~Log[2]~ "fold change"),
      ylab = bquote(~-Log[10]~ "p-value"),
      title = "Differential Expression: Advanced Volcano",
      subtitle = "Top 10 most significant genes highlighted",
      pCutoff = 1e-6,
      FCcutoff = 1.5,
      pointSize = 3.0,
      labSize = 5.0,
      labCol = "black",
      labFace = "bold",
      boxedLabels = TRUE,
      colAlpha = 0.8,
      legendPosition = "right",
      legendLabSize = 12,
      legendIconSize = 4.0,
      drawConnectors = TRUE,
      widthConnectors = 0.75,
      colConnectors = "grey30",
      arrowheads = FALSE,
      gridlines.major = TRUE,
      gridlines.minor = FALSE,
      border = "partial",
      borderWidth = 1.5,
      borderColour = "black"
    )
    print(p_adv)
    dev.off()
    
    # Plot 3: Custom Color Override Volcano Plot
    # Create custom key-value pairs for coloring based on custom thresholds
    keyvals <- ifelse(
      res_shrunk\$log2FoldChange < -2.0 & res_shrunk\$pvalue < 1e-5, "royalblue",
      ifelse(res_shrunk\$log2FoldChange > 2.0 & res_shrunk\$pvalue < 1e-5, "gold", "grey60")
    )
    keyvals[is.na(keyvals)] <- "grey60"
    names(keyvals)[keyvals == "gold"] <- "Upregulated (High)"
    names(keyvals)[keyvals == "grey60"] <- "Unchanged / Low"
    names(keyvals)[keyvals == "royalblue"] <- "Downregulated (Low)"
    
    pdf("volcano_custom_colors.pdf", width = 9, height = 10)
    p_custom <- EnhancedVolcano(
      res_shrunk,
      lab = rownames(res_shrunk),
      x = "log2FoldChange",
      y = "pvalue",
      selectLab = top_genes,
      xlab = bquote(~Log[2]~ "fold change"),
      title = "Custom Color Overrides",
      subtitle = "Highlighting extreme fold changes",
      pCutoff = 1e-5,
      FCcutoff = 2.0,
      pointSize = 3.5,
      labSize = 4.5,
      colCustom = keyvals,
      colAlpha = 0.9,
      legendPosition = "bottom",
      legendLabSize = 12,
      legendIconSize = 5.0,
      drawConnectors = TRUE,
      widthConnectors = 0.5,
      colConnectors = "black"
    )
    print(p_custom)
    dev.off()
    
    # Plot 4: Continuous Color Gradient Volcano Plot
    pdf("volcano_continuous.pdf", width = 9, height = 10)
    p_cont <- EnhancedVolcano(
      res_shrunk,
      lab = rownames(res_shrunk),
      x = "log2FoldChange",
      y = "pvalue",
      pCutoff = 1e-5,
      FCcutoff = 1.0,
      pointSize = 2.5,
      labSize = 4.0,
      title = "Continuous Color Gradient",
      subtitle = "Shading based on statistical significance",
      colAlpha = 0.85,
      colGradient = c("red3", "royalblue"),
      legendPosition = "right",
      legendLabSize = 12,
      drawConnectors = TRUE,
      widthConnectors = 0.5
    )
    print(p_cont)
    dev.off()
    
    message("EnhancedVolcano pipeline completed successfully. Outputs generated.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_ENHANCEDVOLCANO_ENHANCED_VOLCANO_TRANSCRIPTOMICS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ENHANCEDVOLCANO_ENHANCED_VOLCANO_TRANSCRIPTOMICS":',
        paste0('    EnhancedVolcano: ', as.character(packageVersion('EnhancedVolcano')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enhanced_volcano_transcriptomics.csv versions.yml
    """
}

workflow BIOC_ENHANCEDVOLCANO_ENHANCED_VOLCANO_TRANSCRIPTOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ENHANCEDVOLCANO_ENHANCED_VOLCANO_TRANSCRIPTOMICS(ch_input)

    emit:
    tables   = BIOC_ENHANCEDVOLCANO_ENHANCED_VOLCANO_TRANSCRIPTOMICS.out.tables
    plots    = BIOC_ENHANCEDVOLCANO_ENHANCED_VOLCANO_TRANSCRIPTOMICS.out.plots
    objects  = BIOC_ENHANCEDVOLCANO_ENHANCED_VOLCANO_TRANSCRIPTOMICS.out.objects
    versions = BIOC_ENHANCEDVOLCANO_ENHANCED_VOLCANO_TRANSCRIPTOMICS.out.versions
}
