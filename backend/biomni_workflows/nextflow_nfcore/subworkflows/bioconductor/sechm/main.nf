#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sechm — sechm_transcriptomics_heatmap
// Perform differential expression visualization and multi-dataset comparison using sechm on RNA-seq count data.
// Input: counts.csv, coldata.csv
// Container: 1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, SummarizedExperiment, sechm
// Visualizations: heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SECHM_SECHM_TRANSCRIPTOMICS_HEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    suppressPackageStartupMessages({
      library(sechm)
      library(ComplexHeatmap)
    })
    
    # ==========================================
    # --- Load Data and Construct SummarizedExperiment ---
    # ==========================================
    
    # Read input files from the working directory
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align counts and coldata
    common_samples <- intersect(colnames(counts), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv.")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Calculate log2 CPM (Counts Per Million) as a normalized assay
    libsizes <- colSums(counts)
    logcpm <- log2((t(t(counts) / libsizes) * 1e6) + 1)
    
    # Create the SummarizedExperiment object
    se <- SummarizedExperiment(
      assays = list(
        counts = as.matrix(counts),
        logcpm = as.matrix(logcpm)
      ),
      colData = coldata
    )
    
    # ==========================================
    # --- Calculate Log2 Fold Changes and Row Metadata ---
    # ==========================================
    
    # Identify control samples for fold-change calculation
    # We assume the first unique condition value represents the control group
    control_cond <- unique(coldata\$condition)[1]
    control_logical <- coldata\$condition == control_cond
    
    # Compute log2 fold changes using sechm's log2FC or fallback manually
    se <- tryCatch({
      log2FC(se, controls = control_logical, assayName = "logcpm")
    }, error = function(e) {
      message("log2FC function failed or not applicable; calculating manually...")
      control_mean <- rowMeans(logcpm[, control_logical, drop = FALSE])
      lfc <- logcpm - control_mean
      assays(se)\$log2FC <- lfc
      assays(se)\$scaledLFC <- safescale(lfc)
      se
    })
    
    # Add row-level metadata (mean expression and variance)
    rowData(se)\$meanLogCPM <- rowMeans(assays(se)\$logcpm)
    rowData(se)\$variance <- apply(assays(se)\$logcpm, 1, var)
    
    # Select top highly variable genes for visualization
    top_n <- min(30, nrow(se))
    top_genes <- names(sort(rowData(se)\$variance, decreasing = TRUE)[1:top_n])
    
    # ==========================================
    # --- Generate Single-Dataset Heatmaps ---
    # ==========================================
    
    pdf("sechm_plots.pdf", width = 10, height = 8)
    
    # 1. Basic scaled heatmap of top variable genes
    p1 <- sechm(
      se, 
      features = top_genes, 
      assayName = "logcpm", 
      do.scale = TRUE,
      top_annotation = "condition", 
      left_annotation = "meanLogCPM",
      show_colnames = TRUE
    )
    draw(p1, column_title = "Top Variable Genes (Scaled LogCPM)")
    
    # 2. Heatmap of Log2 Fold Changes with quantile capping (breaks)
    lfc_assay <- if ("log2FC" %in% assayNames(se)) "log2FC" else "logcpm"
    p2 <- sechm(
      se, 
      features = top_genes, 
      assayName = lfc_assay, 
      breaks = 0.98, 
      top_annotation = "condition",
      show_colnames = TRUE
    )
    draw(p2, column_title = "Top Variable Genes (Log2FC with Quantile Capping)")
    
    # 3. Customizing colors using global package options
    setSechmOption("hmcols", value = c("darkblue", "white", "darkred"))
    p3 <- sechm(
      se, 
      features = top_genes, 
      assayName = "logcpm", 
      do.scale = TRUE,
      top_annotation = "condition"
    )
    draw(p3, column_title = "Custom Global Color Palette (Blue-White-Red)")
    
    # Reset options to default
    resetAllSechmOptions()
    
    dev.off()
    
    # ==========================================
    # --- Multi-Dataset Comparison (crossHm) ---
    # ==========================================
    
    # Simulate a second dataset (e.g., a technical replicate or batch) by adding jitter
    se2 <- se
    assays(se2)\$logcpm <- jitter(assays(se2)\$logcpm, factor = 500)
    
    pdf("cross_heatmap.pdf", width = 12, height = 8)
    
    # Plot comparative heatmap across both datasets with a unified scale
    p_cross <- crossHm(
      list(Dataset_A = se, Dataset_B = se2), 
      features = top_genes, 
      assayName = "logcpm", 
      do.scale = TRUE, 
      top_annotation = "condition", 
      uniqueScale = TRUE
    )
    draw(p_cross, column_title = "Cross-Dataset Comparison (Unified Scale)")
    
    dev.off()
    
    # ==========================================
    # --- Export Melted Data Frame ---
    # ==========================================
    
    # Extract tidy format data for the top features
    melted_df <- meltSE(se, features = top_genes, assayName = "logcpm")
    write.csv(melted_df, "melted_top_genes.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_SECHM_SECHM_TRANSCRIPTOMICS_HEATMAP":',
        paste0('    sechm: ', as.character(packageVersion('sechm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sechm_transcriptomics_heatmap.csv versions.yml
    """
}

workflow BIOC_SECHM_SECHM_TRANSCRIPTOMICS_HEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SECHM_SECHM_TRANSCRIPTOMICS_HEATMAP(ch_input)

    emit:
    tables   = BIOC_SECHM_SECHM_TRANSCRIPTOMICS_HEATMAP.out.tables
    plots    = BIOC_SECHM_SECHM_TRANSCRIPTOMICS_HEATMAP.out.plots
    objects  = BIOC_SECHM_SECHM_TRANSCRIPTOMICS_HEATMAP.out.objects
    versions = BIOC_SECHM_SECHM_TRANSCRIPTOMICS_HEATMAP.out.versions
}
