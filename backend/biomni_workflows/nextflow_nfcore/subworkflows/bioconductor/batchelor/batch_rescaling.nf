#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: batchelor — batch_rescaling
// Center batches in log-expression space on a per-gene basis while preserving sparsity (best for technical replicates).
// Input: sce1, sce2
// Container: quay.io/biocontainers/bioconductor-batchelor:1.26.0--r45ha27e39d_0
// Requires: SingleCellExperiment, batchelor, scater, scran, scuttle
// Visualizations: PCA plot
// QC: diagnostic MA/PCA QC, cell QC metrics, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run rescaleBatches to obtain a corrected expression matrix wrapped in a SingleCellExperiment

nextflow.enable.dsl = 2

process BIOC_BATCHELOR_BATCH_RESCALING {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(SingleCellExperiment)
    library(batchelor)
    library(scran)
    library(scater)
    library(scuttle)
    
    # Read user input files from the working directory
    file1 <- if (file.exists("sce1")) "sce1" else "sce1.rds"
    file2 <- if (file.exists("sce2")) "sce2" else "sce2.rds"
    
    sce1 <- readRDS(file1)
    sce2 <- readRDS(file2)
    
    # Preprocessing: Subset to common genes
    universe <- intersect(rownames(sce1), rownames(sce2))
    sce1 <- sce1[universe, ]
    sce2 <- sce2[universe, ]
    
    # Preprocessing: Multi-batch normalization to compute comparable log-expression values
    out <- multiBatchNorm(sce1, sce2)
    sce1 <- out[[1]]
    sce2 <- out[[2]]
    
    # --- DOCUMENTED WORKFLOW: batch_rescaling ---
    # Center batches in log-expression space on a per-gene basis while preserving sparsity
    rescale.out <- rescaleBatches(sce1, sce2)
    # --- END DOCUMENTED WORKFLOW ---
    
    # Downstream Analysis & Diagnostics
    # Identify highly variable genes (HVGs) for visualization
    dec1 <- modelGeneVar(sce1)
    dec2 <- modelGeneVar(sce2)
    combined.dec <- combineVar(dec1, dec2)
    chosen.hvgs <- getTopHVGs(combined.dec, n=min(5000, length(universe)))
    
    # Run PCA on the corrected expression values
    rescale.out <- runPCA(rescale.out, subset_row=chosen.hvgs, exprs_values="corrected")
    
    # Save outputs
    # 1. Save the complete corrected SingleCellExperiment object
    saveRDS(rescale.out, "rescale_output.rds")
    
    # 2. Save a diagnostic PCA plot showing the aligned batches
    pdf("rescale_pca_plot.pdf", width=8, height=6)
    p <- plotPCA(rescale.out, colour_by="batch")
    print(p)
    dev.off()
    
    # 3. Save a subset of the corrected expression matrix to a CSV file
    corrected_matrix <- assay(rescale.out, "corrected")
    subset_genes <- head(chosen.hvgs, min(100, length(chosen.hvgs)))
    write.csv(as.matrix(corrected_matrix[subset_genes, ]), "corrected_expression_subset.csv")

    writeLines(c(
        '"BIOC_BATCHELOR_BATCH_RESCALING":',
        paste0('    batchelor: ', as.character(packageVersion('batchelor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_rescaling.csv versions.yml
    """
}

workflow BIOC_BATCHELOR_BATCH_RESCALING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce1, sce2 ] ]

    main:
    BIOC_BATCHELOR_BATCH_RESCALING(ch_input)

    emit:
    tables   = BIOC_BATCHELOR_BATCH_RESCALING.out.tables
    plots    = BIOC_BATCHELOR_BATCH_RESCALING.out.plots
    objects  = BIOC_BATCHELOR_BATCH_RESCALING.out.objects
    versions = BIOC_BATCHELOR_BATCH_RESCALING.out.versions
}
