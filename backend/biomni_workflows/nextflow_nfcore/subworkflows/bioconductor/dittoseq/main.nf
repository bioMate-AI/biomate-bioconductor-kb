#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dittoSeq — dittoseq_bulk_rna_seq_visualization
// Import bulk RNA-seq count data, perform dimensionality reduction, and generate a comprehensive suite of color-blind-friendly diagnostic and exploratory plots us
// Input: counts.csv, coldata.csv
// Container: 1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, dittoSeq
// Visualizations: PCA plot, box plot, bar plot, heatmap, dot plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DITTOSEQ_DITTOSEQ_BULK_RNA_SEQ_VISUALIZATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("dittoSeq")
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
    library(dittoSeq)
    
    # ==========================================
    # --- Load and Align Input Data ---
    # ==========================================
    message("Loading input datasets...")
    counts_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Ensure sample names are set as row names for coldata
    if ("sample" %in% colnames(coldata_df)) {
        rownames(coldata_df) <- coldata_df\$sample
    } else {
        rownames(coldata_df) <- colnames(counts_df)
    }
    
    # Align counts and coldata to ensure matching samples
    common_samples <- intersect(colnames(counts_df), rownames(coldata_df))
    if (length(common_samples) == 0) {
        stop("Error: No common samples found between counts.csv and coldata.csv")
    }
    
    counts_mat <- as.matrix(counts_df[, common_samples, drop = FALSE])
    coldata_df <- coldata_df[common_samples, drop = FALSE]
    
    # Add a mock batch metadata to demonstrate multi-variable annotations
    coldata_df\$batch <- factor(rep(c("Batch_A", "Batch_B"), length.out = nrow(coldata_df)))
    
    # ==========================================
    # --- Normalization & Dimensionality Reduction ---
    # ==========================================
    message("Performing log-normalization and PCA...")
    # Simple log2 transformation for visualization purposes
    logcounts_mat <- log2(counts_mat + 1)
    
    # Identify highly variable genes for PCA
    gene_vars <- apply(logcounts_mat, 1, var)
    top_genes <- names(sort(gene_vars, decreasing = TRUE))[1:min(500, nrow(logcounts_mat))]
    
    # Run PCA on top variable genes
    pca_res <- prcomp(t(logcounts_mat[top_genes, ]))
    pca_embeddings <- pca_res\$x[, 1:2, drop = FALSE]
    
    # ==========================================
    # --- Import into dittoSeq Structure ---
    # ==========================================
    message("Importing data into dittoSeq bulk structure...")
    bulkSCE <- importDittoBulk(
        x = list(counts = counts_mat, logcounts = logcounts_mat),
        metadata = coldata_df,
        reductions = list(pca = pca_embeddings)
    )
    
    # Verify bulk status using dittoSeq helper
    is_bulk_dataset <- isBulk(bulkSCE)
    message("Is the imported object recognized as bulk? ", is_bulk_dataset)
    
    # ==========================================
    # --- Comprehensive Visualizations ---
    # ==========================================
    message("Generating dittoSeq visualizations...")
    
    # 1. PCA Plot (Dimensionality Reduction)
    pdf("pca_plot.pdf", width = 6, height = 5)
    dittoDimPlot(
        object = bulkSCE, 
        var = "condition", 
        reduction.use = "pca", 
        size = 4, 
        do.ellipse = TRUE, 
        main = "PCA of Bulk RNA-Seq Samples"
    )
    dev.off()
    
    # 2. Boxplot of the top variable gene
    pdf("boxplot_top_gene.pdf", width = 6, height = 5)
    dittoBoxPlot(
        object = bulkSCE, 
        var = top_genes[1], 
        group.by = "condition", 
        main = paste("Expression of", top_genes[1])
    )
    dev.off()
    
    # 3. Barplot of batch distribution across conditions
    pdf("barplot_batch.pdf", width = 6, height = 5)
    dittoBarPlot(
        object = bulkSCE, 
        var = "batch", 
        group.by = "condition", 
        main = "Batch Distribution by Condition"
    )
    dev.off()
    
    # 4. Heatmap of top variable genes
    pdf("heatmap_top_genes.pdf", width = 7, height = 6)
    dittoHeatmap(
        object = bulkSCE, 
        genes = top_genes[1:min(15, length(top_genes))], 
        annot.by = c("condition", "batch"),
        scaled.to.max = TRUE,
        main = "Top Variable Genes Heatmap"
    )
    dev.off()
    
    # 5. DotPlot of top variable genes
    pdf("dotplot_genes.pdf", width = 7, height = 5)
    dittoDotPlot(
        object = bulkSCE, 
        vars = top_genes[1:min(8, length(top_genes))], 
        group.by = "condition",
        main = "Dot Plot of Top Genes"
    )
    dev.off()
    
    # ==========================================
    # --- Extracting Underlying Data & Metadata ---
    # ==========================================
    message("Exporting underlying plot data and metadata summaries...")
    
    # Extract underlying data from the barplot
    barplot_data <- dittoBarPlot(
        object = bulkSCE, 
        var = "batch", 
        group.by = "condition", 
        data.out = TRUE
    )
    write.csv(barplot_data\$data, "barplot_underlying_data.csv", row.names = FALSE)
    
    # Extract metadata summary using dittoSeq helpers
    meta_slots <- getMetas(bulkSCE)
    meta_summary <- data.frame(
        Metadata = meta_slots,
        IsPresent = sapply(meta_slots, function(m) isMeta(m, bulkSCE)),
        Levels = sapply(meta_slots, function(m) paste(metaLevels(m, bulkSCE), collapse = ", "))
    )
    write.csv(meta_summary, "metadata_summary.csv", row.names = FALSE)
    
    message("Workflow completed successfully!")

    writeLines(c(
        '"BIOC_DITTOSEQ_DITTOSEQ_BULK_RNA_SEQ_VISUALIZATION":',
        paste0('    dittoSeq: ', as.character(packageVersion('dittoSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dittoseq_bulk_rna_seq_visualization.csv versions.yml
    """
}

workflow BIOC_DITTOSEQ_DITTOSEQ_BULK_RNA_SEQ_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DITTOSEQ_DITTOSEQ_BULK_RNA_SEQ_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_DITTOSEQ_DITTOSEQ_BULK_RNA_SEQ_VISUALIZATION.out.tables
    plots    = BIOC_DITTOSEQ_DITTOSEQ_BULK_RNA_SEQ_VISUALIZATION.out.plots
    objects  = BIOC_DITTOSEQ_DITTOSEQ_BULK_RNA_SEQ_VISUALIZATION.out.objects
    versions = BIOC_DITTOSEQ_DITTOSEQ_BULK_RNA_SEQ_VISUALIZATION.out.versions
}
