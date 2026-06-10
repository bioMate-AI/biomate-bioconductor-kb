#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowCyBar — cybar_visualization
// Normalize cytometric cell abundance data and visualize community dynamics using barcodes and boxplots.
// Input: Cell_number_sample.txt
// Container: quay.io/biocontainers/bioconductor-flowcybar:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCyBar
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read cell abundance data
//  * 2. [Core Analysis] Normalize cell numbers using the "mean" or "first" method
//  * 3. [Core Analysis] Convert normalized data to a data frame
//  * 4. [Core Analysis] Generate cytometric barcodes and boxplots
//  * 5. [Visualization & Output] Save normalized values to a text file

nextflow.enable.dsl = 2

process BIOC_FLOWCYBAR_CYBAR_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    
    # Load required library
    library(flowCyBar)
    
    # 1. Read cell abundance data
    Cell_number_sample <- read.table("Cell_number_sample.txt", header = TRUE, sep = "\t")
    
    # 2. Normalize cell numbers using the "mean" or "first" method
    normalize(Cell_number_sample[,-1], digits=2) 
    normalize(Cell_number_sample[,-1], method="first", digits=2) 
    normalized <- normalize(Cell_number_sample[,-1], digits=2) 
    
    # 5. Save normalized values to a text file
    write.table(normalized, file="normalized.txt", row.names=TRUE, quote=FALSE, sep="\t")
    
    # 3. Convert normalized data to a data frame
    Normalized_mean <- normalize(Cell_number_sample[,-1], digits=2)
    Normalized_mean <- data.frame(data.matrix(Normalized_mean))
    
    Normalized_first <- normalize(Cell_number_sample[,-1], method="first", digits=2)
    Normalized_first <- data.frame(data.matrix(Normalized_first))
    
    # Open PDF device to save the generated plots
    pdf("cybar_plots.pdf", width=11, height=8.5)
    
    # 4. Generate cytometric barcodes and boxplots
    cybar_plot(Normalized_mean, Cell_number_sample[,-1]) 
    cybar_plot(Normalized_first, Cell_number_sample[,-1]) 
    cybar_plot(x=Normalized_first, to=3.5)
    cybar_plot(Normalized_mean, Cell_number_sample[,-1], labels="vert", order="sim")
    cybar_plot(Normalized_first, Cell_number_sample[,-1], to=3.5, labels="vert", order="sim")
    cybar_plot(x=Normalized_mean, Rowv=TRUE, grad=15, dendrogram="both", barmain="Normalized cell numbers")
    
    # Update row names to sample names and plot
    rownames(Normalized_mean) <- Cell_number_sample[,1]
    cybar_plot(Normalized_mean, Cell_number_sample[,-1], barmain="Normalized cell numbers", labels="vert", order="sim", boxmain="Cell numbers")
    
    # Close PDF device
    dev.off()

    writeLines(c(
        '"BIOC_FLOWCYBAR_CYBAR_VISUALIZATION":',
        paste0('    flowCyBar: ', as.character(packageVersion('flowCyBar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cybar_visualization.csv versions.yml
    """
}

workflow BIOC_FLOWCYBAR_CYBAR_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Cell_number_sample.txt ] ]

    main:
    BIOC_FLOWCYBAR_CYBAR_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_FLOWCYBAR_CYBAR_VISUALIZATION.out.tables
    plots    = BIOC_FLOWCYBAR_CYBAR_VISUALIZATION.out.plots
    objects  = BIOC_FLOWCYBAR_CYBAR_VISUALIZATION.out.objects
    versions = BIOC_FLOWCYBAR_CYBAR_VISUALIZATION.out.versions
}
