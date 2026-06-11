#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: escheR — dataframe_visualization
// Visualize multi-dimensional data from a generic R data.frame (e.g., exported from Seurat) using custom x and y coordinates.
// Input: pbmc_meta.rds, pbmc_2pc.rds
// Container: quay.io/biocontainers/bioconductor-escher:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: escheR, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize the plot using make_escheR() with object, .x, and .y arguments. 2. Add a fill layer using add_fill()

nextflow.enable.dsl = 2

process BIOC_ESCHER_DATAFRAME_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    
    # Load required libraries
    library(escheR)
    library(ggplot2)
    
    # Read user input files from the working directory
    pbmc_meta <- readRDS("pbmc_meta.rds")
    pbmc_2pc <- readRDS("pbmc_2pc.rds")
    
    # Call generic function for make_escheR.data.frame exactly as documented
    p <- make_escheR(
      object = pbmc_meta,
      .x = pbmc_2pc[,1],
      .y = pbmc_2pc[,2]) |>
      add_fill(var = "groups")
    
    # Save the resulting plot to a PDF file
    ggplot2::ggsave(
      filename = "escheR_dataframe_plot.pdf",
      plot = p,
      width = 8,
      height = 6
    )

    writeLines(c(
        '"BIOC_ESCHER_DATAFRAME_VISUALIZATION":',
        paste0('    escheR: ', as.character(packageVersion('escheR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dataframe_visualization.csv versions.yml
    """
}

workflow BIOC_ESCHER_DATAFRAME_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc_meta.rds, pbmc_2pc.rds ] ]

    main:
    BIOC_ESCHER_DATAFRAME_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_ESCHER_DATAFRAME_VISUALIZATION.out.tables
    plots    = BIOC_ESCHER_DATAFRAME_VISUALIZATION.out.plots
    objects  = BIOC_ESCHER_DATAFRAME_VISUALIZATION.out.objects
    versions = BIOC_ESCHER_DATAFRAME_VISUALIZATION.out.versions
}
