#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hyperdraw — hypergraph_visualization
// Create, lay out, customize, and render a directed hypergraph visualization from a graphNEL or Hypergraph object.
// Input: testgnel, hg
// Container: quay.io/biocontainers/bioconductor-hyperdraw:1.62.0--r45hef64f4b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: graph, hyperdraw, hypergraph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert the input graph representation to a graphBPH object using graphBPH()
//  * 2. [Core Analysis] Compute the graph layout using graphLayout() to produce an RagraphBPH object
//  * 3. [Visualization & Output] Customize rendering attributes (such as lwd, color, margin, and shape) using edgeDataDefaults(), edgeData(), nodeDataDefaults(), a
//  * 4. [Visualization & Output] Render the final layout using plot()

nextflow.enable.dsl = 2

process BIOC_HYPERDRAW_HYPERGRAPH_VISUALIZATION {
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
    library(hyperdraw)
    library(hypergraph)
    library(graph)
    
    # Read the declared user input files from the working directory
    testgnel <- readRDS("testgnel")
    hg <- readRDS("hg")
    
    # 1. Convert the input graph representation to a graphBPH object using graphBPH()
    testbph <- graphBPH(testgnel, edgeNodePattern="^R")
    hgbph <- graphBPH(hg)
    
    # 2. Compute the graph layout using graphLayout() to produce an RagraphBPH object
    testrabph <- graphLayout(testbph)
    
    # 3. Customize rendering attributes using edgeDataDefaults(), edgeData(), nodeDataDefaults()
    edgeDataDefaults(testrabph, "lwd") <- 1
    edgeDataDefaults(testrabph, "color") <- "black"
    nodeDataDefaults(testrabph, "margin") <- 'unit(3, "mm")'
    nodeDataDefaults(testrabph, "shape") <- "box"
    
    # Safely apply specific edge customizations if the expected nodes exist in the input
    tryCatch({
      edgeData(testrabph, c("A", "R1"), 
                          c("R1", "B"), "lwd") <- c("5", "3")
      edgeData(testrabph, c("A", "R1"), 
                          c("R1", "B"), "color") <- "red"
    }, error = function(e) {
      warning("Could not set specific edge attributes (A, R1, B): ", e\$message)
    })
    
    # 4. Render the final layout using plot() and save to PDF
    pdf("hypergraph_visualization.pdf", width = 7, height = 7)
    plot(testrabph)
    dev.off()
    
    # Save the processed layout objects to RDS files
    saveRDS(testrabph, "testrabph.rds")
    saveRDS(hgbph, "hgbph.rds")

    writeLines(c(
        '"BIOC_HYPERDRAW_HYPERGRAPH_VISUALIZATION":',
        paste0('    hyperdraw: ', as.character(packageVersion('hyperdraw')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hypergraph_visualization.csv versions.yml
    """
}

workflow BIOC_HYPERDRAW_HYPERGRAPH_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testgnel, hg ] ]

    main:
    BIOC_HYPERDRAW_HYPERGRAPH_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_HYPERDRAW_HYPERGRAPH_VISUALIZATION.out.tables
    plots    = BIOC_HYPERDRAW_HYPERGRAPH_VISUALIZATION.out.plots
    objects  = BIOC_HYPERDRAW_HYPERGRAPH_VISUALIZATION.out.objects
    versions = BIOC_HYPERDRAW_HYPERGRAPH_VISUALIZATION.out.versions
}
