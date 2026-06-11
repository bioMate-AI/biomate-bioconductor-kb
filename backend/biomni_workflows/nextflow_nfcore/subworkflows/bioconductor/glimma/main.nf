#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Glimma — deseq2_glimma
// Run a complete DESeq2 differential expression analysis on user-provided RNA-seq counts and metadata, and generate interactive Glimma MDS and MA plots.
// Input: counts.csv, coldata.csv
// Container: 2.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, Glimma, htmlwidgets
// Visualizations: interactive MDS
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GLIMMA_DESEQ2_GLIMMA {
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
    library(Glimma)
    library(DESeq2)
    library(htmlwidgets)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    # Read counts and coldata
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    
    # Set row names of counts to gene_id
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_df\$gene_id <- NULL
    } else {
        rownames(counts_df) <- counts_df[, 1]
        counts_df[, 1] <- NULL
    }
    
    # Ensure sample names match between coldata and counts
    rownames(coldata_df) <- coldata_df\$sample
    common_samples <- intersect(colnames(counts_df), coldata_df\$sample)
    counts_df <- counts_df[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # Convert counts to integer matrix
    counts_matrix <- as.matrix(counts_df)
    class(counts_matrix) <- "integer"
    
    # Ensure condition is a factor
    coldata_df\$condition <- as.factor(coldata_df\$condition)
    
    # Create DESeqDataSet
    dds <- DESeqDataSetFromMatrix(
        countData = counts_matrix,
        colData = coldata_df,
        design = ~ condition
    )
    
    # Add gene annotations to rowData if available
    rowData(dds)\$GeneID <- rownames(dds)
    
    # ==========================================
    # --- Interactive MDS Plotting ---
    # ==========================================
    
    # Generate and save interactive MDS plot
    mds_plot <- glimmaMDS(dds)
    htmlwidgets::saveWidget(mds_plot, "glimma_mds_deseq2.html", selfcontained = TRUE)
    
    # ==========================================
    # --- Differential Expression & MA Plot ---
    # ==========================================
    
    # Run DESeq2 pipeline
    dds <- DESeq(dds, quiet = TRUE)
    
    # Generate and save interactive MA plot
    ma_plot <- glimmaMA(dds)
    htmlwidgets::saveWidget(ma_plot, "glimma_ma_deseq2.html", selfcontained = TRUE)

    writeLines(c(
        '"BIOC_GLIMMA_DESEQ2_GLIMMA":',
        paste0('    Glimma: ', as.character(packageVersion('Glimma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deseq2_glimma.csv versions.yml
    """
}

workflow BIOC_GLIMMA_DESEQ2_GLIMMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GLIMMA_DESEQ2_GLIMMA(ch_input)

    emit:
    tables   = BIOC_GLIMMA_DESEQ2_GLIMMA.out.tables
    plots    = BIOC_GLIMMA_DESEQ2_GLIMMA.out.plots
    objects  = BIOC_GLIMMA_DESEQ2_GLIMMA.out.objects
    versions = BIOC_GLIMMA_DESEQ2_GLIMMA.out.versions
}
