#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pRolocGUI — proloc_spatial_explorer
// Prepare spatial proteomics MSnSet data from intensity and coldata CSVs and launch the interactive pRolocVis explorer.
// Input: intensity.csv, coldata.csv
// Container: 2.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MSnbase, pRolocGUI
// Visualizations: PCA plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROLOCGUI_PROLOC_SPATIAL_EXPLORER {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    
    # Stage 1: Load required libraries
    library(MSnbase)
    library(pRolocGUI)
    
    # Stage 2: Read and align input files
    intensity <- read.csv("intensity.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align sample names between intensity matrix and coldata
    if ("sample" %in% colnames(coldata)) {
      rownames(coldata) <- coldata\$sample
    }
    common_samples <- intersect(colnames(intensity), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No matching samples found between intensity.csv and coldata.csv")
    }
    
    intensity <- intensity[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Stage 3: Construct MSnSet object
    exprs_mat <- as.matrix(intensity)
    
    # Create feature metadata with a default 'markers' column required by pRolocVis
    fd <- data.frame(
      feature_id = rownames(exprs_mat),
      markers = rep("unknown", nrow(exprs_mat)),
      row.names = rownames(exprs_mat),
      stringsAsFactors = FALSE
    )
    
    # Construct S4 AnnotatedDataFrames
    pd_annotated <- new("AnnotatedDataFrame", data = coldata)
    fd_annotated <- new("AnnotatedDataFrame", data = fd)
    
    # Create the MSnSet container
    msnset <- new("MSnSet", exprs = exprs_mat, featureData = fd_annotated, phenoData = pd_annotated)
    
    # Stage 4: Normalize profiles (standard sum normalization for spatial proteomics)
    row_sums <- rowSums(exprs(msnset), na.rm = TRUE)
    row_sums[row_sums == 0] <- 1
    exprs(msnset) <- exprs(msnset) / row_sums
    
    # Save the processed MSnSet object
    saveRDS(msnset, "processed_msnset.rds")
    
    # Stage 5: Generate static PCA preview
    pdf("pca_preview.pdf", width = 7, height = 7)
    row_vars <- apply(exprs(msnset), 1, var, na.rm = TRUE)
    valid_rows <- !is.na(row_vars) & row_vars > 0
    
    if (sum(valid_rows) > 1) {
      pca_proteins <- prcomp(exprs(msnset)[valid_rows, ], scale. = TRUE)
      plot(pca_proteins\$x[, 1], pca_proteins\$x[, 2], 
           col = "darkgray",
           pch = 19, xlab = "PC1", ylab = "PC2",
           main = "Spatial Proteomics PCA Preview")
    } else {
      plot(1, 1, type = "n", main = "PCA Preview (Insufficient variance)")
      text(1, 1, "Not enough variable features for PCA")
    }
    dev.off()
    
    # Stage 6: Write launcher script for interactive visualization
    writeLines(c(
      "library(pRolocGUI)",
      "msnset <- readRDS('processed_msnset.rds')",
      "pRolocVis(msnset, app = 'explore', fcol = 'markers')"
    ), "launch_explore.R")
    
    # Launch the interactive application if in an interactive session
    if (interactive()) {
      pRolocVis(msnset, app = "explore", fcol = "markers")
    }

    writeLines(c(
        '"BIOC_PROLOCGUI_PROLOC_SPATIAL_EXPLORER":',
        paste0('    pRolocGUI: ', as.character(packageVersion('pRolocGUI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proloc_spatial_explorer.csv versions.yml
    """
}

workflow BIOC_PROLOCGUI_PROLOC_SPATIAL_EXPLORER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PROLOCGUI_PROLOC_SPATIAL_EXPLORER(ch_input)

    emit:
    tables   = BIOC_PROLOCGUI_PROLOC_SPATIAL_EXPLORER.out.tables
    plots    = BIOC_PROLOCGUI_PROLOC_SPATIAL_EXPLORER.out.plots
    objects  = BIOC_PROLOCGUI_PROLOC_SPATIAL_EXPLORER.out.objects
    versions = BIOC_PROLOCGUI_PROLOC_SPATIAL_EXPLORER.out.versions
}
