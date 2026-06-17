#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: batchelor — fast_mnn_correction
// Correct batch effects in single-cell RNA-seq datasets using the fast Mutual Nearest Neighbors (MNN) method in PCA space.
// Input: sce1, sce2
// Container: quay.io/biocontainers/bioconductor-batchelor:1.26.0--r45ha27e39d_0
// R packages: SingleCellExperiment, batchelor, ggplot2, knitr, scater, scran, scRNAseq, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, batchelor, ggplot2, scater, scran, scuttle
// Visualizations: t-SNE plot
// QC: per-cell QC metrics, batch-effect correction, cell QC metrics, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform quality control on cells
//  * 2. [Core Analysis] Subset datasets to common genes
//  * 3. [Core Analysis] Normalize sequencing depth across batches using multiBatchNorm
//  * 4. [Core Analysis] Model gene variance and select highly variable genes (HVGs)
//  * 5. [Core Analysis] Run fastMNN to obtain corrected low-dimensional coordinates

nextflow.enable.dsl = 2

process BIOC_BATCHELOR_FAST_MNN_CORRECTION {
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
    .bm_deps <- c("SingleCellExperiment", "batchelor", "ggplot2", "knitr", "scater", "scran", "scRNAseq", "scuttle", "SummarizedExperiment")
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
    library(scuttle)
    library(SummarizedExperiment)
    library(scran)
    library(batchelor)
    library(scater)
    library(ggplot2)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    # The pipeline reads exactly these files from the working directory
    sce1 <- readRDS("sce1.rds")
    sce2 <- readRDS("sce2.rds")
    
    # ==========================================
    # 2. Perform Quality Control on Cells
    # ==========================================
    # Identify mitochondrial genes and calculate QC metrics
    sce1 <- addPerCellQC(sce1, subsets=list(Mito=grep("mt-", rownames(sce1), ignore.case=TRUE)))
    qc1 <- quickPerCellQC(colData(sce1), sub.fields="subsets_Mito_percent")
    sce1 <- sce1[, !qc1\$discard]
    
    sce2 <- addPerCellQC(sce2, subsets=list(Mito=grep("mt_", rownames(sce2), ignore.case=TRUE)))
    qc2 <- quickPerCellQC(colData(sce2), sub.fields="subsets_Mito_percent")
    sce2 <- sce2[, !qc2\$discard]
    
    # ==========================================
    # 3. Subset Datasets to Common Genes
    # ==========================================
    universe <- intersect(rownames(sce1), rownames(sce2))
    sce1 <- sce1[universe,]
    sce2 <- sce2[universe,]
    
    # ==========================================
    # 4. Normalize Sequencing Depth Across Batches
    # ==========================================
    out <- multiBatchNorm(sce1, sce2)
    sce1 <- out[[1]]
    sce2 <- out[[2]]
    
    # ==========================================
    # 5. Model Gene Variance and Select HVGs
    # ==========================================
    dec1 <- modelGeneVar(sce1)
    dec2 <- modelGeneVar(sce2)
    combined.dec <- combineVar(dec1, dec2)
    chosen.hvgs <- getTopHVGs(combined.dec, n=5000)
    
    # ==========================================
    # 6. Run fastMNN to Obtain Corrected Coordinates
    # ==========================================
    set.seed(101)
    f.out <- fastMNN(A=sce1, B=sce2, subset.row=chosen.hvgs)
    
    # ==========================================
    # 7. Visualization and Diagnostics
    # ==========================================
    set.seed(103)
    f.out <- runTSNE(f.out, dimred="corrected")
    
    # Save t-SNE plot to PDF
    pdf("corrected_tsne_plot.pdf", width=8, height=6)
    print(plotTSNE(f.out, colour_by="batch") + ggtitle("fastMNN Corrected t-SNE"))
    dev.off()
    
    # ==========================================
    # 8. Save Outputs
    # ==========================================
    # Save the complete corrected SingleCellExperiment object
    saveRDS(f.out, "corrected_sce.rds")
    
    # Save corrected low-dimensional coordinates (PCA space)
    corrected_pcs <- reducedDim(f.out, "corrected")
    write.csv(as.data.frame(corrected_pcs), "corrected_coordinates.csv", row.names=TRUE)
    
    # Save cell metadata including batch assignments
    write.csv(as.data.frame(colData(f.out)), "corrected_metadata.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_BATCHELOR_FAST_MNN_CORRECTION":',
        paste0('    batchelor: ', as.character(packageVersion('batchelor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fast_mnn_correction.csv versions.yml
    """
}

workflow BIOC_BATCHELOR_FAST_MNN_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce1, sce2 ] ]

    main:
    BIOC_BATCHELOR_FAST_MNN_CORRECTION(ch_input)

    emit:
    tables   = BIOC_BATCHELOR_FAST_MNN_CORRECTION.out.tables
    plots    = BIOC_BATCHELOR_FAST_MNN_CORRECTION.out.plots
    objects  = BIOC_BATCHELOR_FAST_MNN_CORRECTION.out.objects
    versions = BIOC_BATCHELOR_FAST_MNN_CORRECTION.out.versions
}
