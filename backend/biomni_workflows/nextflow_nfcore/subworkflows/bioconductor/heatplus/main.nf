#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Heatplus — regular_heatmap
// Generate a standard heatmap without annotations, with optional custom clustering, distance metrics, and legend.
// Input: exprs_matrix.csv
// Container: quay.io/biocontainers/bioconductor-heatplus:3.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Heatplus
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load expression data. 2. Define custom distance and clustering functions (optional). 3. Generate heatmap object using regHeatmap. 

nextflow.enable.dsl = 2

process BIOC_HEATPLUS_REGULAR_HEATMAP {
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
    library(Biobase)
    library(Heatplus)
    
    # 1. Load expression data from the user input file
    if (!file.exists("exprs_matrix.csv")) {
      stop("Error: 'exprs_matrix.csv' not found in the working directory.")
    }
    
    # Read the CSV matrix
    raw_matrix <- as.matrix(read.csv("exprs_matrix.csv", row.names = 1))
    mode(raw_matrix) <- "numeric"
    
    # Create raw_matrix2 as a subset of features (e.g., top 50 features or all if fewer than 50)
    num_features <- min(50, nrow(raw_matrix))
    raw_matrix2 <- raw_matrix[1:num_features, , drop = FALSE]
    
    # 2. Generate and plot Heatmap 1 (Default settings)
    pdf("heatmap_reg1.pdf")
    reg1 = regHeatmap(raw_matrix)
    plot(reg1)
    dev.off()
    saveRDS(reg1, "reg1.rds")
    
    # 3. Generate and plot Heatmap 2 (Custom legend, colors, and breaks)
    pdf("heatmap_reg2.pdf")
    reg2 = regHeatmap(raw_matrix2, legend=2, col=heat.colors, breaks=7)
    plot(reg2)
    dev.off()
    saveRDS(reg2, "reg2.rds")
    
    # 4. Define custom distance and clustering functions
    corrdist = function(x) as.dist(1-cor(t(x)))
    hclust.avl = function(x) hclust(x, method="average")
    
    # 5. Generate and plot Heatmap 3 (Using custom clustering and distance)
    pdf("heatmap_reg3.pdf")
    reg3 = regHeatmap(raw_matrix2, legend=2, dendrogram = list(clustfun=hclust.avl, distfun=corrdist))
    plot(reg3)
    dev.off()
    saveRDS(reg3, "reg3.rds")
    
    # 6. Generate and plot Heatmap 4 (Hiding column dendrogram)
    pdf("heatmap_reg4.pdf")
    reg4 = regHeatmap(raw_matrix2, legend=3, dendrogram=list(Col=list(status="hide")))
    plot(reg4)
    dev.off()
    saveRDS(reg4, "reg4.rds")

    writeLines(c(
        '"BIOC_HEATPLUS_REGULAR_HEATMAP":',
        paste0('    Heatplus: ', as.character(packageVersion('Heatplus')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regular_heatmap.csv versions.yml
    """
}

workflow BIOC_HEATPLUS_REGULAR_HEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs_matrix.csv ] ]

    main:
    BIOC_HEATPLUS_REGULAR_HEATMAP(ch_input)

    emit:
    tables   = BIOC_HEATPLUS_REGULAR_HEATMAP.out.tables
    plots    = BIOC_HEATPLUS_REGULAR_HEATMAP.out.plots
    objects  = BIOC_HEATPLUS_REGULAR_HEATMAP.out.objects
    versions = BIOC_HEATPLUS_REGULAR_HEATMAP.out.versions
}
