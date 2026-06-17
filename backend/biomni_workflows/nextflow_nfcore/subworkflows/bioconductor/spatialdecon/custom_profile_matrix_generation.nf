#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpatialDecon — custom_profile_matrix_generation
// Create a custom cell profile matrix from single-cell RNA-seq count matrices or Seurat objects.
// Input: mini_singleCell_dataset$mtx, mini_singleCell_dataset$annots, seuratObject
// Container: quay.io/biocontainers/bioconductor-spatialdecon:1.20.0--r45hdfd78af_0
// R packages: Seurat, SeuratObject, SpatialDecon
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, SeuratObject, SpatialDecon
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load single-cell dataset or create a Seurat object
//  * 2. [Core Analysis] Generate custom profile matrix from raw counts and annotations using create_profile_matrix
//  * 3. [Core Analysis] Alternatively, extract counts and annotations from a Seurat object and generate the profile matrix using create_profile_matrix

nextflow.enable.dsl = 2

process BIOC_SPATIALDECON_CUSTOM_PROFILE_MATRIX_GENERATION {
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
    .bm_deps <- c("Seurat", "SeuratObject", "SpatialDecon")
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
    library(SpatialDecon)
    library(SeuratObject)
    library(Seurat)
    
    # 1. Load single-cell dataset and Seurat object from user input files
    if (file.exists("mini_singleCell_dataset.rds")) {
      mini_singleCell_dataset <- readRDS("mini_singleCell_dataset.rds")
    } else {
      mini_singleCell_dataset <- list()
      if (file.exists("mini_singleCell_dataset_mtx.rds")) {
        mini_singleCell_dataset\$mtx <- readRDS("mini_singleCell_dataset_mtx.rds")
      }
      if (file.exists("mini_singleCell_dataset_annots.rds")) {
        mini_singleCell_dataset\$annots <- readRDS("mini_singleCell_dataset_annots.rds")
      }
    }
    
    seuratObject <- readRDS("seuratObject.rds")
    
    # 2. Generate custom profile matrix from raw counts and annotations using create_profile_matrix
    custom_mtx <- create_profile_matrix(mtx = mini_singleCell_dataset\$mtx,
                                        cellAnnots = mini_singleCell_dataset\$annots,
                                        cellTypeCol = "LabeledCellType",
                                        cellNameCol = "CellID",
                                        matrixName = "custom_mini_colon",
                                        outDir = NULL,
                                        normalize = FALSE,
                                        minCellNum = 5,
                                        minGenes = 10,
                                        scalingFactor = 5,
                                        discardCellTypes = TRUE)
    
    # 3. Alternatively, extract counts and annotations from a Seurat object and generate the profile matrix
    # Ensure Idents are set up as expected
    Idents(seuratObject) <- seuratObject\$LabeledCellType
    
    annots <- data.frame(cbind(cellType=as.character(Idents(seuratObject)), 
                               cellID=names(Idents(seuratObject))))
    
    custom_mtx_seurat <- create_profile_matrix(mtx = Seurat::GetAssayData(object = seuratObject, 
                                                                          assay = "RNA", 
                                                                          layer = "counts"), 
                                               cellAnnots = annots, 
                                               cellTypeCol = "cellType", 
                                               cellNameCol = "cellID", 
                                               matrixName = "custom_mini_colon",
                                               outDir = NULL, 
                                               normalize = FALSE, 
                                               minCellNum = 5, 
                                               minGenes = 10)
    
    # Save outputs to the working directory
    saveRDS(custom_mtx, "custom_profile_matrix.rds")
    write.csv(as.matrix(custom_mtx), "custom_profile_matrix.csv", row.names = TRUE)
    
    saveRDS(custom_mtx_seurat, "custom_profile_matrix_seurat.rds")
    write.csv(as.matrix(custom_mtx_seurat), "custom_profile_matrix_seurat.csv", row.names = TRUE)
    
    # Generate and save heatmap plot of the custom profile matrix
    pdf("custom_profile_matrix_heatmap.pdf", width = 8, height = 8)
    heatmap(sweep(custom_mtx, 1, apply(custom_mtx, 1, max), "/"), labRow = NA, margins = c(10, 5), cexCol = 0.7)
    dev.off()

    writeLines(c(
        '"BIOC_SPATIALDECON_CUSTOM_PROFILE_MATRIX_GENERATION":',
        paste0('    SpatialDecon: ', as.character(packageVersion('SpatialDecon')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_profile_matrix_generation.csv versions.yml
    """
}

workflow BIOC_SPATIALDECON_CUSTOM_PROFILE_MATRIX_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mini_singleCell_dataset$mtx, mini_singleCell_dataset$annots, seuratObject ] ]

    main:
    BIOC_SPATIALDECON_CUSTOM_PROFILE_MATRIX_GENERATION(ch_input)

    emit:
    tables   = BIOC_SPATIALDECON_CUSTOM_PROFILE_MATRIX_GENERATION.out.tables
    plots    = BIOC_SPATIALDECON_CUSTOM_PROFILE_MATRIX_GENERATION.out.plots
    objects  = BIOC_SPATIALDECON_CUSTOM_PROFILE_MATRIX_GENERATION.out.objects
    versions = BIOC_SPATIALDECON_CUSTOM_PROFILE_MATRIX_GENERATION.out.versions
}
