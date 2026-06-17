#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Dino — standard_matrix_normalization_and_seurat
// Filter and normalize a raw UMI count matrix using Dino, then convert it to a Seurat object for downstream clustering and visualization.
// Input: pbmcSmall
// Container: quay.io/biocontainers/bioconductor-dino:1.16.0--r45hdfd78af_0
// R packages: Dino, knitr, Matrix, scran, Seurat, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: Dino, Matrix, Seurat
// Visualizations: UMAP/t-SNE plot, UMAP plot
// QC: low-count filtering, highly-variable feature selection, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out genes with low non-zero expression
//  * 2. [Core Analysis] Normalize the UMI count matrix using Dino
//  * 3. [Core Analysis] Convert the normalized matrix into a Seurat object using SeuratFromDino
//  * 4. [Visualization & Output] Run downstream Seurat clustering and visualization (FindVariableFeatures, ScaleData, RunPCA, FindNeighbors, FindClusters, RunUMAP,

nextflow.enable.dsl = 2

process BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT {
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
    .bm_deps <- c("Dino", "knitr", "Matrix", "scran", "Seurat", "SingleCellExperiment")
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
    library(Dino)
    library(Seurat)
    library(Matrix)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input File
    # -----------------------------------------------------------------------------
    # The pipeline expects 'pbmcSmall' in the working directory.
    # We support RDS, CSV, TSV, or a generic text file.
    if (file.exists("pbmcSmall.rds")) {
      pbmcSmall <- readRDS("pbmcSmall.rds")
    } else if (file.exists("pbmcSmall.csv")) {
      pbmcSmall <- read.csv("pbmcSmall.csv", row.names = 1, check.names = FALSE)
      pbmcSmall <- as.matrix(pbmcSmall)
    } else if (file.exists("pbmcSmall.tsv")) {
      pbmcSmall <- read.delim("pbmcSmall.tsv", row.names = 1, check.names = FALSE)
      pbmcSmall <- as.matrix(pbmcSmall)
    } else if (file.exists("pbmcSmall")) {
      pbmcSmall <- tryCatch({
        readRDS("pbmcSmall")
      }, error = function(e) {
        as.matrix(read.table("pbmcSmall", header = TRUE, row.names = 1, check.names = FALSE))
      })
    } else {
      stop("Required input file 'pbmcSmall' (RDS, CSV, or TSV format) not found in the working directory.")
    }
    
    # Ensure the input is a matrix or sparse matrix
    if (!inherits(pbmcSmall, c("matrix", "dgCMatrix"))) {
      pbmcSmall <- as.matrix(pbmcSmall)
    }
    
    # -----------------------------------------------------------------------------
    # Stage 2: Clean UMI Data (Filter out genes with low non-zero expression)
    # -----------------------------------------------------------------------------
    pbmcSmall <- pbmcSmall[rowSums(pbmcSmall != 0) >= 20, ]
    
    # -----------------------------------------------------------------------------
    # Stage 3: Normalize UMI Count Matrix using Dino
    # -----------------------------------------------------------------------------
    pbmcSmall_Norm <- Dino(pbmcSmall)
    
    # Save the normalized matrix
    saveRDS(pbmcSmall_Norm, file = "pbmcSmall_Norm.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 4: Convert to Seurat and Run Downstream Clustering & Visualization
    # -----------------------------------------------------------------------------
    pbmcSmall_Seurat <- SeuratFromDino(pbmcSmall_Norm, doNorm = FALSE)
    
    pbmcSmall_Seurat <- FindVariableFeatures(pbmcSmall_Seurat, 
                            selection.method = "mvp")
    
    pbmcSmall_Seurat <- ScaleData(pbmcSmall_Seurat, 
                            features = rownames(pbmcSmall_Norm))
    
    pbmcSmall_Seurat <- RunPCA(pbmcSmall_Seurat, 
                            features = VariableFeatures(object = pbmcSmall_Seurat),
                            verbose = FALSE)
    
    pbmcSmall_Seurat <- FindNeighbors(pbmcSmall_Seurat, dims = 1:10)
    
    pbmcSmall_Seurat <- FindClusters(pbmcSmall_Seurat, verbose = FALSE)
    
    pbmcSmall_Seurat <- RunUMAP(pbmcSmall_Seurat, dims = 1:10)
    
    # Save the final Seurat object
    saveRDS(pbmcSmall_Seurat, file = "pbmcSmall_Seurat.rds")
    
    # Generate and save the UMAP plot
    pdf("umap_plot.pdf", width = 7, height = 6)
    print(DimPlot(pbmcSmall_Seurat, reduction = "umap"))
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved: 'pbmcSmall_Norm.rds', 'pbmcSmall_Seurat.rds', and 'umap_plot.pdf'.\n")

    writeLines(c(
        '"BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT":',
        paste0('    Dino: ', as.character(packageVersion('Dino')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_matrix_normalization_and_seurat.csv versions.yml
    """
}

workflow BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmcSmall ] ]

    main:
    BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT(ch_input)

    emit:
    tables   = BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT.out.tables
    plots    = BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT.out.plots
    objects  = BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT.out.objects
    versions = BIOC_DINO_STANDARD_MATRIX_NORMALIZATION_AND_SEURAT.out.versions
}
