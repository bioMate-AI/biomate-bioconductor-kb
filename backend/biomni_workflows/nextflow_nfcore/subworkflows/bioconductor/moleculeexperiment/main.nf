#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: moleculeexperiment — import_from_vendor_directories
// Import raw spatial transcriptomics outputs from instrument directories directly into a standardized MoleculeExperiment object.
// Input: repoDir
// Container: quay.io/biocontainers/bioconductor-moleculeexperiment:1.10.0--r45hdfd78af_0
// R packages: BiocStyle, ggplot2, MoleculeExperiment
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOLECULEEXPERIMENT_IMPORT_FROM_VENDOR_DIRECTORIES {
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
    .bm_deps <- c("BiocStyle", "ggplot2", "MoleculeExperiment")
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
    
    # 1. Identify the path to the vendor output directory
    # The pipeline reads the user input directory 'repoDir' from the working directory
    repoDir <- "repoDir"
    
    if (!dir.exists(repoDir)) {
      stop(paste("Input directory 'repoDir' does not exist at:", repoDir))
    }
    
    # 2. Read the data into a MoleculeExperiment object using the platform-specific reader function
    # Keeping the documented function call and argument names exactly as specified
    me <- readXenium(repoDir, keepCols = "essential", addBoundaries = "cell")
    
    # Print the constructed MoleculeExperiment object to console
    print(me)
    
    # 3. Write named output files for the meaningful results
    
    # Save the MoleculeExperiment object as an RDS file
    saveRDS(me, file = "molecule_experiment.rds")
    
    # Extract and save flattened molecules data frame
    tryCatch({
      mols_flat <- molecules(me, assayName = "detected", flatten = TRUE)
      write.csv(mols_flat, file = "molecules_flattened.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not extract or save flattened molecules: ", e\$message)
    })
    
    # Extract and save flattened boundaries data frame
    tryCatch({
      bds_flat <- boundaries(me, assayName = "cell", flatten = TRUE)
      write.csv(bds_flat, file = "boundaries_flattened.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not extract or save flattened boundaries: ", e\$message)
    })
    
    # Generate and save a spatial visualization plot
    tryCatch({
      pdf("spatial_molecules_plot.pdf", width = 8, height = 8)
      p <- ggplot_me() +
        geom_polygon_me(me, assayName = "cell", fill = "grey") +
        geom_point_me(me) +
        theme_classic()
      print(p)
      dev.off()
    }, error = function(e) {
      warning("Could not generate or save spatial plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_MOLECULEEXPERIMENT_IMPORT_FROM_VENDOR_DIRECTORIES":',
        paste0('        moleculeexperiment: ', as.character(packageVersion("moleculeexperiment")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_import_from_vendor_directories.csv versions.yml
    """
}

workflow BIOC_MOLECULEEXPERIMENT_IMPORT_FROM_VENDOR_DIRECTORIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ repoDir ] ]

    main:
    BIOC_MOLECULEEXPERIMENT_IMPORT_FROM_VENDOR_DIRECTORIES(ch_input)

    emit:
    tables   = BIOC_MOLECULEEXPERIMENT_IMPORT_FROM_VENDOR_DIRECTORIES.out.tables
    plots    = BIOC_MOLECULEEXPERIMENT_IMPORT_FROM_VENDOR_DIRECTORIES.out.plots
    objects  = BIOC_MOLECULEEXPERIMENT_IMPORT_FROM_VENDOR_DIRECTORIES.out.objects
    versions = BIOC_MOLECULEEXPERIMENT_IMPORT_FROM_VENDOR_DIRECTORIES.out.versions
}
