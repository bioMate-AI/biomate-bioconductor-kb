#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpaNorm — spanorm_seurat_workflow
// Normalise spatial transcriptomics data stored in a Seurat object.
// Input: Seurat object containing raw counts and spatial coordinates in metadata.
// Container: quay.io/biocontainers/bioconductor-spanorm:1.4.0--r45hdfd78af_0
// R packages: Seurat, SpaNorm, SpatialExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, SpaNorm, SpatialExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Add spatial coordinates to Seurat metadata; 2. Run SpaNorm on the Seurat object

nextflow.enable.dsl = 2

process BIOC_SPANORM_SPANORM_SEURAT_WORKFLOW {
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
    .bm_deps <- c("Seurat", "SpaNorm", "SpatialExperiment")
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
    library(Seurat)
    library(SpatialExperiment)
    library(SpaNorm)
    
    # 1. Read the user input Seurat object from the working directory
    # The pipeline expects 'seurat_input.rds' in the working directory
    input_file <- "seurat_input.rds"
    if (!file.exists(input_file)) {
      stop(paste("Input file", input_file, "not found in the working directory."))
    }
    
    seurat_in <- readRDS(input_file)
    
    # Extract counts and spatial coordinates
    counts_matrix <- Seurat::GetAssayData(seurat_in, slot = "counts")
    meta <- seurat_in@meta.data
    
    # Identify spatial coordinate columns in metadata
    x_col <- grep("^x\$|^imagecol\$|^pxl_col", colnames(meta), ignore.case = TRUE, value = TRUE)
    y_col <- grep("^y\$|^imagerow\$|^pxl_row", colnames(meta), ignore.case = TRUE, value = TRUE)
    
    if (length(x_col) > 0 && length(y_col) > 0) {
      coords_matrix <- as.matrix(meta[, c(x_col[1], y_col[1])])
    } else {
      # Fallback to first two numeric columns if not explicitly named
      numeric_cols <- sapply(meta, is.numeric)
      if (sum(numeric_cols) >= 2) {
        coords_matrix <- as.matrix(meta[, which(numeric_cols)[1:2]])
      } else {
        # Default dummy coordinates if none found
        coords_matrix <- matrix(0, nrow = ncol(counts_matrix), ncol = 2)
      }
    }
    colnames(coords_matrix) <- c("x", "y")
    
    # === DOCUMENTED CODE ===
    seurat_obj <- seurat_in
    seurat_obj@meta.data\$x <- coords_matrix[, "x"]
    seurat_obj@meta.data\$y <- coords_matrix[, "y"]
    seurat_obj <- SpaNorm(seurat_obj, sample.p = 0.1, df.tps = 2, backend = "cpu", verbose = TRUE)
    # === END DOCUMENTED CODE ===
    
    # Save the normalized Seurat object
    saveRDS(seurat_obj, "seurat_norm_output.rds")
    
    # Save the normalized counts as a CSV file
    norm_data <- Seurat::GetAssayData(seurat_obj, slot = "data")
    write.csv(as.matrix(norm_data), "normalized_counts.csv", row.names = TRUE)
    
    # Generate a diagnostic plot of spatial coordinates
    pdf("spatial_coordinates_plot.pdf", width = 8, height = 6)
    plot(seurat_obj@meta.data\$x, seurat_obj@meta.data\$y, 
         col = "blue", pch = 19, cex = 0.6,
         xlab = "X Coordinate", ylab = "Y Coordinate", 
         main = "Spatial Coordinates of Normalized Spots")
    dev.off()

    writeLines(c(
        '"BIOC_SPANORM_SPANORM_SEURAT_WORKFLOW":',
        paste0('    SpaNorm: ', as.character(packageVersion('SpaNorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spanorm_seurat_workflow.csv versions.yml
    """
}

workflow BIOC_SPANORM_SPANORM_SEURAT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Seurat object containing raw counts and spatial coordinates in metadata. ] ]

    main:
    BIOC_SPANORM_SPANORM_SEURAT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SPANORM_SPANORM_SEURAT_WORKFLOW.out.tables
    plots    = BIOC_SPANORM_SPANORM_SEURAT_WORKFLOW.out.plots
    objects  = BIOC_SPANORM_SPANORM_SEURAT_WORKFLOW.out.objects
    versions = BIOC_SPANORM_SPANORM_SEURAT_WORKFLOW.out.versions
}
