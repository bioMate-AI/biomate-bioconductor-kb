#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: moleculeexperiment — build_from_custom_data_frames
// Construct a MoleculeExperiment object from custom R data frames containing molecule coordinates and segmentation boundaries.
// Input: moleculesDf, boundariesDf
// Container: quay.io/biocontainers/bioconductor-moleculeexperiment:1.10.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOLECULEEXPERIMENT_BUILD_FROM_CUSTOM_DATA_FRAMES {
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
    .bm_deps <- c("MoleculeExperiment", "ggplot2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(MoleculeExperiment)
    library(ggplot2)
    
    # Read input files from the working directory
    if (file.exists("moleculesDf.csv")) {
      moleculesDf <- read.csv("moleculesDf.csv", stringsAsFactors = FALSE)
    } else if (file.exists("moleculesDf.rds")) {
      moleculesDf <- readRDS("moleculesDf.rds")
    } else {
      stop("Required input file 'moleculesDf.csv' or 'moleculesDf.rds' not found in the working directory.")
    }
    
    if (file.exists("boundariesDf.csv")) {
      boundariesDf <- read.csv("boundariesDf.csv", stringsAsFactors = FALSE)
    } else if (file.exists("boundariesDf.rds")) {
      boundariesDf <- readRDS("boundariesDf.rds")
    } else {
      stop("Required input file 'boundariesDf.csv' or 'boundariesDf.rds' not found in the working directory.")
    }
    
    # Convert the molecules data frame to a standardized MoleculeExperiment list
    moleculesMEList <- dataframeToMEList(moleculesDf,
      dfType = "molecules",
      assayName = "detected",
      sampleCol = "sample_id",
      factorCol = "features",
      xCol = "x_coords",
      yCol = "y_coords"
    )
    
    # Convert the boundaries data frame to a standardized MoleculeExperiment list
    boundariesMEList <- dataframeToMEList(boundariesDf,
      dfType = "boundaries",
      assayName = "cell",
      sampleCol = "sample_id",
      factorCol = "cell_id",
      xCol = "vertex_x",
      yCol = "vertex_y"
    )
    
    # Construct the final MoleculeExperiment object using the class constructor
    toyME <- MoleculeExperiment(
      molecules = moleculesMEList,
      boundaries = boundariesMEList
    )
    
    # Save the constructed MoleculeExperiment object to an RDS file
    saveRDS(toyME, file = "toyME.rds")
    
    # Save a text summary of the constructed object
    sink("toyME_summary.txt")
    cat("--- MoleculeExperiment Object Summary ---\n")
    print(toyME)
    sink()
    
    # Generate and save a diagnostic plot of the molecules and boundaries
    tryCatch({
      pdf("toyME_plot.pdf", width = 8, height = 8)
      p <- ggplot_me() +
        geom_polygon_me(toyME, assayName = "cell", fill = "grey80", colour = "black", alpha = 0.5) +
        geom_point_me(toyME, assayName = "detected", byColour = "feature_id", size = 1.5) +
        theme_classic() +
        ggtitle("MoleculeExperiment: Custom Data Frames Workflow")
      print(p)
      dev.off()
    }, error = function(e) {
      message("Could not generate PDF plot: ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MOLECULEEXPERIMENT_BUILD_FROM_CUSTOM_DATA_FRAMES":
        moleculeexperiment: \$(Rscript -e 'cat(as.character(packageVersion("moleculeexperiment")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_build_from_custom_data_frames.csv versions.yml
    """
}

workflow BIOC_MOLECULEEXPERIMENT_BUILD_FROM_CUSTOM_DATA_FRAMES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ moleculesDf, boundariesDf ] ]

    main:
    BIOC_MOLECULEEXPERIMENT_BUILD_FROM_CUSTOM_DATA_FRAMES(ch_input)

    emit:
    tables   = BIOC_MOLECULEEXPERIMENT_BUILD_FROM_CUSTOM_DATA_FRAMES.out.tables
    plots    = BIOC_MOLECULEEXPERIMENT_BUILD_FROM_CUSTOM_DATA_FRAMES.out.plots
    objects  = BIOC_MOLECULEEXPERIMENT_BUILD_FROM_CUSTOM_DATA_FRAMES.out.objects
    versions = BIOC_MOLECULEEXPERIMENT_BUILD_FROM_CUSTOM_DATA_FRAMES.out.versions
}
