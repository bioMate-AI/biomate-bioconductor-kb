#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MoleculeExperiment — vendor_import_subset_and_visualize
// Import raw spatial transcriptomics data from vendor-specific directories, subset the data by spatial coordinates, and visualize the molecules and boundaries.
// Input: raw_data_dir
// Container: quay.io/biocontainers/bioconductor-moleculeexperiment:1.10.0--r45hdfd78af_0
// R packages: MoleculeExperiment, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: MoleculeExperiment, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import raw spatial transcriptomics data
//  * 2. [Visualization & Output] Define a spatial extent and subset the MoleculeExperiment
//  * 3. [Visualization & Output] Visualize the molecules and boundaries using specialized

nextflow.enable.dsl = 2

process BIOC_MOLECULEEXPERIMENT_VENDOR_IMPORT_SUBSET_AND_VISUALIZE {
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
    .bm_deps <- c("MoleculeExperiment", "ggplot2")
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
        library(MoleculeExperiment)
        library(ggplot2)
        
        # Define input directory
        repoDir <- "raw_data_dir"
        
        # Check if input directory exists
        if (!dir.exists(repoDir)) {
          stop("Error: 'raw_data_dir' directory does not exist in the current working directory.")
        }
        
        # Detect vendor type
        files <- list.files(repoDir, recursive = TRUE)
        is_merscope <- any(grepl("detected_transcripts", files)) || any(grepl("merfish", files, ignore.case = TRUE))
        is_cosmx <- any(grepl("tx_file", files)) || any(grepl("cosmx", files, ignore.case = TRUE))
        
        # --- Import raw spatial transcriptomics data ---
        if (is_merscope) {
          message("Detected MERSCOPE data. Reading with readMerscope.")
          me <- readMerscope(repoDir, keepCols = "essential", addBoundaries = "cell")
        } else if (is_cosmx) {
          message("Detected CosMx data. Reading with readCosmx.")
          me <- readCosmx(repoDir, keepCols = "essential", addBoundaries = "cell")
        } else {
          message("Assuming Xenium data. Reading with readXenium.")
          me <- readXenium(repoDir, keepCols = "essential", addBoundaries = "cell")
        }
        
        # Alias meMerscope to me to support the documented subsetting code
        meMerscope <- me
        
        # --- Define a spatial extent and subset the MoleculeExperiment ---
        new_extent = extent(meMerscope, "detected") - c(0, 100, 0, 0)
        
        me_sub = subset_by_extent(meMerscope, new_extent)
        
        # Save the subsetted object
        saveRDS(me_sub, file = "me_subsetted.rds")
        
        # Export subsetted molecules as a CSV table
        tryCatch({
          df_molecules <- molecules(me_sub, assayName = "detected", flatten = TRUE)
          write.csv(df_molecules, file = "subsetted_molecules.csv", row.names = FALSE)
          message("Saved subsetted molecules to 'subsetted_molecules.csv'.")
        }, error = function(e) {
          message("Could not export molecules to CSV: ", e\$message)
        })
        
        # --- Visualize the molecules and boundaries using specialized ---
        # Documented visualization with dynamic zoom
        p_zoom <- ggplot_me() +
          geom_polygon_me(me, assayName = "cell", fill = "grey") +
          geom_point_me(me) +
          # zoom in to selected patch area
          coord_cartesian(
            xlim = c(new_extent["xmin"], new_extent["xmax"]),
            ylim = c(new_extent["ymin"], new_extent["ymax"])
          )
        
        ggsave("visualize_zoom.pdf", plot = p_zoom, width = 8, height = 8)
        
        # Robust visualization: zoom to actual extent of the subsetted data
        tryCatch({
          ext_sub <- extent(me_sub, "detected")
          p_sub <- ggplot_me() +
            geom_polygon_me(me_sub, assayName = "cell", fill = "grey") +
            geom_point_me(me_sub) +
            coord_cartesian(
              xlim = c(ext_sub["xmin"], ext_sub["xmax"]),
              ylim = c(ext_sub["ymin"], ext_sub["ymax"])
            ) +
            ggtitle("Subsetted MoleculeExperiment (Dynamic Zoom)")
          
          ggsave("visualize_subset.pdf", plot = p_sub, width = 8, height = 8)
          message("Saved robust subset visualization to 'visualize_subset.pdf'.")
        }, error = function(e) {
          message("Could not generate robust subset visualization: ", e\$message)
        })
        
        # Robust visualization: zoom to actual extent of the full data
        tryCatch({
          ext_full <- extent(me, "detected")
          p_full <- ggplot_me() +
            geom_polygon_me(me, assayName = "cell", fill = "grey") +
            geom_point_me(me) +
            coord_cartesian(
              xlim = c(ext_full["xmin"], ext_full["xmax"]),
              ylim = c(ext_full["ymin"], ext_full["ymax"])
            ) +
            ggtitle("Full MoleculeExperiment (Dynamic Zoom)")
          
          ggsave("visualize_full.pdf", plot = p_full, width = 8, height = 8)
          message("Saved robust full visualization to 'visualize_full.pdf'.")
        }, error = function(e) {
          message("Could not generate robust full visualization: ", e\$message)
        })
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MOLECULEEXPERIMENT_VENDOR_IMPORT_SUBSET_AND_VISUALIZE":',
        paste0('    MoleculeExperiment: ', as.character(packageVersion('MoleculeExperiment')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vendor_import_subset_and_visualize.csv versions.yml
    """
}

workflow BIOC_MOLECULEEXPERIMENT_VENDOR_IMPORT_SUBSET_AND_VISUALIZE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_data_dir ] ]

    main:
    BIOC_MOLECULEEXPERIMENT_VENDOR_IMPORT_SUBSET_AND_VISUALIZE(ch_input)

    emit:
    tables   = BIOC_MOLECULEEXPERIMENT_VENDOR_IMPORT_SUBSET_AND_VISUALIZE.out.tables
    plots    = BIOC_MOLECULEEXPERIMENT_VENDOR_IMPORT_SUBSET_AND_VISUALIZE.out.plots
    objects  = BIOC_MOLECULEEXPERIMENT_VENDOR_IMPORT_SUBSET_AND_VISUALIZE.out.objects
    versions = BIOC_MOLECULEEXPERIMENT_VENDOR_IMPORT_SUBSET_AND_VISUALIZE.out.versions
}
