#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SCArray — gds_single_cell_analysis
// Convert single-cell data to GDS format, load it as a GDS-backed SingleCellExperiment, and perform memory-efficient downstream analysis.
// Input: example.rds, example.gds
// Container: quay.io/biocontainers/bioconductor-scarray:1.18.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, SCArray, SingleCellExperiment, scater, scuttle
// Visualizations: ordination plot, PCA plot, UMAP plot
// QC: cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert SingleCellExperiment or matrix to GDS format using scConvGDS()
//  * 2. [Input & Preparation] Load GDS file as a SingleCellExperiment using scExperiment()
//  * 3. [Core Analysis] Normalize counts using logNormCounts()
//  * 4. [Visualization & Output] Calculate row and column summarizations using colMeans(), rowMeans(), and scRowMeanVar()
//  * 5. [Core Analysis] Perform memory-efficient PCA using scRunPCA()
//  * 6. [Core Analysis] Perform UMAP dimensionality reduction using runUMAP()

nextflow.enable.dsl = 2

process BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS {
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
    .bm_deps <- c("SCArray", "SingleCellExperiment", "Matrix", "scuttle", "scater")
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
    suppressPackageStartupMessages(library(SCArray))
    suppressPackageStartupMessages(library(SingleCellExperiment))
    suppressPackageStartupMessages(library(Matrix))
    suppressPackageStartupMessages(library(scuttle))
    suppressPackageStartupMessages(library(scater))
    
    # 1. Convert SingleCellExperiment to GDS format
    # Read the user-provided SingleCellExperiment RDS file from the working directory
    fn_rds <- "example.rds"
    sce <- readRDS(fn_rds)
    
    # Convert to GDS format
    scConvGDS(sce, "test.gds")
    
    # Open and close the GDS file to verify structure
    f <- scOpen("test.gds")
    scClose(f)
    
    # 2. Convert a sparse matrix to GDS format
    cnt <- matrix(0, nrow=4, ncol=8)
    set.seed(100)
    cnt[sample.int(length(cnt), 8)] <- rpois(8, 4)
    cnt <- as(cnt, "sparseMatrix")
    
    if (file.exists("test.gds")) {
        unlink("test.gds", force=TRUE)
    }
    scConvGDS(cnt, "test.gds")
    
    # 3. Load GDS file as a SingleCellExperiment
    # Read the user-provided GDS file from the working directory
    fn_gds <- "example.gds"
    sce <- scExperiment(fn_gds)
    
    # Extract counts and compute log-transformed counts (DelayedMatrix)
    cnt <- assays(sce)\$counts
    logcnt <- log2(cnt + 1)
    
    # 4. Normalize counts using logNormCounts
    sce <- logNormCounts(sce)
    
    # 5. Calculate row and column summarizations
    col_mean <- colMeans(logcnt)
    row_mean <- rowMeans(logcnt)
    mvar <- scRowMeanVar(logcnt)
    
    # Save summarization results to disk
    write.csv(as.data.frame(col_mean), "column_means.csv", row.names=TRUE)
    write.csv(as.data.frame(row_mean), "row_means.csv", row.names=TRUE)
    write.csv(as.data.frame(mvar), "row_mean_variance.csv", row.names=TRUE)
    
    # 6. Perform memory-efficient PCA
    sce <- scRunPCA(sce)
    
    # Plot and save PCA results
    pdf("pca_plot.pdf", width=6, height=5)
    plotReducedDim(sce, dimred="PCA")
    dev.off()
    
    # 7. Perform UMAP dimensionality reduction
    sce <- runUMAP(sce)
    
    # Plot and save UMAP results
    pdf("umap_plot.pdf", width=6, height=5)
    plotReducedDim(sce, dimred="UMAP")
    dev.off()
    
    # Save the final analyzed SingleCellExperiment object
    saveRDS(sce, "analyzed_sce.rds")
    
    # Clean up temporary GDS file
    if (file.exists("test.gds")) {
        unlink("test.gds", force=TRUE)
    }

    writeLines(c(
        '"BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS":',
        paste0('    SCArray: ', as.character(packageVersion('SCArray')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gds_single_cell_analysis.csv versions.yml
    """
}

workflow BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.rds, example.gds ] ]

    main:
    BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS.out.tables
    plots    = BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS.out.plots
    objects  = BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS.out.objects
    versions = BIOC_SCARRAY_GDS_SINGLE_CELL_ANALYSIS.out.versions
}
