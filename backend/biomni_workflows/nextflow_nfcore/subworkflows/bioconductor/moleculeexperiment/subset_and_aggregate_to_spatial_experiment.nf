#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: moleculeexperiment — subset_and_aggregate_to_spatial_experiment
// Subset a MoleculeExperiment object by spatial coordinates and aggregate molecule counts within boundaries to create a cell-level SpatialExperiment object.
// Input: meMerscope, me
// Container: quay.io/biocontainers/bioconductor-moleculeexperiment:1.10.0--r45hdfd78af_0
// R packages: MoleculeExperiment, SpatialExperiment, ggplot2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_MOLECULEEXPERIMENT_SUBSET_AND_AGGREGATE_TO_SPATIAL_EXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-moleculeexperiment:1.10.0--r45hdfd78af_0"

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
    .bm_deps <- c("MoleculeExperiment", "SpatialExperiment", "ggplot2", "SummarizedExperiment")
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
    libr    library(SummarizedExperiment)
ary(MoleculeExperiment)
    library(SpatialExperiment)
    library(ggplot2)
    
    # --- Read user input files from the working directory ---
    meMerscope_file <- if (file.exists("meMerscope.rds")) "meMerscope.rds" else "meMerscope"
    me_file <- if (file.exists("me.rds")) "me.rds" else "me"
    
    if (!file.exists(meMerscope_file)) {
      stop("Required input file 'meMerscope' or 'meMerscope.rds' not found in the working directory.")
    }
    if (!file.exists(me_file)) {
      stop("Required input file 'me' or 'me.rds' not found in the working directory.")
    }
    
    meMerscope <- readRDS(meMerscope_file)
    me <- readRDS(me_file)
    
    # --- Define the spatial coordinates for subsetting ---
    new_extent = extent(meMerscope, "detected") - c(0, 100, 0, 0)
    
    # --- Subset the MoleculeExperiment object using ---
    me_sub = subset_by_extent(meMerscope, new_extent)
    
    # --- Aggregate the molecule-level transcripts into cell-level ---
    spe <- countMolecules(me, boundariesAssay = "nucleus")
    
    # --- Save meaningful results ---
    # Save the subsetted MoleculeExperiment object
    saveRDS(me_sub, "me_subset.rds")
    
    # Save the aggregated SpatialExperiment object
    saveRDS(spe, "spe_aggregated.rds")
    
    # Export count matrix to CSV
    if (requireNamespace("SummarizedExperiment", quietly = TRUE)) {
      counts_matrix <- SummarizedExperiment::assay(spe, "counts")
      write.csv(as.matrix(counts_matrix), "cell_counts_matrix.csv", row.names = TRUE)
    }
    
    # Export spatial coordinates to CSV
    if (requireNamespace("SpatialExperiment", quietly = TRUE)) {
      spatial_coords <- SpatialExperiment::spatialCoords(spe)
      write.csv(as.data.frame(spatial_coords), "spatial_coordinates.csv", row.names = TRUE)
    }
    
    # Generate a PDF plot of the subsetted MoleculeExperiment
    tryCatch({
      pdf("me_subset_plot.pdf", width = 7, height = 7)
      p <- ggplot_me() +
        geom_polygon_me(me_sub, assayName = "cell", fill = "grey", alpha = 0.5) +
        geom_point_me(me_sub, assayName = "detected", size = 0.5) +
        ggtitle("Subsetted MoleculeExperiment") +
        theme_minimal()
      print(p)
      dev.off()
    }, error = function(e) {
      warning("Could not generate PDF plot: ", e\$message)
    })
    
    cat("Pipeline completed successfully. Outputs saved: me_subset.rds, spe_aggregated.rds, cell_counts_matrix.csv, spatial_coordinates.csv, me_subset_plot.pdf\n")

    writeLines(c(
        '"BIOC_MOLECULEEXPERIMENT_SUBSET_AND_AGGREGATE_TO_SPATIAL_EXPERIMENT":',
        paste0('        moleculeexperiment: ', as.character(packageVersion("moleculeexperiment")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subset_and_aggregate_to_spatial_experiment.csv versions.yml
    """
}

workflow BIOC_MOLECULEEXPERIMENT_SUBSET_AND_AGGREGATE_TO_SPATIAL_EXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ meMerscope, me ] ]

    main:
    BIOC_MOLECULEEXPERIMENT_SUBSET_AND_AGGREGATE_TO_SPATIAL_EXPERIMENT(ch_input)

    emit:
    tables   = BIOC_MOLECULEEXPERIMENT_SUBSET_AND_AGGREGATE_TO_SPATIAL_EXPERIMENT.out.tables
    plots    = BIOC_MOLECULEEXPERIMENT_SUBSET_AND_AGGREGATE_TO_SPATIAL_EXPERIMENT.out.plots
    objects  = BIOC_MOLECULEEXPERIMENT_SUBSET_AND_AGGREGATE_TO_SPATIAL_EXPERIMENT.out.objects
    versions = BIOC_MOLECULEEXPERIMENT_SUBSET_AND_AGGREGATE_TO_SPATIAL_EXPERIMENT.out.versions
}
