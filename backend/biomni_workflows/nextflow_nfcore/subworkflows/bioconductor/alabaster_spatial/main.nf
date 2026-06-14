#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alabaster_spatial — alabaster_spatial_serialization_pipeline
// Read spatial transcriptomics count and metadata, construct a SpatialExperiment object, serialize and deserialize it using the alabaster framework, and perform s
// Input: counts.csv, coldata.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, SummarizedExperiment, alabaster.base, alabaster.spatial, alabaster_spatial
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_SPATIAL_ALABASTER_SPATIAL_SERIALIZATION_PIPELINE {
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
    .bm_deps <- c("SpatialExperiment", "alabaster.base", "alabaster.spatial", "SummarizedExperiment")
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
    lib    library(SummarizedExperiment)
rary(SpatialExperiment)
    library(alabaster.base)
    library(alabaster.spatial)
    
    # ==========================================
    # --- Read Input Data & Preprocess ---
    # ==========================================
    
    # Read counts matrix
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_df\$gene_id <- NULL
    } else {
        rownames(counts_df) <- counts_df[, 1]
        counts_df <- counts_df[, -1, drop = FALSE]
    }
    
    # Read coldata (sample metadata)
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    if ("sample" %in% colnames(coldata_df)) {
        rownames(coldata_df) <- coldata_df\$sample
    } else {
        rownames(coldata_df) <- coldata_df[, 1]
    }
    
    # Align counts and coldata
    common_samples <- intersect(colnames(counts_df), rownames(coldata_df))
    if (length(common_samples) == 0) {
        stop("No matching samples found between counts.csv and coldata.csv")
    }
    counts_mat <- as.matrix(counts_df[, common_samples, drop = FALSE])
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # ==========================================
    # --- Construct SpatialExperiment ---
    # ==========================================
    
    # Extract or generate spatial coordinates
    spatial_cols <- intersect(c("x", "y", "pxl_col_in_fullres", "pxl_row_in_fullres"), colnames(coldata_df))
    if (length(spatial_cols) >= 2) {
        spatial_coords <- as.matrix(coldata_df[, spatial_cols[1:2]])
    } else {
        # Generate dummy grid coordinates if spatial coordinates are not provided
        n <- ncol(counts_mat)
        side <- ceiling(sqrt(n))
        grid <- expand.grid(x = 1:side, y = 1:side)[1:n, ]
        spatial_coords <- as.matrix(grid)
        colnames(spatial_coords) <- c("x", "y")
    }
    rownames(spatial_coords) <- colnames(counts_mat)
    
    # Build the SpatialExperiment object
    se <- SpatialExperiment::SpatialExperiment(
        assays = list(counts = counts_mat),
        colData = coldata_df,
        spatialCoords = spatial_coords
    )
    
    # ==========================================
    # --- Serialize using alabaster.spatial ---
    # ==========================================
    
    # Define output directory for the serialized object
    save_dir <- "serialized_spatial_experiment"
    if (dir.exists(save_dir)) {
        unlink(save_dir, recursive = TRUE)
    }
    
    # Save the SpatialExperiment object to disk
    message("Saving SpatialExperiment object using alabaster...")
    alabaster.base::saveObject(se, save_dir)
    
    # ==========================================
    # --- Deserialize (Load) the Object ---
    # ==========================================
    
    # Read the object back to verify round-trip integrity
    message("Loading SpatialExperiment object back using alabaster...")
    se_loaded <- alabaster.base::readObject(save_dir)
    
    # ==========================================
    # --- Downstream Analysis & QC ---
    # ==========================================
    
    # Calculate basic QC metrics
    total_counts <- colSums(SummarizedExperiment::assay(se_loaded, "counts"))
    detected_genes <- colSums(SummarizedExperiment::assay(se_loaded, "counts") > 0)
    
    # Append metrics to loaded object metadata
    SummarizedExperiment::colData(se_loaded)\$total_counts <- total_counts
    SummarizedExperiment::colData(se_loaded)\$detected_genes <- detected_genes
    
    # Export QC metrics table
    qc_output <- data.frame(
        sample = rownames(SummarizedExperiment::colData(se_loaded)),
        total_counts = total_counts,
        detected_genes = detected_genes,
        spatial_x = SpatialExperiment::spatialCoords(se_loaded)[, 1],
        spatial_y = SpatialExperiment::spatialCoords(se_loaded)[, 2],
        condition = if ("condition" %in% colnames(SummarizedExperiment::colData(se_loaded))) {
            SummarizedExperiment::colData(se_loaded)\$condition
        } else {
            NA
        }
    )
    write.csv(qc_output, "spatial_qc_metrics.csv", row.names = FALSE)
    
    # Generate spatial visualization plot
    pdf("spatial_qc_plot.pdf", width = 7, height = 6)
    plot(
        SpatialExperiment::spatialCoords(se_loaded),
        col = rainbow(100)[cut(total_counts, 100)],
        pch = 19,
        cex = 1.5,
        main = "Spatial Spots Colored by Total Counts",
        xlab = "Spatial X Coordinate",
        ylab = "Spatial Y Coordinate"
    )
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ALABASTER_SPATIAL_ALABASTER_SPATIAL_SERIALIZATION_PIPELINE":',
        paste0('    alabaster_spatial: ', as.character(packageVersion('alabaster_spatial')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_spatial_serialization_pipeline.csv versions.yml
    """
}

workflow BIOC_ALABASTER_SPATIAL_ALABASTER_SPATIAL_SERIALIZATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ALABASTER_SPATIAL_ALABASTER_SPATIAL_SERIALIZATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_ALABASTER_SPATIAL_ALABASTER_SPATIAL_SERIALIZATION_PIPELINE.out.tables
    plots    = BIOC_ALABASTER_SPATIAL_ALABASTER_SPATIAL_SERIALIZATION_PIPELINE.out.plots
    objects  = BIOC_ALABASTER_SPATIAL_ALABASTER_SPATIAL_SERIALIZATION_PIPELINE.out.objects
    versions = BIOC_ALABASTER_SPATIAL_ALABASTER_SPATIAL_SERIALIZATION_PIPELINE.out.versions
}
