#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TRONCO — export_to_external_tools
// Export inferred progression models to GraphML format for visualization in Cytoscape.
// Input: model.RData
// Container: quay.io/biocontainers/bioconductor-tronco:2.42.0--r45hdfd78af_0
// R packages: TRONCO
// Bioconductor: 3.20 | R: 4.4
// Requires: TRONCO
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Export the inferred progression model to GraphML format

nextflow.enable.dsl = 2

process BIOC_TRONCO_EXPORT_TO_EXTERNAL_TOOLS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("TRONCO")
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
    
    # Load the required TRONCO library
    library(TRONCO)
    
    # Check if the required input file exists
    input_file <- "model.RData"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    # Load the model from the RData file into a temporary environment
    # to identify and extract the TRONCO model object.
    temp_env <- new.env()
    load(input_file, envir = temp_env)
    
    # Retrieve the loaded object and assign it to 'model.boot'
    # to match the documented code exactly.
    loaded_objects <- ls(temp_env)
    if (length(loaded_objects) == 0) {
      stop("No objects found in the loaded RData file.")
    }
    
    # We assume the first object is the TRONCO model
    model.boot <- temp_env[[loaded_objects[1]]]
    
    # Verify that the object is indeed loaded
    if (is.null(model.boot)) {
      stop("Failed to load a valid TRONCO model object from model.RData.")
    }
    
    # --- DOCUMENTED CODE ---
    # Export the inferred progression model to GraphML format
    export.graphml(model.boot, file = 'graph.gml', fontsize = 12, scale.nodes = .6, height.logic = 0.25)
    # --- END DOCUMENTED CODE ---
    
    # Print confirmation of successful execution
    cat("Successfully exported the progression model to 'graph.gml'.\n")

    writeLines(c(
        '"BIOC_TRONCO_EXPORT_TO_EXTERNAL_TOOLS":',
        paste0('    TRONCO: ', as.character(packageVersion('TRONCO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_export_to_external_tools.csv versions.yml
    """
}

workflow BIOC_TRONCO_EXPORT_TO_EXTERNAL_TOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ model.RData ] ]

    main:
    BIOC_TRONCO_EXPORT_TO_EXTERNAL_TOOLS(ch_input)

    emit:
    tables   = BIOC_TRONCO_EXPORT_TO_EXTERNAL_TOOLS.out.tables
    plots    = BIOC_TRONCO_EXPORT_TO_EXTERNAL_TOOLS.out.plots
    objects  = BIOC_TRONCO_EXPORT_TO_EXTERNAL_TOOLS.out.objects
    versions = BIOC_TRONCO_EXPORT_TO_EXTERNAL_TOOLS.out.versions
}
