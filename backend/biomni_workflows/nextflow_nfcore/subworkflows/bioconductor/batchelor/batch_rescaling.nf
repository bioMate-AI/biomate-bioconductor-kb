#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: batchelor — batch_rescaling
// Center batches in log-expression space on a per-gene basis while preserving sparsity (best for technical replicates).
// Input: sce1, sce2
// Container: quay.io/biocontainers/bioconductor-batchelor:1.26.0--r45ha27e39d_0
// R packages: SingleCellExperiment, batchelor, scater, scran, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, batchelor, scater, scran, scuttle
// Visualizations: PCA plot
// QC: diagnostic MA/PCA QC, cell QC metrics, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Save the complete corrected SingleCellExperiment object
//  * 2. [Core Analysis] Save a diagnostic PCA plot showing the aligned batches
//  * 3. [Core Analysis] Save a subset of the corrected expression matrix to a CSV

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SingleCellExperiment", "batchelor", "scater", "scran", "scuttle", "SummarizedExperiment")
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
    library(batchelor)
    library(SummarizedExperiment)
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
    # --- Save the complete corrected SingleCellExperiment object ---
    saveRDS(rescale.out, "rescale_output.rds")
    
    # --- Save a diagnostic PCA plot showing the aligned batches ---
    pdf("rescale_pca_plot.pdf", width=8, height=6)
    p <- plotPCA(rescale.out, colour_by="batch")
    print(p)
    dev.off()
    
    # --- Save a subset of the corrected expression matrix to a CSV ---
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
